import UIKit
import FleksyCore

/// Adapts UITextDocumentProxy to the Composer's TextDocument protocol.
final class ProxyDocument: TextDocument {
    private let proxyProvider: () -> UITextDocumentProxy
    init(_ provider: @escaping () -> UITextDocumentProxy) { proxyProvider = provider }

    var textBeforeCursor: String { proxyProvider().documentContextBeforeInput ?? "" }
    var textAfterCursor: String { proxyProvider().documentContextAfterInput ?? "" }
    func insert(_ text: String) { proxyProvider().insertText(text) }
    func deleteBackward(_ count: Int) {
        let p = proxyProvider()
        for _ in 0..<count { p.deleteBackward() }
    }
}
