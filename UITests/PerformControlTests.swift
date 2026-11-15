import XCTest

final class PerformControlTests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}

    @MainActor private func launch(largeType:Bool=false)->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--screen","perform","-AppleLanguages","(en)","-AppleLocale","en_US"]
        if largeType{app.launchArguments.append("--large-type")}
        app.launch()
        XCTAssertTrue(app.buttons["perform.play"].waitForExistence(timeout:15))
        return app
    }

    @MainActor private func turnClockwise(_ knob:XCUIElement){
        let center=knob.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        let start=center.withOffset(CGVector(dx:0,dy:-44))
        let end=center.withOffset(CGVector(dx:44,dy:0))
        start.press(forDuration:0.1,thenDragTo:end)
    }

    @MainActor private func waitForValue(_ knob:XCUIElement,_ predicate:NSPredicate){
        let expectation=XCTNSPredicateExpectation(predicate:predicate,object:knob)
        XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:5),.completed)
    }

    @MainActor func testCircularFilterChangesLiveValueAndResets(){
        let app=launch();let knob=app.sliders["perform.filter"]
        XCTAssertTrue(knob.waitForExistence(timeout:5));XCTAssertFalse(knob.isEnabled)
        app.buttons["perform.play"].tap()
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:knob)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:5),.completed)
        XCTAssertGreaterThanOrEqual(knob.frame.height,44)
        XCTAssertEqual(knob.value as? String,"BYPASS")
        turnClockwise(knob)
        waitForValue(knob,NSPredicate(format:"value BEGINSWITH '+'"))
        // The readout is bound to PerformanceController.fx, not local dial state.
        XCTAssertEqual(app.buttons["perform.play"].label,"Stop")
        app.buttons["perform.filter.reset"].tap()
        waitForValue(knob,NSPredicate(format:"value == 'BYPASS'"))
        let center=knob.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        let below=center.withOffset(CGVector(dx:0,dy:45))
        center.press(forDuration:0.1,thenDragTo:below)
        waitForValue(knob,NSPredicate(format:"value BEGINSWITH '-'"))
        knob.doubleTap();waitForValue(knob,NSPredicate(format:"value == 'BYPASS'"))
        app.buttons["perform.panic"].tap()
    }

    @MainActor func testFilterIsReadOnlyDuringTakeReplay(){
        let app=launch();app.buttons["perform.record"].tap()
        let mode=app.staticTexts["perform.mode"]
        waitForValue(mode,NSPredicate(format:"label == 'RECORDING'"))
        let knob=app.sliders["perform.filter"]
        turnClockwise(knob);waitForValue(knob,NSPredicate(format:"value BEGINSWITH '+'"))
        app.buttons["perform.record"].tap()
        let replay=app.buttons["perform.replay"]
        for _ in 0..<6{if replay.isHittable{break};app.scrollViews.firstMatch.swipeUp()}
        XCTAssertTrue(replay.waitForExistence(timeout:5));replay.tap()
        // A disabled replay control may not be hittable. Stop scrolling when
        // its center is visible, rather than swiping past the sheet's top.
        let scroll=app.scrollViews.firstMatch
        for _ in 0..<6 {
            let frame=knob.frame
            if frame.height>0,scroll.frame.contains(CGPoint(x:frame.midX,y:frame.midY)){break}
            scroll.swipeDown()
        }
        XCTAssertTrue(knob.exists);XCTAssertFalse(knob.isEnabled)
        XCTAssertFalse(app.buttons["perform.filter.reset"].isEnabled)
        app.buttons["perform.panic"].tap()
    }

    @MainActor func testLargeTypeFilterAndTransportRemainReachable(){
        let app=launch(largeType:true)
        let knob=app.sliders["perform.filter"],reset=app.buttons["perform.filter.reset"]
        XCTAssertTrue(knob.waitForExistence(timeout:5));XCTAssertTrue(app.buttons["perform.play"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["perform.section.Verse"].frame.width,app.scrollViews.firstMatch.frame.width*0.8)
        app.buttons["perform.play"].tap()
        waitForValue(knob,NSPredicate(format:"enabled == true"))
        let scroll=app.scrollViews.firstMatch
        for _ in 0..<5{
            if scroll.frame.contains(knob.frame.insetBy(dx:0,dy:-10)),reset.isHittable{break}
            scroll.swipeUp()
        }
        XCTAssertTrue(knob.isHittable);XCTAssertGreaterThanOrEqual(knob.frame.height,44)
        XCTAssertTrue(reset.isHittable);XCTAssertGreaterThanOrEqual(reset.frame.height,44)
        XCTAssertTrue(app.buttons["perform.play"].isHittable)
        turnClockwise(knob);waitForValue(knob,NSPredicate(format:"value BEGINSWITH '+'"))
        let shot=XCTAttachment(data:XCUIScreen.main.screenshot().pngRepresentation,uniformTypeIdentifier:"public.png")
        shot.name="OriginalVision-qa-large-perform";shot.lifetime = .keepAlways;add(shot)
        reset.tap();waitForValue(knob,NSPredicate(format:"value == 'BYPASS'"))
        app.buttons["perform.panic"].tap()
    }
}
