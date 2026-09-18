import Foundation
@testable import WineVault
import WineVaultData
import WineVaultDomain
import XCTest

/// Valuation-flow coverage for issue #4: every lookup is user-initiated,
/// candidates are never auto-applied, manual entry always works offline, and
/// the collection total only counts confirmed quotes.
@MainActor
final class ValuationFlowTests: XCTestCase {
    private func makeStore(
        provider: (any PriceProviding)? = FixturePriceProvider()
    ) async throws -> (InventoryStore, SQLiteBottleRepository) {
        let repository = try SQLiteBottleRepository(inMemory: true)
        let store = InventoryStore(
            dependencies: InventoryDependencies(repository: repository, priceProvider: provider)
        )
        await store.load()
        return (store, repository)
    }

    private func addBottle(
        to store: InventoryStore,
        name: String,
        producer: String? = "Maison"
    ) async throws -> Bottle {
        let form = BottleForm(
            name: name,
            producer: producer ?? "",
            quantity: 1,
            storageLocation: "Rack"
        )
        let saved = await store.save(form)
        XCTAssertTrue(saved)
        return try XCTUnwrap(store.bottles.first { $0.name == name })
    }

    private func storedQuotes(
        _ repository: SQLiteBottleRepository,
        bottleID: UUID
    ) async throws -> [ValuationQuote] {
        try await repository.quotes(bottleID: bottleID)
    }

    func testLookupProducesCandidatesAndNothingIsStoredUntilConfirmed() async throws {
        let (store, repository) = try await makeStore()
        let bottle = try await addBottle(to: store, name: "Estate Reserve")

        await store.requestPriceLookup(for: bottle)

        XCTAssertEqual(store.lookupCandidates.count, 1)
        let candidate = try XCTUnwrap(store.lookupCandidates.first)
        XCTAssertEqual(candidate.source, "CellarTrace Fixture")
        // Nothing was stored — lookup alone never writes a quote.
        let storedAfter = try await storedQuotes(repository, bottleID: bottle.id)
        XCTAssertTrue(storedAfter.isEmpty)
        XCTAssertTrue(store.quotesByBottle.isEmpty)
    }

    func testConfirmStoresDatedSourcedQuoteWithExactQuery() async throws {
        let (store, repository) = try await makeStore()
        let bottle = try await addBottle(to: store, name: "Estate Reserve")
        await store.requestPriceLookup(for: bottle)
        let candidate = try XCTUnwrap(store.lookupCandidates.first)

        let confirmed = await store.confirm(candidate, for: bottle)

        XCTAssertTrue(confirmed)
        let quotes = try await storedQuotes(repository, bottleID: bottle.id)
        XCTAssertEqual(quotes.count, 1)
        let quote = try XCTUnwrap(quotes.first)
        XCTAssertEqual(quote.amount, candidate.amount)
        XCTAssertEqual(quote.currency, "USD")
        XCTAssertEqual(quote.source, "CellarTrace Fixture")
        XCTAssertEqual(quote.quoteDate, candidate.quoteDate)
        // Exact query text is preserved verbatim for provenance.
        XCTAssertEqual(quote.query, "Estate Reserve Maison")
        XCTAssertEqual(store.latestQuote(for: bottle.id)?.id, quote.id)
        XCTAssertTrue(store.lookupCandidates.isEmpty)
    }

    func testAmbiguousCandidatesRequireExplicitChoice() async throws {
        let date = Date(timeIntervalSince1970: 1_600_000_000)
        let provider = FixturePriceProvider(canned: [
            try PriceCandidate(
                amount: 18, currency: "USD", source: "Shop A",
                quoteDate: date, matchLabel: "Estate Reserve 750ml"
            ),
            try PriceCandidate(
                amount: 420, currency: "USD", source: "Shop B",
                quoteDate: date, matchLabel: "Estate Reserve Magnum"
            ),
        ])
        let (store, repository) = try await makeStore(provider: provider)
        let bottle = try await addBottle(to: store, name: "Estate Reserve")

        await store.requestPriceLookup(for: bottle)

        XCTAssertEqual(store.lookupCandidates.count, 2)
        let storedAfter = try await storedQuotes(repository, bottleID: bottle.id)
        XCTAssertTrue(storedAfter.isEmpty)

        // Confirm only the magnum; the 750ml candidate must not leak in.
        let magnum = try XCTUnwrap(store.lookupCandidates.first { $0.matchLabel.contains("Magnum") })
        let confirmed = await store.confirm(magnum, for: bottle)
        XCTAssertTrue(confirmed)

        let quotes = try await storedQuotes(repository, bottleID: bottle.id)
        XCTAssertEqual(quotes.count, 1)
        XCTAssertEqual(quotes[0].amount, 420)
    }

