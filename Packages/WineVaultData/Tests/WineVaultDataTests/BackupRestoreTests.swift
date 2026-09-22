import Foundation
import XCTest

@testable import WineVaultData
import WineVaultDomain

/// Issue #6 acceptance: backup → wipe → restore round-trip including
/// photos, plus rejection paths for corrupted and future-schema archives.
final class BackupRestoreTests: XCTestCase {
    private func makeRoot(_ label: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupRestoreTests-\(label)-\(UUID().uuidString)", isDirectory: true)
    }

    private func makeBottle(name: String, quantity: Int = 1) throws -> Bottle {
        try Bottle(
            name: name,
            producer: "Maison \(name)",
            vintage: 2018,
            region: "Loire",
            quantity: quantity,
            storageLocation: "Rack",
            tags: ["keep"],
            notes: "note for \(name)"
        )
    }

    private func makeQuote(bottleID: UUID, amount: Decimal, date: Date) throws -> ValuationQuote {
        try ValuationQuote(
            bottleID: bottleID, quoteDate: date, amount: amount,
            currency: "USD", source: "TestShop", retrievedAt: date, query: "wine \(amount)"
        )
    }

    func testBackupWipeRestoreRoundTripPreservesBottlesQuotesAndPhotos() async throws {
        let root = makeRoot("roundtrip")
        defer { try? FileManager.default.removeItem(at: root) }
        let stack = try WineVaultDataStack(rootDirectory: root)

        let kept = try makeBottle(name: "Sancerre")
        try await stack.repository.create(kept)
        let photo = try await stack.savePhoto(Data("label-bytes".utf8), fileExtension: "jpg", for: kept.id)
        let storedRecord = try await stack.repository.bottle(id: kept.id)
        let stored = try XCTUnwrap(storedRecord)
        XCTAssertEqual(stored.photos, [photo])
        let quoteDate = Date(timeIntervalSince1970: 1_750_000_000)
        try await stack.repository.createQuote(try makeQuote(bottleID: kept.id, amount: 31, date: quoteDate))

        let bundle = try await stack.createBackup(appVersion: "9.9 (99)")
        // Optional diagnostic: dump the real archive for external ZIP
        // tooling checks (set WV_DUMP_ZIP=/path/to/file.zip).
        if let dump = ProcessInfo.processInfo.environment["WV_DUMP_ZIP"] {
            try bundle.zipData.write(to: URL(fileURLWithPath: dump))
        }
        XCTAssertNotNil(bundle.zipData.range(of: Data("manifest.json".utf8)))
        XCTAssertTrue(bundle.suggestedFileName.hasPrefix("wine-vault-backup-"))
        XCTAssertEqual(bundle.manifest.schemaVersion, DatabaseSchema.currentVersion)

        // Wipe everything through the stack: rows plus unreferenced photos.
        let deletion = try await stack.deleteBottle(id: kept.id)
        XCTAssertTrue(deletion.pendingPhotoCleanup.isEmpty)
        let orphans = try await stack.garbageCollectOrphanPhotos()
        XCTAssertEqual(orphans, [])

        let summary = try await stack.restoreBackup(from: bundle.zipData, strategy: .replace)
        XCTAssertEqual(summary.bottlesInserted, 1)
        XCTAssertEqual(summary.photosRestored, 1)
        XCTAssertEqual(summary.photosPending, 0)

        let restoredBottles = try await stack.repository.bottles()
        XCTAssertEqual(restoredBottles, [stored])
        let restoredQuotes = try await stack.repository.quotes(bottleID: kept.id)
        XCTAssertEqual(restoredQuotes.count, 1)
        XCTAssertEqual(restoredQuotes.first?.amount, 31)
        let photoData = try await stack.photos.data(for: photo)
        XCTAssertEqual(photoData, Data("label-bytes".utf8))
    }

