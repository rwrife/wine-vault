import SwiftUI
import UserNotifications
import WineVaultDomain

/// Drink-by timeline: bottles grouped by window (Passed / Ready now / Soon /
/// Future / No drink-by date), most urgent first, plus the opt-in for local
/// notifications. The grouped dates are always visible in-app; notifications
/// are an optional layer on top and the screen works identically without
/// them (permission denied, unavailable, or never requested).
///
/// `select` hands a bottle id back to the browser so choosing a row opens the
/// shared detail pane (persistent column at regular width, pushed view at
/// compact width).
struct DrinkByTimelineView: View {
    @ObservedObject var store: InventoryStore
    let select: (UUID) -> Void

    var body: some View {
        List {
            if store.isReminderSchedulingAvailable {
                remindersSection
            }
            if store.bottles.isEmpty {
                ContentUnavailableView(
                    "Nothing to plan yet",
                    systemImage: "calendar",
                    description: Text("Add bottles with a drink-by date and they will appear here.")
                )
            } else {
                ForEach(store.timelineGroups, id: \.state) { group in
                    Section(drinkByStateTitle(group.state)) {
                        ForEach(group.bottles) { bottle in
                            timelineRow(bottle)
                        }
                    }
                }
            }
        }
        .navigationTitle("Drink-by timeline")
        .accessibilityIdentifier("drinkByTimelineList")
    }

    @ViewBuilder
    private var remindersSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { store.remindersOptedIn },
                set: { enabled in
                    Task { await store.setRemindersOptedIn(enabled) }
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drink-by reminders")
                    Text("Wine Vault asks once, on this toggle, and only reminds you about dates you already set. No notifications without your opt-in.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("drinkByRemindersToggle")
            if store.remindersOptedIn,
               let status = store.remindersAuthorization, !status.allowsReminders {
                switch status {
                case .denied:
                    Text("Notifications are turned off for Wine Vault in system settings, so reminders can't fire. The timeline above still shows every date.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .accessibilityIdentifier("drinkByRemindersDegraded")
                default:
                    EmptyView()
                }
            }
        } header: {
            Text("Reminders")
        }
    }

    @ViewBuilder
    private func timelineRow(_ bottle: Bottle) -> some View {
        Button {
            select(bottle.id)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(bottle.name).font(.headline)
                if let drinkBy = bottle.drinkBy {
                    Text(drinkBy.formatted(date: .abbreviated, time: .omitted))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No drink-by date set")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("Quantity \(bottle.quantity)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
        .accessibilityIdentifier("timelineRow_\(bottle.id.uuidString)")
    }
}
