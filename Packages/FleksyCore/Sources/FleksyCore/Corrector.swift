import Foundation

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
    public func candidates(for typed: String) -> [Candidate] {
        let lower = typed.lowercased()
        let a = Diacritics.scalars(lower)
        let af = a.map(Diacritics.fold)
        guard !a.isEmpty else { return [] }
        let n = a.count
        let limit = maxCost(forLength: n)
        let maxLenDelta = Int(limit.rounded(.up))

        var results: [Candidate] = []
        var buffer = DPBuffer(rows: n + 1, cols: n + maxLenDelta + 1)
        for len in max(1, n - maxLenDelta)...(n + maxLenDelta) {
            guard let indices = lexicon.byLength[len] else { continue }
            for i in indices {
                let e = lexicon.entries[i]
                let cost = editCost(a, af, e.scalars, e.folded, limit: limit, buffer: &buffer)
                guard cost <= limit else { continue }
                var score = -cost + frequencyWeight * e.logFrequency
                if cost == 0 { score += exactMatchBonus }
                results.append(Candidate(word: e.word, cost: cost, score: score, frequency: e.frequency))
            }
        }
        results.sort { $0.score > $1.score }
        return Array(results.prefix(maxResults))
    }

    struct DPBuffer {
        var prev2: [Double]
        var prev: [Double]
        var cur: [Double]
        init(rows: Int, cols: Int) {
            prev2 = Array(repeating: 0, count: cols)
            prev = Array(repeating: 0, count: cols)
            cur = Array(repeating: 0, count: cols)
        }
    }

    @inline(__always)
    func substitutionCost(_ x: UInt32, _ xf: UInt32, _ y: UInt32, _ yf: UInt32) -> Double {
        if x == y { return 0 }
        if xf == yf { return diacriticCost }
        if let n = neighbours[xf], n.contains(yf) { return adjacentCost }
        return 1
    }

    /// Weighted Damerau-Levenshtein with early exit once every cell in a row exceeds `limit`.
    func editCost(_ a: [UInt32], _ af: [UInt32], _ b: [UInt32], _ bf: [UInt32], limit: Double, buffer: inout DPBuffer) -> Double {
        let n = a.count, m = b.count
        if n == 0 { return Double(m) }
        if m == 0 { return Double(n) }
        for j in 0...m { buffer.prev[j] = Double(j) }
        for i in 1...n {
            buffer.cur[0] = Double(i)
            var rowMin = buffer.cur[0]
            for j in 1...m {
                let sub = buffer.prev[j - 1] + substitutionCost(a[i - 1], af[i - 1], b[j - 1], bf[j - 1])
                let del = buffer.prev[j] + 1
                let ins = buffer.cur[j - 1] + 1
                var best = min(sub, del, ins)
                if i > 1, j > 1, af[i - 1] == bf[j - 2], af[i - 2] == bf[j - 1] {
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
