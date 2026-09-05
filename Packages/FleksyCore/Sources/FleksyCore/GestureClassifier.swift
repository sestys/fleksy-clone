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
        if abs(dx) >= abs(dy) {
            return .swipe(dx > 0 ? .right : .left)
        } else {
            return .swipe(dy > 0 ? .down : .up)
        }
    }
}
