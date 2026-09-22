import Foundation
import GRDB
import WineVaultDomain

// Restore row-apply for backups (issue #6), split out to keep files short.

extension SQLiteBottleRepository {
    /// Applies validated restore rows in a single transaction. Caller must
    /// hold exclusive access. `merge` inserts or replaces same-identifier
    /// records and keeps local-only ones; `replace` clears every bottle and
    /// quote first.
    func applyRestoredRows(
        bottles: [Bottle],
        quotes: [ValuationQuote],
        strategy: BackupRestoreStrategy
    ) throws -> BackupRestoreSummary {
        try validateStorageLocation()
        var summary = BackupRestoreSummary()
        try database.write { db in
            if strategy == .replace {
                try db.execute(sql: "DELETE FROM valuationQuotes")
                try db.execute(sql: "DELETE FROM bottles")
            }
            let existingBottleIDs = Set(
                try String.fetchAll(db, sql: "SELECT id FROM bottles")
            )
            let existingQuoteIDs = Set(
                try String.fetchAll(db, sql: "SELECT id FROM valuationQuotes")
            )
            for bottle in bottles {
                if existingBottleIDs.contains(bottle.id.uuidString) {
                    try Self.updateRow(bottle, in: db)
                    summary.bottlesReplaced += 1
                } else {
                    try insert(bottle, in: db)
                    summary.bottlesInserted += 1
                }
            }
            let knownBottleIDs = Set(
                try String.fetchAll(db, sql: "SELECT id FROM bottles")
            )
            for quote in quotes {
                // Orphan quotes (bottle absent after merge) are skipped
                // rather than inserting a cascade-violating row.
                guard knownBottleIDs.contains(quote.bottleID.uuidString) else { continue }
                if existingQuoteIDs.contains(quote.id.uuidString) { continue }
                try db.execute(
                    sql: """
                        INSERT INTO valuationQuotes
                            (id, bottleID, quoteDate, amount, currency, source, retrievedAt, query)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        quote.id.uuidString, quote.bottleID.uuidString,
                        quote.quoteDate.timeIntervalSince1970,
                        NSDecimalNumber(decimal: quote.amount).stringValue,
                        quote.currency, quote.source,
                        quote.retrievedAt.timeIntervalSince1970,
                        quote.query,
                    ]
                )
                summary.quotesInserted += 1
            }
        }
        return summary
    }

    /// Plain-SQL row update that stays inside the caller's transaction.
    private static func updateRow(_ bottle: Bottle, in db: Database) throws {
        try db.execute(
            sql: """
                UPDATE bottles SET
                    name = ?, producer = ?, vintage = ?, region = ?, grape = ?,
                    quantity = ?, storageLocation = ?, tags = ?, drinkBy = ?,
                    photos = ?, notes = ?
                WHERE id = ?
                """,
            arguments: [
                bottle.name, bottle.producer, bottle.vintage, bottle.region,
                bottle.grape, bottle.quantity, bottle.storageLocation,
                try encode(bottle.tags),
                bottle.drinkBy?.timeIntervalSince1970,
                try encode(bottle.photos), bottle.notes,
                bottle.id.uuidString,
            ]
        )
    }
}
