import AppKit
import Carbon.HIToolbox
import ShakerCore

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: Settings {
        didSet { settingsDidChange(from: oldValue) }
    }
    @Published private(set) var isEnabled: Bool
    @Published private(set) var pending: PendingDeactivation?
    @Published private(set) var status: EngineStatus = .off
    @Published private(set) var hasPermission = Permissions.isTrusted
    /// Why the shaker last switched itself off, shown until it is switched on again.
    @Published private(set) var autoOffNote: String?
    @Published private(set) var hotKeyError: String?

    private let engine = JiggleEngine()
    private let store = SettingsStore()
    private let hotKey = HotKeyManager()
    private var timer: Timer?

    init() {
        settings = store.loadSettings()
        isEnabled = store.loadEnabled()
        pending = store.loadPending()
        hotKey.onPress = { [weak self] in self?.toggle() }
        applyHotKey()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        // .common keeps it firing while a menu is being tracked.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick()
    }

    // MARK: On/off

    func toggle() { setEnabled(!isEnabled) }

    func setEnabled(_ on: Bool) {
        guard on != isEnabled else { return }
        isEnabled = on
        if on {
            autoOffNote = nil
            if pending == nil, let after = settings.deactivateAfter {
                pending = .after(after, from: Date())
            }
            if !Permissions.isTrusted { Permissions.requestOrOpenSettings() }
        } else {
            pending = nil
        }
        store.saveEnabled(on)
        store.savePending(pending)
        Log.engine.info("enabled: \(on, privacy: .public)")
        tick()
    }

    /// "Turn off in …": also switches on, since a countdown for an idle shaker means nothing.
    func deactivate(after duration: TimeInterval) {
        setPending(.after(duration, from: Date()))
    }

    /// "Turn off at …": one-shot, never restarts.
    func deactivate(at time: TimeOfDay) {
        setPending(.at(time, after: Date()))
    }

    func cancelPendingDeactivation() {
        pending = nil
        store.savePending(nil)
    }

    private func setPending(_ newValue: PendingDeactivation) {
        pending = newValue
        store.savePending(newValue)
        setEnabled(true)
    }

    // MARK: Tick

    func tick() {
        let trusted = Permissions.isTrusted
        if trusted != hasPermission { hasPermission = trusted }

        let outcome = engine.tick(
            now: Date(), settings: settings, enabled: isEnabled, pending: pending, hasPermission: trusted
        )
        switch outcome.command {
        case .activate?:
            Log.engine.info("schedule window started")
            setEnabled(true)
            return
        case .deactivate(let cause)?:
            setEnabled(false)
            autoOffNote = switch cause {
            case .timer: String(localized: "Turned off by timer")
            case .battery(let level): String(localized: "Turned off: battery at \("\(level)%")")
            }
            Log.engine.info("auto off: \(String(describing: cause), privacy: .public)")
            return
        case nil:
            break
        }

        if outcome.status.logKind != status.logKind {
            Log.engine.info("status: \(outcome.status.logKind, privacy: .public)")
        }
        if outcome.status != status { status = outcome.status }
    }

    // MARK: Settings

    private func settingsDidChange(from old: Settings) {
        store.save(settings)
        if old.hotKey != settings.hotKey || old.hotKeyEnabled != settings.hotKeyEnabled {
            applyHotKey()
        }
        tick()
    }

    /// While the shortcut recorder is listening, the current shortcut must not fire.
    func suspendHotKey(_ suspended: Bool) {
        if suspended { hotKey.unregister() } else { applyHotKey() }
    }

    private func applyHotKey() {
        let result = hotKey.register(settings.hotKeyEnabled ? settings.hotKey : nil)
        hotKeyError = switch result {
        case noErr: nil
        case OSStatus(eventHotKeyExistsErr): String(localized: "This shortcut is already used by another app.")
        default: String(localized: "Could not register this shortcut (error \(Int(result))).")
        }
    }

    // MARK: Presentation

    var iconState: IconState {
        switch status {
        case .off: .off
        case .paused: .paused
        case .waitingForIdle: .waiting
        case .active: .active
        }
    }

    var menuBarSymbol: String { settings.iconStyle.symbol(for: iconState) }

    var statusText: String {
        if !isEnabled, let autoOffNote { return autoOffNote }
        return status.text
    }
}

extension EngineStatus {
    /// Status without the countdown, so transitions are logged once rather than every second.
    var logKind: String {
        switch self {
        case .off: "off"
        case .paused(let reason): "paused(\(reason.rawValue))"
        case .waitingForIdle: "waitingForIdle"
        case .active: "active"
        }
    }
}
