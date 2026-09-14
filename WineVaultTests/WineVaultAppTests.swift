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
