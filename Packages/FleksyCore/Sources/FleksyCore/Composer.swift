import Foundation

/// The text field the keyboard edits. Mirrors the parts of UITextDocumentProxy we need.
public protocol TextDocument: AnyObject {
    var textBeforeCursor: String { get }
    var textAfterCursor: String { get }
    func insert(_ text: String)
    func deleteBackward(_ count: Int)
}

public enum ShiftState: Equatable, Sendable {
    case off, on, locked
}

/// High-level input events produced by the keyboard view.
public enum InputEvent: Equatable, Sendable {
    case character(String)
    case space
    case backspace
    case enter
    case shiftTap
    case shiftDoubleTap
    case swipe(SwipeDirection)
    case selectCandidate(Int)
    case switchLanguage
    case contextChanged
}

public struct CandidateItem: Equatable, Sendable {
    public let text: String
    public let isSelected: Bool
    public init(text: String, isSelected: Bool) { self.text = text; self.isSelected = isSelected }
}

public struct ComposerSettings: Equatable, Sendable {
    public var autocorrect = true
    public var autoCapitalize = true
    public var doubleSpacePeriod = true
    public var czechQwertz = true
    /// Swipe down picks the next suggestion and swipe up walks back towards the word
    /// you typed. Set false for the original Fleksy direction (up = next).
    public var swipeDownForNext = true
    public init() {}
}

/// Provides lexicons lazily so the keyboard can load them off the main thread.
public protocol LexiconProvider: AnyObject {
    func lexicon(for language: Language) -> Lexicon?
}

public final class InMemoryLexicons: LexiconProvider {
    var map: [Language: Lexicon]
    public init(_ lexicons: [Lexicon]) {
        map = Dictionary(uniqueKeysWithValues: lexicons.map { ($0.language, $0) })
    }
    public func lexicon(for language: Language) -> Lexicon? { map[language] }
}

/// The single place that mutates text. Implements the Fleksy editing model:
/// autocorrect on commit, swipe up/down to swap the committed word, swipe left to
/// delete a word, swipe right for space and double swipe for a period.
public final class Composer {
    /// A committed word and its alternatives. For a corrected word the options are
    /// `[typed, correction, alternatives...]` so the typed word is always the leftmost item.
    struct Commit {
        var options: [String]
        var index: Int
        var trailing: String
        /// The word exactly as typed, before any correction.
        var typed: String
        /// True when autocorrect replaced the typed word (the typed word is options[0]).
        var corrected: Bool
        /// The word this one followed, for the personal bigram counts. Swapping the
        /// committed word has to move the pair count off the old word and onto the new.
        var previous: String?
        var current: String { options[index] }
    }

    /// Marks offered after a double space, in swipe-up order.
    public static let punctuationCycle = [".", ",", "!", "?", ";", ":"]

    struct PunctuationRun {
        var index: Int
        var count: Int
        var mark: String { Composer.punctuationCycle[index] }
        var text: String { String(repeating: mark, count: count) + " " }
    }

    public let document: TextDocument
    public var settings: ComposerSettings
    public private(set) var languages: [Language]
    public private(set) var language: Language
    public private(set) var shift: ShiftState = .off
    public private(set) var candidates: [CandidateItem] = []
    /// Short status shown in the suggestion bar after an action (e.g. "learned").
    public private(set) var notice: String?
    public var onLanguageChange: ((Language) -> Void)?

    private let lexicons: LexiconProvider
    public let personal: PersonalModel
    private var correctors: [Language: Corrector] = [:]
    private var lastCommit: Commit?
    /// Where each letter of the word being typed was tapped, in order. Kept in step with
    /// `currentWord`, and abandoned the moment the two disagree.
    private var touches: [TouchSample?] = []
    private var punctuation: PunctuationRun?
    private var lastEvent: InputEvent?

    public init(document: TextDocument, lexicons: LexiconProvider, personal: PersonalModel = PersonalModel(), languages: [Language] = [.czech, .english], language: Language? = nil, settings: ComposerSettings = ComposerSettings()) {
        self.document = document
        self.lexicons = lexicons
        self.personal = personal
        self.languages = languages.isEmpty ? [.english] : languages
        self.language = language ?? self.languages[0]
        self.settings = settings
        refreshAutoCapitalization()
    }

    public func setLanguages(_ langs: [Language], current: Language) {
        languages = langs.isEmpty ? [.english] : langs
        language = languages.contains(current) ? current : languages[0]
        correctors = [:]
        refreshCandidates()
    }

