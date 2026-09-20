import Foundation

// The Domain layer is intentionally dependency-free: no GRDB, UIKit,
// networking, storage, or other side effects.

/// Deterministic seed bottles for `--ui-testing-seed=wine-vault`.
///
/// UI tests that assert on populated screens (timeline grouping, dashboards,
/// value history) need known data without driving the add-bottle form ten
/// times. The seeds are fixed, offline, and reference-free (no photos), so
/// assertions can depend on exact counts and labels. Production launches are
/// unaffected — the seed is only applied when the launch argument is present.
public struct SeededBottle: Equatable, Sendable {
    public let name: String
    public let producer: String?
    public let vintage: Int?
    public let region: String?
    public let grape: String?
    public let quantity: Int
    public let storageLocation: String
    public let drinkByInDays: Int?
    public let notes: String?

    public init(
        name: String,
        producer: String? = nil,
        vintage: Int? = nil,
        region: String? = nil,
        grape: String? = nil,
        quantity: Int,
        storageLocation: String,
        drinkByInDays: Int? = nil,
        notes: String? = nil
    ) {
        self.name = name
        self.producer = producer
        self.vintage = vintage
        self.region = region
        self.grape = grape
        self.quantity = quantity
        self.storageLocation = storageLocation
        self.drinkByInDays = drinkByInDays
        self.notes = notes
    }
}

/// The fixed seed set: one bottle in each drink-by window plus one with no
/// window, spread across two regions and two grapes so dashboard grouping is
/// exercised. Values chosen so timeline groups have exact expected counts.
public let uiTestSeedBottles: [SeededBottle] = [
    SeededBottle(
        name: "Seed Passed Pinot", producer: "Seed Estate", vintage: 2018,
        region: "Seedburgundy", grape: "Pinot", quantity: 1,
        storageLocation: "Seed Rack A", drinkByInDays: -30,
        notes: "Past its drink-by window."
    ),
    SeededBottle(
        name: "Seed Ready Merlot", producer: "Seed Estate", vintage: 2020,
        region: "Seedburgundy", grape: "Merlot", quantity: 2,
        storageLocation: "Seed Rack B", drinkByInDays: 0
    ),
    SeededBottle(
        name: "Seed Soon Syrah", producer: "Seed Hills", vintage: 2021,
        region: "Seedville", grape: "Syrah", quantity: 1,
        storageLocation: "Seed Rack B", drinkByInDays: 45
    ),
    SeededBottle(
        name: "Seed Future Cabernet", producer: "Seed Hills", vintage: 2023,
        region: "Seedville", grape: "Cabernet", quantity: 3,
        storageLocation: "Seed Rack C", drinkByInDays: 400
    ),
    SeededBottle(
        name: "Seed Windowless blends", producer: "Seed Cellars",
        region: "Seedville", grape: "Blend", quantity: 1,
        storageLocation: "Seed Rack C"
    ),
]

extension Bottle {
    /// Materializes one seed against a reference date. The seed's
    /// `drinkByInDays` offset is resolved against `reference` (calendar-day
    /// precision) so grouping is stable within a single test run.
    public init(seed: SeededBottle, reference: Date, calendar: Calendar = .current) throws {
        let drinkBy = seed.drinkByInDays.map { offset in
            calendar.date(
                byAdding: .day,
                value: offset,
                to: calendar.startOfDay(for: reference)
            )
        } ?? nil
        try self.init(
            name: seed.name,
            producer: seed.producer,
            vintage: seed.vintage,
            region: seed.region,
            grape: seed.grape,
            quantity: seed.quantity,
            storageLocation: seed.storageLocation,
            drinkBy: drinkBy,
            notes: seed.notes
        )
    }
}
