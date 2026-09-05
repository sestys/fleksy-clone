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
    struct Commit {
        var options: [String]
        var index: Int
        var trailing: String
        var current: String { options[index] }
    }

    public let document: TextDocument
    public var settings: ComposerSettings
    public private(set) var languages: [Language]
    public private(set) var language: Language
    public private(set) var shift: ShiftState = .off
    public private(set) var candidates: [CandidateItem] = []
    public var onLanguageChange: ((Language) -> Void)?

    private let lexicons: LexiconProvider
    private var correctors: [Language: Corrector] = [:]
    private var lastCommit: Commit?
    private var lastEvent: InputEvent?

    public init(document: TextDocument, lexicons: LexiconProvider, languages: [Language] = [.czech, .english], language: Language? = nil, settings: ComposerSettings = ComposerSettings()) {
        self.document = document
        self.lexicons = lexicons
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

    public func handle(_ event: InputEvent) {
        switch event {
        case .character(let c):
            typeCharacter(c)
        case .space:
            insertSpace(fromSwipe: false)
        case .swipe(.right):
            insertSpace(fromSwipe: true)
        case .swipe(.left):
            deletePreviousWord()
        case .swipe(.up):
            cycleCommit(by: 1)
        case .swipe(.down):
            cycleCommit(by: -1)
        case .backspace:
            if !document.textBeforeCursor.isEmpty { document.deleteBackward(1) }
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
            guard let idx = languages.firstIndex(of: language) else { return }
            language = languages[(idx + 1) % languages.count]
            onLanguageChange?(language)
            refreshCandidates()
        case .contextChanged:
            refreshCandidates()
            refreshAutoCapitalization()
        }
        lastEvent = event
    }

    // MARK: - Helpers

    static func isWordScalar(_ s: Unicode.Scalar) -> Bool {
        CharacterSet.letters.contains(s) || s == "'" || s == "’"
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

    private func typeCharacter(_ raw: String) {
        var c = raw
        if shift != .off, raw.rangeOfCharacter(from: .letters) != nil {
            c = raw.uppercased()
        }
        let isWordChar = raw.unicodeScalars.allSatisfy(Composer.isWordScalar)
        if isWordChar {
            document.insert(c)
            lastCommit = nil
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
        // Double space / double swipe right -> period.
        if settings.doubleSpacePeriod, before.hasSuffix(" "), !before.hasSuffix(". "),
           lastEvent == (fromSwipe ? .swipe(.right) : .space) {
            let trimmed = before.dropLast()
            if let last = trimmed.unicodeScalars.last, Composer.isWordScalar(last) || last == ")" || last == "\"" {
                document.deleteBackward(1)
                document.insert(". ")
                if var commit = lastCommit, commit.trailing == " " {
                    commit.trailing = ". "
                    lastCommit = commit
                }
                refreshAutoCapitalization()
                return
            }
        }
        commitCurrentWord(trailing: " ")
        refreshAutoCapitalization()
    }

    /// Runs autocorrect on the word before the cursor and appends `trailing`.
    private func commitCurrentWord(trailing: String) {
        let word = currentWord
        guard !word.isEmpty else {
            document.insert(trailing)
            lastCommit = nil
            refreshCandidates()
            return
        }
        var options = [word]
        if let corrector = corrector(for: language), word.count >= 2 {
            let cands = corrector.candidates(for: word)
            let alternatives = cands.map { Composer.applyCase(of: word, to: $0.word) }.filter { $0.lowercased() != word.lowercased() }
            if settings.autocorrect, let best = cands.first(where: { $0.word != word.lowercased() }),
               Composer.shouldCorrect(word, best: best, corrector: corrector) {
                let replacement = Composer.applyCase(of: word, to: best.word)
                document.deleteBackward(word.count)
                document.insert(replacement)
                options = [replacement] + alternatives.filter { $0 != replacement } + [word]
            } else {
                options = [word] + alternatives
            }
        }
        document.insert(trailing)
        lastCommit = Commit(options: options, index: 0, trailing: trailing)
        refreshCandidates()
    }

    /// Unknown words are corrected when a candidate is within the cost budget. Known but very
    /// rare words are also corrected when a cheap edit yields a far more common word ("teh" -> "the").
    static func shouldCorrect(_ word: String, best: Corrector.Candidate, corrector: Corrector) -> Bool {
        let typedFrequency = corrector.lexicon.frequency(of: word)
        if typedFrequency > 0 {
            return best.cost <= 1.0 && log10(best.frequency) - log10(typedFrequency) >= 2.5
        }
        return best.cost <= corrector.maxCost(forLength: word.unicodeScalars.count)
    }

    private func isCommitValid(_ commit: Commit) -> Bool {
        document.textBeforeCursor.hasSuffix(commit.current + commit.trailing)
    }

    private func cycleCommit(by delta: Int) {
        if let commit = lastCommit, isCommitValid(commit) {
            guard commit.options.count > 1 else { return }
            let n = commit.options.count
            let newIndex = ((commit.index + delta) % n + n) % n
            replaceCommit(commit, with: newIndex)
            return
        }
        // Swiping up on a word still being typed: correct it in place, no space.
        if delta > 0, !currentWord.isEmpty {
            commitCurrentWord(trailing: "")
        }
    }

    private func replaceCommit(_ commit: Commit, with newIndex: Int) {
        document.deleteBackward(commit.current.count + commit.trailing.count)
        var updated = commit
        updated.index = newIndex
        document.insert(updated.current + updated.trailing)
        lastCommit = updated
        refreshCandidates()
        refreshAutoCapitalization()
    }

    private func selectCandidate(_ i: Int) {
        if let commit = lastCommit, isCommitValid(commit) {
            guard commit.options.indices.contains(i) else { return }
            replaceCommit(commit, with: i)
            return
        }
        let word = currentWord
        guard !word.isEmpty, candidates.indices.contains(i) else { return }
        let chosen = candidates[i].text
        document.deleteBackward(word.count)
        document.insert(chosen + " ")
        var options = candidates.map { $0.text }
        options.remove(at: i)
        options.insert(chosen, at: 0)
        lastCommit = Commit(options: options, index: 0, trailing: " ")
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
        refreshCandidates()
        refreshAutoCapitalization()
    }

    // MARK: - Derived state

    private func refreshCandidates() {
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
