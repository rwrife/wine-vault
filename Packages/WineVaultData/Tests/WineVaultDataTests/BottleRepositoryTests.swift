import Foundation
import GRDB
import XCTest

@testable import WineVaultData
import WineVaultDomain

final class BottleRepositoryTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDownWithError() throws {
        for directory in temporaryDirectories {
            try FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
    }

    func testCRUDRoundTripsUnicodeAndEmojiAfterReopen() async throws {
        let databaseURL = try makeTemporaryDirectory().appendingPathComponent("vault.sqlite")
        let id = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let original = try Bottle(
            id: id,
            name: "Cuvée 🍷",
            producer: "Château Étoile",
            vintage: 2020,
            region: "Dão",
            grape: "Touriga Nacional",
            quantity: 2,
            storageLocation: "Étagère №1",
            tags: ["fête 🎉", "dîner"],
            drinkBy: Date(timeIntervalSince1970: 1_900_000_000),
            photos: [try PhotoReference("photos/étiquette-🍇.jpg")],
            notes: "Très bon — café ☕️"
        )
        var repository: SQLiteBottleRepository? = try SQLiteBottleRepository(databaseURL: databaseURL)
        try await repository?.create(original)
        let initiallyRead = try await repository?.bottle(id: id)
        XCTAssertEqual(initiallyRead, original)

        var updated = original
        try updated.setQuantity(7)
        updated.notes = "Mis à jour ✨"
        try await repository?.update(updated)
        let allBottles = try await repository?.bottles()
        XCTAssertEqual(allBottles, [updated])

        repository = nil
        let reopened = try SQLiteBottleRepository(databaseURL: databaseURL)
        let reopenedBottle = try await reopened.bottle(id: id)
        XCTAssertEqual(reopenedBottle, updated)
        try await reopened.deleteBottle(id: id)
        let deletedBottle = try await reopened.bottle(id: id)
        XCTAssertNil(deletedBottle)
    }

    func testDuplicateCreateAndMissingUpdateFailMeaningfully() async throws {
        let repository = try SQLiteBottleRepository(inMemory: true)
        let bottle = try Bottle(name: "One", quantity: 1, storageLocation: "Rack")
        try await repository.create(bottle)

        await XCTAssertThrowsErrorAsync(try await repository.create(bottle)) { error in
            XCTAssertEqual(error as? RepositoryError, .duplicateBottle(bottle.id))
        }
        let missing = try Bottle(name: "Missing", quantity: 1, storageLocation: "Rack")
        await XCTAssertThrowsErrorAsync(try await repository.update(missing)) { error in
            XCTAssertEqual(error as? RepositoryError, .bottleNotFound(missing.id))
        }
    }

    func testQuotesRoundTripExactlyAndCascadeWhenBottleDeleted() async throws {
        let repository = try SQLiteBottleRepository(inMemory: true)
        let bottle = try Bottle(name: "Quoted", quantity: 1, storageLocation: "Rack")
        try await repository.create(bottle)
        let quote = try ValuationQuote(
            bottleID: bottle.id,
            quoteDate: Date(timeIntervalSince1970: 1_800_000_000),
            amount: Decimal(string: "123456789.123456789")!,
            currency: "JPY",
            source: "鑑定士 🗾",
            retrievedAt: Date(timeIntervalSince1970: 1_800_000_100),
            query: "葡萄酒 🍷"
        )

        try await repository.createQuote(quote)
        let savedQuotes = try await repository.quotes(bottleID: bottle.id)
        XCTAssertEqual(savedQuotes, [quote])
        try await repository.deleteBottle(id: bottle.id)
        let deletedQuotes = try await repository.quotes(bottleID: bottle.id)
        XCTAssertEqual(deletedQuotes, [])
    }

    func testDatabaseRejectsZeroAndNegativeQuantities() async throws {
        let repository = try SQLiteBottleRepository(inMemory: true)
        for quantity in [0, -1] {
            await XCTAssertThrowsErrorAsync(
                try await repository.unsafeTestInsert(quantity: quantity)
            ) { _ in }
        }
    }

    func testStoredQuoteValuesAreRevalidatedOnRead() async throws {
        let repository = try SQLiteBottleRepository(inMemory: true)
        let bottle = try Bottle(name: "Quoted", quantity: 1, storageLocation: "Rack")
        try await repository.create(bottle)
        try await repository.unsafeTestInsertQuote(bottleID: bottle.id, amount: "-1", source: "")

        await XCTAssertThrowsErrorAsync(try await repository.quotes(bottleID: bottle.id)) { error in
            XCTAssertEqual(error as? RepositoryError, .invalidStoredValue)
        }
    }

    func testVersionOneDatabaseMigratesForwardAndPreservesBottle() async throws {
        let databaseURL = try makeTemporaryDirectory().appendingPathComponent("legacy.sqlite")
        try DatabaseSchema.createVersionOneDatabase(at: databaseURL)
        let legacyID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let legacyQueue = try DatabaseQueue(path: databaseURL.path)
        try await legacyQueue.write { database in
            try database.execute(
                sql: """
                    INSERT INTO bottles
                        (id, name, producer, vintage, region, grape, quantity,
                         storageLocation, tags, drinkBy, photos)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    legacyID.uuidString, "Héritage 🍷", "Étoile", 1999, "Dão",
                    "Touriga", 2, "Cave", "[\"ancien\"]", nil, "[]",
                ]
            )
        }

        let migrated = try SQLiteBottleRepository(databaseURL: databaseURL)
        let bottle = try await migrated.bottle(id: legacyID)
        XCTAssertEqual(bottle?.name, "Héritage 🍷")
        XCTAssertNil(bottle?.notes)
        let migrations = try await migrated.appliedMigrationIdentifiers()
        XCTAssertEqual(migrations, ["v1", "v2"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WineVaultDataTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectories.append(directory)
        return directory
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void
) async {
    do {
        _ = try await expression()
        XCTFail("Expected expression to throw")
    } catch {
        errorHandler(error)
    }
}
