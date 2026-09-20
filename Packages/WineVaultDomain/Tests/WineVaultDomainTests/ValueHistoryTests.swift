import XCTest

@testable import WineVaultDomain

final class ValueHistoryTests: XCTestCase {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }

    private func quote(
        bottleID: UUID,
        quoteDate: Date,
        amount: Decimal,
        currency: String = "USD"
    ) throws -> ValuationQuote {
        try ValuationQuote(
            bottleID: bottleID,
            quoteDate: quoteDate,
            amount: amount,
            currency: currency,
            source: "History Fixture",
            retrievedAt: quoteDate,
            query: "history query"
        )
    }

    private func bottle(name: String) throws -> Bottle {
        try Bottle(name: name, quantity: 1, storageLocation: "Rack")
    }

    func testEmptyHistoryWhenNoQuotes() throws {
        let bottles = [try bottle(name: "A")]
        XCTAssertTrue(
            valueHistory(bottles: bottles, quotesByBottle: [:]).isEmpty
        )
    }

    func testSingleQuoteProducesOnePointOnItsDay() throws {
        let bottle = try bottle(name: "A")
        let d1 = day(2026, 9, 1)
        let quotes = try [quote(bottleID: bottle.id, quoteDate: d1, amount: 20)]

        let history = valueHistory(
            bottles: [bottle],
            quotesByBottle: [bottle.id: quotes]
        )

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].date, d1)
        XCTAssertEqual(history[0].total, 20)
        XCTAssertEqual(history[0].valuedBottleCount, 1)
    }

    func testLaterQuoteAccumulatesFromItsDateForward() throws {
        let first = try bottle(name: "First")
        let second = try bottle(name: "Second")
        let d1 = day(2026, 9, 1)
        let d3 = day(2026, 9, 3)

        let history = valueHistory(
            bottles: [first, second],
            quotesByBottle: [
                first.id: [try quote(bottleID: first.id, quoteDate: d1, amount: 10)],
                second.id: [try quote(bottleID: second.id, quoteDate: d3, amount: 15)],
            ]
        )

        // Day 1: only first is valued (10). Day 2: unchanged -> omitted, no
        // fabricated observation. Day 3: both valued (25).
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].date, d1)
        XCTAssertEqual(history[0].total, 10)
        XCTAssertEqual(history[1].date, d3)
        XCTAssertEqual(history[1].total, 25)
        XCTAssertEqual(history[1].valuedBottleCount, 2)
    }

    func testNewerQuoteSupersedesOlderOnItsDay() throws {
        let bottle = try bottle(name: "Refreshed")
        let d1 = day(2026, 9, 1)
        let d5 = day(2026, 9, 5)

        let history = valueHistory(
            bottles: [bottle],
            quotesByBottle: [
                bottle.id: [
                    try quote(bottleID: bottle.id, quoteDate: d1, amount: 30),
                    try quote(bottleID: bottle.id, quoteDate: d5, amount: 24),
                ]
            ]
        )

        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].total, 30)
        // Only the newest quote per bottle counts — 24, not 54.
        XCTAssertEqual(history[1].total, 24)
        XCTAssertEqual(history[1].valuedBottleCount, 1)
    }

    func testForeignCurrencyNewestQuoteExcludesBottleLikeCollectionTotal() throws {
        let bottle = try bottle(name: "Euro priced")
        let d1 = day(2026, 9, 1)
        let d5 = day(2026, 9, 5)

        let quotes = try [
            quote(bottleID: bottle.id, quoteDate: d1, amount: 40),
            quote(bottleID: bottle.id, quoteDate: d5, amount: 30, currency: "EUR"),
        ]
        let history = valueHistory(
            bottles: [bottle],
            quotesByBottle: [bottle.id: quotes]
        )
        let valuation = collectionValuation(
            bottles: [bottle],
            quotesByBottle: [bottle.id: quotes],
            reference: d5
        )

        // Day 1 point: USD quote is newest -> counted (total 40). Day 5:
        // newest quote is EUR -> the bottle drops out of the USD total,
        // matching collectionValuation (total 0, mismatch 1). The change to
        // zero is a real observation and is emitted as a point.
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].total, 40)
        XCTAssertEqual(history[0].valuedBottleCount, 1)
        XCTAssertEqual(history[1].date, d5)
        XCTAssertEqual(history[1].total, 0)
        XCTAssertEqual(history[1].valuedBottleCount, 0)
        XCTAssertEqual(valuation.total, 0)
        XCTAssertEqual(valuation.excludedCurrencyMismatchCount, 1)
    }

    func testSeedBottlesResolveAgainstReferenceAndCoverEveryWindow() throws {
        XCTAssertFalse(uiTestSeedBottles.isEmpty)
        let reference = day(2026, 9, 19)
        var seen: Set<DrinkByState> = []
        for seed in uiTestSeedBottles {
            let bottle = try Bottle(seed: seed, reference: reference)
            XCTAssertEqual(bottle.name, seed.name)
            XCTAssertEqual(bottle.quantity, seed.quantity)
            let state = drinkByState(drinkBy: bottle.drinkBy, reference: reference)
            seen.insert(state)
            if let offset = seed.drinkByInDays {
                XCTAssertNotNil(bottle.drinkBy, "seed \(seed.name) must resolve its offset")
                let days = Calendar.current.dateComponents(
                    [.day],
                    from: reference,
                    to: bottle.drinkBy!
                ).day
                XCTAssertEqual(days, offset)
            } else {
                XCTAssertNil(bottle.drinkBy)
            }
        }
        // The seed set exercises each timeline bucket exactly once.
        XCTAssertEqual(seen, Set(DrinkByState.allCases))
    }
}

