import Foundation

// The Domain layer is intentionally dependency-free: no GRDB, UIKit,
// networking, storage, or other side effects.

/// The wine's position relative to its drink-by window.
public enum DrinkByState: String, Sendable, CaseIterable {
    case noWindow       // drink-by date unknown
    case future         // still aging
    case soon           // within `soonWindowDays` of the drink-by date
    case ready          // on the drink-by date itself
    case passed         // past the drink-by date
}

/// Classifies a bottle's drink-by date against a reference date.
///
/// Pure function — the reference date is injected so tests are deterministic.
/// - Parameters:
///   - drinkBy: optional drink-by date (midnight-aligned calendar date).
///   - reference: the "today" to evaluate against.
///   - soonWindowDays: how many days before the drink-by date count as `soon`.
public func drinkByState(
    drinkBy: Date?,
    reference: Date,
    soonWindowDays: Int = 90,
    calendar: Calendar = .current
) -> DrinkByState {
    guard let drinkBy else { return .noWindow }
    let days = calendar.dateComponents(
        [.day],
        from: calendar.startOfDay(for: reference),
        to: calendar.startOfDay(for: drinkBy)
    ).day ?? 0
    if days < 0 { return .passed }
    if days == 0 { return .ready }
    if soonWindowDays >= 0, days <= soonWindowDays { return .soon }
    return .future
}

/// The display order for timeline sections: most urgent first.
public let drinkByStateDisplayOrder: [DrinkByState] = [
    .passed, .ready, .soon, .future, .noWindow,
]

/// Groups bottles into drink-by timeline sections, most urgent first.
/// Empty groups are omitted so the UI never renders an empty section.
/// Pure and deterministic: the reference date and calendar are injected.
public func drinkByTimelineGroups(
    _ bottles: [Bottle],
    reference: Date,
    soonWindowDays: Int = 90,
    calendar: Calendar = .current
) -> [(state: DrinkByState, bottles: [Bottle])] {
    let grouped = Dictionary(grouping: bottles) { bottle in
        drinkByState(
            drinkBy: bottle.drinkBy,
            reference: reference,
            soonWindowDays: soonWindowDays,
            calendar: calendar
        )
    }
    return drinkByStateDisplayOrder.compactMap { state in
        guard let group = grouped[state], !group.isEmpty else { return nil }
        let sorted = group.sorted { lhs, rhs in
            switch (lhs.drinkBy, rhs.drinkBy) {
            case let (left?, right?):
                if left != right { return left < right }
                return lhs.name < rhs.name
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return lhs.name < rhs.name
            }
        }
        return (state, sorted)
    }
}

/// Human-readable section title for a drink-by state.
public func drinkByStateTitle(_ state: DrinkByState) -> String {
    switch state {
    case .passed: return "Passed"
    case .ready: return "Ready now"
    case .soon: return "Soon"
    case .future: return "Future"
    case .noWindow: return "No drink-by date"
    }
}

/// A reminder the app may schedule for one bottle at one specific time.
/// Pure value type — the app layer converts these into notification requests,
/// so this layer stays free of UserNotifications.
public struct DrinkByReminder: Equatable, Sendable {
    public let bottleID: UUID
    public let bottleName: String
    public let fireDate: Date
    /// Which moment this reminder marks, for user-facing copy.
    public let kind: Kind

    public enum Kind: String, Sendable {
        case upcoming   // `leadDays` before the drink-by date
        case dueOnDay   // the drink-by date itself
    }

    public init(bottleID: UUID, bottleName: String, fireDate: Date, kind: Kind) {
        self.bottleID = bottleID
        self.bottleName = bottleName
        self.fireDate = fireDate
        self.kind = kind
    }
}

/// The hour-of-day reminders fire at (local time), 9 AM by default.
public let drinkByReminderHour = 9

/// Ceiling on the reminder candidates a single scheduling pass may request.
/// The app layer keeps its pending schedule below this bound (the system
/// caps pending requests per app), preferring the soonest fire dates and
/// breaking ties by bottle name for determinism.
public let drinkByReminderBudget = 60

/// Computes upcoming drink-by reminders for bottles with a future drink-by
/// date: one `leadDays` before the date and one on the date itself, each at
/// `drinkByReminderHour` local time. Candidates at or before `reference`
/// (i.e. already in the past) are omitted so re-scheduling after permission
/// grants never fires stale notifications. Deterministic: reference and
/// calendar are injected; output is sorted by fire date, then name.
public func drinkByReminders(
    bottles: [Bottle],
    reference: Date,
    leadDays: Int = 7,
    calendar: Calendar = .current
) -> [DrinkByReminder] {
    var reminders: [DrinkByReminder] = []
    for bottle in bottles {
        guard let drinkBy = bottle.drinkBy else { continue }
        let offsets: [(Int, DrinkByReminder.Kind)] = [
            (max(0, leadDays), .upcoming),
            (0, .dueOnDay),
        ]
        var seenDays = Set<Date>()
        for (offset, kind) in offsets where leadDays > 0 || kind == .dueOnDay {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: drinkBy),
                  let fire = calendar.date(
                      bySettingHour: drinkByReminderHour, minute: 0, second: 0, of: day
                  ) else { continue }
            // Skip same-day duplicates when leadDays == 0.
            guard seenDays.insert(calendar.startOfDay(for: fire)).inserted else { continue }
            guard fire > reference else { continue }
            reminders.append(
                DrinkByReminder(
                    bottleID: bottle.id,
                    bottleName: bottle.name,
                    fireDate: fire,
                    kind: kind
                )
            )
        }
    }
    return reminders.sorted { lhs, rhs in
        if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
        return lhs.bottleName < rhs.bottleName
    }
}

/// Truncates the reminder list to the scheduling `budget`, keeping the
/// soonest fire dates (ties broken by bottle name). The input is already in
/// that order, so this is a plain prefix with a defensive re-sort.
public func cappedReminders(
    _ reminders: [DrinkByReminder],
    budget: Int = drinkByReminderBudget
) -> [DrinkByReminder] {
    guard budget >= 0 else { return [] }
    let ordered = reminders.sorted { lhs, rhs in
        if lhs.fireDate != rhs.fireDate { return lhs.fireDate < rhs.fireDate }
        return lhs.bottleName < rhs.bottleName
    }
    return Array(ordered.prefix(budget))
}

/// Stable identifier for one drink-by timeline section, for `ForEach` in the
/// UI layer. Derived deterministically from the state raw value.
public func drinkByTimelineSectionID(_ state: DrinkByState) -> String {
    "drinkby.section.\(state.rawValue)"
}
