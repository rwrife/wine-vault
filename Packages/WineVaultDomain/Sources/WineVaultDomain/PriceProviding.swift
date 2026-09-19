import Foundation

// The Domain layer stays intentionally dependency-free: no networking,
// storage, or UI types. `PriceProviding` is the seam that lets the app
// inject a network-backed implementation while tests and UI tests use the
// deterministic `FixturePriceProvider` below.

/// A user-initiated lookup request built from a bottle's identity.
public struct PriceQuery: Codable, Equatable, Sendable {
    public let text: String

    public init(text: String) throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DomainValidationError.emptyPriceQuery
        }
        self.text = trimmed
    }
}

/// One possible match returned by a price provider. Candidates are never
/// applied automatically — the user must explicitly confirm one before it
/// is stored as a `ValuationQuote`.
public struct PriceCandidate: Codable, Equatable, Sendable {
    public let amount: Decimal
    public let currency: String
    public let source: String
    public let quoteDate: Date
    /// Human-readable description of what this candidate matched
    /// (e.g. "2019 Estate Reserve — Maison Test, 750ml").
    public let matchLabel: String

    public init(
        amount: Decimal,
        currency: String,
        source: String,
        quoteDate: Date,
        matchLabel: String
    ) throws {
        guard !amount.isNaN, amount >= 0 else {
            throw DomainValidationError.invalidQuoteAmount
        }
        let provenance = [currency, source, matchLabel]
        guard provenance.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw DomainValidationError.missingQuoteProvenance
        }
        self.amount = amount
        self.currency = currency
        self.source = source
        self.quoteDate = quoteDate
        self.matchLabel = matchLabel
    }
}

public enum PriceProviderError: Error, Equatable, Sendable {
    /// Price lookup is not configured/allowed in the current build state.
    case disabled
    /// The request timed out before any data arrived.
    case timedOut
    /// The provider answered successfully but knows nothing about this query.
    case noResults
}

/// Query in, candidate matches out. Every implementation must only ever run
/// when the user explicitly asked for a lookup — Wine Vault never touches
/// the network on its own.
public protocol PriceProviding: Sendable {
    func priceCandidates(for query: PriceQuery) async throws -> [PriceCandidate]
}

/// Builds the exact query text sent to a provider from a bottle's identity.
/// Deterministic and stable so the stored quote can record it verbatim.
public func priceQuery(for bottle: Bottle) throws -> PriceQuery {
    var parts: [String] = [bottle.name]
    if let producer = bottle.producer?.trimmingCharacters(in: .whitespacesAndNewlines),
       !producer.isEmpty {
        parts.append(producer)
    }
    if let vintage = bottle.vintage {
        parts.append(String(vintage))
    }
    if let region = bottle.region?.trimmingCharacters(in: .whitespacesAndNewlines),
       !region.isEmpty {
        parts.append(region)
    }
    if let grape = bottle.grape?.trimmingCharacters(in: .whitespacesAndNewlines),
       !grape.isEmpty {
        parts.append(grape)
    }
    return try PriceQuery(text: parts.joined(separator: " "))
}
