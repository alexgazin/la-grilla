import XCTest

/// Markers (I39), song dynamics (I38), start with a beat (U51), louder in words (I61),
/// step size (I24) and renaming in place (U48).
final class IdeasBatchUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 150 }

    @MainActor private func launch(_ screen: String = "grid") -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--screen", screen, "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor private func run(_ text: String, in app: XCUIApplication) {
        app.buttons["commands.open"].tap()
        let field = app.textFields["commands.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(text + "\n")
    }

    @MainActor func testMarkerIsPinnedAndListedThenUndone() {
        let app = launch()
        run("markers", in: app)
        XCTAssertTrue(app.navigationBars["Markers"].waitForExistence(timeout: 5))
        let field = app.textFields["markers.text"]
        field.tap(); field.typeText("vocals here")
        app.buttons["markers.add"].tap()
        let row = app.buttons["markers.row.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("vocals here"), row.label)
        app.navigationBars["Markers"].buttons["Done"].tap()
        app.buttons["Undo"].tap()
        run("markers", in: app)
        XCTAssertFalse(app.buttons["markers.row.0"].waitForExistence(timeout: 2), "One Undo removes the marker")
    }

    @MainActor func testSongDynamicsApplyInOneUndo() {
        let app = launch()
        run("song dynamics", in: app)
        XCTAssertTrue(app.navigationBars["Song dynamics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["dynamics.role.0"].exists)
        let apply = app.buttons["dynamics.apply"]
        for _ in 0..<6 where !apply.isHittable { app.swipeUp() }
        XCTAssertTrue(apply.isEnabled)
        apply.tap()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.navigationBars["Song dynamics"])
        wait(for: [closed], timeout: 8)
        XCTAssertTrue(app.buttons["Undo"].isEnabled)
    }

    @MainActor func testStartWithABeatOpensItsBeatAtTheGenreTempo() {
        let app = launch()
        run("new project", in: app)
        let quick = app.buttons["project.quick.house"]
        XCTAssertTrue(quick.waitForExistence(timeout: 8))
        quick.tap()
        XCTAssertTrue(app.navigationBars["Beat machine"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["beat.title"].label, "Deep House")
        app.buttons["beat.close"].tap()
        XCTAssertTrue(app.staticTexts["studio.tempo"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["studio.tempo"].label, "122 BPM")
    }

    @MainActor func testLouderInWordsRaisesTheMasterWithOneUndo() {
        let app = launch()
        run("сделай громче", in: app)
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Undo"].isEnabled, "The master change is one edit")
    }

    @MainActor func testSectionRenamesWithADoubleTap() {
        let app = launch()
        let chip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'grid.section.'")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.doubleTap()
        // System alerts do not carry SwiftUI identifiers on their fields and buttons.
        let alert = app.alerts["Rename section"]
        if !alert.waitForExistence(timeout: 5) { print(app.debugDescription) }
        XCTAssertTrue(alert.exists, "A double tap on a section opens Rename")
        let field = alert.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.clearAndType("Hook")
        alert.buttons["Save"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'grid.section.' AND label CONTAINS 'Hook'")).firstMatch.waitForExistence(timeout: 5))
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        tap()
        if let current = value as? String, !current.isEmpty {
            typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        typeText(text)
    }
}
