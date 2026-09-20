import SwiftUI
import Charts
import WineVaultDomain

/// Collection dashboard: totals, grouping by region and grape, and estimated
/// value over time derived from the user's own confirmed quotes only.
///
/// Accessibility: every chart has a data-table fallback that VoiceOver reads
/// row by row; the charts remain decorative-friendly because the same data
/// is presented as text.
struct DashboardView: View {
    @ObservedObject var store: InventoryStore

    var body: some View {
        List {
            summarySection
            drinkBySection
            groupSection(
                title: "Bottles by region",
                placeholder: "Nothing grouped yet — add bottles with a region.",
                counts: store.dashboardCounts?.byRegion ?? [:]
            )
            groupSection(
                title: "Bottles by grape",
                placeholder: "Nothing grouped yet — add bottles with a grape.",
                counts: store.dashboardCounts?.byGrape ?? [:]
            )
            valueSection
        }
        .navigationTitle("Dashboard")
        .accessibilityIdentifier("dashboardList")
    }

    @ViewBuilder
    private var summarySection: some View {
        Section("Collection") {
            if let counts = store.dashboardCounts {
                LabeledContent("Distinct bottles", value: String(counts.distinctBottles))
                LabeledContent("Total quantity", value: String(counts.totalQuantity))
            } else {
                Text("No bottles yet.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var drinkBySection: some View {
        Section("Drink-by windows") {
            if store.bottles.isEmpty {
                Text("Nothing to summarize yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(DrinkByState.allCases, id: \.self) { state in
                    let count = store.drinkByQuantityCounts[state] ?? 0
                    if count > 0 {
                        LabeledContent(drinkByStateTitle(state), value: "\(count) bottle\(count == 1 ? "" : "s")")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func groupSection(title: String, placeholder: String, counts: [String: Int]) -> some View {
        Section(title) {
            if counts.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.secondary)
            } else {
                // Sort by quantity descending, then name, so rows are stable.
                ForEach(
                    counts.sorted { $0.value > $1.value || ($0.value == $1.value && $0.key < $1.key) },
                    id: \.key
                ) { group in
                    LabeledContent(
                        group.key,
                        value: "\(group.value) bottle\(group.value == 1 ? "" : "s")"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var valueSection: some View {
        let history = store.valueHistory
        Section("Estimated value over time") {
            if history.isEmpty {
                Text("No confirmed quotes yet. Estimate value or enter prices manually and points appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                valueChart(history)
                valueTable(history)
                Text("Points come only from quotes you confirmed or entered — never live or implied prices.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func valueChart(_ history: [ValueHistoryPoint]) -> some View {
        Chart(history) { point in
            LineMark(
                x: .value("Date", point.date),
                y: .value("Estimated total", point.total as NSDecimalNumber)
            )
            PointMark(
                x: .value("Date", point.date),
                y: .value("Estimated total", point.total as NSDecimalNumber)
            )
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: 180)
        .accessibilityHidden(true) // data-table fallback below carries the info
        .accessibilityIdentifier("dashboardValueChart")
    }

    private func valueTable(_ history: [ValueHistoryPoint]) -> some View {
        // Data-table fallback so the chart is readable in accessibility mode.
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(history.enumerated()), id: \.offset) { _, point in
                LabeledContent(
                    point.date.formatted(date: .abbreviated, time: .omitted),
                    value: "\(point.total.formatted(.currency(code: store.valuationCurrency))) (\(point.valuedBottleCount) valued)"
                )
                .font(.footnote)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Value history data table")
        .accessibilityIdentifier("dashboardValueTable")
    }
}
