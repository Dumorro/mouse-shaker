import AppKit
import CoreGraphics
import IOKit.ps

/// Point-in-time reads of system state. Polled once per engine tick, so there are no observers
/// to keep in sync and nothing can get stuck after a missed notification.
@MainActor
final class SystemMonitors {
    struct Session {
        var locked: Bool
        /// False while fast user switching has moved another user to the console.
        var onConsole: Bool
    }

    struct Battery {
        var onBattery: Bool
        /// Percent, or nil on Macs without an internal battery.
        var level: Int?
    }

    func session() -> Session {
        guard let dict = CGSessionCopyCurrentDictionary() as NSDictionary? as? [String: Any] else {
            return Session(locked: false, onConsole: true)
        }
        return Session(
            locked: dict["CGSSessionScreenIsLocked"] as? Bool ?? false,
            onConsole: dict["kCGSSessionOnConsoleKey"] as? Bool ?? true
        )
    }

    func battery() -> Battery {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            return Battery(onBattery: false, level: nil)
        }
        let providing = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String?
        let onBattery = providing == kIOPSBatteryPowerValue
        let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] ?? []
        for source in sources {
            guard
                let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                let current = desc[kIOPSCurrentCapacityKey] as? Int,
                let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return Battery(onBattery: onBattery, level: current * 100 / max)
        }
        return Battery(onBattery: onBattery, level: nil)
    }

    func appState(bundleID: String) -> (running: Bool, frontmost: Bool) {
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
        return (running, frontmost)
    }

    /// Another app's menu is open (pop-up menu window level) or the screenshot UI is on screen.
    /// Our own menu bar panel is ignored. Reads only layer and owner, which need no Screen
    /// Recording permission.
    func menuOrScreenshotOpen() -> Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else { return false }
        let me = Int(ProcessInfo.processInfo.processIdentifier)
        let menuLayer = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return windows.contains { window in
            if window["kCGWindowOwnerPID"] as? Int == me { return false }
            if window["kCGWindowLayer"] as? Int == menuLayer { return true }
            return window["kCGWindowOwnerName"] as? String == "screencaptureui"
        }
    }

    var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}
