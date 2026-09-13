import Foundation

/// Arbitration between a key tap, a moving finger and a hold action. Timers and
/// UIKit touches stay in the view; the decisions that allow them to type live here.
public struct TouchLifecycle: Sendable {
    public enum State: Sendable { case pending, dragging, repeating, accent, consumed, cancelled, finished }
    public private(set) var state: State = .pending
    public let startedAt: TimeInterval
    public let sequence: Int

    public init(startedAt: TimeInterval, sequence: Int) {
        self.startedAt = startedAt
        self.sequence = sequence
    }

    public var allowsHold: Bool { state == .pending || state == .repeating }

    public mutating func move(dx: Double, dy: Double) {
        guard hypot(dx, dy) >= 12 else { return }
        if state == .pending { state = .dragging }
        else if state == .repeating { state = .cancelled }
    }

    public mutating func repeatTick() -> Bool {
        guard allowsHold else { return false }
        state = .repeating
        return true
    }

    public mutating func openAccent() -> Bool {
        guard state == .pending else { return false }
        state = .accent
        return true
    }

    public mutating func consume() { state = .consumed }

    public mutating func finish(dx: Double, dy: Double, at time: TimeInterval,
                                classifier: GestureClassifier = GestureClassifier(swipeThreshold: 30, maxSwipeDuration: 0.9)) -> Gesture? {
        let mayType = state == .pending || state == .dragging
        state = .finished
        return mayType ? classifier.classify(dx: dx, dy: dy, duration: time - startedAt) : nil
    }

    /// Fingers lifted in the same callback are emitted in their touch-down order.
    public func precedes(_ other: TouchLifecycle) -> Bool {
        startedAt == other.startedAt ? sequence < other.sequence : startedAt < other.startedAt
    }
}
