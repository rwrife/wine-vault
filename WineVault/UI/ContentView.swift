import SwiftUI
import WineVaultData

/// Placeholder root view (issue #1 skeleton).
///
/// Opens the local repository and surfaces a retryable error if startup fails.
/// The real browse/detail navigation lands with the core workflow UI issue.
struct ContentView: View {
    typealias RepositoryLoader = @Sendable () async throws -> any BottleRepository

    enum LoadState: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private let repositoryLoader: RepositoryLoader?
    @State private var loadState = LoadState.loading

    init(repository: (any BottleRepository)? = nil) {
        if let repository {
            repositoryLoader = { repository }
        } else {
            repositoryLoader = nil
        }
    }

    init(repositoryLoader: @escaping RepositoryLoader) {
        self.repositoryLoader = repositoryLoader
    }

    var body: some View {
        NavigationStack {
            content
            .navigationTitle("Wine Vault")
        }
        .task {
            await loadRepository()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch loadState {
        case .loading:
            ProgressView("Opening your collection…")
        case .ready:
            ContentUnavailableView(
                "Wine Vault",
                systemImage: "wineglass",
                description: Text("Collection coming soon. Local-first, always.")
            )
        case let .failed(message):
            ContentUnavailableView {
                Label("Collection unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await loadRepository() }
                }
            }
        }
    }

    @MainActor
    private func loadRepository() async {
        loadState = .loading
        loadState = await Self.load(using: repositoryLoader)
    }

    static func load(using loader: RepositoryLoader?) async -> LoadState {
        guard let loader else { return .ready }
        do {
            let repository = try await loader()
            _ = try await repository.bottles()
            return .ready
        } catch {
            return .failed("Your local collection could not be opened. \(error.localizedDescription)")
        }
    }
}

#Preview {
    ContentView()
}