    func testMergeStrategyKeepsLocalOnlyRecordsAndReplacesSameIdentifier() async throws {
        let sourceRoot = makeRoot("merge-source")
        let targetRoot = makeRoot("merge-target")
        defer {
            try? FileManager.default.removeItem(at: sourceRoot)
            try? FileManager.default.removeItem(at: targetRoot)
        }
        let source = try WineVaultDataStack(rootDirectory: sourceRoot)
        let target = try WineVaultDataStack(rootDirectory: targetRoot)

        let shared = try makeBottle(name: "Shared")
        try await source.repository.create(shared)
        let archived = try Bottle(
            id: shared.id, name: "Shared Renamed", quantity: 5, storageLocation: "Bin"
        )
        // The ZIP must carry the newer record for the same identifier.
        try await source.repository.update(archived)
        let bundle = try await source.createBackup(appVersion: "1")

        let localOnly = try makeBottle(name: "Local Only")
        try await target.repository.create(localOnly)

        let summary = try await target.restoreBackup(from: bundle.zipData, strategy: .merge)
        XCTAssertEqual(summary.bottlesInserted, 1)
        XCTAssertEqual(summary.bottlesReplaced, 0) // target had no matching id yet

        let names = try await target.repository.bottles().map(\.name).sorted()
        XCTAssertEqual(names, ["Local Only", "Shared Renamed"])

        // Merging the same archive again replaces the same id, inserts nothing.
        let again = try await target.restoreBackup(from: bundle.zipData, strategy: .merge)
        XCTAssertEqual(again.bottlesInserted, 0)
        XCTAssertEqual(again.bottlesReplaced, 1)
    }

    func testCorruptedArchiveLeavesExistingDataIntact() async throws {
        let root = makeRoot("corrupt")
        defer { try? FileManager.default.removeItem(at: root) }
        let stack = try WineVaultDataStack(rootDirectory: root)
        let bottle = try makeBottle(name: "Guarded")
        try await stack.repository.create(bottle)
        let photo = try await stack.savePhoto(Data("keepme".utf8), fileExtension: "jpg", for: bottle.id)

        let bundle = try await stack.createBackup(appVersion: "1")
        // Flip one byte inside the manifest payload: its CRC check fails
        // during archive validation, before anything live is touched.
        var corrupted = bundle.zipData
        let marker = Data("\"appVersion\"".utf8)
        guard let range = corrupted.firstRange(of: marker) else {
            return XCTFail("manifest payload marker not found in ZIP")
        }
        corrupted[corrupted.index(range.lowerBound, offsetBy: 2)] ^= 0x20

        do {
            _ = try await stack.restoreBackup(from: corrupted, strategy: .replace)
            XCTFail("expected validation failure")
        } catch let error as BackupError {
            XCTAssertEqual(error, .checksumMismatch(VaultBackupManifest.fileName))
        }

        // Vault untouched: rows and photo file are still there.
        let bottles = try await stack.repository.bottles()
        XCTAssertEqual(bottles.count, 1)
        XCTAssertEqual(bottles.first?.name, "Guarded")
        let photoData = try await stack.photos.data(for: photo)
        XCTAssertEqual(photoData, Data("keepme".utf8))
    }

