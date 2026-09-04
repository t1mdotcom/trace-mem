import AVFoundation
import Foundation
import Speech
import os

/// Mic ("Ich") + system audio ("Andere") → two SpeechTranscribers → one chronological Markdown file.
@MainActor
final class MeetingSession {
    private static let log = Logger(subsystem: "dev.theinemann.trace-mem", category: "meeting")

    private(set) var isRunning = false
    private(set) var fileURL: URL?
    var onSegment: (TranscriptWriter.Segment) -> Void = { _ in }
    /// Non-fatal problems while running (e.g. system audio silent → permission missing).
    var onWarning: (String?) -> Void = { _ in }

    private var writer: TranscriptWriter?
    private var started = Date()
    private var micProvider: CaptureInputSequenceProvider?
    private var systemTap: SystemAudioTap?
    private var analyzers: [SpeechAnalyzer] = []
    private var continuations: [AsyncStream<AnalyzerInput>.Continuation] = []
    /// Per-speaker offset (seconds) that maps a stream's audio time to seconds since session start.
    private let origins = OSAllocatedUnfairLock<[String: Double]>(initialState: [:])
    private var pumpTasks: [Task<Void, Never>] = []   // never awaited: input sequences don't end on cancel
    private var resultTasks: [Task<Void, Never>] = [] // end when analyzers finish

    func start(locale: Locale, inputDeviceUID: String?, output: URL? = nil) async throws {
        guard !isRunning else { return } // V11
        Diag.log("meeting start")
        started = Date()
        let url = output ?? TranscriptWriter.defaultURL(for: started)
        writer = try TranscriptWriter(url: url, started: started)
        fileURL = url
        do {
            // --- "Ich": microphone
            let micT = Self.makeTranscriber(locale)
            guard let mic = MicSelection.device(preferredUID: inputDeviceUID) else {
                throw NSError(domain: "trace-mem", code: 1, userInfo: [NSLocalizedDescriptionKey: "Kein Mikrofon gefunden"])
            }
            let provider = try await CaptureInputSequenceProvider.providerWithSession(from: mic, compatibleWith: [micT])
            let (micStream, micCont) = AsyncStream<AnalyzerInput>.makeStream()
            continuations.append(micCont)
            let origins = origins, started = started
            pumpTasks.append(Task {
                do {
                    for try await i in provider.analyzerInputs {
                        if Task.isCancelled { break }
                        origins.withLock { o in
                            if o["Ich"] == nil {
                                o["Ich"] = (i.bufferStartTime?.seconds ?? 0) - Date().timeIntervalSince(started)
                            }
                        }
                        micCont.yield(i)
                    }
                } catch { Diag.error("mic pump: \(error)") }
                micCont.finish()
            })
            let micA = SpeechAnalyzer(modules: [micT])
            resultTasks.append(resultsTask(micT, speaker: "Ich"))
            try await micA.start(inputSequence: micStream)
            if !provider.captureSession.isRunning { provider.captureSession.startRunning() }
            micProvider = provider
            analyzers.append(micA)
            Diag.log("meeting: mic running (\(mic.localizedName))")

            // --- "Andere": system audio tap
            let sysT = Self.makeTranscriber(locale)
            let tap = try SystemAudioTap()
            let converter = try await AnalyzerInputConverter.converter(compatibleWith: [sysT])
            let (sysStream, sysCont) = AsyncStream<AnalyzerInput>.makeStream()
            continuations.append(sysCont)
            let rate = tap.format.sampleRate
            pumpTasks.append(Task {
                var n = 0, sampleTime: AVAudioFramePosition = 0, yielded = 0, peak: Float = 0
                var everHeard = false, warned = false
                origins.withLock { $0["Andere"] = -Date().timeIntervalSince(started) }
                for await chunk in tap.buffers {
                    if Task.isCancelled { break }
                    n += 1
                    if let ch = chunk.buffer.floatChannelData {
                        let len = Int(chunk.buffer.frameLength) * Int(chunk.buffer.format.channelCount)
                        for k in 0..<len { peak = max(peak, abs(ch[0][k])) }
                    }
                    do {
                        let inputs = try converter.convert(chunk.buffer, at: AVAudioTime(sampleTime: sampleTime, atRate: rate))
                        yielded += inputs.count
                        for i in inputs { sysCont.yield(i) }
                    } catch { Diag.error("convert: \(error)") }
                    sampleTime += AVAudioFramePosition(chunk.buffer.frameLength)
                    if peak > 0, !everHeard {
                        everHeard = true
                        if warned { await MainActor.run { [weak self] in self?.onWarning(nil) } }
                    }
                    if n % 500 == 0 {
                        Diag.log("system tap: \(n) chunks, peak \(peak), inputs yielded \(yielded)")
                        // ~30s of pure zeros = TCC "System Audio Recording" denied (macOS delivers silence, no error).
                        if n == 3000, !everHeard {
                            warned = true
                            Diag.error("system tap silent for 30s – Systemaudio-Freigabe fehlt?")
                            await MainActor.run { [weak self] in self?.onWarning("Systemaudio stumm – Freigabe in Systemeinstellungen prüfen") }
                        }
                        peak = 0
                    }
                }
                for i in (try? converter.flush()) ?? [] { sysCont.yield(i) }
                sysCont.finish()
            })
            let sysA = SpeechAnalyzer(modules: [sysT])
            resultTasks.append(resultsTask(sysT, speaker: "Andere"))
            try await sysA.start(inputSequence: sysStream)
            try tap.start()
            systemTap = tap
            analyzers.append(sysA)
            Diag.log("meeting: system tap running \(tap.format)")

            isRunning = true
        } catch {
            await teardown()
            throw error
        }
    }

