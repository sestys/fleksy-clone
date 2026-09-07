import XCTest
@testable import FleksyCore

final class EmojiUsageTests: XCTestCase {
    /// Notes each emoji once per character, left to right, with an increasing clock.
    private func used(_ sequence: [String], into usage: inout EmojiUsage, from start: Int = 1) {
        for (i, emoji) in sequence.enumerated() { usage.note(emoji, at: start + i) }
    }

    func testMostUsedComesFirst() {
        var usage = EmojiUsage()
        used(["😀", "😀", "😀", "🎉", "🎉", "🔥"], into: &usage)
        XCTAssertEqual(usage.ordered(), ["😀", "🎉", "🔥"])
        XCTAssertEqual(usage.count(of: "😀"), 3)
        XCTAssertEqual(usage.count(of: "🙈"), 0)
    }

    func testRecencyOnlyBreaksTies() {
        var usage = EmojiUsage()
        used(["😀", "😀", "🎉"], into: &usage)
        // The newer emoji is used once more, drawing level, and its recency wins the tie.
        usage.note("🎉", at: 100)
        XCTAssertEqual(usage.ordered(), ["🎉", "😀"])
        // One more use of the older one puts it back in front on count alone.
        usage.note("😀", at: 101)
        XCTAssertEqual(usage.ordered(), ["😀", "🎉"])
    }

    func testOrderIsStableForEquallyUsedEmoji() {
        var usage = EmojiUsage()
        for emoji in ["😀", "🎉", "🔥", "🙈"] { usage.note(emoji, at: 5) }  // same instant
        XCTAssertEqual(usage.ordered(), usage.ordered())
        XCTAssertEqual(Set(usage.ordered()), ["😀", "🎉", "🔥", "🙈"])
    }

    /// The point of the whole type: using an emoji that is already on the list must not
    /// move it, so a run of taps does not chase the grid around.
    func testUsingAnEmojiAlreadyInFrontDoesNotReorderTheRest() {
        var usage = EmojiUsage()
        used(["😀", "😀", "😀", "🎉", "🎉", "🔥"], into: &usage)
        let before = usage.ordered()
        usage.note("😀", at: 50)
        XCTAssertEqual(usage.ordered(), before)
    }

    func testTheListIsCappedAndDropsTheLeastUsed() {
        var usage = EmojiUsage(limit: 3)
        used(["😀", "😀", "😀", "🎉", "🎉", "🔥", "🙈"], into: &usage)
        XCTAssertEqual(usage.ordered(), ["😀", "🎉", "🙈"])
        XCTAssertEqual(usage.count(of: "🔥"), 0, "the least used emoji is the one dropped")
    }

    func testEmptyEmojiIsIgnored() {
        var usage = EmojiUsage()
        usage.note("", at: 1)
        XCTAssertTrue(usage.isEmpty)
    }

    // MARK: - Storage

    func testCountsRoundTripThroughStorage() {
        var usage = EmojiUsage()
        used(["😀", "😀", "🎉"], into: &usage)
        let restored = EmojiUsage(stored: usage.stored)
        XCTAssertEqual(restored.ordered(), usage.ordered())
        XCTAssertEqual(restored.count(of: "😀"), 2)
    }

    func testMalformedStorageIsIgnoredRatherThanTrusted() {
        let usage = EmojiUsage(stored: ["😀": [2, 9], "🎉": [], "🔥": [1], "🙈": [0, 3], "🌟": [1, 2, 3]])
        XCTAssertEqual(usage.ordered(), ["😀"])
    }

    func testAnOlderRecentListIsCarriedOver() {
        // The old format was most-recent-first with no counts.
        let usage = EmojiUsage.migrating(fromMostRecentFirst: ["🔥", "🎉", "😀"])
        XCTAssertEqual(usage.ordered(), ["🔥", "🎉", "😀"], "the old order is the only ranking we have")
        XCTAssertEqual(usage.count(of: "🔥"), 1)
    }

    func testMigrationRespectsTheLimit() {
        let many = (0..<60).map { String(UnicodeScalar(0x1F600 + $0)!) }
        let usage = EmojiUsage.migrating(fromMostRecentFirst: many, limit: 10)
        XCTAssertEqual(usage.ordered().count, 10)
        XCTAssertEqual(usage.ordered().first, many.first)
    }
}
