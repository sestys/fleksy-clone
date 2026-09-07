import XCTest
@testable import FleksyCore

/// An in-memory `PersonalStore`, standing in for the file the keyboard actually writes.
final class FakePersonalStore: PersonalStore {
    var saved: [Language: PersonalCounts]
    var saves = 0
    init(_ initial: [Language: PersonalCounts] = [:]) { saved = initial }
    func load() -> [Language: PersonalCounts] { saved }
    func save(_ counts: [Language: PersonalCounts]) { saved = counts; saves += 1 }
}

final class PersonalModelTests: XCTestCase {
    private func model(_ settings: PersonalModelSettings = PersonalModelSettings(),
                       store: PersonalStore? = nil) -> PersonalModel {
        PersonalModel(store: store, settings: settings)
    }

    // MARK: - Counting

    func testAWordUsedEnoughBecomesOfferable() {
        let m = model()
        XCTAssertNil(m.vocabulary(for: .english))
        m.note("fleksy", after: nil, language: .english)
        XCTAssertNil(m.vocabulary(for: .english), "one use is not enough to suggest a word back")
        m.note("fleksy", after: nil, language: .english)
        XCTAssertEqual(m.vocabulary(for: .english)?.allWords, ["fleksy"])
    }

    func testUnnoteTakesTheWordBackOut() {
        let m = model()
        m.note("fleksy", after: nil, language: .english)
        m.note("fleksy", after: nil, language: .english)
        XCTAssertEqual(m.vocabulary(for: .english)?.allWords, ["fleksy"])
        m.unnote("fleksy", after: nil, language: .english)
        XCTAssertNil(m.vocabulary(for: .english))
    }

    func testCountsNeverGoNegative() {
        let m = model()
        m.unnote("nope", after: "a", language: .english)
        XCTAssertTrue(m.counts(for: .english).isEmpty)
    }

    func testLanguagesAreKeptApart() {
        let m = model()
        m.note("dělám", after: nil, language: .czech)
        m.note("dělám", after: nil, language: .czech)
        XCTAssertEqual(m.vocabulary(for: .czech)?.allWords, ["dělám"])
        XCTAssertNil(m.vocabulary(for: .english))
    }

    func testNonWordsAreNotRecorded() {
        let m = model()
        for _ in 0..<4 { m.note("a1b", after: nil, language: .english) }
        XCTAssertTrue(m.counts(for: .english).isEmpty)
    }

    // MARK: - Explicit learning

    func testALearnedWordIsOfferedWithoutWaiting() {
        let m = model()
        m.learn("Fleksy", language: .english)
        XCTAssertEqual(m.vocabulary(for: .english)?.allWords, ["fleksy"])
        XCTAssertTrue(m.prior(for: .english, previous: nil).isLearned("FLEKSY"))
        m.forget("fleksy", language: .english)
        XCTAssertNil(m.vocabulary(for: .english))
    }

    // MARK: - Context

    func testTheBigramPriorIsScopedToThePrecedingWord() {
        let m = model()
        m.note("meeting", after: "the", language: .english)
        m.note("meeting", after: "the", language: .english)
        m.note("weather", after: "the", language: .english)
        m.note("elsewhere", after: "went", language: .english)

        let afterThe = m.prior(for: .english, previous: "the")
        XCTAssertGreaterThan(afterThe.contextBoost(for: "meeting"), afterThe.contextBoost(for: "weather"))
        XCTAssertEqual(afterThe.contextBoost(for: "elsewhere"), 0)

        let afterWent = m.prior(for: .english, previous: "went")
        XCTAssertEqual(afterWent.contextBoost(for: "meeting"), 0)
        XCTAssertGreaterThan(afterWent.contextBoost(for: "elsewhere"), 0)

        XCTAssertEqual(m.prior(for: .english, previous: nil).contextBoost(for: "meeting"), 0)
    }

    func testPersonalFrequencyIsComparableWithCorpusFrequency() {
        var settings = PersonalModelSettings()
        settings.scale = 4000
        let m = model(settings)
        m.note("fleksy", after: nil, language: .english)
        m.note("fleksy", after: nil, language: .english)
        let prior = m.prior(for: .english, previous: nil)
        XCTAssertEqual(prior.personalFrequency(of: "fleksy"), 8000, accuracy: 1)
        XCTAssertEqual(prior.personalFrequency(of: "unseen"), 0)
    }

    // MARK: - Ageing

