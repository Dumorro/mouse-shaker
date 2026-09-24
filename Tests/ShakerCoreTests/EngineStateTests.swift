import Foundation
import Testing
@testable import ShakerCore

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func inputs(
    at offset: TimeInterval,
    enabled: Bool = true,
    lastInput: TimeInterval = 0,
    lastAction: TimeInterval? = nil,
    idle: TimeInterval = 30,
    interval: TimeInterval = 10,
    continuous: Bool = false
) -> EngineInputs {
    EngineInputs(
        now: t0 + offset,
        enabled: enabled,
        lastUserInput: t0 + lastInput,
        lastAction: lastAction.map { t0 + $0 },
        idleDelay: idle,
        interval: interval,
        continuous: continuous
    )
}

@Suite struct EngineStateTests {
    @Test func disabledIsOff() {
        let r = EngineStateMachine.evaluate(inputs(at: 100, enabled: false))
        #expect(r.status == .off)
        #expect(!r.act)
    }

    @Test func waitsForIdleDelay() {
        let r = EngineStateMachine.evaluate(inputs(at: 20))
        #expect(r.status == .waitingForIdle(remaining: 10))
        #expect(!r.act)
    }

    @Test func actsAsSoonAsIdleDelayElapses() {
        let r = EngineStateMachine.evaluate(inputs(at: 30))
        #expect(r.act)
        #expect(r.status == .active(nextActionIn: 10))
    }

    @Test func toleratesTimerJitterAtIdleBoundary() {
        #expect(EngineStateMachine.evaluate(inputs(at: 29.98)).act)
    }

    @Test func repeatsEveryInterval() {
        let early = EngineStateMachine.evaluate(inputs(at: 36, lastAction: 30))
        #expect(!early.act)
        #expect(early.status == .active(nextActionIn: 4))
        #expect(EngineStateMachine.evaluate(inputs(at: 40, lastAction: 30)).act)
    }

    @Test func realInputRestartsIdleDelay() {
        // Acted at 30, user moved at 35: wait until 65.
        let r = EngineStateMachine.evaluate(inputs(at: 50, lastInput: 35, lastAction: 30))
        #expect(r.status == .waitingForIdle(remaining: 15))
        #expect(!r.act)
        // Idle again: acts immediately rather than waiting for the old interval.
        #expect(EngineStateMachine.evaluate(inputs(at: 65, lastInput: 35, lastAction: 30)).act)
    }

    @Test func zeroIdleDelayStillLeavesOneSecondAfterInput() {
        #expect(!EngineStateMachine.evaluate(inputs(at: 0.5, idle: 0)).act)
        #expect(EngineStateMachine.evaluate(inputs(at: 1, idle: 0)).act)
    }

    @Test func continuousActsEverySecond() {
        #expect(EngineStateMachine.evaluate(inputs(at: 41, lastAction: 40, interval: 300, continuous: true)).act)
    }

    @Test func pauseReasonsFollowPriorityOrder() {
        var i = inputs(at: 100)
        i.hasPermission = false
        i.sessionActive = false
        i.screenLocked = true
        i.inSchedule = false
        i.appConditionMet = false
        i.menuOrScreenshotOpen = true

        var seen: [PauseReason] = []
        while let reason = EngineStateMachine.pauseReason(i) {
            seen.append(reason)
            switch reason {
            case .noPermission: i.hasPermission = true
            case .sessionInactive: i.sessionActive = true
            case .screenLocked: i.screenLocked = false
            case .outsideSchedule: i.inSchedule = true
            case .appCondition: i.appConditionMet = true
            case .menuOrScreenshot: i.menuOrScreenshotOpen = false
            }
        }
        #expect(seen == PauseReason.allCases)
        #expect(EngineStateMachine.evaluate(i).act)
    }

    @Test func pausedNeverActs() {
        var i = inputs(at: 100)
        i.screenLocked = true
        let r = EngineStateMachine.evaluate(i)
        #expect(r.status == .paused(.screenLocked))
        #expect(!r.act)
        #expect(!r.status.isRunning)
    }

    @Test func appConditionKinds() {
        let running = AppCondition(kind: .running, bundleID: "com.apple.Safari")
        #expect(running.isMet(appRunning: true, appFrontmost: false))
        #expect(!running.isMet(appRunning: false, appFrontmost: false))

        let front = AppCondition(kind: .frontmost, bundleID: "com.apple.Safari")
        #expect(front.isMet(appRunning: true, appFrontmost: true))
        #expect(!front.isMet(appRunning: true, appFrontmost: false))

        let notFront = AppCondition(kind: .notFrontmost, bundleID: "com.apple.Safari")
        #expect(notFront.isMet(appRunning: true, appFrontmost: false))
        #expect(!notFront.isMet(appRunning: true, appFrontmost: true))

        #expect(AppCondition(kind: .frontmost, bundleID: nil).isMet(appRunning: false, appFrontmost: false))
    }
}
