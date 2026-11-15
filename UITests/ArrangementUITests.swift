import XCTest

final class ArrangementUITests: XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}

    @MainActor private func launch(_ screen:String="grid")->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--screen",screen,"--arrangement-clips","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:15))
        if screen=="grid"{wait(app.buttons["grid.mode.clips"],NSPredicate(format:"value == 'Clips'"))}
        return app
    }
    @MainActor private func wait(_ element:XCUIElement,_ predicate:NSPredicate){
        let expectation=XCTNSPredicateExpectation(predicate:predicate,object:element)
        XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:6),.completed)
    }
    @MainActor private func drag(_ source:XCUICoordinate,to destination:XCUICoordinate){
        // Give UIKit time to lift the native Transferable before moving, then
        // dwell over the receiver. A 0.6s press with immediate release raced the
        // lift/target registration in the recorded iOS 26 simulator run.
        source.press(forDuration:1.2,thenDragTo:destination,withVelocity:.slow,thenHoldForDuration:0.6)
    }

    @MainActor func testClipTapResizeNativeDragAndUndo(){
        let app=launch()
        let clips=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.clip.' AND label == 'Harmony'"))
        let harmony=clips.firstMatch
        XCTAssertTrue(harmony.waitForExistence(timeout:5))
        wait(harmony,NSPredicate(format:"hittable == true"))
        let id=harmony.identifier
        // This is the actual clip hit target, including its drawn waveform.
        harmony.coordinate(withNormalizedOffset:CGVector(dx:0.4,dy:0.5)).tap()
        XCTAssertTrue(app.navigationBars["Clip settings"].waitForExistence(timeout:5))
        let length=app.steppers["clip.length"]
        XCTAssertTrue(length.waitForExistence(timeout:5))
        let decrement=length.buttons["clip.length-Decrement"]
        XCTAssertTrue(decrement.waitForExistence(timeout:5))
        for _ in 0..<3{decrement.tap()}
        wait(length,NSPredicate(format:"value == '1.00 bars'"))
        app.buttons["Done"].tap()
        let clip=app.buttons[id]
        wait(clip,NSPredicate(format:"value == '1.00 bars'"))
        wait(clip,NSPredicate(format:"hittable == true"))
        wait(clip,NSPredicate{_,_ in clip.frame.width+6<app.windows.firstMatch.frame.width/2})
        let initialX=clip.frame.minX,bar=clip.frame.width+6
        XCTAssertLessThan(bar,app.windows.firstMatch.frame.width/2,"Clip accessibility frame must match the one-bar clip, not its entire lane")
        let finger=clip.coordinate(withNormalizedOffset:CGVector(dx:0.4,dy:0.5))
        drag(finger,to:finger.withOffset(CGVector(dx:bar,dy:0)))
        XCTAssertGreaterThan(clip.frame.minX,initialX+bar*0.5)
        clip.tap();XCTAssertTrue(app.navigationBars["Clip settings"].waitForExistence(timeout:5))
        XCTAssertEqual(app.steppers["clip.start"].value as? String,"2:1")
        app.buttons["Done"].tap()
        let shot=XCTAttachment(data:XCUIScreen.main.screenshot().pngRepresentation,uniformTypeIdentifier:"public.png")
        shot.name="OriginalVision-original-vision-arrangement-clips";shot.lifetime = .keepAlways;add(shot)
        app.buttons["Undo"].tap()
        XCTAssertEqual(clip.frame.minX,initialX,accuracy:3)
        XCTAssertEqual(clip.value as? String,"1.00 bars")
        app.buttons["Redo"].tap()
        XCTAssertGreaterThan(clip.frame.minX,initialX+bar*0.5)
    }

    @MainActor func testAccessibleAddClipPreservesExistingClipsAndIsUndoable(){
        let app=launch()
        let originalDrums=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.clip.' AND label == 'Drums'")).firstMatch
        XCTAssertTrue(originalDrums.waitForExistence(timeout:5))
        wait(originalDrums,NSPredicate(format:"hittable == true"))
        let originalID=originalDrums.identifier,originalLength=originalDrums.value as? String
        app.buttons["grid.clips.list"].tap()
        XCTAssertTrue(app.navigationBars["Clip list"].waitForExistence(timeout:5))
        let bass=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.clip.add.bass.'")).firstMatch
        XCTAssertTrue(bass.exists);XCTAssertFalse(bass.isEnabled)
        XCTAssertTrue(app.staticTexts["Root bass follows harmony and cannot hold independent clips."].exists)
        let add=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.clip.add.drums.'")).firstMatch
        XCTAssertTrue(add.exists);XCTAssertEqual(add.label,"Add clip to Drums")
        XCTAssertGreaterThanOrEqual(add.frame.height,44)
        add.tap()
        XCTAssertTrue(app.navigationBars["Clip settings"].waitForExistence(timeout:5))
        XCTAssertEqual(app.steppers["clip.start"].value as? String,"5:1")
        XCTAssertEqual(app.steppers["clip.length"].value as? String,"1.00 bars")
        app.buttons["Done"].tap()
        XCTAssertEqual(app.buttons[originalID].value as? String,originalLength)
        XCTAssertTrue(app.buttons["Undo"].isEnabled);app.buttons["Undo"].tap()
        app.buttons["grid.clips.list"].tap()
        let rows=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.clip.list.'"))
        XCTAssertEqual(rows.count,2)
        app.buttons["Done"].tap();XCTAssertTrue(app.buttons["Redo"].isEnabled);app.buttons["Redo"].tap()
        app.buttons["grid.clips.list"].tap();XCTAssertEqual(rows.count,3)
    }

    @MainActor func testSectionChipsDragWholeSectionAndUndo(){
        let app=launch("perform")
        XCTAssertTrue(app.buttons["perform.done"].waitForExistence(timeout:5));app.buttons["perform.done"].tap()
        wait(app.buttons["grid.mode.clips"],NSPredicate(format:"value == 'Clips'"))
        let sections=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.section.'"))
        XCTAssertEqual(sections.count,2)
        let verse=sections.element(boundBy:0),chorus=sections.element(boundBy:1)
        let verseID=verse.identifier,chorusID=chorus.identifier
        wait(verse,NSPredicate(format:"hittable == true"));wait(chorus,NSPredicate(format:"hittable == true"))
        drag(verse.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)),to:chorus.coordinate(withNormalizedOffset:CGVector(dx:0.6,dy:0.5)))
        let movedVerse=app.buttons[verseID],movedChorus=app.buttons[chorusID]
        wait(movedVerse,NSPredicate(format:"label CONTAINS '5–8'"))
        XCTAssertLessThan(movedChorus.frame.minX,movedVerse.frame.minX)
        XCTAssertTrue(movedChorus.label.contains("1–4"))
        app.buttons["Undo"].tap()
        wait(movedVerse,NSPredicate(format:"label CONTAINS '1–4'"))
        XCTAssertLessThan(movedVerse.frame.minX,movedChorus.frame.minX)
    }
}
