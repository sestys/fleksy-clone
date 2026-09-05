import XCTest
@testable import FleksyCore

final class CorrectorTests: XCTestCase {
    func testLexiconParsingAndLookup() {
        let lex = Lexicon(language: .english, text: "the 100\nHello 50\n123 9\nit's 3\n")
        XCTAssertEqual(lex.count, 3)
        XCTAssertTrue(lex.contains("Hello"))
        XCTAssertTrue(lex.contains("it's"))
        XCTAssertFalse(lex.contains("123"))
    }

    func testCompletions() {
        XCTAssertEqual(TestLexicons.english.completions(for: "wor"), ["world", "word", "words"])
        XCTAssertEqual(TestLexicons.english.completions(for: "hel", limit: 1), ["hello"])
        XCTAssertEqual(TestLexicons.english.completions(for: "hello"), [])
    }

    func testTransposition() {
        let c = Corrector(lexicon: TestLexicons.english)
        // "teh" is a (rare) lexicon entry in the fixture: exact match ranks first, then the fix.
        XCTAssertEqual(Array(c.candidates(for: "teh").map(\.word).prefix(2)), ["teh", "the"])
        XCTAssertEqual(c.candidates(for: "hlelo").first?.word, "hello")
    }

    func testAdjacentKeyTypo() {
        let c = Corrector(lexicon: TestLexicons.english)
        XCTAssertEqual(c.candidates(for: "wprld").first?.word, "world") // p is next to o
        XCTAssertEqual(c.candidates(for: "thanjs").first?.word, "thanks")
    }

    func testDiacriticsAreCheap() {
        let c = Corrector(lexicon: TestLexicons.czech)
        XCTAssertEqual(c.candidates(for: "delam").first?.word, "dělám")
        XCTAssertEqual(c.candidates(for: "dobre").first?.word, "dobře")
        XCTAssertEqual(c.candidates(for: "prijdu").first?.word, "přijdu")
        // Exact word beats a diacritic variant even when the variant is more frequent.
        XCTAssertEqual(c.candidates(for: "byt").first?.word, "byt")
        XCTAssertEqual(c.candidates(for: "byt").map(\.word).prefix(2), ["byt", "být"])
    }

    func testNoCandidateForGarbage() {
        let c = Corrector(lexicon: TestLexicons.english)
        let best = c.candidates(for: "xqzvbn").first
        XCTAssertTrue(best == nil || best!.cost > c.maxCost(forLength: 6))
    }

    func testKnownWordIsFirst() {
        let c = Corrector(lexicon: TestLexicons.english)
        XCTAssertEqual(c.candidates(for: "help").first?.word, "help")
        XCTAssertEqual(c.candidates(for: "Help").first?.word, "help")
    }
}
