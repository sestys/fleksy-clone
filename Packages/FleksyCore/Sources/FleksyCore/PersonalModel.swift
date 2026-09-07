import Foundation

/// What one language's typing history looks like on disk.
public struct PersonalCounts: Codable, Equatable, Sendable {
    /// Decayed count of every word the user has committed.
    public var unigrams: [String: Float] = [:]
    /// Decayed counts of what followed what, as previous word -> next word -> count.
    /// Nested rather than flat so looking up one word's successors is a single hash
    /// lookup: this runs on every committed word, and a scan over every pair the user
    /// has ever typed would be felt on the space bar.
    public var bigrams: [String: [String: Float]] = [:]
    /// Words taught deliberately with the learn gesture. These are never corrected away
    /// and are offered immediately, without waiting to clear `minimumUses`.
    public var learned: Set<String> = []
    /// When the counts were last aged. Decay is applied lazily from here.
    public var decayedAt = Date()

    public init() {}

    public var isEmpty: Bool { unigrams.isEmpty && bigrams.isEmpty && learned.isEmpty }

    /// How often `word` has followed `previous`.
    public func pairCount(_ previous: String, _ word: String) -> Float {
        bigrams[previous.lowercased()]?[word.lowercased()] ?? 0
    }

    var pairTotal: Int { bigrams.values.reduce(0) { $0 + $1.count } }
}

/// Persists the counts between keyboard sessions.
public protocol PersonalStore: AnyObject {
    func load() -> [Language: PersonalCounts]
    func save(_ counts: [Language: PersonalCounts])
}

public struct PersonalModelSettings: Equatable, Sendable {
    /// What one personal use of a word is worth in corpus occurrences. The bundled lists
    /// count in the millions, so a bare count would never outrank them; this puts a word
    /// you have typed a handful of times on a par with a moderately common one.
    public var scale: Double = 4000
    /// How often a word must be used before it is offered as a candidate. Two means a
    /// one-off typo can be recorded without ever being suggested back to you.
    public var minimumUses: Float = 2
    /// Counts halve after this long, so old habits fade instead of accumulating forever.
    public var halfLifeDays: Double = 60
    /// Counts below this are dropped entirely when decay runs.
    public var pruneBelow: Float = 0.3
    public var maxWords = 3000
    public var maxPairs = 6000
    /// Weight of the "you have written this pair before" term in a candidate's score.
    public var contextWeight: Double = 0.8
    public init() {}
}

/// A read-only view of the personal model, scoped to one language and one preceding
/// word, in the form the corrector consumes.
public struct PersonalPrior: Sendable {
    /// Personal vocabulary, scanned alongside the main lexicon so that words the user
    /// invented can be offered as corrections at all.
    public let vocabulary: Lexicon?
    /// Decayed counts of `previous -> candidate`, already scoped to the previous word.
    let successors: [String: Float]
    /// Decayed counts of the candidate on its own.
    let unigrams: [String: Float]
    public let learned: Set<String>
    let contextWeight: Double
    let scale: Double

    public static let none = PersonalPrior(vocabulary: nil, successors: [:], unigrams: [:],
                                           learned: [], contextWeight: 0, scale: 1)

    /// Extra score for `word` from having followed the current context before.
    /// Runs per candidate per keystroke, so the no-context case must cost nothing.
    func contextBoost(for word: String) -> Double {
        if successors.isEmpty { return 0 }
        guard let count = successors[word.lowercased()], count > 0 else { return 0 }
        return contextWeight * log10(1 + Double(count))
    }

    /// How often the user has typed `word`, expressed on the corpus frequency scale so
    /// it can be compared with a lexicon frequency.
    public func personalFrequency(of word: String) -> Double {
        guard let count = unigrams[word.lowercased()], count > 0 else { return 0 }
        return Double(count) * scale
    }

    public func isLearned(_ word: String) -> Bool { learned.contains(word.lowercased()) }
}

/// Tracks the words and word pairs the user actually types, and offers them back.
///
/// This is the part of the keyboard that gets to know you: it needs no shipped data, it
/// works in a language we have no dictionary for, and it is the only mechanism by which
/// a word you invented can ever be suggested. Counts decay so that what you wrote last
/// year stops outvoting what you write today.
public final class PersonalModel: @unchecked Sendable {
    public var settings: PersonalModelSettings
    private let store: PersonalStore?
    private var counts: [Language: PersonalCounts]
    private var vocabularies: [Language: Lexicon] = [:]
    private var unsaved = 0
    /// Commits between writes. Keyboards are killed without notice, so this trades a
    /// little durability for not touching the disk on every space bar.
    public var saveEvery = 8

    public init(store: PersonalStore? = nil, settings: PersonalModelSettings = PersonalModelSettings()) {
        self.store = store
        self.settings = settings
        counts = store?.load() ?? [:]
        decayAll()
    }

    // MARK: - Recording

    /// Records that the user committed `word`, optionally after `previous`.
    public func note(_ word: String, after previous: String?, language: Language) {
        adjust(word, after: previous, language: language, by: 1)
        unsaved += 1
        if unsaved >= saveEvery { flush() }
    }

    /// Undoes a `note`, for when a committed word is swapped for one of its alternatives.
    public func unnote(_ word: String, after previous: String?, language: Language) {
        adjust(word, after: previous, language: language, by: -1)
    }

