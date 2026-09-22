import Foundation
import SwiftUI
import UserNotifications
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
    /// Reminder backend. `nil` means drink-by reminders are unavailable in
    /// this launch (the UI hides the opt-in); UI tests inject
    /// `InertReminderScheduler` so the harness never touches real
    /// notifications. Production injects `UNReminderScheduler`.
    let reminderScheduling: (any ReminderScheduling)?
    /// Backup backend. `nil` means export/backup is unavailable in this
    /// launch; UI tests inject an in-memory `InertBackupService` so the
    /// harness never writes real archives.
    let backup: (any BackupServicing)?

    /// App version string embedded in backup manifests.
    let appVersion: String

    init(
        repository: any BottleRepository,
        savePhoto: @escaping @Sendable (Data, UUID) async throws -> Void = { _, _ in },
        photoData: @escaping @Sendable (PhotoReference) async throws -> Data = { _ in Data() },
        deleteBottle: (@Sendable (UUID) async throws -> BottleDeletionResult)? = nil,
        priceProvider: (any PriceProviding)? = nil,
        reminderScheduling: (any ReminderScheduling)? = nil,
        backup: (any BackupServicing)? = nil,
        appVersion: String = "0.1.0"
    ) {
        self.repository = repository
        self.savePhoto = savePhoto
        self.photoData = photoData
        self.deleteBottle = deleteBottle ?? { id in
            try await repository.deleteBottle(id: id)
            return BottleDeletionResult()
        }
        self.priceProvider = priceProvider
        self.reminderScheduling = reminderScheduling
        self.backup = backup
        self.appVersion = appVersion
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
            priceProvider: priceProvider,
            reminderScheduling: UNReminderScheduler(),
            backup: StackBackupService(stack: stack),
            appVersion: Self.displayAppVersion()
        )
    }

    /// CFBundleShortVersionString (CFBundleVersion) when available, so the
    /// manifest records the real shipping version.
    static func displayAppVersion() -> String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
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
    /// Lookup-outcome guidance (no matches, timeout, provider off, …) shown
    /// inside the estimate sheets. Deliberately separate from `errorMessage`:
    /// the collection-level error alert competes with sheet presentations on
    /// iOS 26 and can cancel the estimate sheet entirely, so lookup results
    /// must never drive it.
    @Published var lookupMessage: String?

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

    // MARK: - Drink-by reminders state (issue #5)

    /// Persisted user opt-in. The system permission request is only ever
    /// made when this flag flips on — never at launch.
    @Published private(set) var remindersOptedIn = false
    @Published private(set) var remindersAuthorization: UNAuthorizationStatus?

    nonisolated static let remindersOptInKey = "WineVaultDrinkByRemindersOptIn"

    var isReminderSchedulingAvailable: Bool {
        dependencies.reminderScheduling != nil
    }

    var timelineGroups: [(state: DrinkByState, bottles: [Bottle])] {
        drinkByTimelineGroups(bottles, reference: Date())
    }

    var dashboardCounts: CollectionCounts? {
        try? collectionCounts(bottles)
    }

    var drinkByQuantityCounts: [DrinkByState: Int] {
        (try? WineVaultDomain.drinkByCounts(bottles, reference: Date())) ?? [:]
    }

    var valueHistory: [ValueHistoryPoint] {
        WineVaultDomain.valueHistory(
            bottles: bottles,
            quotesByBottle: quotesByBottle,
            baseCurrency: valuationCurrency
        )
    }

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

    // MARK: - Export / backup / restore (issue #6)

    @Published private(set) var isExporting = false
    /// Success/failure guidance for export and restore, shown in settings.
    @Published var backupMessage: String?
    /// Last CSV export payload offered to the share sheet.
    @Published private(set) var csvShareData: Data?
    /// Last ZIP backup offered to the share sheet.
    @Published private(set) var zipShareData: Data?
    @Published private(set) var suggestedBackupName = "wine-vault-backup.zip"

    var isBackupAvailable: Bool {
        dependencies.backup != nil
    }

    func exportInventoryCSV() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        let csv = inventoryCSV(bottles: bottles, quotesByBottle: quotesByBottle)
        guard let data = csv.data(using: .utf8) else {
            backupMessage = "The inventory could not be encoded as CSV."
            return
        }
        csvShareData = data
        backupMessage = "CSV ready: \(bottles.count) bottle row(s) with quote provenance."
    }

    func createBackup() async {
        guard let backup = dependencies.backup, !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            let bundle = try await backup.createBackup(appVersion: dependencies.appVersion)
            zipShareData = bundle.zipData
            suggestedBackupName = bundle.suggestedFileName
            backupMessage = "Backup ready: \(bundle.suggestedFileName)"
        } catch {
            backupMessage = "The backup could not be created. \(error.localizedDescription)"
        }
    }

    /// Applies a picked ZIP archive. Failures leave existing data intact
    /// (the data layer validates the whole archive before touching it).
    func restore(zipData: Data, strategy: BackupRestoreStrategy) async {
        guard let backup = dependencies.backup, !isExporting else { return }
        isExporting = true
        defer { isExporting = false }
        do {
            let summary = try await backup.restoreBackup(from: zipData, strategy: strategy)
            await load()
            backupMessage = """
                Restored \(summary.bottlesInserted) new and \
                \(summary.bottlesReplaced) replaced bottle(s), \
                \(summary.photosRestored) photo(s).
                """
        } catch let error as BackupError {
            backupMessage = BackupErrorText.describe(error)
        } catch {
            backupMessage = "The restore failed. Your current collection is untouched."
        }
    }

    private let dependencies: InventoryDependencies

    init(repository: any BottleRepository) {
        dependencies = InventoryDependencies(repository: repository)
        remindersOptedIn = UserDefaults.standard.bool(forKey: Self.remindersOptInKey)
    }

    init(dependencies: InventoryDependencies) {
        self.dependencies = dependencies
        remindersOptedIn = UserDefaults.standard.bool(forKey: Self.remindersOptInKey)
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
            await syncReminders()
        } catch {
            errorMessage = "Your collection could not be loaded. \(error.localizedDescription)"
        }
    }

    // MARK: - Reminders (issue #5)

    /// Flips the user's drink-by reminders opt-in. The system permission
    /// request happens only through this user-initiated path — never at
    /// launch. A denial simply keeps reminders off; the drink-by timeline
    /// still shows every date in-app.
    func setRemindersOptedIn(_ optedIn: Bool) async {
        remindersOptedIn = optedIn
        UserDefaults.standard.set(optedIn, forKey: Self.remindersOptInKey)
        await syncReminders()
    }

    /// Reconciles pending system reminders with the current bottles when
    /// the user opted in and scheduling is available. Best-effort by
    /// contract: any backend failure leaves the in-app timeline intact.
    func syncReminders() async {
        guard let scheduler = dependencies.reminderScheduling else { return }
        remindersAuthorization = await scheduler.authorizationStatus
        guard remindersOptedIn else {
            await scheduler.cancelAll()
            return
        }
        if remindersAuthorization?.allowsReminders != true {
            // The user just flipped the opt-in toggle: this is the only
            // moment the system prompt is surfaced.
            _ = await scheduler.requestAuthorization()
            remindersAuthorization = await scheduler.authorizationStatus
            guard remindersAuthorization?.allowsReminders == true else { return }
        }
        let reminders = drinkByReminders(bottles: bottles, reference: Date())
        await scheduler.schedule(reminders: reminders)
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
            lookupMessage = "Price lookup is not enabled. You can still enter prices manually."
            return
        }
        let queue = bottles.filter { latestQuote(for: $0.id) == nil }
        guard !queue.isEmpty else {
            lookupMessage = "Every bottle already has a price on record. Re-estimate from each bottle to refresh."
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
            lookupMessage = nil
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
            lookupMessage = "Price lookup is not enabled. You can still enter a price manually."
            return
        }
        guard !isLookingUpPrice else { return }
        isLookingUpPrice = true
        defer { isLookingUpPrice = false }
        do {
            let query = try priceQuery(for: bottle)
            let candidates = try await priceProvider.priceCandidates(for: query)
            guard !candidates.isEmpty else {
                lookupMessage = "The price service returned no matches for “\(query.text)”. You can still enter a price manually."
                lookupCandidates = []
                lookupBottleID = nil
                return
            }
            lookupCandidates = candidates
            lookupBottleID = bottle.id
            pendingManualMatch = nil
            lookupMessage = nil
        } catch let error as PriceProviderError {
            lookupCandidates = []
            lookupBottleID = nil
            switch error {
            case .disabled:
                lookupMessage = "Price lookup is turned off. You can still enter a price manually."
            case .timedOut:
                lookupMessage = "The price lookup timed out. Try again, or enter a price manually."
            case .noResults:
                lookupMessage = "No price matches for “\(bottle.name)”. You can still enter a price manually."
            }
        } catch {
            lookupCandidates = []
            lookupBottleID = nil
            lookupMessage = "The price lookup could not complete. You can still enter a price manually."
        }
    }

    func cancelLookup() {
        isCollectionLookupMode = false
        collectionLookupQueue = []
        collectionLookupTotal = 0
        lookupCandidates = []
        lookupBottleID = nil
        pendingManualMatch = nil
        lookupMessage = nil
    }

    /// Explicitly declines the current candidate list without storing anything,
    /// then continues a collection run if one is active.
    func skipLookup() async {
        lookupCandidates = []
        lookupBottleID = nil
        pendingManualMatch = nil
        lookupMessage = nil
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
