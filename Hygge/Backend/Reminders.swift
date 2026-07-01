//
//  Reminders.swift
//  Hygge — the app's ONE notification: an opt-in "starts soon" reminder for an
//  event you chose. No other local/push notifications exist anywhere (on-brand).
//

import Foundation
import UserNotifications

enum Reminders {
    /// Ask once; returns whether we may post notifications.
    static func requestAuth() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .denied: return false
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        @unknown default: return false
        }
    }

    /// Schedule a reminder 45 minutes before the event starts. No-op if the
    /// time can't be parsed or is already in the past.
    static func schedule(eventId: String, title: String, date: String, startTime: String?) async {
        guard let fire = fireDate(date: date, startTime: startTime), fire > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Starts soon in St. Joe."
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(identifier: id(eventId), content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(req)
    }

    static func cancel(eventId: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id(eventId)])
    }

    static func isScheduled(eventId: String) async -> Bool {
        let reqs = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return reqs.contains { $0.identifier == id(eventId) }
    }

    private static func id(_ eventId: String) -> String { "event-\(eventId)" }

    /// "YYYY-MM-DD" + a display time ("5 PM", "5:30 PM", "10 AM") → local Date 45m before start.
    private static func fireDate(date ymd: String, startTime: String?) -> Date? {
        let d = ymd.split(separator: "-").compactMap { Int($0) }
        guard d.count == 3 else { return nil }
        var comps = DateComponents()
        comps.year = d[0]; comps.month = d[1]; comps.day = d[2]
        comps.hour = 12; comps.minute = 0   // default noon when time is unparseable
        if let t = startTime, let (h, m) = parseTime(t) { comps.hour = h; comps.minute = m }
        guard let start = Calendar.current.date(from: comps) else { return nil }
        return start.addingTimeInterval(-45 * 60)
    }

    /// Parse a display time like "5 PM" / "5:30 pm" / "10 AM" into (hour24, minute).
    private static func parseTime(_ s: String) -> (Int, Int)? {
        let lower = s.lowercased()
        let isPM = lower.contains("pm")
        let isAM = lower.contains("am")
        let digits = lower
            .replacingOccurrences(of: "am", with: "")
            .replacingOccurrences(of: "pm", with: "")
            .trimmingCharacters(in: .whitespaces)
        let hm = digits.split(separator: ":")
        guard let hRaw = hm.first.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) else { return nil }
        let m = hm.count > 1 ? (Int(hm[1].trimmingCharacters(in: .whitespaces)) ?? 0) : 0
        var h = hRaw
        if isPM && h < 12 { h += 12 }
        if isAM && h == 12 { h = 0 }
        guard (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }
}
