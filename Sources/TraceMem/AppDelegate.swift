import AppKit

enum AppState: String {
    case idle = "Bereit"
    case recording = "Aufnahme…"
    case transcribing = "Transkribiere…"
    case cleanup = "Cleanup…"
    case blocked = "Blockiert"

    var symbol: String {
        switch self {
        case .idle: "waveform"
        case .recording: "waveform.circle.fill"
        case .transcribing, .cleanup: "ellipsis.circle"
        case .blocked: "exclamationmark.triangle"
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: AppState.idle.rawValue, action: nil, keyEquivalent: "")

    var state: AppState = .idle {
        didSet {
            statusLine.title = state.rawValue
            statusItem.button?.image = NSImage(systemSymbolName: state.symbol, accessibilityDescription: state.rawValue)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: AppState.idle.symbol, accessibilityDescription: "trace-mem")

        let menu = NSMenu()
        statusLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
}
