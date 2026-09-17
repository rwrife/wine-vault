import Foundation
@testable import WineVault
import WineVaultData
import WineVaultDomain
import XCTest

/// App-target smoke test for the issue #1 skeleton: proves the app host
/// builds, the placeholder root view exists, and unit tests can run in it.
final class WineVaultAppTests: XCTestCase {
    @MainActor
    func testContentViewInstantiates() {
        _ = ContentView()  // must not crash at init
    }

    @MainActor
    func testContentViewAcceptsNativeDataPackageRepository() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WineVaultAppTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let stack = try WineVaultDataStack(rootDirectory: root)

        _ = ContentView(repository: stack.repository)
    }

    func testRepositoryLoadFailureIsPresentedInsteadOfDiscarded() async {
        let state = await ContentView.load(using: {
            FailingBottleRepository()
        })

        guard case let .failed(message) = state else {
            return XCTFail("Expected a recoverable failed state")
        }
        XCTAssertTrue(message.contains("could not be opened"))
    }

    func testStackStartupFailureIsRecoverable() async {
        let state = await ContentView.load(using: {
            throw TestRepositoryError.unavailable
        })

        guard case .failed = state else {
            return XCTFail("Expected a recoverable failed state")
        }
    }

    @MainActor
    func testInventoryStoreAddSearchEditAndDelete() async throws {
        let repository = try SQLiteBottleRepository(inMemory: true)
        let store = InventoryStore(repository: repository)
        await store.load()

        var form = BottleForm(
            name: "Estate Reserve", producer: "Maison", vintage: "2020",
            region: "Bordeaux", grape: "Merlot", quantity: 2,
            storageLocation: "Rack A", tags: ["Dinner"]
        )
        await store.save(form)
        XCTAssertEqual(store.bottles.map(\.name), ["Estate Reserve"])

        store.criteria.searchText = "maison"
        XCTAssertEqual(store.filteredBottles.map(\.name), ["Estate Reserve"])

        form.name = "Estate Reserve Edited"
        form.quantity = 4
        await store.save(form)
        XCTAssertEqual(store.bottles.first?.quantity, 4)

        let bottle = try XCTUnwrap(store.bottles.first)
        let quote = try ValuationQuote(
            bottleID: bottle.id,
            quoteDate: Date(),
            amount: 25,
            currency: "USD",
            source: "Test",
            retrievedAt: Date(),
            query: bottle.name
        )
        try await repository.createQuote(quote)
        await store.delete(bottle)
        XCTAssertTrue(store.bottles.isEmpty)
        let remainingQuotes = try await repository.quotes(bottleID: bottle.id)
        XCTAssertTrue(remainingQuotes.isEmpty)
    }

    @MainActor
    func testInventoryStoreSurfacesRepositoryFailure() async {
        let store = InventoryStore(repository: FailingBottleRepository())

        await store.load()

        XCTAssertTrue(store.bottles.isEmpty)
        XCTAssertNotNil(store.errorMessage)
    }

    @MainActor
    func testInventoryStoreReloadsAfterCommittedDeleteWithPhotoCleanupWarning() async throws {
        let repository = try SQLiteBottleRepository(inMemory: true)
        let reference = try PhotoReference("photos/pending.jpg")
        let bottle = try Bottle(
            name: "Cleanup Warning",
            quantity: 1,
            storageLocation: "Rack",
            photos: [reference]
        )
        try await repository.create(bottle)
        let store = InventoryStore(
            dependencies: InventoryDependencies(
                repository: repository,
                deleteBottle: { id in
                    try await repository.deleteBottle(id: id)
                    return BottleDeletionResult(pendingPhotoCleanup: [reference])
                }
            )
        )
        await store.load()

        await store.delete(bottle)

        XCTAssertTrue(store.bottles.isEmpty)
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.cleanupWarningMessage?.contains("Bottle deleted") == true)
    }

    @MainActor
    func testInventoryStoreCanRetryAfterPhotoWriteFailsAfterCreate() async throws {
        let repository = try SQLiteBottleRepository(inMemory: true)
        let attempts = PhotoSaveAttempts()
        let store = InventoryStore(
            dependencies: InventoryDependencies(
                repository: repository,
                savePhoto: { _, _ in
                    guard await attempts.recordAttempt() > 1 else {
                        throw TestRepositoryError.unavailable
                    }
                }
            )
        )
        let form = BottleForm(name: "Retry Reserve", quantity: 1)

        let firstSaveSucceeded = await store.save(form, photoData: Data([0x01]))
        XCTAssertFalse(firstSaveSucceeded)
        XCTAssertEqual(store.bottles.map(\.name), ["Retry Reserve"])
        XCTAssertNotNil(store.errorMessage)

        let retrySucceeded = await store.save(form, photoData: Data([0x01]))
        XCTAssertTrue(retrySucceeded)
        XCTAssertEqual(store.bottles.map(\.name), ["Retry Reserve"])
        XCTAssertNil(store.errorMessage)
        let attemptCount = await attempts.count
        XCTAssertEqual(attemptCount, 2)
    }

    @MainActor
    func testInventoryStoreRejectsReentrantSaveWhilePhotoWriteIsInFlight() async throws {
        let repository = try SQLiteBottleRepository(inMemory: true)
        let gate = SaveGate()
        let store = InventoryStore(
            dependencies: InventoryDependencies(
                repository: repository,
                savePhoto: { _, _ in await gate.suspend() }
            )
        )
        let form = BottleForm(name: "Serialized Reserve", quantity: 1)

        let firstSave = Task { @MainActor in
            await store.save(form, photoData: Data([0x01]))
        }
        await gate.waitUntilStarted()

        XCTAssertTrue(store.isSaving)
        let reentrantSaveSucceeded = await store.save(form, photoData: Data([0x02]))
        XCTAssertFalse(reentrantSaveSucceeded)

        await gate.release()
        let firstSaveSucceeded = await firstSave.value
        XCTAssertTrue(firstSaveSucceeded)
        XCTAssertFalse(store.isSaving)
        let bottleCount = try await repository.bottles().count
        XCTAssertEqual(bottleCount, 1)
        let attemptCount = await gate.attemptCount
        XCTAssertEqual(attemptCount, 1)
    }

    @MainActor
    func testEditingBottleAppendsPhotoWithoutLosingExistingPhoto() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WineVaultPhotoEditTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let stack = try WineVaultDataStack(rootDirectory: root)
        let original = try Bottle(name: "Cellar Red", quantity: 1, storageLocation: "A")
        try await stack.repository.create(original)
        let firstPhoto = try await stack.savePhoto(Data([0x01]), fileExtension: "jpg", for: original.id)
        let store = InventoryStore(
            dependencies: InventoryDependencies(
                repository: stack.repository,
                savePhoto: { data, bottleID in
                    _ = try await stack.savePhoto(data, fileExtension: "jpg", for: bottleID)
                },
                photoData: { reference in try await stack.photos.data(for: reference) }
            )
        )
        await store.load()
        var form = BottleForm(bottle: try XCTUnwrap(store.bottles.first))
        form.name = "Cellar Red Edited"

        let saved = await store.save(form, photoData: Data([0x02]))

        XCTAssertTrue(saved)
        let edited = try XCTUnwrap(store.bottles.first)
        XCTAssertEqual(edited.photos.count, 2)
        XCTAssertEqual(edited.photos.first, firstPhoto)
        XCTAssertNotEqual(edited.photos.last, firstPhoto)
    }

    @MainActor
    func testSuccessfulWriteRemainsSuccessfulWhenRefreshFails() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WineVaultRefreshTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let stack = try WineVaultDataStack(rootDirectory: root)
        let repository = RefreshFailingRepository(base: stack.repository)
        let store = InventoryStore(repository: repository)
        let form = BottleForm(name: "Saved Before Refresh", quantity: 1)

        let saved = await store.save(form)

        XCTAssertTrue(saved)
        let persistedBottle = try await stack.repository.bottle(id: form.id)
        XCTAssertNotNil(persistedBottle)
        XCTAssertTrue(store.errorMessage?.contains("could not be loaded") == true)
    }
}

