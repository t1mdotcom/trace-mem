import AVFoundation
import CoreAudio
import Foundation

/// System-wide audio output mixdown via Core Audio process tap (macOS 14.2+).
/// First use triggers the "System Audio Recording" TCC prompt (NSAudioCaptureUsageDescription).
final class SystemAudioTap {
    struct CoreAudioError: Error, CustomStringConvertible {
        let status: OSStatus, what: String
        var description: String { "\(what) failed (\(status))" }
    }

    /// AVAudioPCMBuffer is not Sendable; the buffer is exclusively owned by the receiver after yield.
    struct Chunk: @unchecked Sendable { let buffer: AVAudioPCMBuffer }

    let format: AVAudioFormat
    let buffers: AsyncStream<Chunk>

    private let cont: AsyncStream<Chunk>.Continuation
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    init() throws {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.name = "trace-mem system audio"
        desc.isPrivate = true
        desc.muteBehavior = .unmuted

        var tap = AudioObjectID(kAudioObjectUnknown)
        try Self.check(AudioHardwareCreateProcessTap(desc, &tap), "AudioHardwareCreateProcessTap")
        tapID = tap

        var addr = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                              mScope: kAudioObjectPropertyScopeGlobal,
                                              mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        try Self.check(AudioObjectGetPropertyData(tap, &addr, 0, nil, &size, &asbd), "kAudioTapPropertyFormat")
        guard let fmt = AVAudioFormat(streamDescription: &asbd) else {
            throw CoreAudioError(status: -1, what: "AVAudioFormat from tap ASBD")
        }
        format = fmt

        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "trace-mem tap",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[String: Any]](),
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: desc.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        try Self.check(AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &agg), "AudioHardwareCreateAggregateDevice")
        aggID = agg

        (buffers, cont) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
    }

    func start() throws {
        let fmt = format
        let cont = cont
        var pid: AudioDeviceIOProcID?
        try Self.check(AudioDeviceCreateIOProcIDWithBlock(&pid, aggID, nil) { _, inInput, _, _, _ in
            // inInput memory is only valid during the callback → copy into an owned buffer.
            let src = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInput))
            guard let first = src.first, first.mDataByteSize > 0 else { return }
            let frames = first.mDataByteSize / fmt.streamDescription.pointee.mBytesPerFrame
            guard let copy = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frames) else { return }
            let dst = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
            for (i, s) in src.enumerated() where i < dst.count {
                guard let from = s.mData, let to = dst[i].mData else { continue }
                memcpy(to, from, Int(min(s.mDataByteSize, dst[i].mDataByteSize)))
            }
            copy.frameLength = frames
            cont.yield(Chunk(buffer: copy))
        }, "AudioDeviceCreateIOProcIDWithBlock")
        procID = pid
        try Self.check(AudioDeviceStart(aggID, pid), "AudioDeviceStart")
    }

    func stop() {
        if let procID {
            AudioDeviceStop(aggID, procID)
            AudioDeviceDestroyIOProcID(aggID, procID)
            self.procID = nil
        }
        cont.finish()
        if aggID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggID); aggID = kAudioObjectUnknown }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID); tapID = kAudioObjectUnknown }
    }

    deinit { stop() }

    private static func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else { throw CoreAudioError(status: status, what: what) }
    }
}
