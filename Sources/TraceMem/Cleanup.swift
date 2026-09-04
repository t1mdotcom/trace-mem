import Foundation
import FoundationModels
import os

/// Post-processing of the raw transcript. V2: any failure → raw text. V7: implausible output → raw text.
enum Cleanup {
    private static let log = Logger(subsystem: "dev.theinemann.trace-mem", category: "cleanup")

    static let instructions = """
    Du korrigierst diktierten Text. Regeln:
    - Entferne Füllwörter (ähm, äh, also, halt, quasi, sozusagen) und Wortwiederholungen durch Versprecher.
    - Setze korrekte Interpunktion und Groß-/Kleinschreibung.
    - Gesprochene Befehle umsetzen: "neuer Absatz" → Absatzumbruch, "neue Zeile" → Zeilenumbruch, "Komma" → ",", "Punkt" → ".", "Fragezeichen" → "?".
    - Sprache beibehalten (Deutsch bleibt Deutsch, Englisch bleibt Englisch). Inhalt nicht verändern, nichts hinzufügen, nichts zusammenfassen.
    - Antworte ausschließlich mit dem korrigierten Text, ohne Anführungszeichen, ohne Erklärung.
    """

    enum Failure: Error, Equatable, CustomStringConvertible {
        case timeout, unavailable(String), process(String), implausible
        var description: String {
            switch self {
            case .timeout: "Timeout"
            case .unavailable(let why): why
            case .process(let msg): msg
            case .implausible: "Antwort unplausibel"
            }
        }
    }

    /// V7 rule. Pure, tested.
    static func validate(raw: String, output: String) -> Result<String, Failure> {
        let out = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !out.isEmpty, out.count <= max(raw.count * 3, 20) else { return .failure(.implausible) }
        return .success(out)
    }

    /// Never throws: returns cleaned text or `raw`, plus the failure reason if it fell back.
    static func run(_ raw: String, settings: Settings) async -> (text: String, failure: Failure?) {
        guard settings.provider != .none, !raw.isEmpty else { return (raw, nil) }
        do {
            let out = try await withTimeout(.milliseconds(settings.cleanupTimeoutMs)) {
                try await generate(raw, settings: settings)
            }
            switch validate(raw: raw, output: out) {
            case .success(let t): return (t, nil)
            case .failure(let f): return (raw, f)
            }
        } catch let f as Failure {
            log.warning("cleanup fallback: \(f.description)")
            return (raw, f)
        } catch {
            log.warning("cleanup fallback: \(error)")
            return (raw, .process(error.localizedDescription))
        }
    }

    static func withTimeout<T: Sendable>(_ d: Duration, _ op: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask { try await Task.sleep(for: d); throw Failure.timeout }
            let first = try await group.next()!
            group.cancelAll()
            return first
        }
    }

    private static func generate(_ raw: String, settings: Settings) async throws -> String {
        switch settings.provider {
        case .none: return raw
        case .apple:
            switch SystemLanguageModel.default.availability {
            case .available: break
            case .unavailable(.modelNotReady): throw Failure.unavailable("Apple-Intelligence-Modell lädt noch")
            case .unavailable(.appleIntelligenceNotEnabled): throw Failure.unavailable("Apple Intelligence in Systemeinstellungen aktivieren")
            case .unavailable(.deviceNotEligible): throw Failure.unavailable("Gerät unterstützt Apple Intelligence nicht")
            case .unavailable(let other): throw Failure.unavailable("Apple Intelligence: \(other)")
            }
            let session = LanguageModelSession(instructions: instructions)
            return try await session.respond(to: raw, options: GenerationOptions(temperature: 0.1)).content
        case .claude:
            let args = ["-p", "--output-format", "text", "--model", settings.model ?? "haiku", instructions]
            return try await shell("claude", args, stdin: raw)
        case .codex:
            var args = ["exec", "--quiet"]
            if let m = settings.model { args += ["--model", m] }
            args.append(instructions + "\n\nText:\n" + raw)
            return try await shell("codex", args, stdin: nil)
        }
    }

    /// Runs `tool` via the user's login shell PATH. Cancellation terminates the process.
    private static func shell(_ tool: String, _ args: [String], stdin input: String?) async throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = [tool] + args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":/opt/homebrew/bin:/usr/local/bin:\(NSHomeDirectory())/.local/bin"
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        if let input {
            let inPipe = Pipe()
            p.standardInput = inPipe
            try p.run()
            inPipe.fileHandleForWriting.write(Data(input.utf8))
            try inPipe.fileHandleForWriting.close()
        } else {
            p.standardInput = FileHandle.nullDevice
            try p.run()
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (c: CheckedContinuation<String, Error>) in
                p.terminationHandler = { proc in
                    let data = out.fileHandleForReading.readDataToEndOfFile()
                    if proc.terminationStatus == 0 {
                        c.resume(returning: String(decoding: data, as: UTF8.self))
                    } else {
                        let e = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                        c.resume(throwing: Failure.process("\(tool) exit \(proc.terminationStatus): \(e.prefix(120))"))
                    }
                }
            }
        } onCancel: { p.terminate() }
    }
}
