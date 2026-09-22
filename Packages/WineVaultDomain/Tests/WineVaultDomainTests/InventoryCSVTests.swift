import Foundation
import XCTest

@testable import WineVaultDomain

final class InventoryCSVTests: XCTestCase {
    private func day(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        guard let date = formatter.date(from: iso) else {
            preconditionFailure("bad fixture date: \(iso)")
        }
        return date
    }

    func testHeaderAndOneRowPerBottleWithLatestQuoteProvenance() throws {
        let first = try Bottle(
            name: "Château Test",
            producer: "Maison Test",
            vintage: 2019,
            region: "Bordeaux",
            grape: "Merlot",
            quantity: 2,
            storageLocation: "Rack A",
            tags: ["gift", "cellar"],
            drinkBy: day("2027-05-01"),
            notes: "Birthday leftovers"
        )
        let older = try ValuationQuote(
            bottleID: first.id, quoteDate: day("2026-01-01"), amount: 30,
            currency: "USD", source: "OldShop", retrievedAt: day("2026-01-01"), query: "q1"
        )
        let newer = try ValuationQuote(
            bottleID: first.id, quoteDate: day("2026-06-01"), amount: 42.5,
            currency: "USD", source: "WineSearchr", retrievedAt: day("2026-06-02"), query: "q2"
        )
        let second = try Bottle(name: "Plain", quantity: 1, storageLocation: "Box")

        let csv = inventoryCSV(
            bottles: [first, second],
            quotesByBottle: [first.id: [older, newer]]
        )
        let rows = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(rows.count, 3)
        let header = rows[0].components(separatedBy: ",")
        XCTAssertEqual(header, [
            "name", "producer", "vintage", "region", "grape", "quantity",
            "storage_location", "tags", "drink_by", "notes",
            "latest_quote_amount", "latest_quote_currency", "latest_quote_date",
            "latest_quote_source",
        ])
        let cells = rows[1].components(separatedBy: ",")
        XCTAssertEqual(cells[0], "Château Test")
        XCTAssertEqual(cells[2], "2019")
        XCTAssertEqual(cells[7], "gift|cellar")
        XCTAssertEqual(cells[8], "2027-05-01")
        // The *newest* quote wins, with amount/currency/date/source.
        XCTAssertEqual(cells[10], "42.5")
        XCTAssertEqual(cells[11], "USD")
        XCTAssertEqual(cells[12], "2026-06-01")
        XCTAssertEqual(cells[13], "WineSearchr")
        // Unvalued bottles leave quote columns empty.
        let plain = rows[2].components(separatedBy: ",")
        XCTAssertEqual(plain[10...13], ["", "", "", ""])
    }

    func testQuotesAndCommasAreRFC4180Escaped() throws {
        let bottle = try Bottle(
            name: "Domaine \"Rousseau\", Fils",
            quantity: 1,
            storageLocation: "Rack, top \"shelf\"",
            notes: "line1\nline2"
        )
        let csv = inventoryCSV(bottles: [bottle], quotesByBottle: [:])
        XCTAssertTrue(csv.contains("\"Domaine \"\"Rousseau\"\", Fils\""))
        XCTAssertTrue(csv.contains("\"Rack, top \"\"shelf\"\"\""))
        XCTAssertTrue(csv.contains("\"line1\nline2\""))
        // Record framing: records join with CRLF, the document ends with a
        // final CRLF, and embedded newlines inside quoted fields are lone
        // \n — so splitting on CRLF yields exactly [header, row, ""].
        let frames = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(frames.count, 3)
        XCTAssertTrue(frames[1].hasPrefix("\"Domaine \"\"Rousseau\"\", Fils\""))
    }

    func testNoIdentifierOrLocationColumnsExist() {
        // Content contract: the header carries only user-entered fields and
        // quote provenance. Guard the exact column set.
        XCTAssertEqual(inventoryCSVHeader.count, 14)
        for banned in ["id", "uuid", "photo", "latitude", "longitude", "device"] {
            XCTAssertFalse(
                inventoryCSVHeader.contains(where: { $0.lowercased().contains(banned) }),
                "CSV must not carry \(banned)-related columns"
            )
        }
    }
}
