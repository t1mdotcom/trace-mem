import AVFoundation
import ApplicationServices
import AppKit

/// V4: every permission has a visible state + a fix link. No silent fail.
enum Permission: CaseIterable {
    case microphone
    case accessibility
    /// System audio recording (Core Audio tap). Not queryable → shown as link only; silence means denied.
    case systemAudio

    var title: String {
        switch self {
        case .microphone: "Mikrofon"
        case .accessibility: "Bedienungshilfen (Hotkey + Einfügen)"
        case .systemAudio: "Systemaudio (Meetings) – in Einstellungen prüfen"
        }
    }

    /// nil = cannot be determined by API.
    var granted: Bool? {
        switch self {
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .accessibility: AXIsProcessTrusted()
        case .systemAudio: nil
        }
    }

    private var settingsURL: URL {
        let pane = switch self {
        case .microphone: "Privacy_Microphone"
        case .accessibility: "Privacy_Accessibility"
        case .systemAudio: "Privacy_AudioCapture"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
    }

    /// Prompts the system dialog when possible, otherwise opens System Settings.
    func request() {
        switch self {
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
            } else {
                NSWorkspace.shared.open(settingsURL)
            }
        case .accessibility:
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(opts) {
                NSWorkspace.shared.open(settingsURL)
            }
        case .systemAudio:
            NSWorkspace.shared.open(settingsURL)
        }
    }

    /// Only permissions that can be queried count; systemAudio is checked at meeting start via silence detection.
    static var allGranted: Bool { allCases.allSatisfy { $0.granted ?? true } }
}
