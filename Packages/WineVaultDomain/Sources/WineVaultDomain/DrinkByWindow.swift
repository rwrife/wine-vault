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