    func testCountsDecayAndArePruned() {
        var counts = PersonalCounts()
        counts.unigrams = ["fresh": 40, "stale": 1]
        counts.bigrams = ["the": ["fresh": 40]]
        counts.decayedAt = Date().addingTimeInterval(-120 * 86_400) // two half-lives
        let store = FakePersonalStore([.english: counts])

        let m = model(PersonalModelSettings(), store: store)
        let after = m.counts(for: .english)
        XCTAssertEqual(after.unigrams["fresh"] ?? 0, 10, accuracy: 0.1, "40 halved twice")
        XCTAssertNil(after.unigrams["stale"], "a count that decays below the floor is dropped")
        XCTAssertEqual(after.pairCount("the", "fresh"), 10, accuracy: 0.1)
    }

    func testFreshCountsAreLeftAlone() {
        var counts = PersonalCounts()
        counts.unigrams = ["today": 5]
        let m = model(PersonalModelSettings(), store: FakePersonalStore([.english: counts]))
        XCTAssertEqual(m.counts(for: .english).unigrams["today"], 5)
    }

    func testTheStoresAreCapped() {
        var settings = PersonalModelSettings()
        settings.maxWords = 10
        settings.maxPairs = 5
        var counts = PersonalCounts()
        for i in 0..<50 { counts.unigrams["word\(i)"] = Float(i) }
        for i in 0..<50 { counts.bigrams["a", default: [:]]["w\(i)"] = Float(i) }
        counts.decayedAt = Date().addingTimeInterval(-2 * 86_400)
        let m = model(settings, store: FakePersonalStore([.english: counts]))
        let after = m.counts(for: .english)
        XCTAssertEqual(after.unigrams.count, 10)
        XCTAssertEqual(after.pairTotal, 5)
        XCTAssertNotNil(after.unigrams["word49"], "the most used entries are the ones kept")
        XCTAssertNil(after.unigrams["word0"])
    }

    // MARK: - Persistence

    func testCountsAreWrittenOutAndReadBack() {
        let store = FakePersonalStore()
        let m = model(PersonalModelSettings(), store: store)
        m.saveEvery = 2
        m.note("fleksy", after: "using", language: .english)
        XCTAssertEqual(store.saves, 0, "writing on every keystroke would be wasteful")
        m.note("fleksy", after: "using", language: .english)
        XCTAssertEqual(store.saves, 1)

        let reloaded = model(PersonalModelSettings(), store: store)
        XCTAssertEqual(reloaded.counts(for: .english).unigrams["fleksy"], 2)
        XCTAssertEqual(reloaded.vocabulary(for: .english)?.allWords, ["fleksy"])
    }

    func testLegacyLearnedWordsAreAdopted() {
        let store = FakePersonalStore()
        let m = model(PersonalModelSettings(), store: store)
        m.adoptLegacyLearnedWords([("wprld", .english), ("nazdar", .czech)])
        XCTAssertTrue(m.isLearned("wprld", language: .english))
        XCTAssertTrue(m.isLearned("nazdar", language: .czech))
        XCTAssertEqual(store.saves, 1)
        m.adoptLegacyLearnedWords([("wprld", .english)])
        XCTAssertEqual(store.saves, 1, "adopting the same words twice writes nothing")
    }

    func testCountsSurviveACodableRoundTrip() throws {
        var counts = PersonalCounts()
        counts.unigrams = ["fleksy": 3]
        counts.bigrams = ["using": ["fleksy": 2]]
        counts.learned = ["fleksy"]
        let data = try JSONEncoder().encode([Language.english: counts])
        let back = try JSONDecoder().decode([Language: PersonalCounts].self, from: data)
        XCTAssertEqual(back[.english], counts)
    }
}

/// The personal model seen through the corrector and composer, which is where it has
/// to actually change what the user gets.
final class PersonalCorrectionTests: XCTestCase {
    private func composer(_ personal: PersonalModel, _ doc: FakeDocument) -> Composer {
        var settings = ComposerSettings()
        settings.autoCapitalize = false   // not what these tests are about
        return Composer(document: doc, lexicons: TestLexicons.provider, personal: personal,
                        languages: [.english], settings: settings)
    }

    func testAWordYouInventedIsOfferedOnceYouHaveUsedIt() {
        let personal = PersonalModel()
        let corrector = Corrector(lexicon: TestLexicons.english)
        // "sest" is not in the lexicon and is one edit from "test".
        XCTAssertFalse(corrector.candidates(for: "sest").contains { $0.word == "sestak" })
        for _ in 0..<3 { personal.note("sestak", after: nil, language: .english) }
        let context = CorrectionContext(personal: personal.prior(for: .english, previous: nil))
        XCTAssertTrue(corrector.candidates(for: "sestk", context: context).contains { $0.word == "sestak" })
    }

