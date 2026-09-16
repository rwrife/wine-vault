import Foundation

public enum BottleFormValidationIssue: String, Equatable, Sendable {
    case nameRequired
    case vintageInvalid
    case quantityMustBePositive

    public var message: String {
        switch self {
        case .nameRequired:
            "Enter a bottle name."
        case .vintageInvalid:
            "Enter a four-digit vintage, or leave it blank."
        case .quantityMustBePositive:
            "Quantity must be at least 1."
        }
    }
}

public enum BottleFormValidationError: Error, Equatable, Sendable {
    case invalid([BottleFormValidationIssue])
}

/// Editable, lossless form state that validates before producing a domain value.
public struct BottleForm: Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var producer: String
    public var vintage: String
    public var region: String
    public var grape: String
    public var quantity: Int
    public var storageLocation: String
    public var tags: [String]
    public var drinkBy: Date?
    public var photos: [PhotoReference]
    public var notes: String

    public init(
        id: UUID = UUID(),
        name: String = "",
        producer: String = "",
        vintage: String = "",
        region: String = "",
        grape: String = "",
        quantity: Int = 1,
        storageLocation: String = "",
        tags: [String] = [],
        drinkBy: Date? = nil,
        photos: [PhotoReference] = [],
        notes: String = ""
    ) {
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

    public init(bottle: Bottle) {
        self.init(
            id: bottle.id,
            name: bottle.name,
            producer: bottle.producer ?? "",
            vintage: bottle.vintage.map(String.init) ?? "",
            region: bottle.region ?? "",
            grape: bottle.grape ?? "",
            quantity: bottle.quantity,
            storageLocation: bottle.storageLocation,
            tags: bottle.tags,
            drinkBy: bottle.drinkBy,
            photos: bottle.photos,
            notes: bottle.notes ?? ""
        )
    }

    public var validationErrors: [BottleFormValidationIssue] {
        var issues: [BottleFormValidationIssue] = []
        if Self.trim(name).isEmpty {
            issues.append(.nameRequired)
        }
        let normalizedVintage = Self.trim(vintage)
        if !normalizedVintage.isEmpty,
           !Self.isFourDigitVintage(normalizedVintage) {
            issues.append(.vintageInvalid)
        }
        if quantity < 1 {
            issues.append(.quantityMustBePositive)
        }
        return issues
    }

    public func bottle() throws -> Bottle {
        let issues = validationErrors
        guard issues.isEmpty else {
            throw BottleFormValidationError.invalid(issues)
        }
        let normalizedVintage = Self.trim(vintage)
        return try Bottle(
            id: id,
            name: Self.trim(name),
            producer: Self.optional(producer),
            vintage: normalizedVintage.isEmpty ? nil : Int(normalizedVintage),
            region: Self.optional(region),
            grape: Self.optional(grape),
            quantity: quantity,
            storageLocation: Self.trim(storageLocation),
            tags: Self.normalizedTags(tags),
            drinkBy: drinkBy,
            photos: photos,
            notes: Self.optional(notes)
        )
    }

    private static func trim(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func optional(_ value: String) -> String? {
        let value = trim(value)
        return value.isEmpty ? nil : value
    }

    private static func isFourDigitVintage(_ value: String) -> Bool {
        value.utf8.count == 4
            && value.utf8.allSatisfy { (48...57).contains($0) }
            && Int(value).map { (1000...9999).contains($0) } == true
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        var seen: Set<String> = []
        return tags.compactMap { tag in
            let value = trim(tag)
            guard !value.isEmpty, seen.insert(value.folding(options: [.caseInsensitive], locale: nil)).inserted else {
                return nil
            }
            return value
        }
    }
}
