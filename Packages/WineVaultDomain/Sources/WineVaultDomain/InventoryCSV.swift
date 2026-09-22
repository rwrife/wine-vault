import Foundation

/// CSV export of the inventory (issue #6): one row per bottle, including the
/// latest user-confirmed quote's amount, currency, quote date, and source.
///
/// Content contract: the export carries only fields the user entered or
/// confirmed. No device identifiers, no location data, no provenance beyond
/// the quote source string the user already sees in the app.

public let inventoryCSVHeader = [
    "name", "producer", "vintage", "region", "grape", "quantity",
    "storage_location", "tags", "drink_by", "notes",
    "latest_quote_amount", "latest_quote_currency", "latest_quote_date",
    "latest_quote_source",
]

/// Renders the full inventory as an RFC 4180 CSV document (CRLF records).
public func inventoryCSV(
    bottles: [Bottle],
    quotesByBottle: [UUID: [ValuationQuote]]
) -> String {
    var lines: [String] = [inventoryCSVHeader.map(csvEscapeField).joined(separator: ",")]
    for bottle in bottles {
        let quote = latestQuote(in: quotesByBottle[bottle.id] ?? [])
        let fields: [String] = [
            bottle.name,
            bottle.producer ?? "",
            bottle.vintage.map(String.init) ?? "",
            bottle.region ?? "",
            bottle.grape ?? "",
            String(bottle.quantity),
            bottle.storageLocation,
            bottle.tags.joined(separator: "|"),
            isoDayString(bottle.drinkBy),
            bottle.notes ?? "",
            quote.map { $0.amount.description } ?? "",
            quote?.currency ?? "",
            quote.map { isoDayString($0.quoteDate) } ?? "",
            quote?.source ?? "",
        ]
        lines.append(fields.map(csvEscapeField).joined(separator: ","))
    }
    return lines.joined(separator: "\r\n") + "\r\n"
}

/// Quotes a field when it contains a comma, quote, or line break, doubling
/// embedded quotes per RFC 4180.
func csvEscapeField(_ field: String) -> String {
    guard field.contains(where: { $0 == "\"" || $0 == "," || $0 == "\n" || $0 == "\r" }) else {
        return field
    }
    return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

/// Deterministic `YYYY-MM-DD` in UTC so exports are stable across locales.
func isoDayString(_ date: Date?) -> String {
    guard let date else { return "" }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    return String(
        format: "%04d-%02d-%02d",
        components.year ?? 0,
        components.month ?? 0,
        components.day ?? 0
    )
}
