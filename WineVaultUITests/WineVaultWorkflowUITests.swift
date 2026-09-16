import UIKit
import XCTest

final class WineVaultWorkflowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    func testAddListSearchEditAndDelete() {
        app.buttons["emptyAddBottleButton"].tap()

        app.textFields["bottleNameField"].tap()
        app.textFields["bottleNameField"].typeText("Estate Reserve")
        app.textFields["producerField"].tap()
        app.textFields["producerField"].typeText("Maison Test")
        tapAfterScrolling(app.steppers["quantityStepper"].buttons["Increment"])
        app.buttons["saveBottleButton"].tap()

        XCTAssertTrue(bottleElement(named: "Estate Reserve").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containingLabel: "Quantity 2").exists)

        openBottle(named: "Estate Reserve")
        app.buttons["editBottleButton"].tap()
        replaceText(in: app.textFields["bottleNameField"], with: "Estate Reserve Edited")
        tapAfterScrolling(app.steppers["quantityStepper"].buttons["Increment"])
        app.buttons["saveBottleButton"].tap()

        returnToCollectionIfNeeded()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("maison test")
        XCTAssertTrue(bottleElement(named: "Estate Reserve Edited").waitForExistence(timeout: 5))
        XCTAssertTrue(element(containingLabel: "Quantity 3").exists)

        openBottle(named: "Estate Reserve Edited")
        app.buttons["deleteBottleButton"].tap()
        let identifiedDelete = app.buttons["confirmDeleteButton"]
        if identifiedDelete.waitForExistence(timeout: 1) {
            identifiedDelete.tap()
        } else {
            app.alerts.buttons["Delete"].tap()
        }

        XCTAssertTrue(app.staticTexts["Your collection is empty"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["undoDeleteButton"].exists)
    }

    func testEmptySaveShowsInlineAccessibleValidation() {
        app.buttons["emptyAddBottleButton"].tap()
        app.buttons["saveBottleButton"].tap()

        let error = app.descendants(matching: .any)["validation_nameRequired"]
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        XCTAssertEqual(error.label, "Error: Enter a bottle name.")
    }

    func testAX5ManualEntryKeepsEssentialControlsReachable() {
        app.terminate()
        app.launchArguments = [
            "--ui-testing",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        app.buttons["emptyAddBottleButton"].tap()
        XCTAssertTrue(app.textFields["bottleNameField"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["saveBottleButton"].exists)
        tapAfterScrolling(app.steppers["quantityStepper"])
    }

    func testRegularWidthShowsBrowserAndDetailColumns() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .pad,
            "Regular-width assertion runs in the CI iPad destination"
        )
        XCTAssertTrue(app.buttons["emptyAddBottleButton"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Select a bottle"].exists)
    }

    private func openBottle(named name: String) {
        let bottle = bottleElement(named: name)
        XCTAssertTrue(bottle.waitForExistence(timeout: 5))
        bottle.tap()
    }

    private func bottleElement(named name: String) -> XCUIElement {
        element(containingLabel: name)
    }

    private func element(containingLabel text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
    }

    private func returnToCollectionIfNeeded() {
        let backButton = app.navigationBars.buttons["Wine Vault"]
        if backButton.exists { backButton.tap() }
    }

    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        field.press(forDuration: 1)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) {
            app.menuItems["Select All"].tap()
        }
        field.typeText(text)
    }

    private func tapAfterScrolling(_ element: XCUIElement) {
        for _ in 0..<5 where !element.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
        element.tap()
    }
}
