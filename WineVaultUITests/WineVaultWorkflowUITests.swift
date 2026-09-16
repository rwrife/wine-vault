import UIKit
import XCTest

final class WineVaultWorkflowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchDefaultApp() {
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()
    }

    @MainActor
    func testAddListSearchEditAndDelete() {
        launchDefaultApp()
        app.buttons["emptyAddBottleButton"].tap()

        app.textFields["bottleNameField"].tap()
        app.textFields["bottleNameField"].typeText("Estate Reserve")
        app.textFields["producerField"].tap()
        app.textFields["producerField"].typeText("Maison Test")
        tapAfterScrolling(app.steppers["quantityStepper"].buttons["Increment"])
        app.buttons["saveBottleButton"].tap()

        let addedBottleExists = bottleElement(named: "Estate Reserve").waitForExistence(timeout: 5)
        let addedQuantityExists = element(containingLabel: "Quantity 2").exists
        XCTAssertTrue(addedBottleExists)
        XCTAssertTrue(addedQuantityExists)

        openBottle(named: "Estate Reserve")
        app.buttons["editBottleButton"].tap()
        replaceText(in: app.textFields["bottleNameField"], with: "Estate Reserve Edited")
        tapAfterScrolling(app.steppers["quantityStepper"].buttons["Increment"])
        app.buttons["saveBottleButton"].tap()

        returnToCollectionIfNeeded()
        let search = app.searchFields.firstMatch
        let searchExists = search.waitForExistence(timeout: 5)
        XCTAssertTrue(searchExists)
        search.tap()
        search.typeText("maison test")
        let editedBottleExists = bottleElement(named: "Estate Reserve Edited").waitForExistence(timeout: 5)
        let editedQuantityExists = element(containingLabel: "Quantity 3").exists
        XCTAssertTrue(editedBottleExists)
        XCTAssertTrue(editedQuantityExists)

        openBottle(named: "Estate Reserve Edited")
        app.buttons["deleteBottleButton"].tap()
        let identifiedDelete = app.buttons["confirmDeleteButton"]
        if identifiedDelete.waitForExistence(timeout: 1) {
            identifiedDelete.tap()
        } else {
            app.alerts.buttons["Delete"].tap()
        }

        let emptyStateExists = app.staticTexts["Your collection is empty"].waitForExistence(timeout: 5)
        XCTAssertTrue(emptyStateExists)
    }

    @MainActor
    func testEmptySaveShowsInlineAccessibleValidation() {
        launchDefaultApp()
        app.buttons["emptyAddBottleButton"].tap()
        app.buttons["saveBottleButton"].tap()

        let error = app.descendants(matching: .any)["validation_nameRequired"]
        let errorExists = error.waitForExistence(timeout: 3)
        let errorLabel = error.label
        XCTAssertTrue(errorExists)
        XCTAssertEqual(errorLabel, "Error: Enter a bottle name.")
    }

    @MainActor
    func testAX5ManualEntryKeepsEssentialControlsReachable() {
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()

        app.buttons["emptyAddBottleButton"].tap()
        let nameFieldExists = app.textFields["bottleNameField"].waitForExistence(timeout: 3)
        let saveButtonExists = app.buttons["saveBottleButton"].exists
        XCTAssertTrue(nameFieldExists)
        XCTAssertTrue(saveButtonExists)
        tapAfterScrolling(app.steppers["quantityStepper"])
    }

    @MainActor
    func testRegularWidthShowsBrowserAndDetailColumns() throws {
        launchDefaultApp()
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        try XCTSkipUnless(
            isPad,
            "Regular-width assertion runs in the CI iPad destination"
        )
        let addButtonExists = app.buttons["emptyAddBottleButton"].waitForExistence(timeout: 3)
        let detailPlaceholderExists = app.staticTexts["Select a bottle"].exists
        XCTAssertTrue(addButtonExists)
        XCTAssertTrue(detailPlaceholderExists)
    }

    @MainActor
    private func openBottle(named name: String) {
        let bottle = bottleElement(named: name)
        let bottleExists = bottle.waitForExistence(timeout: 5)
        XCTAssertTrue(bottleExists)
        bottle.tap()
    }

    @MainActor
    private func bottleElement(named name: String) -> XCUIElement {
        element(containingLabel: name)
    }

    @MainActor
    private func element(containingLabel text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
    }

    @MainActor
    private func returnToCollectionIfNeeded() {
        let backButton = app.navigationBars.buttons["Wine Vault"]
        if backButton.exists { backButton.tap() }
    }

    @MainActor
    private func replaceText(in field: XCUIElement, with text: String) {
        field.tap()
        field.press(forDuration: 1)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) {
            app.menuItems["Select All"].tap()
        }
        field.typeText(text)
    }

    @MainActor
    private func tapAfterScrolling(_ element: XCUIElement) {
        for _ in 0..<5 where !element.isHittable {
            app.swipeUp()
        }
        let isHittable = element.isHittable
        XCTAssertTrue(isHittable)
        element.tap()
    }
}
