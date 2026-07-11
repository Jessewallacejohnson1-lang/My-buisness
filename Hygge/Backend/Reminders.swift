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

    /// "YYYY-MM-DD" + a free-text display time ("5 PM", "noon", "midnight", nil) →
    /// local Date 45m before start. Shares the app's one time parser
    /// (DateHelpers.minutesOf) so "midnight"/"noon" agree with the rest of the app;
    /// an all-day / unparseable time has no meaningful "starts soon" → no reminder.
    private static func fireDate(date ymd: String, startTime: String?) -> Date? {
        let d = ymd.split(separator: "-").compactMap { Int($0) }
        guard d.count == 3 else { return nil }
        let minutes = DateHelpers.minutesOf(startTime)   // 24*60 ⇒ all-day / unparseable
        guard minutes < 24 * 60 else { return nil }
        var comps = DateComponents()
        comps.year = d[0]; comps.month = d[1]; comps.day = d[2]
        comps.hour = minutes / 60
        comps.minute = minutes % 60
        guard let start = Calendar.current.date(from: comps) else { return nil }
        return start.addingTimeInterval(-45 * 60)
    }
}
