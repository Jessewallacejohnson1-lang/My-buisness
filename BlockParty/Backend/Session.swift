//
//  Session.swift
//  Block Party — the auth session (GoTrue) + Keychain persistence.
//

import Foundation
import Security

struct AuthUser: Codable, Equatable {
    let id: String
    let email: String?
    /// GoTrue's `is_anonymous`: the quiet account every install gets before sign-in
    /// exists. Absent from sessions stored before 2026-10-09, which read as real.
    var isAnonymous: Bool? = nil

    enum CodingKeys: String, CodingKey {
        case id, email
        case isAnonymous = "is_anonymous"
    }
}

/// A GoTrue session. `expiresAt` is an absolute epoch time (seconds).
struct Session: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Double
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case user
    }

    /// Treat a token within 60s of expiry as stale so we refresh proactively.
    var isExpired: Bool { Date().timeIntervalSince1970 >= expiresAt - 60 }
}

/// Minimal Keychain blob store, keyed by a string. Tokens belong here, not
/// UserDefaults.
enum Keychain {
    private static let account = "bp.session"

    #if targetEnvironment(simulator)
    /// Simulator builds made without signing (bp-build's `xc.sh`) carry no keychain
    /// entitlement, so every save failed (-34018) and each launch made a new anonymous
    /// account on the live project. There, and only there, the session lives in
    /// UserDefaults instead: it survives relaunches, not an uninstall.
    private static let simulatorKey = "bp.session.simulator"
    #endif

    /// Updates the stored session in place, adding it when there is none. Never
    /// deletes first: an anonymous account lost between a delete and an add can't be
    /// signed back into.
    static func save(_ session: Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(add as CFDictionary, nil)
        }
        #if targetEnvironment(simulator)
        if status == errSecMissingEntitlement {
            UserDefaults.standard.set(data, forKey: simulatorKey)
            return
        }
        #endif
        if status != errSecSuccess { Log.network("Keychain: session not saved (\(status))") }
    }

    static func load() -> Session? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        var data: Data?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess { data = item as? Data }
        #if targetEnvironment(simulator)
        data = data ?? UserDefaults.standard.data(forKey: simulatorKey)
        #endif
        return data.flatMap { try? JSONDecoder().decode(Session.self, from: $0) }
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        #if targetEnvironment(simulator)
        UserDefaults.standard.removeObject(forKey: simulatorKey)
        #endif
    }
}
