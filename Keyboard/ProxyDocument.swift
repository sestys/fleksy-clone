import UIKit
import FleksyCore

/// Adapts UITextDocumentProxy to the Composer's TextDocument protocol.
final class ProxyDocument: TextDocument {
    private let proxyProvider: () -> UITextDocumentProxy
    init(_ provider: @escaping () -> UITextDocumentProxy) { proxyProvider = provider }

    var textBeforeCursor: String { proxyProvider().documentContextBeforeInput ?? "" }
    var textAfterCursor: String { proxyProvider().documentContextAfterInput ?? "" }
    var snapshot: DocumentSnapshot {
        let p = proxyProvider()
        // UIKit may return nil before attaching the proxy, despite the SDK's
        // nonnull annotation. Read the public Objective-C getter as an optional
        // object to avoid Swift's unconditional NSUUID -> UUID bridge trapping.
        let identifier = p.perform(#selector(getter: UITextDocumentProxy.documentIdentifier))?
            .takeUnretainedValue() as? UUID
        var snapshot = DocumentSnapshot(before: p.documentContextBeforeInput, after: p.documentContextAfterInput,
                                        selection: p.selectedText, identifier: identifier)
        let literalField = p.keyboardType == .emailAddress || p.keyboardType == .URL
        snapshot.autocorrectionAllowed = p.autocorrectionType != .no && !literalField
        switch p.autocapitalizationType ?? .sentences {
        case .none: snapshot.capitalization = .none
        case .words: snapshot.capitalization = .words
        case .allCharacters: snapshot.capitalization = .allCharacters
        default: snapshot.capitalization = .sentences
        }
        if literalField { snapshot.capitalization = .none }
        return snapshot
    }
    func insert(_ text: String) { proxyProvider().insertText(text) }
    func deleteBackward(_ count: Int) {
        let p = proxyProvider()
        for _ in 0..<count { p.deleteBackward() }
    }
}
