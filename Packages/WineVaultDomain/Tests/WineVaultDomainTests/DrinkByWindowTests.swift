import XCTest

@testable import WineVaultDomain

final class DrinkByWindowTests: XCTestCase {
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)!
    }

    func testNoWindowWhenDrinkByMissing() {
        XCTAssertEqual(
            drinkByState(drinkBy: nil, reference: date(2026, 9, 13)),
            .noWindow
        )
    }

    func testFutureBeyondSoonWindow() {
        XCTAssertEqual(
            drinkByState(drinkBy: date(2027, 6, 1), reference: date(2026, 9, 13)),
            .future
        )
    }

    func testSoonWithinWindowBoundary() {
        // Exactly soonWindowDays ahead -> .soon (inclusive boundary)
        let ref = date(2026, 9, 13)
        let drinkBy = Calendar.current.date(byAdding: .day, value: 90, to: ref)!
        XCTAssertEqual(drinkByState(drinkBy: drinkBy, reference: ref), .soon)
    }

    func testReadyOnDrinkByDay() {
        let day = date(2026, 9, 13)
        XCTAssertEqual(drinkByState(drinkBy: day, reference: day), .ready)
    }

    func testPassedDayAfter() {
        let ref = date(2026, 9, 13)
        let drinkBy = Calendar.current.date(byAdding: .day, value: -1, to: ref)!
        XCTAssertEqual(drinkByState(drinkBy: drinkBy, reference: ref), .passed)
    }

    func testTimeOfDayIgnored() {
        // A drink-by later in the day than the reference is still `.ready`,
        // because comparison is calendar-day aligned.
        let ref = Calendar.current.date(
            bySettingHour: 22, minute: 30, second: 0, of: date(2026, 9, 13)
        )!
        let drinkBy = Calendar.current.date(
            bySettingHour: 6, minute: 0, second: 0, of: date(2026, 9, 13)
        )!
        XCTAssertEqual(drinkByState(drinkBy: drinkBy, reference: ref), .ready)
    }
}
