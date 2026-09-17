import Foundation
import XCTest

@testable import WineVaultDomain

final class BottleFilteringTests: XCTestCase {
    private let reference = Date(timeIntervalSince1970: 1_789_084_800)

    func testSearchMatchesNameProducerAndRegionCaseInsensitively() throws {
        let bottles = try fixtures()

        let reserve = filterBottles(
            bottles, criteria: .init(searchText: "reserve"), reference: reference
        )
        let producer = filterBottles(
            bottles, criteria: .init(searchText: "estate"), reference: reference
        )
        let region = filterBottles(
            bottles, criteria: .init(searchText: "rioja"), reference: reference
        )
        XCTAssertEqual(reserve.map(\.name), ["Reserve"])
        XCTAssertEqual(producer.map(\.name), ["Reserve"])
        XCTAssertEqual(region.map(\.name), ["Gran Tinto"])
    }

    func testRegionGrapeAndTagFiltersCompose() throws {
        let bottles = try fixtures()
        let criteria = BottleFilterCriteria(region: " bordeaux ", grape: "MERLOT", tag: " Dinner ")

        XCTAssertEqual(filterBottles(bottles, criteria: criteria, reference: reference).map(\.name), ["Reserve"])
    }

    func testDrinkByFilterUsesInjectedReferenceDate() throws {
        let bottles = try fixtures()

        XCTAssertEqual(
            filterBottles(bottles, criteria: .init(drinkBy: .ready), reference: reference).map(\.name),
            ["Reserve"]
        )
        XCTAssertEqual(
            filterBottles(bottles, criteria: .init(drinkBy: .noWindow), reference: reference).map(\.name),
            ["Gran Tinto"]
        )
    }

    func testAvailableFacetsAreTrimmedDeduplicatedAndSorted() throws {
        let facets = bottleFilterFacets(try fixtures())

        XCTAssertEqual(facets.regions, ["Bordeaux", "Rioja"])
        XCTAssertEqual(facets.grapes, ["Merlot", "Tempranillo"])
        XCTAssertEqual(facets.tags, ["Dinner", "gift"])
    }

    private func fixtures() throws -> [Bottle] {
        [
            try Bottle(
                name: "Reserve", producer: "Estate House", region: "Bordeaux",
                grape: "Merlot", quantity: 2, storageLocation: "A",
                tags: ["Dinner", "gift"], drinkBy: reference
            ),
            try Bottle(
                name: "Gran Tinto", producer: "Bodega", region: "Rioja",
                grape: "Tempranillo", quantity: 1, storageLocation: "B",
                tags: ["dinner"]
            ),
        ]
    }
}