private actor PhotoSaveAttempts {
    private(set) var count = 0

    func recordAttempt() -> Int {
        count += 1
        return count
    }
}

private actor SaveGate {
    private var started = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private(set) var attemptCount = 0

    func suspend() async {
        attemptCount += 1
        guard attemptCount == 1 else { return }
        started = true
        startWaiters.forEach { $0.resume() }
        startWaiters.removeAll()
        await withCheckedContinuation { releaseContinuation = $0 }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private struct RefreshFailingRepository: BottleRepository {
    let base: any BottleRepository

    func create(_ bottle: Bottle) async throws { try await base.create(bottle) }
    func bottle(id: UUID) async throws -> Bottle? { try await base.bottle(id: id) }
    func bottles() async throws -> [Bottle] { throw TestRepositoryError.unavailable }
    func update(_ bottle: Bottle) async throws { try await base.update(bottle) }
    func deleteBottle(id: UUID) async throws { try await base.deleteBottle(id: id) }
    func createQuote(_ quote: ValuationQuote) async throws { try await base.createQuote(quote) }
    func quotes(bottleID: UUID) async throws -> [ValuationQuote] {
        try await base.quotes(bottleID: bottleID)
    }
}

private enum TestRepositoryError: Error {
    case unavailable
}

private struct FailingBottleRepository: BottleRepository {
    func create(_ bottle: Bottle) async throws {
        throw TestRepositoryError.unavailable
    }

    func bottle(id: UUID) async throws -> Bottle? {
        throw TestRepositoryError.unavailable
    }

    func bottles() async throws -> [Bottle] {
        throw TestRepositoryError.unavailable
    }

    func update(_ bottle: Bottle) async throws {
        throw TestRepositoryError.unavailable
    }

    func deleteBottle(id: UUID) async throws {
        throw TestRepositoryError.unavailable
    }

    func createQuote(_ quote: ValuationQuote) async throws {
        throw TestRepositoryError.unavailable
    }

    func quotes(bottleID: UUID) async throws -> [ValuationQuote] {
        throw TestRepositoryError.unavailable
    }
}
