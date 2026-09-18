import Foundation
import SwiftUI
import WineVaultData
import WineVaultDomain

struct InventoryDependencies: Sendable {
    let repository: any BottleRepository
    let savePhoto: @Sendable (Data, UUID) async throws -> Void
    let photoData: @Sendable (PhotoReference) async throws -> Data
    let deleteBottle: @Sendable (UUID) async throws -> BottleDeletionResult
    /// Opt-in price provider. `nil` means price lookup is not configured in
    /// this build/launch (e.g. release until a live provider is enabled);
    /// tests and UI tests inject `FixturePriceProvider`.
    let priceProvider: (any PriceProviding)?

    init(
        repository: any BottleRepository,
        savePhoto: @escaping @Sendable (Data, UUID) async throws -> Void = { _, _ in },
        photoData: @escaping @Sendable (PhotoReference) async throws -> Data = { _ in Data() },
        deleteBottle: (@Sendable (UUID) async throws -> BottleDeletionResult)? = nil,
        priceProvider: (any PriceProviding)? = nil
    ) {
        self.repository = repository
        self.savePhoto = savePhoto
        self.photoData = photoData
        self.priceProvider = priceProvider
        self.deleteBottle = deleteBottle ?? { id in
            try await repository.deleteBottle(id: id)
            return BottleDeletionResult()
        }
    }

    static func appPrivateDefault(priceProvider: (any PriceProviding)? = nil) throws -> InventoryDependencies {
        let stack = try WineVaultDataStack.appPrivateDefault()
        return InventoryDependencies(
            repository: stack.repository,
            savePhoto: { data, bottleID in
                _ = try await stack.savePhoto(data, fileExtension: "jpg", for: bottleID)
            },
            photoData: { reference in
                try await stack.photos.data(for: reference)
            },
            deleteBottle: { id in
                try await stack.deleteBottle(id: id)
            },
            priceProvider: priceProvider
        )
    }
}

@MainActor
final class InventoryStore: ObservableObject {
    @Published private(set) var bottles: [Bottle] = []
    @Published var criteria = BottleFilterCriteria()
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published var cleanupWarningMessage: String?

    // MARK: - Valuation state (issue #4)

    /// Candidate matches from the last user-initiated lookup, awaiting an
    /// explicit confirmation. Never applied automatically.
    @Published private(set) var lookupCandidates: [PriceCandidate] = []
    @Published private(set) var isLookingUpPrice = false
    /// Bottle whose lookup produced `lookupCandidates`, if from a lookup.
    @Published private(set) var lookupBottleID: UUID?
    /// User-chosen match label awaiting manual amount/currency entry.
    @Published private(set) var pendingManualMatch: PriceCandidate?
    @Published private(set) var quotesByBottle: [UUID: [ValuationQuote]] = [:]
    @Published private(set) var valuationCurrency = "USD"
    /// Remaining bottles in a collection-wide "Estimate value" run. Each
    /// still requires its own explicit confirm/skip — nothing auto-applies.
    @Published private(set) var collectionLookupQueue: [Bottle] = []
    @Published private(set) var collectionLookupTotal = 0
    private var isCollectionLookupMode = false

    var isCollectionLookupActive: Bool {
        isCollectionLookupMode && !collectionLookupQueue.isEmpty
    }

    var isPriceLookupConfigured: Bool {
        dependencies.priceProvider != nil
    }

    var collectionValuation: CollectionValuation {
        WineVaultDomain.collectionValuation(
            bottles: bottles,
            quotesByBottle: quotesByBottle,
            baseCurrency: valuationCurrency,
            reference: Date()
        )
    }

    func latestQuote(for bottleID: UUID) -> ValuationQuote? {
        WineVaultDomain.latestQuote(in: quotesByBottle[bottleID] ?? [])
    }

    private let dependencies: InventoryDependencies

    init(repository: any BottleRepository) {
        dependencies = InventoryDependencies(repository: repository)
    }

    init(dependencies: InventoryDependencies) {
        self.dependencies = dependencies
    }

    var filteredBottles: [Bottle] {
        filterBottles(bottles, criteria: criteria, reference: Date())
    }