    func testTimeoutSurfacesMessageAndManualPathRemains() async throws {
        let (store, _) = try await makeStore(provider: FixturePriceProvider(behavior: .timeout))
        let bottle = try await addBottle(to: store, name: "Timed Out")

        await store.requestPriceLookup(for: bottle)

        let message = try XCTUnwrap(store.errorMessage)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("timed out"))
        XCTAssertTrue(store.lookupCandidates.isEmpty)
        // Offline fallback still works with no network answer.
        let saved = await store.saveManualPrice(amount: 15, currency: "USD", for: bottle)
        XCTAssertTrue(saved)
        XCTAssertNotNil(store.latestQuote(for: bottle.id))
    }

    func testNoResultsSurfacesMessage() async throws {
        let (store, _) = try await makeStore(provider: FixturePriceProvider(behavior: .noResults))
        let bottle = try await addBottle(to: store, name: "Unknown Cuvée")

        await store.requestPriceLookup(for: bottle)

        let message = try XCTUnwrap(store.errorMessage)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("No price matches"))
    }

    func testDisabledProviderDoesNotPretendToLookUp() async throws {
        let (store, _) = try await makeStore(provider: FixturePriceProvider(behavior: .disabled))
        let bottle = try await addBottle(to: store, name: "Quiet")

        await store.requestPriceLookup(for: bottle)

        let message = try XCTUnwrap(store.errorMessage)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("turned off"))
        XCTAssertTrue(store.lookupCandidates.isEmpty)
    }

    func testMissingProviderDirectsToManualEntry() async throws {
        let (store, _) = try await makeStore(provider: nil)
        XCTAssertFalse(store.isPriceLookupConfigured)
        let bottle = try await addBottle(to: store, name: "No Provider")

        await store.requestPriceLookup(for: bottle)

        let message = try XCTUnwrap(store.errorMessage)
        XCTAssertTrue(message.localizedCaseInsensitiveContains("not enabled"))
    }

    func testManualPriceIsStoredAsDatedQuoteWithManualProvenance() async throws {
        let (store, repository) = try await makeStore()
        let bottle = try await addBottle(to: store, name: "Hand Picked")

        let saved = await store.saveManualPrice(
            amount: Decimal(string: "23.50")!,
            currency: "USD",
            for: bottle
        )
        XCTAssertTrue(saved)

        let quote = try XCTUnwrap(store.latestQuote(for: bottle.id))
        XCTAssertEqual(quote.amount, Decimal(string: "23.50")!)
        XCTAssertEqual(quote.source, "Manual entry")
        let stored = try await storedQuotes(repository, bottleID: bottle.id)
        XCTAssertEqual(stored.count, 1)
        XCTAssertTrue(stored[0].query.contains("Hand Picked"))
    }

    func testManualPriceRejectsInvalidAmount() async throws {
        let (store, repository) = try await makeStore()
        let bottle = try await addBottle(to: store, name: "Bad Input")

        let saved = await store.saveManualPrice(amount: Decimal(-5), currency: "USD", for: bottle)

        XCTAssertFalse(saved)
        XCTAssertNotNil(store.errorMessage)
        let storedAfter = try await storedQuotes(repository, bottleID: bottle.id)
        XCTAssertTrue(storedAfter.isEmpty)
    }

    func testCurrencyMismatchIsValuedButExcludedFromTotal() async throws {
        let (store, _) = try await makeStore()
        let usdBottle = try await addBottle(to: store, name: "US One")
        let euroBottle = try await addBottle(to: store, name: "Euro One")

        let savedUS = await store.saveManualPrice(amount: 10, currency: "USD", for: usdBottle)
        XCTAssertTrue(savedUS)
        let savedEuro = await store.saveManualPrice(amount: 99, currency: "EUR", for: euroBottle)
        XCTAssertTrue(savedEuro)

        let valuation = store.collectionValuation
        XCTAssertEqual(valuation.total, 10)
        XCTAssertEqual(valuation.excludedCurrencyMismatchCount, 1)
        XCTAssertEqual(valuation.valuedBottleCount, 2)
        XCTAssertEqual(valuation.unvaluedBottleCount, 0)
    }

    func testCollectionEstimateQueueConfirmsOneBottleAtATime() async throws {
        let (store, repository) = try await makeStore()
        let first = try await addBottle(to: store, name: "Queue First")
        let second = try await addBottle(to: store, name: "Queue Second")

        await store.startCollectionEstimate()

        XCTAssertTrue(store.isCollectionLookupActive)
        XCTAssertEqual(store.collectionLookupTotal, 2)
        // The first bottle's candidates are presented; nothing stored yet.
        XCTAssertEqual(store.lookupCandidates.count, 1)
        let storedAfter = try await storedQuotes(repository, bottleID: first.id)
        XCTAssertTrue(storedAfter.isEmpty)

        let firstCandidate = try XCTUnwrap(store.lookupCandidates.first)
        let confirmedFirst = await store.confirm(firstCandidate, for: first)
        XCTAssertTrue(confirmedFirst)

        // The run advanced to the second bottle.
        XCTAssertEqual(store.collectionLookupQueue.first?.id, second.id)
        XCTAssertEqual(store.lookupCandidates.count, 1)

        let secondCandidate = try XCTUnwrap(store.lookupCandidates.first)
        let confirmedSecond = await store.confirm(secondCandidate, for: second)
        XCTAssertTrue(confirmedSecond)

        XCTAssertFalse(store.isCollectionLookupActive)
        XCTAssertNotNil(store.latestQuote(for: first.id))
        XCTAssertNotNil(store.latestQuote(for: second.id))
        XCTAssertEqual(store.collectionValuation.valuedBottleCount, 2)
    }

    func testCollectionEstimateSkipLeavesBottleUnvalued() async throws {
        let (store, _) = try await makeStore()
        let first = try await addBottle(to: store, name: "Skip Me")
        let second = try await addBottle(to: store, name: "Keep Me")

        await store.startCollectionEstimate()
        await store.skipLookup()

        XCTAssertEqual(store.collectionLookupQueue.first?.id, second.id)
        XCTAssertNil(store.latestQuote(for: first.id))

        let candidate = try XCTUnwrap(store.lookupCandidates.first)
        let confirmed = await store.confirm(candidate, for: second)
        XCTAssertTrue(confirmed)

        XCTAssertNotNil(store.latestQuote(for: second.id))
        XCTAssertEqual(
            store.collectionValuation.coverageDescription,
            "1 of 2 bottles valued; 1 unvalued excluded"
        )
    }

    func testCollectionEstimateStopsWhenCancelled() async throws {
        let (store, _) = try await makeStore()
        _ = try await addBottle(to: store, name: "Still Unvalued")

        await store.startCollectionEstimate()
        XCTAssertTrue(store.isCollectionLookupActive)

        store.cancelLookup()

        XCTAssertFalse(store.isCollectionLookupActive)
        XCTAssertTrue(store.lookupCandidates.isEmpty)
        XCTAssertTrue(store.quotesByBottle.isEmpty)
    }

    func testDeleteQuoteRemovesFromStoreAndDatabase() async throws {
        let (store, repository) = try await makeStore()
        let bottle = try await addBottle(to: store, name: "Delete Quote")
        let saved = await store.saveManualPrice(amount: 8, currency: "USD", for: bottle)
        XCTAssertTrue(saved)
        let quote = try XCTUnwrap(store.latestQuote(for: bottle.id))

        let deleted = await store.deleteQuote(quote)
        XCTAssertTrue(deleted)

        XCTAssertNil(store.latestQuote(for: bottle.id))
        let storedAfter = try await storedQuotes(repository, bottleID: bottle.id)
        XCTAssertTrue(storedAfter.isEmpty)
    }

    func testConcurrentLookupsAreCoalesced() async throws {
        let gate = GatePriceProvider()
        let (store, _) = try await makeStore(provider: gate)
        let bottle = try await addBottle(to: store, name: "Gate")

        async let firstLookup: Void = store.requestPriceLookup(for: bottle)
        await gate.waitForRequest()
        await store.requestPriceLookup(for: bottle)  // ignored while one is in flight
        await gate.release()
        await firstLookup

        let requestCount = await gate.requestCount
        XCTAssertEqual(requestCount, 1)
    }

    func testCollectionEstimateWithNoProviderDoesNotStart() async throws {
        let (store, _) = try await makeStore(provider: nil)
        _ = try await addBottle(to: store, name: "Blocked")

        await store.startCollectionEstimate()

        XCTAssertFalse(store.isCollectionLookupActive)
        XCTAssertNotNil(store.errorMessage)
    }
}

private actor GatePriceProvider: PriceProviding {
    private(set) var requestCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func priceCandidates(for query: PriceQuery) async throws -> [PriceCandidate] {
        requestCount += 1
        waiters.forEach { $0.resume() }
        waiters.removeAll()
        await withCheckedContinuation { releaseContinuation = $0 }
        return [
            try PriceCandidate(
                amount: 5, currency: "USD", source: "Gate",
                quoteDate: Date(), matchLabel: "gate match"
            ),
        ]
    }

    func waitForRequest() async {
        guard requestCount == 0 else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
