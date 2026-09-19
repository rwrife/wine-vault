import Foundation
@testable import WineVaultDomain
import XCTest

final class PriceProvidingTests: XCTestCase {
    private func bottle(
        name: String = "Estate Reserve",
        producer: String? = "Maison Test",
        vintage: Int? = 2019,
        region: String? = "Bordeaux",
        grape: String? = "Merlot"
    ) throws -> Bottle {
        try Bottle(
            name: name,
            producer: producer,
            vintage: vintage,
            region: region,
            grape: grape,
            quantity: 1,
            storageLocation: "Rack"
        )
    }

    func testPriceQueryIncludesIdentityPartsInOrder() throws {
        let query = try priceQuery(for: bottle())
        XCTAssertEqual(query.text, "Estate Reserve Maison Test 2019 Bordeaux Merlot")
    }

    func testPriceQueryOmitsMissingOptionalFields() throws {
        let query = try priceQuery(
            for: bottle(producer: nil, vintage: nil, region: nil, grape: nil)
        )
        XCTAssertEqual(query.text, "Estate Reserve")
    }

    func testPriceQueryRejectsBlankNameBottle() {
        XCTAssertThrowsError(
            try priceQuery(
                for: bottle(name: "   ", producer: nil, vintage: nil, region: nil, grape: nil)
            )
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .emptyPriceQuery)
        }
    }

    func testPriceQueryTrimsWhitespace() throws {
        let query = try priceQuery(
            for: bottle(producer: "  Maison Test  ", region: "  ", grape: " ")
        )
        XCTAssertEqual(query.text, "Estate Reserve Maison Test 2019")
    }

    func testFixtureProviderReturnsDeterministicCandidates() async throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let provider = FixturePriceProvider(now: { fixedDate })
        let candidates = try await provider.priceCandidates(
            for: PriceQuery(text: "Estate Reserve")
        )
        XCTAssertEqual(candidates.count, 1)
        XCTAssertEqual(candidates[0].amount, 24.00)
        XCTAssertEqual(candidates[0].currency, "USD")
        XCTAssertEqual(candidates[0].source, "CellarTrace Fixture")
        XCTAssertEqual(candidates[0].quoteDate, fixedDate)
        XCTAssertTrue(candidates[0].matchLabel.contains("Estate Reserve"))
    }

    func testFixtureProviderNoResultsBehavior() async {
        let provider = FixturePriceProvider(behavior: .noResults)
        do {
            _ = try await provider.priceCandidates(for: PriceQuery(text: "Anything"))
            XCTFail("Expected noResults")
        } catch let error as PriceProviderError {
            XCTAssertEqual(error, .noResults)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFixtureProviderTimeoutBehavior() async {
        let provider = FixturePriceProvider(behavior: .timeout)
        do {
            _ = try await provider.priceCandidates(for: PriceQuery(text: "Anything"))
            XCTFail("Expected timedOut")
        } catch let error as PriceProviderError {
            XCTAssertEqual(error, .timedOut)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFixtureProviderDisabledBehavior() async {
        let provider = FixturePriceProvider(behavior: .disabled)
        do {
            _ = try await provider.priceCandidates(for: PriceQuery(text: "Anything"))
            XCTFail("Expected disabled")
        } catch let error as PriceProviderError {
            XCTAssertEqual(error, .disabled)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testFixtureProviderAmbiguousCannedListIsPreserved() async throws {
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        let canned = [
            try PriceCandidate(
                amount: 18, currency: "USD", source: "Shop A",
                quoteDate: date, matchLabel: "Estate Reserve 2019 750ml"
            ),
            try PriceCandidate(
                amount: 420, currency: "USD", source: "Shop B",
                quoteDate: date, matchLabel: "Estate Reserve 2019 Magnum"
            ),
        ]
        let provider = FixturePriceProvider(canned: canned)
        let returned = try await provider.priceCandidates(
            for: PriceQuery(text: "Estate Reserve")
        )
        XCTAssertEqual(returned, canned)
    }

    func testPriceCandidateRejectsInvalidProvenance() {
        XCTAssertThrowsError(
            try PriceCandidate(
                amount: -1, currency: "USD", source: "Shop",
                quoteDate: Date(), matchLabel: "match"
            )
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .invalidQuoteAmount)
        }
        XCTAssertThrowsError(
            try PriceCandidate(
                amount: 10, currency: "  ", source: "Shop",
                quoteDate: Date(), matchLabel: "match"
            )
        ) { error in
            XCTAssertEqual(error as? DomainValidationError, .missingQuoteProvenance)
        }
    }
}
