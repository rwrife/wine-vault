import SwiftUI
import UIKit
import WineVaultDomain

struct CollectionView: View {
    @ObservedObject var store: InventoryStore
    @State private var selection: UUID?
    @State private var showingAdd = false
    @State private var showingFilters = false
    @State private var editingBottle: Bottle?
    @State private var pendingDeletion: Bottle?
    @State private var showingCollectionEstimate = false

    var body: some View {
        NavigationSplitView {
            browser
        } detail: {
            if let bottle = selectedBottle {
                BottleDetailView(
                    bottle: bottle,
                    store: store,
                    edit: { editingBottle = bottle },
                    delete: { pendingDeletion = bottle }
                )
            } else {
                ContentUnavailableView(
                    "Select a bottle",
                    systemImage: "wineglass",
                    description: Text("Choose a bottle to see its cellar details.")
                )
            }
        }
        .sheet(isPresented: $showingAdd) {
            BottleFormView(store: store, bottle: nil)
        }
        .sheet(item: $editingBottle) { bottle in
            BottleFormView(store: store, bottle: bottle)
        }
        .sheet(isPresented: $showingFilters) {
            BottleFiltersView(store: store)
        }
        .sheet(isPresented: $showingCollectionEstimate) {
            CollectionEstimateView(store: store)
        }
        .alert("Delete \(pendingDeletion?.name ?? "bottle")?", isPresented: deletionPresented) {
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Delete", role: .destructive) {
                guard let bottle = pendingDeletion else { return }
                pendingDeletion = nil
                if selection == bottle.id { selection = nil }
                Task { await store.delete(bottle) }
            }
        } message: {
            Text("This permanently removes the bottle and its saved valuation history.")
        }
        .alert("Something went wrong", isPresented: errorPresented) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "Unknown error")
        }
        .alert("Photo cleanup incomplete", isPresented: cleanupWarningPresented) {
            Button("OK") { store.cleanupWarningMessage = nil }
        } message: {
            Text(store.cleanupWarningMessage ?? "The bottle was deleted.")
        }
    }

    private var browser: some View {
        Group {
            if store.isLoading && store.bottles.isEmpty {
                ProgressView("Loading bottles…")
            } else if store.bottles.isEmpty {
                ContentUnavailableView {
                    Label("Your collection is empty", systemImage: "wineglass")
                } description: {
                    Text("Add a bottle manually. A label photo is always optional.")
                } actions: {
                    Button("Add Bottle") { showingAdd = true }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("emptyAddBottleButton")
                }
            } else if store.filteredBottles.isEmpty {
                ContentUnavailableView {
                    Label("No matching bottles", systemImage: "magnifyingglass")
                } description: {
                    Text("Try another search or clear the active filters.")
                } actions: {
                    Button("Clear Search and Filters") { store.clearFilters() }
                        .accessibilityIdentifier("emptyClearFiltersButton")
                }
            } else {
                List(selection: $selection) {
                    ForEach(store.filteredBottles) { bottle in
                        NavigationLink(value: bottle.id) {
                            BottleRow(bottle: bottle, store: store)
                        }
                        .accessibilityIdentifier("bottleRow_\(bottle.id.uuidString)")
                        .swipeActions {
                            Button("Delete", role: .destructive) { pendingDeletion = bottle }
                        }
                    }
                    Section {
                        valuationFooter
                    }
                }
                .accessibilityIdentifier("bottleList")
            }
        }
        .navigationTitle("Wine Vault")
        .searchable(text: $store.criteria.searchText, prompt: "Name, producer, or region")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Estimate value", systemImage: "tag") {
                    showingCollectionEstimate = true
                    Task { await store.startCollectionEstimate() }
                }
                .accessibilityIdentifier("collectionEstimateButton")
                .disabled(store.bottles.isEmpty)
                Button("Filter", systemImage: filterSystemImage) {
                    showingFilters = true
                }
                .accessibilityIdentifier("filterButton")
                Button("Add Bottle", systemImage: "plus") { showingAdd = true }
                    .accessibilityIdentifier("addBottleButton")
            }
        }
        .refreshable { await store.load() }
    }

    @ViewBuilder
    private var valuationFooter: some View {
        let valuation = store.collectionValuation
        VStack(alignment: .leading, spacing: 4) {
            Text("Estimated collection value: \(valuation.total.formatted(.currency(code: valuation.baseCurrency)))")
                .accessibilityIdentifier("collectionValuationTotal")
            Text(valuation.coverageDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("collectionValuationCoverage")
            if valuation.excludedCurrencyMismatchCount > 0 {
                Text(
                    "\(valuation.excludedCurrencyMismatchCount) valued bottle(s) priced in another "
                        + "currency and excluded from the \(valuation.baseCurrency) total."
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("collectionValuationMismatch")
            }
            if valuation.staleQuoteCount > 0 {
                Text("\(valuation.staleQuoteCount) newest quote(s) are over 90 days old.")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("collectionValuationStale")
            }
            Text("Estimates from dated quotes — not an authoritative valuation.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var selectedBottle: Bottle? {
        store.bottles.first { $0.id == selection }
    }

    private var filterSystemImage: String {
        store.criteria.isFiltering
            ? "line.3.horizontal.decrease.circle.fill"
            : "line.3.horizontal.decrease.circle"
    }

    private var deletionPresented: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }

    private var cleanupWarningPresented: Binding<Bool> {
        Binding(
            get: { store.cleanupWarningMessage != nil },
            set: { if !$0 { store.cleanupWarningMessage = nil } }
        )
    }
}

private struct BottleRow: View {
    let bottle: Bottle
    @ObservedObject var store: InventoryStore

    var body: some View {
        HStack(spacing: 12) {
            BottlePhotoView(reference: bottle.photos.last, store: store)
                .frame(width: 52, height: 68)
                .clipShape(.rect(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(bottle.name).font(.headline)
                if let vintage = bottle.vintage {
                    Text(String(vintage)).foregroundStyle(.secondary)
                }
                Text("Quantity \(bottle.quantity)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var rowAccessibilityLabel: String {
        [bottle.name, bottle.vintage.map(String.init), "Quantity \(bottle.quantity)"]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

struct BottlePhotoView: View {
    let reference: PhotoReference?
    @ObservedObject var store: InventoryStore
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFill()
            } else {
                Image(systemName: "wineglass")
                    .resizable()
                    .scaledToFit()
                    .padding(12)
                    .foregroundStyle(.secondary)
                    .background(.quaternary)
            }
        }
        .accessibilityHidden(true)
        .task(id: reference) {
            image = nil
            guard let reference,
                  let data = try? await store.photoData(for: reference),
                  let uiImage = UIImage(data: data) else { return }
            image = Image(uiImage: uiImage)
        }
    }
}
