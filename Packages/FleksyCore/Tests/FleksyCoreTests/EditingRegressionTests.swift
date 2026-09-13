import XCTest
@testable import FleksyCore

final class EditingRegressionTests: XCTestCase {
    private func composer(_ document: FakeDocument, personal: PersonalModel = PersonalModel()) -> Composer {
        var settings = ComposerSettings()
        settings.autoCapitalize = false
        return Composer(document: document, lexicons: TestLexicons.provider, personal: personal,
                        languages: [.english, .czech], language: .english, settings: settings)
    }

    func testEnterEndsPendingCorrection() {
        let doc = FakeDocument("helo")
        let c = composer(doc)
        c.handle(.enter)
        let entered = doc.text
        c.handle(.swipe(.up))
        c.handle(.selectCandidate(0))
        c.handle(.swipe(.down))
        XCTAssertEqual(doc.text, entered)
        XCTAssertEqual(doc.insertions.filter { $0.contains("\n") }.count, 1)
        XCTAssertTrue(c.candidates.isEmpty)
    }

    func testDeleteDecomposedWordPreservesPrecedingSpace() {
        let doc = FakeDocument("x de\u{030C}lam")
        composer(doc).handle(.swipe(.left))
        XCTAssertEqual(doc.text, "x ")
    }

    func testDeleteWordAfterCRLFDoesNotOverdelete() {
        let doc = FakeDocument("keep\r\n")
        composer(doc).handle(.swipe(.left))
        XCTAssertEqual(doc.text, "")
        XCTAssertEqual(doc.deletions, [5], "CRLF is one grapheme, not two backspaces")
    }

    func testCandidateSelectionInsideWordDoesNotDuplicateSuffix() {
        let doc = FakeDocument("hel", after: "lo")
        let c = composer(doc)
        c.handle(.contextChanged)
        c.handle(.selectCandidate(1))
        XCTAssertEqual(doc.text, "hello")
        XCTAssertTrue(c.candidates.isEmpty)
    }

    func testSpaceInsideWordDoesNotCorrectPrefix() {
        let doc = FakeDocument("helo", after: "world")
        composer(doc).handle(.space)
        XCTAssertEqual(doc.text, "helo world")
    }

    func testContextChangeWithMatchingSuffixDoesNotReuseOriginalCorrection() {
        let doc = FakeDocument("teh")
        let c = composer(doc)
        c.handle(.space)
        doc.before = "another the "
        c.handle(.contextChanged)
        XCTAssertTrue(c.candidates.isEmpty)
        c.handle(.selectCandidate(0))
        XCTAssertEqual(doc.text, "another the ")
    }

    func testStaleCandidateTapAfterExternalEditDoesNothing() {
        let doc = FakeDocument("hel")
        let c = composer(doc)
        c.handle(.contextChanged)
        doc.before = "wor"
        c.handle(.selectCandidate(1))
        XCTAssertEqual(doc.text, "wor")
    }

    func testSwitchingLanguageKeepsLearningWithOriginalCommit() {
        let doc = FakeDocument("teh")
        let personal = PersonalModel()
        let c = composer(doc, personal: personal)
        c.handle(.space)
        c.handle(.switchLanguage)
        c.handle(.swipe(.up))
        XCTAssertEqual(doc.text, "teh ")
        XCTAssertNil(personal.counts(for: .english).unigrams["the"])
        XCTAssertEqual(personal.counts(for: .english).unigrams["teh"], 1)
        XCTAssertTrue(personal.counts(for: .czech).isEmpty)
        c.handle(.swipe(.up))
        XCTAssertTrue(personal.isLearned("teh", language: .english))
        XCTAssertFalse(personal.isLearned("teh", language: .czech))
    }

    func testRecoveringWordDoesNotSubtractHistoricalUse() {
        let personal = PersonalModel()
        personal.note("world", after: nil, language: .english)
        let doc = FakeDocument("world ")
        let c = composer(doc, personal: personal)
        c.handle(.swipe(.down))
        XCTAssertNotEqual(doc.text, "world ")
        XCTAssertEqual(personal.counts(for: .english).unigrams["world"], 1)
        c.handle(.swipe(.up))
        XCTAssertEqual(doc.text, "world ")
        XCTAssertEqual(personal.counts(for: .english).unigrams["world"], 2)
    }

