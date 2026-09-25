import Foundation
import XCTest

@testable import WineVaultData
import WineVaultDomain

/// Issue #8 persistence harness: a fuzz-style round-trip over 500 synthetic
/// bottles written from a deterministic pseudo-random generator. Every
/// field (including optional/unicode/emoji/edge values) must survive an
/// identical write → read → reopen cycle. The seed is fixed so a failure
/// reproduces byte-for-byte in CI.
final class SyntheticRoundTripTests: XCTestCase {
    /// SplitMix64 — small, deterministic, dependency-free.
    private struct DeterministicGenerator: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed
        }

        mutating func next() -> UInt64 {
            state = state &+ 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    private static let alphabet = Array("🍷Cuvée Étoile 🎉dão №1 ☕️ abcXYZ019 .-/'")
    /// Photo file names must satisfy `PhotoReference`'s safety rules
    /// (no slashes, no leading dot), so they get their own alphabet.
    private static let photoAlphabet = Array("label019🍷É")
    private static let racks = ["Rack A", "Étagère №2", "Cave 🕯️", "Box-07"]
    private static let grapes = ["Touriga Nacional", "Pinot Noir 🍇", "Riesling", nil]
    private static let regions = ["Dão", "Mosel", "Willamette 🌲", nil]

    private func syntheticBottles(count: Int, seed: UInt64) throws -> [Bottle] {
        var generator = DeterministicGenerator(seed: seed)
        func word(_ maxCount: Int, alphabet: [Character] = Self.alphabet) -> String {
            let length = Int(generator.next() % UInt64(maxCount)) + 1
            let letters = (0..<length).map { _ in alphabet[Int(generator.next() % UInt64(alphabet.count))] }
            return String(letters)
        }
        return try (0..<count).map { index in
            var tags: [String] = []
            for _ in 0..<Int(generator.next() % 4) {
                tags.append(word(8))
            }
            let photos = try (0..<Int(generator.next() % 3)).map { _ in
                let stem = word(6, alphabet: Self.photoAlphabet)
                return try PhotoReference("photos/label-\(index)-\(stem).jpg")
            }
            let drinkBy: Date? = generator.next() % 4 == 0
                ? Date(timeIntervalSince1970: Double(Int(generator.next() % 4_000_000_000)))
                : nil
            let name = word(30)
            return try Bottle(
                name: name.isEmpty ? " " : name,
                producer: generator.next() % 5 == 0 ? nil : word(20),
                vintage: generator.next() % 6 == 0 ? nil : 1950 + Int(generator.next() % 80),
                region: Self.regions[Int(generator.next() % UInt64(Self.regions.count))],
                grape: Self.grapes[Int(generator.next() % UInt64(Self.grapes.count))],
                quantity: 1 + Int(generator.next() % 144),
                storageLocation: Self.racks[Int(generator.next() % UInt64(Self.racks.count))],
                tags: tags,
                drinkBy: drinkBy,
                photos: photos,
                notes: generator.next() % 3 == 0 ? nil : word(80)
            )
        }
    }

    private func makeTemporaryDatabaseURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SyntheticRoundTrip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("vault.sqlite")
    }

    func testFiveHundredSyntheticBottlesRoundTripThroughFileDatabase() async throws {
        let bottles = try syntheticBottles(count: 500, seed: 0x5EED_D1CE_0000_FACE)
        XCTAssertEqual(bottles.count, 500)

        let databaseURL = try makeTemporaryDatabaseURL()
        var repository: SQLiteBottleRepository? = try SQLiteBottleRepository(databaseURL: databaseURL)
        for bottle in bottles {
            try await repository?.create(bottle)
        }
        let written = try await repository?.bottles()
        XCTAssertEqual(Set(written?.map(\.id) ?? []), Set(bottles.map(\.id)))

        // Reopen the same file: every bottle must decode identically.
        repository = nil
        let reopened = try SQLiteBottleRepository(databaseURL: databaseURL)
        let stored = try await reopened.bottles()
        XCTAssertEqual(
            stored.sorted { $0.id.uuidString < $1.id.uuidString },
            bottles.sorted { $0.id.uuidString < $1.id.uuidString }
        )
    }

    func testFiveHundredSyntheticBottlesSurviveUpdateAndDelete() async throws {
        let bottles = try syntheticBottles(count: 500, seed: 0x5EED_0DD_0000_FACE)
        let repository = try SQLiteBottleRepository(inMemory: true)
        for bottle in bottles {
            try await repository.create(bottle)
        }

        // Update every third bottle (quantity + notes), delete every fifth.
        var updated: [UUID: Bottle] = [:]
        var deleted: Set<UUID> = []
        for (index, bottle) in bottles.enumerated() {
            if index % 3 == 0 {
                var mutable = bottle
                try mutable.setQuantity(bottle.quantity + 3)
                mutable.notes = "mutated ✨ \(index)"
                try await repository.update(mutable)
                updated[bottle.id] = mutable
            }
            if index % 5 == 0 {
                try await repository.deleteBottle(id: bottle.id)
                deleted.insert(bottle.id)
            }
        }

        let expected = bottles.compactMap { bottle -> Bottle? in
            if deleted.contains(bottle.id) { return nil }
            return updated[bottle.id] ?? bottle
        }
        let stored = try await repository.bottles()
        XCTAssertEqual(
            stored.sorted { $0.id.uuidString < $1.id.uuidString },
            expected.sorted { $0.id.uuidString < $1.id.uuidString }
        )
    }
}
