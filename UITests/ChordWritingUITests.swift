import XCTest

/// Verifies stored writing through the real editor, Undo/Redo and a fresh
/// application process. Domain tests separately inspect MIDI/portable bytes.
final class ChordWritingUITests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}

    @MainActor func testTypedRootAndSlashWritingSurviveUndoRedoAndStoreReopen()throws {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--screen","grid","--project-store-id",UUID().uuidString,"-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();defer{app.terminate()}
        let chord=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.chord.'")).firstMatch
        XCTAssertTrue(chord.waitForExistence(timeout:15))
        let original=chord.label
        chord.tap()
        let input=app.textFields["chord.symbol"]
        XCTAssertTrue(input.waitForExistence(timeout:5))
        input.tap()
        let previous=input.value as? String ?? ""
        input.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:previous.count)+"Dbmaj7/F#\n")
        let display=app.staticTexts["chord.display-symbol"]
        XCTAssertTrue(display.waitForExistence(timeout:5))
        XCTAssertEqual(display.label,"D♭maj7/F♯")
        let apply=app.buttons["chord.apply"]
        reveal(apply,in:app);apply.tap()
        wait{!app.navigationBars["Edit chord"].exists}
        XCTAssertTrue(chord.label.hasPrefix("D♭maj7/F♯"))
        app.buttons["Undo"].tap()
        wait{chord.label==original}
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        app.buttons["Redo"].tap()
        wait{chord.label.hasPrefix("D♭maj7/F♯")}
        let saved=app.descendants(matching:.any).matching(NSPredicate(format:"label == 'Saved on this iPhone'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout:8))
        app.terminate();app.launch()
        XCTAssertTrue(chord.waitForExistence(timeout:15))
        XCTAssertTrue(chord.label.hasPrefix("D♭maj7/F♯"))
        chord.tap()
        XCTAssertTrue(input.waitForExistence(timeout:5))
        XCTAssertEqual(input.value as? String,"D♭maj7/F♯")
        XCTAssertEqual(display.label,"D♭maj7/F♯")
        let frame=XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        frame.name="Writing-real-root-and-slash-store-reopen";frame.lifetime = .keepAlways;add(frame)
        app.buttons["Cancel"].tap()
    }
    @MainActor private func reveal(_ target:XCUIElement,in app:XCUIApplication){
        for _ in 0..<7{
            let bounds=app.frame,frame=target.frame
            if target.isHittable,frame.minY>=bounds.minY+8,frame.maxY<=bounds.maxY-8{return}
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(target.isHittable)
    }
    @MainActor private func wait(_ condition:()->Bool){
        let deadline=Date().addingTimeInterval(5)
        repeat{if condition(){return};RunLoop.current.run(until:Date().addingTimeInterval(0.1))}while Date()<deadline
        XCTFail("The real editor did not reach the expected state")
    }
}