    public func invalidateCorrectors() { correctors = [:] }

    // MARK: - Event handling

    /// `touch` is where the key was actually tapped, when the event came from one.
    /// It is only meaningful for `.character` and is what drives the spatial model.
    public func handle(_ event: InputEvent, touch: TouchSample? = nil) {
        notice = nil
        switch event {
        case .character(let c):
            typeCharacter(c, touch: touch)
        case .space:
            insertSpace(fromSwipe: false)
        case .swipe(.right):
            insertSpace(fromSwipe: true)
        case .swipe(.left):
            deletePreviousWord()
        case .swipe(.up):
            cycleCommit(by: settings.swipeDownForNext ? -1 : 1)
        case .swipe(.down):
            cycleCommit(by: settings.swipeDownForNext ? 1 : -1)
        case .backspace:
            if !document.textBeforeCursor.isEmpty { document.deleteBackward(1) }
            if !touches.isEmpty { touches.removeLast() }
            refreshCandidates()
            refreshAutoCapitalization()
        case .enter:
            commitCurrentWord(trailing: "\n")
            refreshAutoCapitalization()
        case .shiftTap:
            shift = shift == .off ? .on : .off
        case .shiftDoubleTap:
            shift = .locked
        case .selectCandidate(let i):
            selectCandidate(i)
        case .switchLanguage:
            touches.removeAll()
            guard let idx = languages.firstIndex(of: language) else { return }
            language = languages[(idx + 1) % languages.count]
            onLanguageChange?(language)
            refreshCandidates()
        case .contextChanged:
            // The host reports this after our own edits as well as after the user moves
            // the caret, so only drop the taps once they no longer match the word.
            if touches.count != currentWord.unicodeScalars.count { touches.removeAll() }
            refreshCandidates()
            refreshAutoCapitalization()
        }
        lastEvent = event
    }

    // MARK: - Helpers

    static func isWordScalar(_ s: Unicode.Scalar) -> Bool {
        CharacterSet.letters.contains(s) || s == "'" || s == "’"
    }

    /// The committed word before the one at the cursor, lowercased, or nil if there
    /// isn't one on this side of a sentence boundary. This is the context the personal
    /// bigram counts are keyed on.
    func previousWord() -> String? {
        let scalars = Array(document.textBeforeCursor.unicodeScalars)
        var i = scalars.count
        while i > 0, Composer.isWordScalar(scalars[i - 1]) { i -= 1 }
        return Composer.wordBefore(scalars, i)
    }

    /// Reads the word ending just before `i`, skipping the separators in between.
    /// Returns nil across a sentence end: "him. Tomorrow" is not a word pair.
    static func wordBefore(_ scalars: [Unicode.Scalar], _ i: Int) -> String? {
        var i = i
        var sawSeparator = false
        while i > 0, !isWordScalar(scalars[i - 1]) {
            let s = scalars[i - 1]
            if s == "\n" || s == "." || s == "!" || s == "?" { return nil }
            sawSeparator = true
            i -= 1
        }
        guard sawSeparator else { return nil }
        var word: [Unicode.Scalar] = []
        while i > 0, isWordScalar(scalars[i - 1]) {
            word.append(scalars[i - 1])
            i -= 1
        }
        guard !word.isEmpty else { return nil }
        return String(String.UnicodeScalarView(word.reversed())).lowercased()
    }

    /// The letters immediately before the cursor.
    public var currentWord: String {
        let before = document.textBeforeCursor
        var scalars: [Unicode.Scalar] = []
        for s in before.unicodeScalars.reversed() {
            if Composer.isWordScalar(s) { scalars.append(s) } else { break }
        }
        return String(String.UnicodeScalarView(scalars.reversed()))
    }

    func corrector(for lang: Language) -> Corrector? {
        if let c = correctors[lang] { return c }
        guard let lex = lexicons.lexicon(for: lang) else { return nil }
        let qwertz: Bool? = lang == .czech ? settings.czechQwertz : nil
        let c = Corrector(lexicon: lex, neighbourMap: Layouts.neighbourMap(for: lang, qwertz: qwertz))
        correctors[lang] = c
        return c
    }

    static func applyCase(of pattern: String, to word: String) -> String {
        guard let first = pattern.first else { return word }
        if pattern.count > 1, pattern == pattern.uppercased(), pattern != pattern.lowercased() {
            return word.uppercased()
        }
        if first.isUppercase {
            return word.prefix(1).uppercased() + word.dropFirst()
        }
        return word
    }

