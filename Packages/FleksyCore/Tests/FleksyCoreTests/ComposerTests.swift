import XCTest
@testable import FleksyCore

final class ComposerTests: XCTestCase {
    func make(_ text: String = "", language: Language = .english, settings: ComposerSettings = ComposerSettings()) -> (Composer, FakeDocument) {
        let doc = FakeDocument(text)
        let c = Composer(document: doc, lexicons: TestLexicons.provider, languages: [.english, .czech], language: language, settings: settings)
        return (c, doc)
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
        // Typed word always leftmost, the correction next to it and selected.
        XCTAssertEqual(c.candidates[0].text, "teh")
        XCTAssertFalse(c.candidates[0].isSelected)
        XCTAssertEqual(c.candidates[1].text, "the")
        XCTAssertTrue(c.candidates[1].isSelected)
    }

    func testSwipeDownAndUpWalkCandidatesWithoutWrapping() {
        let (c, doc) = make()
        c.handle(.shiftTap)
        type("helo ", into: c)                             // fixture: "help" (adjacent key) and "hello"
        XCTAssertEqual(doc.text, "help ")
        let options = c.candidates.map(\.text)
        XCTAssertEqual(Array(options.prefix(3)), ["helo", "help", "hello"])
        c.handle(.swipe(.down))
        XCTAssertEqual(doc.text, "hello ")
        for _ in 0..<10 { c.handle(.swipe(.down)) }      // never wraps around to the typed word
        XCTAssertEqual(doc.text, options.last! + " ")
        for _ in 0..<(options.count - 1) { c.handle(.swipe(.up)) }
        XCTAssertEqual(doc.text, "helo ")                  // always ends at the typed word
        XCTAssertNil(c.notice)
        c.handle(.swipe(.down))
        XCTAssertEqual(doc.text, "help ")
    }

