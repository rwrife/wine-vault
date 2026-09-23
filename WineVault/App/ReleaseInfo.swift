import Foundation

// The single source of truth for App Store / TestFlight metadata (issue #7).
//
// `WineVault/AppStoreMetadata.plist` mirrors these constants for release
// tooling and App Store Connect entry, and `ReleaseMetadataTests` locks the
// two together so drift fails CI instead of shipping inconsistent
// storefront copy. Keep the copy honest: quotes are dated estimates, data
// stays on-device, and no alcohol-health claims ever appear here.

enum ReleaseInfo {
    /// Keep in sync with `MARKETING_VERSION` in `project.yml` —
    /// `Scripts/validate_project_yml.sh` asserts the pairing on Linux CI.
    static let version = "0.1.0"

    static let bundleID = "com.infinityball.winevault"

    /// App Store field-length limits are asserted in `ReleaseMetadataTests`.
    static let appTitle = "Wine Vault"
    static let subtitle = "Local-first cellar inventory"
    static let primaryCategory = "FOOD_AND_DRINK"
    static let secondaryCategory = "UTILITIES"

    /// Matches the shipped `PrivacyInfo.xcprivacy` (no tracking, no
    /// collected data); the cross-check lives in `ReleaseMetadataTests`.
    static let privacyDeclaration = "Data Not Collected"

    /// Comma-separated, 100-character field.
    static let keywords =
        "wine,cellar,inventory,bottle,drink by,valuation,collector,offline"

    /// Store description assembled from parts so source lines stay lint
    /// clean while the shipped string keeps paragraph breaks only where the
    /// App Store needs them.
    static let description: String =
        releaseIntro + "\n\n" + releaseBullets.joined(separator: "\n")

    private static let releaseIntro =
        "Wine Vault is a local-first cellar inventory for your home wine "
        + "collection. Track bottles, quantities, vintages, regions, grapes, "
        + "storage locations, and drink-by notes — entirely on your iPhone."

    private static let releaseBullets: [String] = [
        "• Fully offline. Every record lives on your device. "
            + "No account, no cloud database, no subscription.",
        "• Photos stay private. Optional label photos stay in the app's own "
            + "storage and never leave your phone.",
        "• Value on demand. Opt-in price lookup returns dated reference "
            + "quotes with their source — estimates with provenance, never "
            + "authoritative prices; manual price entry always works offline.",
        "• Understand the collection. Drink-by timeline, dashboards by "
            + "region and grape, and a value chart built only from your own "
            + "stored quotes.",
        "• Your data, exportable. CSV export and ZIP backups — including "
            + "photos — restore on a new device in one step.",
        "• No telemetry, no tracking, no data collected — confirmed by the "
            + "app's own privacy manifest.",
    ]

    struct ScreenshotSlot: Equatable, Sendable {
        let display: String
        let pixelSize: String
        let caption: String
    }

    /// Placeholder plan, not assets: which screenshots to produce, at which
    /// App Store display families, and what each must show. The iPad slot
    /// documents the shipped regular-width two-column layout — the same
    /// adaptive surface that is the documented iPhone Duo migration path.
    static let screenshotPlan: [ScreenshotSlot] = [
        ScreenshotSlot(
            display: "iPhone 6.9\" (1320x2868)",
            pixelSize: "1320x2868",
            caption: "Browse the whole cellar — bottles, vintages, "
                + "and locations, fully offline."
        ),
        ScreenshotSlot(
            display: "iPhone 6.9\" (1320x2868)",
            pixelSize: "1320x2868",
            caption: "Request a dated value estimate only when you want "
                + "one; confirm matches yourself."
        ),
        ScreenshotSlot(
            display: "iPhone 6.9\" (1320x2868)",
            pixelSize: "1320x2868",
            caption: "See what's ready to drink on the drink-by timeline."
        ),
        ScreenshotSlot(
            display: "iPhone 6.9\" (1320x2868)",
            pixelSize: "1320x2868",
            caption: "Export CSV or a ZIP backup with photos and restore "
                + "it on a new device."
        ),
        ScreenshotSlot(
            display: "iPad 13\" (2064x2752)",
            pixelSize: "2064x2752",
            caption: "Two-column browsing on wide layouts — the same "
                + "adaptive design on every device."
        ),
    ]
}
