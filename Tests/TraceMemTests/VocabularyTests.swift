import Foundation
import Testing
@testable import TraceMem

private let clintview = Vocabulary(entries: [.init(term: "Clintview", variants: ["Clinvef", "Klint wju"])])

@Test func parsesTermsVariantsAndComments() {
    let v = Vocabulary(parsing: """
    # Kommentar
      Clintview :  Clinvef , Klint wju,
    
    Kubernetes
    : nur Varianten
    """)
    #expect(v.entries == [.init(term: "Clintview", variants: ["Clinvef", "Klint wju"]), .init(term: "Kubernetes")])
    // The template's example line must stay inactive until the user uncomments it.
    #expect(Vocabulary(parsing: Vocabulary.template).entries.isEmpty)
}

@Test(arguments: [
    ("Das Clint View Dashboard.", "Das Clintview Dashboard."),     // split by the recognizer
    ("Clint-View läuft", "Clintview läuft"),
    ("in clintview gestern", "in Clintview gestern"),              // canonical casing
    ("Klintview ist down", "Clintview ist down"),                 // fuzzy, distance 1
    ("Clint Vio läuft jetzt", "Clintview läuft jetzt"),           // fuzzy across words, distance 2
    ("Der Bug in Clinvef, endlich.", "Der Bug in Clintview, endlich."), // listed variant
    ("Klint-Wju geht", "Clintview geht"),                          // multi-word variant
    ("in Clint View gestern", "in Clintview gestern"),            // neighbour word not absorbed
])
func correctsMisrecognitions(input: String, expected: String) {
    #expect(clintview.apply(to: input) == expected)
}

@Test(arguments: [
    "Das klingt wie ein Plan.",
    "Clint Eastwood dreht wieder.",
    "Frag Clint, der weiß das.",
    "Alle Clintviews sind online.",  // inflected correct term
    "Erst Clint. View kam später.",   // windows never span punctuation
    "Clint\nView",                    // or line breaks
])
func leavesUnrelatedTextUntouched(input: String) {
    #expect(clintview.apply(to: input) == input)
}

@Test func shortTermsMatchOnlyExactly() {
    let v = Vocabulary(entries: [.init(term: "Docker"), .init(term: "C#", variants: ["C Sharp"])])
    #expect(v.apply(to: "Der Hocker wackelt") == "Der Hocker wackelt")
    #expect(v.apply(to: "Doc Ker Image bauen") == "Docker Image bauen")
    #expect(v.apply(to: "C ist alt, C Sharp nicht") == "C ist alt, C# nicht")
}

@Test func longestExactTermWins() {
    let v = Vocabulary(entries: [.init(term: "Claude"), .init(term: "Claude Code")])
    #expect(v.apply(to: "frag claude code und claude") == "frag Claude Code und Claude")
}

@Test func loadTreatsMissingFileAsEmptyButReportsUnreadable() throws {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("trace-mem-vocab-\(UUID()).txt")
    defer { try? FileManager.default.removeItem(at: tmp) }
    #expect(try Vocabulary.load(from: tmp) == Vocabulary())

    try "Clintview: Clinvef\n".write(to: tmp, atomically: true, encoding: .utf8)
    #expect(try Vocabulary.load(from: tmp).entries == [.init(term: "Clintview", variants: ["Clinvef"])])

    try Data([0xC3, 0x28, 0xFF]).write(to: tmp) // invalid UTF-8
    #expect(throws: (any Error).self) { try Vocabulary.load(from: tmp) }
}
