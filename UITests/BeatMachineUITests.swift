import XCTest

/// Beat machine: a ready beat is chosen, edited, heard with the song and put in with one Undo.
final class BeatMachineUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 180 }

    @MainActor func testReadyBeatIsEditedHeardAndPutInWithOneUndo() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--screen", "jam", "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.staticTexts["studio.tempo"].label, "120 BPM")
        let entry = app.buttons["jam.beat-machine"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        entry.tap()
        XCTAssertTrue(app.navigationBars["Beat machine"].waitForExistence(timeout: 8))

        let preset = app.buttons["beat.preset.trap-dark"]
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        preset.tap()
        XCTAssertEqual(app.staticTexts["beat.bpm"].label, "145")
        XCTAssertEqual(app.staticTexts["beat.title"].label, "Dark Trap")

        // A kick on the third sixteenth: the step reports its new state.
        let step = app.buttons["beat.step.0.2"]
        XCTAssertTrue(step.waitForExistence(timeout: 5))
        XCTAssertEqual(step.value as? String, "Off")
        step.tap()
        XCTAssertEqual(step.value as? String, "Hit")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "BeatMachine-pattern"; shot.lifetime = .keepAlways; add(shot)

        let play = app.buttons["beat.play"]
        for _ in 0..<8 where !play.isHittable { app.swipeUp() }
        XCTAssertTrue(play.waitForExistence(timeout: 5) && play.isEnabled, "The kit and the 808 are ready")
        play.tap()
        XCTAssertEqual(play.label, "Stop")
        XCTAssertEqual(app.staticTexts["studio.tempo"].label, "120 BPM", "Listening changes nothing")
        let panel = XCTAttachment(screenshot: app.screenshot()); panel.name = "BeatMachine-apply"; panel.lifetime = .keepAlways; add(panel)

        app.buttons["beat.apply"].tap()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.navigationBars["Beat machine"])
        wait(for: [closed], timeout: 15)
        XCTAssertEqual(app.staticTexts["studio.tempo"].label, "145 BPM")
        app.buttons["Undo"].tap()
        XCTAssertEqual(app.staticTexts["studio.tempo"].label, "120 BPM", "One Undo takes the whole beat back")
    }
}
