import AppKit
import os
import notify

enum AppState: String {
    case idle = "Bereit"
    case recording = "Aufnahme…"
    case transcribing = "Transkribiere…"
    case cleanup = "Cleanup…"
    case meeting = "Meeting läuft…"
    case blocked = "Blockiert"

    var symbol: String {
        switch self {
        case .idle: "waveform"
        case .recording: "waveform.circle.fill"
        case .transcribing, .cleanup: "ellipsis.circle"
        case .meeting: "record.circle.fill"
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
    private let localeMenu = NSMenu()
    private let meeting = MeetingSession()
    private let meetingItem = NSMenuItem(title: "Meeting aufnehmen", action: #selector(toggleMeeting), keyEquivalent: "")
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
        meetingItem.target = self
        menu.addItem(meetingItem)
        menu.addItem(.separator())
        let localeItem = NSMenuItem(title: "Sprache", action: nil, keyEquivalent: "")
        for (title, id) in [("System (\(Locale.current.identifier))", nil), ("Deutsch", "de-DE"), ("English", "en-US")] as [(String, String?)] {
            let it = NSMenuItem(title: title, action: #selector(pickLocale(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = id
            localeMenu.addItem(it)
        }
        localeItem.submenu = localeMenu
        menu.addItem(localeItem)
        refreshLocaleItems()
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
        meeting.onWarning = { [unowned self] msg in lastError = msg; state = state } // refresh status line
        hotkey.onStart = { [unowned self] in startRecording() }
        hotkey.onStop = { [unowned self] in stopRecording() }
        refreshPermissions()

        // Debug/automation hook: `notifyutil -p dev.theinemann.trace-mem.meeting` toggles meeting mode.
        var token: Int32 = 0
        notify_register_dispatch("dev.theinemann.trace-mem.meeting", &token, .main) { [unowned self] _ in
            Diag.log("notify: toggle meeting (state \(state.rawValue), running \(meeting.isRunning))")
            toggleMeeting()
        }
        Diag.log("launched")

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
        Diag.error("\(message)")
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

    // MARK: meeting mode (T15/T16)

    @objc private func toggleMeeting() {
        if meeting.isRunning {
            meetingItem.isEnabled = false
            Task { [unowned self] in
                do {
                    let url = try await meeting.stop(settings: settings)
                    NSWorkspace.shared.open(url)
                    lastError = nil
                    state = .idle
                } catch { fail("Meeting: \(error.localizedDescription)") }
                meetingItem.title = "Meeting aufnehmen"
                meetingItem.isEnabled = true
            }
        } else {
            guard state == .idle else { return } // V11
            lastError = nil
            state = .meeting
            meetingItem.title = "Meeting beenden"
            Task { [unowned self] in
                do { try await meeting.start(locale: await Dictation.resolveLocale(settings.locale), inputDeviceUID: settings.inputDeviceUID) }
                catch {
                    fail("Meeting: \(error.localizedDescription)")
                    meetingItem.title = "Meeting aufnehmen"
                }
            }
        }
    }

    // MARK: locale

    private func refreshLocaleItems() {
        for it in localeMenu.items { it.state = (it.representedObject as? String) == settings.locale ? .on : .off }
    }

    @objc private func pickLocale(_ sender: NSMenuItem) {
        settings.locale = sender.representedObject as? String
        refreshLocaleItems()
        Task { [unowned self] in
            do { try await dictation.ensureAssets(locale: await Dictation.resolveLocale(settings.locale)) }
            catch { fail("Sprachmodell: \(error.localizedDescription)") }
        }
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
            guard let ok = p.granted else { item.state = .off; item.title = p.title; continue }
            item.state = ok ? .on : .off
            item.title = ok ? p.title : "\(p.title) – fehlt, klicken zum Erteilen"
        }
        if !Permission.allGranted { lastError = "Berechtigung fehlt"; state = .blocked }
        else if state == .blocked, lastError == "Berechtigung fehlt" { lastError = nil; state = .idle }
        if Permission.accessibility.granted == true, !hotkey.isActive { hotkey.start() }
    }

    @objc private func requestPermission(_ sender: NSMenuItem) {
        (sender.representedObject as? Permission)?.request()
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) { refreshPermissions(); rebuildMicMenu() }
}
