import CoreGraphics
import Foundation

/// Tracks the time of the last *real* user input. Listen-only event tap, so it never delays or
/// alters events, and it records only a timestamp, never key codes or text.
@MainActor
final class ActivityMonitor {
    private(set) var lastUserInput = Date()
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// False when the tap could only be created for pointer events (no keyboard access).
    private var seesKeyboard = false

    var isRunning: Bool { tap != nil }

    private static func mask(_ types: [CGEventType]) -> CGEventMask {
        types.reduce(0) { $0 | (1 << CGEventMask($1.rawValue)) }
    }

    private static let pointerMask: CGEventMask = {
        let types: [CGEventType] = [
            .mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel, .tabletPointer, .tabletProximity,
        ]
        // Trackpad gestures (NSEvent types with no CGEventType case): rotate, begin/end gesture,
        // gesture, magnify, swipe, smart magnify, pressure.
        let gestures: [CGEventMask] = [18, 19, 20, 29, 30, 31, 32, 34]
        return gestures.reduce(mask(types)) { $0 | (1 << $1) }
    }()

    private static let keyboardMask = mask([.keyDown, .keyUp, .flagsChanged])

    /// Starting counts as activity: the idle delay runs from the moment the shaker is switched on.
    func start() {
        guard tap == nil else { return }
        lastUserInput = Date()
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        var created = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: Self.pointerMask | Self.keyboardMask, callback: activityTapCallback, userInfo: refcon
        )
        seesKeyboard = created != nil
        if created == nil {
            Log.input.error("keyboard event tap refused; falling back to pointer tap + keyboard polling")
            created = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                eventsOfInterest: Self.pointerMask, callback: activityTapCallback, userInfo: refcon
            )
        }
        guard let created else {
            Log.input.error("event tap could not be created")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
        tap = created
        runLoopSource = source
        Log.input.info("activity monitor started (keyboard via tap: \(self.seesKeyboard, privacy: .public))")
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
        Log.input.info("activity monitor stopped")
    }

    /// Without a keyboard tap, read the HID "last key down" counter. Our own F18 taps also reset
    /// it, so a key-down within half a second of our last synthetic key is ignored.
    func pollKeyboardFallback(lastSyntheticKey: Date?) {
        guard isRunning, !seesKeyboard else { return }
        let seconds = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
        let keyDown = Date().addingTimeInterval(-seconds)
        if let lastSyntheticKey, abs(keyDown.timeIntervalSince(lastSyntheticKey)) < 0.5 { return }
        if keyDown > lastUserInput { lastUserInput = keyDown }
    }

    fileprivate func handle(type: CGEventType, synthetic: Bool) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        default:
            if !synthetic { lastUserInput = Date() }
        }
    }
}

/// The run loop source is on the main run loop, so the callback always runs on the main thread.
private func activityTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        let monitor = Unmanaged<ActivityMonitor>.fromOpaque(refcon).takeUnretainedValue()
        let synthetic = SyntheticEvent.isSynthetic(event)
        MainActor.assumeIsolated { monitor.handle(type: type, synthetic: synthetic) }
    }
    return Unmanaged.passUnretained(event)
}
