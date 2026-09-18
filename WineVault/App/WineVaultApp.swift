import SwiftUI
import WineVaultData
import WineVaultDomain

@main
struct WineVaultApp: App {
    private let dependenciesLoader: ContentView.DependenciesLoader = {
        if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("WineVault-UITests-\(UUID().uuidString)", isDirectory: true)
            let stack = try WineVaultDataStack(rootDirectory: root)
            return InventoryDependencies(
                repository: stack.repository,
                savePhoto: { data, bottleID in
                    _ = try await stack.savePhoto(data, fileExtension: "jpg", for: bottleID)
                },
                photoData: { reference in try await stack.photos.data(for: reference) },
                deleteBottle: { id in try await stack.deleteBottle(id: id) },
                priceProvider: Self.uiTestPriceProvider()
            )
        }
        return try InventoryDependencies.appPrivateDefault()
    }

    /// The UI-test launch only ever talks to the deterministic fixture —
    /// never the network. `--ui-testing-price=<mode>` scripts the behavior:
    /// ok (default), no-results, timeout, or disabled.
    private static func uiTestPriceProvider() -> any PriceProviding {
        let arguments = ProcessInfo.processInfo.arguments
        let mode = arguments.first { $0.hasPrefix("--ui-testing-price=") }
            .map { String($0.dropFirst("--ui-testing-price=".count)) } ?? "ok"
        let behavior: FixturePriceProvider.Behavior
        switch mode {
        case "no-results": behavior = .noResults
        case "timeout": behavior = .timeout
        case "disabled": behavior = .disabled
        default: behavior = .canned
        }
        return FixturePriceProvider(behavior: behavior)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(dependenciesLoader: dependenciesLoader)
        }
    }
}
