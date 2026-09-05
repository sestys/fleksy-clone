import Foundation

/// What a key does when tapped.
public enum KeyAction: Equatable, Hashable, Sendable {
    case character(String)
    case shift
    case backspace
    case space
    case enter
    case numbers      // switch to the 123 layer
    case symbols      // switch to the #+= layer
    case letters      // back to ABC
    case globe        // next system keyboard
}

/// A single key in a layout row. `width` is relative: 1.0 = a standard letter key.
public struct Key: Equatable, Hashable, Sendable {
    public let action: KeyAction
    public let label: String
    public let width: Double
    public let accents: [String]

    public init(_ action: KeyAction, label: String? = nil, width: Double = 1.0, accents: [String] = []) {
        self.action = action
        self.width = width
        self.accents = accents
        if let label {
            self.label = label
        } else if case .character(let c) = action {
            self.label = c
        } else {
            self.label = ""
        }
    }

    public static func char(_ c: String, accents: [String] = []) -> Key {
        Key(.character(c), accents: accents)
    }

    public var isCharacter: Bool {
        if case .character = action { return true }
        return false
    }
}

public enum KeyboardLayer: Equatable, Sendable {
    case letters
    case numbers
    case symbols
}

/// Rows of keys. Row 0 is the top row.
public struct KeyboardLayout: Equatable, Sendable {
    public let rows: [[Key]]
    public init(rows: [[Key]]) { self.rows = rows }

    /// Total relative width of a row (used to scale keys to the view width).
    public func rowWidth(_ index: Int) -> Double {
        rows[index].reduce(0) { $0 + $1.width }
    }

    public var maxRowWidth: Double {
        (0..<rows.count).map(rowWidth).max() ?? 0
    }

    public func allKeys() -> [Key] { rows.flatMap { $0 } }
}

public enum Layouts {
    // MARK: Accent tables

    static let czechAccents: [String: [String]] = [
        "a": ["á"], "e": ["ě", "é"], "i": ["í"], "o": ["ó"], "u": ["ů", "ú"], "y": ["ý"],
        "c": ["č"], "d": ["ď"], "n": ["ň"], "r": ["ř"], "s": ["š"], "t": ["ť"], "z": ["ž"],
    ]

    static let englishAccents: [String: [String]] = [
        "a": ["á", "à", "â", "ä", "ã", "å", "æ"], "e": ["é", "è", "ê", "ë", "ě"], "i": ["í", "ì", "î", "ï"],
        "o": ["ó", "ò", "ô", "ö", "õ", "ø", "œ"], "u": ["ú", "ù", "û", "ü"], "c": ["ç", "č"],
        "n": ["ñ"], "s": ["ß", "š"], "y": ["ý", "ÿ"], "z": ["ž"], "r": ["ř"],
    ]

    public static func accents(for letter: String, language: Language) -> [String] {
        let table = language == .czech ? czechAccents : englishAccents
        return table[letter.lowercased()] ?? []
    }

    // MARK: Letter rows

    static let qwertyRows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
    static let qwertzRows = ["qwertzuiop", "asdfghjkl", "yxcvbnm"]

    public static func letterRows(for language: Language, qwertz: Bool? = nil) -> [String] {
        let useQwertz = qwertz ?? (language == .czech)
        return useQwertz ? qwertzRows : qwertyRows
    }

    /// Horizontal offset (in key widths) of each letter row relative to the top row.
    /// Used by the corrector to compute which keys are physical neighbours.
    static let letterRowOffsets: [Double] = [0, 0.5, 1.5]

    // MARK: Full layouts

    /// Standard Fleksy-like letter layout: 3 letter rows + bottom bar.
    public static func letters(for language: Language, qwertz: Bool? = nil) -> KeyboardLayout {
        let rowStrings = letterRows(for: language, qwertz: qwertz)
        func keys(_ s: String) -> [Key] {
            s.map { ch in
                let c = String(ch)
                return Key.char(c, accents: accents(for: c, language: language))
            }
        }
        let row1 = keys(rowStrings[0])
        let row2 = keys(rowStrings[1])
        let row3 = [Key(.shift, label: "⇧", width: 1.5)] + keys(rowStrings[2]) + [Key(.backspace, label: "⌫", width: 1.5)]
        let row4 = bottomRow(toggle: Key(.numbers, label: "123", width: 1.5), language: language)
        return KeyboardLayout(rows: [row1, row2, row3, row4])
    }

    public static func numbers(for language: Language) -> KeyboardLayout {
        let row1 = "1234567890".map { Key.char(String($0)) }
        let row2 = ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""].map { Key.char($0) }
        let row3 = [Key(.symbols, label: "#+=", width: 1.5)] + [".", ",", "?", "!", "'", "%"].map { Key.char($0, accents: []) } + [Key(.backspace, label: "⌫", width: 1.5)]
        let row4 = bottomRow(toggle: Key(.letters, label: "ABC", width: 1.5), language: language)
        return KeyboardLayout(rows: [row1, row2, row3, row4])
    }

    public static func symbols(for language: Language) -> KeyboardLayout {
        let row1 = ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="].map { Key.char($0) }
        let row2 = ["_", "\\", "|", "~", "<", ">", "€", "£", "¥", "•"].map { Key.char($0) }
        let row3 = [Key(.numbers, label: "123", width: 1.5)] + [".", ",", "?", "!", "'", "`"].map { Key.char($0) } + [Key(.backspace, label: "⌫", width: 1.5)]
        let row4 = bottomRow(toggle: Key(.letters, label: "ABC", width: 1.5), language: language)
        return KeyboardLayout(rows: [row1, row2, row3, row4])
    }

    static func bottomRow(toggle: Key, language: Language) -> [Key] {
        [
            toggle,
            Key(.globe, label: "🌐", width: 1.25),
            Key(.space, label: language.displayName, width: 4.75),
            Key(.character(","), label: ",", width: 1.0),
            Key(.enter, label: "↵", width: 1.5),
        ]
    }

    public static func layout(layer: KeyboardLayer, language: Language, qwertz: Bool? = nil) -> KeyboardLayout {
        switch layer {
        case .letters: return letters(for: language, qwertz: qwertz)
        case .numbers: return numbers(for: language)
        case .symbols: return symbols(for: language)
        }
    }

    /// Physical neighbours of every letter for a language's letter rows.
    public static func neighbourMap(for language: Language, qwertz: Bool? = nil) -> [Character: Set<Character>] {
        let rows = letterRows(for: language, qwertz: qwertz)
        var positions: [(Character, Double, Double)] = []
        for (r, row) in rows.enumerated() {
            for (i, ch) in row.enumerated() {
                positions.append((ch, Double(i) + letterRowOffsets[r], Double(r)))
            }
        }
        var map: [Character: Set<Character>] = [:]
        for (c, x, y) in positions {
            var set = Set<Character>()
            for (d, x2, y2) in positions where d != c {
                if abs(x - x2) <= 1.0 && abs(y - y2) <= 1.0 { set.insert(d) }
            }
            map[c] = set
        }
        return map
    }
}
