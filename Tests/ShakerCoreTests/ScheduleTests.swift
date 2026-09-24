import Foundation
import Testing
@testable import ShakerCore

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

/// 2026-09-21 is a Monday.
private func date(_ day: Int, _ hour: Int, _ minute: Int, month: Int = 9) -> Date {
    utc.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

@Suite struct ScheduleTests {
    let workday = Schedule(enabled: true, weekdays: [2, 3, 4, 5, 6], from: .init(hour: 8, minute: 0), to: .init(hour: 18, minute: 15))

    @Test func disabledScheduleNeverRestricts() {
        var s = workday
        s.enabled = false
        #expect(s.contains(date(27, 3, 0), calendar: utc)) // Sunday 03:00
    }

    @Test func calendarFixtureIsMonday() {
        #expect(utc.component(.weekday, from: date(21, 12, 0)) == 2)
    }

    @Test(arguments: [21, 22, 23, 24, 25])
    func weekdaysInsideWindow(day: Int) {
        #expect(workday.contains(date(day, 12, 0), calendar: utc))
    }

    @Test(arguments: [26, 27])
    func weekendExcluded(day: Int) {
        #expect(!workday.contains(date(day, 12, 0), calendar: utc))
    }

    @Test func startIsInclusiveEndIsExclusive() {
        #expect(!workday.contains(date(21, 7, 59), calendar: utc))
        #expect(workday.contains(date(21, 8, 0), calendar: utc))
        #expect(workday.contains(date(21, 18, 14), calendar: utc))
        #expect(!workday.contains(date(21, 18, 15), calendar: utc))
    }

    @Test func overnightWindowBelongsToStartDay() {
        // Friday only, 22:00 → 06:00.
        let s = Schedule(enabled: true, weekdays: [6], from: .init(hour: 22, minute: 0), to: .init(hour: 6, minute: 0))
        #expect(s.contains(date(25, 23, 0), calendar: utc))  // Fri 23:00
        #expect(s.contains(date(26, 5, 59), calendar: utc))  // Sat 05:59
        #expect(!s.contains(date(26, 6, 0), calendar: utc))  // Sat 06:00
        #expect(!s.contains(date(25, 5, 0), calendar: utc))  // Fri 05:00 belongs to Thursday's window
        #expect(!s.contains(date(26, 23, 0), calendar: utc)) // Sat 23:00
        #expect(!s.contains(date(25, 12, 0), calendar: utc)) // Fri noon, between windows
    }

    @Test func overnightFromSaturdayWrapsToSunday() {
        let s = Schedule(enabled: true, weekdays: [7], from: .init(hour: 20, minute: 0), to: .init(hour: 2, minute: 0))
        #expect(s.contains(date(27, 1, 0), calendar: utc)) // Sun 01:00, started Saturday
    }

    @Test func equalBoundsMeanWholeDay() {
        let s = Schedule(enabled: true, weekdays: [2], from: .init(hour: 0, minute: 0), to: .init(hour: 0, minute: 0))
        #expect(s.contains(date(21, 0, 0), calendar: utc))
        #expect(s.contains(date(21, 23, 59), calendar: utc))
        #expect(!s.contains(date(22, 12, 0), calendar: utc))
    }

    @Test func startEdgeOnlyOnTransitionIntoWindow() {
        #expect(Schedule.isStartEdge(previous: false, current: true))
        #expect(!Schedule.isStartEdge(previous: nil, current: true))
        #expect(!Schedule.isStartEdge(previous: true, current: true))
        #expect(!Schedule.isStartEdge(previous: true, current: false))
    }

    @Test func timeOfDayDisplayIsZeroPadded() {
        #expect(TimeOfDay(hour: 8, minute: 5).displayString == "08:05")
    }
}
