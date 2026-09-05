import XCTest
@testable import FleksyCore

final class ComposerTests: XCTestCase {
    func make(_ text: String = "", language: Language = .english, settings: ComposerSettings = ComposerSettings()) -> (Composer, FakeDocument) {
        let doc = FakeDocument(text)
        let c = Composer(document: doc, lexicons: TestLexicons.provider, languages: [.english, .czech], language: language, settings: settings)
        return (c, doc)
    }

    func type(_ s: String, into c: Composer) {
        for ch in s {
            if ch == " " { c.handle(.space) } else { c.handle(.character(String(ch))) }
        }
    }

    func testTypingAndAutoCapitalization() {
        let (c, doc) = make()
        XCTAssertEqual(c.shift, .on)
        type("hello world", into: c)
        XCTAssertEqual(doc.text, "Hello world")
        XCTAssertEqual(c.shift, .off)
    }

    func testAutocorrectOnSpace() {
        let (c, doc) = make()
        c.handle(.shiftTap) // turn off auto-cap
        type("teh ", into: c)
        XCTAssertEqual(doc.text, "the ")
        XCTAssertEqual(c.candidates.first?.text, "the")
        XCTAssertTrue(c.candidates.first!.isSelected)
        XCTAssertEqual(c.candidates.last?.text, "teh")
    }

    func testSwipeUpAndDownCycleCandidates() {
        let (c, doc) = make()
        c.handle(.shiftTap)
        type("hlelo ", into: c)
        XCTAssertEqual(doc.text, "hello ")
        c.handle(.swipe(.up))
        XCTAssertNotEqual(doc.text, "hello ")
        XCTAssertTrue(doc.text.hasSuffix(" "))
        let second = doc.text
        c.handle(.swipe(.down))
        XCTAssertEqual(doc.text, "hello ")
        c.handle(.swipe(.down)) // wraps to the original typed word
        XCTAssertEqual(doc.text, "hlelo ")
        c.handle(.swipe(.up))
        XCTAssertEqual(doc.text, "hello ")
        c.handle(.swipe(.up))
        XCTAssertEqual(doc.text, second)
    }

    func testSwipeUpKeepsCase() {
        let (c, doc) = make()
        type("Teh ", into: c)
        XCTAssertEqual(doc.text, "The ")
        c.handle(.swipe(.down))
        XCTAssertEqual(doc.text, "Teh ")
    }

    func testSwipeRightInsertsSpaceAndCorrects() {
        let (c, doc) = make()
        c.handle(.shiftTap)
        type("wprld", into: c)
        c.handle(.swipe(.right))
        XCTAssertEqual(doc.text, "world ")
    }

    func testDoubleSwipeRightMakesPeriodAndCapitalizes() {
        let (c, doc) = make()
        type("hello", into: c)
        c.handle(.swipe(.right))
        c.handle(.swipe(.right))
        XCTAssertEqual(doc.text, "Hello. ")
        XCTAssertEqual(c.shift, .on)
        // After the auto period, swipes cycle punctuation (down wraps to the end of the cycle).
        c.handle(.swipe(.down))
        XCTAssertEqual(doc.text, "Hello: ")
    }

    func testSpaceAfterOtherGestureStillMakesPeriod() {
        let (c, doc) = make("Hello world ")
        c.handle(.swipe(.left))
        XCTAssertEqual(doc.text, "Hello ")
        c.handle(.swipe(.right))
        XCTAssertEqual(doc.text, "Hello. ")
        c.handle(.swipe(.right))            // another space repeats the mark
        XCTAssertEqual(doc.text, "Hello.. ")
    }

    func testSwipeUpAfterPeriodCyclesPunctuation() {
        let (c, doc) = make()
        type("hello  ", into: c)
        XCTAssertEqual(doc.text, "Hello. ")
        XCTAssertEqual(c.candidates.map(\.text), Composer.punctuationCycle)
        XCTAssertTrue(c.candidates[0].isSelected)
        c.handle(.swipe(.up))
        XCTAssertEqual(doc.text, "Hello, ")
        XCTAssertEqual(c.shift, .off)
        c.handle(.swipe(.up))
        XCTAssertEqual(doc.text, "Hello! ")
        XCTAssertEqual(c.shift, .on)
        c.handle(.swipe(.down))
        XCTAssertEqual(doc.text, "Hello, ")
        c.handle(.swipe(.down))
        XCTAssertEqual(doc.text, "Hello. ")
        c.handle(.swipe(.down))
        XCTAssertEqual(doc.text, "Hello: ")
        c.handle(.selectCandidate(3))
        XCTAssertEqual(doc.text, "Hello? ")
        type("ok", into: c)
        XCTAssertEqual(doc.text, "Hello? Ok")
        c.handle(.swipe(.up))          // corrects the word being typed, not punctuation
        XCTAssertEqual(doc.text, "Hello? Ok")
    }

    func testRepeatedSpaceRepeatsTheMark() {
        let (c, doc) = make()
        type("hello   ", into: c)
        XCTAssertEqual(doc.text, "Hello.. ")
        c.handle(.swipe(.right))
        XCTAssertEqual(doc.text, "Hello... ")
        c.handle(.swipe(.up))
        XCTAssertEqual(doc.text, "Hello, ")
        c.handle(.space)
        XCTAssertEqual(doc.text, "Hello,, ")
        c.handle(.backspace)
        c.handle(.space)               // run broken by backspace: plain space
        XCTAssertEqual(doc.text, "Hello,, ")
    }