    func testAOneOffTypoIsNeverSuggestedBack() {
        let personal = PersonalModel()
        personal.note("wrold", after: nil, language: .english)
        let corrector = Corrector(lexicon: TestLexicons.english)
        let context = CorrectionContext(personal: personal.prior(for: .english, previous: nil))
        XCTAssertFalse(corrector.candidates(for: "wrold", context: context).contains { $0.word == "wrold" })
        XCTAssertEqual(corrector.candidates(for: "wrold", context: context).first?.word, "world")
    }

    func testContextPicksBetweenTwoPlausibleWords() {
        let corrector = Corrector(lexicon: TestLexicons.english)
        // "helo" is one adjacent-key edit from "help" (o/p are neighbours) and one
        // insertion from "hello". On lexicon frequency alone, the cheaper edit wins.
        XCTAssertEqual(corrector.candidates(for: "helo").first?.word, "help")

        // Give both words the same personal usage, so only the pair counts differ and
        // the test is about context rather than about how often a word is typed at all.
        let personal = PersonalModel()
        for _ in 0..<3 {
            personal.note("hello", after: "and", language: .english)
            personal.note("help", after: "please", language: .english)
        }
        func best(after previous: String) -> String? {
            let context = CorrectionContext(personal: personal.prior(for: .english, previous: previous))
            return corrector.candidates(for: "helo", context: context).first?.word
        }
        XCTAssertEqual(best(after: "and"), "hello", "context should overturn the cheaper edit")
        XCTAssertEqual(best(after: "please"), "help")
        XCTAssertEqual(best(after: "the"), "help", "with no pair either way, the cheaper edit stands")
    }

    func testUsingAWordOftenLiftsItEverywhereNotJustInContext() {
        let corrector = Corrector(lexicon: TestLexicons.english)
        XCTAssertEqual(corrector.candidates(for: "helo").first?.word, "help")
        let personal = PersonalModel()
        for _ in 0..<3 { personal.note("hello", after: "and", language: .english) }
        // The pair was only ever "and hello", but the word count is not position-bound.
        let elsewhere = CorrectionContext(personal: personal.prior(for: .english, previous: "the"))
        XCTAssertEqual(corrector.candidates(for: "helo", context: elsewhere).first?.word, "hello")
    }

    func testAWordYouTypeOftenStopsBeingCorrectedAway() {
        let personal = PersonalModel()
        let doc = FakeDocument()
        let c = composer(personal, doc)
        // First time through it is corrected: the keyboard has never seen it.
        type("wprld ", into: c)
        XCTAssertEqual(doc.text, "world ")

        for _ in 0..<12 { personal.note("wprld", after: nil, language: .english) }
        let doc2 = FakeDocument()
        let c2 = composer(personal, doc2)
        type("wprld ", into: c2)
        XCTAssertEqual(doc2.text, "wprld ", "a word used this often is the user's, not a typo")
    }

    func testTypingRecordsWordsAndThePairsTheyFormed() {
        let personal = PersonalModel()
        let doc = FakeDocument()
        let c = composer(personal, doc)
        type("hello world ", into: c)
        let counts = personal.counts(for: .english)
        XCTAssertEqual(counts.unigrams["hello"], 1)
        XCTAssertEqual(counts.unigrams["world"], 1)
        XCTAssertEqual(counts.pairCount("hello", "world"), 1)
    }

    func testPairsDoNotSpanASentenceBoundary() {
        let personal = PersonalModel()
        let doc = FakeDocument()
        let c = composer(personal, doc)
        type("hello. world ", into: c)
        let counts = personal.counts(for: .english)
        XCTAssertEqual(counts.unigrams["world"], 1)
        XCTAssertEqual(counts.pairCount("hello", "world"), 0)
    }

    func testSwappingACommittedWordMovesTheCount() {
        let personal = PersonalModel()
        let doc = FakeDocument()
        let c = composer(personal, doc)
        type("the wprld ", into: c)
        XCTAssertEqual(doc.text, "the world ")
        XCTAssertEqual(personal.counts(for: .english).unigrams["world"], 1)

        c.handle(.swipe(.up))               // back to what was typed
        XCTAssertEqual(doc.text, "the wprld ")
        let counts = personal.counts(for: .english)
        XCTAssertNil(counts.unigrams["world"], "the rejected correction should not be counted")
        XCTAssertEqual(counts.unigrams["wprld"], 1)
        XCTAssertEqual(counts.pairCount("the", "wprld"), 1)
        XCTAssertEqual(counts.pairCount("the", "world"), 0)
    }
}