    private func typeCharacter(_ raw: String, touch: TouchSample? = nil) {
        var c = raw
        if shift != .off, raw.rangeOfCharacter(from: .letters) != nil {
            c = raw.uppercased()
        }
        let isWordChar = raw.unicodeScalars.allSatisfy(Composer.isWordScalar)
        if isWordChar {
            document.insert(c)
            touches.append(touch)
            lastCommit = nil
            punctuation = nil
            if shift == .on { shift = .off }
            refreshCandidates()
        } else {
            let punctuationThatCommits: Set<String> = [".", ",", "!", "?", ";", ":"]
            if punctuationThatCommits.contains(raw), !currentWord.isEmpty {
                commitCurrentWord(trailing: c)
            } else {
                document.insert(c)
                if punctuationThatCommits.contains(raw), var commit = lastCommit, isCommitValid(commit) {
                    commit.trailing += c
                    lastCommit = commit
                } else {
                    lastCommit = nil
                }
                refreshCandidates()
            }
            if shift == .on { shift = .off }
            refreshAutoCapitalization()
        }
    }

    private func insertSpace(fromSwipe: Bool) {
        let before = document.textBeforeCursor
        // Another space right after an auto-inserted mark repeats it: "word. " -> "word.. ".
        if var run = punctuation, isPunctuationValid(run) {
            document.deleteBackward(1)
            document.insert(run.mark + " ")
            run.count += 1
            punctuation = run
            refreshCandidates()
            refreshAutoCapitalization()
            return
        }
        // Space (or swipe right) directly after "word " -> period. Fleksy: swipe right twice.
        if settings.doubleSpacePeriod, before.hasSuffix(" "), !before.hasSuffix(". ") {
            let trimmed = before.dropLast()
            if let last = trimmed.unicodeScalars.last, Composer.isWordScalar(last) || last == ")" || last == "\"" {
                document.deleteBackward(1)
                document.insert(". ")
                punctuation = PunctuationRun(index: 0, count: 1)
                lastCommit = nil
                refreshCandidates()
                refreshAutoCapitalization()
                return
            }
        }
        punctuation = nil
        commitCurrentWord(trailing: " ")
        refreshAutoCapitalization()
    }

    private func isPunctuationValid(_ run: PunctuationRun) -> Bool {
        document.textBeforeCursor.hasSuffix(run.text)
    }

    /// Replaces the current punctuation run with a single mark from the cycle.
    private func replacePunctuation(_ run: PunctuationRun, with index: Int) {
        document.deleteBackward(run.text.count)
        let updated = PunctuationRun(index: index, count: 1)
        document.insert(updated.text)
        punctuation = updated
        refreshCandidates()
        refreshAutoCapitalization()
    }

    /// Runs autocorrect on the word before the cursor and appends `trailing`.
    private func commitCurrentWord(trailing: String) {
        let word = currentWord
        guard !word.isEmpty else {
            document.insert(trailing)
            lastCommit = nil
            touches.removeAll()
            refreshCandidates()
            return
        }
        // Read the context before touching the document, while the word is still there.
        let previous = previousWord()
        let prior = personal.prior(for: language, previous: previous)
        let taps = touches
        touches.removeAll()
        var options = [word]
        var corrected = false
        if let corrector = corrector(for: language), word.count >= 2 {
            let cands = corrector.candidates(for: word, context: CorrectionContext(personal: prior, touches: taps))
            let alternatives = cands.map { Composer.applyCase(of: word, to: $0.word) }.filter { $0.lowercased() != word.lowercased() }
            if settings.autocorrect, !prior.isLearned(word),
               let best = Composer.correction(for: word, candidates: cands, corrector: corrector, personal: prior) {
                let replacement = Composer.applyCase(of: word, to: best.word)
                document.deleteBackward(word.count)
                document.insert(replacement)
                options = [word, replacement] + alternatives.filter { $0 != replacement }
                corrected = true
            } else {
                options = [word] + alternatives
            }
        }
        document.insert(trailing)
        let commit = Commit(options: options, index: corrected ? 1 : 0, trailing: trailing, typed: word,
                            corrected: corrected, previous: previous)
        lastCommit = commit
        personal.note(commit.current, after: previous, language: language)
        refreshCandidates()
    }

