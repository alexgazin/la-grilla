import XCTest

/// U4 · U13: search actions by words and pin them to the quick bar.
final class CommandPaletteUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 150 }

    @MainActor private func launch() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--screen", "grid", "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor func testTypedTempoAndKeyApplyWithOneUndoEach() {
        let app = launch()
        let tempo = app.staticTexts["studio.tempo"]
        app.buttons["commands.open"].tap()
        let field = app.textFields["commands.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("tempo 92")
        XCTAssertTrue(app.buttons["commands.row.0"].waitForExistence(timeout: 3))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Stage2-search-actions"; shot.lifetime = .keepAlways; add(shot)
        field.typeText("\n")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '92 BPM'"), object: tempo)], timeout: 5), .completed)
        app.buttons["commands.open"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // The wrong keyboard layout still finds the action: "ntvg" is "темп" typed on QWERTY.
        field.typeText("ntvg 100\n")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == '100 BPM'"), object: tempo)], timeout: 5), .completed)
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertEqual(tempo.label, "92 BPM")
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertEqual(tempo.label, "120 BPM")
    }

    @MainActor func testPinnedActionRunsFromTheQuickBar() {
        let app = launch()
        app.buttons["commands.open"].tap()
        let field = app.textFields["commands.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("history")
        let row = app.buttons["commands.row.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        row.press(forDuration: 1.0)
        let pin = app.buttons["Pin to quick bar"]
        XCTAssertTrue(pin.waitForExistence(timeout: 3))
        pin.tap()
        app.buttons["commands.close"].tap()
        let quick = app.buttons["quickbar.0"]
        XCTAssertTrue(quick.waitForExistence(timeout: 5))
        quick.tap()
        XCTAssertTrue(app.buttons["history.current"].waitForExistence(timeout: 5), "The pinned action opened the edit history")
    }
}
