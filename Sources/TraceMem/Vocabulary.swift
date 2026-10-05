import Foundation

/// User vocabulary: project terms the on-device STT model doesn't know. `SpeechTranscriber` ignores
/// contextual strings, so correction happens on the transcript text (I.vocab match, V17). Pure, AppKit-free.
struct Vocabulary: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        var term: String
        /// Known misrecognitions, matched exactly (after normalization).
        var variants: [String] = []
    }

    var entries: [Entry] = []

    var terms: [String] { entries.map(\.term) }

    static let url = Settings.url.deletingLastPathComponent().appendingPathComponent("vocabulary.txt")

    static let template = """
    # trace-mem Wörterbuch
    # Ein Begriff pro Zeile, so geschrieben, wie er im Text stehen soll.
    # Getrennt oder leicht falsch erkannte Schreibweisen (z. B. "Clint View") werden automatisch ersetzt.
    # Hartnäckige Fehlerkennungen nach einem Doppelpunkt ergänzen, kommagetrennt:
    # Clintview: Clinvef, Klint wju

    """

    init(entries: [Entry] = []) { self.entries = entries }

    /// One term per line, `#` comments, optional `Term: variant, variant`.
    init(parsing text: String) {
        entries = text.split(whereSeparator: \.isNewline).compactMap { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#") else { return nil }
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let term = parts[0].trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty else { return nil }
            let variants = parts.count < 2 ? [] : parts[1].split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return Entry(term: term, variants: variants)
        }
    }

    /// Missing file → empty vocabulary. Any other read error throws (V18).
    static func load(from url: URL = Vocabulary.url) throws -> Vocabulary {
        do {
            return Vocabulary(parsing: try String(contentsOf: url, encoding: .utf8))
        } catch let e as CocoaError where e.code == .fileReadNoSuchFile {
            return Vocabulary()
        }
    }

    // MARK: matching

    private static let maxWindow = 4
    private static let minKeyLength = 3

    /// Levenshtein budget against the term key: long keys tolerate more noise, short ones only match exactly.
    private static func maxDistance(forKeyLength n: Int) -> Int {
        n >= 9 ? 2 : n >= 7 ? 1 : 0
    }

    /// Lowercased, diacritics folded, letters and digits only. "Clint-View" and "clintview" share a key.
    private static func key<S: StringProtocol>(_ s: S) -> [Character] {
        Array(String(s).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber })
    }

    private struct Target {
        let term: String
        /// Empty when the term itself is too short to match; variants may still map to it.
        let key: [Character]
        let variantKeys: Set<[Character]>
        let maxDistance: Int
    }

    private struct Match {
        let start: Int, count: Int, distance: Int, term: String
    }

    /// Replaces misrecognized spellings of known terms with the canonical term. Text without a match is returned unchanged.
    func apply(to text: String) -> String {
        let targets = entries.compactMap { e -> Target? in
            let key = Self.key(e.term)
            let variants = Set(e.variants.map { Self.key($0) }.filter { $0.count >= Self.minKeyLength })
            let termUsable = key.count >= Self.minKeyLength
            guard termUsable || !variants.isEmpty else { return nil }
            return Target(term: e.term, key: termUsable ? key : [], variantKeys: variants,
                          maxDistance: termUsable ? Self.maxDistance(forKeyLength: key.count) : 0)
        }
        guard !targets.isEmpty else { return text }

        let words = Self.wordRanges(in: text)
        let keys = words.map { Self.key(text[$0]) }
        var matches: [Match] = []
        var joined: [Character] = []
        for start in words.indices {
            joined.removeAll(keepingCapacity: true)
            for end in start..<min(start + Self.maxWindow, words.count) {
                // Windows only span plain spaces/hyphens, never punctuation or line breaks.
                if end > start, !Self.isJoiner(text[words[end - 1].upperBound..<words[end].lowerBound]) { break }
                joined += keys[end]
                guard joined.count >= Self.minKeyLength,
                      let (distance, term) = Self.bestMatch(for: joined, in: targets) else { continue }
                matches.append(Match(start: start, count: end - start + 1, distance: distance, term: term))
            }
        }
        guard !matches.isEmpty else { return text }

        // Lowest distance first, then longest window; overlapping later candidates lose.
        matches.sort { ($0.distance, -$0.count, $0.start) < ($1.distance, -$1.count, $1.start) }
        var taken = [Bool](repeating: false, count: words.count)
        var accepted: [Match] = []
        for m in matches where !taken[m.start..<m.start + m.count].contains(true) {
            for i in m.start..<m.start + m.count { taken[i] = true }
            accepted.append(m)
        }

        var out = ""
        var cursor = text.startIndex
        for m in accepted.sorted(by: { $0.start < $1.start }) {
            let range = words[m.start].lowerBound..<words[m.start + m.count - 1].upperBound
            out += text[cursor..<range.lowerBound]
            out += m.term
            cursor = range.upperBound
        }
        out += text[cursor...]
        return out
    }

    private static func bestMatch(for window: [Character], in targets: [Target]) -> (Int, String)? {
        var best: (Int, String)?
        for t in targets {
            let d: Int
            if window == t.key || t.variantKeys.contains(window) {
                d = 0
            } else if t.maxDistance > 0, abs(window.count - t.key.count) <= t.maxDistance,
                      !window.starts(with: t.key) { // term + suffix = inflected correct term, leave it
                d = levenshtein(window, t.key)
                guard d <= t.maxDistance else { continue }
            } else { continue }
            if best.map({ d < $0.0 }) ?? true { best = (d, t.term) }
        }
        return best
    }

    /// Both inputs non-empty: windows and fuzzy-matchable keys are ≥ `minKeyLength`.
    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        var prev = Array(0...b.count)
        var cur = prev
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&prev, &cur)
        }
        return prev[b.count]
    }

    private static func isJoiner(_ s: Substring) -> Bool {
        s.allSatisfy { $0 == "-" || ($0.isWhitespace && !$0.isNewline) }
    }

    /// Maximal runs of letters/digits.
    private static func wordRanges(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        var i = text.startIndex
        while i < text.endIndex {
            let isWord = text[i].isLetter || text[i].isNumber
            if isWord, start == nil { start = i }
            if !isWord, let s = start { ranges.append(s..<i); start = nil }
            i = text.index(after: i)
        }
        if let s = start { ranges.append(s..<text.endIndex) }
        return ranges
    }
}