final class DrinkByTimelineTests: XCTestCase {
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }

    private func bottle(name: String, drinkBy: Date?) throws -> Bottle {
        try Bottle(name: name, quantity: 1, storageLocation: "Rack", drinkBy: drinkBy)
    }

    func testGroupsOrderedMostUrgentFirstWithEmptyGroupsOmitted() throws {
        let reference = day(2026, 9, 19)
        let bottles = [
            try bottle(name: "Future one", drinkBy: day(2027, 6, 1)),
            try bottle(name: "Windowless", drinkBy: nil),
            try bottle(name: "Passed one", drinkBy: day(2026, 8, 1)),
            try bottle(name: "Soon one", drinkBy: day(2026, 10, 20)),
        ]

        let groups = drinkByTimelineGroups(bottles, reference: reference)

        // No bottles are ready on the reference day -> no .ready section.
        XCTAssertEqual(groups.map(\.state), [.passed, .soon, .future, .noWindow])
        XCTAssertEqual(groups[0].bottles.map(\.name), ["Passed one"])
        XCTAssertEqual(groups[1].bottles.map(\.name), ["Soon one"])
    }

    func testWithinGroupSortIsEarliestDrinkByThenName() throws {
        let reference = day(2026, 9, 19)
        let bottles = [
            try bottle(name: "Zeta", drinkBy: day(2026, 12, 1)),
            try bottle(name: "Alpha", drinkBy: day(2026, 10, 1)),
            try bottle(name: "Beta", drinkBy: day(2026, 12, 1)),
        ]

        let groups = try XCTUnwrap(drinkByTimelineGroups(bottles, reference: reference).first)

        XCTAssertEqual(groups.state, .soon)
        XCTAssertEqual(groups.bottles.map(\.name), ["Alpha", "Beta", "Zeta"])
    }

    func testTitlesAreHumanReadable() {
        XCTAssertEqual(drinkByStateTitle(.passed), "Passed")
        XCTAssertEqual(drinkByStateTitle(.ready), "Ready now")
        XCTAssertEqual(drinkByStateTitle(.soon), "Soon")
        XCTAssertEqual(drinkByStateTitle(.future), "Future")
        XCTAssertEqual(drinkByStateTitle(.noWindow), "No drink-by date")
    }
}

final class DrinkByReminderTests: XCTestCase {
    private var calendar: Calendar { .current }

