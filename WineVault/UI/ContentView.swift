import SwiftUI
import WineVaultDomain

/// Placeholder root view (issue #1 skeleton).
///
/// No store, no network — the skeleton gate only proves the app target
/// builds and tests run on the iOS 26 simulator. The real browse/detail
/// navigation lands with the core workflow UI issue.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Wine Vault",
                systemImage: "wineglass",
                description: Text("Collection coming soon. Local-first, always.")
            )
            .navigationTitle("Wine Vault")
        }
    }
}

#Preview {
    ContentView()
}
