import CoreGraphics
import Foundation
import os

/// Global CGEvent tap. Requires Accessibility. V8: re-enables itself when the system disables it.
@MainActor
final class HotkeyTap {
    private static let log = Logger(subsystem: "dev.theinemann.trace-mem", category: "hotkey")

    var matcher: HotkeyMatcher
    var onStart: () -> Void = {}
    var onStop: () -> Void = {}

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    init(binding: HotkeyBinding) { matcher = HotkeyMatcher(binding: binding) }

    var isActive: Bool { tap != nil }

    /// Returns false if the tap could not be created (missing Accessibility permission).
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: hotkeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Diag.error("tapCreate failed – Accessibility missing?")
            return false
        }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        tap = nil; source = nil
    }

    fileprivate func handle(type: CGEventType, keyCode: UInt16, flags: UInt64, autorepeat: Bool) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            Diag.error("tap disabled (\(type.rawValue)) – re-enabling")
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let r = matcher.handle(type: type, keyCode: keyCode, flags: flags, autorepeat: autorepeat)
        switch r.action {
        case .start: onStart()
        case .stop: onStop()
        case .none: break
        }
        return r.consume
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<HotkeyTap>.fromOpaque(refcon).takeUnretainedValue()
    let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags.rawValue
    let autorepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    // Tap source lives on the main run loop → callback runs on main thread.
    let consume = MainActor.assumeIsolated {
        tap.handle(type: type, keyCode: keyCode, flags: flags, autorepeat: autorepeat)
    }
    return consume ? nil : Unmanaged.passUnretained(event)
}
