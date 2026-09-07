import XCTest
@testable import FleksyCore

final class GestureTests: XCTestCase {
    let g = GestureClassifier(swipeThreshold: 28, maxSwipeDuration: 0.8)

    func testSmallMovementIsTap() {
        XCTAssertEqual(g.classify(dx: 5, dy: -3, duration: 0.1), .tap)
    }

    func testDirections() {
        XCTAssertEqual(g.classify(dx: 60, dy: 5, duration: 0.2), .swipe(.right))
        XCTAssertEqual(g.classify(dx: -60, dy: 5, duration: 0.2), .swipe(.left))
        XCTAssertEqual(g.classify(dx: 4, dy: -50, duration: 0.2), .swipe(.up))
        XCTAssertEqual(g.classify(dx: 4, dy: 50, duration: 0.2), .swipe(.down))
    }

    func testSlowDragIsTap() {
        XCTAssertEqual(g.classify(dx: 60, dy: 0, duration: 2), .tap)
    }

    // MARK: Two fingers vs. two keys at once

    /// The regression that made fast typing drop letters: two keys pressed at the same
    /// instant used to be swallowed as a two-finger gesture.
    func testTwoKeysHitAtOnceIsNotATwoFingerSwipe() {
        let g = GestureClassifier(swipeThreshold: 30, maxSwipeDuration: 0.9)
        XCTAssertNil(g.multiFingerSwipe([Displacement(dx: 0, dy: 0), Displacement(dx: 2, dy: -3)]))
        // Even a sloppy roll from one key to the next stays two taps.
        XCTAssertNil(g.multiFingerSwipe([Displacement(dx: 8, dy: 4), Displacement(dx: -6, dy: 9)]))
    }

    func testOneFingerMovingDoesNotMakeATwoFingerSwipe() {
        let g = GestureClassifier(swipeThreshold: 30, maxSwipeDuration: 0.9)
        XCTAssertNil(g.multiFingerSwipe([Displacement(dx: 0, dy: 60), Displacement(dx: 1, dy: 2)]))
    }

    func testTwoFingersMovingTogetherIsASwipe() {
        let g = GestureClassifier(swipeThreshold: 30, maxSwipeDuration: 0.9)
        XCTAssertEqual(g.multiFingerSwipe([Displacement(dx: 4, dy: 70), Displacement(dx: -3, dy: 62)]), .down)
        XCTAssertEqual(g.multiFingerSwipe([Displacement(dx: -80, dy: 5), Displacement(dx: -66, dy: -8)]), .left)
    }

    func testTwoFingersMovingApartIsNotASwipe() {
        let g = GestureClassifier(swipeThreshold: 30, maxSwipeDuration: 0.9)
        XCTAssertNil(g.multiFingerSwipe([Displacement(dx: 0, dy: 70), Displacement(dx: 0, dy: -70)]))
    }

    func testASingleFingerNeverMakesAMultiFingerSwipe() {
        let g = GestureClassifier(swipeThreshold: 30, maxSwipeDuration: 0.9)
        XCTAssertNil(g.multiFingerSwipe([Displacement(dx: 0, dy: 90)]))
    }
}