    var facets: BottleFilterFacets {
        bottleFilterFacets(bottles)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let loadedBottles = dependencies.repository.bottles()
            async let loadedQuotes = dependencies.repository.allQuotes()
            let (loaded, quotes) = try await (loadedBottles, loadedQuotes)
            bottles = loaded
            quotesByBottle = Dictionary(grouping: quotes, by: \.bottleID)
            errorMessage = nil
        } catch {
            errorMessage = "Your collection could not be loaded. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func save(_ form: BottleForm, photoData: Data? = nil) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let bottle = try form.bottle()
            // Ask the repository rather than the last loaded snapshot. A photo write can
            // fail after the bottle itself was created; a retry must update that record
            // instead of getting stuck on a duplicate identifier.
            if try await dependencies.repository.bottle(id: bottle.id) != nil {
                try await dependencies.repository.update(bottle)
            } else {
                try await dependencies.repository.create(bottle)
            }
            if let photoData {
                try await dependencies.savePhoto(photoData, bottle.id)
            }
            await load()
            return true
        } catch BottleFormValidationError.invalid(_) {
            return false
        } catch {
            errorMessage = "The bottle could not be saved. \(error.localizedDescription)"
            await loadPreservingError()
            return false
        }
    }

    func delete(_ bottle: Bottle) async {
        cleanupWarningMessage = nil
        do {
            let result = try await dependencies.deleteBottle(bottle.id)
            await load()
            if !result.pendingPhotoCleanup.isEmpty {
                let count = result.pendingPhotoCleanup.count
                cleanupWarningMessage = "Bottle deleted, but \(count) label photo "
                    + (count == 1 ? "file still needs" : "files still need")
                    + " cleanup from private storage."
            }
        } catch {
            errorMessage = "The bottle could not be deleted. \(error.localizedDescription)"
        }
    }

    func photoData(for reference: PhotoReference) async throws -> Data {
        try await dependencies.photoData(reference)
    }

    func clearFilters() {
        criteria = BottleFilterCriteria()
    }

    // MARK: - Valuation flow (issue #4)

    /// User-initiated collection-wide estimate. Queues unvalued bottles and
    /// shows them one at a time for explicit confirmation; each step reuses
    /// the per-bottle candidate flow. Nothing is applied without a tap.
    func startCollectionEstimate() async {
        guard dependencies.priceProvider != nil else {
            errorMessage = "Price lookup is not enabled. You can still enter prices manually."
            return
        }
        let queue = bottles.filter { latestQuote(for: $0.id) == nil }
        guard !queue.isEmpty else {
            errorMessage = "Every bottle already has a price on record. Re-estimate from each bottle to refresh."
            return
        }
        isCollectionLookupMode = true
        collectionLookupQueue = queue
        collectionLookupTotal = queue.count
        if let first = queue.first {
            await requestPriceLookup(for: first)
        }
    }

    /// Moves a collection run to the next queued bottle after the current
    /// one was confirmed, skipped, or failed.
    func advanceCollectionLookup() async {
        guard isCollectionLookupMode else { return }
        guard !collectionLookupQueue.isEmpty else {
            endCollectionEstimate()
            return
        }
        collectionLookupQueue.removeFirst()
        if let next = collectionLookupQueue.first {
            lookupCandidates = []
            pendingManualMatch = nil
            errorMessage = nil
            await requestPriceLookup(for: next)
        } else {
            endCollectionEstimate()
        }
    }

    func endCollectionEstimate() {
        isCollectionLookupMode = false
        collectionLookupQueue = []
        collectionLookupTotal = 0
        lookupCandidates = []
        lookupBottleID = nil
        pendingManualMatch = nil
    }

    /// User-initiated per-bottle lookup. Results are only ever candidates;
    /// nothing is stored here. Also used by the collection flow to refresh
    /// one bottle at a time.
    func requestPriceLookup(for bottle: Bottle) async {
        guard let priceProvider = dependencies.priceProvider else {
            errorMessage = "Price lookup is not enabled. You can still enter a price manually."
            return
        }
        guard !isLookingUpPrice else { return }
        isLookingUpPrice = true
        defer { isLookingUpPrice = false }
        do {
            let query = try priceQuery(for: bottle)
            let candidates = try await priceProvider.priceCandidates(for: query)
            guard !candidates.isEmpty else {
                errorMessage = "The price service returned no matches for “\(query.text)”. You can still enter a price manually."
                lookupCandidates = []
                lookupBottleID = nil
                return
            }
            lookupCandidates = candidates
            lookupBottleID = bottle.id
            pendingManualMatch = nil
            errorMessage = nil
        } catch let error as PriceProviderError {
            lookupCandidates = []
            lookupBottleID = nil
            switch error {
            case .disabled:
                errorMessage = "Price lookup is turned off. You can still enter a price manually."
            case .timedOut:
                errorMessage = "The price lookup timed out. Try again, or enter a price manually."
            case .noResults:
                errorMessage = "No price matches for “\(bottle.name)”. You can still enter a price manually."
            }
        } catch {
            lookupCandidates = []
            lookupBottleID = nil
            errorMessage = "The price lookup could not complete. You can still enter a price manually."
        }
    }

    func cancelLookup() {
        isCollectionLookupMode = false
        collectionLookupQueue = []
        collectionLookupTotal = 0
        lookupCandidates = []
        lookupBottleID = nil
        pendingManualMatch = nil
    }

    /// Explicitly declines the current candidate list without storing anything,
    /// then continues a collection run if one is active.
    func skipLookup() async {
        lookupCandidates = []
        lookupBottleID = nil
        pendingManualMatch = nil
        if isCollectionLookupMode {
            await advanceCollectionLookup()
        }
    }

    /// The user explicitly confirmed one candidate match; record it with the
    /// exact query text used and the retrieval date. Ambiguity is resolved
    /// here — the caller must pass one specific candidate.
    @discardableResult
    func confirm(_ candidate: PriceCandidate, for bottle: Bottle) async -> Bool {
        guard let quote = try? ValuationQuote(
            bottleID: bottle.id,
            quoteDate: candidate.quoteDate,
            amount: candidate.amount,
            currency: candidate.currency,
            source: candidate.source,
            retrievedAt: Date(),
            query: priceQueryText(for: bottle)
        ) else {
            errorMessage = "That quote is missing provenance and was not saved."
            return false
        }
        do {
            try await dependencies.repository.createQuote(quote)
            await load()
            lookupCandidates = []
            lookupBottleID = nil
            pendingManualMatch = nil
            if isCollectionLookupMode {
                await advanceCollectionLookup()
            }
            return true
        } catch {
            errorMessage = "The confirmed quote could not be saved. \(error.localizedDescription)"
            return false
        }
    }

    /// Ambiguity handled explicitly: the user selects which candidate the
    /// manual price applies to before entering the amount offline.
    func beginManualPriceEntry(for candidate: PriceCandidate) {
        pendingManualMatch = candidate
    }

    /// Always-available offline fallback: store the user's own price with
    /// manual provenance.
    @discardableResult
    func saveManualPrice(
        amount: Decimal,
        currency: String,
        for bottle: Bottle,
        matchLabel: String? = nil
    ) async -> Bool {
        let label = matchLabel
            ?? pendingManualMatch?.matchLabel
            ?? "Manual entry for \(bottle.name)"
        guard let quote = try? ValuationQuote(
            bottleID: bottle.id,
            quoteDate: Date(),
            amount: amount,
            currency: currency,
            source: "Manual entry",
            retrievedAt: Date(),
            query: "\(priceQueryText(for: bottle)) | \(label)"
        ) else {
            errorMessage = "Enter a valid amount and currency to save a price."
            return false
        }
        do {
            try await dependencies.repository.createQuote(quote)
            await load()
            pendingManualMatch = nil
            return true
        } catch {
            errorMessage = "Your price could not be saved. \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func deleteQuote(_ quote: ValuationQuote) async -> Bool {
        do {
            try await dependencies.repository.deleteQuote(id: quote.id)
            await load()
            return true
        } catch {
            errorMessage = "The quote could not be deleted. \(error.localizedDescription)"
            return false
        }
    }

    private func priceQueryText(for bottle: Bottle) -> String {
        (try? priceQuery(for: bottle)).map(\.text) ?? bottle.name
    }

    private func loadPreservingError() async {
        let saveError = errorMessage
        await load()
        errorMessage = saveError
    }
}
