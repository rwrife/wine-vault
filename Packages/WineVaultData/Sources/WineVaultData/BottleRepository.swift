import Foundation
import GRDB
import WineVaultDomain

public enum RepositoryError: Error, Equatable, Sendable {
    case duplicateBottle(UUID)
    case bottleNotFound(UUID)
    case invalidStoredValue
    case unsafeStorageLocation
    case missingPhotoReference(PhotoReference)
}

public protocol BottleRepository: Sendable {
    func create(_ bottle: Bottle) async throws
    func bottle(id: UUID) async throws -> Bottle?
    func bottles() async throws -> [Bottle]
    func update(_ bottle: Bottle) async throws
    func deleteBottle(id: UUID) async throws
    func createQuote(_ quote: ValuationQuote) async throws
    func quotes(bottleID: UUID) async throws -> [ValuationQuote]
    func deleteQuote(id: UUID) async throws
    func allQuotes() async throws -> [ValuationQuote]
}

public actor SQLiteBottleRepository: BottleRepository {
    let database: DatabaseQueue
    let coordinator: DataAccessCoordinator
    let guardedRootDirectory: URL?
    let canonicalRootDirectory: URL?
    let rootIdentity: FileIdentity?
    let databaseURL: URL?
    let databaseIdentity: FileIdentity?
    let photoStore: PhotoStore?

    public init(databaseURL: URL) throws {
        let storage = try Self.makePersistentStorage(databaseURL: databaseURL)
        coordinator = DataAccessCoordinator()
        guardedRootDirectory = storage.root
        canonicalRootDirectory = storage.canonicalRoot
        rootIdentity = storage.rootIdentity
        database = storage.database
        self.databaseURL = databaseURL.standardizedFileURL
        databaseIdentity = storage.databaseIdentity
        photoStore = nil
    }

    public init(inMemory: Bool) throws {
        precondition(inMemory, "Use init(databaseURL:) for persistent repositories")
        coordinator = DataAccessCoordinator()
        guardedRootDirectory = nil
        canonicalRootDirectory = nil
        rootIdentity = nil
        databaseURL = nil
        databaseIdentity = nil
        photoStore = nil
        database = try DatabaseQueue(configuration: DatabaseSchema.configuration())
        try DatabaseSchema.migrator().migrate(database)
    }

    init(
        databaseURL: URL,
        coordinator: DataAccessCoordinator,
        photoStore: PhotoStore
    ) throws {
        let storage = try Self.makePersistentStorage(databaseURL: databaseURL)
        self.coordinator = coordinator
        guardedRootDirectory = storage.root
        canonicalRootDirectory = storage.canonicalRoot
        rootIdentity = storage.rootIdentity
        database = storage.database
        self.databaseURL = databaseURL.standardizedFileURL
        databaseIdentity = storage.databaseIdentity
        self.photoStore = photoStore
    }

    public func create(_ bottle: Bottle) async throws {
        try await coordinator.withExclusiveAccess {
            try await self.validatePhotoReferencesWithoutCoordination(bottle.photos)
            try await self.createWithoutCoordination(bottle)
        }
    }

    public func bottle(id: UUID) async throws -> Bottle? {
        try await coordinator.withExclusiveAccess {
            try await self.bottleWithoutCoordination(id: id)
        }
    }

    public func bottles() async throws -> [Bottle] {
        try await coordinator.withExclusiveAccess {
            try await self.bottlesWithoutCoordination()
        }
    }

    public func update(_ bottle: Bottle) async throws {
        try await coordinator.withExclusiveAccess {
            try await self.validatePhotoReferencesWithoutCoordination(bottle.photos)
            try await self.updateWithoutCoordination(bottle)
        }
    }

    public func deleteBottle(id: UUID) async throws {
        try await coordinator.withExclusiveAccess {
            try await self.deleteBottleWithoutCoordination(id: id)
        }
    }

    func createWithoutCoordination(_ bottle: Bottle) throws {
        try validateStorageLocation()
        try database.write { database in
            let alreadyExists = try Bool.fetchOne(
                database,
                sql: "SELECT EXISTS (SELECT 1 FROM bottles WHERE id = ?)",
                arguments: [bottle.id.uuidString]
            ) ?? false
            guard !alreadyExists else {
                throw RepositoryError.duplicateBottle(bottle.id)
            }
            try insert(bottle, in: database)
        }
    }

    func bottleWithoutCoordination(id: UUID) throws -> Bottle? {
        try validateStorageLocation()
        return try database.read { database in
            try Row.fetchOne(
                database,
                sql: "SELECT * FROM bottles WHERE id = ?",
                arguments: [id.uuidString]
            ).map(decodeBottle)
        }
    }

    func bottlesWithoutCoordination() throws -> [Bottle] {
        try validateStorageLocation()
        return try database.read { database in
            try Row.fetchAll(database, sql: "SELECT * FROM bottles ORDER BY name, id")
                .map(decodeBottle)
        }
    }

    func updateWithoutCoordination(_ bottle: Bottle) throws {
        try validateStorageLocation()
        try database.write { database in
            let tags = try encode(bottle.tags)
            let photos = try encode(bottle.photos)
            try database.execute(
                sql: """
                    UPDATE bottles SET
                        name = ?, producer = ?, vintage = ?, region = ?, grape = ?,
                        quantity = ?, storageLocation = ?, tags = ?, drinkBy = ?,
                        photos = ?, notes = ?
                    WHERE id = ?
                    """,
                arguments: [
                    bottle.name, bottle.producer, bottle.vintage, bottle.region,
                    bottle.grape, bottle.quantity, bottle.storageLocation, tags,
                    bottle.drinkBy?.timeIntervalSince1970, photos, bottle.notes,
                    bottle.id.uuidString,
                ]
            )
            guard database.changesCount == 1 else {
                throw RepositoryError.bottleNotFound(bottle.id)
            }
        }
    }

    func deleteBottleWithoutCoordination(id: UUID) throws {
        try validateStorageLocation()
        try database.write { database in
            try database.execute(
                sql: "DELETE FROM bottles WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    func photoReferencesWithoutCoordination() throws -> Set<PhotoReference> {
        try validateStorageLocation()
        return try database.read { database in
            let encodedPhotos = try String.fetchAll(database, sql: "SELECT photos FROM bottles")
            return try encodedPhotos.reduce(into: Set<PhotoReference>()) { references, encoded in
                references.formUnion(try decode([PhotoReference].self, from: encoded))
            }
        }
    }

    func validatePhotoReferencesWithoutCoordination(
        _ references: [PhotoReference]
    ) async throws {
        guard let photoStore else { return }
        for reference in references {
            do {
                try await photoStore.validateWithoutCoordination(reference)
            } catch PhotoStoreError.photoNotFound {
                throw RepositoryError.missingPhotoReference(reference)
            }
        }
    }

    func appliedMigrationIdentifiers() throws -> [String] {
        try validateStorageLocation()
        return try database.read { database in
            try DatabaseSchema.migrator().appliedMigrations(database)
        }
    }

    func unsafeTestInsert(quantity: Int) throws {
        try validateStorageLocation()
        try database.write { database in
            try database.execute(
                sql: """
                    INSERT INTO bottles
                        (id, name, quantity, storageLocation, tags, photos)
                    VALUES (?, ?, ?, ?, '[]', '[]')
                    """,
                arguments: [UUID().uuidString, "Invalid", quantity, "Rack"]
            )
        }
    }

    func validateStorageLocation() throws {
        guard let guardedRootDirectory,
              let canonicalRootDirectory,
              let rootIdentity,
              let databaseURL,
              let databaseIdentity else { return }
        guard try PhotoStore.isPlainDirectory(guardedRootDirectory),
              guardedRootDirectory.resolvingSymlinksInPath().standardizedFileURL.path
                == canonicalRootDirectory.path,
              try FileIdentity.capture(guardedRootDirectory, type: .typeDirectory) == rootIdentity,
              try Self.isSafeDatabaseFile(databaseURL),
              try FileIdentity.capture(databaseURL, type: .typeRegular) == databaseIdentity else {
            throw RepositoryError.unsafeStorageLocation
        }
    }

    static func isSafeDatabaseFile(_ databaseURL: URL) throws -> Bool {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: databaseURL.path)
            return attributes[.type] as? FileAttributeType == .typeRegular
        } catch let error as CocoaError
            where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return true
        }
    }
}

