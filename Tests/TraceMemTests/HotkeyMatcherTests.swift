import CoreGraphics
import Testing
@testable import TraceMem

private let alt = CGEventFlags.maskAlternate.rawValue
private let cmd = CGEventFlags.maskCommand.rawValue

@Test func modifierOnlyHold() {
    var m = HotkeyMatcher(binding: .default) // right ⌥, hold
    #expect(m.handle(type: .flagsChanged, keyCode: 0x3D, flags: alt) == .init(action: .start, consume: false))
    #expect(m.handle(type: .flagsChanged, keyCode: 0x3D, flags: alt) == .init(action: .none, consume: false)) // dup
    #expect(m.handle(type: .flagsChanged, keyCode: 0x3D, flags: 0) == .init(action: .stop, consume: false))
    // left ⌥ (0x3A) must not match
    #expect(m.handle(type: .flagsChanged, keyCode: 0x3A, flags: alt) == .init(action: .none, consume: false))
}

@Test func keyWithModifiersHoldConsumesOnlyMatches() {
    // ⌥+Space hold
    let b = HotkeyBinding(keyCode: 49, modifiers: alt, isModifierKey: false, mode: .hold)
    var m = HotkeyMatcher(binding: b)
    // plain space passes through (V13)
    #expect(m.handle(type: .keyDown, keyCode: 49, flags: 0) == .init(action: .none, consume: false))
    #expect(m.handle(type: .keyUp, keyCode: 49, flags: 0) == .init(action: .none, consume: false))
    // ⌘+Space (Spotlight) passes through
    #expect(m.handle(type: .keyDown, keyCode: 49, flags: cmd) == .init(action: .none, consume: false))
    // ⌥+Space starts, autorepeat swallowed, release (⌥ already up) stops
    #expect(m.handle(type: .keyDown, keyCode: 49, flags: alt) == .init(action: .start, consume: true))
    #expect(m.handle(type: .keyDown, keyCode: 49, flags: alt, autorepeat: true) == .init(action: .none, consume: true))
    #expect(m.handle(type: .keyUp, keyCode: 49, flags: 0) == .init(action: .stop, consume: true))
    // other keys untouched
    #expect(m.handle(type: .keyDown, keyCode: 0, flags: alt) == .init(action: .none, consume: false))
}

@Test func toggleMode() {
    let b = HotkeyBinding(keyCode: 0x60, modifiers: 0, isModifierKey: false, mode: .toggle) // F5
    var m = HotkeyMatcher(binding: b)
    #expect(m.handle(type: .keyDown, keyCode: 0x60, flags: 0).action == .start)
    #expect(m.handle(type: .keyUp, keyCode: 0x60, flags: 0).action == .none)
    #expect(m.isRecording)
    #expect(m.handle(type: .keyDown, keyCode: 0x60, flags: 0).action == .stop)
    #expect(m.handle(type: .keyUp, keyCode: 0x60, flags: 0).action == .none)
    #expect(!m.isRecording)
    _ = m.handle(type: .keyDown, keyCode: 0x60, flags: 0)
    m.reset()
    #expect(!m.isRecording)
}
