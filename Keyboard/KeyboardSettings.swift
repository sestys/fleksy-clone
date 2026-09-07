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
        static let swipeDownForNext = "swipeDownForNext"
        static let recentEmoji = "recentEmoji"   // legacy most-recent-first list
        static let emojiUses = "emojiUses"
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

    /// Height of one key row in points (portrait). `keyHeightRange` is what the
    /// settings slider offers; 54 is roughly the stock iOS row height.
    static let keyHeightRange: ClosedRange<Double> = 38...82
    static let defaultKeyHeight: Double = 54

    var keyHeight: Double {
        get {
            let stored = defaults.object(forKey: Keys.keyHeight) as? Double ?? KeyboardSettings.defaultKeyHeight
            return min(max(stored, KeyboardSettings.keyHeightRange.lowerBound), KeyboardSettings.keyHeightRange.upperBound)
        }
        set { defaults.set(newValue, forKey: Keys.keyHeight) }
    }

    /// Swipe down = next suggestion, swipe up = back towards what you typed.
    var swipeDownForNext: Bool {
        get { defaults.object(forKey: Keys.swipeDownForNext) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.swipeDownForNext) }
    }

    var clicks: Bool {
        get { defaults.object(forKey: Keys.clicks) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.clicks) }
    }

    private var emojiUsage: EmojiUsage {
        get {
            if let stored = defaults.dictionary(forKey: Keys.emojiUses) as? [String: [Int]] {
                return EmojiUsage(stored: stored)
            }
            // First run after the upgrade: carry over the list the old version kept.
            return EmojiUsage.migrating(fromMostRecentFirst: defaults.stringArray(forKey: Keys.recentEmoji) ?? [])
        }
        set {
            defaults.set(newValue.stored, forKey: Keys.emojiUses)
            defaults.removeObject(forKey: Keys.recentEmoji)
        }
    }

    /// Emoji for the recent tab, most used first. This is a snapshot on purpose: the
    /// picker re-reads it when the tab is opened and not while it is being tapped, so
    /// emoji never move out from under a finger picking several in a row.
    var recentEmoji: [String] { emojiUsage.ordered() }

    func noteEmojiUsed(_ e: String) {
        var usage = emojiUsage
        usage.note(e, at: Int(Date().timeIntervalSince1970))
        emojiUsage = usage
    }

    // MARK: Learned words (legacy)

    private static let learnedKey = "learnedWords"

    /// Words taught to an earlier version, stored as "cs:word" / "en:word". Read once at
    /// launch and handed to the personal model, then cleared; nothing writes here now.
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
        s.swipeDownForNext = swipeDownForNext
        return s
    }
}
