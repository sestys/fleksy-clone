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

    func key(_ id: String) -> XCUIElement {
        keyboard.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    func tapKey(_ id: String) {
        let k = key(id)
        XCTAssertTrue(k.waitForExistence(timeout: 2), "missing key \(id)")
        k.tap()
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

        swipe(dx: 0, dy: -90)                  // swipe up = next candidate
        XCTAssertNotEqual(fieldText, "Hello world ")
        swipe(dx: 0, dy: 90)                   // swipe down = back
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
}
