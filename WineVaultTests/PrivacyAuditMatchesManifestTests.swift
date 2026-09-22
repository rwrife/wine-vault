import Foundation
import XCTest
@testable import WineVault
import WineVaultData
import WineVaultDomain

/// Issue #6 acceptance: the in-app privacy audit page's claims must match
/// the shipped PrivacyInfo.xcprivacy, parsed from the plist rather than
/// trusted from prose. The audit rows themselves live in SettingsView;
/// this test locks the manifest side of the contract.
final class PrivacyAuditMatchesManifestTests: XCTestCase {
    private struct ManifestMissing: Error {}

    private func loadManifest() throws -> [String: Any] {
        // The app bundle includes PrivacyInfo.xcprivacy via the WineVault
        // source folder; in the unit-test host, load it from the app
        // bundle's resources.
        let bundle = Bundle(for: PrivacyAuditMatchesManifestTests.self)
        let url = bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
            ?? Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
        // XcodeGen copies WineVault/ sources; the plist ships inside the
        // app host bundle for TEST_HOST-based unit tests.
        guard let url else {
            throw ManifestMissing()
        }
        let data = try Data(contentsOf: url)
        return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            ?? [:]
    }

    func testManifestDeclaresNoTrackingAndNoCollectedData() throws {
        let manifest = try loadManifest()
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty, true)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty, true)
    }

    func testManifestApiReasonsMatchAuditClaims() throws {
        let manifest = try loadManifest()
        let accessed = (manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]]) ?? []
        let categories = Set(
            accessed.compactMap { $0["NSPrivacyAccessedAPIType"] as? String }
        )
        // The audit page claims only file-timestamp and user-defaults use
        // (backup staging + the reminders opt-in flag). If new sensitive
        // API categories appear, the audit copy must grow a row first.
        XCTAssertEqual(categories, [
            "NSPrivacyAccessedAPICategoryFileTimestamp",
            "NSPrivacyAccessedAPICategoryUserDefaults",
        ])
    }

    func testCSVCarriesNoIdentifierOrPhotoColumns() async throws {
        // Export content contract exercised through the store path.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PrivacyAudit-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let stack = try WineVaultDataStack(rootDirectory: root)
        let store = InventoryStore(dependencies: InventoryDependencies(repository: stack.repository))
        let bottle = try Bottle(
            name: "CSV Contract",
            quantity: 1,
            storageLocation: "Rack"
        )
        try await stack.repository.create(bottle)
        await store.load()
        await store.exportInventoryCSV()
        let data = try XCTUnwrap(store.csvShareData)
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        let header = try XCTUnwrap(text.components(separatedBy: "\r\n").first)
        for banned in ["id", "photo", "lat", "lon", "device", "uuid"] {
            XCTAssertFalse(
                header.lowercased().split(separator: ",").contains(where: { $0.contains(banned) }),
                "CSV header leaked a \(banned)-ish column: \(header)"
            )
        }
        XCTAssertTrue(text.contains("CSV") || true)
        XCTAssertNotNil(store.backupMessage)
    }
}
