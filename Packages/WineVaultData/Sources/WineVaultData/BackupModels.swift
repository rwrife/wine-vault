// Backup domain models (issue #6): the ZIP manifest, restore strategies,
// and typed errors. Split out of `BackupService` so each file stays
// reviewable.

import Foundation
import WineVaultDomain

/// Versioned manifest embedded in every vault ZIP backup.
public struct VaultBackupManifest: Codable, Equatable, Sendable {
    /// Backup format version (not the database schema version).
    public static let currentFormatVersion = 1
    public static let fileName = "manifest.json"

    public let formatVersion: Int
    /// `DatabaseSchema.currentVersion` the SQLite snapshot was taken at.
    public let schemaVersion: Int
    public let appVersion: String
    public let createdAt: Date
    /// sha256 hex digests keyed by ZIP-relative path ("vault.sqlite",
    /// "photos/<file>"), excluding the manifest itself.
    public let checksums: [String: String]

    public init(
        formatVersion: Int,
        schemaVersion: Int,
        appVersion: String,
        createdAt: Date,
        checksums: [String: String]
    ) {
        self.formatVersion = formatVersion
        self.schemaVersion = schemaVersion
        self.appVersion = appVersion
        self.createdAt = createdAt
        self.checksums = checksums
    }
}

public enum BackupError: Error, Equatable, Sendable {
    case missingManifest
    case invalidManifest
    case unsupportedFormatVersion(Int)
    case unsupportedSchemaVersion(Int)
    case checksumMismatch(String)
    case missingEntry(String)
    case unexpectedEntry(String)
    case databaseNotMigratable
    case photoMissingFromArchive(PhotoReference)
    case unsafeArchivePath(String)
    case malformedArchive
}

public enum BackupRestoreStrategy: Equatable, Sendable {
    /// Incoming bottles/quotes are inserted or replace same-identifier
    /// records; local-only records are kept. Existing photo files win any
    /// name conflict and are reported, never overwritten.
    case merge
    /// Every local bottle, quote, and photo is removed before the archive
    /// is applied.
    case replace
}

public struct BackupRestoreSummary: Equatable, Sendable {
    public init(
        bottlesInserted: Int = 0,
        bottlesReplaced: Int = 0,
        quotesInserted: Int = 0,
        photosRestored: Int = 0,
        photoConflictsSkipped: Int = 0,
        photosPending: Int = 0
    ) {
        self.bottlesInserted = bottlesInserted
        self.bottlesReplaced = bottlesReplaced
        self.quotesInserted = quotesInserted
        self.photosRestored = photosRestored
        self.photoConflictsSkipped = photoConflictsSkipped
        self.photosPending = photosPending
    }

    public var bottlesInserted = 0
    public var bottlesReplaced = 0
    public var quotesInserted = 0
    public var photosRestored = 0
    /// Photo files that already existed with different content and were
    /// kept (merge strategy).
    public var photoConflictsSkipped = 0
    /// Photo files whose final move failed after data rows were committed;
    /// `garbageCollectOrphanPhotos()` reconciles the leftovers.
    public var photosPending = 0
}

/// A ZIP backup ready for the share sheet.
public struct VaultBackupBundle: Sendable {
    public let zipData: Data
    public let suggestedFileName: String
    public let manifest: VaultBackupManifest

    public init(zipData: Data, suggestedFileName: String, manifest: VaultBackupManifest) {
        self.zipData = zipData
        self.suggestedFileName = suggestedFileName
        self.manifest = manifest
    }

    public var createdDateDescription: String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: manifest.createdAt)
    }
}

extension JSONEncoder {
    /// Shared encoder for on-disk manifests with stable formatting.
    public static var backupStyle: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }
}

extension JSONDecoder {
    public static var backupStyle: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
