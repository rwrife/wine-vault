import Foundation
import SwiftUI
import WineVaultData
import WineVaultDomain

struct InventoryDependencies: Sendable {
    let repository: any BottleRepository
    let savePhoto: @Sendable (Data, UUID) async throws -> Void
    let photoData: @Sendable (PhotoReference) async throws -> Data

    init(
        repository: any BottleRepository,
        savePhoto: @escaping @Sendable (Data, UUID) async throws -> Void = { _, _ in },
        photoData: @escaping @Sendable (PhotoReference) async throws -> Data = { _ in Data() }
    ) {
        self.repository = repository
        self.savePhoto = savePhoto
        self.photoData = photoData
    }

    static func appPrivateDefault() throws -> InventoryDependencies {
        let stack = try WineVaultDataStack.appPrivateDefault()
        return InventoryDependencies(
            repository: stack.repository,
            savePhoto: { data, bottleID in
                _ = try await stack.savePhoto(data, fileExtension: "jpg", for: bottleID)
            },
            photoData: { reference in
                try await stack.photos.data(for: reference)
            }
        )
    }
}

@MainActor
final class InventoryStore: ObservableObject {
    @Published private(set) var bottles: [Bottle] = []
    @Published var criteria = BottleFilterCriteria()
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let dependencies: InventoryDependencies

    init(repository: any BottleRepository) {
        dependencies = InventoryDependencies(repository: repository)
    }

    init(dependencies: InventoryDependencies) {
        self.dependencies = dependencies
    }

    var filteredBottles: [Bottle] {
        filterBottles(bottles, criteria: criteria, reference: Date())
    }

    var facets: BottleFilterFacets {
        bottleFilterFacets(bottles)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            bottles = try await dependencies.repository.bottles()
            errorMessage = nil
        } catch {
            errorMessage = "Your collection could not be loaded. \(error.localizedDescription)"
        }
    }

    @discardableResult
    func save(_ form: BottleForm, photoData: Data? = nil) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let bottle = try form.bottle()
            // Ask the repository rather than the last loaded snapshot. A photo write can
            // fail after the bottle itself was created; a retry must update that record
            // instead of getting stuck on a duplicate identifier.
            if try await dependencies.repository.bottle(id: bottle.id) != nil {
                try await dependencies.repository.update(bottle)
            } else {
                try await dependencies.repository.create(bottle)
            }
            if let photoData {
                try await dependencies.savePhoto(photoData, bottle.id)
            }
            await load()
            return true
        } catch BottleFormValidationError.invalid(_) {
            return false
        } catch {
            errorMessage = "The bottle could not be saved. \(error.localizedDescription)"
            await loadPreservingError()
            return false
        }
    }

    func delete(_ bottle: Bottle) async {
        do {
            try await dependencies.repository.deleteBottle(id: bottle.id)
            await load()
        } catch {
            errorMessage = "The bottle could not be deleted. \(error.localizedDescription)"
        }
    }

    func photoData(for reference: PhotoReference) async throws -> Data {
        try await dependencies.photoData(reference)
    }

    func clearFilters() {
        criteria = BottleFilterCriteria()
    }

    private func loadPreservingError() async {
        let saveError = errorMessage
        await load()
        errorMessage = saveError
    }
}
