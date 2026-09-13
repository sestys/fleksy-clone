import XCTest
@testable import FleksyCore

final class TouchLifecycleTests: XCTestCase {
    func testMovingBeforeHoldDeadlineCancelsRepeatButStillSwipes() {
        var touch = TouchLifecycle(startedAt: 10, sequence: 0)
        touch.move(dx: -60, dy: 0)
        XCTAssertFalse(touch.repeatTick())
        XCTAssertEqual(touch.finish(dx: -60, dy: 0, at: 10.6), .swipe(.left))
    }

    func testReturningToStartDoesNotRearmHold() {
        var touch = TouchLifecycle(startedAt: 10, sequence: 0)
        touch.move(dx: 20, dy: 0)
        touch.move(dx: 0, dy: 0)
        XCTAssertFalse(touch.repeatTick())
        XCTAssertFalse(touch.openAccent())
    }

    func testMovingAfterRepeatStopsFurtherDeletionAndDoesNotAlsoSwipe() {
        var touch = TouchLifecycle(startedAt: 10, sequence: 0)
        XCTAssertTrue(touch.repeatTick())
        touch.move(dx: -60, dy: 0)
        XCTAssertFalse(touch.repeatTick())
        XCTAssertNil(touch.finish(dx: -60, dy: 0, at: 10.7))
    }

    func testConsumedFingerCannotRepeatOrType() {
        var touch = TouchLifecycle(startedAt: 10, sequence: 0)
        touch.consume()
        XCTAssertFalse(touch.repeatTick())
        XCTAssertFalse(touch.openAccent())
        XCTAssertNil(touch.finish(dx: 0, dy: 0, at: 10.2))
    }

    func testAccentClaimPreventsRepeatAndOrdinaryTap() {
        var touch = TouchLifecycle(startedAt: 10, sequence: 0)
        XCTAssertTrue(touch.openAccent())
        touch.move(dx: 70, dy: 0)
        XCTAssertFalse(touch.repeatTick())
        XCTAssertNil(touch.finish(dx: 70, dy: 0, at: 10.7))
    }

    func testOneTouchEmitsOnlyOneTap() {
        var touch = TouchLifecycle(startedAt: 10, sequence: 0)
        XCTAssertEqual(touch.finish(dx: 0, dy: 0, at: 10.1), .tap)
        XCTAssertNil(touch.finish(dx: 0, dy: 0, at: 10.2))
    }

    func testSimultaneousLiftUsesTouchDownOrderWithStableTieBreak() {
        let first = TouchLifecycle(startedAt: 10, sequence: 1)
        let second = TouchLifecycle(startedAt: 10.1, sequence: 2)
        let third = TouchLifecycle(startedAt: 10.1, sequence: 3)
        XCTAssertEqual([third, first, second].sorted { $0.precedes($1) }.map(\.sequence), [1, 2, 3])
    }
}
