import Carbon.HIToolbox
import ShakerCore

/// System-wide shortcut via Carbon `RegisterEventHotKey`. Unlike an event tap, it needs no permission.
@MainActor
final class HotKeyManager {
    var onPress: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Returns `noErr`, or e.g. `eventHotKeyExistsErr` when another app already owns the combo.
    @discardableResult
    func register(_ combo: KeyCombo?) -> OSStatus {
        unregister()
        guard let combo else { return noErr }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4D53_4B52), id: 1) // "MSKR"
        return RegisterEventHotKey(
            UInt32(combo.keyCode), combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { manager.onPress?() }
                return noErr
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef
        )
    }
}

extension KeyCombo {
    var carbonModifiers: UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }
}

enum KeyLabels {
    static let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
        101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
        106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]

    static let special: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    static func label(keyCode: UInt16, characters: String?) -> String? {
        if let name = functionKeys[keyCode] ?? special[keyCode] { return name }
        guard let characters, !characters.isEmpty else { return nil }
        return characters.uppercased()
    }
}
