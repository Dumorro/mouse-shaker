import Foundation

/// A one-shot request to switch the shaker off. It never restarts it.
public struct PendingDeactivation: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// "Deactivate in 1h": a duration from when it was set.
        case after
        /// "Deactivate at 18:00": a wall-clock time.
        case at
    }

    public var kind: Kind
    public var date: Date

    public init(kind: Kind, date: Date) {
        self.kind = kind
        self.date = date
    }

    public func isDue(at now: Date) -> Bool { now >= date }

    public static func after(_ duration: TimeInterval, from now: Date) -> PendingDeactivation {
        PendingDeactivation(kind: .after, date: now.addingTimeInterval(duration))
    }

    /// Next occurrence of `time` strictly after `now` (today if still ahead, otherwise tomorrow).
    public static func at(_ time: TimeOfDay, after now: Date, calendar: Calendar = .current) -> PendingDeactivation {
        let match = DateComponents(hour: time.hour, minute: time.minute, second: 0)
        let date = calendar.nextDate(after: now, matching: match, matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(24 * 3600)
        return PendingDeactivation(kind: .at, date: date)
    }

    /// 15 min … 12 h.
    public static let presets: [TimeInterval] = [15, 30, 60, 120, 180, 240, 360, 480, 720].map { $0 * 60 }
}

public enum BatteryGuard {
    /// Switch off when running on battery at or below `threshold` percent.
    /// Macs without a battery (`level == nil`) never trigger it.
    public static func shouldDeactivate(enabled: Bool, threshold: Int, onBattery: Bool, level: Int?) -> Bool {
        guard enabled, onBattery, let level else { return false }
        return level <= threshold
    }
}

public enum DurationFormat {
    /// Compact duration: "0s", "45s", "1m 30s", "5m", "2h 5m", "12h".
    public static func short(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return s > 0 ? "\(m)m \(s)s" : "\(m)m" }
        return "\(s)s"
    }
}