    func testDoubleSpaceMakesPeriod() {
        let (c, doc) = make()
        type("hello  ", into: c)
        XCTAssertEqual(doc.text, "Hello. ")
        type("world", into: c)
        XCTAssertEqual(doc.text, "Hello. World")
    }

    func testSwipeLeftDeletesWord() {
        let (c, doc) = make("hello world ")
        c.handle(.swipe(.left))
        XCTAssertEqual(doc.text, "hello ")
        c.handle(.swipe(.left))
        XCTAssertEqual(doc.text, "")
        c.handle(.swipe(.left))
        XCTAssertEqual(doc.text, "")
    }

    func testSwipeLeftDeletesPunctuation() {
        let (c, doc) = make("hello. ")
        c.handle(.swipe(.left))
        XCTAssertEqual(doc.text, "hello")
    }

    func testBackspaceInvalidatesCommit() {
        let (c, doc) = make()
        c.handle(.shiftTap)
        type("wprld ", into: c)
        XCTAssertEqual(doc.text, "world ")
        c.handle(.backspace)
        c.handle(.backspace)
        XCTAssertEqual(doc.text, "worl")
        c.handle(.swipe(.down)) // commit is gone: nothing to cycle
        XCTAssertEqual(doc.text, "worl")
        c.handle(.swipe(.up)) // corrects the word being typed, no space
        XCTAssertEqual(doc.text, "world")
    }

    func testCompletionsWhileTyping() {
        let (c, _) = make()
        c.handle(.shiftTap)
        type("wor", into: c)
        XCTAssertEqual(c.candidates.map(\.text), ["wor", "world", "word"])
        XCTAssertTrue(c.candidates[0].isSelected)
    }

    func testSelectCompletionInsertsWordAndSpace() {
        let (c, doc) = make()
        c.handle(.shiftTap)
        type("wor", into: c)
        c.handle(.selectCandidate(1))
        XCTAssertEqual(doc.text, "world ")
        c.handle(.swipe(.up))
        XCTAssertEqual(doc.text, "wor ")
    }

    func testSelectCandidateAfterCommit() {
        let (c, doc) = make()
        c.handle(.shiftTap)
        type("teh ", into: c)
        let idx = c.candidates.firstIndex { $0.text == "teh" }!
        c.handle(.selectCandidate(idx))
        XCTAssertEqual(doc.text, "teh ")
    }

    func testPunctuationCommits() {
        let (c, doc) = make()
        c.handle(.shiftTap)
        type("teh", into: c)
        c.handle(.character(","))
        XCTAssertEqual(doc.text, "the,")
        c.handle(.swipe(.down))
        XCTAssertEqual(doc.text, "teh,")
    }

    func testCzechDiacriticsCorrection() {
        let (c, doc) = make(language: .czech)
        type("ahoj jak se mas ", into: c)
        XCTAssertEqual(doc.text, "Ahoj jak se máš ")
        type("delam", into: c)
        c.handle(.swipe(.right))
        XCTAssertEqual(doc.text, "Ahoj jak se máš dělám ")
    }

    func testDiacriticRestorationBeatsAccentlessDictionaryEntry() {
        let (c, doc) = make(language: .czech)
        c.handle(.shiftTap)
        type("dekuji ", into: c)
        XCTAssertEqual(doc.text, "děkuji ")
        c.handle(.swipe(.down))
        XCTAssertEqual(doc.text, "dekuji ")
    }

    func testLanguageSwitchChangesCorrection() {
        let (c, doc) = make(language: .english)
        var switched: Language?
        c.onLanguageChange = { switched = $0 }
        c.handle(.switchLanguage)
        XCTAssertEqual(c.language, .czech)
        XCTAssertEqual(switched, .czech)
        c.handle(.shiftTap)
        type("dobre ", into: c)
        XCTAssertEqual(doc.text, "dobře ")
        c.handle(.switchLanguage)
        XCTAssertEqual(c.language, .english)
    }

    func testShiftAndCapsLock() {
        let (c, doc) = make()
        c.handle(.shiftTap)
        XCTAssertEqual(c.shift, .off)
        c.handle(.shiftDoubleTap)
        XCTAssertEqual(c.shift, .locked)
        type("hi ", into: c)
        XCTAssertEqual(doc.text, "HI ")
        XCTAssertEqual(c.shift, .locked)
    }

    func testAutocorrectDisabled() {
        var s = ComposerSettings()
        s.autocorrect = false
        let (c, doc) = make(settings: s)
        c.handle(.shiftTap)
        type("teh ", into: c)
        XCTAssertEqual(doc.text, "teh ")
        c.handle(.swipe(.up))
        XCTAssertEqual(doc.text, "the ")
    }

    func testEnterCommits() {
        let (c, doc) = make()
        c.handle(.shiftTap)
        type("teh", into: c)
        c.handle(.enter)
        XCTAssertEqual(doc.text, "the\n")
        XCTAssertEqual(c.shift, .on)
    }
}
