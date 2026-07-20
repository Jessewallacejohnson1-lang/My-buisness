//
//  SupabaseHTTP.swift
//  Block Party — low-level HTTP against GoTrue (/auth) and PostgREST (/rest).
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
    private static let session = URLSession(configuration: .default)

    /// Invoked when a PostgREST call is rejected with 401 (a dead access token that
    /// the local clock still believes is valid). Set once at launch to notify
    /// AuthStore so it can refresh-or-sign-out. Kept as a closure so this low-level
    /// layer stays decoupled from AuthStore. Auth (GoTrue) calls never fire it —
    /// their 401s are handled inline by the sign-in/refresh flows.
    static var onUnauthorized: (@Sendable () -> Void)?

    // MARK: - Auth (GoTrue)

    /// POST/GET against /auth/v1. `path` may include a query string, e.g.
    /// "token?grant_type=password" — split it so the "?" stays a real query
    /// separator (appendingPathComponent would percent-encode it into the path).
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

        let (data, resp) = try await session.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if !(200..<300).contains(code) {
            throw SupabaseError(message: parseAuthError(data) ?? "Auth failed (\(code))", status: code)
        }
        return data
    }

    // MARK: - REST (PostgREST)

    /// Request against /rest/v1. `query` is the raw query string (after "?").
    /// `prefer` sets the Prefer header (e.g. "return=representation", "count=exact").
    @discardableResult
    static func rest(_ path: String, method: String = "GET", query: String? = nil,
                     accessToken: String, body: Data? = nil,
                     prefer: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var comps = URLComponents(url: SupabaseConfig.restURL.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)!
        comps.percentEncodedQuery = query
        var req = URLRequest(url: comps.url!)
        req.httpMethod = method
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { req.setValue(prefer, forHTTPHeaderField: "Prefer") }
        req.httpBody = body

        let (data, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        if !(200..<300).contains(code) {
            if code == 401 { onUnauthorized?() }   // token rejected server-side → refresh or route to Login
            throw SupabaseError(message: parseRestError(data) ?? "Request failed (\(code))", status: code)
        }
        return (data, http!)
    }

    // MARK: - Error parsing

    private static func parseAuthError(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (obj["error_description"] as? String)
            ?? (obj["msg"] as? String)
            ?? (obj["message"] as? String)
            ?? (obj["error"] as? String)
    }

    private static func parseRestError(_ data: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (obj["message"] as? String) ?? (obj["hint"] as? String) ?? (obj["details"] as? String)
    }
}
