import Foundation

// The Domain layer is intentionally dependency-free: no GRDB, UIKit,
// networking, storage, or other side effects.

/// A dated collection value observation for the dashboard's value-over-time
/// chart. Points are change observations derived from the user's own stored
/// quotes — never a live or implied price.
public struct ValueHistoryPoint: Equatable, Sendable, Identifiable {
    public let date: Date
    public let total: Decimal
    /// Number of bottles counted into `total` on that day.
    public let valuedBottleCount: Int

    public init(date: Date, total: Decimal, valuedBottleCount: Int) {
        self.date = date
        self.total = total
        self.valuedBottleCount = valuedBottleCount
    }

    /// Stable identity for `Chart`/`ForEach`: history emits at most one
    /// point per calendar day, so the date alone is unique.
    public var id: Date { date }
}

extension ValueHistoryPoint: Comparable {
    public static func < (lhs: ValueHistoryPoint, rhs: ValueHistoryPoint) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        return lhs.total < rhs.total
    }
}

/// Builds the value history from stored quotes only.
///
/// Semantics (change points, not fabricated days): starting at the first
/// stored quote, evaluate "collection total as of day D" using exactly the
/// `collectionValuation` rule — newest stored quote per bottle dated
/// on-or-before D wins; a bottle whose newest quote at D is in a foreign
/// currency is excluded rather than converted. Emit a point whenever the
/// observation changes (a quote lands, a refresh changes the total, or the
/// total drops to zero because the newest quote switched currency). Days
/// with no stored quote and no change produce no point.
public func valueHistory(
    bottles: [Bottle],
    quotesByBottle: [UUID: [ValuationQuote]],
    baseCurrency: String = "USD",
    calendar: Calendar = .current
) -> [ValueHistoryPoint] {
    let candidateDays: [Date] = bottles
        .flatMap { bottle in quotesByBottle[bottle.id] ?? [] }
        .map { calendar.startOfDay(for: $0.quoteDate) }
        .sorted()
        .reduce(into: []) { days, day in
            if days.last != day { days.append(day) }
        }

    var points: [ValueHistoryPoint] = []
    for day in candidateDays {
        var total: Decimal = 0
        var valued = 0
        for bottle in bottles {
            // Same newest-per-bottle rule as collectionValuation: newest
            // quote dated on-or-before the day wins, and a newest quote in
            // a foreign currency excludes the bottle (never guessed at).
            let asOf = (quotesByBottle[bottle.id] ?? []).filter {
                calendar.startOfDay(for: $0.quoteDate) <= day
            }
            guard let newest = latestQuote(in: asOf),
                  newest.currency == baseCurrency else { continue }
            total += newest.amount
            valued += 1
        }
        // Skip leading empties: before the first observation exists there is
        // nothing truthful to plot. Once observing, a drop (including to
        // zero) is a real change and must be shown.
        if valued == 0, points.isEmpty { continue }
        let changed: Bool
        if let last = points.last {
            changed = last.total != total || last.valuedBottleCount != valued
        } else {
            changed = true
        }
        if changed {
            points.append(ValueHistoryPoint(date: day, total: total, valuedBottleCount: valued))
        }
    }
    return points
}