    func testNewerSchemaVersionIsRejected() async throws {
        let root = makeRoot("future")
        defer { try? FileManager.default.removeItem(at: root) }
        let stack = try WineVaultDataStack(rootDirectory: root)
        try await stack.repository.create(try makeBottle(name: "Present"))
        let bundle = try await stack.createBackup(appVersion: "1")

        // Rebuild the archive with a bumped manifest schemaVersion.
        let futureArchive = try archiveByBumpingSchemaVersion(
            in: bundle.zipData, to: DatabaseSchema.currentVersion + 1
        )

        do {
            _ = try await stack.restoreBackup(from: futureArchive, strategy: .replace)
            XCTFail("expected unsupported schema rejection")
        } catch let error as BackupError {
            XCTAssertEqual(error, .unsupportedSchemaVersion(DatabaseSchema.currentVersion + 1))
        }

        // Direct manifest check (bypassing checksums) proves the version gate.
        let manifest = VaultBackupManifest(
            formatVersion: VaultBackupManifest.currentFormatVersion,
            schemaVersion: DatabaseSchema.currentVersion + 5,
            appVersion: "next",
            createdAt: Date(),
            checksums: [:]
        )
        let manifestData = try JSONEncoder.backupStyle.encode(manifest)
        let validArchive = ZipArchive.build(entries: [
            ZipEntry(name: VaultBackupManifest.fileName, data: manifestData, modificationDate: Date()),
        ] + [
            ZipEntry(
                name: "vault.sqlite",
                data: try Data(contentsOf: root.appendingPathComponent("vault.sqlite")),
                modificationDate: Date()
            ),
        ])
        do {
            let staging = FileManager.default.temporaryDirectory
                .appendingPathComponent("staging-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: staging) }
            _ = try WineVaultDataStack.validateAndExtract(validArchive, into: staging)
            XCTFail("expected unsupported schema rejection")
        } catch let error as BackupError {
            XCTAssertEqual(error, .unsupportedSchemaVersion(DatabaseSchema.currentVersion + 5))
        }
    }

    /// Rebuilds a backup archive with the manifest's `schemaVersion` set to
    /// `version`, re-checksummed into a fresh valid ZIP.
    private func archiveByBumpingSchemaVersion(
        in zipData: Data, to version: Int
    ) throws -> Data {
        let entries = try ZipArchive.read(zipData)
        var rebuilt: [ZipEntry] = []
        for entry in entries {
            guard entry.name == VaultBackupManifest.fileName else {
                rebuilt.append(entry)
                continue
            }
            let object = try JSONSerialization.jsonObject(with: entry.data)
            guard var json = object as? [String: Any] else {
                throw BackupError.invalidManifest
            }
            json["schemaVersion"] = version
            rebuilt.append(
                ZipEntry(
                    name: entry.name,
                    data: try JSONSerialization.data(withJSONObject: json),
                    modificationDate: entry.modificationDate
                )
            )
        }
        return ZipArchive.build(entries: rebuilt)
    }

    func testUndeclaredEntryAndWrongFormatVersionAreRejected() async throws {
        let root = makeRoot("extra")
        defer { try? FileManager.default.removeItem(at: root) }
        let stack = try WineVaultDataStack(rootDirectory: root)
        try await stack.repository.create(try makeBottle(name: "Clean"))
        let bundle = try await stack.createBackup(appVersion: "1")

        let entries = try ZipArchive.read(bundle.zipData)
        let smuggled = entries + [
            ZipEntry(name: "photos/evil.jpg", data: Data("evil".utf8), modificationDate: Date())
        ]
        do {
            _ = try await stack.restoreBackup(
                from: ZipArchive.build(entries: smuggled), strategy: .replace
            )
            XCTFail("expected undeclared-entry rejection")
        } catch let error as BackupError {
            XCTAssertEqual(error, .unexpectedEntry("undeclared-entry"))
        }

        // Wrong format version, with a consistent manifest (no checksum tamper).
        var rebuilt: [ZipEntry] = []
        for entry in entries {
            if entry.name == VaultBackupManifest.fileName {
                var manifest = try JSONDecoder.backupStyle.decode(
                    VaultBackupManifest.self, from: entry.data
                )
                manifest = VaultBackupManifest(
                    formatVersion: 99,
                    schemaVersion: manifest.schemaVersion,
                    appVersion: manifest.appVersion,
                    createdAt: manifest.createdAt,
                    checksums: manifest.checksums
                )
                rebuilt.append(
                    ZipEntry(
                        name: entry.name,
                        data: try JSONEncoder.backupStyle.encode(manifest),
                        modificationDate: entry.modificationDate
                    )
                )
            } else {
                rebuilt.append(entry)
            }
        }
        do {
            _ = try await stack.restoreBackup(
                from: ZipArchive.build(entries: rebuilt), strategy: .replace
            )
            XCTFail("expected format version rejection")
        } catch let error as BackupError {
            XCTAssertEqual(error, .unsupportedFormatVersion(99))
        }
    }

    func testManifestChecksumsCoverDatabaseAndPhotos() async throws {
        let root = makeRoot("manifest")
        defer { try? FileManager.default.removeItem(at: root) }
        let stack = try WineVaultDataStack(rootDirectory: root)
        let bottle = try makeBottle(name: "Provenance")
        try await stack.repository.create(bottle)
        _ = try await stack.savePhoto(Data("p1".utf8), fileExtension: "png", for: bottle.id)

        let bundle = try await stack.createBackup(appVersion: "2.0 (200)")
        XCTAssertEqual(bundle.manifest.checksums["vault.sqlite"]?.count, 64)
        let photoKeys = bundle.manifest.checksums.keys.filter { $0.hasPrefix("photos/") }
        XCTAssertEqual(photoKeys.count, 1)
        XCTAssertNil(bundle.manifest.checksums[VaultBackupManifest.fileName])
        for (_, digest) in bundle.manifest.checksums {
            XCTAssertEqual(digest.count, 64)
        }
    }
}
