import AppKit
import ShakerCore
import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var model: AppModel
    @State private var panel = WindowReference()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if !model.hasPermission {
                PermissionBanner()
            }
            Divider()

            Picker("Mode", selection: $model.settings.mode) {
                ForEach(MovementMode.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Text("Idle delay").foregroundStyle(.secondary)
                    DurationPicker(title: "Idle delay", selection: $model.settings.idleDelay, options: Settings.idleDelayOptions)
                        .labelsHidden()
                        .fixedSize()
                }
                GridRow {
                    Text("Move every").foregroundStyle(.secondary)
                    DurationPicker(title: "Move every", selection: $model.settings.interval, options: Settings.intervalOptions)
                        .labelsHidden()
                        .fixedSize()
                        .disabled(model.settings.continuous)
                }
            }

            Divider()
            DeactivationControls()
            Divider()

            HStack {
                Button("Settings…") {
                    // Otherwise the panel stays on top of the settings window it just opened.
                    MenuBarPanel.dismiss(panel.window)
                    SettingsWindow.show(model: model)
                }
                .keyboardShortcut(",")
                Spacer()
                Button("Quit Mouse Shaker") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 310)
        .background(HostingWindowReader(reference: panel))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.menuBarSymbol)
                .font(.system(size: 20))
                .frame(width: 28)
                .foregroundStyle(model.status.isRunning ? Color.accentColor : Color.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mouse Shaker").font(.headline)
                Text(verbatim: model.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .monospacedDigit()
            }
            Spacer()
            Toggle("Active", isOn: Binding(get: { model.isEnabled }, set: { model.setEnabled($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .help(model.settings.hotKeyEnabled ? model.settings.hotKey.displayString : "")
        }
    }
}

struct PermissionBanner: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text("Accessibility access needed").font(.callout.weight(.semibold))
                Text("Mouse Shaker needs it to move the pointer.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Grant Access…") { Permissions.requestOrOpenSettings() }
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    }
}

struct DeactivationControls: View {
    @EnvironmentObject private var model: AppModel
    @State private var atTime = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()

    var body: some View {
        if let pending = model.pending {
            HStack(spacing: 8) {
                Image(systemName: "timer").foregroundStyle(.secondary)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(verbatim: Self.describe(pending, now: context.date))
                        .monospacedDigit()
                }
                Spacer()
                Button("Cancel") { model.cancelPendingDeactivation() }
                    .buttonStyle(.borderless)
            }
            .font(.callout)
        } else {
            HStack(spacing: 6) {
                Menu("Turn off in") {
                    ForEach(PendingDeactivation.presets, id: \.self) { duration in
                        Button(DurationFormat.short(duration)) { model.deactivate(after: duration) }
                    }
                }
                .fixedSize()
                Spacer()
                Text("or at").foregroundStyle(.secondary)
                DatePicker("Turn off at", selection: $atTime, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .fixedSize()
                Button("Set") { model.deactivate(at: TimeOfDay(date: atTime)) }
            }
        }
    }

    static func describe(_ pending: PendingDeactivation, now: Date) -> String {
        let time = pending.date.formatted(date: .omitted, time: .shortened)
        let remaining = DurationFormat.short(pending.date.timeIntervalSince(now))
        return String(localized: "Turns off at \(time) · in \(remaining)")
    }
}
