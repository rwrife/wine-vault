import Foundation

public struct BottleFilterCriteria: Equatable, Sendable {
    public var searchText: String
    public var region: String?
    public var grape: String?
    public var tag: String?
    public var drinkBy: DrinkByState?

    public init(
        searchText: String = "",
        region: String? = nil,
        grape: String? = nil,
        tag: String? = nil,
        drinkBy: DrinkByState? = nil
    ) {
        self.searchText = searchText
        self.region = region
        self.grape = grape
        self.tag = tag
        self.drinkBy = drinkBy
    }

    public var isFiltering: Bool {
        !normalized(searchText).isEmpty
            || region != nil
            || grape != nil
            || tag != nil
            || drinkBy != nil
    }
}

public struct BottleFilterFacets: Equatable, Sendable {
    public let regions: [String]
    public let grapes: [String]
    public let tags: [String]
}

public func filterBottles(
    _ bottles: [Bottle],
    criteria: BottleFilterCriteria,
    reference: Date,
    calendar: Calendar = .current
) -> [Bottle] {
    let search = normalized(criteria.searchText)
    return bottles.filter { bottle in
        let matchesSearch = search.isEmpty || [bottle.name, bottle.producer, bottle.region]
            .compactMap { $0 }
            .contains { normalized($0).contains(search) }
        let matchesRegion = matches(bottle.region, criteria.region)
        let matchesGrape = matches(bottle.grape, criteria.grape)
        let matchesTag = criteria.tag.map { selected in
            bottle.tags.contains { normalized($0) == normalized(selected) }
        } ?? true
        let matchesDrinkBy = criteria.drinkBy.map {
            drinkByState(drinkBy: bottle.drinkBy, reference: reference, calendar: calendar) == $0
        } ?? true
        return matchesSearch && matchesRegion && matchesGrape && matchesTag && matchesDrinkBy
    }
}

public func bottleFilterFacets(_ bottles: [Bottle]) -> BottleFilterFacets {
    BottleFilterFacets(
        regions: facetValues(bottles.compactMap(\.region)),
        grapes: facetValues(bottles.compactMap(\.grape)),
        tags: facetValues(bottles.flatMap(\.tags))
    )
}

private func matches(_ actual: String?, _ selected: String?) -> Bool {
    selected.map { normalized(actual ?? "") == normalized($0) } ?? true
}

private func normalized(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
}

private func facetValues(_ values: [String]) -> [String] {
    var retained: [String: String] = [:]
    for rawValue in values {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { continue }
        retained[normalized(value), default: value] = retained[normalized(value)] ?? value
    }
    return retained.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}
