import Foundation

/// Collects timestamped segments from several sources, writes them chronologically (V10)
/// and incrementally (V9) to a Markdown file.
struct TranscriptWriter {
    struct Segment: Equatable, Sendable {
        var start: TimeInterval // seconds since session start
        var speaker: String
        var text: String
    }

    let url: URL
    let started: Date
    /// Segments arriving later than this many seconds after the newest one are assumed not to reorder anything.
    var reorderWindow: TimeInterval = 10

    private(set) var written: [Segment] = []
    private var pending: [Segment] = []

    init(url: URL, started: Date = Date()) throws {
        self.url = url
        self.started = started
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.header(start: started, end: nil).write(to: url, atomically: true, encoding: .utf8)
    }

    mutating func add(_ s: Segment) throws {
        guard !s.text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        pending.append(s)
        let newest = pending.map(\.start).max() ?? 0
        try flush(upTo: newest - reorderWindow)
    }

    /// Flushes everything and rewrites the file with end/duration + optional summary.
    mutating func finish(summary: String?, ended: Date = Date()) throws {
        try flush(upTo: .infinity)
        var out = Self.header(start: started, end: ended)
        out += written.map(Self.line).joined(separator: "\n") + "\n"
        if let summary, !summary.isEmpty { out += "\n## Zusammenfassung\n\n\(summary)\n" }
        try out.write(to: url, atomically: true, encoding: .utf8)
    }

    private mutating func flush(upTo limit: TimeInterval) throws {
        let ready = pending.filter { $0.start <= limit }.sorted { $0.start < $1.start }
        guard !ready.isEmpty else { return }
        pending.removeAll { $0.start <= limit }
        written += ready
        let h = try FileHandle(forWritingTo: url)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: Data((ready.map(Self.line).joined(separator: "\n") + "\n").utf8))
    }

    static func line(_ s: Segment) -> String { "[\(stamp(s.start))] \(s.speaker): \(s.text)" }

    static func stamp(_ t: TimeInterval) -> String {
        let x = max(0, Int(t.rounded()))
        return String(format: "%02d:%02d:%02d", x / 3600, x / 60 % 60, x % 60)
    }

    private static func header(start: Date, end: Date?) -> String {
        let iso = ISO8601DateFormatter()
        var h = "---\nstart: \(iso.string(from: start))\n"
        if let end {
            h += "end: \(iso.string(from: end))\nduration: \(stamp(end.timeIntervalSince(start)))\n"
        }
        return h + "---\n\n"
    }

    static func defaultURL(for date: Date = Date(), in dir: URL? = nil) -> URL {
        let base = dir ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("trace-mem")
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HH-mm"
        return base.appendingPathComponent(f.string(from: date) + ".md")
    }
}