    /// Finalizes both streams, writes summary (if provider set), returns the file.
    func stop(settings: Settings) async throws -> URL {
        guard isRunning, let url = fileURL else { throw NSError(domain: "trace-mem", code: 2) }
        Diag.log("meeting stop")
        isRunning = false
        micProvider?.captureSession.stopRunning()
        systemTap?.stop()
        continuations.forEach { $0.finish() }
        pumpTasks.forEach { $0.cancel() }
        for a in analyzers {
            do { try await a.finalizeAndFinishThroughEndOfInput() } catch { Diag.error("finalize: \(error)") }
        }
        Diag.log("meeting: analyzers finalized")
        for t in resultTasks { await t.value }
        Diag.log("meeting: tasks done")

        var w = writer!
        try w.finish(summary: nil)
        let transcript = w.written.map(TranscriptWriter.line).joined(separator: "\n")
        let s = await Cleanup.summarize(transcript, settings: settings)
        if let f = s.failure { Diag.error("summary skipped: \(f.description)") }
        try w.finish(summary: s.text ?? s.failure.map { "_Zusammenfassung übersprungen: \($0.description)_" }, ended: Date())
        await teardown()
        return url
    }

    private static func makeTranscriber(_ locale: Locale) -> SpeechTranscriber {
        // Same preset as dictation (known to work); finals filtered in resultsTask.
        SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
    }

    private func resultsTask(_ t: SpeechTranscriber, speaker: String) -> Task<Void, Never> {
        Task { [weak self] in
            do {
                for try await r in t.results {
                    guard r.isFinal else { continue }
                    let origin = self?.origins.withLock { $0[speaker] } ?? 0
                    let seg = TranscriptWriter.Segment(start: r.range.start.seconds - origin, speaker: speaker,
                                                       text: String(r.text.characters).trimmingCharacters(in: .whitespacesAndNewlines))
                    self?.record(seg)
                }
            } catch { Diag.error("\(speaker) results: \(error)") }
            Diag.log("\(speaker) results ended")
        }
    }

    private func record(_ seg: TranscriptWriter.Segment) {
        Diag.log("segment \(seg.speaker) @\(seg.start): \(seg.text)")
        do { try writer?.add(seg); onSegment(seg) }
        catch { Diag.error("write: \(error)") }
    }

    private func teardown() async {
        micProvider?.captureSession.stopRunning()
        systemTap?.stop()
        continuations.forEach { $0.finish() }
        pumpTasks.forEach { $0.cancel() }
        resultTasks.forEach { $0.cancel() }
        micProvider = nil; systemTap = nil; analyzers = []; continuations = []; pumpTasks = []; resultTasks = []
        isRunning = false
    }
}
