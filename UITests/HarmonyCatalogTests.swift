import XCTest

final class HarmonyCatalogTests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}

    @MainActor private func launch()->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--screen","grid","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:15))
        return app
    }

    @MainActor private func openFirstChord(_ app:XCUIApplication){
        let chord=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","grid.chord.")).firstMatch
        XCTAssertTrue(chord.waitForExistence(timeout:5));chord.tap()
        XCTAssertTrue(app.navigationBars["Edit chord"].waitForExistence(timeout:5))
    }

    @MainActor private func reveal(_ element:XCUIElement,in app:XCUIApplication){
        for _ in 0..<6{if element.isHittable{return};app.scrollViews.firstMatch.swipeUp()}
        XCTAssertTrue(element.isHittable)
    }

    @MainActor private func replace(_ field:XCUIElement,with text:String){
        XCTAssertTrue(field.exists)
        // Tapping past the existing text places the caret at its end.
        field.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:0.5)).tap()
        let old=field.value as? String ?? ""
        field.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count)+text+"\n")
    }

    @MainActor func testCustomFormulaPersistsEveryToneAndIsUndoable(){
        let app=launch();openFirstChord(app)
        XCTAssertGreaterThanOrEqual(app.buttons["chord.set-symbol"].frame.width,44)
        XCTAssertGreaterThanOrEqual(app.buttons["chord.set-symbol"].frame.height,44)
        let custom=app.switches["chord.custom"];reveal(custom,in:app);custom.tap()
        let formula=app.textFields["chord.formula"];reveal(formula,in:app)
        replace(formula,with:"0, 3, 7, 11, 14")
        XCTAssertFalse(app.staticTexts["chord.error"].exists)
        XCTAssertEqual(app.staticTexts["chord.notes"].label,"C4 · E♭4 · G4 · B4 · D5")
        reveal(app.buttons["chord.inversion"],in:app)
        XCTAssertTrue(app.staticTexts["Inversion"].exists)
        XCTAssertTrue(app.staticTexts["Slash bass"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons["chord.inversion"].frame.height,44)
        reveal(app.buttons["chord.slash-bass"],in:app)
        XCTAssertGreaterThanOrEqual(app.buttons["chord.slash-bass"].frame.height,44)
        let apply=app.buttons["chord.apply"];reveal(apply,in:app);apply.tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout:5));XCTAssertTrue(app.buttons["Undo"].isEnabled)
        let tile=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.chord.' AND label CONTAINS 'Custom chord'")).firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout:5));XCTAssertFalse(tile.label.contains("Major"))
        openFirstChord(app)
        XCTAssertEqual(app.textFields["chord.symbol"].value as? String,"C{0,3,7,11,14}")
        XCTAssertEqual(app.staticTexts["chord.notes"].label,"C4 · E♭4 · G4 · B4 · D5")
        let shot=XCTAttachment(data:XCUIScreen.main.screenshot().pngRepresentation,uniformTypeIdentifier:"public.png")
        shot.name="OriginalVision-original-vision-custom-harmony";shot.lifetime = .keepAlways;add(shot)
        app.buttons["Cancel"].tap();app.buttons["Undo"].tap();openFirstChord(app)
        XCTAssertEqual(app.textFields["chord.symbol"].value as? String,"C")
    }

    @MainActor func testAlteredNotationAndInvalidFormulaNeverSilentlySave(){
        let app=launch();openFirstChord(app)
        replace(app.textFields["chord.symbol"],with:"C7(b9,#11)")
        XCTAssertFalse(app.staticTexts["chord.error"].exists)
        XCTAssertEqual(app.staticTexts["chord.notes"].label,"C4 · E4 · G4 · B♭4 · C♯5 · F♯5")
        replace(app.textFields["chord.symbol"],with:"C{0,7,4}")
        XCTAssertTrue(app.staticTexts["chord.error"].waitForExistence(timeout:5))
        let apply=app.buttons["chord.apply"];reveal(apply,in:app);apply.tap()
        XCTAssertTrue(app.navigationBars["Edit chord"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        openFirstChord(app);XCTAssertEqual(app.textFields["chord.symbol"].value as? String,"C")
    }
}
