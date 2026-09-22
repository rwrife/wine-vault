import Foundation
import GRDB
import WineVaultDomain

/// Backup/restore over the whole app-private vault root
/// (`vault.sqlite` + `photos/`), issue #6.
///
/// Restore contract: an archive is fully validated (manifest, checksums,
/// exact entry set, migratability, photo references) **before** any live
/// file or row is touched. Failures therefore leave the existing vault
/// intact; photos are staged as hidden files and moved into place only
/// after the database transaction commits.
extension WineVaultDataStack {

    // MARK: - Backup

    public func createBackup(appVersion: String) async throws -> VaultBackupBundle {
        let now = Date()
        return try await coordinator.withExclusiveAccess {
            let bottles = try await repository.bottlesWithoutCoordination()
            let database = repository.database

            let snapshotURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("wine-vault-backup-\(UUID().uuidString).sqlite")
            defer { try? FileManager.default.removeItem(at: snapshotURL) }

            var checksums: [String: String] = [:]
            var entries: [ZipEntry] = []

            // Snapshot the database with SQLite's online backup API so no
            // WAL sidecar files need to travel in the archive.
            try FileManager.default.createDirectory(
                at: snapshotURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let snapshot = try DatabaseQueue(path: snapshotURL.path)
            try DatabaseSchema.migrator().migrate(snapshot)
            try database.backup(to: snapshot)
            let databaseData = try Data(contentsOf: snapshotURL)
            checksums["vault.sqlite"] = SHA256.hexDigest(databaseData)
            entries.append(ZipEntry(name: "vault.sqlite", data: databaseData, modificationDate: now))

            // Pack every file physically present under photos/ and confirm
            // every bottle's references resolve.
            let packed = try await photos.packedPhotos(now: now)
            entries.append(contentsOf: packed.entries)
            for bottle in bottles {
                for reference in bottle.photos where !packed.covered.contains(reference) {
                    throw BackupError.photoMissingFromArchive(reference)
                }
            }
            for entry in entries where entry.name != "vault.sqlite" {
                checksums[entry.name] = SHA256.hexDigest(entry.data)
            }

            let manifest = VaultBackupManifest(
                formatVersion: VaultBackupManifest.currentFormatVersion,
                schemaVersion: DatabaseSchema.currentVersion,
                appVersion: appVersion,
                createdAt: now,
                checksums: checksums
            )
            let manifestData = try JSONEncoder.backupStyle.encode(manifest)
            var allEntries = entries
            allEntries.append(
                ZipEntry(name: VaultBackupManifest.fileName, data: manifestData, modificationDate: now)
            )

            let dayStamp = Self.dayStamp(for: now)
            return VaultBackupBundle(
                zipData: ZipArchive.build(entries: allEntries),
                suggestedFileName: "wine-vault-backup-\(dayStamp).zip",
                manifest: manifest
            )
        }
    }

    // MARK: - Restore

    public func restoreBackup(from zipData: Data, strategy: BackupRestoreStrategy) async throws
        -> BackupRestoreSummary {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("wine-vault-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: staging) }

        let staged = try Self.validateAndExtract(zipData, into: staging)

        return try await coordinator.withExclusiveAccess {
            try await self.commitRestore(staged, strategy: strategy)
        }
    }

    /// Validates the archive completely and stages its contents in `staging`
    /// without touching the live vault.
    nonisolated static func validateAndExtract(_ zipData: Data, into staging: URL) throws -> StagedRestore {
        let entries = try readArchive(zipData)
        let manifest = try validatedManifest(for: entries)
        try ZipArchive.extract(zipData, to: staging)
        let database = try migratedStagedDatabase(in: staging)
        let bottles = try stagedBottles(in: database)
        let quotes = try stagedQuotes(in: database)
        try stagedPhotosExist(referencedBy: bottles, in: staging)
        return StagedRestore(
            stagingDirectory: staging,
            manifest: manifest,
            bottles: bottles,
            quotes: quotes
        )
    }

    private nonisolated static func readArchive(_ zipData: Data) throws -> [ZipEntry] {
        do {
            return try ZipArchive.read(zipData)
        } catch let error as ZipError {
            switch error {
            case .checksumMismatch(let name): throw BackupError.checksumMismatch(name)
            case .unsafeEntryPath(let name): throw BackupError.unsafeArchivePath(name)
            case .malformed, .encryptedEntry, .unsupportedCompression, .entryTooLarge, .duplicateEntry:
                throw BackupError.malformedArchive
            }
        }
    }

    /// Manifest presence, versions, checksums, and exact entry-set checks.
    private nonisolated static func validatedManifest(for entries: [ZipEntry]) throws
        -> VaultBackupManifest {
        let byName = Dictionary(entries.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        guard entries.count == Set(entries.map(\.name)).count else {
            throw BackupError.unexpectedEntry("duplicate-entry")
        }
        guard let manifestEntry = byName[VaultBackupManifest.fileName] else {
            throw BackupError.missingManifest
        }
        let manifest: VaultBackupManifest
        do {
            manifest = try JSONDecoder.backupStyle.decode(
                VaultBackupManifest.self, from: manifestEntry.data
            )
        } catch {
            throw BackupError.invalidManifest
        }
        guard manifest.formatVersion == VaultBackupManifest.currentFormatVersion else {
            throw BackupError.unsupportedFormatVersion(manifest.formatVersion)
        }
        guard manifest.schemaVersion <= DatabaseSchema.currentVersion else {
            throw BackupError.unsupportedSchemaVersion(manifest.schemaVersion)
        }
        guard byName["vault.sqlite"] != nil else {
            throw BackupError.missingEntry("vault.sqlite")
        }
        for (path, digest) in manifest.checksums {
            guard let entry = byName[path] else { throw BackupError.missingEntry(path) }
            guard SHA256.hexDigest(entry.data) == digest else {
                throw BackupError.checksumMismatch(path)
            }
        }
        // Exact entry set: nothing outside the manifest may ride along.
        guard entries.allSatisfy({
            $0.name == VaultBackupManifest.fileName || manifest.checksums[$0.name] != nil
        }) else {
            throw BackupError.unexpectedEntry("undeclared-entry")
        }
        return manifest
    }

    private nonisolated static func migratedStagedDatabase(in staging: URL) throws
        -> DatabaseQueue {
        let url = staging.appendingPathComponent("vault.sqlite")
        let database: DatabaseQueue
        do {
            database = try DatabaseQueue(path: url.path)
        } catch {
            throw BackupError.databaseNotMigratable
        }
        do {
            try DatabaseSchema.migrator().migrate(database)
        } catch {
            throw BackupError.databaseNotMigratable
        }
        return database
    }

    private nonisolated static func stagedBottles(in database: DatabaseQueue) throws -> [Bottle] {
        try database.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM bottles ORDER BY name, id").map(decodeBottle)
        }
    }

    private nonisolated static func stagedQuotes(in database: DatabaseQueue) throws
        -> [ValuationQuote] {
        try database.read { db in
            try Row.fetchAll(
                db,
                sql: "SELECT * FROM valuationQuotes ORDER BY bottleID, quoteDate, id"
            ).map(decodeQuote)
        }
    }

    private nonisolated static func stagedPhotosExist(
        referencedBy bottles: [Bottle],
        in staging: URL
    ) throws {
        for bottle in bottles {
            for reference in bottle.photos {
                let photoURL = staging.appendingPathComponent(reference.path)
                var isRegularFile = false
                if FileManager.default.fileExists(atPath: photoURL.path) {
                    isRegularFile = try PhotoStore.isPlainFile(photoURL)
                }
                guard isRegularFile else {
                    throw BackupError.photoMissingFromArchive(reference)
                }
            }
        }
    }

    struct StagedRestore: Sendable {
        let stagingDirectory: URL
        let manifest: VaultBackupManifest
        let bottles: [Bottle]
        let quotes: [ValuationQuote]
    }

    /// Commits a fully-validated restore; only called under exclusive access.
    private func commitRestore(
        _ staged: StagedRestore,
        strategy: BackupRestoreStrategy
    ) async throws -> BackupRestoreSummary {
        let photosDirectory = try await photos.photosDirectoryURL()

        // 1. Stage incoming photo bytes as hidden temporary files so no
        //    live photo is mutated before the database transaction commits.
        let stagedPhotos = try await stageIncomingPhotos(of: staged, into: photosDirectory)

        // 2. Apply rows in one database transaction.
        var summary: BackupRestoreSummary
        do {
            summary = try await repository.applyRestoredRows(
                bottles: staged.bottles,
                quotes: staged.quotes,
                strategy: strategy
            )
        } catch {
            for stagedPhoto in stagedPhotos {
                try? FileManager.default.removeItem(at: stagedPhoto.stagedURL)
            }
            throw error
        }

        // 3. Move staged photos into place.
        try await moveStagedPhotos(
            stagedPhotos,
            into: photosDirectory,
            strategy: strategy,
            summary: &summary
        )

        if strategy == .replace {
            let references = try await repository.photoReferencesWithoutCoordination()
            _ = try await photos.garbageCollectWithoutCoordination(keeping: references)
        }
        return summary
    }

    private struct StagedPhoto: Sendable {
        let finalName: String
        let stagedURL: URL
    }

    private func stageIncomingPhotos(
        of staged: StagedRestore,
        into photosDirectory: URL
    ) async throws -> [StagedPhoto] {
        let fileManager = FileManager.default
        var stagedPhotos: [StagedPhoto] = []
        var incomingPhotoNames = Set<String>()
        for bottle in staged.bottles {
            for reference in bottle.photos where !incomingPhotoNames.contains(reference.fileName) {
                incomingPhotoNames.insert(reference.fileName)
                let source = staged.stagingDirectory.appendingPathComponent(reference.path)
                let stagedURL = photosDirectory.appendingPathComponent(
                    ".restore-\(UUID().uuidString)-\(reference.fileName)"
                )
                try fileManager.copyItem(at: source, to: stagedURL)
                stagedPhotos.append(StagedPhoto(finalName: reference.fileName, stagedURL: stagedURL))
            }
        }
        return stagedPhotos
    }

    private func moveStagedPhotos(
        _ stagedPhotos: [StagedPhoto],
        into photosDirectory: URL,
        strategy: BackupRestoreStrategy,
        summary: inout BackupRestoreSummary
    ) async throws {
        let fileManager = FileManager.default
        for stagedPhoto in stagedPhotos {
            let finalURL = photosDirectory.appendingPathComponent(stagedPhoto.finalName)
            do {
                if fileManager.fileExists(atPath: finalURL.path) {
                    if strategy == .merge {
                        summary.photoConflictsSkipped += 1
                        try fileManager.removeItem(at: stagedPhoto.stagedURL)
                        continue
                    }
                    try fileManager.removeItem(at: finalURL)
                }
                try fileManager.moveItem(at: stagedPhoto.stagedURL, to: finalURL)
                summary.photosRestored += 1
            } catch {
                summary.photosPending += 1
            }
        }
    }

    public nonisolated static func dayStamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.timeZone = .gmt
        return formatter.string(from: date)
    }
}
