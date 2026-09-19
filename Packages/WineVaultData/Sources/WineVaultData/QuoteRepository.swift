import Foundation
import GRDB
import WineVaultDomain

// Valuation-quote persistence for SQLiteBottleRepository, split out from
// BottleRepository.swift to keep each file under the lint file-length limit.

extension SQLiteBottleRepository {
    public func createQuote(_ quote: ValuationQuote) async throws {
        try await coordinator.withExclusiveAccess {
            try await self.createQuoteWithoutCoordination(quote)
        }
    }

    public func quotes(bottleID: UUID) async throws -> [ValuationQuote] {
        try await coordinator.withExclusiveAccess {
            try await self.quotesWithoutCoordination(bottleID: bottleID)
        }
    }

    public func deleteQuote(id: UUID) async throws {
        try await coordinator.withExclusiveAccess {
            try await self.deleteQuoteWithoutCoordination(id: id)
        }
    }

    public func allQuotes() async throws -> [ValuationQuote] {
        try await coordinator.withExclusiveAccess {
            try await self.allQuotesWithoutCoordination()
        }
    }

    func createQuoteWithoutCoordination(_ quote: ValuationQuote) throws {
        try validateStorageLocation()
        try database.write { database in
            try database.execute(
                sql: """
                    INSERT INTO valuationQuotes
                        (id, bottleID, quoteDate, amount, currency, source, retrievedAt, query)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    quote.id.uuidString, quote.bottleID.uuidString,
                    quote.quoteDate.timeIntervalSince1970,
                    NSDecimalNumber(decimal: quote.amount).stringValue,
                    quote.currency, quote.source, quote.retrievedAt.timeIntervalSince1970,
                    quote.query,
                ]
            )
        }
    }

    func quotesWithoutCoordination(bottleID: UUID) throws -> [ValuationQuote] {
        try validateStorageLocation()
        return try database.read { database in
            try Row.fetchAll(
                database,
                sql: """
                    SELECT * FROM valuationQuotes
                    WHERE bottleID = ? ORDER BY quoteDate, id
                    """,
                arguments: [bottleID.uuidString]
            ).map(decodeQuote)
        }
    }

    func allQuotesWithoutCoordination() throws -> [ValuationQuote] {
        try validateStorageLocation()
        return try database.read { database in
            try Row.fetchAll(
                database,
                sql: "SELECT * FROM valuationQuotes ORDER BY bottleID, quoteDate, id"
            ).map(decodeQuote)
        }
    }

    func deleteQuoteWithoutCoordination(id: UUID) throws {
        try validateStorageLocation()
        try database.write { database in
            try database.execute(
                sql: "DELETE FROM valuationQuotes WHERE id = ?",
                arguments: [id.uuidString]
            )
        }
    }

    /// Test-only backdoor that bypasses `ValuationQuote` validation so tests
    /// can prove stored rows are re-validated on read. Never call from app code.
    func unsafeTestInsertQuote(bottleID: UUID, amount: String, source: String) throws {
        try validateStorageLocation()
        try database.write { database in
            try database.execute(
                sql: """
                    INSERT INTO valuationQuotes
                        (id, bottleID, quoteDate, amount, currency, source, retrievedAt, query)
                    VALUES (?, ?, 0, ?, 'USD', ?, 0, 'Wine')
                    """,
                arguments: [UUID().uuidString, bottleID.uuidString, amount, source]
            )
        }
    }
}

private func decodeQuote(_ row: Row) throws -> ValuationQuote {
    guard let id = UUID(uuidString: row["id"]),
          let bottleID = UUID(uuidString: row["bottleID"]),
          let amount = Decimal(string: row["amount"], locale: Locale(identifier: "en_US_POSIX")) else {
        throw RepositoryError.invalidStoredValue
    }
    do {
        return try ValuationQuote(
            id: id,
            bottleID: bottleID,
            quoteDate: Date(timeIntervalSince1970: row["quoteDate"]),
            amount: amount,
            currency: row["currency"],
            source: row["source"],
            retrievedAt: Date(timeIntervalSince1970: row["retrievedAt"]),
            query: row["query"]
        )
    } catch {
        throw RepositoryError.invalidStoredValue
    }
}
