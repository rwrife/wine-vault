import Foundation

/// A dated estimate with enough provenance to explain how it was obtained.
public struct ValuationQuote: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let bottleID: UUID
    public let quoteDate: Date
    public let amount: Decimal
    public let currency: String
    public let source: String
    public let retrievedAt: Date
    public let query: String

    public init(
        id: UUID = UUID(),
        bottleID: UUID,
        quoteDate: Date,
        amount: Decimal,
        currency: String,
        source: String,
        retrievedAt: Date,
        query: String
    ) throws {
        guard !amount.isNaN, amount >= 0 else {
            throw DomainValidationError.invalidQuoteAmount
        }
        let provenance = [currency, source, query]
        guard provenance.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw DomainValidationError.missingQuoteProvenance
        }
        self.id = id
        self.bottleID = bottleID
        self.quoteDate = quoteDate
        self.amount = amount
        self.currency = currency
        self.source = source
        self.retrievedAt = retrievedAt
        self.query = query
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            bottleID: container.decode(UUID.self, forKey: .bottleID),
            quoteDate: container.decode(Date.self, forKey: .quoteDate),
            amount: container.decode(Decimal.self, forKey: .amount),
            currency: container.decode(String.self, forKey: .currency),
            source: container.decode(String.self, forKey: .source),
            retrievedAt: container.decode(Date.self, forKey: .retrievedAt),
            query: container.decode(String.self, forKey: .query)
        )
    }
}
