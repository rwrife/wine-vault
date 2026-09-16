import Foundation
import WineVaultDomain

public enum AppPrivatePathError: Error, Equatable, Sendable {
    case invalidApplicationSupportDirectory
    case invalidBundleIdentifier
    case unsafeRootDirectory
}

public enum AppPrivatePaths {
    public static func rootDirectory(
        applicationSupportDirectory: URL,
        bundleIdentifier: String
    ) throws -> URL {
        guard applicationSupportDirectory.isFileURL else {
            throw AppPrivatePathError.invalidApplicationSupportDirectory
        }
        let identifierComponents = bundleIdentifier.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard !identifierComponents.isEmpty,
              identifierComponents.allSatisfy({ component in
                  !component.isEmpty
                      && component.first != "-"
                      && component.last != "-"
                      && component.allSatisfy({
                          $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
                      })
              }) else {
            throw AppPrivatePathError.invalidBundleIdentifier
        }

        let support = applicationSupportDirectory.standardizedFileURL
        let root = support.appendingPathComponent(bundleIdentifier, isDirectory: true)
            .standardizedFileURL
        let canonicalSupport = support.resolvingSymlinksInPath().standardizedFileURL
        let expectedCanonicalRoot = canonicalSupport
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .standardizedFileURL
        let rootExists = FileManager.default.fileExists(atPath: root.path)
        let canonicalRoot = rootExists
            ? root.resolvingSymlinksInPath().standardizedFileURL
            : expectedCanonicalRoot
        guard root.deletingLastPathComponent().path == support.path,
              canonicalRoot.path == expectedCanonicalRoot.path else {
            throw AppPrivatePathError.unsafeRootDirectory
        }
        if rootExists, try !PhotoStore.isPlainDirectory(root) {
            throw AppPrivatePathError.unsafeRootDirectory
        }
        return root
    }

    public static func defaultRootDirectory(
        bundleIdentifier: String = "com.infinityball.winevault"
    ) throws -> URL {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw AppPrivatePathError.invalidApplicationSupportDirectory
        }
        return try rootDirectory(
            applicationSupportDirectory: applicationSupport,
            bundleIdentifier: bundleIdentifier
        )
    }
}

/// Shared app wiring for the SQLite repository and app-private photo library.
public struct WineVaultDataStack: Sendable {
    public let rootDirectory: URL
    public let repository: SQLiteBottleRepository
    public let photos: PhotoStore
    let coordinator: DataAccessCoordinator

    public init(rootDirectory: URL) throws {
        let root = rootDirectory.standardizedFileURL
        if FileManager.default.fileExists(atPath: root.path),
           try !PhotoStore.isPlainDirectory(root) {
            throw AppPrivatePathError.unsafeRootDirectory
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        guard try PhotoStore.isPlainDirectory(root) else {
            throw AppPrivatePathError.unsafeRootDirectory
        }

        let coordinator = DataAccessCoordinator.sharedStorage
        self.coordinator = coordinator
        self.rootDirectory = root
        let photoStore = try PhotoStore(
            rootDirectory: root,
            coordinator: coordinator,
            isManagedByDataStack: true
        )
        photos = photoStore
        repository = try SQLiteBottleRepository(
            databaseURL: root.appendingPathComponent("vault.sqlite"),
            coordinator: coordinator,
            photoStore: photoStore
        )
    }

    /// Saves a photo and establishes its bottle reference as one exclusive operation.
    public func savePhoto(
        _ data: Data,
        fileExtension: String,
        for bottleID: UUID
    ) async throws -> PhotoReference {
        try await coordinator.withExclusiveAccess {
            guard var bottle = try await repository.bottleWithoutCoordination(id: bottleID) else {
                throw RepositoryError.bottleNotFound(bottleID)
            }
            let reference = try await photos.saveWithoutCoordination(
                data,
                fileExtension: fileExtension
            )
            bottle.photos.append(reference)
            do {
                try await repository.validatePhotoReferencesWithoutCoordination(bottle.photos)
                try await repository.updateWithoutCoordination(bottle)
                return reference
            } catch {
                try? await photos.deleteWithoutCoordination(reference)
                throw error
            }
        }
    }

    /// Detaches a photo and removes its file when no bottle still references it.
    public func deletePhoto(_ reference: PhotoReference, from bottleID: UUID) async throws {
        try await coordinator.withExclusiveAccess {
            guard var bottle = try await repository.bottleWithoutCoordination(id: bottleID) else {
                throw RepositoryError.bottleNotFound(bottleID)
            }
            bottle.photos.removeAll { $0 == reference }
            try await repository.validatePhotoReferencesWithoutCoordination(bottle.photos)
            try await repository.updateWithoutCoordination(bottle)
            let remaining = try await repository.photoReferencesWithoutCoordination()
            if !remaining.contains(reference) {
                try await photos.deleteWithoutCoordination(reference)
            }
        }
    }

    /// Deletes a bottle and removes only photos no remaining bottle references.
    public func deleteBottle(id: UUID) async throws {
        try await coordinator.withExclusiveAccess {
            guard let bottle = try await repository.bottleWithoutCoordination(id: id) else {
                throw RepositoryError.bottleNotFound(id)
            }
            try await repository.deleteBottleWithoutCoordination(id: id)
            let remainingReferences = try await repository.photoReferencesWithoutCoordination()
            for reference in Set(bottle.photos) where !remainingReferences.contains(reference) {
                try await photos.deleteWithoutCoordination(reference)
            }
        }
    }

    /// Removes orphan files while repository mutations and photo saves are excluded.
    @discardableResult
    public func garbageCollectOrphanPhotos() async throws -> [PhotoReference] {
        try await coordinator.withExclusiveAccess {
            let references = try await repository.photoReferencesWithoutCoordination()
            return try await photos.garbageCollectWithoutCoordination(keeping: references)
        }
    }

    public static func appPrivateDefault(
        bundleIdentifier: String = "com.infinityball.winevault"
    ) throws -> WineVaultDataStack {
        try WineVaultDataStack(
            rootDirectory: AppPrivatePaths.defaultRootDirectory(
                bundleIdentifier: bundleIdentifier
            )
        )
    }
}
