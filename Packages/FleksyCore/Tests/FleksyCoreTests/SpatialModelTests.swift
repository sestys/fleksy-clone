import XCTest
@testable import FleksyCore

final class SpatialModelTests: XCTestCase {
    /// Three 40x50 keys in a row, centred at x = 20, 60, 100.
    private func row(_ characters: [String]) -> SpatialModel {
        SpatialModel(keys: characters.enumerated().map { i, c in
            SpatialModel.KeyBox(character: c, centerX: Double(i) * 40 + 20, centerY: 25, width: 40, height: 50)
        })
    }

    func testADeadCentreTapHasNoAlternatives() {
        let model = row(["g", "h", "j"])
        let sample = model.sample(x: 60, y: 25, typed: "h")
        XCTAssertEqual(sample?.alternatives.map(\.character), ["h"])
        XCTAssertEqual(sample?.cost(of: "h"), 0)
        XCTAssertNil(sample?.cost(of: "g"))
    }

    func testATapOnTheBorderIsNearlyAmbiguous() throws {
        let model = row(["g", "h", "j"])
        // 1pt inside h, hard against the g/h border.
        let sample = try XCTUnwrap(model.sample(x: 41, y: 25, typed: "h"))
        let g = try XCTUnwrap(sample.cost(of: "g"))
        XCTAssertLessThan(g, 0.15, "a tap on the border should be cheap to reinterpret")
        XCTAssertGreaterThan(g, 0)
        XCTAssertNil(sample.cost(of: "j"), "the far key is still out of reach")
    }

    func testCostGrowsWithDistance() {
        let model = row(["g", "h", "j"])
        let near = model.sample(x: 45, y: 25, typed: "h")?.cost(of: "g")
        let far = model.sample(x: 55, y: 25, typed: "h")?.cost(of: "g")
        XCTAssertNotNil(near)
        // Further from g means a dearer reinterpretation, or none at all.
        XCTAssertTrue(far == nil || far! > near!)
    }

    func testTheReportedKeyIsAlwaysTheCheapestReading() {
        let model = row(["g", "h", "j"])
        for x in stride(from: 41.0, to: 79.0, by: 4) {
            let sample = model.sample(x: x, y: 25, typed: "h")
            XCTAssertEqual(sample?.alternatives.first?.character, "h", "at x=\(x)")
            XCTAssertEqual(sample?.alternatives.first?.cost, 0)
        }
    }

    func testAlternativesAreCapped() {
        var model = SpatialModel(keys: "qwertyuiop".enumerated().map { i, c in
            SpatialModel.KeyBox(character: String(c), centerX: Double(i) * 40 + 20, centerY: 25, width: 40, height: 50)
        })
        model.maxAlternatives = 3
        model.spread = 3   // deliberately vague, so everything is in reach
        let sample = model.sample(x: 220, y: 25, typed: "u")
        XCTAssertEqual(sample?.alternatives.count, 3)
        XCTAssertEqual(sample?.alternatives.first?.character, "u")
    }

    func testAnUnknownOrEmptyKeyYieldsNothing() {
        XCTAssertNil(row(["g", "h"]).sample(x: 20, y: 25, typed: "?"))
        XCTAssertNil(SpatialModel().sample(x: 0, y: 0, typed: "a"))
    }

    func testRowsAboveAndBelowAreReachable() {
        let model = SpatialModel(keys: [
            SpatialModel.KeyBox(character: "g", centerX: 20, centerY: 25, width: 40, height: 50),
            SpatialModel.KeyBox(character: "b", centerX: 20, centerY: 75, width: 40, height: 50),
        ])
        let low = model.sample(x: 20, y: 48, typed: "g")   // right at the row boundary
        XCTAssertNotNil(low?.cost(of: "b"))
        let high = model.sample(x: 20, y: 10, typed: "g")
        XCTAssertNil(high?.cost(of: "b"))
    }
}

/// The spatial model where it matters: whether it changes the correction.
final class SpatialCorrectionTests: XCTestCase {
    /// A QWERTY row layout roughly to scale for a 390pt-wide phone.
    private func qwerty() -> SpatialModel {
        var keys: [SpatialModel.KeyBox] = []
        let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
        let offsets = [0.0, 0.5, 1.5]
        for (r, letters) in rows.enumerated() {
            for (i, c) in letters.enumerated() {
                keys.append(SpatialModel.KeyBox(character: String(c),
                                                centerX: (Double(i) + offsets[r] + 0.5) * 39,
                                                centerY: Double(r) * 45 + 22.5,
                                                width: 39, height: 45))
            }
        }
        return SpatialModel(keys: keys)
    }

