import Carbon.HIToolbox
import CoreGraphics
import ShakerCore

/// Every event we post carries this value in `eventSourceUserData`, so `ActivityMonitor` can
/// tell our own events from real input. The system idle counters cannot: they are reset by both.
enum SyntheticEvent {
    static let tag: Int64 = 0x5348_414B // "SHAK"

    static func isSynthetic(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.eventSourceUserData) == tag
    }
}

@MainActor
final class InputSynthesizer {
    private let source: CGEventSource? = {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = SyntheticEvent.tag
        return source
    }()

    /// Global display coordinates, origin at the top-left of the main display (same space as posting).
    var cursorLocation: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    /// True while a physical mouse button is held: a drag, a selection, or menu tracking.
    var isMouseButtonDown: Bool {
        [CGMouseButton.left, .right, .center].contains { CGEventSource.buttonState(.hidSystemState, button: $0) }
    }

    func move(to point: CGPoint) {
        post(CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left))
    }

    /// Silent mode: a pointer event at the current position. No visible motion, but the HID idle
    /// timer is reset like any other input.
    func nudgeInPlace() {
        move(to: cursorLocation)
    }

    /// F18 has no default binding in macOS, so pressing it does nothing visible.
    func tapKey(_ keyCode: CGKeyCode = CGKeyCode(kVK_F18)) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down)
            event?.flags = []
            post(event)
        }
    }

    /// One pixel there and back, so the content under the pointer ends where it started.
    func scroll(_ direction: ScrollDirection) {
        guard direction != .off else { return }
        let dy: Int32 = direction == .vertical || direction == .both ? 1 : 0
        let dx: Int32 = direction == .horizontal || direction == .both ? 1 : 0
        for sign: Int32 in [1, -1] {
            post(CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: dy * sign, wheel2: dx * sign, wheel3: 0))
        }
    }

    /// Left click at `point`, then put the pointer back where it was.
    func click(at point: CGPoint) {
        let back = cursorLocation
        move(to: point)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left)
            event?.setIntegerValueField(.mouseEventClickState, value: 1)
            post(event)
        }
        move(to: back)
    }

    static func displayBounds(containing point: CGPoint) -> CGRect {
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        if CGGetDisplaysWithPoint(point, 1, &display, &count) == .success, count > 0 {
            return CGDisplayBounds(display)
        }
        return CGDisplayBounds(CGMainDisplayID())
    }

    private func post(_ event: CGEvent?) {
        guard let event else { return }
        event.setIntegerValueField(.eventSourceUserData, value: SyntheticEvent.tag)
        event.post(tap: .cghidEventTap)
    }
}
