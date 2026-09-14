import Foundation
import XCTest

@testable import WineVaultData
import WineVaultDomain

final class StorageBoundaryTests: XCTestCase {
    func testDanglingDatabaseSymlinkNeverCreatesOutsideTarget() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageBoundaryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("root", isDirectory: true)
        let outside = parent.appendingPathComponent("outside.sqlite")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("vault.sqlite"), withDestinationURL: outside
        )

        XCTAssertThrowsError(try WineVaultDataStack(rootDirectory: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
    }

    func testTwoStacksShareCoordinationAndPreserveAttachedPhotos() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageBoundaryTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try WineVaultDataStack(rootDirectory: root)
        let second = try WineVaultDataStack(rootDirectory: root)
        XCTAssertTrue(first.coordinator === second.coordinator)
        let bottle = try Bottle(name: "Two stacks", quantity: 1, storageLocation: "Rack")
        try await first.repository.create(bottle)

        async let attached = first.savePhoto(Data("label".utf8), fileExtension: "jpg", for: bottle.id)
        async let collected = second.garbageCollectOrphanPhotos()
        let (reference, removed) = try await (attached, collected)
        XCTAssertFalse(removed.contains(reference))
        let stored = try await second.repository.bottle(id: bottle.id)
        let image = try await second.photos.data(for: reference)
        XCTAssertEqual(stored?.photos, [reference])
        XCTAssertEqual(image, Data("label".utf8))
    }
}
