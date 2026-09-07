import XCTest
@testable import FleksyCore

/// Uses the real bundled word lists from Resources/Dictionaries (found relative to this file).
final class RealLexiconTests: XCTestCase {
    static func load(_ lang: Language) -> Lexicon? {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        func read(_ resource: String) -> String? {
            try? String(contentsOf: root.appendingPathComponent("Resources/Dictionaries/\(resource).txt"),
                        encoding: .utf8)
        }
        guard let words = read(lang.lexiconResource) else { return nil }
        return Lexicon(language: lang, texts: [words, read(lang.namesResource)].compactMap { $0 })
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

    /// A keyboard extension is killed without warning past roughly 50 MB, and both
    /// languages are loaded at once. Measuring the process footprint here reads as noise
    /// because earlier tests leave reusable pages behind, so assert on the buffers
    /// themselves: they are the entire cost of a lexicon by design.
    func testLexiconMemoryFootprint() throws {
        let lex = try XCTUnwrap(RealLexiconTests.load(.czech))
        let mb = Double(lex.storageBytes) / 1_048_576
        print("czech lexicon storage: \(String(format: "%.2f", mb)) MB for \(lex.count) words")
        // ~4.4 MB as built. The array-per-word layout this replaced cost ~17 MB.
        XCTAssertLessThan(mb, 6.0, "lexicon storage regressed to \(mb) MB")
        // Guard the shape too: a regression to per-word arrays would not show up above.
        XCTAssertLessThan(lex.storageBytes / lex.count, 100, "bytes per word regressed")
    }

    // MARK: - Names

    /// The bundled lists come from film subtitles, so they knew the names that get said
    /// in films and little else. Czech fared worst: every one of these was mangled.
    func testCzechNamesSurviveAutocorrect() throws {
        let lex = try XCTUnwrap(RealLexiconTests.load(.czech))
        let c = Corrector(lexicon: lex)
        let names = ["novák", "nováková", "novotný", "dvořák", "kučera", "horák", "šesták",
                     "svoboda", "černý", "procházka", "matěj", "ondřej", "vojtěch", "kryštof",
                     "štěpán", "zdeněk", "miloš", "radek", "adéla", "barbora", "markéta",
                     "šárka", "hana", "kateřina", "tereza", "eliška"]
        for name in names {
            XCTAssertTrue(lex.contains(name), "\(name) is not in the list")
            let corrected = Composer.correction(for: name, candidates: c.candidates(for: name), corrector: c)
            XCTAssertNil(corrected, "\(name) was corrected to \(corrected?.word ?? "")")
        }
    }

    /// Typing a name without its diacritics should reach the properly spelled one.
    func testCzechNamesAreReachedWithoutDiacritics() throws {
        let lex = try XCTUnwrap(RealLexiconTests.load(.czech))
        let c = Corrector(lexicon: lex)
        for (typed, expected) in [("novak", "novák"), ("dvorak", "dvořák"), ("kucera", "kučera"),
                                  ("sestak", "šesták"), ("matej", "matěj"), ("adela", "adéla")] {
            let chosen = Composer.correction(for: typed, candidates: c.candidates(for: typed), corrector: c)?.word
            XCTAssertEqual(chosen, expected, "\(typed)")
        }
    }

    /// The other half of the bargain. A name must never outrank an ordinary word it
    /// happens to fold onto, or adding names would break normal typing: Dostal is a
    /// surname but "dostal" is the past tense of "get", and sakra, nic and pan are words
    /// long before they are anybody's name.
    func testOrdinaryWordsAreNotCorrectedIntoNames() throws {
        let lex = try XCTUnwrap(RealLexiconTests.load(.czech))
        let c = Corrector(lexicon: lex)
        for word in ["nic", "sakra", "dostal", "dostala", "pan", "pana", "nad", "stane",
                     "copak", "cesta", "sen", "stal", "kolik", "lety", "holku", "hana"] {
            let corrected = Composer.correction(for: word, candidates: c.candidates(for: word), corrector: c)
            XCTAssertNil(corrected, "\(word) was corrected to \(corrected?.word ?? "")")
        }
    }

    func testEnglishNamesSurviveAutocorrect() throws {
        let lex = try XCTUnwrap(RealLexiconTests.load(.english))
        let c = Corrector(lexicon: lex)
        for name in ["vazquez", "obrien", "espinoza", "pham", "nguyen", "mcdaniel", "huynh",
                     "smith", "johnson", "patel", "kowalski", "novak"] {
            XCTAssertTrue(lex.contains(name), "\(name) is not in the list")
            let corrected = Composer.correction(for: name, candidates: c.candidates(for: name), corrector: c)
            XCTAssertNil(corrected, "\(name) was corrected to \(corrected?.word ?? "")")
        }
    }

    /// The word lists still have to win where the two sources disagree.
    func testTheWordListOutranksTheNameList() throws {
        let lex = try XCTUnwrap(RealLexiconTests.load(.czech))
        for word in ["se", "to", "je", "na", "nic"] {
            XCTAssertGreaterThan(lex.frequency(of: word), 100_000, "\(word) lost its frequency")
        }
    }

    func testLoadSpeed() throws {
        let start = Date()
        _ = try XCTUnwrap(RealLexiconTests.load(.czech))
        print("lexicon load time: \(Int(Date().timeIntervalSince(start) * 1000)) ms")
    }
}
