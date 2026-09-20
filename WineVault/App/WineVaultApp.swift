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
            if ProcessInfo.processInfo.arguments.contains(Self.seedLaunchArgument) {
                try await Self.seedRepository(stack.repository)
            }
            return InventoryDependencies(
                repository: stack.repository,
                savePhoto: { data, bottleID in
                    _ = try await stack.savePhoto(data, fileExtension: "jpg", for: bottleID)
                },
                photoData: { reference in try await stack.photos.data(for: reference) },
                deleteBottle: { id in try await stack.deleteBottle(id: id) },
                priceProvider: Self.uiTestPriceProvider(),
                reminderScheduling: InertReminderScheduler()
            )
        }
        return try InventoryDependencies.appPrivateDefault()
    }

    /// Seed bottles for UI tests that assert on populated screens
    /// (`--ui-testing-seed=wine-vault`). Deterministic, offline, and applied
    /// only on a fresh temporary store, so exact counts are stable.
    nonisolated static let seedLaunchArgument = "--ui-testing-seed=wine-vault"

    nonisolated private static func seedRepository(_ repository: BottleRepository) async throws {
        let reference = Date()
        for seed in uiTestSeedBottles {
            try await repository.create(Bottle(seed: seed, reference: reference))
        }
    }

    /// The UI-test launch only ever talks to the deterministic fixture —
    /// never the network. `--ui-testing-price=<mode>` scripts the behavior:
    /// ok (default), no-results, timeout, or disabled.
    nonisolated private static func uiTestPriceProvider() -> any PriceProviding {
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