    /// Picks the replacement for a committed word, or nil to keep it as typed.
    ///
    /// 1. Diacritic restoration: a word spelled the same apart from accents wins when it is the
    ///    more common spelling ("dekuji" -> "děkuji"), even if the accent-less form is in the list.
    /// 2. Unknown words are corrected when a candidate is within the cost budget.
    /// 3. Known but very rare words are corrected when a cheap edit yields a far more common
    ///    word ("teh" -> "the").
    static func correction(for word: String, candidates: [Corrector.Candidate], corrector: Corrector,
                           personal: PersonalPrior = .none) -> Corrector.Candidate? {
        let lower = word.lowercased()
        // A word the user types often counts as known even when we ship no entry for it,
        // which is what stops their own vocabulary being corrected away.
        let typedFrequency = max(corrector.lexicon.frequency(of: lower), personal.personalFrequency(of: lower))
        let folded = Diacritics.fold(lower)
        if let variant = candidates.first(where: { $0.word != lower && Diacritics.fold($0.word) == folded }),
           variant.frequency > typedFrequency {
            return variant
        }
        guard let best = candidates.first(where: { $0.word != lower }) else { return nil }
        if typedFrequency > 0 {
            let ok = best.cost <= 1.0 && log10(best.frequency) - log10(typedFrequency) >= 2.5
            return ok ? best : nil
        }
        return best.cost <= corrector.maxCost(forLength: word.unicodeScalars.count) ? best : nil
    }

    private func isCommitValid(_ commit: Commit) -> Bool {
        document.textBeforeCursor.hasSuffix(commit.current + commit.trailing)
    }

    private func cycleCommit(by delta: Int) {
        if let run = punctuation, isPunctuationValid(run) {
            let n = Composer.punctuationCycle.count
            replacePunctuation(run, with: ((run.index + delta) % n + n) % n)
            return
        }
        if let commit = lastCommit, isCommitValid(commit) {
            // Swipe down walks left towards the typed word and never wraps. Once there, further
            // swipes down on a corrected word alternate between learning and forgetting it.
            if delta < 0, commit.corrected, commit.index == 0 {
                if personal.isLearned(commit.typed, language: language) {
                    personal.forget(commit.typed, language: language)
                    notice = "forgotten"
                } else {
                    personal.learn(commit.typed, language: language)
                    notice = "learned"
                }
                refreshCandidates()
                return
            }
            let newIndex = max(0, min(commit.options.count - 1, commit.index + delta))
            guard newIndex != commit.index else { return }
            replaceCommit(commit, with: newIndex)
            return
        }
        // Swiping "next" on a word still being typed: correct it in place, no space.
        if delta > 0, !currentWord.isEmpty {
            commitCurrentWord(trailing: "")
            return
        }
        // Nothing pending. Reach back to the last word already in the document and
        // rebuild its alternatives, so its autocorrect can always be walked through
        // again - even after the commit was dropped by typing on, tapping elsewhere or
        // the host reporting a context change.
        guard currentWord.isEmpty, let recovered = recoverPreviousWord() else { return }
        let newIndex = max(0, min(recovered.options.count - 1, recovered.index + delta))
        if newIndex == recovered.index {
            lastCommit = recovered
            refreshCandidates()
        } else {
            replaceCommit(recovered, with: newIndex)
        }
    }

    /// Non-word characters that may sit between the cursor and the last word and still
    /// be swallowed back when that word is swapped. Newlines are excluded: re-inserting
    /// one can send a message.
    private static let recoverableTrailing = Set<Unicode.Scalar>(" .,!?;:)\"'".unicodeScalars)

    /// Rebuilds a `Commit` for the word before the cursor from the document alone.
    /// `corrected` is false: we cannot know what was originally typed, so this restores
    /// navigation of the alternatives but not the learn/forget gesture.
    private func recoverPreviousWord() -> Commit? {
        let scalars = Array(document.textBeforeCursor.unicodeScalars)
        var i = scalars.count
        var trailing: [Unicode.Scalar] = []
        while i > 0, trailing.count < 4, Composer.recoverableTrailing.contains(scalars[i - 1]) {
            trailing.append(scalars[i - 1])
            i -= 1
        }
        var word: [Unicode.Scalar] = []
        while i > 0, Composer.isWordScalar(scalars[i - 1]) {
            word.append(scalars[i - 1])
            i -= 1
        }
        guard !word.isEmpty else { return nil }
        let typed = String(String.UnicodeScalarView(word.reversed()))
        let previous = Composer.wordBefore(scalars, i)
        var options = [typed]
        if let corrector = corrector(for: language), typed.count >= 2 {
            let context = CorrectionContext(personal: personal.prior(for: language, previous: previous))
            options += corrector.candidates(for: typed, context: context)
                .map { Composer.applyCase(of: typed, to: $0.word) }
                .filter { $0.lowercased() != typed.lowercased() }
        }
        guard options.count > 1 else { return nil }
        return Commit(options: options, index: 0, trailing: String(String.UnicodeScalarView(trailing.reversed())),
                      typed: typed, corrected: false, previous: previous)
    }

