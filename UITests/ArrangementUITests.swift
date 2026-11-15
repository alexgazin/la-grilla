import XCTest

final class ArrangementUITests: XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}

    @MainActor private func launch(_ screen:String="grid")->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--screen",screen,"--arrangement-clips","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:15))
        return app
    }
    @MainActor private func wait(_ element:XCUIElement,_ predicate:NSPredicate){
        let expectation=XCTNSPredicateExpectation(predicate:predicate,object:element)
        XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:6),.completed)
    }

    @MainActor func testClipTapResizeNativeDragAndUndo(){
        let app=launch()
        let clips=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.clip.'"))
        let harmony=clips.firstMatch
        XCTAssertTrue(harmony.waitForExistence(timeout:5))
        let id=harmony.identifier
        // This is the actual clip hit target, including its drawn waveform.
        harmony.coordinate(withNormalizedOffset:CGVector(dx:0.4,dy:0.5)).tap()
        XCTAssertTrue(app.navigationBars["Clip settings"].waitForExistence(timeout:5))
        let length=app.steppers["clip.length"]
        XCTAssertTrue(length.waitForExistence(timeout:5))
        for _ in 0..<3{length.buttons["Decrement"].tap()}
        wait(length,NSPredicate(format:"value == '1.00 bars'"))
        app.buttons["Done"].tap()
        let clip=app.buttons[id]
        wait(clip,NSPredicate(format:"value == '1.00 bars'"))
        let initialX=clip.frame.minX,bar=clip.frame.width+6
        let finger=clip.coordinate(withNormalizedOffset:CGVector(dx:0.4,dy:0.5))
        finger.press(forDuration:0.6,thenDragTo:finger.withOffset(CGVector(dx:bar,dy:0)))
        XCTAssertGreaterThan(clip.frame.minX,initialX+bar*0.5)
        clip.tap();XCTAssertTrue(app.navigationBars["Clip settings"].waitForExistence(timeout:5))
        XCTAssertEqual(app.steppers["clip.start"].value as? String,"2:1")
        app.buttons["Done"].tap()
        let shot=XCTAttachment(data:XCUIScreen.main.screenshot().pngRepresentation,uniformTypeIdentifier:"public.png")
        shot.name="OriginalVision-arrangement-clips";shot.lifetime = .keepAlways;add(shot)
        app.buttons["Undo"].tap()
        XCTAssertEqual(clip.frame.minX,initialX,accuracy:3)
        XCTAssertEqual(clip.value as? String,"1.00 bars")
        app.buttons["Redo"].tap()
        XCTAssertGreaterThan(clip.frame.minX,initialX+bar*0.5)
    }

    @MainActor func testSectionChipsDragWholeSectionAndUndo(){
        let app=launch("perform")
        XCTAssertTrue(app.buttons["perform.done"].waitForExistence(timeout:5));app.buttons["perform.done"].tap()
        let sections=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.section.'"))
        XCTAssertEqual(sections.count,2)
        let verse=sections.element(boundBy:0),chorus=sections.element(boundBy:1)
        let verseID=verse.identifier,chorusID=chorus.identifier
        verse.press(forDuration:0.6,thenDragTo:chorus)
        let movedVerse=app.buttons[verseID],movedChorus=app.buttons[chorusID]
        wait(movedVerse,NSPredicate(format:"label CONTAINS '5–8'"))
        XCTAssertLessThan(movedChorus.frame.minX,movedVerse.frame.minX)
        XCTAssertTrue(movedChorus.label.contains("1–4"))
        app.buttons["Undo"].tap()
        wait(movedVerse,NSPredicate(format:"label CONTAINS '1–4'"))
        XCTAssertLessThan(movedVerse.frame.minX,movedChorus.frame.minX)
    }
}
