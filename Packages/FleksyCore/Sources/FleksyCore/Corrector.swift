import Foundation

/// Everything beyond the typed letters that should influence a correction.
public struct CorrectionContext: Sendable {
    /// What the user has typed before, and what usually follows the previous word.
    public var personal: PersonalPrior
    /// Where each letter of the typed word was actually tapped, in order. A nil entry
    /// (an accent picked from a popup, say) falls back to the discrete neighbour model,
    /// and the whole array is ignored unless it lines up with the word being corrected.
    public var touches: [TouchSample?]

    public init(personal: PersonalPrior = .none, touches: [TouchSample?] = []) {
        self.personal = personal
        self.touches = touches
    }
}

/// Dictionary-based autocorrection: weighted Damerau-Levenshtein distance combined
/// with word frequency, aware of diacritics and physical key adjacency.
public struct Corrector: Sendable {
    public struct Candidate: Equatable, Sendable {
        public let word: String
        public let cost: Double
        public let score: Double
        public let frequency: Double
    }

    public let lexicon: Lexicon
    let neighbours: [UInt32: Set<UInt32>]

    public var adjacentCost = 0.6
    public var diacriticCost = 0.15
    public var transposeCost = 0.8
    public var frequencyWeight = 0.35
    public var maxResults = 5
    public var exactMatchBonus = 1.0

    public init(lexicon: Lexicon, neighbourMap: [Character: Set<Character>]) {
        self.lexicon = lexicon
        var n: [UInt32: Set<UInt32>] = [:]
        for (k, v) in neighbourMap {
            guard let ks = k.unicodeScalars.first?.value else { continue }
            n[ks] = Set(v.compactMap { $0.unicodeScalars.first?.value })
        }
        neighbours = n
    }

    public init(lexicon: Lexicon) {
        self.init(lexicon: lexicon, neighbourMap: Layouts.neighbourMap(for: lexicon.language))
    }

    /// Maximum edit cost we accept as a correction for a typed word of this length.
    public func maxCost(forLength n: Int) -> Double {
        switch n {
        case ...2: return 0.5
        case 3: return 1.0
        case 4...5: return 1.4
        case 6...8: return 2.0
        default: return 2.6
        }
    }

    /// Ranked candidates for `typed`. The first one is the best correction.
    /// The typed word is not included unless it is a lexicon word.
    public func candidates(for typed: String, context: CorrectionContext = CorrectionContext()) -> [Candidate] {
        let lower = typed.lowercased()
        let a = Diacritics.scalars(lower)
        let af = a.map(Diacritics.fold)
        guard !a.isEmpty else { return [] }
        let n = a.count
        let limit = maxCost(forLength: n)
        let maxLenDelta = Int(limit.rounded(.up))

        // Prune: the candidate's first letter must be the typed first letter, its keyboard
        // neighbour, or the second typed letter (a transposition). Typos rarely break this.
        var allowedFirst: Set<UInt32> = [af[0]]
        if n > 1 { allowedFirst.insert(af[1]) }
        if let nb = neighbours[af[0]] { allowedFirst.formUnion(nb) }

        // Touch geometry only applies when there is one sample per typed letter; anything
        // else means the word and the taps have drifted apart and the letters are all we know.
        let touches: [[UInt32: Double]?] = context.touches.count == n
            ? context.touches.map { $0?.costsByScalar() }
            : []

        var buffer = DPBuffer(cols: n + maxLenDelta + 1)
        var results: [Candidate] = []
        scan(lexicon, a, af, allowedFirst: allowedFirst, limit: limit, maxLenDelta: maxLenDelta,
             context: context, touches: touches, into: &results, buffer: &buffer)
        // The user's own vocabulary is scanned too, so a word we ship no entry for can
        // still be offered once they have used it enough.
        if let personal = context.personal.vocabulary {
            scan(personal, a, af, allowedFirst: allowedFirst, limit: limit, maxLenDelta: maxLenDelta,
                 context: context, touches: touches, into: &results, buffer: &buffer)
        }
        return rank(results)
    }

