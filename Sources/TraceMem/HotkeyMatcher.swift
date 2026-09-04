import CoreGraphics

/// Pure state machine: (binding, event) → action. No AppKit, unit-testable.
struct HotkeyMatcher: Sendable {
    enum Action: Equatable, Sendable { case start, stop, none }
    struct Result: Equatable, Sendable {
        var action: Action
        /// V13: swallow event only when it matched a non-modifier binding.
        var consume: Bool
    }

    var binding: HotkeyBinding
    private(set) var isRecording = false
    private var keyIsDown = false

    /// Only these flags participate in matching; caps lock, numpad, autorepeat bits are ignored.
    static let relevantFlags: UInt64 = CGEventFlags.maskShift.rawValue | CGEventFlags.maskControl.rawValue
        | CGEventFlags.maskAlternate.rawValue | CGEventFlags.maskCommand.rawValue | CGEventFlags.maskSecondaryFn.rawValue

    /// keyCode of a modifier key → its CGEventFlags mask.
    static func modifierMask(for keyCode: UInt16) -> UInt64? {
        switch keyCode {
        case 0x38, 0x3C: CGEventFlags.maskShift.rawValue
        case 0x3B, 0x3E: CGEventFlags.maskControl.rawValue
        case 0x3A, 0x3D: CGEventFlags.maskAlternate.rawValue
        case 0x37, 0x36: CGEventFlags.maskCommand.rawValue
        case 0x3F: CGEventFlags.maskSecondaryFn.rawValue
        default: nil
        }
    }

    init(binding: HotkeyBinding) { self.binding = binding }

    mutating func handle(type: CGEventType, keyCode: UInt16, flags: UInt64, autorepeat: Bool = false) -> Result {
        guard keyCode == binding.keyCode else { return Result(action: .none, consume: false) }

        let pressed: Bool
        let consume: Bool
        if binding.isModifierKey {
            guard type == .flagsChanged, let mask = Self.modifierMask(for: keyCode) else {
                return Result(action: .none, consume: false)
            }
            pressed = flags & mask != 0
            consume = false
        } else {
            guard type == .keyDown || type == .keyUp else { return Result(action: .none, consume: false) }
            if type == .keyDown {
                guard flags & Self.relevantFlags == binding.modifiers else { return Result(action: .none, consume: false) }
                if autorepeat { return Result(action: .none, consume: true) }
                pressed = true
            } else {
                // keyUp: match regardless of modifiers (user may release them first)
                guard keyIsDown else { return Result(action: .none, consume: false) }
                pressed = false
            }
            consume = true
        }

        guard pressed != keyIsDown else { return Result(action: .none, consume: consume) }
        keyIsDown = pressed

        switch binding.mode {
        case .hold:
            isRecording = pressed
            return Result(action: pressed ? .start : .stop, consume: consume)
        case .toggle:
            guard pressed else { return Result(action: .none, consume: consume) }
            isRecording.toggle()
            return Result(action: isRecording ? .start : .stop, consume: consume)
        }
    }

    /// Called when recording ended for another reason (e.g. meeting mode, error).
    mutating func reset() { isRecording = false; keyIsDown = false }
}
