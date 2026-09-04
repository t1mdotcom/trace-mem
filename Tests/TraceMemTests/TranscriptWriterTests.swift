import Foundation
import Testing
@testable import TraceMem

@Test func writerOrdersAndFlushesIncrementally() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("tm-\(UUID()).md")
    var w = try TranscriptWriter(url: url, started: Date(timeIntervalSince1970: 0))
    w.reorderWindow = 5
    try w.add(.init(start: 3, speaker: "Andere", text: "zweiter"))
    try w.add(.init(start: 1, speaker: "Ich", text: "erster"))
    try w.add(.init(start: 20, speaker: "Ich", text: "spät")) // pushes 1 and 3 out of the window
    let mid = try String(contentsOf: url, encoding: .utf8)
    #expect(mid.contains("[00:00:01] Ich: erster\n[00:00:03] Andere: zweiter\n")) // V9 incremental, V10 ordered
    #expect(!mid.contains("spät"))

    try w.finish(summary: "Kurz.", ended: Date(timeIntervalSince1970: 65))
    let final = try String(contentsOf: url, encoding: .utf8)
    #expect(final.contains("duration: 00:01:05"))
    #expect(final.contains("[00:00:20] Ich: spät"))
    #expect(final.hasSuffix("## Zusammenfassung\n\nKurz.\n"))
    #expect(w.written.map(\.start) == [1, 3, 20])
}

@Test func stampFormat() {
    #expect(TranscriptWriter.stamp(3725) == "01:02:05")
    #expect(TranscriptWriter.defaultURL(for: Date(timeIntervalSince1970: 0), in: URL(fileURLWithPath: "/x")).lastPathComponent.hasSuffix(".md"))
}
