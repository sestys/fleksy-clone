import Foundation

/// A typing language. Determines the letter layout, accent popups and lexicon.
public enum Language: String, CaseIterable, Codable, Sendable {
    case czech = "cs"
    case english = "en"

    /// Name shown on the space bar, in the language itself (as Fleksy does).
    public var displayName: String {
        switch self {
        case .czech: return "Čeština"
        case .english: return "English"
        }
    }

    public var shortName: String {
        switch self {
        case .czech: return "CS"
        case .english: return "EN"
        }
    }

    /// Resource file name for the bundled frequency list.
    public var lexiconResource: String { rawValue }
}
