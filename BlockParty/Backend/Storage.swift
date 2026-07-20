//
//  Storage.swift
//  Block Party — image upload to the public `event-images` Supabase Storage bucket.
//
//  Ported from apps/mobile/src/lib/uploadImage.ts: upload bytes to
//  events/{timestamp}.jpg, return the public URL, nil on any failure so the
//  caller posts without an image rather than breaking.
//

import Foundation

struct Storage {
    let auth: AuthStore

    func uploadEventImage(_ data: Data, contentType: String = "image/jpeg") async -> String? {
        guard let token = try? await auth.validAccessToken() else { return nil }
        let ext = (contentType.split(separator: "/").last.map(String.init) ?? "jpg")
            .replacingOccurrences(of: "jpeg", with: "jpg")
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let path = "events/\(ts).\(ext)"

        var req = URLRequest(url: SupabaseConfig.storageURL.appendingPathComponent("object/event-images/\(path)"))
        req.httpMethod = "POST"
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")

        guard let (_, resp) = try? await URLSession.shared.upload(for: req, from: data),
              let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else {
            return nil
        }
        return SupabaseConfig.url
            .appendingPathComponent("storage/v1/object/public/event-images/\(path)")
            .absoluteString
    }

    /// Upload an avatar to the public `avatars` bucket at `{userId}/avatar-{ts}.jpg`
    /// (folder-scoped RLS). Returns the public URL, nil on any failure so the
    /// caller finishes onboarding without an avatar rather than breaking.
    func uploadAvatar(_ data: Data, userId: String, contentType: String = "image/jpeg") async -> String? {
        guard let token = try? await auth.validAccessToken() else { return nil }
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        let path = "\(userId)/avatar-\(ts).jpg"

        var req = URLRequest(url: SupabaseConfig.storageURL.appendingPathComponent("object/avatars/\(path)"))
        req.httpMethod = "POST"
        req.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")

        guard let (_, resp) = try? await URLSession.shared.upload(for: req, from: data),
              let code = (resp as? HTTPURLResponse)?.statusCode, (200..<300).contains(code) else {
            return nil
        }
        return SupabaseConfig.url
            .appendingPathComponent("storage/v1/object/public/avatars/\(path)")
            .absoluteString
    }
}
