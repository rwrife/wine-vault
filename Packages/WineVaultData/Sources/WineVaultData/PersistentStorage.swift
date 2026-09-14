import Foundation
import GRDB

struct PersistentStorage {
    let root: URL
    let canonicalRoot: URL
    let rootIdentity: FileIdentity
    let database: DatabaseQueue
    let databaseIdentity: FileIdentity
}

extension SQLiteBottleRepository {
    static func makePersistentStorage(databaseURL: URL) throws -> PersistentStorage {
        let root = databaseURL.deletingLastPathComponent().standardizedFileURL
        guard try PhotoStore.isPlainDirectory(root),
              try isSafeDatabaseFile(databaseURL) else {
            throw RepositoryError.unsafeStorageLocation
        }
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let rootIdentity = try FileIdentity.capture(root, type: .typeDirectory)
        let database = try DatabaseQueue(
            path: databaseURL.path,
            configuration: DatabaseSchema.configuration()
        )
        try DatabaseSchema.migrator().migrate(database)
        guard try PhotoStore.isPlainDirectory(root),
              root.resolvingSymlinksInPath().standardizedFileURL.path == canonicalRoot.path,
              try FileIdentity.capture(root, type: .typeDirectory) == rootIdentity,
              try isSafeDatabaseFile(databaseURL) else {
            throw RepositoryError.unsafeStorageLocation
        }
        return PersistentStorage(
            root: root,
            canonicalRoot: canonicalRoot,
            rootIdentity: rootIdentity,
            database: database,
            databaseIdentity: try FileIdentity.capture(databaseURL, type: .typeRegular)
        )
    }
}
