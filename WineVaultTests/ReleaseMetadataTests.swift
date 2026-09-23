import Foundation
@testable import WineVault
import XCTest

/// Issue #7: App Store metadata is release-legal copy, so every draft field
/// is checked against App Store Connect field limits, the local-first
/// product contract, and the shipped privacy manifest. The plist that
/// release tooling reads must also stay byte-for-byte consistent with
/// `ReleaseInfo` — drift fails CI instead of shipping mismatched copy.
final class ReleaseMetadataTests: XCTestCase {
    private func loadMetadata() throws -> [String: Any] {
        // TEST_HOST unit tests run inside the app bundle, which ships the
        // plist via the WineVault source folder.
        let bundle = Bundle(for: ReleaseMetadataTests.self)
        let url = bundle.url(forResource: "AppStoreMetadata", withExtension: "plist")
            ?? Bundle.main.url(forResource: "AppStoreMetadata", withExtension: "plist")
        let data = try XCTUnwrap(url, "AppStoreMetadata.plist is not bundled")
        return try PropertyListSerialization.propertyList(
            from: try Data(contentsOf: data), format: nil
        ) as? [String: Any] ?? [:]
    }

    // MARK: - Field limits

    func testTitleAndSubtitleFitStoreLimits() throws {
        XCTAssertLessThanOrEqual(ReleaseInfo.appTitle.utf16.count, 30, "App name limit is 30 characters")
        XCTAssertLessThanOrEqual(ReleaseInfo.subtitle.utf16.count, 30, "Subtitle limit is 30 characters")
    }

    func testKeywordsFitCommaSeparatedFieldLimit() throws {
        XCTAssertLessThanOrEqual(ReleaseInfo.keywords.utf16.count, 100, "Keywords limit is 100 characters")
        let terms = ReleaseInfo.keywords.split(separator: ",").map(String.init)
        XCTAssertFalse(terms.isEmpty)
        for term in terms {
            XCTAssertFalse(term.isEmpty, "Empty keyword term")
        }
        XCTAssertEqual(Set(terms).count, terms.count, "Duplicate keyword terms")
    }

    func testDescriptionFitsStoreLimit() throws {
        XCTAssertLessThanOrEqual(ReleaseInfo.description.utf16.count, 4000, "Promotional text limit is 4000 characters")
    }

    func testCategoriesAreAppStoreConnectValues() throws {
        XCTAssertTrue(
            ["FOOD_AND_DRINK", "UTILITIES"].contains(ReleaseInfo.primaryCategory),
            "Primary category must be a supported App Store category"
        )
        XCTAssertNotEqual(ReleaseInfo.secondaryCategory, ReleaseInfo.primaryCategory)
    }

    // MARK: - Product-contract guardrails

    func testMetadataNeverPresentsQuotesAsAuthoritativePrices() throws {
        let lowered = ReleaseInfo.description.lowercased()
        for banned in ["current price", "actual price", "guaranteed value", "guaranteed price"] {
            XCTAssertFalse(lowered.contains(banned), "Forbidden claim: \(banned)")
        }
        XCTAssertTrue(lowered.contains("estimate"), "Quotes must be described as estimates")
    }

    func testMetadataMakesNoHealthClaims() throws {
        let lowered = ReleaseInfo.description.lowercased()
        for banned in ["health", "healthy", "cardiovascular", "antioxidant", "moderation"] {
            XCTAssertFalse(lowered.contains(banned), "Health-related wording is out of scope: \(banned)")
        }
    }

    func testMetadataStatesLocalFirstPosture() throws {
        let lowered = ReleaseInfo.description.lowercased()
        XCTAssertTrue(lowered.contains("offline"))
        XCTAssertTrue(lowered.contains("no account"))
        XCTAssertTrue(lowered.contains("no telemetry"))
    }

    // MARK: - Privacy declaration consistency

    func testPrivacyDeclarationMatchesManifest() throws {
        // "Data Not Collected" is only a truthful store declaration if the
        // shipped manifest collects nothing and tracks nobody.
        let bundle = Bundle(for: ReleaseMetadataTests.self)
        let url = bundle.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
            ?? Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy")
        let plistURL = try XCTUnwrap(url, "PrivacyInfo.xcprivacy is not bundled")
        let data = try Data(contentsOf: plistURL)
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty, true)
        XCTAssertEqual((manifest["NSPrivacyTrackingDomains"] as? [Any])?.isEmpty, true)
        XCTAssertEqual(ReleaseInfo.privacyDeclaration, "Data Not Collected")
    }

    // MARK: - Plist/code consistency

    func testPlistMatchesReleaseInfoConstants() throws {
        let metadata = try loadMetadata()
        XCTAssertEqual(metadata["Version"] as? String, ReleaseInfo.version)
        XCTAssertEqual(metadata["BundleID"] as? String, ReleaseInfo.bundleID)
        XCTAssertEqual(metadata["Name"] as? String, ReleaseInfo.appTitle)
        XCTAssertEqual(metadata["Subtitle"] as? String, ReleaseInfo.subtitle)
        XCTAssertEqual(metadata["PrimaryCategory"] as? String, ReleaseInfo.primaryCategory)
        XCTAssertEqual(metadata["SecondaryCategory"] as? String, ReleaseInfo.secondaryCategory)
        XCTAssertEqual(metadata["PrivacyDeclaration"] as? String, ReleaseInfo.privacyDeclaration)
        XCTAssertEqual(metadata["Keywords"] as? String, ReleaseInfo.keywords)
        XCTAssertEqual(metadata["Description"] as? String, ReleaseInfo.description)
    }

    func testScreenshotPlanCoversCompactAndRegularWidth() throws {
        XCTAssertEqual(ReleaseInfo.screenshotPlan.count, 5)
        let displays = Set(ReleaseInfo.screenshotPlan.map(\.display))
        XCTAssertTrue(displays.contains { $0.hasPrefix("iPhone") }, "Compact-width slots required")
        XCTAssertTrue(displays.contains { $0.hasPrefix("iPad") }, "Regular-width two-column slot required")
        for slot in ReleaseInfo.screenshotPlan {
            XCTAssertFalse(slot.caption.isEmpty)
            XCTAssertLessThanOrEqual(slot.caption.utf16.count, 170, "Caption limit is 170 characters")
        }
    }
}
