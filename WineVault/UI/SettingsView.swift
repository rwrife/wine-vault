import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WineVaultData
import WineVaultDomain

/// Settings: export & backup controls plus the privacy/permission audit
/// page (issue #6). The audit text is required to match the shipped
/// PrivacyInfo.xcprivacy — the unit test `PrivacyAuditMatchesManifestTests`
/// parses the bundled plist and asserts each claim here.
struct SettingsView: View {
    @ObservedObject var store: InventoryStore
    @State private var sharePayload: SharePayload?
    @State private var showingRestorePicker = false
    @State private var pendingRestoreURL: URL?
    @State private var showingStrategyChooser = false
    @State private var restoreImportError: String?

    private static let privacyStatement = """
        Wine Vault collects nothing. There are no accounts, no analytics, \
        and no advertising. Your bottles, notes, and photos live only in \
        this app's private storage on this device. Files leave the device \
        only when you export them yourself or ask for a price lookup.
        """

    var body: some View {
        List {
            Section("Export & backup") {
                Button {
                    Task {
                        await store.exportInventoryCSV()
                        if let csv = store.csvShareData {
                            sharePayload = SharePayload(
                                data: csv,
                                fileName: "wine-vault-inventory.csv",
                                contentType: .commaSeparatedText
                            )
                        }
                    }
                } label: {
                    Label("Export inventory CSV", systemImage: "tablecells")
                }
                .accessibilityIdentifier("exportCSVButton")
                Text(
                    "One row per bottle with its latest confirmed quote, currency, "
                        + "quote date, and source. Only fields you entered — no "
                        + "identifiers or location data."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button {
                    Task {
                        await store.createBackup()
                        if let zip = store.zipShareData {
                            sharePayload = SharePayload(
                                data: zip,
                                fileName: store.suggestedBackupName,
                                contentType: .zip
                            )
                        }
                    }
                } label: {
                    Label("Back up everything (ZIP)", systemImage: "archivebox")
                }
                .accessibilityIdentifier("createBackupButton")
                .disabled(!store.isBackupAvailable || store.isExporting)
                Text(
                    "Versioned manifest, database snapshot, and every label photo, "
                        + "with checksums. The ZIP opens on any computer."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)

                Button {
                    showingRestorePicker = true
                } label: {
                    Label("Restore from backup", systemImage: "arrow.down.doc")
                }
                .accessibilityIdentifier("restoreBackupButton")
                .disabled(!store.isBackupAvailable || store.isExporting)

                if let message = store.backupMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("backupMessage")
                }
                if let importError = restoreImportError {
                    Text(importError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("restoreImportError")
                }
            }

            Section("Privacy & permissions") {
                PrivacyPermissionRow(
                    title: "Camera",
                    usage: """
                        Photograph a wine label when you choose. Photos are saved to this \
                        app's private storage; the system Photo Library is never touched.
                        """,
                    degrades: """
                        Without camera access you can add bottles and photos manually — \
                        every other feature works.
                        """
                )
                PrivacyPermissionRow(
                    title: "Notifications",
                    usage: """
                        Optional drink-by reminders. Scheduling only starts after you flip \
                        the reminders toggle on the drink-by timeline.
                        """,
                    degrades: """
                        If notifications are denied or off, reminders simply don't fire; \
                        the in-app drink-by timeline always shows every date.
                        """
                )
                PrivacyPermissionRow(
                    title: "Network",
                    usage: """
                        Used only for price lookups you start yourself. A lookup sends only \
                        the search text you chose — no collection data, no identifiers.
                        """,
                    degrades: "The app is fully usable offline; manual price entry is the fallback."
                )
                .accessibilityIdentifier("privacyNetworkRow")

                VStack(alignment: .leading, spacing: 6) {
                    Text("What is never collected")
                        .font(.headline)
                    Text(Self.privacyStatement)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(
                        "This matches the app's privacy manifest: no tracking, "
                            + "no tracking domains, and no collected data types."
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("privacyNeverCollected")

                if store.isReminderSchedulingAvailable {
                    NavigationLink {
                        RemindersPermissionView(store: store)
                    } label: {
                        Label("Drink-by reminders toggle", systemImage: "bell")
                    }
                    .accessibilityIdentifier("remindersToggleLink")
                }
            }
        }
        .navigationTitle("Settings")
        .sheet(item: $sharePayload) { payload in
            ShareSheetContainer(items: [payload.item])
        }
        .fileImporter(
            isPresented: $showingRestorePicker,
            allowedContentTypes: [.zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls) where urls.first != nil:
                let url = urls[0]
                // Access must be claimed while scoped; copy to a stable
                // temporary location before the restore flow starts.
                guard url.startAccessingSecurityScopedResource() else {
                    restoreImportError = "Wine Vault could not open that file."
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                do {
                    let data = try Data(contentsOf: url)
                    let staged = FileManager.default.temporaryDirectory
                        .appendingPathComponent("restore-\(UUID().uuidString).zip")
                    try data.write(to: staged, options: .atomic)
                    pendingRestoreURL = staged
                    restoreImportError = nil
                    showingStrategyChooser = true
                } catch {
                    restoreImportError = "That backup file could not be read."
                }
            default:
                restoreImportError = "No backup file was selected."
            }
        }
        .confirmationDialog(
            "How should this backup be applied?",
            isPresented: $showingStrategyChooser,
            titleVisibility: .visible
        ) {
            Button("Merge") {
                startPendingRestore(strategy: .merge)
            }
            .accessibilityIdentifier("restoreMergeButton")
            Button("Replace everything") {
                startPendingRestore(strategy: .replace)
            }
            .accessibilityIdentifier("restoreReplaceButton")
            Button("Cancel", role: .cancel) {
                discardPendingRestore()
            }
        } message: {
            Text(
                "Merge: adds the backup's bottles and replaces same-identifier "
                    + "records; anything only on this device is kept. Replace: "
                    + "erases all current bottles, quotes, and photos first. "
                    + "Either way, a failed restore leaves your current data intact."
            )
        }
    }

    private func startPendingRestore(strategy: BackupRestoreStrategy) {
        guard let url = pendingRestoreURL else { return }
        pendingRestoreURL = nil
        Task {
            defer { try? FileManager.default.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url) else {
                store.backupMessage = "That backup file could not be read."
                return
            }
            await store.restore(zipData: data, strategy: strategy)
        }
    }

    private func discardPendingRestore() {
        if let url = pendingRestoreURL {
            try? FileManager.default.removeItem(at: url)
        }
        pendingRestoreURL = nil
    }
}

private struct PrivacyPermissionRow: View {
    let title: String
    let usage: String
    let degrades: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(usage).font(.footnote).foregroundStyle(.secondary)
            Text("Without it: \(degrades)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Deep-links the user to the system permission screen for reminders —
/// the revoke shortcut Apple allows in-app.
private struct RemindersPermissionView: View {
    @ObservedObject var store: InventoryStore

    var body: some View {
        List {
            Text(
                "Reminders respect the toggle on the drink-by timeline. "
                    + "You can revoke notification access at any time in the "
                    + "system Settings; the timeline keeps working."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            Button("Open system Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .accessibilityIdentifier("openSystemSettingsButton")
        }
        .navigationTitle("Notifications")
    }
}

/// One shared-sheet payload with a file name + type so receivers see a
/// proper file rather than anonymous data.
struct SharePayload: Identifiable, Sendable {
    let data: Data
    let fileName: String
    let contentType: UTType
    var id: String { fileName }

    var item: ShareItem { ShareItem(self) }
}

/// File-wrapped activity item so the share sheet writes a real file.
struct ShareItem: Transferable {
    private let payload: SharePayload

    init(_ payload: SharePayload) {
        self.payload = payload
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .data) { item in
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(item.fileName)
            try item.data.write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }

    var data: Data { payload.data }
    var fileName: String { payload.fileName }
}

/// Minimal UIActivityViewController wrapper for the classic share sheet.
struct ShareSheetContainer: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
