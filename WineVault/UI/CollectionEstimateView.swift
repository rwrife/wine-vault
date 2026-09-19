import SwiftUI
import WineVaultDomain

/// Drives a collection-wide "Estimate value" run: one queued unvalued bottle
/// at a time, each requiring its own explicit confirm or skip. The run never
/// stores anything on its own and can be stopped at any point.
struct CollectionEstimateView: View {
    @ObservedObject var store: InventoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var runStarted = false

    private var currentBottle: Bottle? {
        store.collectionLookupQueue.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let bottle = currentBottle {
                    content(for: bottle)
                } else if !runStarted {
                    ProgressView("Preparing estimate…")
                        .accessibilityIdentifier("collectionEstimatePreparing")
                } else {
                    ContentUnavailableView {
                        Label("Estimate finished", systemImage: "checkmark.circle")
                    } description: {
                        Text(store.lookupMessage ?? "No bottles left in this estimate run.")
                    } actions: {
                        Button("Done") {
                            store.endCollectionEstimate()
                            dismiss()
                        }
                        .accessibilityIdentifier("collectionEstimateDoneButton")
                    }
                }
            }
            .navigationTitle("Estimating collection")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                guard !runStarted else { return }
                runStarted = true
                await store.startCollectionEstimate()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Stop") {
                        store.cancelLookup()
                        dismiss()
                    }
                    .accessibilityIdentifier("stopCollectionEstimateButton")
                }
            }
        }
    }

    @ViewBuilder
    private func content(for bottle: Bottle) -> some View {
        List {
            Section {
                Text("Bottle \(store.collectionLookupTotal - store.collectionLookupQueue.count + 1) of \(store.collectionLookupTotal): \(bottle.name)")
                    .font(.headline)
                    .accessibilityIdentifier("collectionEstimateProgress")
                Text("Confirm a match or skip. Nothing is saved without your confirmation.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if store.isLookingUpPrice {
                Section {
                    ProgressView("Asking the price service…")
                }
            } else if store.lookupCandidates.isEmpty {
                Section {
                    Text(store.lookupMessage ?? "No matches for this bottle.")
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(store.lookupCandidates.enumerated()), id: \.offset) { index, candidate in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.matchLabel)
                        candidateSummary(candidate)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button("Confirm this match") {
                            Task { await store.confirm(candidate, for: bottle) }
                        }
                        .accessibilityIdentifier("collectionConfirmButton_\(index)")
                    }
                }
            }
            if !store.isLookingUpPrice {
                Section {
                    Button("Skip this bottle") {
                        Task { await store.skipLookup() }
                    }
                    .accessibilityIdentifier("skipBottleButton")
                }
            }
        }
    }
}
