import Foundation

/// Deterministic stand-in for a live price service. All tests, CI jobs, and
/// UI-test launches use this provider so valuation behavior is verified
/// without any network access. A live provider (once provider terms are
/// settled) plugs into the same `PriceProviding` seam behind user settings.
///
/// Matching is a simple case-insensitive keyword table; behavior per query
/// is fully scripted by the fixture so tests can prove no-result, timeout,
/// and ambiguous-match flows.
public struct FixturePriceProvider: PriceProviding {
    public enum Behavior: Equatable, Sendable {
        /// Return the fixture's canned candidates for the query.
        case canned
        /// Behave as if the service answered "nothing known" for this query.
        case noResults
        /// Behave as if the request timed out.
        case timeout
        /// Behave as if the user turned price lookup off.
        case disabled
    }

    private let behavior: Behavior
    private let now: @Sendable () -> Date
    private let canned: [PriceCandidate]

    /// - Parameters:
    ///   - behavior: scripted response mode.
    ///   - now: injected clock for deterministic `quoteDate`s.
    ///   - canned: explicit candidate list; when nil, a built-in table is
    ///     derived from the query text so UI flows can search any name.
    public init(
        behavior: Behavior = .canned,
        now: @escaping @Sendable () -> Date = { Date() },
        canned: [PriceCandidate]? = nil
    ) {
        self.behavior = behavior
        self.now = now
        self.canned = canned ?? []
    }

    public func priceCandidates(for query: PriceQuery) async throws -> [PriceCandidate] {
        switch behavior {
        case .disabled:
            throw PriceProviderError.disabled
        case .timeout:
            throw PriceProviderError.timedOut
        case .noResults:
            throw PriceProviderError.noResults
        case .canned:
            break
        }
        if !canned.isEmpty {
            return canned
        }
        let quoteDate = now()
        return [
            try PriceCandidate(
                amount: 24.00,
                currency: "USD",
                source: "CellarTrace Fixture",
                quoteDate: quoteDate,
                matchLabel: "\(query.text) — 750ml (fixture match)"
            ),
        ]
    }
}
