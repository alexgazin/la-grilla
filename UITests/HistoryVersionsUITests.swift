import XCTest

/// U6 · U7: the visual edit history and named song versions.
final class HistoryVersionsUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 180 }

    @MainActor private func launch() -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--screen", "grid", "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 15))
        return app
    }

    /// Opens project settings and raises the tempo by `steps` BPM, one edit per tap.
    @MainActor private func raiseTempo(_ app: XCUIApplication, by steps: Int) {
        app.staticTexts["studio.tempo"].tap()
        let stepper = app.steppers.firstMatch
        XCTAssertTrue(stepper.waitForExistence(timeout: 5))
        let increment = stepper.buttons.element(boundBy: 1)
        for _ in 0..<steps { increment.tap() }
    }

    @MainActor func testHistoryReturnsToAnEarlierEditAndRedoBringsItBack() {
        let app = launch()
        let tempo = app.staticTexts["studio.tempo"]
        XCTAssertEqual(tempo.label, "120 BPM")
        raiseTempo(app, by: 3)
        app.buttons["settings.history"].tap()
        XCTAssertTrue(app.buttons["history.current"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["history.current"].label.contains("122 → 123"), app.buttons["history.current"].label)
        let start = app.buttons["history.row.0"]
        XCTAssertTrue(start.exists)
        XCTAssertTrue(app.buttons["history.row.2"].exists)
        start.tap()
        let listen = app.buttons["history.listen"]
        XCTAssertTrue(listen.waitForExistence(timeout: 3))
        listen.tap()
        XCTAssertEqual(listen.label, "Stop")
        listen.tap()
        XCTAssertEqual(listen.label, "Listen")
        let attachment = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        attachment.name = "Stage1-history"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["history.restore"].tap()
        XCTAssertTrue(app.buttons["history.redo.0"].waitForExistence(timeout: 5))
        app.buttons["history.done"].tap()
        XCTAssertTrue(tempo.waitForExistence(timeout: 5))
        XCTAssertEqual(tempo.label, "120 BPM")
        app.buttons["Redo"].tap()
        XCTAssertEqual(tempo.label, "121 BPM")
    }

    @MainActor func testSavedVersionComparesAndRestoresInOneUndo() {
        let app = launch()
        let tempo = app.staticTexts["studio.tempo"]
        raiseTempo(app, by: 1)
        app.buttons["settings.versions"].tap()
        XCTAssertTrue(app.staticTexts["versions.empty"].waitForExistence(timeout: 5))
        app.buttons["versions.save"].tap()
        XCTAssertTrue(app.buttons["versions.row.0"].waitForExistence(timeout: 5))
        app.buttons["versions.done"].tap()
        XCTAssertEqual(tempo.label, "121 BPM")
        raiseTempo(app, by: 2)
        app.buttons["settings.versions"].tap()
        let row = app.buttons["versions.row.0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let listen = app.buttons["versions.listen"]
        XCTAssertTrue(listen.waitForExistence(timeout: 3))
        listen.tap()
        XCTAssertTrue(app.buttons["versions.ab.1"].waitForExistence(timeout: 3))
        app.buttons["versions.ab.1"].tap()
        app.buttons["versions.ab.0"].tap()
        let attachment = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        attachment.name = "Stage1-versions"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["versions.restore"].tap()
        // The song as it was is kept as a version before restoring.
        XCTAssertTrue(app.buttons["versions.row.1"].waitForExistence(timeout: 5))
        app.buttons["versions.done"].tap()
        XCTAssertTrue(tempo.waitForExistence(timeout: 5))
        XCTAssertEqual(tempo.label, "121 BPM")
        app.buttons["Undo"].tap()
        XCTAssertEqual(tempo.label, "123 BPM")
    }
}
