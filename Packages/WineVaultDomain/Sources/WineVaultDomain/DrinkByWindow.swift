import Foundation

/// Pure-domain seeds for the Wine Vault app.
///
/// The Domain layer is intentionally dependency-free: no GRDB, no UIKit,
/// no networking. Full value types (`Bottle`, `ValuationQuote`) land with
/// issue #2; this file establishes the layer boundary plus one tested pure
/// function so the CI warnings-as-errors baseline has real code to gate.

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
    soonWindowDays: Int = 90
) -> DrinkByState {
    guard let drinkBy else { return .noWindow }
    let calendar = Calendar.current
    let days = calendar.dateComponents(
        [.day],
        from: calendar.startOfDay(for: reference),
        to: calendar.startOfDay(for: drinkBy)
    ).day ?? 0
    if days < 0 { return .passed }
    if days == 0 { return .ready }
    if days <= soonWindowDays { return .soon }
    return .future
}
