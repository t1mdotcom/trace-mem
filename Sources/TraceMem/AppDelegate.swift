import AppKit
import os

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
    private static let log = Logger(subsystem: "dev.theinemann.trace-mem", category: "app")

    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: AppState.idle.rawValue, action: nil, keyEquivalent: "")
    private var permissionItems: [Permission: NSMenuItem] = [:]
    var settings = Settings.load() {
        didSet { try? settings.save(); hotkey.matcher = HotkeyMatcher(binding: settings.hotkey) }
    }
    private lazy var hotkey = HotkeyTap(binding: settings.hotkey)
    private let dictation = Dictation()
    private let indicator = IndicatorPanel()
    private var startTask: Task<Void, Never>?
    private let capturePanel = HotkeyCapturePanel()
    private let hotkeyItem = NSMenuItem(title: "", action: #selector(changeHotkey), keyEquivalent: "")
    private let modeItem = NSMenuItem(title: "", action: #selector(toggleMode), keyEquivalent: "")
    private let providerMenu = NSMenu()
    private let micMenu = NSMenu()
    private var lastError: String?

    var state: AppState = .idle {
        didSet {
            statusLine.title = lastError.map { "\(state.rawValue) – \($0)" } ?? state.rawValue
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
        hotkeyItem.target = self
        modeItem.target = self
        menu.addItem(hotkeyItem)
        menu.addItem(modeItem)
        refreshHotkeyItems()
        let micItem = NSMenuItem(title: "Mikrofon", action: nil, keyEquivalent: "")
        micItem.submenu = micMenu
        menu.addItem(micItem)
        let providerItem = NSMenuItem(title: "Text-Cleanup", action: nil, keyEquivalent: "")
        for p in Settings.Provider.allCases {
            let it = NSMenuItem(title: Self.providerTitle(p), action: #selector(pickProvider(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = p.rawValue
            providerMenu.addItem(it)
        }
        providerItem.submenu = providerMenu
        menu.addItem(providerItem)
        refreshProviderItems()
        menu.addItem(.separator())
        menu.addItem(withTitle: "Beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu

        dictation.onUpdate = { [unowned self] text in indicator.update(text: text) }
        dictation.onAssetProgress = { [unowned self] p in
            lastError = p < 1 ? "Sprachmodell lädt \(Int(p * 100))%" : nil
            state = p < 1 ? .blocked : .idle
        }
        hotkey.onStart = { [unowned self] in startRecording() }
        hotkey.onStop = { [unowned self] in stopRecording() }
        refreshPermissions()

        Task { [unowned self] in
            do { try await dictation.ensureAssets(locale: await Dictation.resolveLocale(settings.locale)) }
            catch { fail("Sprachmodell: \(error.localizedDescription)") }
        }
    }

    // MARK: pipeline (T9): hold → record → release → finalize → inject

    private func startRecording() {
        guard state == .idle, startTask == nil else { return } // V11
        lastError = nil
        state = .recording
        indicator.show(status: "…", level: { [unowned self] in dictation.level })
        startTask = Task { [unowned self] in
            do { try await dictation.start(locale: await Dictation.resolveLocale(settings.locale), inputDeviceUID: settings.inputDeviceUID) }
            catch { fail("Aufnahme: \(error.localizedDescription)"); indicator.hide() }
        }
    }

    private func stopRecording() {
        guard state == .recording else { return }
        state = .transcribing
        Task { [unowned self] in
            await startTask?.value // short press: wait until start finished (V5)
            startTask = nil
            do {
                let raw = try await dictation.stop()
                var text = raw
                if !raw.isEmpty, settings.provider != .none {
                    state = .cleanup
                    indicator.update(text: "Cleanup…")
                    let r = await Cleanup.run(raw, settings: settings)
                    text = r.text
                    if let f = r.failure { lastError = "Cleanup übersprungen: \(f.description)" }
                }
                indicator.hide()
                if !text.isEmpty { await Injector.paste(text) }
                if state == .transcribing || state == .cleanup { state = .idle }
            } catch {
                indicator.hide()
                fail("Transkription: \(error.localizedDescription)")
            }
        }
    }

    private func fail(_ message: String) {
        Self.log.error("\(message)")
        lastError = message
        state = .blocked
    }

    // MARK: hotkey settings (T12a)

    private func refreshHotkeyItems() {
        hotkeyItem.title = "Hotkey ändern… (aktuell: \(settings.hotkey.displayName))"
        modeItem.title = settings.hotkey.mode == .hold ? "Modus: Halten zum Sprechen" : "Modus: Drücken für Start/Stopp"
    }

    @objc private func changeHotkey() {
        hotkey.stop() // don't trigger recordings while capturing
        capturePanel.show { [unowned self] binding in
            if var b = binding {
                b.mode = settings.hotkey.mode
                settings.hotkey = b
                refreshHotkeyItems()
            }
            hotkey.start()
        }
    }

    @objc private func toggleMode() {
        settings.hotkey.mode = settings.hotkey.mode == .hold ? .toggle : .hold
        refreshHotkeyItems()
    }

    // MARK: microphone (V15)

    private func rebuildMicMenu() {
        micMenu.removeAllItems()
        let auto = NSMenuItem(title: "Automatisch (eingebautes bevorzugt)", action: #selector(pickMic(_:)), keyEquivalent: "")
        auto.target = self
        auto.state = settings.inputDeviceUID == nil ? .on : .off
        micMenu.addItem(auto)
        micMenu.addItem(.separator())
        for d in MicSelection.available {
            let it = NSMenuItem(title: d.localizedName, action: #selector(pickMic(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = d.uniqueID
            it.state = d.uniqueID == settings.inputDeviceUID ? .on : .off
            micMenu.addItem(it)
        }
    }

    @objc private func pickMic(_ sender: NSMenuItem) {
        settings.inputDeviceUID = sender.representedObject as? String
    }

    // MARK: cleanup provider (T12)

    private static func providerTitle(_ p: Settings.Provider) -> String {
        switch p {
        case .apple: "Apple Intelligence (on-device)"
        case .claude: "Claude CLI"
        case .codex: "Codex CLI"
        case .none: "Aus (Rohtext)"
        }
    }

    private func refreshProviderItems() {
        for it in providerMenu.items {
            it.state = (it.representedObject as? String) == settings.provider.rawValue ? .on : .off
        }
    }

    @objc private func pickProvider(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let p = Settings.Provider(rawValue: raw) else { return }
        settings.provider = p
        refreshProviderItems()
    }

    // MARK: permissions

    func refreshPermissions() {
        for (p, item) in permissionItems {
            item.state = p.granted ? .on : .off
            item.title = p.granted ? p.title : "\(p.title) – fehlt, klicken zum Erteilen"
        }
        if !Permission.allGranted { lastError = "Berechtigung fehlt"; state = .blocked }
        else if state == .blocked, lastError == "Berechtigung fehlt" { lastError = nil; state = .idle }
        if Permission.accessibility.granted, !hotkey.isActive { hotkey.start() }
    }

    @objc private func requestPermission(_ sender: NSMenuItem) {
        (sender.representedObject as? Permission)?.request()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) { refreshPermissions(); rebuildMicMenu() }
}
