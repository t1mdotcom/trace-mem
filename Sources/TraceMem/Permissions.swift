import AVFoundation
import ApplicationServices
import AppKit

/// V4: every permission has a visible state + a fix link. No silent fail.
enum Permission: CaseIterable {
    case microphone
    case accessibility

    var title: String {
        switch self {
        case .microphone: "Mikrofon"
        case .accessibility: "Bedienungshilfen (Hotkey + Einfügen)"
        }
    }

    var granted: Bool {
        switch self {
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .accessibility: AXIsProcessTrusted()
        }
    }

    private var settingsURL: URL {
        let pane = switch self {
        case .microphone: "Privacy_Microphone"
        case .accessibility: "Privacy_Accessibility"
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
        }
    }

    static var allGranted: Bool { allCases.allSatisfy(\.granted) }
}
