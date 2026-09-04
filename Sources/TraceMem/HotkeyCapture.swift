import CoreGraphics

/// Pure state machine for "press a key" capture. V12: rejects system-critical bindings.
struct HotkeyCapture: Sendable {
    enum Outcome: Equatable, Sendable { case pending, cancelled, rejected(String), captured(HotkeyBinding) }

    private var pendingModifier: UInt16?
    private var modifierWasCombined = false

    mutating func handle(type: CGEventType, keyCode: UInt16, flags: UInt64) -> Outcome {
        let mods = flags & HotkeyMatcher.relevantFlags
        switch type {
        case .flagsChanged:
            guard let mask = HotkeyMatcher.modifierMask(for: keyCode) else { return .pending }
            if flags & mask != 0 {
                pendingModifier = keyCode
                modifierWasCombined = false
                return .pending
            }
            // released: modifier-only binding if no other key was pressed meanwhile
            guard pendingModifier == keyCode, !modifierWasCombined else { pendingModifier = nil; return .pending }
            pendingModifier = nil
            return .captured(HotkeyBinding(keyCode: keyCode, modifiers: 0, isModifierKey: true, mode: .hold))
        case .keyDown:
            modifierWasCombined = true
            if keyCode == 0x35, mods == 0 { return .cancelled } // Esc
            let cmd = CGEventFlags.maskCommand.rawValue
            if mods & cmd != 0, keyCode == 0x0C { return .rejected("⌘Q ist reserviert") }
            if mods & cmd != 0, keyCode == 0x0D { return .rejected("⌘W ist reserviert") }
            return .captured(HotkeyBinding(keyCode: keyCode, modifiers: mods, isModifierKey: false, mode: .hold))
        default:
            return .pending
        }
    }
}

extension HotkeyBinding {
    /// Human-readable, e.g. "⌥ rechts" or "⌥ Leertaste".
    var displayName: String {
        var parts: [String] = []
        if modifiers & CGEventFlags.maskControl.rawValue != 0 { parts.append("⌃") }
        if modifiers & CGEventFlags.maskAlternate.rawValue != 0 { parts.append("⌥") }
        if modifiers & CGEventFlags.maskShift.rawValue != 0 { parts.append("⇧") }
        if modifiers & CGEventFlags.maskCommand.rawValue != 0 { parts.append("⌘") }
        if modifiers & CGEventFlags.maskSecondaryFn.rawValue != 0 { parts.append("fn") }
        parts.append(Self.keyName(keyCode))
        return parts.joined(separator: " ")
    }

    private static func keyName(_ k: UInt16) -> String {
        switch k {
        case 0x38: "⇧ links"; case 0x3C: "⇧ rechts"
        case 0x3B: "⌃ links"; case 0x3E: "⌃ rechts"
        case 0x3A: "⌥ links"; case 0x3D: "⌥ rechts"
        case 0x37: "⌘ links"; case 0x36: "⌘ rechts"
        case 0x3F: "fn"
        case 0x31: "Leertaste"; case 0x24: "↩"; case 0x30: "⇥"; case 0x33: "⌫"; case 0x35: "Esc"
        case 0x7A: "F1"; case 0x78: "F2"; case 0x63: "F3"; case 0x76: "F4"; case 0x60: "F5"; case 0x61: "F6"
        case 0x62: "F7"; case 0x64: "F8"; case 0x65: "F9"; case 0x6D: "F10"; case 0x67: "F11"; case 0x6F: "F12"
        case 0x00: "A"; case 0x0B: "B"; case 0x08: "C"; case 0x02: "D"; case 0x0E: "E"; case 0x03: "F"; case 0x05: "G"
        case 0x04: "H"; case 0x22: "I"; case 0x26: "J"; case 0x28: "K"; case 0x25: "L"; case 0x2E: "M"; case 0x2D: "N"
        case 0x1F: "O"; case 0x23: "P"; case 0x0C: "Q"; case 0x0F: "R"; case 0x01: "S"; case 0x11: "T"; case 0x20: "U"
        case 0x09: "V"; case 0x0D: "W"; case 0x07: "X"; case 0x10: "Y"; case 0x06: "Z"
        default: "Taste \(k)"
        }
    }
}
