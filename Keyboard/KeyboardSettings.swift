import Foundation
import FleksyCore

/// Persisted keyboard preferences. Stored in the extension's own UserDefaults so no
/// App Group (and therefore no paid developer account) is required.
final class KeyboardSettings {
    static let shared = KeyboardSettings()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let theme = "theme"
        static let languages = "languages"
        static let currentLanguage = "currentLanguage"
        static let czechQwertz = "czechQwertz"
        static let autocorrect = "autocorrect"
        static let autoCapitalize = "autoCapitalize"
        static let keyHeight = "keyHeight"
        static let clicks = "clicks"
        static let recentEmoji = "recentEmoji"
    }

    var theme: Theme {
        get { Theme.named(defaults.string(forKey: Keys.theme) ?? Theme.classic.id) }
        set { defaults.set(newValue.id, forKey: Keys.theme) }
    }

    var languages: [Language] {
        get {
            let raw = defaults.stringArray(forKey: Keys.languages) ?? ["cs", "en"]
            let langs = raw.compactMap(Language.init(rawValue:))
            return langs.isEmpty ? [.english] : langs
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: Keys.languages) }
    }

    var currentLanguage: Language {
        get {
            let l = Language(rawValue: defaults.string(forKey: Keys.currentLanguage) ?? "") ?? languages[0]
            return languages.contains(l) ? l : languages[0]
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.currentLanguage) }
    }

    var czechQwertz: Bool {
        get { defaults.object(forKey: Keys.czechQwertz) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.czechQwertz) }
    }

    var autocorrect: Bool {
        get { defaults.object(forKey: Keys.autocorrect) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.autocorrect) }
    }

    var autoCapitalize: Bool {
        get { defaults.object(forKey: Keys.autoCapitalize) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.autoCapitalize) }
    }

    /// Height of one key row in points (portrait).
    var keyHeight: Double {
        get { defaults.object(forKey: Keys.keyHeight) as? Double ?? 54 }
        set { defaults.set(newValue, forKey: Keys.keyHeight) }
    }

    var clicks: Bool {
        get { defaults.object(forKey: Keys.clicks) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.clicks) }
    }

    var recentEmoji: [String] {
        get { defaults.stringArray(forKey: Keys.recentEmoji) ?? [] }
        set { defaults.set(Array(newValue.prefix(40)), forKey: Keys.recentEmoji) }
    }

    func noteEmojiUsed(_ e: String) {
        var list = recentEmoji.filter { $0 != e }
        list.insert(e, at: 0)
        recentEmoji = list
    }

    // MARK: Learned words

    private static let learnedKey = "learnedWords"

    /// Stored as "cs:word" / "en:word".
    var learnedWords: [String] {
        get { defaults.stringArray(forKey: KeyboardSettings.learnedKey) ?? [] }
        set { defaults.set(newValue, forKey: KeyboardSettings.learnedKey) }
    }

    func clearLearnedWords() { learnedWords = [] }

    var composerSettings: ComposerSettings {
        var s = ComposerSettings()
        s.autocorrect = autocorrect
        s.autoCapitalize = autoCapitalize
        s.czechQwertz = czechQwertz
        return s
    }
}

/// LearnedWordsStore backed by the extension's UserDefaults.
final class PersistentLearnedWords: LearnedWordsStore {
    private let settings: KeyboardSettings
    private var cache: Set<String>

    init(settings: KeyboardSettings = .shared) {
        self.settings = settings
        cache = Set(settings.learnedWords)
    }

    func reload() { cache = Set(settings.learnedWords) }

    func contains(_ word: String, language: Language) -> Bool {
        cache.contains("\(language.rawValue):\(word.lowercased())")
    }

    func add(_ word: String, language: Language) {
        let entry = "\(language.rawValue):\(word.lowercased())"
        guard !cache.contains(entry) else { return }
        cache.insert(entry)
        settings.learnedWords = settings.learnedWords + [entry]
    }

    func remove(_ word: String, language: Language) {
        let entry = "\(language.rawValue):\(word.lowercased())"
        cache.remove(entry)
        settings.learnedWords = settings.learnedWords.filter { $0 != entry }
    }
}
