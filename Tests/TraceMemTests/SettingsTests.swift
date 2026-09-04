import Foundation
import Testing
@testable import TraceMem

@Test func settingsRoundTripAndDefaults() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("trace-mem-\(UUID()).json")
    #expect(Settings.load(from: tmp) == Settings())

    var s = Settings()
    s.provider = .codex
    s.hotkey = HotkeyBinding(keyCode: 49, modifiers: 0x80000, isModifierKey: false, mode: .toggle)
    try s.save(to: tmp)
    #expect(Settings.load(from: tmp) == s)

    try "not json".write(to: tmp, atomically: true, encoding: .utf8)
    #expect(Settings.load(from: tmp) == Settings())
}
