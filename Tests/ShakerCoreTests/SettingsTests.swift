import Foundation
import Testing
@testable import ShakerCore

@Suite struct SettingsTests {
    @Test func roundTrips() throws {
        var s = Settings()
        s.mode = .silent
        s.idleDelay = 5
        s.deactivateAfter = 3600
        s.clickPositions = [ScreenPoint(x: 10, y: 20)]
        s.schedule.enabled = true
        s.schedule.weekdays = [1, 7]
        s.appCondition = AppCondition(kind: .frontmost, bundleID: "com.apple.Safari", appName: "Safari")
        s.hotKeyEnabled = false
        let data = try JSONEncoder().encode(s)
        #expect(try JSONDecoder().decode(Settings.self, from: data) == s)
    }

    @Test func missingKeysFallBackToDefaults() throws {
        let json = #"{"mode":"silent","schedule":{"enabled":true}}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Settings.self, from: json)
        var expected = Settings()
        expected.mode = .silent
        expected.schedule.enabled = true
        #expect(s == expected)
    }

    @Test func unknownEnumValueFallsBackInsteadOfThrowing() throws {
        let json = #"{"mode":"teleport","iconStyle":"unicorn","idleDelay":12}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(Settings.self, from: json)
        #expect(s.mode == .natural)
        #expect(s.iconStyle == .cursor)
        #expect(s.idleDelay == 12)
    }

    @Test func defaultHotKeyRendersInAppleOrder() {
        #expect(KeyCombo.default.displayString == "⌃⌘J")
        let all = KeyCombo(keyCode: 0, modifiers: [.command, .shift, .option, .control], key: "A")
        #expect(all.displayString == "⌃⌥⇧⌘A")
    }
}
