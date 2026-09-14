import Foundation

public struct CollectionCounts: Equatable, Sendable {
    public let distinctBottles: Int
    public let totalQuantity: Int
    public let byRegion: [String: Int]
    public let byGrape: [String: Int]
    public let byTag: [String: Int]
}

public enum CollectionSummaryError: Error, Equatable, Sendable {
    case quantityOverflow
}

/// Summarizes physical bottle quantities, not just database row counts.
public func collectionCounts(_ bottles: [Bottle]) throws -> CollectionCounts {
    try CollectionCounts(
        distinctBottles: bottles.count,
        totalQuantity: bottles.reduce(0) { try checkedSum($0, $1.quantity) },
        byRegion: groupedQuantities(bottles, key: \Bottle.region),
        byGrape: groupedQuantities(bottles, key: \Bottle.grape),
        byTag: bottles.reduce(into: [:]) { counts, bottle in
            for tag in Set(bottle.tags) {
                counts[tag] = try checkedSum(counts[tag, default: 0], bottle.quantity)
            }
        }
    )
}

public func drinkByCounts(
    _ bottles: [Bottle],
    reference: Date,
    soonWindowDays: Int = 90,
    calendar: Calendar = .current
) throws -> [DrinkByState: Int] {
    try bottles.reduce(into: [:]) { counts, bottle in
        let state = drinkByState(
            drinkBy: bottle.drinkBy,
            reference: reference,
            soonWindowDays: soonWindowDays,
            calendar: calendar
        )
        counts[state] = try checkedSum(counts[state, default: 0], bottle.quantity)
    }
}

private func groupedQuantities(
    _ bottles: [Bottle],
    key: KeyPath<Bottle, String?>
) throws -> [String: Int] {
    try bottles.reduce(into: [:]) { counts, bottle in
        guard let value = bottle[keyPath: key] else { return }
        counts[value] = try checkedSum(counts[value, default: 0], bottle.quantity)
    }
}

private func checkedSum(_ lhs: Int, _ rhs: Int) throws -> Int {
    let (sum, overflow) = lhs.addingReportingOverflow(rhs)
    guard !overflow else { throw CollectionSummaryError.quantityOverflow }
    return sum
}
