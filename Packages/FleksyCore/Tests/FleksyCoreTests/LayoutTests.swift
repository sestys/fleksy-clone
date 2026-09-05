import XCTest
@testable import FleksyCore

final class LayoutTests: XCTestCase {
    func testEnglishLettersIsQwerty() {
        let l = Layouts.letters(for: .english)
        XCTAssertEqual(l.rows.count, 4)
        XCTAssertEqual(l.rows[0].map(\.label).joined(), "qwertyuiop")
        XCTAssertEqual(l.rows[2].first?.action, .shift)
        XCTAssertEqual(l.rows[2].last?.action, .backspace)
    }

    func testCzechLettersIsQwertzWithAccents() {
        let l = Layouts.letters(for: .czech)
        XCTAssertEqual(l.rows[0].map(\.label).joined(), "qwertzuiop")
        let e = l.rows[0].first { $0.label == "e" }!
        XCTAssertEqual(e.accents, ["ě", "é"])
        let u = l.rows[0].first { $0.label == "u" }!
        XCTAssertEqual(u.accents, ["ů", "ú"])
    }

    func testCzechQwertyOverride() {
        let l = Layouts.letters(for: .czech, qwertz: false)
        XCTAssertEqual(l.rows[0].map(\.label).joined(), "qwertyuiop")
    }

    func testBottomRowHasSpaceWithLanguageName() {
        let l = Layouts.letters(for: .czech)
        let space = l.rows[3].first { $0.action == .space }!
        XCTAssertEqual(space.label, "Čeština")
        XCTAssertEqual(l.rowWidth(3), 10, accuracy: 0.001)
    }

    func testAllRowsFitTenUnits() {
        for lang in Language.allCases {
            for layer in [KeyboardLayer.letters, .numbers, .symbols] {
                let l = Layouts.layout(layer: layer, language: lang)
                XCTAssertEqual(l.maxRowWidth, 10, accuracy: 0.001, "\(lang) \(layer)")
                for i in 0..<l.rows.count {
                    XCTAssertLessThanOrEqual(l.rowWidth(i), 10.001, "\(lang) \(layer) row \(i)")
                }
            }
        }
    }

    func testNeighbourMap() {
        let n = Layouts.neighbourMap(for: .english)
        XCTAssertTrue(n["g"]!.contains("h"))
        XCTAssertTrue(n["g"]!.contains("t"))
        XCTAssertTrue(n["g"]!.contains("y"))
        XCTAssertTrue(n["g"]!.contains("v"))
        XCTAssertTrue(n["g"]!.contains("b"))
        XCTAssertFalse(n["g"]!.contains("k"))
        XCTAssertFalse(n["q"]!.contains("z"))
        let cz = Layouts.neighbourMap(for: .czech)
        XCTAssertTrue(cz["a"]!.contains("y"))  // qwertz: y is below a
    }
}
