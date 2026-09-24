import IOKit.pwr_mgt

/// "Prevent sleep while active". Visible in `pmset -g assertions` as "Mouse Shaker is active".
@MainActor
final class SleepAssertion {
    private var assertionID: IOPMAssertionID = 0
    private var held = false
    private var userActivityID: IOPMAssertionID = 0

    func set(_ on: Bool) {
        guard on != held else { return }
        if on {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                "Mouse Shaker is active" as CFString,
                &assertionID
            )
            held = result == kIOReturnSuccess
            if !held { Log.system.error("sleep assertion failed: \(result, privacy: .public)") }
        } else {
            IOPMAssertionRelease(assertionID)
            held = false
        }
        Log.system.info("prevent sleep: \(self.held, privacy: .public)")
    }

    /// Tells power management the user is present, which restarts the display-dim timer.
    /// Reusing the same ID refreshes one assertion instead of piling up new ones.
    func declareUserActivity() {
        IOPMAssertionDeclareUserActivity("Mouse Shaker" as CFString, kIOPMUserActiveLocal, &userActivityID)
    }
}
