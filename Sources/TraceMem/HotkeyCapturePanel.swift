import AppKit

/// Small key window: "Taste drücken". Uses a local NSEvent monitor, so it works without Accessibility.
@MainActor
final class HotkeyCapturePanel {
    private var panel: NSPanel?
    private var monitor: Any?
    private var capture = HotkeyCapture()
    private let label = NSTextField(labelWithString: "")

    func show(onResult: @escaping @MainActor (HotkeyBinding?) -> Void) {
        close()
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 110),
                        styleMask: [.titled, .closable], backing: .buffered, defer: false)
        p.title = "Hotkey ändern"
        p.level = .floating
        p.center()
        label.frame = NSRect(x: 20, y: 30, width: 320, height: 50)
        label.alignment = .center
        label.maximumNumberOfLines = 2
        label.stringValue = "Taste oder Modifier drücken\n(Esc bricht ab)"
        p.contentView?.addSubview(label)
        panel = p

        capture = HotkeyCapture()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [unowned self] ev in
            let type: CGEventType = ev.type == .keyDown ? .keyDown : .flagsChanged
            let flags = ev.cgEvent?.flags.rawValue ?? UInt64(ev.modifierFlags.rawValue)
            switch capture.handle(type: type, keyCode: ev.keyCode, flags: flags) {
            case .pending: break
            case .cancelled: close(); onResult(nil)
            case .rejected(let why): label.stringValue = "\(why)\nAndere Taste drücken"
            case .captured(let b): close(); onResult(b)
            }
            return nil
        }
        NSApp.activate()
        p.makeKeyAndOrderFront(nil)
    }

    func close() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        panel?.orderOut(nil)
        panel = nil
    }
}