    private func replaceCommit(_ commit: Commit, with newIndex: Int) {
        document.deleteBackward(commit.current.count + commit.trailing.count)
        var updated = commit
        updated.index = newIndex
        document.insert(updated.current + updated.trailing)
        // The word the user settled on is the one worth counting, not the one we guessed.
        personal.unnote(commit.current, after: commit.previous, language: language)
        personal.note(updated.current, after: commit.previous, language: language)
        lastCommit = updated
        refreshCandidates()
        refreshAutoCapitalization()
    }

    private func selectCandidate(_ i: Int) {
        if let run = punctuation, isPunctuationValid(run) {
            guard Composer.punctuationCycle.indices.contains(i) else { return }
            replacePunctuation(run, with: i)
            return
        }
        if let commit = lastCommit, isCommitValid(commit) {
            guard commit.options.indices.contains(i) else { return }
            replaceCommit(commit, with: i)
            return
        }
        let word = currentWord
        guard !word.isEmpty, candidates.indices.contains(i) else { return }
        let previous = previousWord()
        let chosen = candidates[i].text
        touches.removeAll()
        document.deleteBackward(word.count)
        document.insert(chosen + " ")
        var options = candidates.map { $0.text }
        options.remove(at: i)
        options.insert(chosen, at: 0)
        lastCommit = Commit(options: options, index: 0, trailing: " ", typed: word, corrected: false, previous: previous)
        personal.note(chosen, after: previous, language: language)
        refreshCandidates()
        refreshAutoCapitalization()
    }

    private func deletePreviousWord() {
        let before = document.textBeforeCursor
        guard !before.isEmpty else { return }
        let scalars = Array(before.unicodeScalars)
        var i = scalars.count
        var count = 0
        while i > 0, CharacterSet.whitespacesAndNewlines.contains(scalars[i - 1]) { i -= 1; count += 1 }
        var wordCount = 0
        while i > 0, Composer.isWordScalar(scalars[i - 1]) { i -= 1; wordCount += 1 }
        if wordCount == 0, i > 0 { wordCount = 1 } // a lone punctuation mark
        document.deleteBackward(count + wordCount)
        lastCommit = nil
        punctuation = nil
        touches.removeAll()
        refreshCandidates()
        refreshAutoCapitalization()
    }

    // MARK: - Derived state

    private func refreshCandidates() {
        if let run = punctuation, isPunctuationValid(run) {
            candidates = Composer.punctuationCycle.enumerated().map { CandidateItem(text: $1, isSelected: $0 == run.index) }
            return
        }
        punctuation = nil
        if let commit = lastCommit, isCommitValid(commit) {
            candidates = commit.options.enumerated().map { CandidateItem(text: $1, isSelected: $0 == commit.index) }
            return
        }
        lastCommit = nil
        let word = currentWord
        guard !word.isEmpty else { candidates = []; return }
        var items = [CandidateItem(text: word, isSelected: true)]
        if let lex = lexicons.lexicon(for: language) {
            for c in lex.completions(for: word, limit: 2) {
                items.append(CandidateItem(text: Composer.applyCase(of: word, to: c), isSelected: false))
            }
        }
        candidates = items
    }

    private func refreshAutoCapitalization() {
        guard settings.autoCapitalize, shift != .locked else { return }
        shift = shouldAutoCapitalize ? .on : .off
    }

    /// True at the start of the text or after sentence-ending punctuation followed by whitespace.
    public var shouldAutoCapitalize: Bool {
        let before = document.textBeforeCursor
        if before.isEmpty { return true }
        let scalars = Array(before.unicodeScalars)
        var i = scalars.count
        guard CharacterSet.whitespacesAndNewlines.contains(scalars[i - 1]) else { return false }
        if scalars[i - 1] == "\n" { return true }
        while i > 0, CharacterSet.whitespacesAndNewlines.contains(scalars[i - 1]) { i -= 1 }
        if i == 0 { return true }
        return [".", "!", "?"].contains(scalars[i - 1])
    }
}
