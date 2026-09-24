import Foundation
import ShakerCore

/// Everything lives in the app's UserDefaults domain (`dev.dumorro.mouseshaker`).
@MainActor
struct SettingsStore {
    private let defaults = UserDefaults.standard
    private let settingsKey = "settings.v1"
    private let enabledKey = "enabled"
    private let pendingKey = "pendingDeactivation"

    func loadSettings() -> Settings {
        guard let data = defaults.data(forKey: settingsKey),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    func save(_ settings: Settings) {
        if let data = try? JSONEncoder().encode(settings) { defaults.set(data, forKey: settingsKey) }
    }

    func loadEnabled() -> Bool { defaults.bool(forKey: enabledKey) }

    func saveEnabled(_ enabled: Bool) { defaults.set(enabled, forKey: enabledKey) }

    func loadPending() -> PendingDeactivation? {
        guard let data = defaults.data(forKey: pendingKey) else { return nil }
        return try? JSONDecoder().decode(PendingDeactivation.self, from: data)
    }

    func savePending(_ pending: PendingDeactivation?) {
        if let pending, let data = try? JSONEncoder().encode(pending) {
            defaults.set(data, forKey: pendingKey)
        } else {
            defaults.removeObject(forKey: pendingKey)
        }
    }
}
