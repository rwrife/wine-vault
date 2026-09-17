import SwiftUI
import WineVaultData

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
                deleteBottle: { id in try await stack.deleteBottle(id: id) }
            )
        }
        return try InventoryDependencies.appPrivateDefault()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(dependenciesLoader: dependenciesLoader)
        }
    }
}
