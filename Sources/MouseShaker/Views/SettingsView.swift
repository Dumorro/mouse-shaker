import AppKit
import ShakerCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            MovementSettings().tabItem { Label("Movement", systemImage: "cursorarrow.motionlines") }
            ScheduleSettings().tabItem { Label("Schedule", systemImage: "calendar") }
            ConditionsSettings().tabItem { Label("Conditions", systemImage: "switch.2") }
            ShortcutSettings().tabItem { Label("Shortcut", systemImage: "keyboard") }
        }
        .frame(width: 540, height: 500)
    }
}

private struct Caption: View {
    let text: LocalizedStringKey
    init(_ text: LocalizedStringKey) { self.text = text }

    var body: some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @EnvironmentObject private var model: AppModel
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section {
                // A closure, not the bare method reference: Swift 6.3 crashes in IRGen on the
                // @isolated(any) thunk for `set: setLaunchAtLogin`.
                Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: { setLaunchAtLogin($0) }))
                if let launchError {
                    Text(verbatim: launchError).font(.caption).foregroundStyle(.red)
                } else if LaunchAtLogin.needsApproval {
                    Caption("Approve Mouse Shaker in System Settings › General › Login Items.")
                }
                Toggle("Prevent sleep while active", isOn: $model.settings.preventSleep)
                Caption("Keeps the display and system awake while Mouse Shaker is on and not paused.")
                Picker("Always turn off after", selection: $model.settings.deactivateAfter) {
                    Text("Never").tag(TimeInterval?.none)
                    ForEach(PendingDeactivation.presets, id: \.self) { duration in
                        Text(verbatim: DurationFormat.short(duration)).tag(TimeInterval?.some(duration))
                    }
                }
            }

            Section("Menu bar icon") {
                Picker("Style", selection: $model.settings.iconStyle) {
                    ForEach(IconStyle.allCases, id: \.self) { style in
                        Image(systemName: style.symbol(for: .active))
                            .accessibilityLabel(Text(style.title))
                            .tag(style)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Permissions") {
                LabeledContent {
                    if model.hasPermission {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant Access…") { Permissions.requestOrOpenSettings() }
                    }
                } label: {
                    Text("Accessibility")
                    Text("Needed to move the pointer and send input events.")
                }
                Caption("If access shows as granted but nothing moves, remove Mouse Shaker from the list and add it again.")
                Button("Open Privacy & Security…") { Permissions.openSystemSettings() }
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            try LaunchAtLogin.set(on)
            launchError = nil
        } catch {
            launchError = error.localizedDescription
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}

// MARK: - Movement

private struct MovementSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Mode") {
                Picker("Mode", selection: $model.settings.mode) {
                    ForEach(MovementMode.allCases, id: \.self) { mode in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.title)
                            Text(mode.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        .tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Section("Timing") {
                DurationPicker(title: "Idle delay", selection: $model.settings.idleDelay, options: Settings.idleDelayOptions)
                Caption("How long to wait after your last input before starting.")
                DurationPicker(title: "Move every", selection: $model.settings.interval, options: Settings.intervalOptions)
                    .disabled(model.settings.continuous)
                Toggle("Continuous movement", isOn: $model.settings.continuous)
                Caption("Acts every second, with no pause between movements.")
            }

            Section("Natural motion") {
                LabeledContent("Distance") {
                    HStack {
                        Slider(value: $model.settings.distance, in: Settings.distanceRange, step: 1)
                            .frame(width: 180)
                        Text(verbatim: "\(Int(model.settings.distance)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    Caption("Reduce Motion is on, so movement is limited to 2 pt.")
                }
            }
            .disabled(model.settings.mode != .natural)

            Section("Extra activity") {
                Toggle("Press a silent key (F18)", isOn: $model.settings.keyPress)
                Picker("Scroll", selection: $model.settings.scroll) {
                    ForEach(ScrollDirection.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Caption("Scrolls one pixel and back, in the window under the pointer.")
            }

            Section("Clicks") {
                Toggle("Click at chosen positions", isOn: $model.settings.clickEnabled)
                LabeledContent {
                    HStack {
                        Button("Choose…") {
                            ClickPositionPicker.shared.begin(existing: model.settings.clickPositions) { points in
                                if let points { model.settings.clickPositions = points }
                            }
                        }
                        Button("Clear") { model.settings.clickPositions = [] }
                            .disabled(model.settings.clickPositions.isEmpty)
                    }
                } label: {
                    Text("Positions: \(model.settings.clickPositions.count)")
                }
                Caption("Clicks are real: they press whatever is under each position. Each action clicks the next position in turn.")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Schedule

private struct ScheduleSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Only run on a schedule", isOn: $model.settings.schedule.enabled)
                Caption("Outside the scheduled hours Mouse Shaker stays paused, even when switched on.")
            }

            Section("Days") {
                HStack(spacing: 8) {
                    ForEach(Schedule.displayOrder, id: \.self) { weekday in
                        DayButton(weekday: weekday, isOn: dayBinding(weekday))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .disabled(!model.settings.schedule.enabled)

            Section("Hours") {
                DatePicker("From", selection: timeBinding(\.from), displayedComponents: .hourAndMinute)
                DatePicker("To", selection: timeBinding(\.to), displayedComponents: .hourAndMinute)
                Caption("If “To” is earlier than “From”, the window runs overnight. Equal times mean all day.")
                Toggle("Switch on automatically when a window starts", isOn: $model.settings.schedule.autoActivate)
            }
            .disabled(!model.settings.schedule.enabled)
        }
        .formStyle(.grouped)
    }

    private func dayBinding(_ weekday: Int) -> Binding<Bool> {
        Binding(
            get: { model.settings.schedule.weekdays.contains(weekday) },
            set: { on in
                if on {
                    model.settings.schedule.weekdays.insert(weekday)
                } else {
                    model.settings.schedule.weekdays.remove(weekday)
                }
            }
        )
    }

    private func timeBinding(_ keyPath: WritableKeyPath<Schedule, TimeOfDay>) -> Binding<Date> {
        Binding(
            get: { model.settings.schedule[keyPath: keyPath].date },
            set: { model.settings.schedule[keyPath: keyPath] = TimeOfDay(date: $0) }
        )
    }
}

private struct DayButton: View {
    let weekday: Int
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            Text(verbatim: Calendar.current.veryShortStandaloneWeekdaySymbols[weekday - 1])
                .font(.callout.weight(.semibold))
                .frame(width: 32, height: 32)
                .background(Circle().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.15)))
                .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .help(Calendar.current.standaloneWeekdaySymbols[weekday - 1])
    }
}

// MARK: - Conditions

private struct ConditionsSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("App") {
                Picker("Run", selection: $model.settings.appCondition.kind) {
                    ForEach(AppConditionKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                AppChooser()
                    .disabled(model.settings.appCondition.kind == .none)
            }

            Section("Pause") {
                Toggle("Pause while the screen is locked", isOn: $model.settings.pauseWhenLocked)
                Toggle("Pause while another user is logged in on screen", isOn: $model.settings.pauseOnUserSwitch)
                Toggle("Pause while a menu or the screenshot tool is open", isOn: $model.settings.pauseForMenus)
                Caption("Real mouse, trackpad, scroll or keyboard input always pauses Mouse Shaker until the idle delay passes again.")
            }

            Section("Battery") {
                Toggle("Switch off on low battery", isOn: $model.settings.batteryGuard)
                Stepper(value: $model.settings.batteryThreshold, in: Settings.batteryThresholdRange, step: 5) {
                    HStack(spacing: 4) {
                        Text("At or below")
                        Text(verbatim: "\(model.settings.batteryThreshold)%").monospacedDigit()
                    }
                }
                .disabled(!model.settings.batteryGuard)
                Caption("Only applies while running on battery power.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppChooser: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        LabeledContent("App") {
            Menu {
                ForEach(Self.runningApps(), id: \.bundleIdentifier) { app in
                    Button {
                        choose(bundleID: app.bundleIdentifier, name: app.localizedName)
                    } label: {
                        Label {
                            Text(verbatim: app.localizedName ?? app.bundleIdentifier ?? "")
                        } icon: {
                            if let icon = app.icon { Image(nsImage: Self.small(icon)) }
                        }
                    }
                }
                Divider()
                Button("Other…") { chooseFromDisk() }
                if model.settings.appCondition.bundleID != nil {
                    Button("Clear") { choose(bundleID: nil, name: nil) }
                }
            } label: {
                if let name = model.settings.appCondition.appName ?? model.settings.appCondition.bundleID {
                    Text(verbatim: name)
                } else {
                    Text("Choose an app")
                }
            }
            .fixedSize()
        }
    }

    private func choose(bundleID: String?, name: String?) {
        model.settings.appCondition.bundleID = bundleID
        model.settings.appCondition.appName = name
    }

    private func chooseFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url) else { return }
        choose(bundleID: bundle.bundleIdentifier, name: FileManager.default.displayName(atPath: url.path))
    }

    private static func runningApps() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
    }

    private static func small(_ image: NSImage) -> NSImage {
        let copy = image.copy() as? NSImage ?? image
        copy.size = NSSize(width: 16, height: 16)
        return copy
    }
}

// MARK: - Shortcut

private struct ShortcutSettings: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Enable global shortcut", isOn: $model.settings.hotKeyEnabled)
                LabeledContent("Switch Mouse Shaker on or off") {
                    ShortcutRecorder(combo: $model.settings.hotKey) { model.suspendHotKey($0) }
                }
                .disabled(!model.settings.hotKeyEnabled)
                if let error = model.hotKeyError, model.settings.hotKeyEnabled {
                    Text(verbatim: error).font(.caption).foregroundStyle(.red)
                }
                Button("Reset to \(KeyCombo.default.displayString)") { model.settings.hotKey = .default }
                    .disabled(model.settings.hotKey == .default)
            }
            Section {
                Caption("Click the shortcut, then press the new combination. It needs at least one of ⌘, ⌃ or ⌥ (function keys work alone). Press Esc to cancel.")
            }
        }
        .formStyle(.grouped)
    }
}
