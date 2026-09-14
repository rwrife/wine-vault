import Foundation
import XCTest

@testable import WineVaultData
import WineVaultDomain

final class WineVaultDataStackTests: XCTestCase {
    func testStackCreatesDatabaseAndPhotosBelowPrivateRoot() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WineVaultDataStackTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let stack = try WineVaultDataStack(rootDirectory: root)
        let bottle = try Bottle(name: "Local", quantity: 1, storageLocation: "Rack")
        try await stack.repository.create(bottle)
        let photo = try await stack.savePhoto(
            Data("label".utf8),
            fileExtension: "jpg",
            for: bottle.id
        )

        XCTAssertEqual(stack.rootDirectory, root.standardizedFileURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("vault.sqlite").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(photo.path).path))
    }

    func testDefaultRootIsNamespacedInsideApplicationSupport() throws {
        let applicationSupport = URL(fileURLWithPath: "/private/container/Library/Application Support")

        let root = try AppPrivatePaths.rootDirectory(
            applicationSupportDirectory: applicationSupport,
            bundleIdentifier: "com.infinityball.winevault"
        )

        XCTAssertEqual(
            root.path,
            "/private/container/Library/Application Support/com.infinityball.winevault"
        )
    }

    func testAppPrivatePathRejectsTraversalControlsAndAbsoluteBundleIdentifiers() {
        let support = URL(fileURLWithPath: "/private/container/Library/Application Support")
        for bundleIdentifier in ["", ".", "..", "../escape", "/tmp/escape", "com.example/app", "com.example.\napp"] {
            XCTAssertThrowsError(
                try AppPrivatePaths.rootDirectory(
                    applicationSupportDirectory: support,
                    bundleIdentifier: bundleIdentifier
                ),
                "accepted unsafe bundle identifier: \(bundleIdentifier)"
            )
        }
    }

    func testStackRejectsSymlinkedRoot() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("WineVaultDataStackTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let target = parent.appendingPathComponent("target", isDirectory: true)
        let root = parent.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: target)

        XCTAssertThrowsError(try WineVaultDataStack(rootDirectory: root))
    }

    func testSystemStyleCanonicalAncestorSymlinkIsPermitted() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("WineVaultDataStackTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let realSupport = parent.appendingPathComponent("real-support", isDirectory: true)
        let aliasSupport = parent.appendingPathComponent("support-alias", isDirectory: true)
        try FileManager.default.createDirectory(at: realSupport, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: aliasSupport, withDestinationURL: realSupport)
        let root = try AppPrivatePaths.rootDirectory(
            applicationSupportDirectory: aliasSupport,
            bundleIdentifier: "com.infinityball.winevault"
        )

        XCTAssertNoThrow(try WineVaultDataStack(rootDirectory: root))
    }

    func testPhotoAttachmentAndGarbageCollectionAreCoordinated() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WineVaultDataStackTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let stack = try WineVaultDataStack(rootDirectory: root)
        let bottle = try Bottle(name: "Concurrent", quantity: 1, storageLocation: "Rack")
        try await stack.repository.create(bottle)

        async let attached = stack.savePhoto(
            Data("label".utf8),
            fileExtension: "jpg",
            for: bottle.id
        )
        async let removed = stack.garbageCollectOrphanPhotos()
        let (reference, garbageCollected) = try await (attached, removed)
        let savedData = try await stack.photos.data(for: reference)
        let savedBottle = try await stack.repository.bottle(id: bottle.id)

        XCTAssertFalse(garbageCollected.contains(reference))
        XCTAssertEqual(savedData, Data("label".utf8))
        XCTAssertEqual(savedBottle?.photos, [reference])
    }

    func testDirectCreateRejectsMissingPhotoReference() async throws {
        let (stack, root) = try makeStack()
        defer { try? FileManager.default.removeItem(at: root) }
        let missing = try PhotoReference("photos/missing.jpg")
        let bottle = try Bottle(
            name: "Missing",
            quantity: 1,
            storageLocation: "Rack",
            photos: [missing]
        )

        await XCTAssertThrowsRepositoryError(
            try await stack.repository.create(bottle),
            .missingPhotoReference(missing)
        )
        let savedBottle = try await stack.repository.bottle(id: bottle.id)
        XCTAssertNil(savedBottle)
    }

    func testDirectUpdateRejectsMissingPhotoReference() async throws {
        let (stack, root) = try makeStack()
        defer { try? FileManager.default.removeItem(at: root) }
        var bottle = try Bottle(name: "Update", quantity: 1, storageLocation: "Rack")
        try await stack.repository.create(bottle)
        let missing = try PhotoReference("photos/missing.jpg")
        bottle.photos = [missing]

        await XCTAssertThrowsRepositoryError(
            try await stack.repository.update(bottle),
            .missingPhotoReference(missing)
        )
        let savedBottle = try await stack.repository.bottle(id: bottle.id)
        XCTAssertEqual(savedBottle?.photos, [])
    }

    func testGarbageCollectionBeforeAttachmentMakesUpdateThrow() async throws {
        let (stack, root) = try makeStack()
        defer { try? FileManager.default.removeItem(at: root) }
        var bottle = try Bottle(name: "Ordering", quantity: 1, storageLocation: "Rack")
        try await stack.repository.create(bottle)
        let orphan = try await stack.photos.save(Data("orphan".utf8), fileExtension: "jpg")

        let removed = try await stack.garbageCollectOrphanPhotos()
        XCTAssertEqual(removed, [orphan])
        bottle.photos = [orphan]
        await XCTAssertThrowsRepositoryError(
            try await stack.repository.update(bottle),
            .missingPhotoReference(orphan)
        )
        let savedBottle = try await stack.repository.bottle(id: bottle.id)
        XCTAssertEqual(savedBottle?.photos, [])
    }

    func testDirectDeleteRejectsReferencedPhotoAndStackDeleteDetachesIt() async throws {
        let (stack, root) = try makeStack()
        defer { try? FileManager.default.removeItem(at: root) }
        let bottle = try Bottle(name: "Delete", quantity: 1, storageLocation: "Rack")
        try await stack.repository.create(bottle)
        let reference = try await stack.savePhoto(
            Data("label".utf8),
            fileExtension: "jpg",
            for: bottle.id
        )

        await XCTAssertThrowsPhotoError(
            try await stack.photos.delete(reference),
            .managedByDataStack
        )
        let retainedData = try await stack.photos.data(for: reference)
        XCTAssertEqual(retainedData, Data("label".utf8))

        try await stack.deletePhoto(reference, from: bottle.id)

        let savedBottle = try await stack.repository.bottle(id: bottle.id)
        XCTAssertEqual(savedBottle?.photos, [])
        await XCTAssertThrowsPhotoError(try await stack.photos.data(for: reference), .photoNotFound)
    }

    func testReplacingDatabaseFileWithPlainFileBlocksRepositoryAccess() async throws {
        let (stack, root) = try makeStack()
        defer { try? FileManager.default.removeItem(at: root) }
        let database = root.appendingPathComponent("vault.sqlite")
        let original = root.appendingPathComponent("original.sqlite")
        try FileManager.default.moveItem(at: database, to: original)
        try Data("replacement".utf8).write(to: database)

        do {
            _ = try await stack.repository.bottles()
            XCTFail("Expected replaced database to be rejected")
        } catch {
            XCTAssertEqual(error as? RepositoryError, .unsafeStorageLocation)
        }
    }

    func testReplacingStackRootWithSymlinkBlocksRepositoryAccess() async throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("WineVaultDataStackTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("root", isDirectory: true)
        let movedRoot = parent.appendingPathComponent("moved-root", isDirectory: true)
        let outside = parent.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let stack = try WineVaultDataStack(rootDirectory: root)
        try FileManager.default.moveItem(at: root, to: movedRoot)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: outside)

        do {
            _ = try await stack.repository.bottles()
            XCTFail("Expected replaced root to be rejected")
        } catch {
            XCTAssertEqual(error as? RepositoryError, .unsafeStorageLocation)
        }
    }

    private func makeStack() throws -> (WineVaultDataStack, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WineVaultDataStackTests-\(UUID().uuidString)", isDirectory: true)
        return (try WineVaultDataStack(rootDirectory: root), root)
    }
}

private func XCTAssertThrowsRepositoryError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ expected: RepositoryError
) async {
    do {
        _ = try await expression()
        XCTFail("Expected \(expected)")
    } catch {
        XCTAssertEqual(error as? RepositoryError, expected)
    }
}

private func XCTAssertThrowsPhotoError<T>(
    _ expression: @autoclosure () async throws -> T,
    _ expected: PhotoStoreError
) async {
    do {
        _ = try await expression()
        XCTFail("Expected \(expected)")
    } catch {
        XCTAssertEqual(error as? PhotoStoreError, expected)
    }
}
