import Foundation
import WineVaultData

/// User-facing explanations of restore failures, each making clear the
/// existing collection was left intact.
enum BackupErrorText {
    static func describe(_ error: BackupError) -> String {
        switch error {
        case .missingManifest:
            return "That file is not a Wine Vault backup (no manifest). Your current collection is untouched."
        case .invalidManifest:
            return "The backup manifest could not be read. Your current collection is untouched."
        case .unsupportedFormatVersion(let version):
            return "That backup uses a newer format (v\(version)) this app cannot open. Your current collection is untouched."
        case .unsupportedSchemaVersion(let version):
            return "That backup comes from a newer app version (schema v\(version)). Update Wine Vault first; your current collection is untouched."
        case .checksumMismatch(let path):
            return "The backup file is corrupted (\(path) failed its checksum). Your current collection is untouched."
        case .missingEntry(let path):
            return "The backup is missing \(path). Your current collection is untouched."
        case .unexpectedEntry:
            return "The backup contains unexpected files. Your current collection is untouched."
        case .databaseNotMigratable:
            return "The backed-up database could not be opened. Your current collection is untouched."
        case .photoMissingFromArchive(let reference):
            return "A photo the backup expects is missing (\(reference.fileName)). Your current collection is untouched."
        case .unsafeArchivePath:
            return "The backup contains unsafe paths and was rejected. Your current collection is untouched."
        case .malformedArchive:
            return "That file could not be read as a ZIP archive. Your current collection is untouched."
        }
    }
}