    private func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return calendar.date(from: components)!
    }

    private func bottle(name: String, drinkBy: Date?) throws -> Bottle {
        try Bottle(name: name, quantity: 1, storageLocation: "Rack", drinkBy: drinkBy)
    }

    func testFutureBottleGetsUpcomingAndDueOnDayAtNineAM() throws {
        let reference = day(2026, 9, 19)
        let bottles = [try bottle(name: "Later", drinkBy: day(2026, 10, 20))]

        let reminders = drinkByReminders(bottles: bottles, reference: reference)

        XCTAssertEqual(reminders.count, 2)
        XCTAssertEqual(reminders.map(\.kind), [.upcoming, .dueOnDay])
        for reminder in reminders {
            let hour = calendar.component(.hour, from: reminder.fireDate)
            XCTAssertEqual(hour, drinkByReminderHour)
        }
        XCTAssertEqual(reminders[0].fireDate, day(2026, 10, 13, hour: 9))
        XCTAssertEqual(reminders[1].fireDate, day(2026, 10, 20, hour: 9))
    }

    func testPastAndSameDayRemindersAreOmitted() throws {
        let reference = day(2026, 9, 19, hour: 18)
        // Due today at 9 AM (already past) and due in the past entirely.
        let bottles = [
            try bottle(name: "Today", drinkBy: day(2026, 9, 19, hour: 6)),
            try bottle(name: "Yesterday", drinkBy: day(2026, 9, 18, hour: 6)),
        ]

        XCTAssertTrue(drinkByReminders(bottles: bottles, reference: reference).isEmpty)
    }

    func testBottlesWithoutWindowGetNothing() throws {
        let bottles = [try bottle(name: "Windowless", drinkBy: nil)]
        XCTAssertTrue(drinkByReminders(bottles: bottles, reference: day(2026, 9, 19)).isEmpty)
    }

    func testSortedByFireDateThenName() throws {
        let reference = day(2026, 9, 19)
        let bottles = [
            try bottle(name: "Zeta", drinkBy: day(2026, 11, 1)),
            try bottle(name: "Alpha", drinkBy: day(2026, 10, 1)),
            try bottle(name: "Beta", drinkBy: day(2026, 10, 1)),
        ]

        let reminders = drinkByReminders(bottles: bottles, reference: reference)

        // Fire-date order: Sep 24 (Alpha, Beta upcoming), Oct 1 (Alpha, Beta
        // due), Oct 25 (Zeta upcoming), Nov 1 (Zeta due).
        XCTAssertEqual(
            reminders.map(\.bottleName),
            ["Alpha", "Beta", "Alpha", "Beta", "Zeta", "Zeta"]
        )
        // Strict-comparator sanity: fire dates never decrease.
        let fireDates = reminders.map(\.fireDate)
        XCTAssertEqual(fireDates, fireDates.sorted())
    }

    func testZeroLeadDaysProducesOnlyDueOnDay() throws {
        let reference = day(2026, 9, 19)
        let bottles = [try bottle(name: "One Shot", drinkBy: day(2026, 12, 1))]

        let reminders = drinkByReminders(
            bottles: bottles, reference: reference, leadDays: 0
        )

        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.kind, .dueOnDay)
    }

    func testCappedRemindersKeepsSoonestByBudget() throws {
        let reference = day(2026, 9, 19)
        let bottles = try (1...10).map { index in
            try bottle(name: "B\(index)", drinkBy: day(2026, 10, 1) + Double(index) * 86_400)
        }
        let all = drinkByReminders(bottles: bottles, reference: reference)
        XCTAssertEqual(all.count, 20)

        let capped = cappedReminders(all, budget: 5)
        XCTAssertEqual(capped.count, 5)
        XCTAssertEqual(capped.map(\.fireDate), all.prefix(5).map(\.fireDate))
        // Budget edge cases: zero yields nothing, negative is treated as zero,
        // an oversized budget keeps everything in order.
        XCTAssertTrue(cappedReminders(all, budget: 0).isEmpty)
        XCTAssertTrue(cappedReminders(all, budget: -1).isEmpty)
        XCTAssertEqual(cappedReminders(all, budget: 100).count, 20)
    }

    func testTimelineSectionIDsAreStableAndUnique() {
        let ids = DrinkByState.allCases.map(drinkByTimelineSectionID)
        XCTAssertEqual(Set(ids).count, DrinkByState.allCases.count)
        XCTAssertEqual(drinkByTimelineSectionID(.ready), "drinkby.section.ready")
    }
}
