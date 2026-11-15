import XCTest

final class AssistantCompositionTests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}
    @MainActor private func launch()->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--uitesting","--screen","assistant-song-proposal","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();XCTAssertTrue(app.navigationBars["Assistant"].waitForExistence(timeout:15));return app
    }
    @MainActor private func reveal(_ element:XCUIElement,in app:XCUIApplication){
        for _ in 0..<8{if element.isHittable{return};app.scrollViews.firstMatch.swipeUp()}
        XCTAssertTrue(element.isHittable)
    }
    @MainActor func testFullSongReviewAppliesAsOneUndoOnCommandFallback(){
        let app=launch()
        let review=app.descendants(matching:.any)["assistant.form-review"].firstMatch
        reveal(review,in:app);XCTAssertTrue(app.staticTexts["PROPOSED FORM"].exists)
        let shot=XCTAttachment(data:XCUIScreen.main.screenshot().pngRepresentation,uniformTypeIdentifier:"public.png");shot.name="OriginalVision-assistant-song-review";shot.lifetime = .keepAlways;add(shot)
        let apply=app.buttons["assistant.apply"];reveal(apply,in:app);apply.tap()
        let tempo=app.staticTexts["studio.tempo"];XCTAssertTrue(tempo.waitForExistence(timeout:5));XCTAssertEqual(tempo.label,"108 BPM")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.section.' AND label CONTAINS 'Intro'")).firstMatch.exists)
        app.buttons["Undo"].tap();XCTAssertEqual(tempo.label,"120 BPM")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.section.' AND label CONTAINS 'Intro'")).firstMatch.exists)
        app.buttons["Redo"].tap();XCTAssertEqual(tempo.label,"108 BPM")
    }
    @MainActor func testFullSongCancelKeepsOriginalAndAvailabilityIsVisible(){
        let app=launch();XCTAssertTrue(app.staticTexts["assistant.ai-status"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["assistant.ai-status"].label.isEmpty)
        app.buttons["Cancel"].tap()
        let tempo=app.staticTexts["studio.tempo"];XCTAssertTrue(tempo.waitForExistence(timeout:5));XCTAssertEqual(tempo.label,"120 BPM")
        XCTAssertFalse(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.section.' AND label CONTAINS 'Intro'")).firstMatch.exists)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
    }
}
