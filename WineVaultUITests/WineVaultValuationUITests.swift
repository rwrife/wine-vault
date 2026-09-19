import XCTest

/// Issue #4 acceptance: the confirm-match flow through the real UI. The
/// launched app under `--ui-testing` uses the deterministic
/// `FixturePriceProvider` only — no network access exists anywhere.
final class WineVaultValuationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testManualPriceAndConfirmedEstimateShowDatedQuotes() throws {
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing"]
        app.launch()

        // Seed one bottle through the add flow.
        app.buttons["emptyAddBottleButton"].tap()
        app.textFields["bottleNameField"].tap()
        app.textFields["bottleNameField"].typeText("Quota Cabernet")
        app.buttons["saveBottleButton"].tap()
        XCTAssertTrue(
            bottleElement(named: "Quota Cabernet").waitForExistence(timeout: 5)
        )

        openBottle(named: "Quota Cabernet")
        scrollDetail(untilHittable: app.buttons["enterPriceManuallyButton"])
        app.buttons["enterPriceManuallyButton"].tap()

        // Offline manual price — always available.
        let amountField = app.textFields["manualAmountField"]
        XCTAssertTrue(amountField.waitForExistence(timeout: 3))
        amountField.tap()
        amountField.typeText("25.50")
        app.buttons["saveManualPriceButton"].tap()

        let quoteText = app.staticTexts["valuationQuoteText"]
        let manualQuoteShown = quoteText.waitForExistence(timeout: 5)
        XCTAssertTrue(manualQuoteShown)
        XCTAssertTrue(
            quoteText.label.contains("Manual entry"),
            "Manual quote should show manual provenance, got: \(quoteText.label)"
        )
        XCTAssertTrue(quoteText.label.contains("Estimated"))

        // User-initiated estimate; candidate must be confirmed explicitly.
        scrollDetail(untilHittable: app.buttons["estimateValueButton"])
        app.buttons["estimateValueButton"].tap()

        let confirmButton = app.buttons["confirmMatchButton_0"]
        let candidateShown = confirmButton.waitForExistence(timeout: 10)
        XCTAssertTrue(candidateShown, "Fixture candidate should await confirmation")
        XCTAssertTrue(app.staticTexts["Estimating collection"].exists == false)
        confirmButton.tap()

        let estimateQuoteShown = quoteText.waitForExistence(timeout: 5)
        XCTAssertTrue(estimateQuoteShown)
        XCTAssertTrue(
            quoteText.label.contains("CellarTrace Fixture"),
            "Confirmed quote should show provider provenance, got: \(quoteText.label)"
        )
        XCTAssertTrue(quoteText.label.contains("Estimated"))
        let disclaimer = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "not an authoritative price"))
            .firstMatch
        XCTAssertTrue(disclaimer.waitForExistence(timeout: 3))

        // Collection coverage statement appears back in the browser list.
        returnToCollectionIfNeeded()
        let coverage = app.staticTexts["collectionValuationCoverage"]
        scrollBrowser(untilHittable: coverage)
        let coverageShown = coverage.waitForExistence(timeout: 5)
        XCTAssertTrue(coverageShown)
        XCTAssertTrue(
            coverage.label.contains("1 of 1 bottles valued"),
            "Coverage should state exactly one valued bottle, got: \(coverage.label)"
        )
    }

    @MainActor
    func testEstimateWithoutConfirmationStoresNothing() throws {
        app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--ui-testing-price=no-results"]
        app.launch()

        app.buttons["emptyAddBottleButton"].tap()
        app.textFields["bottleNameField"].tap()
        app.textFields["bottleNameField"].typeText("Mystery Cuvée")
        app.buttons["saveBottleButton"].tap()
        XCTAssertTrue(bottleElement(named: "Mystery Cuvée").waitForExistence(timeout: 5))

        openBottle(named: "Mystery Cuvée")
        scrollDetail(untilHittable: app.buttons["estimateValueButton"])
        app.buttons["estimateValueButton"].tap()

        // No results: the sheet explains and offers the manual fallback.
        let fallback = app.buttons["manualFallbackFromLookupButton"]
        let fallbackShown = fallback.waitForExistence(timeout: 10)
        if !fallbackShown {
            // Ship the failure evidence into the CI console log: the
            // xcresult attachment is not readable from Linux triage.
            print("HIERARCHY-DUMP-BEGIN estimateValue no-results sheet")
            print(app.debugDescription)
            print("HIERARCHY-DUMP-END")
        }
        XCTAssertTrue(fallbackShown)
        fallback.tap()

        // No quote on record and the manual path is still offered.
        XCTAssertTrue(app.buttons["enterPriceManuallyButton"].waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "No price on record")
            ).firstMatch.exists
        )
    }

    @MainActor
    private func openBottle(named name: String) {
        let bottle = bottleElement(named: name)
        XCTAssertTrue(bottle.waitForExistence(timeout: 5))
        bottle.tap()
    }

    @MainActor
    private func bottleElement(named name: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", name))
            .firstMatch
    }

    @MainActor
    private func returnToCollectionIfNeeded() {
        let backButton = app.navigationBars.buttons["Wine Vault"]
        if backButton.exists { backButton.tap() }
    }

    @MainActor
    private func scrollDetail(untilHittable element: XCUIElement) {
        let tables = [app.tables.firstMatch, app.collectionViews.firstMatch]
        for _ in 0..<6 where !element.exists || !element.isHittable {
            let container = tables.first { $0.exists } ?? app.tables.firstMatch
            container.swipeUp()
        }
    }

    @MainActor
    private func scrollBrowser(untilHittable element: XCUIElement) {
        scrollDetail(untilHittable: element)
    }
}
