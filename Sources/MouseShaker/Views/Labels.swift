import ShakerCore
import SwiftUI

enum IconState {
    case off, waiting, active, paused
}

extension IconStyle {
    func symbol(for state: IconState) -> String {
        switch (self, state) {
        case (.cursor, .off): "cursorarrow"
        case (.cursor, .waiting): "cursorarrow.rays"
        case (.cursor, .active): "cursorarrow.motionlines"
        case (.cursor, .paused): "cursorarrow.slash"
        case (.mouse, .off), (.mouse, .paused): "computermouse"
        case (.mouse, _): "computermouse.fill"
        case (.cup, .off), (.cup, .paused): "cup.and.saucer"
        case (.cup, _): "cup.and.saucer.fill"
        case (.bolt, .off): "bolt"
        case (.bolt, .paused): "bolt.slash"
        case (.bolt, _): "bolt.fill"
        case (.eye, .off): "eye"
        case (.eye, .paused): "eye.slash"
        case (.eye, _): "eye.fill"
        }
    }

    /// Without it, VoiceOver reads the symbols' generic descriptions ("Flash", "Show").
    var title: LocalizedStringKey {
        switch self {
        case .cursor: "Cursor"
        case .mouse: "Mouse"
        case .cup: "Coffee cup"
        case .bolt: "Bolt"
        case .eye: "Eye"
        }
    }
}

extension MovementMode {
    var title: LocalizedStringKey {
        switch self {
        case .natural: "Natural"
        case .silent: "Silent"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .natural: "Moves the pointer a few points along a curved path and back."
        case .silent: "Keeps your Mac active without visibly moving the pointer."
        }
    }
}

extension ScrollDirection {
    var title: LocalizedStringKey {
        switch self {
        case .off: "Off"
        case .vertical: "Vertical"
        case .horizontal: "Horizontal"
        case .both: "Both"
        }
    }
}

extension AppConditionKind {
    var title: LocalizedStringKey {
        switch self {
        case .none: "Always"
        case .running: "Only while the app is running"
        case .frontmost: "Only while the app is in front"
        case .notFrontmost: "Only while the app isn't in front"
        }
    }
}

extension PauseReason {
    var text: String {
        switch self {
        case .noPermission: String(localized: "Paused: needs Accessibility access")
        case .sessionInactive: String(localized: "Paused: another user is active")
        case .screenLocked: String(localized: "Paused: screen locked")
        case .outsideSchedule: String(localized: "Paused: outside schedule")
        case .appCondition: String(localized: "Paused: app condition not met")
        case .menuOrScreenshot: String(localized: "Paused: menu or screenshot open")
        }
    }
}

extension EngineStatus {
    var text: String {
        switch self {
        case .off:
            String(localized: "Off")
        case .paused(let reason):
            reason.text
        case .waitingForIdle(let remaining):
            String(localized: "Waiting for idle · \(DurationFormat.short(remaining))")
        case .active(let next):
            String(localized: "Active · next in \(DurationFormat.short(next))")
        }
    }
}

extension TimeOfDay {
    /// Today at this time, for binding to a `DatePicker`.
    var date: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    init(date: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        self.init(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }
}

/// Picker over a fixed list of durations; 0 renders as "None".
struct DurationPicker: View {
    let title: LocalizedStringKey
    @Binding var selection: TimeInterval
    let options: [TimeInterval]

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options, id: \.self) { value in
                if value == 0 {
                    Text("None").tag(value)
                } else {
                    Text(verbatim: DurationFormat.short(value)).tag(value)
                }
            }
        }
    }
}
