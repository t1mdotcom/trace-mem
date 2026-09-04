import Foundation

struct HotkeyBinding: Codable, Equatable, Sendable {
    enum Mode: String, Codable, Sendable { case hold, toggle }
    var keyCode: UInt16
    var modifiers: UInt64
    var isModifierKey: Bool
    var mode: Mode

    /// Right ⌥ (kVK_RightOption = 0x3D), hold. Placeholder until user picks one.
    static let `default` = HotkeyBinding(keyCode: 0x3D, modifiers: 0, isModifierKey: true, mode: .hold)
}

struct Settings: Codable, Equatable, Sendable {
    enum Provider: String, Codable, CaseIterable, Sendable { case apple, claude, codex, none }

    var provider: Provider = .apple
    /// Provider for meeting summaries; nil = same as `provider`.
    var summaryProvider: Provider? = nil
    var model: String? = nil
    var hotkey: HotkeyBinding = .default
    var locale: String? = nil
    var cleanupTimeoutMs: Int = 3000
    var inputDeviceUID: String? = nil

    static let url: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("trace-mem", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }()

    static func load(from url: URL = Settings.url) -> Settings {
        guard let data = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(Settings.self, from: data) else { return Settings() }
        return s
    }

    func save(to url: URL = Settings.url) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(self).write(to: url, options: .atomic)
    }
}
