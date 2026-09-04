import CoreGraphics
import Testing
@testable import TraceMem

private let alt = CGEventFlags.maskAlternate.rawValue
private let cmd = CGEventFlags.maskCommand.rawValue

@Test func captureModifierOnly() {
    var c = HotkeyCapture()
    #expect(c.handle(type: .flagsChanged, keyCode: 0x3D, flags: alt) == .pending)
    #expect(c.handle(type: .flagsChanged, keyCode: 0x3D, flags: 0)
        == .captured(HotkeyBinding(keyCode: 0x3D, modifiers: 0, isModifierKey: true, mode: .hold)))
}

@Test func captureKeyWithModifier() {
    var c = HotkeyCapture()
    #expect(c.handle(type: .flagsChanged, keyCode: 0x3A, flags: alt) == .pending)
    #expect(c.handle(type: .keyDown, keyCode: 49, flags: alt)
        == .captured(HotkeyBinding(keyCode: 49, modifiers: alt, isModifierKey: false, mode: .hold)))
    // releasing ⌥ afterwards must not produce a second binding
    #expect(c.handle(type: .flagsChanged, keyCode: 0x3A, flags: 0) == .pending)
}

@Test func captureRejectsCriticalAndCancelsOnEsc() {
    var c = HotkeyCapture()
    #expect(c.handle(type: .keyDown, keyCode: 0x35, flags: 0) == .cancelled)
    #expect(c.handle(type: .keyDown, keyCode: 0x0C, flags: cmd) == .rejected("⌘Q ist reserviert"))
    #expect(c.handle(type: .keyDown, keyCode: 0x0D, flags: cmd) == .rejected("⌘W ist reserviert"))
    // ⌥Esc is a valid binding
    if case .captured(let b) = c.handle(type: .keyDown, keyCode: 0x35, flags: alt) {
        #expect(b.displayName == "⌥ Esc")
    } else { Issue.record("⌥Esc should be captured") }
}

@Test func displayNames() {
    #expect(HotkeyBinding.default.displayName == "⌥ rechts")
    #expect(HotkeyBinding(keyCode: 0x60, modifiers: 0, isModifierKey: false, mode: .toggle).displayName == "F5")
}
