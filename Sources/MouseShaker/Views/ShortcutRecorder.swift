import AppKit
import ShakerCore
import SwiftUI

struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo
    var onRecordingChange: (Bool) -> Void = { _ in }
    @StateObject private var recorder = Recorder()

    var body: some View {
        Button {
            if recorder.isRecording {
                recorder.stop()
            } else {
                recorder.start { newCombo in
                    if let newCombo { combo = newCombo }
                    onRecordingChange(false)
                }
                onRecordingChange(true)
            }
        } label: {
            Group {
                if recorder.isRecording {
                    Text("Type shortcut…")
                } else {
                    Text(verbatim: combo.displayString)
                }
            }
            .frame(minWidth: 110)
        }
        .onDisappear { recorder.stop() }
    }
}

/// Owns the key monitor. A class, so the monitor closure can hold it weakly.
@MainActor
private final class Recorder: ObservableObject {
    @Published private(set) var isRecording = false
    private var monitor: Any?
    private var completion: ((KeyCombo?) -> Void)?

    func start(completion: @escaping (KeyCombo?) -> Void) {
        stop()
        self.completion = completion
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Only Sendable values cross into the main-actor closure.
            let keyCode = event.keyCode
            let flags = event.modifierFlags.rawValue
            let characters = event.charactersIgnoringModifiers
            let consumed = MainActor.assumeIsolated {
                self?.handle(keyCode: keyCode, flags: NSEvent.ModifierFlags(rawValue: flags), characters: characters) ?? false
            }
            return consumed ? nil : event
        }
    }

    func stop() {
        finish(with: nil)
    }

    private func handle(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) -> Bool {
        if keyCode == 53 { // Esc
            finish(with: nil)
            return true
        }
        var modifiers: KeyCombo.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }

        let isFunctionKey = KeyLabels.functionKeys[keyCode] != nil
        let hasRealModifier = !modifiers.intersection([.command, .option, .control]).isEmpty
        guard isFunctionKey || hasRealModifier,
              let label = KeyLabels.label(keyCode: keyCode, characters: characters)
        else {
            NSSound.beep()
            return true
        }
        finish(with: KeyCombo(keyCode: keyCode, modifiers: modifiers, key: label))
        return true
    }

    private func finish(with combo: KeyCombo?) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        let wasRecording = isRecording
        isRecording = false
        let completion = self.completion
        self.completion = nil
        if wasRecording { completion?(combo) }
    }
}
