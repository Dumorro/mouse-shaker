import Foundation

/// Why an enabled shaker is not acting. Declared in priority order: when several apply, the
/// first one is reported.
public enum PauseReason: String, CaseIterable, Sendable {
    case noPermission
    case sessionInactive
    case screenLocked
    case outsideSchedule
    case appCondition
    case menuOrScreenshot
}

public enum EngineStatus: Equatable, Sendable {
    case off
    case paused(PauseReason)
    case waitingForIdle(remaining: TimeInterval)
    case active(nextActionIn: TimeInterval)

    /// Enabled and not blocked by any condition.
    public var isRunning: Bool {
        switch self {
        case .waitingForIdle, .active: return true
        case .off, .paused: return false
        }
    }
}

public struct EngineInputs: Sendable {
    public var now: Date
    public var enabled: Bool
    public var hasPermission: Bool
    public var sessionActive: Bool
    public var screenLocked: Bool
    public var inSchedule: Bool
    public var appConditionMet: Bool
    public var menuOrScreenshotOpen: Bool
    /// Last real (non-synthetic) keyboard, mouse, scroll or gesture input.
    public var lastUserInput: Date
    public var lastAction: Date?
    public var idleDelay: TimeInterval
    public var interval: TimeInterval
    public var continuous: Bool

    public init(
        now: Date,
        enabled: Bool,
        hasPermission: Bool = true,
        sessionActive: Bool = true,
        screenLocked: Bool = false,
        inSchedule: Bool = true,
        appConditionMet: Bool = true,
        menuOrScreenshotOpen: Bool = false,
        lastUserInput: Date,
        lastAction: Date? = nil,
        idleDelay: TimeInterval,
        interval: TimeInterval,
        continuous: Bool = false
    ) {
        self.now = now
        self.enabled = enabled
        self.hasPermission = hasPermission
        self.sessionActive = sessionActive
        self.screenLocked = screenLocked
        self.inSchedule = inSchedule
        self.appConditionMet = appConditionMet
        self.menuOrScreenshotOpen = menuOrScreenshotOpen
        self.lastUserInput = lastUserInput
        self.lastAction = lastAction
        self.idleDelay = idleDelay
        self.interval = interval
        self.continuous = continuous
    }
}

public enum EngineStateMachine {
    /// Even with "no idle delay", never act within a second of real input, so the shaker never
    /// fights a user who is actively moving the pointer.
    public static let minimumIdle: TimeInterval = 1
    public static let continuousInterval: TimeInterval = 1
    /// Absorbs timer jitter so a 30 s interval does not slip to 31 s.
    static let tolerance: TimeInterval = 0.05

    public static func pauseReason(_ i: EngineInputs) -> PauseReason? {
        if !i.hasPermission { return .noPermission }
        if !i.sessionActive { return .sessionInactive }
        if i.screenLocked { return .screenLocked }
        if !i.inSchedule { return .outsideSchedule }
        if !i.appConditionMet { return .appCondition }
        if i.menuOrScreenshotOpen { return .menuOrScreenshot }
        return nil
    }

    /// Returns the status to display and whether to perform an action on this tick.
    ///
    /// Once the idle delay has elapsed, the first action happens immediately and then repeats
    /// every `interval`. Any real input restarts the idle delay.
    public static func evaluate(_ i: EngineInputs) -> (status: EngineStatus, act: Bool) {
        guard i.enabled else { return (.off, false) }
        if let reason = pauseReason(i) { return (.paused(reason), false) }

        let idleDelay = max(i.idleDelay, minimumIdle)
        let idle = i.now.timeIntervalSince(i.lastUserInput)
        if idle + tolerance < idleDelay {
            return (.waitingForIdle(remaining: idleDelay - idle), false)
        }

        let interval = i.continuous ? continuousInterval : max(i.interval, 1)
        guard let last = i.lastAction, last >= i.lastUserInput else {
            return (.active(nextActionIn: interval), true)
        }
        let since = i.now.timeIntervalSince(last)
        if since + tolerance >= interval {
            return (.active(nextActionIn: interval), true)
        }
        return (.active(nextActionIn: interval - since), false)
    }
}
