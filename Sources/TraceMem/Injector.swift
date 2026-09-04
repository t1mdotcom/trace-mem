import AppKit
import CoreGraphics

/// V3: full copy of the pasteboard contents so restore() brings back every type, not only strings.
struct PasteboardSnapshot {
    private let items: [NSPasteboardItem]

    init(_ pb: NSPasteboard) {
        items = (pb.pasteboardItems ?? []).map { src in
            let copy = NSPasteboardItem()
            for type in src.types {
                if let data = src.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    func restore(to pb: NSPasteboard) {
        pb.clearContents()
        if !items.isEmpty { pb.writeObjects(items) }
    }
}

enum Injector {
    /// Puts `text` into the focused app via pasteboard + synthetic ⌘V, then restores the pasteboard.
    @MainActor
    static func paste(_ text: String, pasteboard pb: NSPasteboard = .general) async {
        let snapshot = PasteboardSnapshot(pb)
        pb.clearContents()
        pb.setString(text, forType: .string)

        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // kVK_ANSI_V
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        // Give the target app time to read the pasteboard before restoring (I.inject: 200ms).
        try? await Task.sleep(for: .milliseconds(200))
        snapshot.restore(to: pb)
    }
}
