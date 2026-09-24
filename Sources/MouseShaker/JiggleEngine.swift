import CoreGraphics
import Foundation
import ShakerCore

/// Gathers the live inputs once per tick, runs the pure `EngineStateMachine`, and performs the
/// resulting action. Commands that change the on/off state go back to `AppModel`, which owns it.
@MainActor
final class JiggleEngine {
    enum Command: Equatable {
        case activate
        case deactivate(Cause)
    }

    enum Cause: Equatable {
        case timer
        case battery(level: Int)
    }

    private let activity = ActivityMonitor()
    private let system = SystemMonitors()
    private let synth = InputSynthesizer()
    private let sleep = SleepAssertion()

    private var lastAction: Date?
    private var lastInSchedule: Bool?
    private var performing = false
    private var clickIndex = 0
    private var lastSyntheticKey: Date?

    func tick(
        now: Date, settings: Settings, enabled: Bool, pending: PendingDeactivation?, hasPermission: Bool
    ) -> (status: EngineStatus, command: Command?) {
        let inSchedule = settings.schedule.contains(now)
        let startEdge = Schedule.isStartEdge(previous: lastInSchedule, current: inSchedule)
        lastInSchedule = inSchedule

        guard enabled else {
            stopRunning()
            if startEdge, settings.schedule.enabled, settings.schedule.autoActivate {
                return (.off, .activate)
            }
            return (.off, nil)
        }

        if let pending, pending.isDue(at: now) {
            stopRunning()
            return (.off, .deactivate(.timer))
        }
        if settings.batteryGuard {
            let battery = system.battery()
            if BatteryGuard.shouldDeactivate(
                enabled: true, threshold: settings.batteryThreshold, onBattery: battery.onBattery, level: battery.level
            ) {
                stopRunning()
                return (.off, .deactivate(.battery(level: battery.level ?? 0)))
            }
        }

        if hasPermission { activity.start() }
        activity.pollKeyboardFallback(lastSyntheticKey: lastSyntheticKey)

        let session = system.session()
        var appConditionMet = true
        if settings.appCondition.kind != .none, let bundleID = settings.appCondition.bundleID {
            let app = system.appState(bundleID: bundleID)
            appConditionMet = settings.appCondition.isMet(appRunning: app.running, appFrontmost: app.frontmost)
        }

        let inputs = EngineInputs(
            now: now,
            enabled: true,
            hasPermission: hasPermission,
            sessionActive: !settings.pauseOnUserSwitch || session.onConsole,
            screenLocked: settings.pauseWhenLocked && session.locked,
            inSchedule: inSchedule,
            appConditionMet: appConditionMet,
            menuOrScreenshotOpen: settings.pauseForMenus && system.menuOrScreenshotOpen(),
            lastUserInput: activity.lastUserInput,
            lastAction: lastAction,
            idleDelay: settings.idleDelay,
            interval: settings.interval,
            continuous: settings.continuous
        )
        let (status, act) = EngineStateMachine.evaluate(inputs)
        sleep.set(settings.preventSleep && status.isRunning)
        if act, perform(settings) {
            lastAction = now
        }
        return (status, nil)
    }

    private func stopRunning() {
        sleep.set(false)
        activity.stop()
        lastAction = nil
    }

    /// Returns false when the action was skipped (one already in flight, or a button is held).
    private func perform(_ settings: Settings) -> Bool {
        guard !performing, !synth.isMouseButtonDown else { return false }
        performing = true
        let reduceMotion = system.reduceMotion
        Task { @MainActor in
            defer { self.performing = false }
            switch settings.mode {
            case .natural:
                await self.playNatural(
                    amplitude: reduceMotion ? 2 : settings.distance,
                    steps: reduceMotion ? 6 : Int.random(in: 12...20)
                )
            case .silent:
                self.synth.nudgeInPlace()
            }
            self.sleep.declareUserActivity()
            if settings.keyPress {
                self.synth.tapKey()
                self.lastSyntheticKey = Date()
            }
            self.synth.scroll(settings.scroll)
            if settings.clickEnabled, !settings.clickPositions.isEmpty {
                let point = settings.clickPositions[self.clickIndex % settings.clickPositions.count]
                self.clickIndex &+= 1
                self.synth.click(at: CGPoint(x: point.x, y: point.y))
            }
            Log.input.info("action performed (mode: \(settings.mode.rawValue, privacy: .public))")
        }
        return true
    }

    /// ~18 ms per step. Stops the moment the user touches anything.
    private func playNatural(amplitude: Double, steps: Int) async {
        let origin = synth.cursorLocation
        var rng = SystemRandomNumberGenerator()
        let path = MotionPath.natural(
            from: origin, amplitude: amplitude, steps: steps,
            bounds: InputSynthesizer.displayBounds(containing: origin), using: &rng
        )
        let inputAtStart = activity.lastUserInput
        for point in path {
            guard activity.lastUserInput == inputAtStart, !synth.isMouseButtonDown else { return }
            synth.move(to: point)
            try? await Task.sleep(nanoseconds: 18_000_000)
        }
    }
}
