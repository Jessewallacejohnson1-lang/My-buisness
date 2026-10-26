//
//  Reminders.swift
//  Block Party — the app's ONE notification: an opt-in "starts soon" reminder for an
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

    /// Schedule a reminder one hour before the event starts. No-op if the
    /// time can't be parsed or is already in the past.
    static func schedule(eventId: String, title: String, date: String, startTime: String?) async {
        guard let fire = fireDate(date: date, startTime: startTime), fire > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = "Starts in 1 hour."
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
    /// one hour before it starts, in the Town's time (`EventWhen`, the app's one time
    /// rule); an all-day / unparseable time has no meaningful "starts soon" → no reminder.
    private static func fireDate(date ymd: String, startTime: String?) -> Date? {
        guard let when = EventWhen(date: ymd, time: startTime, endAt: nil), when.timed else { return nil }
        return when.start.addingTimeInterval(-60 * 60)
    }
}
