import Foundation
import XCTest

@testable import WineVaultDomain

final class CollectionSummaryTests: XCTestCase {
    func testCollectionCountsQuantitiesAndGroupsWithoutMutation() throws {
        let bottles = [
            try Bottle(
                name: "One", region: "Bordeaux", grape: "Merlot",
                quantity: 2, storageLocation: "A", tags: ["red"]
            ),
            try Bottle(
                name: "Two", region: "Bordeaux", grape: "Cabernet",
                quantity: 3, storageLocation: "B", tags: ["red", "gift"]
            ),
            try Bottle(name: "Three", quantity: 1, storageLocation: "C")
        ]

        let summary = try collectionCounts(bottles)

        XCTAssertEqual(summary.distinctBottles, 3)
        XCTAssertEqual(summary.totalQuantity, 6)
        XCTAssertEqual(summary.byRegion, ["Bordeaux": 5])
        XCTAssertEqual(summary.byGrape, ["Merlot": 2, "Cabernet": 3])
        XCTAssertEqual(summary.byTag, ["red": 5, "gift": 3])
        XCTAssertEqual(bottles.map(\.quantity), [2, 3, 1])
    }

    func testDrinkByCountsAllStates() throws {
        let calendar = Calendar(identifier: .gregorian)
        let reference = Date(timeIntervalSince1970: 1_789_084_800)
        let bottles = [
            try Bottle(name: "Unknown", quantity: 2, storageLocation: "A"),
            try Bottle(
                name: "Passed", quantity: 1, storageLocation: "A",
                drinkBy: calendar.date(byAdding: .day, value: -1, to: reference)
            ),
            try Bottle(name: "Ready", quantity: 3, storageLocation: "A", drinkBy: reference),
            try Bottle(
                name: "Soon", quantity: 4, storageLocation: "A",
                drinkBy: calendar.date(byAdding: .day, value: 30, to: reference)
            ),
            try Bottle(
                name: "Future", quantity: 5, storageLocation: "A",
                drinkBy: calendar.date(byAdding: .day, value: 91, to: reference)
            ),
        ]

        XCTAssertEqual(
            try drinkByCounts(bottles, reference: reference, calendar: calendar),
            [.noWindow: 2, .passed: 1, .ready: 3, .soon: 4, .future: 5]
        )
    }

    func testAggregateCountsReportOverflowInsteadOfTrapping() throws {
        let reference = Date(timeIntervalSince1970: 1_789_084_800)
        let bottles = [
            try Bottle(
                name: "One", region: "Region", grape: "Grape", quantity: .max,
                storageLocation: "A", tags: ["Tag"], drinkBy: reference
            ),
            try Bottle(
                name: "Two", region: "Region", grape: "Grape", quantity: 1,
                storageLocation: "B", tags: ["Tag"], drinkBy: reference
            ),
        ]

        XCTAssertThrowsError(try collectionCounts(bottles))
        XCTAssertThrowsError(try drinkByCounts(bottles, reference: reference))
    }

    func testNegativeSoonWindowNeverClassifiesFutureDateAsSoon() {
        let reference = Date(timeIntervalSince1970: 1_789_084_800)
        let future = reference.addingTimeInterval(86_400)
        XCTAssertEqual(
            drinkByState(drinkBy: future, reference: reference, soonWindowDays: -1),
            .future
        )
    }
}
