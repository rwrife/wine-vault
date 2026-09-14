import Foundation
import GRDB

public enum DatabaseSchema {
    public static let currentVersion = 2

    static func configuration() -> Configuration {
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return configuration
    }

    static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { database in
            try database.create(table: "bottles") { table in
                table.column("id", .text).primaryKey()
                table.column("name", .text).notNull()
                table.column("producer", .text)
                table.column("vintage", .integer)
                table.column("region", .text)
                table.column("grape", .text)
                table.column("quantity", .integer).notNull()
                table.column("storageLocation", .text).notNull()
                table.column("tags", .text).notNull()
                table.column("drinkBy", .double)
                table.column("photos", .text).notNull()
                table.check(sql: "quantity > 0")
            }
        }
        migrator.registerMigration("v2") { database in
            try database.alter(table: "bottles") { table in
                table.add(column: "notes", .text)
            }
            try database.create(table: "valuationQuotes") { table in
                table.column("id", .text).primaryKey()
                table.column("bottleID", .text)
                    .notNull()
                    .references("bottles", onDelete: .cascade)
                table.column("quoteDate", .double).notNull()
                table.column("amount", .text).notNull()
                table.column("currency", .text).notNull()
                table.column("source", .text).notNull()
                table.column("retrievedAt", .double).notNull()
                table.column("query", .text).notNull()
            }
            try database.create(
                index: "valuationQuotes_on_bottleID",
                on: "valuationQuotes",
                columns: ["bottleID"]
            )
        }
        return migrator
    }

    /// Test/support utility that produces a genuine old schema for migration checks.
    public static func createVersionOneDatabase(at url: URL) throws {
        let queue = try DatabaseQueue(path: url.path, configuration: configuration())
        try migrator().migrate(queue, upTo: "v1")
    }
}
