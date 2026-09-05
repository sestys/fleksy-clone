import XCTest
@testable import FleksyCore

/// Uses the real bundled word lists from Resources/Dictionaries (found relative to this file).
final class RealLexiconTests: XCTestCase {
    static func load(_ lang: Language) -> Lexicon? {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Resources/Dictionaries/\(lang.rawValue).txt")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return Lexicon(language: lang, text: text)
    }

    func testCzechCorrectionsWithRealList() throws {
        let lex = try XCTUnwrap(RealLexiconTests.load(.czech))
        XCTAssertGreaterThan(lex.count, 40_000)
        let c = Corrector(lexicon: lex)
        let cases: [(String, String)] = [
            ("delam", "dělám"), ("prijdu", "přijdu"), ("dekuji", "děkuji"), ("zitra", "zítra"),
            ("prosim", "prosím"), ("muzes", "můžeš"), ("nevim", "nevím"), ("clovek", "člověk"),
        ]
        for (typed, expected) in cases {
            let cands = c.candidates(for: typed)
            let chosen = Composer.correction(for: typed, candidates: cands, corrector: c)?.word ?? typed
            XCTAssertEqual(chosen, expected, "\(typed) -> \(cands.map(\.word))")
        }
        let dobry = c.candidates(for: "dobry")
        XCTAssertEqual(Composer.correction(for: "dobry", candidates: dobry, corrector: c)?.word, "dobrý")
    }

    func testEnglishCorrectionsWithRealList() throws {
        let lex = try XCTUnwrap(RealLexiconTests.load(.english))
        let c = Corrector(lexicon: lex)
        let cases: [(String, String)] = [
            ("teh", "the"), ("recieve", "receive"), ("wprld", "world"), ("keybaord", "keyboard"),
            ("becuase", "because"), ("tomorow", "tomorrow"),
        ]
        for (typed, expected) in cases {
            let cands = c.candidates(for: typed)
            let chosen = Composer.correction(for: typed, candidates: cands, corrector: c)?.word ?? typed
            XCTAssertEqual(chosen, expected, "\(typed) -> \(cands.map(\.word))")
        }
    }

    func testCorrectionSpeed() throws {
        let lex = try XCTUnwrap(RealLexiconTests.load(.czech))
        let c = Corrector(lexicon: lex)
        let words = ["delam", "prijdu", "nejakym", "a", "to", "ceskoslovensko", "zkouska"]
        let start = Date()
        for w in words { _ = c.candidates(for: w) }
        let perWord = Date().timeIntervalSince(start) / Double(words.count)
        print("avg correction time: \(Int(perWord * 1000)) ms/word")
        XCTAssertLessThan(perWord, 0.5)
    }

    func testLoadSpeed() throws {
        let start = Date()
        _ = try XCTUnwrap(RealLexiconTests.load(.czech))
        print("lexicon load time: \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    }
}