    func testSwipeUpBackToTypedWordKeepsCase() {
        let (c, doc) = make()
        type("Teh ", into: c)
        XCTAssertEqual(doc.text, "The ")
        c.handle(.swipe(.up))
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
        // After the auto period, swipes cycle punctuation (up wraps to the end of the cycle).
        c.handle(.swipe(.up))
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

    func testSwipeAfterPeriodCyclesPunctuation() {
        let (c, doc) = make()
        type("hello  ", into: c)
        XCTAssertEqual(doc.text, "Hello. ")
        XCTAssertEqual(c.candidates.map(\.text), Composer.punctuationCycle)
        XCTAssertTrue(c.candidates[0].isSelected)
        c.handle(.swipe(.down))
        XCTAssertEqual(doc.text, "Hello, ")
        XCTAssertEqual(c.shift, .off)
        c.handle(.swipe(.down))
        XCTAssertEqual(doc.text, "Hello! ")
        XCTAssertEqual(c.shift, .on)
        c.handle(.swipe(.up))
        XCTAssertEqual(doc.text, "Hello, ")
        c.handle(.swipe(.up))
        XCTAssertEqual(doc.text, "Hello. ")
        c.handle(.swipe(.up))
        XCTAssertEqual(doc.text, "Hello: ")
        c.handle(.selectCandidate(3))
        XCTAssertEqual(doc.text, "Hello? ")
        type("ok", into: c)
        XCTAssertEqual(doc.text, "Hello? Ok")
        c.handle(.swipe(.down))        // corrects the word being typed, not punctuation
        XCTAssertEqual(doc.text, "Hello? Ok")
    }

    func testRepeatedSpaceRepeatsTheMark() {
        let (c, doc) = make()
        type("hello   ", into: c)
        XCTAssertEqual(doc.text, "Hello.. ")
        c.handle(.swipe(.right))
        XCTAssertEqual(doc.text, "Hello... ")
        c.handle(.swipe(.down))
        XCTAssertEqual(doc.text, "Hello, ")
        c.handle(.space)
        XCTAssertEqual(doc.text, "Hello,, ")
        c.handle(.backspace)
        c.handle(.space)               // run broken by backspace: plain space
        XCTAssertEqual(doc.text, "Hello,, ")
    }

    func testSwipeUpAfterCorrectionRevertsThenLearns() {
        let store = PersonalModel()
        let doc = FakeDocument()
        let c = Composer(document: doc, lexicons: TestLexicons.provider, personal: store, languages: [.english], settings: ComposerSettings())
        c.handle(.shiftTap)
        type("wprld", into: c)
        c.handle(.swipe(.right))
        XCTAssertEqual(doc.text, "world ")
        c.handle(.swipe(.up))                  // restore what was typed
        XCTAssertEqual(doc.text, "wprld ")
        XCTAssertNil(c.notice)
        XCTAssertFalse(store.isLearned("wprld", language: .english))
        c.handle(.swipe(.up))                  // learn it
        XCTAssertEqual(doc.text, "wprld ")
        XCTAssertEqual(c.notice, "learned")
        XCTAssertTrue(store.isLearned("wprld", language: .english))
        c.handle(.swipe(.up))                  // forget it again
        XCTAssertEqual(doc.text, "wprld ")
        XCTAssertEqual(c.notice, "forgotten")
        XCTAssertFalse(store.isLearned("wprld", language: .english))
        c.handle(.swipe(.up))                  // and learn once more
        XCTAssertEqual(c.notice, "learned")
        XCTAssertTrue(store.isLearned("wprld", language: .english))
        c.handle(.swipe(.down))                    // back to the correction
        XCTAssertEqual(doc.text, "world ")
        XCTAssertNil(c.notice)
        c.handle(.swipe(.up))
        XCTAssertEqual(doc.text, "wprld ")
        c.handle(.swipe(.right))                 // swipe right is still the period
        XCTAssertEqual(doc.text, "wprld. ")

        // Learned words are never corrected again, also for a fresh composer sharing the store.
        type("wprld", into: c)
        c.handle(.swipe(.right))
        XCTAssertEqual(doc.text, "wprld. Wprld ")
        let doc2 = FakeDocument()
        let c2 = Composer(document: doc2, lexicons: TestLexicons.provider, personal: store, languages: [.english], settings: ComposerSettings())
        c2.handle(.shiftTap)
        type("wprld ", into: c2)
        XCTAssertEqual(doc2.text, "wprld ")
    }

    func testSwipeDownNeverReachesTypedWord() {
        let store = PersonalModel()
        let doc = FakeDocument()
        let c = Composer(document: doc, lexicons: TestLexicons.provider, personal: store, languages: [.english], settings: ComposerSettings())
        c.handle(.shiftTap)
        type("wprld ", into: c)
        for _ in 0..<10 {
            c.handle(.swipe(.down))
            XCTAssertNotEqual(doc.text, "wprld ")
            XCTAssertNil(c.notice)
        }
        XCTAssertFalse(store.isLearned("wprld", language: .english))
    }

    func testSwipeUpOnUncorrectedWordDoesNotLearn() {
        let store = PersonalModel()
        let doc = FakeDocument()
        let c = Composer(document: doc, lexicons: TestLexicons.provider, personal: store, languages: [.english], settings: ComposerSettings())
        c.handle(.shiftTap)
        type("hello ", into: c)
        c.handle(.swipe(.up))
        c.handle(.swipe(.up))
        XCTAssertNil(c.notice)
        XCTAssertFalse(store.isLearned("hello", language: .english))
    }

    func testSpaceTapAfterCorrectionStillMakesPeriod() {
        let (c, doc) = make()
        type("wprld  ", into: c)
        XCTAssertEqual(doc.text, "World. ")
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
        c.handle(.swipe(.up)) // commit is gone: nothing to cycle
        XCTAssertEqual(doc.text, "worl")
        c.handle(.swipe(.down)) // corrects the word being typed, no space
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
        c.handle(.swipe(.down))
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
        c.handle(.swipe(.up))
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
        c.handle(.swipe(.up))
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
        c.handle(.swipe(.down))
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

    func testSwipeDirectionCanBeInverted() {
        var s = ComposerSettings()
        s.swipeDownForNext = false           // original Fleksy direction
        let (c, doc) = make(settings: s)
        c.handle(.shiftTap)
        type("teh ", into: c)
        XCTAssertEqual(doc.text, "the ")
        c.handle(.swipe(.down))              // now walks back to the typed word
        XCTAssertEqual(doc.text, "teh ")
        c.handle(.swipe(.up))
        XCTAssertEqual(doc.text, "the ")
    }

    func testSwipeReachesBackToTheLastWordAfterTheCommitIsGone() {
        let (c, doc) = make()
        c.handle(.shiftTap)
        type("teh ", into: c)
        XCTAssertEqual(doc.text, "the ")
        c.handle(.contextChanged)
        c.handle(.character("x"))            // whatever dropped the commit
        c.handle(.backspace)
        XCTAssertEqual(doc.text, "the ")
        XCTAssertTrue(c.candidates.isEmpty)
        c.handle(.swipe(.up))                // reach back: the word and its options return
        XCTAssertEqual(doc.text, "the ")
        XCTAssertEqual(c.candidates.first?.text, "the")
        XCTAssertTrue(c.candidates.count > 1)
        c.handle(.swipe(.down))              // and can be walked again
        XCTAssertNotEqual(doc.text, "the ")
        c.handle(.swipe(.up))
        XCTAssertEqual(doc.text, "the ")
    }

    func testSwipeDoesNotReachBackAcrossANewline() {
        let (c, doc) = make("the\n")
        c.handle(.swipe(.up))
        c.handle(.swipe(.down))
        XCTAssertEqual(doc.text, "the\n")
    }

    func testSwipeReachesBackOverPunctuation() {
        let (c, doc) = make("hello world. ")
        c.handle(.swipe(.down))
        XCTAssertNotEqual(doc.text, "hello world. ")
        XCTAssertTrue(doc.text.hasPrefix("hello "))
        XCTAssertTrue(doc.text.hasSuffix(". "))
    }
}
