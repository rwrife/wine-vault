import UIKit
import XCTest

/// Issue #6 UI flow coverage: settings entry, privacy audit page presence,
/// and the export/backup happy path against the inert in-memory backup
/// backend (no real share sheet or file picker is driven on purpose).
final class WineVaultBackupUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchSeededApp() {
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-seed=wine-vault",
        ]
        app.launch()
    }

    /// SwiftUI `List` renders lazily: at compact width the privacy
    /// section sits below the fold. Swipe the screen (bounded) until the
    /// identifier materialises — coordinate-based so it doesn't depend
    /// on which container type the List surfaces as.
    @MainActor
    private func scrollToIdentifier(_ identifier: String) -> Bool {
        let element = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@", identifier)
        ).firstMatch
        if element.waitForExistence(timeout: 5) { return true }
        for _ in 0..<6 {
            app.swipeUp()
            if element.waitForExistence(timeout: 3) { return true }
        }
        return element.exists
    }

    @MainActor
    func testSettingsExposesPrivacyAuditAndBackupControls() {
        launchSeededApp()
        app.buttons["settingsButton"].tap()

        XCTAssertTrue(app.buttons["exportCSVButton"].exists)
        XCTAssertTrue(app.buttons["createBackupButton"].exists)
        XCTAssertTrue(app.buttons["restoreBackupButton"].exists)

        XCTAssertTrue(
            scrollToIdentifier("privacyNeverCollected"),
            "The privacy audit statement must be reachable in settings."
        )

        app.buttons["settingsDoneButton"].tap()
    }

    @MainActor
    func testBackupHappyPathReportsReadyArchive() {
        launchSeededApp()
        app.buttons["settingsButton"].tap()
        app.buttons["createBackupButton"].tap()

        XCTAssertTrue(
            app.staticTexts["backupMessage"].waitForExistence(timeout: 5),
            "Creating a backup must report a ready archive."
        )
        let message = app.staticTexts["backupMessage"].label
        XCTAssertTrue(
            message.localizedCaseInsensitiveContains("wine-vault-backup"),
            "Backup message should name the generated archive, got: \(message)"
        )
    }

    @MainActor
    func testRestoreHappyPathReportsAppliedSummary() {
        app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-testing-seed=wine-vault",
            "--ui-testing-restore-file",
        ]
        app.launch()
        app.buttons["settingsButton"].tap()

        // The document picker cannot be driven from XCUITest, so the app
        // exposes a gated staging button that pre-seeds the same archive
        // bytes the real import path would stage.
        app.buttons["stageRestoreButton"].tap()

        // SwiftUI surfaces both the action-sheet button and its label copy
        // with the same identifier, so target the unique option label.
        let replaceButton = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Replace everything")
        ).firstMatch
        XCTAssertTrue(
            replaceButton.waitForExistence(timeout: 5),
            "Staging an archive must open the merge/replace chooser."
        )
        replaceButton.tap()

        let message = app.staticTexts["backupMessage"]
        XCTAssertTrue(
            message.waitForExistence(timeout: 10),
            "A completed restore must report its applied summary."
        )
        XCTAssertTrue(
            message.label.localizedCaseInsensitiveContains("Restored"),
            "Restore message should summarize applied records, got: \(message.label)"
        )

        app.buttons["settingsDoneButton"].tap()
    }

    @MainActor
    func testExportCSVHappyPathReportsRowCount() {
        launchSeededApp()
        app.buttons["settingsButton"].tap()
        app.buttons["exportCSVButton"].tap()

        XCTAssertTrue(
            app.staticTexts["backupMessage"].waitForExistence(timeout: 5),
            "CSV export must report readiness."
        )
        let message = app.staticTexts["backupMessage"].label
        XCTAssertTrue(
            message.localizedCaseInsensitiveContains("CSV"),
            "Expected CSV confirmation text, got: \(message)"
        )
    }
}