func insert(_ bottle: Bottle, in database: Database) throws {
    try database.execute(
        sql: """
            INSERT INTO bottles
                (id, name, producer, vintage, region, grape, quantity,
                 storageLocation, tags, drinkBy, photos, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
        arguments: [
            bottle.id.uuidString, bottle.name, bottle.producer, bottle.vintage,
            bottle.region, bottle.grape, bottle.quantity, bottle.storageLocation,
            try encode(bottle.tags), bottle.drinkBy?.timeIntervalSince1970,
            try encode(bottle.photos), bottle.notes,
        ]
    )
}

func decodeBottle(_ row: Row) throws -> Bottle {
    guard let id = UUID(uuidString: row["id"]) else {
        throw RepositoryError.invalidStoredValue
    }
    return try Bottle(
        id: id,
        name: row["name"],
        producer: row["producer"],
        vintage: row["vintage"],
        region: row["region"],
        grape: row["grape"],
        quantity: row["quantity"],
        storageLocation: row["storageLocation"],
        tags: try decode([String].self, from: row["tags"]),
        drinkBy: (row["drinkBy"] as Double?).map(Date.init(timeIntervalSince1970:)),
        photos: try decode([PhotoReference].self, from: row["photos"]),
        notes: row["notes"]
    )
}

func encode<T: Encodable>(_ value: T) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
        throw RepositoryError.invalidStoredValue
    }
    return string
}

func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
    guard let data = string.data(using: .utf8) else {
        throw RepositoryError.invalidStoredValue
    }
    return try JSONDecoder().decode(type, from: data)
}
