import XCTest

/// Exercise the real touch path, then verify that one Undo reverses the whole
/// gesture rather than just its last display update.
final class PianoTouchUITests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}

    @MainActor private func openNoteRoll()->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--device-output-startup","--project-store-id",UUID().uuidString,"--screen","grid","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["notes.open"].waitForExistence(timeout:15))
        app.buttons["notes.open"].tap()
        XCTAssertTrue(app.navigationBars["Piano roll"].waitForExistence(timeout:5))
        app.buttons["notes.add"].tap()
        return app
    }

    @MainActor func testPinchChangesTimeScaleAndKeepsPitchRowsInPlace() {
        let app = openNoteRoll()
        defer { app.terminate() }
        let viewport = app.scrollViews["notes.viewport"]
        let canvas = app.descendants(matching: .any).matching(identifier: "notes.canvas").firstMatch
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        let initialY = canvas.frame.minY
        let touch = viewport.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.74))
        touch.press(forDuration: 0.02, thenDragTo: touch.withOffset(CGVector(dx: 0, dy: -60)),
                    withVelocity: 180, thenHoldForDuration: 0.3)
        let before = canvas.frame
        XCTAssertLessThan(before.minY, initialY - 8)
        viewport.pinch(withScale: 1.45, velocity: 1)
        let enlarged = canvas.frame
        XCTAssertGreaterThan(enlarged.width, before.width + 10)
        XCTAssertEqual(enlarged.minY, before.minY, accuracy: 2)
        viewport.pinch(withScale: 0.8, velocity: -1)
        let reduced = canvas.frame
        XCTAssertLessThan(reduced.width, enlarged.width - 10)
        XCTAssertEqual(reduced.minY, before.minY, accuracy: 2)
        viewport.swipeDown()
        XCTAssertGreaterThan(canvas.frame.minY, reduced.minY + 8)
        app.buttons["notes.undo"].tap()
        XCTAssertEqual(app.staticTexts["notes.count"].label, "0")
    }

    @MainActor func testKeyboardSelectsInstrumentRecordsPhraseAndReturnsToNotes() {
        let app = openNoteRoll()
        defer { app.terminate() }
        app.buttons["keyboard.open"].tap()
        let electric = app.buttons["keyboard.instrument.electric-piano"]
        let shelf = app.scrollViews["keyboard.instruments"]
        for _ in 0..<3 where !electric.isHittable { shelf.swipeLeft() }
        XCTAssertTrue(electric.isHittable)
        electric.tap()
        let current = app.staticTexts["keyboard.current-sound"]
        let updated = NSPredicate(format: "label == %@", "Electric piano")
        expectation(for: updated, evaluatedWith: current)
        waitForExpectations(timeout: 12)
        let keyboard = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        keyboard.name = "Studio33-instrument-keyboard"
        keyboard.lifetime = .keepAlways
        add(keyboard)
        app.buttons["Octave up"].tap()
        XCTAssertEqual(app.staticTexts["keyboard.octave"].label, "C5")
        app.buttons["keyboard.record"].tap()
        let c = app.buttons["keyboard.key.72"]
        XCTAssertTrue(c.waitForExistence(timeout: 5))
        c.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)).press(forDuration: 0.35)
        app.buttons["keyboard.record"].tap()
        app.buttons["Done"].firstMatch.tap()
        XCTAssertEqual(app.staticTexts["notes.count"].label, "2")
        app.buttons["notes.undo"].tap()
        XCTAssertEqual(app.staticTexts["notes.count"].label, "1")
    }

    @MainActor func testResizeHandleUsesGridAndCommitsOneUndoableEdit(){
        let app=openNoteRoll();defer{app.terminate()}
        let duration=app.staticTexts["notes.selection.duration"]
        XCTAssertTrue(duration.waitForExistence(timeout:5))
        XCTAssertEqual(duration.label,"480 ticks")
        let handle=app.descendants(matching:.any).matching(identifier:"notes.resize-handle").firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout:5))
        XCTAssertTrue(handle.isHittable)
        XCTAssertGreaterThanOrEqual(handle.frame.width,44)
        XCTAssertGreaterThanOrEqual(handle.frame.height,44)
        let start=handle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        // 240pt/bar and 3840 ticks/bar: 60pt extends 480 ticks to1440.
        start.press(forDuration:0.1,thenDragTo:start.withOffset(CGVector(dx:60,dy:0)),withVelocity:80,thenHoldForDuration:0.8)
        let resizedTicks=1_440.formatted(.number.locale(Locale(identifier:"en_US")))
        XCTAssertEqual(duration.label,resizedTicks+" ticks")
        XCTAssertEqual(app.staticTexts["notes.count"].label,"1")
        let screenshot=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        screenshot.name="Touch21-Piano-resized-note-and-handle";screenshot.lifetime = .keepAlways;add(screenshot)
        app.buttons["notes.undo"].tap()
        XCTAssertEqual(duration.label,"480 ticks","A whole touch resize must be one project edit")
        app.buttons["notes.undo"].tap()
        XCTAssertEqual(app.staticTexts["notes.count"].label,"0","The previous history entry must still be Add note")
    }

    @MainActor func testHoldAndMoveKeepsDurationAndCommitsOneUndoableEdit(){
        let app=openNoteRoll();defer{app.terminate()}
        let start=app.steppers["notes.selection.start"],pitch=app.steppers["notes.selection.pitch"]
        XCTAssertEqual(start.value as? String,"1:1")
        XCTAssertEqual(pitch.value as? String,"C5")
        let canvas=app.descendants(matching:.any).matching(identifier:"notes.canvas").firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout:5))
        // The actual newly added C5 body is row11, left of its resize grip.
        let touch=canvas.coordinate(withNormalizedOffset:CGVector(dx:0,dy:0)).withOffset(CGVector(dx:12,dy:276))
        touch.press(forDuration:0.5,thenDragTo:touch.withOffset(CGVector(dx:60,dy:-48)),withVelocity:80,thenHoldForDuration:0.5)
        XCTAssertEqual(start.value as? String,"1:2")
        XCTAssertEqual(pitch.value as? String,"D5")
        XCTAssertEqual(app.staticTexts["notes.selection.duration"].label,"480 ticks")
        app.buttons["notes.undo"].tap()
        XCTAssertEqual(start.value as? String,"1:1")
        XCTAssertEqual(pitch.value as? String,"C5")
        app.buttons["notes.undo"].tap()
        XCTAssertEqual(app.staticTexts["notes.count"].label,"0")
    }

}
