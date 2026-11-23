import XCTest

/// I17 · I10: chords from text, melody ideas.
final class ChordImportUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 150 }

    @MainActor func testPastedSongbookChordsAreHeardThenApplied() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--screen", "grid", "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 15))
        app.buttons["commands.open"].tap()
        let field = app.textFields["commands.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("chords from photo\n")
        let mode = app.buttons["chords.mode.1"]
        XCTAssertTrue(mode.waitForExistence(timeout: 5))
        mode.tap()
        let editor = app.textViews["chords.text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 3))
        editor.tap()
        editor.typeText("| Dm | G7 | Cmaj7 | A7 |")
        XCTAssertTrue(app.descendants(matching: .any)["chords.preview"].waitForExistence(timeout: 3))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Stage5-chords-from-text"; shot.lifetime = .keepAlways; add(shot)
        let apply = app.buttons["chords.apply"]
        for _ in 0..<4 where !apply.isHittable { app.swipeUp() }
        apply.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: apply)], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["Undo"].firstMatch.isEnabled)
    }
}
