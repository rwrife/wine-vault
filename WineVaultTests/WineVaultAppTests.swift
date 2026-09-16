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
    func testInventoryStoreAddSearchEditDeleteAndUndo() async throws {
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
        await store.delete(bottle)
        XCTAssertTrue(store.bottles.isEmpty)
        XCTAssertTrue(store.canUndoDelete)

        await store.undoDelete()
        XCTAssertEqual(store.bottles.first?.name, "Estate Reserve Edited")
        XCTAssertEqual(store.bottles.first?.quantity, 4)
    }

    @MainActor
    func testInventoryStoreSurfacesRepositoryFailure() async {
        let store = InventoryStore(repository: FailingBottleRepository())

        await store.load()

        XCTAssertTrue(store.bottles.isEmpty)
        XCTAssertNotNil(store.errorMessage)
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
}

private actor PhotoSaveAttempts {
    private(set) var count = 0

    func recordAttempt() -> Int {
        count += 1
        return count
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
