import Foundation
@testable import WineVaultDomain
import XCTest

final class ValuationTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_750_000_000)
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func bottle(_ name: String) throws -> Bottle {
        try Bottle(name: name, quantity: 1, storageLocation: "Rack")
    }

    private func quote(
        bottleID: UUID,
        amount: Decimal,
        currency: String = "USD",
        daysBefore reference: Int = 0,
        retrievedOffset: TimeInterval = 0
    ) throws -> ValuationQuote {
        let day = utc.date(byAdding: .day, value: -reference, to: base)!
        return try ValuationQuote(
            bottleID: bottleID,
            quoteDate: day,
            amount: amount,
            currency: currency,
            source: "Test Source",
            retrievedAt: day.addingTimeInterval(retrievedOffset),
            query: "test query"
        )
    }

    func testQuoteAgeAndFreshnessBoundaries() throws {
        let bottle = try bottle("Boundary")
        let fresh = try quote(bottleID: bottle.id, amount: 10, daysBefore: 0)
        let aging = try quote(bottleID: bottle.id, amount: 10, daysBefore: 31)
        let stale = try quote(bottleID: bottle.id, amount: 10, daysBefore: 91)

        XCTAssertEqual(quoteAgeInDays(quote: fresh, reference: base, calendar: utc), 0)
        XCTAssertEqual(quoteFreshness(quote: fresh, reference: base, calendar: utc), .fresh)
        XCTAssertEqual(
            quoteFreshness(
                quote: try quote(bottleID: bottle.id, amount: 10, daysBefore: 30),
                reference: base,
                calendar: utc
            ),
            .fresh
        )
        XCTAssertEqual(quoteFreshness(quote: aging, reference: base, calendar: utc), .aging)
        XCTAssertEqual(quoteFreshness(quote: stale, reference: base, calendar: utc), .stale)
    }

    func testLatestQuotePicksNewestThenRetrievedThenID() throws {
        let bottle = try bottle("Latest")
        let older = try quote(bottleID: bottle.id, amount: 10, daysBefore: 10)
        let newer = try quote(bottleID: bottle.id, amount: 20, daysBefore: 1)
        XCTAssertEqual(latestQuote(in: [older, newer])?.amount, 20)

        // Same quoteDate: later retrievedAt wins.
        let sameDayEarly = try quote(
            bottleID: bottle.id, amount: 11, daysBefore: 5, retrievedOffset: 0
        )
        let sameDayLate = try quote(
            bottleID: bottle.id, amount: 12, daysBefore: 5, retrievedOffset: 60
        )
        XCTAssertEqual(latestQuote(in: [sameDayEarly, sameDayLate])?.amount, 12)
        XCTAssertNil(latestQuote(in: []))
    }

    func testCollectionValuationUsesNewestPerBottleAndStatesCoverage() throws {
        let alpha = try bottle("A")
        let beta = try bottle("B")
        let unvalued = try bottle("C")
        let quotesByBottle: [UUID: [ValuationQuote]] = [
            alpha.id: [
                try quote(bottleID: alpha.id, amount: 10, daysBefore: 100),
                try quote(bottleID: alpha.id, amount: 30, daysBefore: 1),
            ],
            beta.id: [try quote(bottleID: beta.id, amount: 5, daysBefore: 0)],
        ]

        let valuation = collectionValuation(
            bottles: [alpha, beta, unvalued],
            quotesByBottle: quotesByBottle,
            reference: base,
            calendar: utc
        )
        XCTAssertEqual(valuation.bottleCount, 3)
        XCTAssertEqual(valuation.valuedBottleCount, 2)
        XCTAssertEqual(valuation.unvaluedBottleCount, 1)
        XCTAssertEqual(valuation.total, 35)
        XCTAssertEqual(valuation.baseCurrency, "USD")
        XCTAssertEqual(
            valuation.coverageDescription,
            "2 of 3 bottles valued; 1 unvalued excluded"
        )
        // The 1-day-old quote for A and 0-day quote for B are fresh; the
        // 100-day-old quote is superseded and never counted as stale.
        XCTAssertEqual(valuation.staleQuoteCount, 0)
    }

    func testCurrencyMismatchExcludedFromTotalButCountedAsValued() throws {
        let alpha = try bottle("A")
        let beta = try bottle("B")
        let valuation = collectionValuation(
            bottles: [alpha, beta],
            quotesByBottle: [
                alpha.id: [try quote(bottleID: alpha.id, amount: 40, currency: "EUR", daysBefore: 1)],
                beta.id: [try quote(bottleID: beta.id, amount: 12, daysBefore: 1)],
            ],
            reference: base,
            calendar: utc
        )
        XCTAssertEqual(valuation.total, 12)
        XCTAssertEqual(valuation.excludedCurrencyMismatchCount, 1)
        XCTAssertEqual(valuation.valuedBottleCount, 2)
    }

    func testStaleQuotesCountedInTotalButReported() throws {
        let alpha = try bottle("A")
        let valuation = collectionValuation(
            bottles: [alpha],
            quotesByBottle: [alpha.id: [try quote(bottleID: alpha.id, amount: 99, daysBefore: 200)]],
            reference: base,
            calendar: utc
        )
        XCTAssertEqual(valuation.total, 99)
        XCTAssertEqual(valuation.staleQuoteCount, 1)
    }

    func testEmptyCollectionValuationIsZeroWithFullCoverage() throws {
        let valuation = collectionValuation(
            bottles: [],
            quotesByBottle: [:],
            reference: base,
            calendar: utc
        )
        XCTAssertEqual(valuation.total, 0)
        XCTAssertEqual(valuation.bottleCount, 0)
        XCTAssertEqual(valuation.coverageDescription, "0 of 0 bottles valued; 0 unvalued excluded")
    }
}
