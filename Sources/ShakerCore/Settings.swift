import Foundation

public enum MovementMode: String, Codable, CaseIterable, Sendable {
    /// Visible, short curved cursor path that returns to where it started.
    case natural
    /// Zero-distance pointer event: resets the system idle timer without visible motion.
    case silent
}

public enum ScrollDirection: String, Codable, CaseIterable, Sendable {
    case off, vertical, horizontal, both
}

public enum IconStyle: String, Codable, CaseIterable, Sendable {
    case cursor, mouse, cup, bolt, eye
}

public struct ScreenPoint: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct KeyCombo: Codable, Equatable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }

    /// Virtual key code (kVK_*).
    public var keyCode: UInt16
    public var modifiers: Modifiers
    /// Label shown for the key itself, e.g. "J" or "F5".
    public var key: String

    public init(keyCode: UInt16, modifiers: Modifiers, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// ⌃⌘J
    public static let `default` = KeyCombo(keyCode: 38, modifiers: [.control, .command], key: "J")

    /// Rendered in Apple's canonical modifier order: ⌃⌥⇧⌘.
    public var displayString: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + key
    }
}

public enum AppConditionKind: String, Codable, CaseIterable, Sendable {
    case none
    /// Only while the chosen app is running.
    case running
    /// Only while the chosen app is the frontmost app.
    case frontmost
    /// Only while the chosen app is NOT the frontmost app.
    case notFrontmost
}

public struct AppCondition: Codable, Equatable, Sendable {
    public var kind: AppConditionKind = .none
    public var bundleID: String?
    public var appName: String?

    public init(kind: AppConditionKind = .none, bundleID: String? = nil, appName: String? = nil) {
        self.kind = kind
        self.bundleID = bundleID
        self.appName = appName
    }

    /// A condition without a chosen app never blocks.
    public func isMet(appRunning: Bool, appFrontmost: Bool) -> Bool {
        guard bundleID != nil else { return true }
        switch kind {
        case .none: return true
        case .running: return appRunning
        case .frontmost: return appFrontmost
        case .notFrontmost: return !appFrontmost
        }
    }
}

public struct Settings: Codable, Equatable, Sendable {
    // Movement
    public var mode: MovementMode = .natural
    public var idleDelay: TimeInterval = 30
    public var interval: TimeInterval = 30
    public var continuous = false
    /// Maximum Natural-mode excursion, in points.
    public var distance: Double = 8
    public var keyPress = false
    public var scroll: ScrollDirection = .off
    public var clickEnabled = false
    public var clickPositions: [ScreenPoint] = []

    // Timing
    public var schedule = Schedule()
    /// "Always deactivate after": applied every time the shaker is switched on. nil = never.
    public var deactivateAfter: TimeInterval?

    // Conditions
    public var appCondition = AppCondition()
    public var pauseWhenLocked = true
    public var pauseOnUserSwitch = true
    public var pauseForMenus = true
    public var batteryGuard = false
    public var batteryThreshold = 20

    // System
    public var preventSleep = true
    public var hotKeyEnabled = true
    public var hotKey = KeyCombo.default
    public var iconStyle: IconStyle = .cursor

    public init() {}

    public static let idleDelayOptions: [TimeInterval] = [0, 5, 10, 15, 30, 60, 120, 180, 300, 600, 900, 1800]
    public static let intervalOptions: [TimeInterval] = [5, 10, 15, 30, 60, 120, 180, 240, 300, 600, 900]
    public static let distanceRange: ClosedRange<Double> = 2...30
    public static let batteryThresholdRange: ClosedRange<Int> = 5...50

    private enum CodingKeys: String, CodingKey {
        case mode, idleDelay, interval, continuous, distance, keyPress, scroll, clickEnabled, clickPositions
        case schedule, deactivateAfter
        case appCondition, pauseWhenLocked, pauseOnUserSwitch, pauseForMenus, batteryGuard, batteryThreshold
        case preventSleep, hotKeyEnabled, hotKey, iconStyle
    }

    /// Tolerant decoding: any missing or unreadable key falls back to its default, so adding a
    /// setting in a later version never wipes the user's stored preferences.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Settings()
        func v<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        mode = v(.mode, d.mode)
        idleDelay = v(.idleDelay, d.idleDelay)
        interval = v(.interval, d.interval)
        continuous = v(.continuous, d.continuous)
        distance = v(.distance, d.distance)
        keyPress = v(.keyPress, d.keyPress)
        scroll = v(.scroll, d.scroll)
        clickEnabled = v(.clickEnabled, d.clickEnabled)
        clickPositions = v(.clickPositions, d.clickPositions)
        schedule = v(.schedule, d.schedule)
        deactivateAfter = try? c.decodeIfPresent(TimeInterval.self, forKey: .deactivateAfter)
        appCondition = v(.appCondition, d.appCondition)
        pauseWhenLocked = v(.pauseWhenLocked, d.pauseWhenLocked)
        pauseOnUserSwitch = v(.pauseOnUserSwitch, d.pauseOnUserSwitch)
        pauseForMenus = v(.pauseForMenus, d.pauseForMenus)
        batteryGuard = v(.batteryGuard, d.batteryGuard)
        batteryThreshold = v(.batteryThreshold, d.batteryThreshold)
        preventSleep = v(.preventSleep, d.preventSleep)
        hotKeyEnabled = v(.hotKeyEnabled, d.hotKeyEnabled)
        hotKey = v(.hotKey, d.hotKey)
        iconStyle = v(.iconStyle, d.iconStyle)
    }
}
