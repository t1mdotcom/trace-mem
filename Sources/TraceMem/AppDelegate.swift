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
    private var permissionItems: [Permission: NSMenuItem] = [:]
    var settings = Settings.load() {
        didSet { try? settings.save() }
    }

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
        for p in Permission.allCases {
            let item = NSMenuItem(title: p.title, action: #selector(requestPermission(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = p
            permissionItems[p] = item
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu
        refreshPermissions()
    }

    func refreshPermissions() {
        for (p, item) in permissionItems {
            item.state = p.granted ? .on : .off
            item.title = p.granted ? p.title : "\(p.title) – fehlt, klicken zum Erteilen"
        }
        if !Permission.allGranted { state = .blocked } else if state == .blocked { state = .idle }
    }

    @objc private func requestPermission(_ sender: NSMenuItem) {
        (sender.representedObject as? Permission)?.request()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) { refreshPermissions() }
}
