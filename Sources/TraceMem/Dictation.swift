import AVFoundation
import Foundation
import Speech
import os

/// One push-to-talk session: mic → SpeechAnalyzer → text. On-device only (V1).
@MainActor
final class Dictation {
    private static let log = Logger(subsystem: "dev.theinemann.trace-mem", category: "dictation")

    enum State { case idle, preparing, recording, finalizing }
    private(set) var state: State = .idle

    /// Partial + final text so far, for the indicator.
    var onUpdate: (String) -> Void = { _ in }
    /// Asset download progress (0…1) while models install (V6).
    var onAssetProgress: (Double) -> Void = { _ in }

    private var transcriber: SpeechTranscriber?
    private var analyzer: SpeechAnalyzer?
    private var provider: CaptureInputSequenceProvider?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var pumpTask: Task<Void, Never>?
    private var resultsTask: Task<String, Error>?

    /// Mic level in dB (≈ -160…0) or nil when not recording. Cheap to poll.
    var level: Float? {
        provider?.captureAudioDataOutput.connections.first?.audioChannels.first?.averagePowerLevel
    }

    static func resolveLocale(_ preferred: String?) async -> Locale {
        let want = preferred.map(Locale.init(identifier:)) ?? Locale.current
        return await SpeechTranscriber.supportedLocale(equivalentTo: want) ?? Locale(identifier: "de-DE")
    }

    /// V6: make sure the on-device model for `locale` is installed; reports progress.
    func ensureAssets(locale: Locale) async throws {
        let t = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard await AssetInventory.status(forModules: [t]) != .installed else { return }
        guard let req = try await AssetInventory.assetInstallationRequest(supporting: [t]) else { return }
        let progress = req.progress
        let poll = Task { [onAssetProgress] in
            while !Task.isCancelled {
                onAssetProgress(progress.fractionCompleted)
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
        defer { poll.cancel(); onAssetProgress(1) }
        try await req.downloadAndInstall()
    }

    func start(locale: Locale, inputDeviceUID: String?) async throws {
        guard state == .idle else { return } // V11
        state = .preparing
        do {
            let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
            guard let mic = MicSelection.device(preferredUID: inputDeviceUID) else {
                throw NSError(domain: "trace-mem", code: 1, userInfo: [NSLocalizedDescriptionKey: "Kein Mikrofon gefunden"])
            }
            let provider = try await CaptureInputSequenceProvider.providerWithSession(from: mic, compatibleWith: [transcriber])

            // Own stream so stop() can end input deterministically (finalizeAndFinishThroughEndOfInput needs an end).
            let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
            inputContinuation = cont
            pumpTask = Task {
                do {
                    for try await input in provider.analyzerInputs {
                        if Task.isCancelled { break }
                        cont.yield(input)
                    }
                } catch { Self.log.error("input pump: \(error)") }
                cont.finish()
            }

            let analyzer = SpeechAnalyzer(modules: [transcriber])
            resultsTask = Task { [onUpdate] in
                var final = ""
                var volatile = ""
                for try await r in transcriber.results {
                    if r.isFinal { final += String(r.text.characters); volatile = "" }
                    else { volatile = String(r.text.characters) }
                    onUpdate(final + volatile)
                }
                return final + volatile
            }
            try await analyzer.start(inputSequence: stream)
            if !provider.captureSession.isRunning { provider.captureSession.startRunning() }

            self.transcriber = transcriber
            self.analyzer = analyzer
            self.provider = provider
            state = .recording
        } catch {
            teardown()
            throw error
        }
    }

    /// V5: always finalizes and returns whatever was recognized.
    func stop() async throws -> String {
        guard state == .recording, let analyzer, let resultsTask else { return "" }
        state = .finalizing
        provider?.captureSession.stopRunning()
        pumpTask?.cancel()
        inputContinuation?.finish()
        defer { teardown() }
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        return try await resultsTask.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func teardown() {
        provider?.captureSession.stopRunning()
        pumpTask?.cancel()
        inputContinuation?.finish()
        transcriber = nil; analyzer = nil; provider = nil
        inputContinuation = nil; pumpTask = nil; resultsTask = nil
        state = .idle
    }
}
