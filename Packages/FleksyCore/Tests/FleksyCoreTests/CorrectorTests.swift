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

/// The flat-buffer lexicon: the parts that used to be handled by Strings and a side index.
final class LexiconStorageTests: XCTestCase {
    func testWordsRoundTripThroughTheFlatStore() {
        let lex = Lexicon(language: .czech, text: "děkuji 100\nzítra 50\nano 9\n")
        XCTAssertEqual(lex.allWords, ["ano", "děkuji", "zítra"])
        for w in lex.allWords { XCTAssertTrue(lex.contains(w), w) }
    }

    func testWordsAreSortedByScalarValue() {
        let lex = Lexicon(language: .english, text: "beta 3\nalpha 2\ngamma 1\nAlpha 9\n")
        XCTAssertEqual(lex.allWords, ["alpha", "beta", "gamma"])
    }

    func testDuplicatesCollapseKeepingTheFirstListing() {
        // The source lists run most-frequent-first, so the first spelling seen wins.
        let lex = Lexicon(language: .english, text: "the 100\nThe 40\nTHE 1\nthem 7\n")
        XCTAssertEqual(lex.count, 2)
        XCTAssertEqual(lex.frequency(of: "the"), 100, accuracy: 0.5)
    }

    func testNonLetterEntriesAreRejectedWholesale() {
        let lex = Lexicon(language: .english, text: "ok 5\na1b 4\n<tag> 3\nfine 2\n")
        XCTAssertEqual(lex.allWords, ["fine", "ok"])
    }

    func testFrequencySurvivesTheLogRoundTrip() {
        let lex = Lexicon(language: .english, text: "common 2500000\nrare 3\n")
        XCTAssertEqual(lex.frequency(of: "common"), 2_500_000, accuracy: 2500)
        XCTAssertEqual(lex.frequency(of: "rare"), 3, accuracy: 0.01)
        XCTAssertEqual(lex.frequency(of: "absent"), 0)
    }

    func testCompletionsSpanTheSortedOrder() {
        let lex = Lexicon(language: .english, text: "work 90\nword 80\nworld 70\nwore 60\nother 50\n")
        XCTAssertEqual(lex.completions(for: "wor", limit: 3), ["work", "word", "world"])
        XCTAssertEqual(lex.completions(for: "work"), [])
        XCTAssertEqual(lex.completions(for: "zzz"), [])
    }

    func testSeveralListsMergeWithTheHigherFrequencyWinning() {
        // Two lists, as the keyboard loads them: words first, then names.
        let lex = Lexicon(language: .czech, texts: ["dostal 80000\nnovak 276\n",
                                                    "dostál 4000\nnovák 7989\n"])
        XCTAssertEqual(lex.count, 4)
        XCTAssertEqual(lex.frequency(of: "dostal"), 80000, accuracy: 80)
        XCTAssertEqual(lex.frequency(of: "novák"), 7989, accuracy: 8)
    }

    func testALaterListCanCorrectAnEarlierOne() {
        // Same word in both: the higher frequency stands, whichever list it came from.
        let lex = Lexicon(language: .english, texts: ["word 10\n", "word 5000\n"])
        XCTAssertEqual(lex.count, 1)
        XCTAssertEqual(lex.frequency(of: "word"), 5000, accuracy: 5)
    }

    func testLookupIsCaseAndAccentExact() {
        let lex = Lexicon(language: .czech, text: "být 100\nbyt 50\n")
        XCTAssertEqual(lex.count, 2)
        XCTAssertTrue(lex.contains("BÝT"))
        XCTAssertEqual(lex.frequency(of: "byt"), 50, accuracy: 0.5)
    }
}
