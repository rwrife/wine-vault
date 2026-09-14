import SwiftUI
import WineVaultData

@main
struct WineVaultApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(repositoryLoader: {
                try WineVaultDataStack.appPrivateDefault().repository
            })
        }
    }
}
