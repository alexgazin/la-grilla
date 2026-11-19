import XCTest

/// Exercise the real touch path, then verify that one Undo reverses the whole
/// gesture rather than just its last display update.
final class PianoTouchUITests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}

    @MainActor private func openNoteRoll(measureZoom: Bool = false)->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--device-output-startup","--project-store-id",UUID().uuidString,"--screen","grid","-AppleLanguages","(en)","-AppleLocale","en_US"]
        if measureZoom { app.launchArguments.append("--measure-piano-zoom") }
        app.launch()
        XCTAssertTrue(app.buttons["notes.open"].waitForExistence(timeout:15))
        app.buttons["notes.open"].tap()
        XCTAssertTrue(app.navigationBars["Piano roll"].waitForExistence(timeout:5))
        app.buttons["notes.add"].tap()
        return app
    }

    @MainActor func testPinchChangesTimeScaleAndKeepsPitchRowsInPlace() throws {
        let app = openNoteRoll(measureZoom: true)
        defer { app.terminate() }
        let viewport = app.scrollViews["notes.viewport"]
        let reading = app.staticTexts["notes.count"]
        func geometry() throws -> (width: Double, y: Double) {
            let value = try XCTUnwrap(reading.value as? String)
            let values = value.split(separator: ",").compactMap { Double($0) }
            XCTAssertEqual(values.count, 2)
            return (try XCTUnwrap(values.first), try XCTUnwrap(values.last))
        }
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        func pan(from: CGFloat, to: CGFloat) {
            // Use a visible, empty column, clear of the selected note and its grip.
            // Lift after the finger stops so deceleration cannot carry into the pinch.
            let visible = viewport.frame.intersection(app.frame)
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let x = visible.minX + visible.width * 0.72
            let start = origin.withOffset(CGVector(dx: x, dy: visible.minY + visible.height*from))
            let end = origin.withOffset(CGVector(dx: x, dy: visible.minY + visible.height*to))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.25)
        }
        let initial = try geometry()
        pan(from: 0.75, to: 0.28)
        let before = try geometry()
        XCTAssertGreaterThan(before.y, initial.y + 8, "viewport \(viewport.frame), initial \(initial), after pan \(before)")
        viewport.pinch(withScale: 1.45, velocity: 1)
        let enlarged = try geometry()
        XCTAssertGreaterThan(enlarged.width, before.width + 10)
        XCTAssertEqual(enlarged.y, before.y, accuracy: 2)
        viewport.pinch(withScale: 0.8, velocity: -1)
        let reduced = try geometry()
        XCTAssertLessThan(reduced.width, enlarged.width - 10)
        XCTAssertEqual(reduced.y, before.y, accuracy: 2)
        pan(from: 0.28, to: 0.75)
        XCTAssertLessThan(try geometry().y, reduced.y - 8)
        app.buttons["notes.undo"].tap()
        XCTAssertEqual(app.staticTexts["notes.count"].label, "0")
    }

    @MainActor func testOriginalFastSwipeAndAnchoredPinch() throws {
        let app = openNoteRoll(measureZoom: true)
        defer { app.terminate() }
        let viewport = app.scrollViews["notes.viewport"]
        let reading = app.staticTexts["notes.count"]
        func geometry() throws -> (width: Double, y: Double) {
            let value = try XCTUnwrap(reading.value as? String)
            let values = value.split(separator: ",").compactMap { Double($0) }
            XCTAssertEqual(values.count, 2)
            return (try XCTUnwrap(values.first), try XCTUnwrap(values.last))
        }
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        let initial = try geometry()
        viewport.swipeUp(velocity: .fast)
        let before = try geometry()
        XCTAssertGreaterThan(before.y, initial.y + 8, "fast swipe, viewport \(viewport.frame), initial \(initial), after \(before)")
        viewport.pinch(withScale: 1.45, velocity: 1)
        let enlarged = try geometry()
        XCTAssertGreaterThan(enlarged.width, before.width + 10)
        XCTAssertEqual(enlarged.y, before.y, accuracy: 2)
        viewport.pinch(withScale: 0.8, velocity: -1)
        let reduced = try geometry()
        XCTAssertLessThan(reduced.width, enlarged.width - 10)
        XCTAssertEqual(reduced.y, before.y, accuracy: 2)
        viewport.swipeDown(velocity: .fast)
        XCTAssertLessThan(try geometry().y, reduced.y - 8)
        app.buttons["notes.undo"].tap()
        XCTAssertEqual(app.staticTexts["notes.count"].label, "0")
    }

    @MainActor func testKeyboardSelectsInstrumentRecordsPhraseAndReturnsToNotes() {
        let app = openNoteRoll()
        defer { app.terminate() }
        app.buttons["keyboard.open"].tap()
        let electric = app.buttons["keyboard.instrument.electric-piano"]
        let shelf = app.scrollViews["keyboard.instruments"]
        XCTAssertTrue(shelf.waitForExistence(timeout: 8))
        // Asking XCTest for an activation point on an offscreen card can itself fail.
        // Use the scroll viewport to bring the real card center into view first.
        @MainActor func visibleCenter() -> Bool {
            guard electric.exists else { return false }
            let frame = electric.frame
            let viewport = shelf.frame.intersection(app.frame).insetBy(dx: 4, dy: 4)
            return !frame.isEmpty && viewport.contains(CGPoint(x: frame.midX, y: frame.midY))
        }
        for _ in 0..<12 {
            if visibleCenter() { break }
            let moveRight = electric.exists && !electric.frame.isEmpty && electric.frame.midX < shelf.frame.minX
            let start = shelf.coordinate(withNormalizedOffset: CGVector(dx: moveRight ? 0.22 : 0.78, dy: 0.5))
            let end = shelf.coordinate(withNormalizedOffset: CGVector(dx: moveRight ? 0.78 : 0.22, dy: 0.5))
            start.press(forDuration: 0.04, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.08)
        }
        guard visibleCenter() else {
            XCTFail("Electric piano did not become visible in the instrument shelf")
            return
        }
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
