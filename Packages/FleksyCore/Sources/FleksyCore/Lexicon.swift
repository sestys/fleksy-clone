import Foundation

/// A frequency-ranked word list for one language.
///
/// The corrector runs edit distance over the whole list on every commit, so words are
/// stored as decoded scalars rather than Strings, in flat buffers shared by every word
/// rather than a pair of arrays per word.
///
/// Two things drive the design, both of them memory rather than speed. A keyboard
/// extension is killed without warning somewhere north of ~50 MB, and two loaded
/// languages used to account for 33 MB of that.
///
/// 1. No per-word allocations. 47k words means 47k spans of two shared buffers, not
///    94k separate heap arrays each with its own allocator header.
/// 2. No large intermediates while parsing. What the allocator touches during `init`
///    never comes back to the OS, so building an array of 47k Strings costs the same
///    as keeping it. The parser therefore streams line by line straight into the
///    buffers, and sorting happens on an index permutation instead of on the words.
///
/// Words are stored lowercased. `sorted` orders them by scalar value so membership and
/// prefix completion are a binary search, with no side index to pay for.
public final class Lexicon: @unchecked Sendable {
    public let language: Language

    /// Every word's scalars end to end; word `i` occupies `offsets[i]..<offsets[i + 1]`.
    let scalarStore: [UInt32]
    /// The same span layout as `scalarStore`, diacritics folded away.
    let foldedStore: [UInt32]
    let offsets: [Int32]
    /// log10 of the corpus frequency. The raw frequency is derived from this rather than
    /// stored twice; it is only ever used for ranking comparisons.
    let logFrequencies: [Float]

    /// Word indices in alphabetical (scalar) order, duplicates removed. This is the set
    /// of live words: `scalarStore` may still hold spans that lost a duplicate contest.
    let sorted: [Int32]
    /// Live word indices grouped by scalar count: length `n` occupies `lengthRanges[n]`.
    let lengthIndex: [Int32]
    let lengthRanges: [Int: Range<Int>]

    // MARK: - Construction

    /// Accumulates words into the flat buffers. Holds no Strings.
    struct Builder {
        var scalarStore: [UInt32] = []
        var foldedStore: [UInt32] = []
        var offsets: [Int32] = [0]
        var logFrequencies: [Float] = []

        mutating func reserve(words: Int, scalars: Int) {
            scalarStore.reserveCapacity(scalars)
            foldedStore.reserveCapacity(scalars)
            offsets.reserveCapacity(words + 1)
            logFrequencies.reserveCapacity(words)
        }

        /// Appends `word`, which must already be lowercased. Rejects non-words.
        mutating func add<S: StringProtocol>(_ word: S, frequency: Double) {
            var length = 0
            for s in word.unicodeScalars {
                guard Lexicon.isWordScalar(s) else {
                    scalarStore.removeLast(length)
                    foldedStore.removeLast(length)
                    return
                }
                scalarStore.append(s.value)
                foldedStore.append(Diacritics.fold(s.value))
                length += 1
            }
            guard length > 0 else { return }
            offsets.append(Int32(scalarStore.count))
            logFrequencies.append(Float(log10(max(frequency, 1))))
        }
    }

    init(language: Language, builder: Builder) {
        self.language = language
        scalarStore = builder.scalarStore
        foldedStore = builder.foldedStore
        offsets = builder.offsets
        logFrequencies = builder.logFrequencies
        let parsed = logFrequencies.count

        // Sort indices, not words: 47k Int32 of scratch instead of 47k Strings.
        var order = [Int32](0..<Int32(parsed))
        let stores = scalarStore
        let bounds = offsets
        order.sort { lhs, rhs in
            let l = Int(bounds[Int(lhs)])..<Int(bounds[Int(lhs) + 1])
            let r = Int(bounds[Int(rhs)])..<Int(bounds[Int(rhs) + 1])
            var i = l.lowerBound, j = r.lowerBound
            while i < l.upperBound, j < r.upperBound {
                if stores[i] != stores[j] { return stores[i] < stores[j] }
                i += 1; j += 1
            }
            if l.count != r.count { return l.count < r.count }
            // Equal words: the earlier one wins, and the source lists are ordered by
            // descending frequency, so that keeps the most frequent spelling.
            return lhs < rhs
        }

        // Drop adjacent duplicates, which are now neighbours.
        var live: [Int32] = []
        live.reserveCapacity(parsed)
        for idx in order {
            if let last = live.last, Lexicon.sameWord(Int(last), Int(idx), stores, bounds) { continue }
            live.append(idx)
        }
        sorted = live

        // Counting sort by length: one pass to size the buckets, one to fill them.
        var counts: [Int: Int] = [:]
        for idx in live { counts[Int(bounds[Int(idx) + 1] - bounds[Int(idx)]), default: 0] += 1 }
        var ranges: [Int: Range<Int>] = [:]
        var cursor = 0
        for length in counts.keys.sorted() {
            ranges[length] = cursor..<(cursor + counts[length]!)
            cursor += counts[length]!
        }
        var index = [Int32](repeating: 0, count: live.count)
        var fill = ranges.mapValues { $0.lowerBound }
        for idx in live {
            let length = Int(bounds[Int(idx) + 1] - bounds[Int(idx)])
            index[fill[length]!] = idx
            fill[length]! += 1
        }
        lengthIndex = index
        lengthRanges = ranges
    }

