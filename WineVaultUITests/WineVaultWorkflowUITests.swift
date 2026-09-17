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
        incrementQuantity(expectedValue: 2)
        app.buttons["saveBottleButton"].tap()

        let addedBottleExists = bottleElement(named: "Estate Reserve").waitForExistence(timeout: 5)
        let addedQuantityExists = element(containingLabel: "Quantity 2").exists
        XCTAssertTrue(addedBottleExists)
        XCTAssertTrue(addedQuantityExists)

        openBottle(named: "Estate Reserve")
        app.buttons["editBottleButton"].tap()
        replaceText(in: app.textFields["bottleNameField"], with: "Estate Reserve Edited")
        incrementQuantity(expectedValue: 3)
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
        let alert = app.alerts.firstMatch
        let alertAppeared = alert.waitForExistence(timeout: 3)
        XCTAssertTrue(alertAppeared)
        // The SwiftUI alert's Delete button is uniquely labeled inside the
        // alert itself; the accessibility identifier can propagate to
        // several system nodes and must not be queried app-wide.
        alert.buttons["Delete"].firstMatch.tap()

        returnToCollectionIfNeeded()
        let emptyStateExists = app.staticTexts["Your collection is empty"].waitForExistence(timeout: 5)
        XCTAssertTrue(emptyStateExists)
    }

    @MainActor
    func testEmptySaveShowsInlineAccessibleValidation() {
        launchDefaultApp()
        app.buttons["emptyAddBottleButton"].tap()
        app.buttons["saveBottleButton"].tap()

        captureHierarchyForFailure(named: "Inline validation")
        let error = app.staticTexts["validation_nameRequired"].firstMatch
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
        incrementQuantity(expectedValue: 2)
        let decrement = app.buttons["Decrement"].firstMatch
        scrollForm(untilHittable: decrement)
        captureHierarchyForFailure(named: "AX5 quantity controls")
        let decrementExists = decrement.exists
        let decrementIsHittable = decrement.isHittable
        XCTAssertTrue(decrementExists)
        XCTAssertTrue(decrementIsHittable)
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
        let currentValue = field.value as? String ?? ""
        if !currentValue.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
        }
        field.typeText(text)
        // Press the keyboard's Done key (the name field uses submitLabel(.done))
        // so the keyboard is deterministically dismissed before the next control
        // is scrolled into view; a lingering keyboard makes form swipes miss.
        field.typeText(XCUIKeyboardKey.return.rawValue)
    }

    @MainActor
    private func incrementQuantity(expectedValue: Int) {
        dismissKeyboardIfPresent()
        let increment = app.buttons["Increment"].firstMatch
        scrollForm(untilHittable: increment)
        captureHierarchyForFailure(named: "Quantity controls")
        let incrementExists = increment.exists
        let incrementIsHittable = increment.isHittable
        XCTAssertTrue(incrementExists)
        XCTAssertTrue(incrementIsHittable)
        increment.tap()

        let quantity = app.staticTexts["Quantity: \(expectedValue)"].firstMatch
        let quantityChanged = quantity.waitForExistence(timeout: 3)
        XCTAssertTrue(quantityChanged)
    }

    @MainActor
    private func dismissKeyboardIfPresent() {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.exists else { return }
        let done = keyboard.buttons["Done"].firstMatch
        if done.exists {
            done.tap()
        } else {
            keyboard.swipeDown()
        }
    }

    @MainActor
    private func scrollForm(untilHittable element: XCUIElement) {
        let form = app.collectionViews.firstMatch
        for _ in 0..<6 where !element.exists || !element.isHittable {
            form.swipeUp()
        }
    }

    @MainActor
    private func captureHierarchyForFailure(named name: String) {
        let attachment = XCTAttachment(string: app.debugDescription)
        attachment.name = name
        attachment.lifetime = .deleteOnSuccess
        add(attachment)
    }
}