    private func adjust(_ word: String, after previous: String?, language: Language, by delta: Float) {
        let w = word.lowercased()
        guard !w.isEmpty, w.unicodeScalars.allSatisfy(Lexicon.isWordScalar) else { return }
        var c = counts[language] ?? PersonalCounts()
        let was = c.unigrams[w] ?? 0
        let now = max(0, was + delta)
        if now == 0 { c.unigrams.removeValue(forKey: w) } else { c.unigrams[w] = now }
        if let previous = previous?.lowercased(), !previous.isEmpty {
            var successors = c.bigrams[previous] ?? [:]
            let pair = max(0, (successors[w] ?? 0) + delta)
            if pair == 0 { successors.removeValue(forKey: w) } else { successors[w] = pair }
            if successors.isEmpty { c.bigrams.removeValue(forKey: previous) } else { c.bigrams[previous] = successors }
        }
        counts[language] = c
        // Only rebuilding when the word crosses the offer threshold keeps the common
        // case (typing a word you already use) free.
        if (was >= settings.minimumUses) != (now >= settings.minimumUses) {
            vocabularies[language] = nil
        }
    }

    // MARK: - Explicit learning

    public func isLearned(_ word: String, language: Language) -> Bool {
        counts[language]?.learned.contains(word.lowercased()) ?? false
    }

    public func learn(_ word: String, language: Language) {
        let w = word.lowercased()
        guard !w.isEmpty else { return }
        var c = counts[language] ?? PersonalCounts()
        guard c.learned.insert(w).inserted else { return }
        counts[language] = c
        vocabularies[language] = nil
        flush()
    }

    public func forget(_ word: String, language: Language) {
        let w = word.lowercased()
        guard var c = counts[language], c.learned.remove(w) != nil else { return }
        counts[language] = c
        vocabularies[language] = nil
        flush()
    }

    // MARK: - Reading

    /// The prior for correcting a word that follows `previous`.
    public func prior(for language: Language, previous: String?) -> PersonalPrior {
        let c = counts[language] ?? PersonalCounts()
        let successors = previous.flatMap { c.bigrams[$0.lowercased()] } ?? [:]
        return PersonalPrior(vocabulary: vocabulary(for: language), successors: successors,
                             unigrams: c.unigrams, learned: c.learned,
                             contextWeight: settings.contextWeight, scale: settings.scale)
    }

    /// Words worth offering: everything used often enough, plus everything taught.
    func vocabulary(for language: Language) -> Lexicon? {
        if let cached = vocabularies[language] { return cached }
        guard let c = counts[language] else { return nil }
        var words: [(String, Double)] = []
        for (word, count) in c.unigrams where count >= settings.minimumUses {
            words.append((word, Double(count) * settings.scale))
        }
        for word in c.learned where c.unigrams[word] ?? 0 < settings.minimumUses {
            words.append((word, settings.minimumUses > 0 ? Double(settings.minimumUses) * settings.scale : settings.scale))
        }
        guard !words.isEmpty else { return nil }
        let lexicon = Lexicon(language: language, words: words)
        vocabularies[language] = lexicon
        return lexicon
    }

    public func counts(for language: Language) -> PersonalCounts { counts[language] ?? PersonalCounts() }

    /// How many words the keyboard has picked up from the user and would offer back.
    /// This is the number worth showing them, not the raw count of everything recorded.
    public func adoptedWordCount() -> Int {
        Language.allCases.reduce(0) { $0 + (vocabulary(for: $1)?.count ?? 0) }
    }

    /// Forgets everything: both the counts and the explicitly taught words.
    public func reset() {
        counts = [:]
        vocabularies = [:]
        flush()
    }

    // MARK: - Ageing and persistence

    /// Halves counts every `halfLifeDays` and drops what falls below the floor.
    private func decayAll() {
        let now = Date()
        for (language, var c) in counts {
            let days = now.timeIntervalSince(c.decayedAt) / 86_400
            guard days >= 1 else { continue }
            let factor = Float(pow(0.5, days / settings.halfLifeDays))
            c.unigrams = c.unigrams.compactMapValues { v in
                let scaled = v * factor
                return scaled >= settings.pruneBelow ? scaled : nil
            }
            c.bigrams = c.bigrams.compactMapValues { successors in
                let scaled = successors.compactMapValues { v in
                    let aged = v * factor
                    return aged >= settings.pruneBelow ? aged : nil
                }
                return scaled.isEmpty ? nil : scaled
            }
            c.decayedAt = now
            counts[language] = trim(c)
            vocabularies[language] = nil
        }
    }

    /// Caps the stores so a long-lived keyboard cannot grow without bound.
    private func trim(_ counts: PersonalCounts) -> PersonalCounts {
        var c = counts
        if c.unigrams.count > settings.maxWords {
            let keep = c.unigrams.sorted { $0.value > $1.value }.prefix(settings.maxWords)
            c.unigrams = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if c.pairTotal > settings.maxPairs {
            let flat = c.bigrams.flatMap { previous, successors in
                successors.map { (previous, $0.key, $0.value) }
            }
            var kept: [String: [String: Float]] = [:]
            for (previous, word, count) in flat.sorted(by: { $0.2 > $1.2 }).prefix(settings.maxPairs) {
                kept[previous, default: [:]][word] = count
            }
            c.bigrams = kept
        }
        return c
    }

    /// Writes the counts out. Cheap to call: it is a no-op with no store attached.
    public func flush() {
        unsaved = 0
        guard let store else { return }
        for (language, c) in counts where c.unigrams.count > settings.maxWords || c.pairTotal > settings.maxPairs {
            counts[language] = trim(c)
            vocabularies[language] = nil
        }
        store.save(counts)
    }

    /// Merges words learned by an earlier version that only kept a flat allow-list.
    public func adoptLegacyLearnedWords(_ words: [(String, Language)]) {
        var changed = false
        for (word, language) in words {
            var c = counts[language] ?? PersonalCounts()
            if c.learned.insert(word.lowercased()).inserted {
                counts[language] = c
                vocabularies[language] = nil
                changed = true
            }
        }
        if changed { flush() }
    }
}
