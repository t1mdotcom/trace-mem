import AVFoundation

struct MicInfo: Equatable, Sendable {
    var uid: String
    var name: String
    var isBuiltIn: Bool
}

/// V15: user choice → built-in → first available. Pure, tested.
enum MicSelection {
    static func pick(preferredUID: String?, from devices: [MicInfo]) -> MicInfo? {
        if let preferredUID, let d = devices.first(where: { $0.uid == preferredUID }) { return d }
        return devices.first(where: \.isBuiltIn) ?? devices.first
    }

    static var available: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
    }

    static func info(_ d: AVCaptureDevice) -> MicInfo {
        // kIOAudioDeviceTransportTypeBuiltIn = 'bltn'
        MicInfo(uid: d.uniqueID, name: d.localizedName, isBuiltIn: d.transportType == 0x626C_746E)
    }

    static func device(preferredUID: String?) -> AVCaptureDevice? {
        let devs = available
        guard let chosen = pick(preferredUID: preferredUID, from: devs.map(info)) else { return AVCaptureDevice.default(for: .audio) }
        return devs.first { $0.uniqueID == chosen.uid }
    }
}
