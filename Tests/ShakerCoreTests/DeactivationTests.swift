import Foundation
import Testing
@testable import ShakerCore

private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func date(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute, second: second))!
}

@Suite struct DeactivationTests {
    @Test func afterExpiresExactlyAtDuration() {
        let now = date(21, 10, 0)
        let p = PendingDeactivation.after(3600, from: now)
        #expect(p.kind == .after)
        #expect(!p.isDue(at: date(21, 10, 59, 59)))
        #expect(p.isDue(at: date(21, 11, 0)))
    }

    @Test func atLaterTodayStaysToday() {
        let p = PendingDeactivation.at(.init(hour: 18, minute: 0), after: date(21, 10, 0), calendar: utc)
        #expect(p.kind == .at)
        #expect(p.date == date(21, 18, 0))
    }

    @Test func atEarlierTodayRollsToTomorrow() {
        let p = PendingDeactivation.at(.init(hour: 9, minute: 0), after: date(21, 10, 0), calendar: utc)
        #expect(p.date == date(22, 9, 0))
    }

    @Test func atSameMinuteRollsToTomorrow() {
        let p = PendingDeactivation.at(.init(hour: 10, minute: 0), after: date(21, 10, 0), calendar: utc)
        #expect(p.date == date(22, 10, 0))
    }

    @Test func presetsSpanFifteenMinutesToTwelveHours() {
        #expect(PendingDeactivation.presets.first == TimeInterval(15 * 60))
        #expect(PendingDeactivation.presets.last == TimeInterval(12 * 3600))
    }

    @Test func batteryGuard() {
        #expect(BatteryGuard.shouldDeactivate(enabled: true, threshold: 20, onBattery: true, level: 20))
        #expect(!BatteryGuard.shouldDeactivate(enabled: true, threshold: 20, onBattery: true, level: 21))
        #expect(!BatteryGuard.shouldDeactivate(enabled: true, threshold: 20, onBattery: false, level: 5))
        #expect(!BatteryGuard.shouldDeactivate(enabled: false, threshold: 20, onBattery: true, level: 5))
        #expect(!BatteryGuard.shouldDeactivate(enabled: true, threshold: 20, onBattery: true, level: nil))
    }

    @Test(arguments: [
        (0.0, "0s"), (0.2, "1s"), (45, "45s"), (60, "1m"), (90, "1m 30s"),
        (3600, "1h"), (7500, "2h 5m"), (43200, "12h"),
    ])
    func durationFormat(seconds: Double, expected: String) {
        #expect(DurationFormat.short(seconds) == expected)
    }
}
