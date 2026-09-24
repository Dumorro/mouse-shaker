import Foundation

public struct TimeOfDay: Codable, Equatable, Hashable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    /// "08:05"
    public var displayString: String { String(format: "%02d:%02d", hour, minute) }
}

/// Weekday numbers follow `Calendar`: 1 = Sunday … 7 = Saturday.
public struct Schedule: Codable, Equatable, Sendable {
    public var enabled = false
    public var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    public var from = TimeOfDay(hour: 8, minute: 0)
    public var to = TimeOfDay(hour: 18, minute: 0)
    /// Switch the shaker on automatically when a scheduled window begins.
    public var autoActivate = true

    public init(
        enabled: Bool = false,
        weekdays: Set<Int> = [2, 3, 4, 5, 6],
        from: TimeOfDay = TimeOfDay(hour: 8, minute: 0),
        to: TimeOfDay = TimeOfDay(hour: 18, minute: 0),
        autoActivate: Bool = true
    ) {
        self.enabled = enabled
        self.weekdays = weekdays
        self.from = from
        self.to = to
        self.autoActivate = autoActivate
    }

    private enum CodingKeys: String, CodingKey { case enabled, weekdays, from, to, autoActivate }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Schedule()
        enabled = (try? c.decodeIfPresent(Bool.self, forKey: .enabled)) ?? d.enabled
        weekdays = (try? c.decodeIfPresent(Set<Int>.self, forKey: .weekdays)) ?? d.weekdays
        from = (try? c.decodeIfPresent(TimeOfDay.self, forKey: .from)) ?? d.from
        to = (try? c.decodeIfPresent(TimeOfDay.self, forKey: .to)) ?? d.to
        autoActivate = (try? c.decodeIfPresent(Bool.self, forKey: .autoActivate)) ?? d.autoActivate
    }

    /// Monday-first display order.
    public static let displayOrder = [2, 3, 4, 5, 6, 7, 1]

    /// Whether `date` falls inside a scheduled window. A disabled schedule never restricts.
    ///
    /// - `from == to` means the whole day.
    /// - `to < from` is an overnight window; it belongs to the weekday on which it started,
    ///   so "Fri 22:00 → 06:00" covers Friday night and Saturday early morning.
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return true }
        let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = c.weekday, let hour = c.hour, let minute = c.minute else { return false }
        let now = hour * 60 + minute
        let start = from.minutesSinceMidnight
        let end = to.minutesSinceMidnight

        if start == end { return weekdays.contains(weekday) }
        if start < end { return weekdays.contains(weekday) && now >= start && now < end }
        if now >= start { return weekdays.contains(weekday) }
        if now < end { return weekdays.contains(Self.previousWeekday(weekday)) }
        return false
    }

    /// True on the tick where the schedule goes from outside to inside a window.
    /// `previous == nil` (first tick after launch) is not an edge: launching mid-window must not
    /// override a user who switched the shaker off.
    public static func isStartEdge(previous: Bool?, current: Bool) -> Bool {
        previous == false && current
    }

    static func previousWeekday(_ weekday: Int) -> Int {
        weekday == 1 ? 7 : weekday - 1
    }
}