    /// Taps `word`, nudging the letter at `slip` towards the given neighbour.
    private func taps(_ word: String, model: SpatialModel, slip: Int? = nil, towards: String? = nil) -> [TouchSample?] {
        var samples: [TouchSample?] = []
        for (i, ch) in word.enumerated() {
            let c = String(ch)
            guard let key = model.keys.first(where: { $0.character == c }) else { samples.append(nil); continue }
            var x = key.centerX
            if i == slip, let towards, let other = model.keys.first(where: { $0.character == towards }) {
                x = (key.centerX + other.centerX) / 2   // halfway to the neighbour
            }
            samples.append(model.sample(x: x, y: key.centerY, typed: c))
        }
        return samples
    }

    func testASlippedTapIsCheapToCorrect() throws {
        let model = qwerty()
        let corrector = Corrector(lexicon: TestLexicons.english)
        // "worfs" typed with the f landing halfway towards d: "words" should be reachable.
        let slipped = taps("worfs", model: model, slip: 3, towards: "d")
        let context = CorrectionContext(touches: slipped)
        let withGeometry = corrector.candidates(for: "worfs", context: context)
        XCTAssertEqual(withGeometry.first?.word, "words")

        // The same letters tapped dead centre are a dearer correction.
        let centred = CorrectionContext(touches: taps("worfs", model: model))
        let confident = corrector.candidates(for: "worfs", context: centred)
        let slippedCost = try XCTUnwrap(withGeometry.first { $0.word == "words" }?.cost)
        let confidentCost = try XCTUnwrap(confident.first { $0.word == "words" }?.cost)
        XCTAssertLessThan(slippedCost, confidentCost)
    }

    func testGeometryIsIgnoredWhenItDoesNotMatchTheWord() {
        let model = qwerty()
        let corrector = Corrector(lexicon: TestLexicons.english)
        // Taps for a different, shorter word: the corrector must fall back to letters only.
        let mismatched = CorrectionContext(touches: taps("hi", model: model))
        XCTAssertEqual(corrector.candidates(for: "wprld", context: mismatched).first?.word,
                       corrector.candidates(for: "wprld").first?.word)
    }

    func testAKeyTheFingerWasNowhereNearIsNotTreatedAsAdjacent() throws {
        let model = qwerty()
        let corrector = Corrector(lexicon: TestLexicons.english)
        // "p" is a neighbour of "o" in the discrete table, so "wprld" -> "world" is cheap.
        let blind = try XCTUnwrap(corrector.candidates(for: "wprld").first { $0.word == "world" })

        // But if the p was tapped dead centre, the geometry says the finger was not near o.
        let confident = CorrectionContext(touches: taps("wprld", model: model))
        let seeing = try XCTUnwrap(corrector.candidates(for: "wprld", context: confident).first { $0.word == "world" },
                                   "still reachable, just dearer")
        XCTAssertGreaterThan(seeing.cost, blind.cost)
    }

    func testTapsFlowFromComposerIntoTheCorrection() {
        let model = qwerty()
        var settings = ComposerSettings()
        settings.autoCapitalize = false
        let doc = FakeDocument()
        let c = Composer(document: doc, lexicons: TestLexicons.provider, languages: [.english], settings: settings)
        // Type "worfs" with the f slipping towards d, one key at a time, then commit.
        let samples = taps("worfs", model: model, slip: 3, towards: "d")
        for (i, ch) in "worfs".enumerated() {
            c.handle(.character(String(ch)), touch: samples[i])
        }
        c.handle(.space)
        XCTAssertEqual(doc.text, "words ")
    }

    func testBackspaceKeepsTheTapsLinedUp() {
        let model = qwerty()
        var settings = ComposerSettings()
        settings.autoCapitalize = false
        let doc = FakeDocument()
        let c = Composer(document: doc, lexicons: TestLexicons.provider, languages: [.english], settings: settings)
        let samples = taps("worfs", model: model, slip: 3, towards: "d")
        for (i, ch) in "worfs".enumerated() {
            c.handle(.character(String(ch)), touch: samples[i])
        }
        c.handle(.backspace)                       // drop the s
        c.handle(.character("s"), touch: samples[4])
        c.handle(.space)
        XCTAssertEqual(doc.text, "words ", "the taps should still line up after an edit")
    }
}
