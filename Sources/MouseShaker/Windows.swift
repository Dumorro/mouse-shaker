import AppKit
import ShakerCore
import SwiftUI

extension NSApplication {
    /// Bring this menu-bar-only app forward so its windows do not open behind others.
    func activateForWindow() {
        if #available(macOS 14, *) {
            activate()
        } else {
            activate(ignoringOtherApps: true)
        }
    }
}

/// Reports the `NSWindow` hosting a SwiftUI view, so the menu bar panel can close itself.
struct HostingWindowReader: NSViewRepresentable {
    let reference: WindowReference

    func makeNSView(context: Context) -> NSView {
        let view = ReportingView()
        view.reference = reference
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ReportingView: NSView {
        var reference: WindowReference?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            reference?.window = window
        }
    }
}

@MainActor
final class WindowReference {
    weak var window: NSWindow?
}

@MainActor
enum MenuBarPanel {
    /// Dismisses the `MenuBarExtra` panel by clicking its own status item button, the same path
    /// as a user click. Closing the panel window directly leaves SwiftUI thinking it is still
    /// open, and the next click on the menu bar icon is swallowed.
    static func dismiss(_ panel: NSWindow?) {
        guard let panel, panel.isVisible else { return }
        let button = NSApp.windows
            .filter { $0.className.contains("StatusBarWindow") }
            .lazy
            .compactMap { $0.contentView.flatMap(statusButton(in:)) }
            .first
        if let button {
            button.performClick(nil)
        } else {
            panel.close()
        }
    }

    private static func statusButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        for subview in view.subviews {
            if let button = statusButton(in: subview) { return button }
        }
        return nil
    }
}

/// A plain AppKit window rather than a SwiftUI `Settings`/`Window` scene: those behave differently
/// across macOS 13/14+ in an app with no Dock icon (auto-opening at launch, opening behind).
@MainActor
enum SettingsWindow {
    private static var window: NSWindow?

    static func show(model: AppModel) {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView().environmentObject(model))
            let window = NSWindow(contentViewController: host)
            window.title = String(localized: "Mouse Shaker Settings")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activateForWindow()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Full-screen overlay on every display: click to add positions, ⌫ removes the last one,
/// Return saves, Esc cancels.
@MainActor
final class ClickPositionPicker {
    static let shared = ClickPositionPicker()

    private(set) var points: [ScreenPoint] = []
    private var windows: [NSWindow] = []
    private var keyMonitor: Any?
    private var completion: (([ScreenPoint]?) -> Void)?

    func begin(existing: [ScreenPoint], completion: @escaping ([ScreenPoint]?) -> Void) {
        guard windows.isEmpty else { return }
        points = existing
        self.completion = completion

        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = NSColor.black.withAlphaComponent(0.3)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = OverlayView(picker: self)
            window.setFrame(screen.frame, display: true)
            windows.append(window)
        }
        NSApp.activateForWindow()
        windows.forEach { $0.orderFrontRegardless() }
        windows.first?.makeKey()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let consumed = MainActor.assumeIsolated { self?.handleKey(keyCode) ?? false }
            return consumed ? nil : event
        }
    }

    fileprivate func add(_ point: ScreenPoint) {
        points.append(point)
        redraw()
    }

    private func handleKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 53: finish(save: false)      // Esc
        case 36, 76: finish(save: true)   // Return, Enter
        case 51, 117:                     // Delete, Forward Delete
            if !points.isEmpty { points.removeLast() }
            redraw()
        default: return false
        }
        return true
    }

    private func redraw() {
        windows.forEach { $0.contentView?.needsDisplay = true }
    }

    private func finish(save: Bool) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        windows.forEach { $0.orderOut(nil) }
        windows = []
        let completion = self.completion
        self.completion = nil
        completion?(save ? points : nil)
    }

    /// Cocoa global space (origin bottom-left of the main display) ↔ CoreGraphics global space
    /// (origin top-left), which is what event posting uses.
    static var mainDisplayHeight: CGFloat { NSScreen.screens.first?.frame.maxY ?? 0 }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class OverlayView: NSView {
    private weak var picker: ClickPositionPicker?

    init(picker: ClickPositionPicker) {
        self.picker = picker
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Uses the event's own location. `NSEvent.mouseLocation` is where the pointer is *now*,
    /// which after a quick click-and-move is no longer where the click happened.
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        // Take keyboard focus on click, so Return/Esc/⌫ reach the picker even if another app
        // was active when the overlay appeared.
        NSApp.activateForWindow()
        window.makeKey()
        let global = window.convertPoint(toScreen: event.locationInWindow)
        picker?.add(ScreenPoint(x: global.x, y: ClickPositionPicker.mainDisplayHeight - global.y))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let picker, let window else { return }

        let hint = String(localized: "Click to add positions · ⌫ removes the last · Return saves · Esc cancels")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = hint.size(withAttributes: attributes)
        let box = NSRect(x: bounds.midX - size.width / 2 - 16, y: bounds.maxY - 120, width: size.width + 32, height: size.height + 16)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10).fill()
        hint.draw(at: NSPoint(x: box.minX + 16, y: box.minY + 8), withAttributes: attributes)

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        for (index, point) in picker.points.enumerated() {
            let cocoa = NSPoint(x: point.x, y: ClickPositionPicker.mainDisplayHeight - point.y)
            let local = NSPoint(x: cocoa.x - window.frame.minX, y: cocoa.y - window.frame.minY)
            guard bounds.contains(local) else { continue }
            let dot = NSRect(x: local.x - 11, y: local.y - 11, width: 22, height: 22)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: dot).fill()
            let label = "\(index + 1)"
            let labelSize = label.size(withAttributes: labelAttributes)
            label.draw(at: NSPoint(x: local.x - labelSize.width / 2, y: local.y - labelSize.height / 2), withAttributes: labelAttributes)
        }
    }
}
