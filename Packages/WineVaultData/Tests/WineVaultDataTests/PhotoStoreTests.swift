import Foundation
import XCTest

@testable import WineVaultData
import WineVaultDomain

final class PhotoStoreTests: XCTestCase {
    func testSaveAndReadUseRelativeAppPrivateReference() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PhotoStore(rootDirectory: root)
        let bytes = Data([0, 1, 2, 0xF0, 0x9F, 0x8D, 0xB7])

        let reference = try await store.save(bytes, fileExtension: "jpeg")

        XCTAssertTrue(reference.path.hasPrefix("photos/"))
        XCTAssertFalse(reference.path.hasPrefix("/"))
        let savedBytes = try await store.data(for: reference)
        XCTAssertEqual(savedBytes, bytes)
    }

    func testDeleteReportsMissingPhoto() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PhotoStore(rootDirectory: root)
        let missing = try PhotoReference("photos/missing.jpg")

        await XCTAssertThrowsPhotoError(try await store.delete(missing), .photoNotFound)
    }

    func testGarbageCollectionDeletesOnlyOrphanPhotos() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PhotoStore(rootDirectory: root)
        let kept = try await store.save(Data("kept".utf8), fileExtension: "jpg")
        let orphan = try await store.save(Data("orphan".utf8), fileExtension: "png")
        let unrelated = root.appendingPathComponent("vault.sqlite")
        try Data("database".utf8).write(to: unrelated)

        let removed = try await store.garbageCollect(keeping: [kept])

        XCTAssertEqual(removed, [orphan])
        let keptBytes = try await store.data(for: kept)
        XCTAssertEqual(keptBytes, Data("kept".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: unrelated.path))
    }

    func testSymlinkCannotEscapePhotoDirectory() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = root.deletingLastPathComponent().appendingPathComponent("outside-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("secret".utf8).write(to: outside)
        let store = try PhotoStore(rootDirectory: root)
        let link = root.appendingPathComponent("photos/link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)

        await XCTAssertThrowsPhotoError(
            try await store.data(for: PhotoReference("photos/link")),
            .unsafeReference
        )
    }

    func testInitiallySymlinkedRootIsRejected() throws {
        let parent = try makeTemporaryDirectory()
        let target = parent.appendingPathComponent("target", isDirectory: true)
        let root = parent.appendingPathComponent("root", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: target)

        XCTAssertThrowsError(try PhotoStore(rootDirectory: root)) { error in
            XCTAssertEqual(error as? PhotoStoreError, .unsafeReference)
        }
    }

    func testReplacingPhotosDirectoryWithSymlinkBlocksReadSaveAndGarbageCollection() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let outside = try makeTemporaryDirectory()
        let victim = outside.appendingPathComponent("victim.jpg")
        try Data("keep".utf8).write(to: victim)
        let store = try PhotoStore(rootDirectory: root)
        let photos = root.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.removeItem(at: photos)
        try FileManager.default.createSymbolicLink(at: photos, withDestinationURL: outside)
        let reference = try PhotoReference("photos/victim.jpg")

        await XCTAssertThrowsPhotoError(try await store.data(for: reference), .unsafeReference)
        await XCTAssertThrowsPhotoError(
            try await store.save(Data("new".utf8), fileExtension: "jpg"),
            .unsafeReference
        )
        await XCTAssertThrowsPhotoError(
            try await store.garbageCollect(keeping: []),
            .unsafeReference
        )
        XCTAssertEqual(try Data(contentsOf: victim), Data("keep".utf8))
    }

    func testReplacingRootWithSymlinkBlocksDestructiveOperations() async throws {
        let parent = try makeTemporaryDirectory()
        let root = parent.appendingPathComponent("root", isDirectory: true)
        let outside = parent.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        let store = try PhotoStore(rootDirectory: root)
        let victim = outside.appendingPathComponent("photos/victim.jpg")
        try FileManager.default.createDirectory(
            at: victim.deletingLastPathComponent(),
            withIntermediateDirectories: false
        )
        try Data("keep".utf8).write(to: victim)
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: outside)

        await XCTAssertThrowsPhotoError(
            try await store.garbageCollect(keeping: []),
            .unsafeReference
        )
        XCTAssertEqual(try Data(contentsOf: victim), Data("keep".utf8))
    }

    func testReplacingPhotosDirectoryWithPlainDirectoryBlocksOperations() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PhotoStore(rootDirectory: root)
        let photos = root.appendingPathComponent("photos", isDirectory: true)
        let originalPhotos = root.appendingPathComponent("original-photos", isDirectory: true)
        try FileManager.default.moveItem(at: photos, to: originalPhotos)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: false)
        let victim = photos.appendingPathComponent("victim.jpg")
        try Data("keep".utf8).write(to: victim)
        let reference = try PhotoReference("photos/victim.jpg")

        await XCTAssertThrowsPhotoError(try await store.data(for: reference), .unsafeReference)
        await XCTAssertThrowsPhotoError(
            try await store.save(Data("new".utf8), fileExtension: "jpg"),
            .unsafeReference
        )
        await XCTAssertThrowsPhotoError(
            try await store.garbageCollect(keeping: []),
            .unsafeReference
        )
        XCTAssertEqual(try Data(contentsOf: victim), Data("keep".utf8))
    }

    func testReplacingRootWithPlainDirectoryBlocksOperations() async throws {
        let parent = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        let root = parent.appendingPathComponent("root", isDirectory: true)
        let originalRoot = parent.appendingPathComponent("original-root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let store = try PhotoStore(rootDirectory: root)
        try FileManager.default.moveItem(at: root, to: originalRoot)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let replacementPhotos = root.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: replacementPhotos, withIntermediateDirectories: false)
        let victim = replacementPhotos.appendingPathComponent("victim.jpg")
        try Data("keep".utf8).write(to: victim)

        await XCTAssertThrowsPhotoError(
            try await store.data(for: PhotoReference("photos/victim.jpg")),
            .unsafeReference
        )
        await XCTAssertThrowsPhotoError(
            try await store.garbageCollect(keeping: []),
            .unsafeReference
        )
        XCTAssertEqual(try Data(contentsOf: victim), Data("keep".utf8))
    }

    func testUnsafeFileExtensionIsRejected() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try PhotoStore(rootDirectory: root)

        await XCTAssertThrowsPhotoError(
            try await store.save(Data(), fileExtension: "../sqlite"),
            .unsafeFileExtension
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
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
