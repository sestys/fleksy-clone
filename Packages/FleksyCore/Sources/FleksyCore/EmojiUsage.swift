import Foundation

/// How often each emoji has been used, so the recent tab can be ordered by frequency
/// rather than by recency.
///
/// A most-recently-used list reorders itself under the finger: tapping an emoji sends it
/// to the front and shifts everything else along, which makes picking several in a row a
/// game of chase. Counting uses instead means the order barely moves from day to day, and
/// the caller decides *when* to re-read it — `ordered()` is a snapshot, and the picker
/// takes a fresh one only when the recent tab is opened, never while it is being tapped.
public struct EmojiUsage: Equatable, Sendable {
    public struct Use: Equatable, Sendable {
        public var count: Int
        /// Breaks ties between equally used emoji, so a new one appears at the top of its
        /// tier rather than in some arbitrary spot. Never outranks the count itself.
        public var lastUsed: Int

        public init(count: Int, lastUsed: Int) {
            self.count = count
            self.lastUsed = lastUsed
        }
    }

    private(set) var uses: [String: Use]
    /// How many emoji the recent tab keeps. The least used are dropped first.
    public var limit: Int

    public init(uses: [String: Use] = [:], limit: Int = 40) {
        self.uses = uses
        self.limit = limit
    }

    public var isEmpty: Bool { uses.isEmpty }

    public func count(of emoji: String) -> Int { uses[emoji]?.count ?? 0 }

    /// Records one use. `time` need only increase between calls.
    public mutating func note(_ emoji: String, at time: Int) {
        guard !emoji.isEmpty else { return }
        let existing = uses[emoji]
        uses[emoji] = Use(count: (existing?.count ?? 0) + 1, lastUsed: time)
        prune()
    }

    /// Most used first, ties broken by most recent, then by the emoji itself so the
    /// order never depends on hash seeding.
    public func ordered() -> [String] {
        uses.sorted { a, b in
            if a.value.count != b.value.count { return a.value.count > b.value.count }
            if a.value.lastUsed != b.value.lastUsed { return a.value.lastUsed > b.value.lastUsed }
            return a.key < b.key
        }.map(\.key)
    }

    private mutating func prune() {
        guard uses.count > limit else { return }
        for emoji in ordered().dropFirst(limit) { uses.removeValue(forKey: emoji) }
    }

    // MARK: - Storage

    /// A plist-native form: emoji -> [count, lastUsed].
    public init(stored: [String: [Int]], limit: Int = 40) {
        var uses: [String: Use] = [:]
        for (emoji, pair) in stored where pair.count == 2 && pair[0] > 0 {
            uses[emoji] = Use(count: pair[0], lastUsed: pair[1])
        }
        self.init(uses: uses, limit: limit)
    }

    public var stored: [String: [Int]] {
        uses.mapValues { [$0.count, $0.lastUsed] }
    }

    /// Seeds counts from an older most-recent-first list, so upgrading does not throw
    /// away the emoji someone has been using. The list order is all we know, so it
    /// becomes the ranking: everything starts on one use, ordered by recency.
    public static func migrating(fromMostRecentFirst list: [String], limit: Int = 40) -> EmojiUsage {
        var uses: [String: Use] = [:]
        for (position, emoji) in list.prefix(limit).enumerated() where !emoji.isEmpty {
            uses[emoji] = Use(count: 1, lastUsed: list.count - position)
        }
        return EmojiUsage(uses: uses, limit: limit)
    }
}
