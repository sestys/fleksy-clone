import Foundation

/// A colour as plain RGBA components (0...1) so themes do not depend on UIKit.
public struct RGBA: Equatable, Hashable, Codable, Sendable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255, alpha)
    }
    public func lighter(_ amount: Double) -> RGBA {
        RGBA(min(1, r + amount), min(1, g + amount), min(1, b + amount), a)
    }
    public func darker(_ amount: Double) -> RGBA {
        RGBA(max(0, r - amount), max(0, g - amount), max(0, b - amount), a)
    }
    public func alpha(_ value: Double) -> RGBA { RGBA(r, g, b, value) }
}

/// Fleksy-style theme: flat rows of colour, no key borders, thin separators.
public struct Theme: Equatable, Hashable, Codable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var background: RGBA
    /// Per-row background colours (letters rows, then the bottom bar). Cycled if shorter.
    public var rowColors: [RGBA]
    public var bottomRowColor: RGBA
    /// Rounded keys in the bottom bar, and the space bar.
    public var bottomKey: RGBA
    public var spaceKey: RGBA
    public var keyText: RGBA
    public var specialKeyText: RGBA
    public var separator: RGBA
    public var pressed: RGBA
    public var candidateBar: RGBA
    public var candidateText: RGBA
    public var candidateSelected: RGBA
    public var popup: RGBA
    public var popupText: RGBA
    public var isDark: Bool

    /// The original Fleksy look: teal top row, grey-blue home row, navy bottom.
    public static let classic = Theme(
        id: "classic", name: "Classic",
        background: RGBA(hex: 0x1E4A50),
        rowColors: [RGBA(hex: 0x1F4B52), RGBA(hex: 0x6D8B97), RGBA(hex: 0x172A4E)],
        bottomRowColor: RGBA(hex: 0x17284A),
        bottomKey: RGBA(hex: 0x34496D), spaceKey: RGBA(hex: 0x6B7D99),
        keyText: RGBA(hex: 0xFFFFFF), specialKeyText: RGBA(hex: 0xE6EEF2),
        separator: RGBA(hex: 0xFFFFFF, alpha: 0.0), pressed: RGBA(hex: 0xFFFFFF, alpha: 0.25),
        candidateBar: RGBA(hex: 0x2C5158), candidateText: RGBA(hex: 0xB7CDD2), candidateSelected: RGBA(hex: 0xFFFFFF),
        popup: RGBA(hex: 0x2C5158), popupText: RGBA(hex: 0xFFFFFF), isDark: true)

    public static let fleksyBlue = Theme(
        id: "blue", name: "Fleksy Blue",
        background: RGBA(hex: 0x1E88E5),
        rowColors: [RGBA(hex: 0x2196F3), RGBA(hex: 0x1E88E5), RGBA(hex: 0x1976D2)],
        bottomRowColor: RGBA(hex: 0x1565C0),
        bottomKey: RGBA(hex: 0x1565C0).lighter(0.12), spaceKey: RGBA(hex: 0x1565C0).lighter(0.22),
        keyText: RGBA(hex: 0xFFFFFF), specialKeyText: RGBA(hex: 0xE3F2FD),
        separator: RGBA(hex: 0xFFFFFF, alpha: 0.18), pressed: RGBA(hex: 0xFFFFFF, alpha: 0.28),
        candidateBar: RGBA(hex: 0x0D47A1), candidateText: RGBA(hex: 0xBBDEFB), candidateSelected: RGBA(hex: 0xFFFFFF),
        popup: RGBA(hex: 0x0D47A1), popupText: RGBA(hex: 0xFFFFFF), isDark: true)

    public static let midnight = Theme(
        id: "midnight", name: "Midnight",
        background: RGBA(hex: 0x1C1C1E),
        rowColors: [RGBA(hex: 0x2C2C2E), RGBA(hex: 0x262628), RGBA(hex: 0x1F1F21)],
        bottomRowColor: RGBA(hex: 0x141416),
        bottomKey: RGBA(hex: 0x141416).lighter(0.12), spaceKey: RGBA(hex: 0x141416).lighter(0.22),
        keyText: RGBA(hex: 0xF2F2F7), specialKeyText: RGBA(hex: 0xAEAEB2),
        separator: RGBA(hex: 0xFFFFFF, alpha: 0.10), pressed: RGBA(hex: 0xFFFFFF, alpha: 0.22),
        candidateBar: RGBA(hex: 0x0E0E10), candidateText: RGBA(hex: 0x8E8E93), candidateSelected: RGBA(hex: 0xFFFFFF),
        popup: RGBA(hex: 0x3A3A3C), popupText: RGBA(hex: 0xFFFFFF), isDark: true)

    public static let snow = Theme(
        id: "snow", name: "Snow",
        background: RGBA(hex: 0xF5F5F7),
        rowColors: [RGBA(hex: 0xFFFFFF), RGBA(hex: 0xF7F7F9), RGBA(hex: 0xEFEFF2)],
        bottomRowColor: RGBA(hex: 0xE4E4E8),
        bottomKey: RGBA(hex: 0xE4E4E8).lighter(0.12), spaceKey: RGBA(hex: 0xE4E4E8).lighter(0.22),
        keyText: RGBA(hex: 0x1C1C1E), specialKeyText: RGBA(hex: 0x5C5C61),
        separator: RGBA(hex: 0x000000, alpha: 0.08), pressed: RGBA(hex: 0x000000, alpha: 0.12),
        candidateBar: RGBA(hex: 0xE9E9EE), candidateText: RGBA(hex: 0x6E6E73), candidateSelected: RGBA(hex: 0x000000),
        popup: RGBA(hex: 0xFFFFFF), popupText: RGBA(hex: 0x000000), isDark: false)

    public static let coral = Theme(
        id: "coral", name: "Coral",
        background: RGBA(hex: 0xE53935),
        rowColors: [RGBA(hex: 0xEF5350), RGBA(hex: 0xE53935), RGBA(hex: 0xD32F2F)],
        bottomRowColor: RGBA(hex: 0xC62828),
        bottomKey: RGBA(hex: 0xC62828).lighter(0.12), spaceKey: RGBA(hex: 0xC62828).lighter(0.22),
        keyText: RGBA(hex: 0xFFFFFF), specialKeyText: RGBA(hex: 0xFFEBEE),
        separator: RGBA(hex: 0xFFFFFF, alpha: 0.18), pressed: RGBA(hex: 0xFFFFFF, alpha: 0.28),
        candidateBar: RGBA(hex: 0xB71C1C), candidateText: RGBA(hex: 0xFFCDD2), candidateSelected: RGBA(hex: 0xFFFFFF),
        popup: RGBA(hex: 0xB71C1C), popupText: RGBA(hex: 0xFFFFFF), isDark: true)

    public static let forest = Theme(
        id: "forest", name: "Forest",
        background: RGBA(hex: 0x2E7D32),
        rowColors: [RGBA(hex: 0x43A047), RGBA(hex: 0x388E3C), RGBA(hex: 0x2E7D32)],
        bottomRowColor: RGBA(hex: 0x1B5E20),
        bottomKey: RGBA(hex: 0x1B5E20).lighter(0.12), spaceKey: RGBA(hex: 0x1B5E20).lighter(0.22),
        keyText: RGBA(hex: 0xFFFFFF), specialKeyText: RGBA(hex: 0xE8F5E9),
        separator: RGBA(hex: 0xFFFFFF, alpha: 0.18), pressed: RGBA(hex: 0xFFFFFF, alpha: 0.28),
        candidateBar: RGBA(hex: 0x1B5E20), candidateText: RGBA(hex: 0xC8E6C9), candidateSelected: RGBA(hex: 0xFFFFFF),
        popup: RGBA(hex: 0x1B5E20), popupText: RGBA(hex: 0xFFFFFF), isDark: true)

    public static let all: [Theme] = [.classic, .fleksyBlue, .midnight, .snow, .coral, .forest]

    public static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? .classic
    }
}
