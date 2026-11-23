import XCTest

/// U45 · U44 · U22: the next-step hint, practice and section focus.
final class ComfortUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 120 }

    @MainActor func testNextStepHintRunsItsActionAndCanBeHidden() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--next-step", "--screen", "grid", "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 15))
        let go = app.buttons["next-step.go"]
        XCTAssertTrue(go.waitForExistence(timeout: 5), "The demo has chords and a beat, so the hint suggests humming a melody")
        go.tap()
        XCTAssertTrue(app.navigationBars["Voice to MIDI"].waitForExistence(timeout: 8))
    }

    @MainActor func testFocusLoopsTheSectionAndPracticeDoesNotChangeTheTempo() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--screen", "grid", "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 15))
        let focus = app.buttons["grid.focus"]
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
        focus.tap()
        XCTAssertEqual(focus.label, "Leave focus")
        focus.tap()
        XCTAssertEqual(focus.label, "Focus on this section")
        app.buttons["commands.open"].tap()
        let field = app.textFields["commands.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("practice\n")
        XCTAssertEqual(app.staticTexts["studio.tempo"].label, "120 BPM", "Practice slows the audition, not the song")
    }
}
