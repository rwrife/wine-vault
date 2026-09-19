import SwiftUI
import WineVaultDomain

struct BottleDetailView: View {
    let bottle: Bottle
    @ObservedObject var store: InventoryStore
    let edit: () -> Void
    let delete: () -> Void

    @State private var showingEstimate = false
    @State private var showingManualPrice = false
    @State private var manualAmount = ""
    @State private var manualCurrency = "USD"

    var body: some View {
        List {
            if !bottle.photos.isEmpty {
                Section("Label photos") {
                    ForEach(Array(bottle.photos.enumerated()), id: \.offset) { _, photo in
                        BottlePhotoView(reference: photo, store: store)
                            .frame(maxWidth: .infinity)
                            .frame(height: 260)
                            .clipShape(.rect(cornerRadius: 12))
                    }
                }
            }
            Section("Bottle") {
                detail("Name", bottle.name)
                detail("Producer", bottle.producer)
                detail("Vintage", bottle.vintage.map(String.init))
                detail("Region", bottle.region)
                detail("Grape", bottle.grape)
                detail("Quantity", String(bottle.quantity))
                detail("Storage", bottle.storageLocation)
            }
            if !bottle.tags.isEmpty {
                Section("Tags") { Text(bottle.tags.joined(separator: ", ")) }
            }
            Section("Drink by") {
                Text(bottle.drinkBy?.formatted(date: .long, time: .omitted) ?? "Not set")
            }
            valuationSection
            if let notes = bottle.notes {
                Section("Notes") { Text(notes) }
            }
        }
        .navigationTitle(bottle.name)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Edit") { edit() }
                    .accessibilityIdentifier("editBottleButton")
                Button("Delete", role: .destructive) { delete() }
                    .accessibilityIdentifier("deleteBottleButton")
            }
        }
        .sheet(isPresented: $showingEstimate) {
            EstimateMatchView(bottle: bottle, store: store)
        }
        .sheet(isPresented: $showingManualPrice) {
            ManualPriceView(
                bottle: bottle,
                store: store,
                amount: $manualAmount,
                currency: $manualCurrency
            )
        }
    }

    @ViewBuilder
    private var valuationSection: some View {
        Section {
            if let quote = store.latestQuote(for: bottle.id) {
                let freshness = WineVaultDomain.quoteFreshness(quote: quote, reference: Date())
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        "Estimated — quoted \(quote.quoteDate.formatted(date: .abbreviated, time: .omitted)) from \(quote.source)"
                    )
                    .accessibilityIdentifier("valuationQuoteText")
                    Text(freshnessText(freshness, quote: quote))
                        .font(.footnote)
                        .foregroundStyle(freshness == .stale ? .orange : .secondary)
                        .accessibilityIdentifier("valuationQuoteAgeText")
                    Text("Exact query: \(quote.query)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if quote.source != "Manual entry" {
                        Text("Estimates only — not an authoritative price.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("No price on record yet.")
                    .foregroundStyle(.secondary)
            }
            Button("Estimate value") {
                // Presentation only — starting the lookup in the same turn
                // races with the sheet transition and can drop the
                // presentation entirely. EstimateMatchView launches it.
                showingEstimate = true
            }
            .accessibilityIdentifier("estimateValueButton")
            .disabled(store.isLookingUpPrice)
            Button("Enter price manually") {
                showingManualPrice = true
            }
            .accessibilityIdentifier("enterPriceManuallyButton")
        } header: {
            Text("Value")
        }
    }

    private func freshnessText(_ freshness: QuoteFreshness, quote: ValuationQuote) -> String {
        let age = WineVaultDomain.quoteAgeInDays(quote: quote, reference: Date())
        switch freshness {
        case .fresh: return "Quote is \(age) day\(age == 1 ? "" : "s") old."
        case .aging: return "Quote is \(age) days old — consider refreshing it."
        case .stale: return "Quote is \(age) days old and may be out of date."
        }
    }

    @ViewBuilder
    private func detail(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label, value: value)
        }
    }
}

func candidateSummary(_ candidate: PriceCandidate) -> Text {
    let price = candidate.amount.formatted(.currency(code: candidate.currency))
    let day = candidate.quoteDate.formatted(date: .abbreviated, time: .omitted)
    return Text("\(price) — \(candidate.source), quoted \(day)")
}

/// Candidate confirmation sheet. Every stored price requires the user to tap
/// exactly one match (or choose the manual path); nothing auto-applies.
private struct EstimateMatchView: View {
    let bottle: Bottle
    @ObservedObject var store: InventoryStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if store.isLookingUpPrice {
                    ProgressView("Asking the price service…")
                } else if let error = store.lookupMessage, store.lookupCandidates.isEmpty {
                    // Plain VStack instead of ContentUnavailableView: the
                    // actions button must reliably carry its accessibility
                    // identifier for the fallback UI test.
                    VStack(spacing: 12) {
                        Label("No estimate yet", systemImage: "exclamationmark.triangle")
                            .font(.title3)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("estimateErrorMessage")
                        Button("Enter price manually") {
                            store.lookupMessage = nil
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("manualFallbackFromLookupButton")
                    }
                    .padding()
                    // NOTE: no accessibilityIdentifier on this container —
                    // on iOS 26 the container identifier propagates onto the
                    // child elements and shadows the fallback button's own
                    // `manualFallbackFromLookupButton` identifier.
                } else {
                    List {
                        Section {
                            Text("Confirm which match this price is for. Quotes are estimates, never authoritative prices.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(store.lookupCandidates.enumerated()), id: \.offset) { index, candidate in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(candidate.matchLabel)
                                candidateSummary(candidate)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                Button("Confirm this match") {
                                    Task {
                                        if await store.confirm(candidate, for: bottle) {
                                            dismiss()
                                        }
                                    }
                                }
                                .accessibilityIdentifier("confirmMatchButton_\(index)")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Estimate value")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                // Launch the user-initiated lookup once the sheet is on
                // screen, never during the presentation transition.
                await store.requestPriceLookup(for: bottle)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.cancelLookup()
                        dismiss()
                    }
                    .accessibilityIdentifier("cancelEstimateButton")
                }
            }
        }
    }
}

/// Offline price entry — always available, network or not.
private struct ManualPriceView: View {
    let bottle: Bottle
    @ObservedObject var store: InventoryStore
    @Binding var amount: String
    @Binding var currency: String
    @Environment(\.dismiss) private var dismiss
    @State private var invalidAmount = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Price you paid or believe is fair") {
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("manualAmountField")
                    TextField("Currency", text: $currency)
                        .accessibilityIdentifier("manualCurrencyField")
                    if invalidAmount {
                        Text("Error: Enter a valid amount.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityLabel("Error: Enter a valid amount.")
                            .accessibilityIdentifier("manualAmountError")
                    }
                }
                Section {
                    Text("Stored as your own estimate with today's date — never presented as an authoritative price.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Enter price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("cancelManualPriceButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let value = Decimal(
                            string: amount.trimmingCharacters(in: .whitespacesAndNewlines),
                            locale: Locale(identifier: "en_US_POSIX")
                        ) else {
                            invalidAmount = true
                            return
                        }
                        invalidAmount = false
                        Task {
                            if await store.saveManualPrice(
                                amount: value,
                                currency: currency.trimmingCharacters(in: .whitespacesAndNewlines),
                                for: bottle
                            ) {
                                dismiss()
                            }
                        }
                    }
                    .accessibilityIdentifier("saveManualPriceButton")
                }
            }
        }
    }
}
