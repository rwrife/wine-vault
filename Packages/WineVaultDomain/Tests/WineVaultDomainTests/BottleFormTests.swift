import Foundation
import XCTest

@testable import WineVaultDomain

final class BottleFormTests: XCTestCase {
    func testCompleteFormNormalizesOptionalValuesAndTags() throws {
        let identifier = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let drinkBy = Date(timeIntervalSince1970: 1_900_000_000)
        let form = BottleForm(
            id: identifier,
            name: "  Cuvée ",
            producer: " Domaine ",
            vintage: " 2019 ",
            region: " Rhône ",
            grape: " Syrah ",
            quantity: 3,
            storageLocation: " Rack A ",
            tags: [" dinner ", "Gift", "gift", ""],
            drinkBy: drinkBy,
            notes: " Pepper "
        )

        let bottle = try form.bottle()

        XCTAssertEqual(bottle.id, identifier)
        XCTAssertEqual(bottle.name, "Cuvée")
        XCTAssertEqual(bottle.producer, "Domaine")
        XCTAssertEqual(bottle.vintage, 2019)
        XCTAssertEqual(bottle.region, "Rhône")
        XCTAssertEqual(bottle.grape, "Syrah")
        XCTAssertEqual(bottle.quantity, 3)
        XCTAssertEqual(bottle.storageLocation, "Rack A")
        XCTAssertEqual(bottle.tags, ["dinner", "Gift"])
        XCTAssertEqual(bottle.drinkBy, drinkBy)
        XCTAssertEqual(bottle.notes, "Pepper")
    }

    func testValidationReportsEveryFieldProblemAtOnce() {
        let form = BottleForm(name: " \n", vintage: "twenty", quantity: 0)

        XCTAssertEqual(
            form.validationErrors,
            [.nameRequired, .vintageInvalid, .quantityMustBePositive]
        )
        XCTAssertThrowsError(try form.bottle()) { error in
            XCTAssertEqual(
                error as? BottleFormValidationError,
                .invalid([.nameRequired, .vintageInvalid, .quantityMustBePositive])
            )
        }
    }

    func testVintageRequiresExactlyFourAsciiDigits() {
        for vintage in ["+2020", "２０２０", "999", "0200", "10000"] {
            XCTAssertEqual(BottleForm(name: "Wine", vintage: vintage).validationErrors, [.vintageInvalid])
        }
        XCTAssertTrue(BottleForm(name: "Wine", vintage: "2020").validationErrors.isEmpty)
    }

    func testEditingPreservesIdentityAndPhotos() throws {
        let photo = try PhotoReference("photos/label.jpg")
        let original = try Bottle(
            id: UUID(), name: "Old", quantity: 1, storageLocation: "A", photos: [photo]
        )

        var form = BottleForm(bottle: original)
        form.name = "New"
        form.quantity = 4

        let edited = try form.bottle()
        XCTAssertEqual(edited.id, original.id)
        XCTAssertEqual(edited.photos, [photo])
        XCTAssertEqual(edited.name, "New")
        XCTAssertEqual(edited.quantity, 4)
    }
}
