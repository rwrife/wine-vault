import Foundation

public enum DomainValidationError: Error, Equatable, Sendable {
    case nonPositiveQuantity
    case unsafePhotoReference
    case invalidQuoteAmount
    case missingQuoteProvenance
    case emptyPriceQuery
}

/// A validated path below the app-private photo directory.
public struct PhotoReference: Codable, Hashable, Sendable {
    public let path: String

    /// File name component of the reference (the last path element).
    public var fileName: String {
        String(path.split(separator: "/").last ?? Substring(path))
    }

    public init(_ path: String) throws {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2,
              components[0] == "photos",
              !components[1].isEmpty,
              !components[1].hasPrefix("."),
              !path.contains("\\"),
              path.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw DomainValidationError.unsafePhotoReference
        }
        self.path = path
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        try self.init(container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(path)
    }
}

public struct Bottle: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var producer: String?
    public var vintage: Int?
    public var region: String?
    public var grape: String?
    public private(set) var quantity: Int
    public var storageLocation: String
    public var tags: [String]
    public var drinkBy: Date?
    public var photos: [PhotoReference]
    public var notes: String?

    public init(
        id: UUID = UUID(),
        name: String,
        producer: String? = nil,
        vintage: Int? = nil,
        region: String? = nil,
        grape: String? = nil,
        quantity: Int,
        storageLocation: String,
        tags: [String] = [],
        drinkBy: Date? = nil,
        photos: [PhotoReference] = [],
        notes: String? = nil
    ) throws {
        guard quantity > 0 else {
            throw DomainValidationError.nonPositiveQuantity
        }
        self.id = id
        self.name = name
        self.producer = producer
        self.vintage = vintage
        self.region = region
        self.grape = grape
        self.quantity = quantity
        self.storageLocation = storageLocation
        self.tags = tags
        self.drinkBy = drinkBy
        self.photos = photos
        self.notes = notes
    }

    public mutating func setQuantity(_ quantity: Int) throws {
        guard quantity > 0 else {
            throw DomainValidationError.nonPositiveQuantity
        }
        self.quantity = quantity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id: container.decode(UUID.self, forKey: .id),
            name: container.decode(String.self, forKey: .name),
            producer: container.decodeIfPresent(String.self, forKey: .producer),
            vintage: container.decodeIfPresent(Int.self, forKey: .vintage),
            region: container.decodeIfPresent(String.self, forKey: .region),
            grape: container.decodeIfPresent(String.self, forKey: .grape),
            quantity: container.decode(Int.self, forKey: .quantity),
            storageLocation: container.decode(String.self, forKey: .storageLocation),
            tags: container.decode([String].self, forKey: .tags),
            drinkBy: container.decodeIfPresent(Date.self, forKey: .drinkBy),
            photos: container.decode([PhotoReference].self, forKey: .photos),
            notes: container.decodeIfPresent(String.self, forKey: .notes)
        )
    }
}
