import Foundation
import UserNotifications
import WineVaultDomain

/// Seam over UNUserNotificationCenter so tests and UI-test launches never
/// touch the real notification center. All methods are best-effort: the app
/// must stay usable when notifications are denied or unavailable.
protocol ReminderScheduling: Sendable {
    var authorizationStatus: UNAuthorizationStatus { get async }
    /// Requests permission. Returns `true` only when authorization is
    /// granted (or provisionally granted). Never raises — denials degrade.
    func requestAuthorization() async -> Bool
    func schedule(reminders: [DrinkByReminder]) async
    func cancelAll() async
}

extension UNAuthorizationStatus {
    var allowsReminders: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }
}

/// Real implementation backed by the system notification center.
///
/// Graceful degradation contract: every failure path (denied authorization,
/// per-request add failures) leaves the app fully usable — the worst case is
/// that one reminder is absent, and the drink-by timeline always shows the
/// date information in-app regardless.
struct UNReminderScheduler: ReminderScheduling {
    private static let scheduledKey = "WineVaultPendingReminderIdentifiers"

    var authorizationStatus: UNAuthorizationStatus {
        get async {
            await withCheckedContinuation { continuation in
                UNUserNotificationCenter.current().getNotificationSettings { settings in
                    continuation.resume(returning: settings.authorizationStatus)
                }
            }
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func schedule(reminders: [DrinkByReminder]) async {
        guard await authorizationStatus.allowsReminders else { return }
        // Replace our previous schedule wholesale so edits/deletes are
        // reflected without leaking stale notifications. The system API has
        // no "list pending", so we track the identifiers we own.
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: Array(ownIdentifiers()))
        var scheduled: [String] = []
        for reminder in cappedReminders(reminders) {
            let content = UNMutableNotificationContent()
            switch reminder.kind {
            case .upcoming:
                content.title = "\(reminder.bottleName) is approaching its drink-by date"
                content.body = "Plan to enjoy it soon — Wine Vault remembers so you don't have to."
            case .dueOnDay:
                content.title = "\(reminder.bottleName) is at its drink-by date"
                content.body = "Time to enjoy it, or check whether it still deserves more cellaring."
            }
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: reminder.fireDate
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            let identifier =
                "winevault.drinkby.\(reminder.bottleID.uuidString).\(reminder.kind.rawValue)"
            let request = UNNotificationRequest(
                identifier: identifier, content: content, trigger: trigger
            )
            // A failed add means that one reminder is absent — the
            // documented degradation, never an error surfaced to the user.
            do {
                try await center.add(request)
                scheduled.append(identifier)
            } catch {
                continue
            }
        }
        UserDefaults.standard.set(scheduled, forKey: Self.scheduledKey)
    }

    func cancelAll() async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: Array(ownIdentifiers()))
        UserDefaults.standard.set([], forKey: Self.scheduledKey)
    }

    private func ownIdentifiers() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: Self.scheduledKey) ?? [])
    }
}

/// No-op scheduler used when the host (tests, UI-test launches, previews)
/// must not touch real notifications.
struct InertReminderScheduler: ReminderScheduling {
    var authorizationStatus: UNAuthorizationStatus { get async { .denied } }
    func requestAuthorization() async -> Bool { false }
    func schedule(reminders: [DrinkByReminder]) async {}
    func cancelAll() async {}
}
