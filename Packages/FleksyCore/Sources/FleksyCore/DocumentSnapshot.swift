import Foundation

/// Context is optional: an unavailable context is not evidence of an empty field.
public struct DocumentSnapshot: Equatable, Sendable {
    public enum Capitalization: Sendable { case none, sentences, words, allCharacters }
    public var before: String?
    public var after: String?
    public var selection: String?
    public var identifier: UUID?
    public var autocorrectionAllowed = true
    public var capitalization: Capitalization = .sentences

    public init(before: String?, after: String?, selection: String? = nil, identifier: UUID? = nil) {
        self.before = before
        self.after = after
        self.selection = selection
        self.identifier = identifier
    }

    public var hasSelection: Bool { !(selection ?? "").isEmpty }
    public var canReplaceWord: Bool {
        guard before != nil, !hasSelection else { return false }
        // UIKit also uses nil for the empty suffix at the end of a field. Keep
        // it in the snapshot for change detection, but don't disable correction
        // when a usable prefix exists and no word suffix is reported.
        return after?.unicodeScalars.first.map { !Composer.isWordScalar($0) } ?? true
    }
}
