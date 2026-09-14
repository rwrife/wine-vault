import Foundation
import WineVaultDomain

public enum PhotoStoreError: Error, Equatable, Sendable {
    case unsafeReference
    case unsafeFileExtension
    case photoNotFound
    case managedByDataStack
}

struct FileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64

    static func capture(_ url: URL, type: FileAttributeType) throws -> FileIdentity {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == type,
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else {
            throw PhotoStoreError.unsafeReference
        }
        return FileIdentity(
            device: device.uint64Value,
            inode: inode.uint64Value
        )
    }
}

/// Stores label images below an explicitly app-private root directory.
public actor PhotoStore {
    private let rootDirectory: URL
    private let photosDirectory: URL
    private let canonicalRootDirectory: URL
    private let canonicalPhotosDirectory: URL
    private let rootIdentity: FileIdentity
    private let photosIdentity: FileIdentity
    private let coordinator: DataAccessCoordinator
    private let isManagedByDataStack: Bool

    public init(rootDirectory: URL) throws {
        try self.init(
            rootDirectory: rootDirectory,
            coordinator: DataAccessCoordinator(),
            isManagedByDataStack: false
        )
    }

    init(
        rootDirectory: URL,
        coordinator: DataAccessCoordinator,
        isManagedByDataStack: Bool
    ) throws {
        let root = rootDirectory.standardizedFileURL
        guard try Self.isPlainDirectory(root) else {
            throw PhotoStoreError.unsafeReference
        }
        let photos = root.appendingPathComponent("photos", isDirectory: true).standardizedFileURL
        if FileManager.default.fileExists(atPath: photos.path),
           try !Self.isPlainDirectory(photos) {
            throw PhotoStoreError.unsafeReference
        }
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        guard try Self.isPlainDirectory(photos) else {
            throw PhotoStoreError.unsafeReference
        }

        self.rootDirectory = root
        photosDirectory = photos
        canonicalRootDirectory = root.resolvingSymlinksInPath().standardizedFileURL
        canonicalPhotosDirectory = photos.resolvingSymlinksInPath().standardizedFileURL
        rootIdentity = try FileIdentity.capture(root, type: .typeDirectory)
        photosIdentity = try FileIdentity.capture(photos, type: .typeDirectory)
        self.coordinator = coordinator
        self.isManagedByDataStack = isManagedByDataStack
    }

    func save(_ data: Data, fileExtension: String) async throws -> PhotoReference {
        try await coordinator.withExclusiveAccess {
            try await self.saveWithoutCoordination(data, fileExtension: fileExtension)
        }
    }

    public func data(for reference: PhotoReference) async throws -> Data {
        try await coordinator.withExclusiveAccess {
            try await self.dataWithoutCoordination(for: reference)
        }
    }

    public func delete(_ reference: PhotoReference) async throws {
        try await coordinator.withExclusiveAccess {
            guard !self.isManagedByDataStack else {
                throw PhotoStoreError.managedByDataStack
            }
            try await self.deleteWithoutCoordination(reference)
        }
    }

    @discardableResult
    func garbageCollect(keeping references: Set<PhotoReference>) async throws -> [PhotoReference] {
        try await coordinator.withExclusiveAccess {
            try await self.garbageCollectWithoutCoordination(keeping: references)
        }
    }

    func saveWithoutCoordination(
        _ data: Data,
        fileExtension: String
    ) throws -> PhotoReference {
        guard (1...10).contains(fileExtension.count),
              fileExtension.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
            throw PhotoStoreError.unsafeFileExtension
        }
        try validateDirectories()
        let filename = "\(UUID().uuidString.lowercased()).\(fileExtension.lowercased())"
        let reference = try PhotoReference("photos/\(filename)")
        let destination = try safeURL(for: reference, mayNotExist: true)
        try data.write(to: destination, options: .atomic)
        try validateDirectories()
        return reference
    }

    func dataWithoutCoordination(for reference: PhotoReference) throws -> Data {
        let url = try safeURL(for: reference, mayNotExist: false)
        return try Data(contentsOf: url)
    }

    func validateWithoutCoordination(_ reference: PhotoReference) throws {
        _ = try safeURL(for: reference, mayNotExist: false)
    }

    func deleteWithoutCoordination(_ reference: PhotoReference) throws {
        let url = try safeURL(for: reference, mayNotExist: false)
        try validateDirectories()
        try FileManager.default.removeItem(at: url)
    }

    func garbageCollectWithoutCoordination(
        keeping references: Set<PhotoReference>
    ) throws -> [PhotoReference] {
        try validateDirectories()
        let keptPaths = Set(references.map(\.path))
        let urls = try FileManager.default.contentsOfDirectory(
            at: photosDirectory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )
        var removed: [PhotoReference] = []
        for url in urls {
            guard let reference = try? PhotoReference("photos/\(url.lastPathComponent)"),
                  !keptPaths.contains(reference.path) else {
                continue
            }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true || values.isSymbolicLink == true else { continue }
            try validateDirectories()
            guard url.deletingLastPathComponent().standardizedFileURL.path == photosDirectory.path else {
                throw PhotoStoreError.unsafeReference
            }
            try FileManager.default.removeItem(at: url)
            removed.append(reference)
        }
        return removed.sorted { $0.path < $1.path }
    }

    private func safeURL(for reference: PhotoReference, mayNotExist: Bool) throws -> URL {
        try validateDirectories()
        let filename = URL(fileURLWithPath: reference.path).lastPathComponent
        let candidate = photosDirectory.appendingPathComponent(filename).standardizedFileURL
        guard candidate.deletingLastPathComponent().path == photosDirectory.path else {
            throw PhotoStoreError.unsafeReference
        }
        if FileManager.default.fileExists(atPath: candidate.path) {
            let values = try candidate.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
            )
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw PhotoStoreError.unsafeReference
            }
        } else if !mayNotExist {
            throw PhotoStoreError.photoNotFound
        }
        return candidate
    }

    private func validateDirectories() throws {
        guard try Self.isPlainDirectory(rootDirectory),
              try Self.isPlainDirectory(photosDirectory),
              rootDirectory.resolvingSymlinksInPath().standardizedFileURL.path
                == canonicalRootDirectory.path,
              photosDirectory.resolvingSymlinksInPath().standardizedFileURL.path
                == canonicalPhotosDirectory.path,
              canonicalPhotosDirectory.deletingLastPathComponent().path
                == canonicalRootDirectory.path,
              try FileIdentity.capture(rootDirectory, type: .typeDirectory) == rootIdentity,
              try FileIdentity.capture(photosDirectory, type: .typeDirectory) == photosIdentity else {
            throw PhotoStoreError.unsafeReference
        }
    }

    static func isPlainDirectory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values.isDirectory == true && values.isSymbolicLink != true
    }
}
