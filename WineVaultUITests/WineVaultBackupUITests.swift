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

    @MainActor
    func testSettingsExposesPrivacyAuditAndBackupControls() {
        launchSeededApp()
        app.buttons["settingsButton"].tap()

        XCTAssertTrue(
            app.staticTexts["privacyNeverCollected"].waitForExistence(timeout: 5),
            "The privacy audit statement must be visible in settings."
        )
        XCTAssertTrue(app.buttons["exportCSVButton"].exists)
        XCTAssertTrue(app.buttons["createBackupButton"].exists)
        XCTAssertTrue(app.buttons["restoreBackupButton"].exists)

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
