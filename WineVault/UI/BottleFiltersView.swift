import SwiftUI
import WineVaultDomain

struct BottleFiltersView: View {
    @ObservedObject var store: InventoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                filterPicker("Region", selection: $store.criteria.region, values: store.facets.regions)
                filterPicker("Grape", selection: $store.criteria.grape, values: store.facets.grapes)
                filterPicker("Tag", selection: $store.criteria.tag, values: store.facets.tags)
                Picker("Drink by", selection: $store.criteria.drinkBy) {
                    Text("Any").tag(DrinkByState?.none)
                    ForEach(DrinkByState.allCases, id: \.self) { state in
                        Text(label(for: state)).tag(Optional(state))
                    }
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { store.clearFilters() }
                        .accessibilityIdentifier("clearFiltersButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("filtersDoneButton")
                }
            }
        }
    }

    private func filterPicker(
        _ title: String,
        selection: Binding<String?>,
        values: [String]
    ) -> some View {
        Picker(title, selection: selection) {
            Text("Any").tag(String?.none)
            ForEach(values, id: \.self) { Text($0).tag(Optional($0)) }
        }
    }

    private func label(for state: DrinkByState) -> String {
        switch state {
        case .noWindow: "Not set"
        case .future: "Aging"
        case .soon: "Soon"
        case .ready: "Ready"
        case .passed: "Past"
        }
    }
}