    func testRankingUsesCurrentCountsAfterVocabularyHasBeenCached() throws {
        let personal = PersonalModel()
        let corrector = Corrector(lexicon: TestLexicons.english)
        for _ in 0..<2 { personal.note("zorb", after: nil, language: .english) }
        _ = personal.prior(for: .english, previous: nil)
        for _ in 0..<18 { personal.note("zorb", after: nil, language: .english) }
        let context = CorrectionContext(personal: personal.prior(for: .english, previous: nil))
        let candidate = try XCTUnwrap(corrector.candidates(for: "zorb", context: context).first { $0.word == "zorb" })
        XCTAssertEqual(candidate.frequency, 80_000, accuracy: 1)
        XCTAssertEqual(candidate.score, 1 + 0.35 * log10(80_000), accuracy: 0.0001)
    }

    func testDecomposedAndComposedWordsHaveSameCorrectionCandidates() {
        let corrector = Corrector(lexicon: TestLexicons.czech)
        XCTAssertEqual(corrector.candidates(for: "de\u{030C}la\u{0301}m"), corrector.candidates(for: "dělám"))
    }

    func testSelectedTextIsNotTreatedAsAnEditableWordPrefix() {
        let doc = FakeDocument("teh")
        doc.selection = "chosen text"
        let c = composer(doc)
        c.handle(.contextChanged)
        c.handle(.selectCandidate(1))
        c.handle(.swipe(.down))
        XCTAssertEqual(doc.text, "teh")
        XCTAssertTrue(doc.deletions.isEmpty)
        XCTAssertTrue(c.candidates.isEmpty)
    }

    func testUnavailableContextDoesNotDisableBackspace() {
        let doc = FakeDocument()
        doc.contextAvailable = false
        let c = composer(doc)
        c.handle(.backspace)
        XCTAssertEqual(doc.deletions, [1])
        XCTAssertTrue(c.candidates.isEmpty)
    }

    func testIdenticalTextInDifferentDocumentDoesNotKeepCommit() {
        let doc = FakeDocument("teh")
        let c = composer(doc)
        c.handle(.space)
        doc.identifier = UUID()
        c.handle(.contextChanged)
        c.handle(.selectCandidate(0))
        XCTAssertEqual(doc.text, "the ")
        XCTAssertTrue(c.candidates.isEmpty)
    }

    func testOwnContextCallbackKeepsCorrection() {
        let doc = FakeDocument("teh")
        let c = composer(doc)
        c.handle(.space)
        c.handle(.contextChanged)
        c.handle(.swipe(.up))
        XCTAssertEqual(doc.text, "teh ")
    }

    func testSameLengthExternalWordDiscardsOldTouchSamples() {
        let doc = FakeDocument()
        let c = composer(doc)
        let confident = TouchSample(alternatives: [KeyProbability(character: "x", cost: 0)])
        for letter in "xxxx" { c.handle(.character(String(letter)), touch: confident) }
        doc.before = "helo"
        c.handle(.contextChanged)
        c.handle(.space)
        XCTAssertEqual(doc.text, "help ", "old confident taps would incorrectly prefer hello")
    }

    func testRankingAlsoTracksDecreasingCounts() throws {
        let personal = PersonalModel()
        for _ in 0..<20 { personal.note("zorb", after: nil, language: .english) }
        _ = personal.prior(for: .english, previous: nil)
        for _ in 0..<18 { personal.unnote("zorb", after: nil, language: .english) }
        let corrector = Corrector(lexicon: TestLexicons.english)
        let context = CorrectionContext(personal: personal.prior(for: .english, previous: nil))
        let candidate = try XCTUnwrap(corrector.candidates(for: "zorb", context: context).first { $0.word == "zorb" })
        XCTAssertEqual(candidate.frequency, 8_000, accuracy: 1)
    }

    func testHostCanDisableAutomaticCorrection() {
        let doc = FakeDocument("teh")
        doc.autocorrectionAllowed = false
        composer(doc).handle(.space)
        XCTAssertEqual(doc.text, "teh ")
    }

    func testMissingAfterContextAtEndOfDocumentStillAllowsCorrection() {
        let doc = FakeDocument("teh")
        doc.afterAvailable = false
        composer(doc).handle(.space)
        XCTAssertEqual(doc.text, "the ")
    }

    func testHostCapitalizationModesAreHonored() {
        for (mode, expected) in [(DocumentSnapshot.Capitalization.none, "hello world"),
                                 (.words, "Hello World"), (.allCharacters, "HELLO WORLD")] {
            let doc = FakeDocument()
            doc.capitalization = mode
            let c = Composer(document: doc, lexicons: TestLexicons.provider, languages: [.english])
            type("hello world", into: c)
            XCTAssertEqual(doc.text, expected)
        }
    }
}
