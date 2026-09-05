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
}
