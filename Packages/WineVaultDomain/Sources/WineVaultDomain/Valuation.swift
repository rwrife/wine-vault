import Foundation

/// Valuation math over stored quotes. A quote is only ever stored after the
/// user explicitly confirmed a candidate match (or entered a price manually),
/// so every stored quote counts toward totals — but only the newest quote per
/// bottle, and only in one currency.

public enum QuoteFreshness: Equatable, Sendable {
    /// Recent enough to present without qualification.
    case fresh
    /// Getting old — still shown, but the UI should age it visibly.
    case aging
    /// Too old to trust as current value.
    case stale
}

/// Calendar-day age of a quote's quoted date against a reference day.
public func quoteAgeInDays(
    quote: ValuationQuote,
    reference: Date,
    calendar: Calendar = .current
) -> Int {
    max(
        0,
        calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: quote.quoteDate),
            to: calendar.startOfDay(for: reference)
        ).day ?? 0
    )
}

/// Classifies a quote for stale-quote aging. A quote quoted on the
/// reference day is 0 days old.
public func quoteFreshness(
    quote: ValuationQuote,
    reference: Date,
    agingAfterDays: Int = 30,
    staleAfterDays: Int = 90,
    calendar: Calendar = .current
) -> QuoteFreshness {
    let age = quoteAgeInDays(quote: quote, reference: reference, calendar: calendar)
    if age > staleAfterDays { return .stale }
    if age > agingAfterDays { return .aging }
    return .fresh
}

/// Newest quote for a bottle. Later quoteDate wins; ties break on
/// retrievedAt, then on a stable uuid string so results are deterministic.
public func latestQuote(in quotes: [ValuationQuote]) -> ValuationQuote? {
    quotes.max { lhs, rhs in
        if lhs.quoteDate != rhs.quoteDate { return lhs.quoteDate < rhs.quoteDate }
        if lhs.retrievedAt != rhs.retrievedAt { return lhs.retrievedAt < rhs.retrievedAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

public struct CollectionValuation: Equatable, Sendable {
    public let bottleCount: Int
    /// Bottles with at least one stored (user-confirmed or manual) quote.
    public let valuedBottleCount: Int
    public let unvaluedBottleCount: Int
    /// Summed newest-per-bottle quotes, only in `baseCurrency`.
    public let total: Decimal
    public let baseCurrency: String
    /// Valued bottles whose newest quote is in a different currency; they
    /// are excluded from `total` rather than silently converted.
    public let excludedCurrencyMismatchCount: Int
    /// Valued bottles whose newest quote is older than `staleAfterDays`.
    public let staleQuoteCount: Int

    /// e.g. "23 of 40 bottles valued; 17 unvalued excluded".
    public var coverageDescription: String {
        "\(valuedBottleCount) of \(bottleCount) bottles valued; \(unvaluedBottleCount) unvalued excluded"
    }
}

/// Computes the collection total strictly from newest stored quotes in the
/// base currency. Missing, other-currency, and absent bottles are never
/// guessed at — coverage states exactly what was counted.
public func collectionValuation(
    bottles: [Bottle],
    quotesByBottle: [UUID: [ValuationQuote]],
    baseCurrency: String = "USD",
    reference: Date = Date(),
    staleAfterDays: Int = 90,
    calendar: Calendar = .current
) -> CollectionValuation {
    let bottleCount = bottles.count
    var total: Decimal = 0
    var valued = 0
    var currencyMismatch = 0
    var stale = 0
    for bottle in bottles {
        let quotes = quotesByBottle[bottle.id] ?? []
        guard let newest = latestQuote(in: quotes) else { continue }
        valued += 1
        if quoteFreshness(
            quote: newest,
            reference: reference,
            staleAfterDays: staleAfterDays,
            calendar: calendar
        ) == .stale {
            stale += 1
        }
        guard newest.currency == baseCurrency else {
            currencyMismatch += 1
            continue
        }
        total += newest.amount
    }
    return CollectionValuation(
        bottleCount: bottleCount,
        valuedBottleCount: valued,
        unvaluedBottleCount: bottleCount - valued,
        total: total,
        baseCurrency: baseCurrency,
        excludedCurrencyMismatchCount: currencyMismatch,
        staleQuoteCount: stale
    )
}
