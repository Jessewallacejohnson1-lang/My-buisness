//
//  SupabaseHTTP.swift
//  Block Party — low-level HTTP against GoTrue (/auth), PostgREST (/rest), Storage and
//  edge functions.
//
//  Hand-rolled over URLSession: no SDK, no SwiftPM dependency, full control of
//  the exact queries — matching the @hygge/core layer 1:1.
//

import Foundation

struct SupabaseError: LocalizedError {
    let message: String
    let status: Int?
    var errorDescription: String? { message }
}

enum SupabaseHTTP {
    // MARK: - Auth (GoTrue)

    /// POST/GET against /auth/v1. `path` may include a query string, e.g.
    /// "token?grant_type=password" — split it so the "?" stays a real query
    /// separator (appendingPathComponent would percent-encode it into the path).
    /// Its 401s never reach `TokenProviding.handleUnauthorized`: the sign-in and
    /// refresh flows handle them inline.
    static func auth(_ path: String, method: String = "POST",
                     body: [String: Any]? = nil, bearer: String? = nil) async throws -> Data {
        let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        var comps = URLComponents(url: SupabaseConfig.authURL.appendingPathComponent(String(parts[0])),
                                  resolvingAgainstBaseURL: false)!
        if parts.count > 1 { comps.percentEncodedQuery = String(parts[1]) }
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(bearer ?? SupabaseConfig.anonKey)", forHTTPHeaderField: "Authorization")
        if let body { req.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let (data, resp) = try await Supabase.Send.live.run(req)
        let code = resp.statusCode
        if !(200..<300).contains(code) {
            throw SupabaseError(message: parseAuthError(data) ?? "The account request didn't go through. Check your connection and try again. (Code \(code))", status: code)
        }
        return data
    }

    // MARK: - What an error means

    /// True when the server never really answered, so the caller keeps what it has and tries
    /// again: the phone is offline or timed out, the token had expired (the server's 401
    /// refreshes it, see `TokenProviding.handleUnauthorized`; the app's own no-session 401 is
    /// let go when the account changes), or the server is busy (408, 429) or down (5xx).
    /// Anything else is the server's no.
    nonisolated static func noAnswer(_ error: Error) -> Bool {
        if error is URLError { return true }
        guard let status = (error as? SupabaseError)?.status else { return false }
        return status == 0 || status == 401 || status == 408 || status == 429 || status >= 500
    }

    // MARK: - Error parsing

    private static func parseAuthError(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (obj["error_description"] as? String)
            ?? (obj["msg"] as? String)
            ?? (obj["message"] as? String)
            ?? (obj["error"] as? String)
    }

    /// PostgREST's, Storage's and an edge function's own words for a refusal.
    static func parseRestError(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (obj["message"] as? String) ?? (obj["hint"] as? String) ?? (obj["details"] as? String)
    }
}

/// The one client for what the app asks Supabase's database, Storage and edge functions
/// (BP app codebase-health 16). It holds what every call shares: the keys and the token, the
/// signed-in check, the decoder, the encoding of every query value, and the 401 hook. It sends
/// through `send`, the network unless a test hands it a fake.
struct Supabase {
    let auth: any TokenProviding
    var send: Send = .live

    /// Where a request goes and what came back.
    struct Send {
        let run: (URLRequest) async throws -> (Data, HTTPURLResponse)

        static let live = Send { request in
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw SupabaseError(message: "The server couldn't complete this request. Check your connection and try again.", status: 0)
            }
            return (data, http)
        }

        /// No signal: every call fails as offline and nothing leaves the phone (`-town-offline`).
        static let offline = Send { _ in throw URLError(.notConnectedToInternet) }

        private static let session = URLSession(configuration: .default)
    }

    /// A query's keys and values, in order and unencoded: `[("id", "eq.\(id)")]`.
    typealias Query = [(String, String)]

    /// The signed-in account's id. A call that writes as someone throws the app's own 401
    /// without one, before anything is sent.
    var userID: String {
        get throws {
            guard let id = auth.userId else {
                throw SupabaseError(message: "Your session ended. Sign in and try again.", status: 401)
            }
            return id
        }
    }

    /// A call to PostgREST (`/rest/v1/<path>`), answering its bytes. `body` goes as JSON.
    /// `anon` is for a read RLS opens to everyone: sign-in is switched off, so most neighbours
    /// have no session, and they read with the app's public key instead of failing into an
    /// empty screen. Approved events are readable by the anon role; RSVPs are not, so a
    /// signed-out read sees none.
    @discardableResult
    func rest(_ path: String, method: String = "GET", _ query: Query = [], body: Any? = nil,
              prefer: String? = nil, anon: Bool = false) async throws -> Data {
        var comps = URLComponents(url: SupabaseConfig.restURL.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        comps.percentEncodedQuery = Self.encode(query)
        var request = URLRequest(url: comps.url!)
        request.httpMethod = method
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        return try await perform(request, type: "application/json", anon: anon)
    }

    /// A database function (`rpc/<function>`) given `args`.
    @discardableResult
    func rpc(_ function: String, _ args: [String: Any] = [:], anon: Bool = false) async throws -> Data {
        try await rest("rpc/\(function)", method: "POST", body: args, anon: anon)
    }

    /// Puts `data` in a public Storage bucket at `path` and answers where it can be read.
    /// A refusal or no answer throws.
    func upload(bucket: String, path: String, _ data: Data, type: String) async throws -> URL {
        var request = URLRequest(url: SupabaseConfig.storageURL.appendingPathComponent("object/\(bucket)/\(path)"))
        request.httpMethod = "POST"
        request.httpBody = data
        try await perform(request, type: type)
        return SupabaseConfig.url.appendingPathComponent("storage/v1/object/public/\(bucket)/\(path)")
    }

    /// An edge function (`functions/v1/<function>`) given `body`.
    func invoke(_ function: String, _ body: [String: Any]) async throws {
        var request = URLRequest(url: SupabaseConfig.url.appendingPathComponent("functions/v1/\(function)"))
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        try await perform(request, type: "application/json")
    }

    /// Every call's one way out. A 401 (a token the server refused though the phone still
    /// thinks it good) tells `auth`, which refreshes it or signs out, without holding up the
    /// caller.
    @discardableResult
    private func perform(_ request: URLRequest, type: String, anon: Bool = false) async throws -> Data {
        let token = anon ? ((try? await auth.validAccessToken()) ?? SupabaseConfig.anonKey)
                         : try await auth.validAccessToken()
        var request = request
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(type, forHTTPHeaderField: "Content-Type")
        let (data, response) = try await send.run(request)
        let code = response.statusCode
        guard (200..<300).contains(code) else {
            if code == 401 { Task { await auth.handleUnauthorized() } }
            throw SupabaseError(message: SupabaseHTTP.parseRestError(data) ?? "The server couldn't complete this request. Check your connection and try again. (Code \(code))", status: code)
        }
        return data
    }

    /// Every query key and value, percent-encoded here and nowhere else: `&`, `=` and `+` too,
    /// so a value can never end its pair or turn into a space. PostgREST's own marks
    /// (`( ) , . * :`) stay as written. nil for no query, so the URL has no "?".
    nonisolated static func encode(_ query: Query) -> String? {
        guard !query.isEmpty else { return nil }
        func escape(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: queryAllowed) ?? s }
        return query.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&")
    }

    private nonisolated static let queryAllowed: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return allowed
    }()

    /// A PostgREST answer as `T`, snake_case keys read as camelCase.
    nonisolated static func decode<T: Decodable>(_ data: Data, as type: T.Type = T.self) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(type, from: data)
    }
}
