import Foundation
import XCTest

@testable import WineVaultDomain

final class BottleTests: XCTestCase {
    func testBottleRetainsCompleteUnicodeInventoryValue() throws {
        let drinkBy = Date(timeIntervalSince1970: 1_900_000_000)
        let photo = try PhotoReference("photos/cuvée-🍷.jpg")
        let bottle = try Bottle(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            name: "Cuvée 🍷",
            producer: "Domaine Étoile",
            vintage: 2019,
            region: "Côtes-du-Rhône",
            grape: "Syrah",
            quantity: 3,
            storageLocation: "Cave № 2",
            tags: ["dîner", "🎉"],
            drinkBy: drinkBy,
            photos: [photo],
            notes: "Poivre — très bon ✨"
        )

        XCTAssertEqual(bottle.name, "Cuvée 🍷")
        XCTAssertEqual(bottle.producer, "Domaine Étoile")
        XCTAssertEqual(bottle.quantity, 3)
        XCTAssertEqual(bottle.photos, [photo])
        XCTAssertEqual(bottle.notes, "Poivre — très bon ✨")
    }

    func testQuantityMustBePositive() {
        for invalidQuantity in [0, -1] {
            XCTAssertThrowsError(
                try Bottle(
                    name: "Invalid",
                    quantity: invalidQuantity,
                    storageLocation: "Rack"
                )
            ) { error in
                XCTAssertEqual(error as? DomainValidationError, .nonPositiveQuantity)
            }
        }
    }

    func testQuantityMutationRejectsInvalidValueWithoutChangingBottle() throws {
        var bottle = try Bottle(name: "Valid", quantity: 2, storageLocation: "Rack")

        XCTAssertThrowsError(try bottle.setQuantity(0)) { error in
            XCTAssertEqual(error as? DomainValidationError, .nonPositiveQuantity)
        }
        XCTAssertEqual(bottle.quantity, 2)
    }

    func testDecodingRejectsNonPositiveQuantity() throws {
        let bottle = try Bottle(name: "Valid", quantity: 2, storageLocation: "Rack")
        let encoded = try JSONEncoder().encode(bottle)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object["quantity"] = 0
        let invalid = try JSONSerialization.data(withJSONObject: object)

        XCTAssertThrowsError(try JSONDecoder().decode(Bottle.self, from: invalid))
    }

    func testPhotoReferencesAreRelativeAndCannotTraverse() {
        let unsafePaths = [
            "", "/private/photo.jpg", "../photo.jpg", "photos/../../photo.jpg",
            "./photo.jpg", "photos\\photo.jpg",
        ]
        for unsafePath in unsafePaths {
            XCTAssertThrowsError(try PhotoReference(unsafePath), "accepted unsafe path: \(unsafePath)")
        }
        let invalidPhotoReferences = [
            "vault.sqlite", "photos/album/photo.jpg", "photos/.hidden.jpg",
            "photos/line\nbreak.jpg", "photos/control\u{0}.jpg",
        ]
        for path in invalidPhotoReferences {
            XCTAssertThrowsError(try PhotoReference(path), "accepted invalid photo reference: \(path)")
        }
        XCTAssertNoThrow(try PhotoReference("photos/étiquette-🍇.jpg"))
    }

    func testValuationQuoteRetainsDatedEstimateProvenance() throws {
        let quoteDate = Date(timeIntervalSince1970: 1_800_000_000)
        let retrievedAt = Date(timeIntervalSince1970: 1_800_000_123)
        let quote = try ValuationQuote(
            bottleID: UUID(),
            quoteDate: quoteDate,
            amount: Decimal(string: "42.75")!,
            currency: "EUR",
            source: "Manual appraisal",
            retrievedAt: retrievedAt,
            query: "Étoile Cuvée 2019"
        )

        XCTAssertEqual(quote.quoteDate, quoteDate)
        XCTAssertEqual(quote.amount, Decimal(string: "42.75")!)
        XCTAssertEqual(quote.currency, "EUR")
        XCTAssertEqual(quote.source, "Manual appraisal")
        XCTAssertEqual(quote.retrievedAt, retrievedAt)
        XCTAssertEqual(quote.query, "Étoile Cuvée 2019")
    }

    func testValuationQuoteRejectsInvalidAmountAndMissingProvenance() {
        let valid = (
            bottleID: UUID(),
            quoteDate: Date(timeIntervalSince1970: 1_800_000_000),
            retrievedAt: Date(timeIntervalSince1970: 1_800_000_100)
        )
        for amount in [Decimal.nan, Decimal(-1)] {
            XCTAssertThrowsError(
                try ValuationQuote(
                    bottleID: valid.bottleID,
                    quoteDate: valid.quoteDate,
                    amount: amount,
                    currency: "USD",
                    source: "Manual",
                    retrievedAt: valid.retrievedAt,
                    query: "Wine"
                )
            )
        }
        for values in [("", "Manual", "Wine"), ("USD", " \n", "Wine"), ("USD", "Manual", "\t")] {
            XCTAssertThrowsError(
                try ValuationQuote(
                    bottleID: valid.bottleID,
                    quoteDate: valid.quoteDate,
                    amount: 0,
                    currency: values.0,
                    source: values.1,
                    retrievedAt: valid.retrievedAt,
                    query: values.2
                )
            )
        }
    }

    func testValuationQuoteDecodingRevalidatesStoredValues() throws {
        let quote = try ValuationQuote(
            bottleID: UUID(),
            quoteDate: Date(timeIntervalSince1970: 1_800_000_000),
            amount: 10,
            currency: "USD",
            source: "Manual",
            retrievedAt: Date(timeIntervalSince1970: 1_800_000_100),
            query: "Wine"
        )
        let encoded = try JSONEncoder().encode(quote)
        let validObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        for replacement in [("source", "" as Any), ("amount", -1 as Any)] {
            var object = validObject
            object[replacement.0] = replacement.1
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    ValuationQuote.self,
                    from: JSONSerialization.data(withJSONObject: object)
                )
            )
        }
    }
}
