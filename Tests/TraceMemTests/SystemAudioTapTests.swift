import AVFoundation
import Testing
@testable import TraceMem

@Test func bufferCopyPreservesSamples() {
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 2, interleaved: true)!
    var samples: [Float] = (0..<1024).map { Float($0 % 7) / 7 } // 512 frames interleaved stereo
    let copy = samples.withUnsafeMutableBufferPointer { p -> AVAudioPCMBuffer? in
        var abl = AudioBufferList(mNumberBuffers: 1, mBuffers: AudioBuffer(
            mNumberChannels: 2, mDataByteSize: UInt32(p.count * 4), mData: UnsafeMutableRawPointer(p.baseAddress)))
        return SystemAudioTap.copy(&abl, format: fmt)
    }
    let c = try! #require(copy)
    #expect(c.frameLength == 512)
    let out = UnsafeBufferPointer(start: c.floatChannelData![0], count: 1024)
    #expect(out.max() ?? 0 > 0.8) // V16: not silence
    #expect(Array(out) == samples)
}