    /// Adds every word of `lexicon` within `limit` of the typed scalars to `results`.
    private func scan(_ lexicon: Lexicon, _ a: [UInt32], _ af: [UInt32], allowedFirst: Set<UInt32>,
                      limit: Double, maxLenDelta: Int, context: CorrectionContext,
                      touches: [[UInt32: Double]?],
                      into results: inout [Candidate], buffer: inout DPBuffer) {
        let n = a.count
        lexicon.scalarStore.withUnsafeBufferPointer { store in
            lexicon.foldedStore.withUnsafeBufferPointer { folded in
                lexicon.lengthIndex.withUnsafeBufferPointer { lengths in
                    for len in max(1, n - maxLenDelta)...(n + maxLenDelta) {
                        guard let bucket = lexicon.lengthRanges[len] else { continue }
                        for slot in bucket {
                            let i = Int(lengths[slot])
                            let span = lexicon.span(i)
                            guard allowedFirst.contains(folded[span.lowerBound]) else { continue }
                            let cost = editCost(a, af, store, folded, span, touches: touches,
                                                limit: limit, buffer: &buffer)
                            guard cost <= limit else { continue }
                            let word = lexicon.word(at: i)
                            var score = -cost + frequencyWeight * Double(lexicon.logFrequencies[i])
                            if cost == 0 { score += exactMatchBonus }
                            score += context.personal.contextBoost(for: word)
                            results.append(Candidate(word: word, cost: cost, score: score,
                                                     frequency: lexicon.frequency(at: i)))
                        }
                    }
                }
            }
        }
    }

    /// Sorts by score and drops duplicates. A word can be reached through both the
    /// bundled list and the user's own vocabulary; the better-scoring reading wins,
    /// which is what makes a heavily used word outrank its dictionary frequency.
    private func rank(_ results: [Candidate]) -> [Candidate] {
        var best: [String: Candidate] = [:]
        best.reserveCapacity(results.count)
        for candidate in results {
            if let existing = best[candidate.word], existing.score >= candidate.score { continue }
            best[candidate.word] = candidate
        }
        // Ties are broken alphabetically so the order never depends on hash seeding.
        let sorted = best.values.sorted { $0.score == $1.score ? $0.word < $1.word : $0.score > $1.score }
        return Array(sorted.prefix(maxResults))
    }

    struct DPBuffer {
        var prev2: [Double]
        var prev: [Double]
        var cur: [Double]
        init(cols: Int) {
            prev2 = Array(repeating: 0, count: cols)
            prev = Array(repeating: 0, count: cols)
            cur = Array(repeating: 0, count: cols)
        }

        /// Widens the rows if a longer candidate turns up than the typed word implied.
        mutating func fit(_ cols: Int) {
            guard prev.count < cols else { return }
            prev2 = Array(repeating: 0, count: cols)
            prev = Array(repeating: 0, count: cols)
            cur = Array(repeating: 0, count: cols)
        }
    }

    /// What it costs to have meant `y` where `x` was typed. `touch`, when present, is
    /// where the finger actually landed, which supersedes the discrete neighbour table:
    /// a key it does not mention is one the finger was nowhere near.
    @inline(__always)
    func substitutionCost(_ x: UInt32, _ xf: UInt32, _ y: UInt32, _ yf: UInt32,
                          _ touch: [UInt32: Double]?) -> Double {
        if x == y { return 0 }
        if xf == yf { return diacriticCost }
        if let touch { return touch[yf] ?? 1 }
        if let n = neighbours[xf], n.contains(yf) { return adjacentCost }
        return 1
    }

    /// Weighted Damerau-Levenshtein between the typed scalars and the lexicon word
    /// occupying `span` of the flat stores, with an early exit once every cell in a row
    /// exceeds `limit`.
    func editCost(_ a: [UInt32], _ af: [UInt32],
                  _ store: UnsafeBufferPointer<UInt32>, _ foldedStore: UnsafeBufferPointer<UInt32>,
                  _ span: Range<Int>, touches: [[UInt32: Double]?] = [],
                  limit: Double, buffer: inout DPBuffer) -> Double {
        let n = a.count, m = span.count
        if n == 0 { return Double(m) }
        if m == 0 { return Double(n) }
        buffer.fit(m + 1)
        let base = span.lowerBound
        for j in 0...m { buffer.prev[j] = Double(j) }
        for i in 1...n {
            buffer.cur[0] = Double(i)
            var rowMin = buffer.cur[0]
            for j in 1...m {
                let bj = store[base + j - 1], bfj = foldedStore[base + j - 1]
                let touch = i <= touches.count ? touches[i - 1] : nil
                let sub = buffer.prev[j - 1] + substitutionCost(a[i - 1], af[i - 1], bj, bfj, touch)
                let del = buffer.prev[j] + 1
                let ins = buffer.cur[j - 1] + 1
                var best = min(sub, del, ins)
                if i > 1, j > 1, af[i - 1] == foldedStore[base + j - 2], af[i - 2] == bfj {
                    best = min(best, buffer.prev2[j - 2] + transposeCost)
                }
                buffer.cur[j] = best
                if best < rowMin { rowMin = best }
            }
            if rowMin > limit { return rowMin }
            swap(&buffer.prev2, &buffer.prev)
            swap(&buffer.prev, &buffer.cur)
        }
        return buffer.prev[m]
    }
}
