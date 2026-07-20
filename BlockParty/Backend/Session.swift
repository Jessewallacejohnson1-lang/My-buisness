//
//  Session.swift
//  Block Party — the auth session (GoTrue) + Keychain persistence.
//

import Foundation
import Security

struct AuthUser: Codable, Equatable {
    let id: String
    let email: String?
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
    private static let account = "hygge.session"

    static func save(_ session: Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> Session? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
