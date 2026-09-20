import Foundation
@testable import WineVault
import UserNotifications
import WineVaultData
import WineVaultDomain
import XCTest

/// Scriptable reminder backend for app-layer tests: records every call and
/// lets the test control what `requestAuthorization` returns, so the
/// opt-in/denial flows are asserted without touching the real notification
/// center.
private actor FakeReminderScheduler: ReminderScheduling {
    var status: UNAuthorizationStatus
    var grantOnRequest = true

    private(set) var authorizationRequests = 0
    private(set) var scheduledBatches: [[DrinkByReminder]] = []
    private(set) var cancelAllCount = 0

    init(status: UNAuthorizationStatus, grantOnRequest: Bool = true) {
        self.status = status
        self.grantOnRequest = grantOnRequest
    }

    var authorizationStatus: UNAuthorizationStatus {
        get async { status }
    }

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        if grantOnRequest { status = .authorized }
        return grantOnRequest
    }

    func schedule(reminders: [DrinkByReminder]) async {
        scheduledBatches.append(reminders)
    }

    func cancelAll() async {
        cancelAllCount += 1
    }
}

/// Issue #5 app-layer behavior: the drink-by reminders opt-in is
/// user-initiated only, denials degrade quietly, and the timeline/dashboard
/// projections match the domain rules the UI renders.
@MainActor
final class DrinkByRemindersStoreTests: XCTestCase {
    private func makeStore(scheduler: (any ReminderScheduling)?) async throws -> InventoryStore {
        let repository = try SQLiteBottleRepository(inMemory: true)
        let store = InventoryStore(
            dependencies: InventoryDependencies(
                repository: repository,
                reminderScheduling: scheduler
            )
        )
        // Explicitly establish the opt-out baseline so persisted state from
        // other tests can never flip the behavior under test.
        await store.setRemindersOptedIn(false)
        await store.load()
        return store
    }

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: InventoryStore.remindersOptInKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: InventoryStore.remindersOptInKey)
        super.tearDown()
    }

    func testNoSchedulerMeansRemindersUnavailableAndSilent() async throws {
        let store = try await makeStore(scheduler: nil)
        XCTAssertFalse(store.isReminderSchedulingAvailable)
        XCTAssertNil(store.remindersAuthorization)
        // Flipping opt-in without a backend must not crash or request anything.
        await store.setRemindersOptedIn(true)
        XCTAssertTrue(store.remindersOptedIn)
        XCTAssertNil(store.remindersAuthorization)
    }

    func testLoadWithoutOptInCancelsAndNeverRequestsPermission() async throws {
        let scheduler = FakeReminderScheduler(status: .notDetermined)
        _ = try await makeStore(scheduler: scheduler)
        let requests = await scheduler.authorizationRequests
        let cancels = await scheduler.cancelAllCount
        let batches = await scheduler.scheduledBatches
        XCTAssertEqual(requests, 0, "permission must never be requested without opt-in")
        XCTAssertGreaterThanOrEqual(cancels, 1, "opt-out state must cancel any pending schedule")
        XCTAssertTrue(batches.isEmpty)
    }

    func testOptInRequestsPermissionOnceAndSchedulesFutureReminders() async throws {
        let scheduler = FakeReminderScheduler(status: .notDetermined)
        let store = try await makeStore(scheduler: scheduler)

        // Add a bottle with a future drink-by date through the store's own path.
        let form = BottleForm(
            name: "Future Reserve",
            quantity: 1,
            storageLocation: "Rack A",
            drinkBy: Calendar.current.date(byAdding: .day, value: 30, to: Date())
        )
        let saved = await store.save(form)
        XCTAssertTrue(saved)

        // The opt-out baseline already requested nothing; flipping on is the
        // single request path.
        await store.setRemindersOptedIn(true)

        let requests = await scheduler.authorizationRequests
        XCTAssertEqual(requests, 1, "the toggle is the only permission request path")
        let batches = await scheduler.scheduledBatches
        XCTAssertEqual(batches.count, 1)
        let reminders = batches.first ?? []
        XCTAssertEqual(reminders.count, 2, "upcoming + due-on-day")
        XCTAssertTrue(reminders.allSatisfy { $0.fireDate > Date() })
        XCTAssertEqual(reminders.map(\.kind), [.upcoming, .dueOnDay])
    }

    func testDeniedPermissionDegradesWithoutScheduling() async throws {
        let scheduler = FakeReminderScheduler(status: .denied, grantOnRequest: false)
        let store = try await makeStore(scheduler: scheduler)
        let form = BottleForm(
            name: "Denied Wine",
            quantity: 1,
            storageLocation: "Rack B",
            drinkBy: Calendar.current.date(byAdding: .day, value: 10, to: Date())
        )
        let saved = await store.save(form)
        XCTAssertTrue(saved)

        await store.setRemindersOptedIn(true)

        let status = await scheduler.authorizationStatus
        XCTAssertEqual(status, .denied)
        XCTAssertFalse(store.remindersAuthorization?.allowsReminders ?? true)
        let batches = await scheduler.scheduledBatches
        XCTAssertTrue(batches.isEmpty, "a denial must schedule nothing")
        // The timeline keeps working regardless of notification state.
        XCTAssertFalse(store.timelineGroups.isEmpty)
    }

    func testOptOutCancelsPendingReminders() async throws {
        let scheduler = FakeReminderScheduler(status: .notDetermined)
        let store = try await makeStore(scheduler: scheduler)
        let form = BottleForm(
            name: "Cancel Me",
            quantity: 1,
            storageLocation: "Rack C",
            drinkBy: Calendar.current.date(byAdding: .day, value: 15, to: Date())
        )
        let saved = await store.save(form)
        XCTAssertTrue(saved)

        await store.setRemindersOptedIn(true)
        await store.setRemindersOptedIn(false)

        let cancels = await scheduler.cancelAllCount
        XCTAssertGreaterThanOrEqual(cancels, 1)
        let batches = await scheduler.scheduledBatches
        XCTAssertEqual(batches.count, 1, "opt-out schedules nothing further")
    }

    func testTimelineAndDashboardProjectionsMatchDomainRules() async throws {
        let store = try await makeStore(scheduler: InertReminderScheduler())
        let calendar = Calendar.current
        let offsets = [-30, 0, 45, 400]
        for (index, offset) in offsets.enumerated() {
            let form = BottleForm(
                name: "W\(index)",
                producer: "Cellar",
                region: index % 2 == 0 ? "North" : "South",
                grape: "Malk",
                quantity: 2,
                storageLocation: "Rack D",
                drinkBy: calendar.date(byAdding: .day, value: offset, to: Date())
            )
            let saved = await store.save(form)
        XCTAssertTrue(saved)
        }
        let noWindow = BottleForm(name: "Free", quantity: 1, storageLocation: "Rack E")
        let savedNoWindow = await store.save(noWindow)
        XCTAssertTrue(savedNoWindow)

        let groupStates = store.timelineGroups.map(\.state)
        XCTAssertEqual(groupStates, [.passed, .ready, .soon, .future, .noWindow])

        let counts = try XCTUnwrap(store.dashboardCounts)
        XCTAssertEqual(counts.distinctBottles, 5)
        XCTAssertEqual(counts.totalQuantity, 9)
        XCTAssertEqual(counts.byRegion["North"], 4)
        XCTAssertEqual(counts.byGrape["Malk"], 8)

        let drinkByCounts = store.drinkByQuantityCounts
        XCTAssertEqual(drinkByCounts[.passed], 2)
        XCTAssertEqual(drinkByCounts[.ready], 2)
        XCTAssertEqual(drinkByCounts[.soon], 2)
        XCTAssertEqual(drinkByCounts[.future], 2)
        XCTAssertEqual(drinkByCounts[.noWindow], 1)
    }

    func testValueHistoryProjectionUsesStoredQuotesOnly() async throws {
        let store = try await makeStore(scheduler: InertReminderScheduler())
        let form = BottleForm(name: "Valued", quantity: 1, storageLocation: "Rack F")
        let saved = await store.save(form)
        XCTAssertTrue(saved)
        let bottle = try XCTUnwrap(store.bottles.first)

        XCTAssertTrue(store.valueHistory.isEmpty, "no quotes means no fabricated points")

        // Offline manual entry is a confirmed quote path through the store.
        let saved = await store.saveManualPrice(
            amount: 30, currency: "USD", for: bottle, matchLabel: "Test entry"
        )
        XCTAssertTrue(saved)
        // saveManualPrice reloads internally, so the point is already visible.
        await store.load()
        XCTAssertEqual(store.valueHistory.count, 1)
        XCTAssertEqual(store.valueHistory.first?.total, 30)
        XCTAssertEqual(store.valueHistory.first?.valuedBottleCount, 1)
    }
}
