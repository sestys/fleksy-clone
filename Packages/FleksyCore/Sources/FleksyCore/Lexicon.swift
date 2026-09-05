import Foundation

/// A frequency-ranked word list for one language.
///
/// Words are stored lowercased with precomputed scalar arrays so the corrector can
/// run edit-distance over the whole list quickly. Words are also kept sorted so
/// prefix completions are a binary search away.
public final class Lexicon: @unchecked Sendable {
    public struct Entry: Sendable {
        public let word: String
        public let scalars: [UInt32]
        public let folded: [UInt32]
        public let frequency: Double
        public let logFrequency: Double
    }

    public let language: Language
    /// Entries sorted alphabetically by `word`.
    public let entries: [Entry]
    /// Entries grouped by scalar count for fast length-window filtering.
    let byLength: [Int: [Int]]
    let index: [String: Int]

    public init(language: Language, words: [(String, Double)]) {
        self.language = language
        var seen = Set<String>()
        var list: [Entry] = []
        list.reserveCapacity(words.count)
        for (raw, freq) in words {
            let w = raw.lowercased()
            guard !w.isEmpty, !seen.contains(w), Lexicon.isWordLike(w) else { continue }
            seen.insert(w)
            let sc = Diacritics.scalars(w)
            list.append(Entry(word: w, scalars: sc, folded: sc.map(Diacritics.fold), frequency: freq, logFrequency: log10(max(freq, 1))))
        }
        list.sort { $0.word < $1.word }
        entries = list
        var byLength: [Int: [Int]] = [:]
        var index: [String: Int] = [:]
        for (i, e) in list.enumerated() {
            byLength[e.scalars.count, default: []].append(i)
            index[e.word] = i
        }
        self.byLength = byLength
        self.index = index
    }

    /// Parses the "word frequency" line format of the FrequencyWords lists.
    public convenience init(language: Language, text: String, limit: Int = .max) {
        var words: [(String, Double)] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = line.split(separator: " ", maxSplits: 1)
            guard let w = parts.first else { continue }
            let f = parts.count > 1 ? Double(parts[1]) ?? 1 : 1
            words.append((String(w), f))
            if words.count >= limit { break }
        }
        self.init(language: language, words: words)
    }

    static func isWordLike(_ w: String) -> Bool {
        for s in w.unicodeScalars {
            if s == "'" || s == "’" { continue }
            if !CharacterSet.letters.contains(s) { return false }
        }
        return true
    }

    public var count: Int { entries.count }

    public func contains(_ word: String) -> Bool {
        index[word.lowercased()] != nil
    }

    public func frequency(of word: String) -> Double {
        guard let i = index[word.lowercased()] else { return 0 }
        return entries[i].frequency
    }

    /// Most frequent words starting with `prefix` (case-insensitive), excluding the prefix itself.
    public func completions(for prefix: String, limit: Int = 3) -> [String] {
        let p = prefix.lowercased()
        guard !p.isEmpty else { return [] }
        // Binary search for the first entry >= prefix.
        var lo = 0, hi = entries.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if entries[mid].word < p { lo = mid + 1 } else { hi = mid }
        }
        var best: [(String, Double)] = []
        var i = lo
        while i < entries.count, entries[i].word.hasPrefix(p) {
            let e = entries[i]
            if e.word != p {
                best.append((e.word, e.frequency))
            }
            i += 1
            if i - lo > 5000 { break }
        }
        best.sort { $0.1 > $1.1 }
        return best.prefix(limit).map { $0.0 }
    }
}
