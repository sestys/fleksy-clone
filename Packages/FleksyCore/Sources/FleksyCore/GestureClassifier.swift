import Foundation

public enum SwipeDirection: Equatable, Sendable {
    case up, down, left, right
}

public enum Gesture: Equatable, Sendable {
    case tap
    case swipe(SwipeDirection)
}

/// Turns a finished touch (start -> end displacement) into a tap or a swipe.
/// Pure geometry so it is testable without UIKit.
public struct GestureClassifier: Sendable {
    /// Minimum displacement, in points, to count as a swipe.
    public var swipeThreshold: Double
    /// Maximum duration of a swipe; slower drags are treated as taps/holds.
    public var maxSwipeDuration: TimeInterval

    public init(swipeThreshold: Double = 28, maxSwipeDuration: TimeInterval = 0.8) {
        self.swipeThreshold = swipeThreshold
        self.maxSwipeDuration = maxSwipeDuration
    }

    public func classify(dx: Double, dy: Double, duration: TimeInterval) -> Gesture {
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance >= swipeThreshold, duration <= maxSwipeDuration else { return .tap }
        return .swipe(GestureClassifier.direction(dx: dx, dy: dy))
    }

    /// The dominant axis of a displacement, ignoring how far it travelled.
    public static func direction(dx: Double, dy: Double) -> SwipeDirection {
        if abs(dx) >= abs(dy) {
            return dx > 0 ? .right : .left
        } else {
            return dy > 0 ? .down : .up
        }
    }

    /// Whether the fingers currently on the keyboard add up to one multi-finger swipe.
    ///
    /// This is what tells a two-finger gesture apart from two keys hit at the same
    /// moment. Fingers that land together barely move, so they stay independent taps
    /// and both letters get typed; only when at least `fingers` of them have each
    /// travelled past the swipe threshold *the same way* is it one gesture.
    public func multiFingerSwipe(_ displacements: [Displacement], fingers: Int = 2) -> SwipeDirection? {
        guard displacements.count >= fingers else { return nil }
        let travelled = displacements.filter { $0.distance >= swipeThreshold }
        guard travelled.count >= fingers else { return nil }
        let directions = travelled.map { GestureClassifier.direction(dx: $0.dx, dy: $0.dy) }
        guard let first = directions.first, directions.allSatisfy({ $0 == first }) else { return nil }
        return first
    }
}

/// How far one finger has travelled from where it landed.
public struct Displacement: Equatable, Sendable {
    public var dx: Double
    public var dy: Double
    public init(dx: Double, dy: Double) {
        self.dx = dx
        self.dy = dy
    }
    public var distance: Double { (dx * dx + dy * dy).squareRoot() }
}
