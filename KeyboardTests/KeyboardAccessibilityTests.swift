import XCTest
import UIKit
import FleksyCore

@MainActor
final class KeyboardAccessibilityTests: XCTestCase {
    private final class Delegate: KeyboardViewDelegate, CandidateBarDelegate {
        var actions: [KeyAction] = []
        var candidates: [Int] = []
        func keyboardView(_ view: KeyboardView, didTap key: Key, at touch: TouchSample?) { actions.append(key.action) }
        func keyboardViewDidDoubleTapShift(_ view: KeyboardView) {}
        func keyboardView(_ view: KeyboardView, didSwipe direction: SwipeDirection, fingers: Int, startedOn key: Key?) {}
        func keyboardView(_ view: KeyboardView, didPickAccent accent: String) { actions.append(.character(accent)) }
        func keyboardView(_ view: KeyboardView, globeTouched event: UIEvent?) {}
        func keyboardViewDidActivateGlobe(_ view: KeyboardView) { actions.append(.globe) }
        func candidateBar(_ bar: CandidateBarView, didSelect index: Int) { candidates.append(index) }
        func candidateBarDidTapSettings(_ bar: CandidateBarView) {}
    }

    func testAccessibilityActivationTypesKeyAndGlobe() throws {
        let view = KeyboardView(layout: Layouts.layout(layer: .letters, language: .english), theme: .classic)
        let delegate = Delegate()
        view.delegate = delegate
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 216)
        view.layoutIfNeeded()
        let keys = try XCTUnwrap(view.accessibilityElements as? [UIAccessibilityElement])
        let letter = try XCTUnwrap(keys.first { $0.accessibilityIdentifier == "key_a" })
        XCTAssertTrue(letter.accessibilityActivate())
        let globe = try XCTUnwrap(keys.first { $0.accessibilityIdentifier == "key_globe" })
        XCTAssertTrue(globe.accessibilityActivate())
        XCTAssertEqual(delegate.actions, [.character("a"), .globe])
    }

    func testShiftAccessibilityTracksState() throws {
        let view = KeyboardView(layout: Layouts.layout(layer: .letters, language: .english), theme: .classic)
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 216)
        view.layoutIfNeeded()
        view.shift = .locked
        let keys = try XCTUnwrap(view.accessibilityElements as? [UIAccessibilityElement])
        XCTAssertEqual(keys.first { $0.accessibilityIdentifier == "key_shift" }?.accessibilityValue, "Caps lock")
        XCTAssertEqual(keys.first { $0.accessibilityIdentifier == "key_a" }?.accessibilityLabel, "A")
    }

    func testNoticeCannotActivateHiddenCandidate() throws {
        let bar = CandidateBarView(theme: .classic)
        let delegate = Delegate()
        bar.delegate = delegate
        let items = [CandidateItem(text: "typed", isSelected: true), CandidateItem(text: "other", isSelected: false)]
        bar.update(items: items, languageHint: "English", notice: nil)
        let stack = try XCTUnwrap(bar.subviews.compactMap { $0 as? UIStackView }.first)
        let candidate = try XCTUnwrap(stack.arrangedSubviews.first)
        XCTAssertTrue(candidate.accessibilityActivate())
        XCTAssertEqual(delegate.candidates, [0])
        bar.update(items: items, languageHint: "English", notice: "learned")
        XCTAssertFalse(candidate.accessibilityActivate())
        XCTAssertEqual(delegate.candidates, [0])
    }
}
