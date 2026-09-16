import SwiftUI
import WineVaultData

struct ContentView: View {
    typealias DependenciesLoader = @Sendable () async throws -> InventoryDependencies

    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private let dependenciesLoader: DependenciesLoader?
    @State private var loadState = LoadState.loading
    @State private var store: InventoryStore?

    init(repository: (any BottleRepository)? = nil) {
        dependenciesLoader = repository.map { repository in
            { InventoryDependencies(repository: repository) }
        }
    }

    init(repositoryLoader: @escaping @Sendable () async throws -> any BottleRepository) {
        dependenciesLoader = {
            InventoryDependencies(repository: try await repositoryLoader())
        }
    }

    init(dependenciesLoader: @escaping DependenciesLoader) {
        self.dependenciesLoader = dependenciesLoader
    }

    var body: some View {
        Group {
            switch (loadState, store) {
            case (.loading, _):
                ProgressView("Opening your collection…")
            case let (.ready, store?):
                CollectionView(store: store)
            case let (.failed(message), _):
                ContentUnavailableView {
                    Label("Collection unavailable", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try Again") { Task { await loadDependencies() } }
                        .accessibilityIdentifier("retryButton")
                }
            default:
                ProgressView("Opening your collection…")
            }
        }
        .task { await loadDependencies() }
    }

    @MainActor
    private func loadDependencies() async {
        loadState = .loading
        do {
            let dependencies = try await dependenciesLoader?()
                ?? InventoryDependencies(repository: SQLiteBottleRepository(inMemory: true))
            let store = InventoryStore(dependencies: dependencies)
            await store.load()
            if let message = store.errorMessage {
                loadState = .failed(message)
            } else {
                self.store = store
                loadState = .ready
            }
        } catch {
            loadState = .failed("Your local collection could not be opened. \(error.localizedDescription)")
        }
    }

    static func load(using loader: (@Sendable () async throws -> any BottleRepository)?) async -> LoadState {
        guard let loader else { return .ready }
        do {
            _ = try await loader().bottles()
            return .ready
        } catch {
            return .failed("Your local collection could not be opened. \(error.localizedDescription)")
        }
    }
}

#Preview {
    ContentView()
}
