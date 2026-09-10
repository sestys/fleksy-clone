import XCTest
import FleksyCore

/// Drives the real keyboard extension inside the Simulator. Requires the keyboard to be
/// enabled (the test script writes AppleKeyboards) and the host app's test field.
final class FleksyCloneUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        let field = app.textFields["testField"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap()
        try activateFleksyKeyboard()
    }

    // MARK: Helpers

    var keyboard: XCUIElement { app.otherElements["fleksy.keyboard"] }

    func activateFleksyKeyboard() throws {
        if keyboard.waitForExistence(timeout: 3) { return }
        // The system keyboard came up first: cycle to the next keyboard. On Face ID phones the
        // globe lives in a system bar below the keyboard, so query it at app level.
        let next = app.buttons["Next keyboard"]
        for _ in 0..<3 {
            if next.exists { next.tap() } else { break }
            if keyboard.waitForExistence(timeout: 3) { return }
        }
        XCTFail("Fleksy Clone keyboard did not appear. Is it enabled in Settings?")
    }

    private var keyCache: [String: XCUIElement] = [:]

    /// Finding a key costs far more than tapping it: rebuilding the query and waiting on
    /// it runs about 1.1s against 0.4s for the tap. An XCUIElement is a lazy handle that
    /// re-resolves whenever it is used, so one per key can be kept for the whole test and
    /// still survives the layout changing under it. The cache lives and dies with the
    /// test case, so nothing carries over between tests.
    func key(_ id: String) -> XCUIElement {
        if let cached = keyCache[id] { return cached }
        let element = keyboard.descendants(matching: .any).matching(identifier: id).firstMatch
        // `exists` is a cheap snapshot read; only pay for a wait when it is not there yet.
        if !element.exists {
            XCTAssertTrue(element.waitForExistence(timeout: 2), "missing key \(id)")
        }
        keyCache[id] = element
        return element
    }

    func tapKey(_ id: String) {
        key(id).tap()
    }

    func typeText(_ s: String) {
        for ch in s {
            if ch == " " { tapKey("key_space") } else { tapKey("key_\(ch)") }
        }
    }

    /// A quick swipe in the middle of the letter rows.
    func swipe(dx: CGFloat, dy: CGFloat, startOn id: String = "key_g") {
        let start = key(id).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: dx, dy: dy))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0.02)
    }

    var fieldText: String {
        app.textFields["testField"].value as? String ?? ""
    }

    func clear() {
        app.buttons["clearButton"].tap()
        app.textFields["testField"].tap()
    }

    // MARK: Tests

    func testTypingAndAutocorrectAndSwipes() {
        // English is needed for these words; the keyboard may start in Czech.
        ensureLanguage("English")
        typeText("hello")
        swipe(dx: 120, dy: 0)                  // swipe right = space
        XCTAssertEqual(fieldText, "Hello ")

        typeText("wprld")
        swipe(dx: 120, dy: 0)
        XCTAssertEqual(fieldText, "Hello world ")

        swipe(dx: 0, dy: -90)                  // swipe up = back to what was typed
        XCTAssertEqual(fieldText, "Hello wprld ")
        swipe(dx: 0, dy: 90)                   // swipe down = the correction again
        XCTAssertEqual(fieldText, "Hello world ")

        swipe(dx: -120, dy: 0)                 // swipe left = delete word
        XCTAssertEqual(fieldText, "Hello ")

        swipe(dx: 120, dy: 0)                  // second swipe right = period
        XCTAssertEqual(fieldText, "Hello. ")
        takeScreenshot("english")
    }

    func testCzechDiacritics() {
        ensureLanguage("Čeština")
        typeText("delam")
        swipe(dx: 120, dy: 0)
        XCTAssertEqual(fieldText, "Dělám ")

        // Long-press e -> accent popup -> pick the first accent (ě).
        let e = key("key_e")
        e.press(forDuration: 0.8)
        XCTAssertEqual(fieldText, "Dělám ě")
        takeScreenshot("czech")
    }

    func testLanguageSwitchViaSpaceBarSwipe() {
        ensureLanguage("English")
        swipe(dx: 100, dy: 0, startOn: "key_space")
        XCTAssertTrue(key("key_space").label == "Čeština" || keyboard.staticTexts["Čeština"].exists || app.staticTexts["Čeština"].exists)
        XCTAssertTrue(key("key_z").exists) // qwertz: z in the top row next to t
        takeScreenshot("switched")
    }

    func testSettingsPanelChangesTheme() {
        app.buttons["fleksy.settingsButton"].tap()
        XCTAssertTrue(app.otherElements["fleksy.settingsPanel"].waitForExistence(timeout: 2))
        app.buttons["fleksy.theme_midnight"].tap()
        takeScreenshot("settings")
        app.buttons["fleksy.settingsDone"].tap()
        XCTAssertFalse(app.otherElements["fleksy.settingsPanel"].exists)
        takeScreenshot("midnight")
        app.buttons["fleksy.settingsButton"].tap()
        app.buttons["fleksy.theme_classic"].tap()
        app.buttons["fleksy.settingsDone"].tap()
    }

    func testSwipeUpRevertsAndLearnsCorrection() {
        // Start from a clean user dictionary so the correction happens.
        app.buttons["fleksy.settingsButton"].tap()
        app.buttons["fleksy.clearLearned"].tap()
        app.buttons["fleksy.settingsDone"].tap()
        ensureLanguage("English")
        typeText("helo")
        swipe(dx: 120, dy: 0)
        XCTAssertEqual(fieldText, "Help ")     // real list: adjacent-key fix beats an insertion
        XCTAssertEqual(app.buttons["fleksy.candidate0"].label, "Helo")   // typed word stays leftmost
        swipe(dx: 0, dy: -90)                  // swipe up: restore typed word
        XCTAssertEqual(fieldText, "Helo ")
        swipe(dx: 0, dy: -90)                  // swipe up again: learn it
        XCTAssertEqual(fieldText, "Helo ")
        XCTAssertTrue(app.buttons["fleksy.notice"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.buttons["fleksy.notice"].label, "✓ learned")
        takeScreenshot("learned")
        swipe(dx: 0, dy: -90)                  // and again: forget it
        XCTAssertEqual(app.buttons["fleksy.notice"].label, "✓ forgotten")
        swipe(dx: 0, dy: -90)                  // and again: learn it
        XCTAssertEqual(app.buttons["fleksy.notice"].label, "✓ learned")
        typeText("helo")
        swipe(dx: 120, dy: 0)                  // no longer corrected
        XCTAssertEqual(fieldText, "Helo helo ")
    }

    func testEmojiPickerAndPeriodKey() {
        ensureLanguage("English")
        typeText("hi.")
        XCTAssertEqual(fieldText, "Hi.")
        tapKey("key_emoji")
        let panel = app.otherElements["fleksy.emojiPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 3))
        takeScreenshot("emoji")
        let smile = app.descendants(matching: .any).matching(identifier: "emoji_😀").firstMatch
        XCTAssertTrue(smile.waitForExistence(timeout: 3))
        smile.tap()
        XCTAssertEqual(fieldText, "Hi.😀")
        app.buttons["fleksy.emojiCategory_nature"].tap()
        let bear = app.descendants(matching: .any).matching(identifier: "emoji_🐵").firstMatch
        XCTAssertTrue(bear.waitForExistence(timeout: 3))
        bear.tap()
        XCTAssertEqual(fieldText, "Hi.😀🐵")
        app.buttons["fleksy.emojiBackspace"].tap()
        XCTAssertEqual(fieldText, "Hi.😀")
        app.buttons["fleksy.emojiABC"].tap()
        XCTAssertFalse(panel.exists)
        XCTAssertTrue(key("key_a").waitForExistence(timeout: 2))
    }

    /// Tapping a recent emoji used to send it to the front, shifting everything else
    /// under the finger. It must now stay where it is, and only re-sort on the way back in.
    func testRecentEmojiKeepTheirPlaceWhileBeingTapped() {
        ensureLanguage("English")
        tapKey("key_emoji")
        let panel = app.otherElements["fleksy.emojiPanel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 3))

        // Build up a recent list, then open it.
        let smile = app.descendants(matching: .any).matching(identifier: "emoji_😀").firstMatch
        XCTAssertTrue(smile.waitForExistence(timeout: 3))
        smile.tap()
        app.buttons["fleksy.emojiCategory_nature"].tap()
        let bear = app.descendants(matching: .any).matching(identifier: "emoji_🐵").firstMatch
        XCTAssertTrue(bear.waitForExistence(timeout: 3))
        bear.tap()
        app.buttons["fleksy.emojiCategory_recent"].tap()

        func recentCells() -> [XCUIElement] {
            let all = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'emoji_'"))
            return (0..<all.count).map { all.element(boundBy: $0) }
        }
        let before = recentCells()
        XCTAssertGreaterThanOrEqual(before.count, 2, "need a couple of recents to test with")

        // Tap the second one repeatedly: it becomes the most used, but must not move.
        let second = before[1]
        let identifier = second.identifier
        let frame = second.frame
        for _ in 0..<3 { second.tap() }

        let after = recentCells()
        XCTAssertEqual(after[1].identifier, identifier, "a tapped emoji jumped to a new position")
        XCTAssertEqual(after[1].frame, frame, "the recent grid moved under the finger")
        XCTAssertEqual(after[0].identifier, before[0].identifier, "the rest of the grid shifted")

        // Leaving and re-entering the tab is when the order is allowed to settle.
        app.buttons["fleksy.emojiCategory_nature"].tap()
        app.buttons["fleksy.emojiCategory_recent"].tap()
        let resorted = recentCells().map(\.identifier)
        let position = resorted.firstIndex(of: identifier)
        XCTAssertNotNil(position)
        XCTAssertLessThanOrEqual(position ?? .max, 1, "using an emoji should raise it on the way back in")
    }

    func ensureLanguage(_ name: String) {
        for _ in 0..<2 {
            if key("key_space").label == name { return }
            swipe(dx: 100, dy: 0, startOn: "key_space")
        }
        XCTAssertEqual(key("key_space").label, name)
    }

    func takeScreenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    func testKeyboardHeightIsAdjustableFromSettings() {
        // Start from the default rather than from whatever the last run left behind.
        // The height is a stored preference and reinstalling does not clear it, so a run
        // that stopped early used to strand the slider at an extreme - and then "drag it
        // to maximum and check the keyboard grew" had nowhere left to grow.
        app.buttons["fleksy.settingsButton"].tap()
        let slider = app.sliders["fleksy.keyHeight"]
        XCTAssertTrue(slider.waitForExistence(timeout: 2), "row height slider is not on screen without scrolling")
        app.buttons["fleksy.keyHeightReset"].tap()
        app.buttons["fleksy.settingsDone"].tap()
        let standard = keyboard.frame.height

        app.buttons["fleksy.settingsButton"].tap()
        app.sliders["fleksy.keyHeight"].adjust(toNormalizedSliderPosition: 1.0)
        app.buttons["fleksy.settingsDone"].tap()
        let taller = keyboard.frame.height
        XCTAssertGreaterThan(taller, standard)

        app.buttons["fleksy.settingsButton"].tap()
        app.sliders["fleksy.keyHeight"].adjust(toNormalizedSliderPosition: 0.0)
        app.buttons["fleksy.settingsDone"].tap()
        XCTAssertLessThan(keyboard.frame.height, standard)
        takeScreenshot("short")

        // Back to the default so the other tests see a normal keyboard.
        app.buttons["fleksy.settingsButton"].tap()
        app.buttons["fleksy.keyHeightReset"].tap()
        takeScreenshot("settings-size")
        app.buttons["fleksy.settingsDone"].tap()
        XCTAssertEqual(keyboard.frame.height, standard, accuracy: 1)
    }

    func testSwipeDirectionToggleInvertsUpAndDown() {
        ensureLanguage("English")
        app.buttons["fleksy.settingsButton"].tap()
        let toggle = app.switches["fleksy.swipeDownForNext"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 2))
        toggle.tap()                           // back to the original Fleksy direction
        app.buttons["fleksy.settingsDone"].tap()

        typeText("wprld")
        swipe(dx: 120, dy: 0)
        XCTAssertEqual(fieldText, "World ")
        swipe(dx: 0, dy: 90)                   // down now walks back to what was typed
        XCTAssertEqual(fieldText, "Wprld ")
        swipe(dx: 0, dy: -90)
        XCTAssertEqual(fieldText, "World ")

        app.buttons["fleksy.settingsButton"].tap()
        app.switches["fleksy.swipeDownForNext"].tap()
        app.buttons["fleksy.settingsDone"].tap()
    }
}