    public convenience init(language: Language, words: [(String, Double)]) {
        var builder = Builder()
        builder.reserve(words: words.count, scalars: words.count * 8)
        for (raw, frequency) in words { builder.add(raw.lowercased(), frequency: frequency) }
        self.init(language: language, builder: builder)
    }

    /// Parses the "word frequency" line format of the FrequencyWords lists.
    ///
    /// Lines are consumed one at a time. Materialising them as an array first would cost
    /// more in allocator high-water than the finished lexicon does.
    public convenience init(language: Language, text: String, limit: Int = .max) {
        var builder = Builder()
        // ~12 bytes of text per word, ~8 scalars per word: enough to avoid regrowth.
        let estimate = min(limit, max(1024, text.utf8.count / 12))
        builder.reserve(words: estimate, scalars: estimate * 8)
        var added = 0
        text.enumerateLines { line, stop in
            guard added < limit else { stop = true; return }
            let parts = line.split(separator: " ", maxSplits: 1)
            guard let word = parts.first else { return }
            let frequency = parts.count > 1 ? Double(parts[1]) ?? 1 : 1
            builder.add(word.lowercased(), frequency: frequency)
            added += 1
        }
        self.init(language: language, builder: builder)
    }

    /// Letters, plus the apostrophes that appear inside contractions.
    @inline(__always)
    static func isWordScalar(_ s: Unicode.Scalar) -> Bool {
        if s == "'" || s == "’" { return true }
        return CharacterSet.letters.contains(s)
    }

    private static func sameWord(_ a: Int, _ b: Int, _ store: [UInt32], _ offsets: [Int32]) -> Bool {
        let la = Int(offsets[a + 1] - offsets[a]), lb = Int(offsets[b + 1] - offsets[b])
        guard la == lb else { return false }
        let base = Int(offsets[a]), other = Int(offsets[b])
        for k in 0..<la where store[base + k] != store[other + k] { return false }
        return true
    }

    // MARK: - Flat access

    public var count: Int { sorted.count }

    /// The span of `scalarStore` / `foldedStore` holding word `i`.
    @inline(__always)
    func span(_ i: Int) -> Range<Int> { Int(offsets[i])..<Int(offsets[i + 1]) }

    /// Rebuilds word `i` as a String. Only worth doing for words we are about to show.
    public func word(at i: Int) -> String {
        var view = String.UnicodeScalarView()
        for value in scalarStore[span(i)] {
            view.append(Unicode.Scalar(value) ?? " ")
        }
        return String(view)
    }

    public func frequency(at i: Int) -> Double { pow(10, Double(logFrequencies[i])) }

    /// All live words in alphabetical order. Rebuilds every String, so this is for tests
    /// and diagnostics, not for the typing path.
    public var allWords: [String] { sorted.map { word(at: Int($0)) } }

    /// Bytes held by the flat buffers. This is the whole of a lexicon's memory: there
    /// are deliberately no per-word allocations, so a real list should sit near 4 MB
    /// rather than the ~17 MB an array-per-word layout cost.
    public var storageBytes: Int {
        (scalarStore.capacity + foldedStore.capacity) * MemoryLayout<UInt32>.stride
            + (offsets.capacity + sorted.capacity + lengthIndex.capacity) * MemoryLayout<Int32>.stride
            + logFrequencies.capacity * MemoryLayout<Float>.stride
    }

    // MARK: - Lookup

    /// Orders word `i` against `query`: negative if the word sorts first, 0 if equal.
    /// `prefixOnly` stops at the end of the query, so a longer word compares equal.
    private func compare(_ i: Int, _ query: [UInt32], prefixOnly: Bool) -> Int {
        let s = span(i)
        let n = min(s.count, query.count)
        for k in 0..<n {
            let a = scalarStore[s.lowerBound + k], b = query[k]
            if a != b { return a < b ? -1 : 1 }
        }
        if prefixOnly, s.count >= query.count { return 0 }
        if s.count == query.count { return 0 }
        return s.count < query.count ? -1 : 1
    }

    /// Position in `sorted` of the first word at or after `query`.
    private func lowerBound(_ query: [UInt32], prefixOnly: Bool) -> Int {
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if compare(Int(sorted[mid]), query, prefixOnly: prefixOnly) < 0 { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    /// Index into the flat stores for `word`, or nil.
    func indexOf(_ word: String) -> Int? {
        let query = Diacritics.scalars(word.lowercased())
        guard !query.isEmpty else { return nil }
        let at = lowerBound(query, prefixOnly: false)
        guard at < sorted.count else { return nil }
        let i = Int(sorted[at])
        return compare(i, query, prefixOnly: false) == 0 ? i : nil
    }

    public func contains(_ word: String) -> Bool { indexOf(word) != nil }

    public func frequency(of word: String) -> Double {
        guard let i = indexOf(word) else { return 0 }
        return frequency(at: i)
    }

    /// Most frequent words starting with `prefix` (case-insensitive), excluding the prefix itself.
    public func completions(for prefix: String, limit: Int = 3) -> [String] {
        let query = Diacritics.scalars(prefix.lowercased())
        guard !query.isEmpty else { return [] }
        var best: [(Int, Float)] = []
        var at = lowerBound(query, prefixOnly: true)
        let start = at
        while at < sorted.count {
            let i = Int(sorted[at])
            guard compare(i, query, prefixOnly: true) == 0 else { break }
            if span(i).count > query.count { best.append((i, logFrequencies[i])) }
            at += 1
            if at - start > 5000 { break }
        }
        best.sort { $0.1 > $1.1 }
        return best.prefix(limit).map { word(at: $0.0) }
    }
}
