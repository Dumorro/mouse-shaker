import AppKit
import ApplicationServices

/// Accessibility (macOS 13–26; "Device Control and Data Access" on newer releases) is required to
/// post pointer and keyboard events.
@MainActor
enum Permissions {
    private static let promptedKey = "didPromptAccessibility"

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// The system prompt only ever appears once per app, so later requests open System Settings.
    static func requestOrOpenSettings() {
        if UserDefaults.standard.bool(forKey: promptedKey) {
            openSystemSettings()
        } else {
            UserDefaults.standard.set(true, forKey: promptedKey)
            // Literal value of kAXTrustedCheckOptionPrompt (a mutable C global, not usable from Swift 6).
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
    }

    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
