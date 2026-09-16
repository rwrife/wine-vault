import SwiftUI
import WineVaultDomain

struct BottleDetailView: View {
    let bottle: Bottle
    @ObservedObject var store: InventoryStore
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        List {
            if let photo = bottle.photos.first {
                BottlePhotoView(reference: photo, store: store)
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipShape(.rect(cornerRadius: 12))
                    .listRowInsets(EdgeInsets())
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
    }

    @ViewBuilder
    private func detail(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            LabeledContent(label, value: value)
        }
    }
}
