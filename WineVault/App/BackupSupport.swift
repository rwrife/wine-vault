import Foundation
import WineVaultData
import WineVaultDomain

/// Seam over backup/restore so UI-test launches can inject an in-memory
/// implementation and never touch real archives.
protocol BackupServicing: Sendable {
    func createBackup(appVersion: String) async throws -> VaultBackupBundle
    func restoreBackup(from zipData: Data, strategy: BackupRestoreStrategy) async throws
        -> BackupRestoreSummary
}

/// Production backend: the live WineVaultDataStack.
struct StackBackupService: BackupServicing {
    let stack: WineVaultDataStack

    func createBackup(appVersion: String) async throws -> VaultBackupBundle {
        try await stack.createBackup(appVersion: appVersion)
    }

    func restoreBackup(from zipData: Data, strategy: BackupRestoreStrategy) async throws
        -> BackupRestoreSummary
    {
        try await stack.restoreBackup(from: zipData, strategy: strategy)
    }
}

/// In-memory backend for `--ui-testing` launches: the archive is a plain
/// JSON stand-in, so the whole settings/backup flow runs deterministically
/// without any real ZIP, database, or share sheet.
struct InertBackupService: BackupServicing {
    actor Store {
        private(set) var archives: [String: Data] = [:]

        func put(name: String, data: Data) {
            archives[name] = data
        }
    }

    private static let store = Store()
    nonisolated static let uiTestArchiveMarker = Data("inert-backup".utf8)
    private static let marker = uiTestArchiveMarker

    func createBackup(appVersion: String) async throws -> VaultBackupBundle {
        let stamp = WineVaultDataStack.dayStamp(for: Date())
        let name = "wine-vault-backup-\(stamp).zip"
        var payload = Self.marker
        payload.append(Data(appVersion.utf8))
        await Self.store.put(name: name, data: payload)
        let manifest = VaultBackupManifest(
            formatVersion: VaultBackupManifest.currentFormatVersion,
            schemaVersion: DatabaseSchema.currentVersion,
            appVersion: appVersion,
            createdAt: Date(),
            checksums: ["vault.sqlite": String(repeating: "0", count: 64)]
        )
        return VaultBackupBundle(zipData: payload, suggestedFileName: name, manifest: manifest)
    }

    func restoreBackup(from zipData: Data, strategy: BackupRestoreStrategy) async throws
        -> BackupRestoreSummary
    {
        guard zipData.starts(with: Self.marker) else {
            throw BackupError.malformedArchive
        }
        return BackupRestoreSummary(
            bottlesInserted: 1, bottlesReplaced: 0, quotesInserted: 0,
            photosRestored: 0, photoConflictsSkipped: 0, photosPending: 0
        )
    }
}
