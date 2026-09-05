import Foundation
@testable import FleksyCore

final class FakeDocument: TextDocument {
    var before: String
    var after: String
    init(_ before: String = "", after: String = "") { self.before = before; self.after = after }
    var textBeforeCursor: String { before }
    var textAfterCursor: String { after }
    func insert(_ text: String) { before += text }
    func deleteBackward(_ count: Int) {
        for _ in 0..<count where !before.isEmpty { before.removeLast() }
    }
    var text: String { before + after }
}

enum TestLexicons {
    static let english = Lexicon(language: .english, words: [
        ("the", 1000), ("hello", 500), ("help", 400), ("world", 450), ("word", 300), ("words", 120),
        ("test", 200), ("tests", 80), ("keyboard", 150), ("this", 800), ("is", 900), ("a", 950),
        ("thanks", 200), ("think", 220), ("teh", 1), ("great", 300), ("with", 700), ("what", 650),
        ("i", 999), ("you", 998), ("it", 700), ("if", 300),
    ])
    static let czech = Lexicon(language: .czech, words: [
        ("dělám", 500), ("děláš", 300), ("dělat", 400), ("ahoj", 800), ("jak", 900), ("se", 1000),
        ("máš", 700), ("dobře", 600), ("řeč", 100), ("čau", 300), ("že", 950), ("to", 990),
        ("dnes", 500), ("zítra", 400), ("jsem", 900), ("jsi", 850), ("být", 700), ("byt", 200),
        ("přijdu", 300), ("prší", 150), ("dekuji", 40), ("děkuji", 4000),
    ])
    static let provider = InMemoryLexicons([english, czech])
}
