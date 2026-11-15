import XCTest

final class VoiceReviewUITests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}
    @MainActor private func reveal(_ element:XCUIElement,in app:XCUIApplication,up:Bool=true){
        for _ in 0..<12 {
            if element.exists && element.isHittable{return}
            if up{app.scrollViews.firstMatch.swipeUp()}else{app.scrollViews.firstMatch.swipeDown()}
        }
        XCTAssertTrue(element.exists);XCTAssertTrue(element.isHittable)
    }
    @MainActor func testLiveMixEditRequiresExplicitReviewAndPreservesManualNotesAndSource(){
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--screen","voice-draft","--voice-review-fixture","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["voice.note-count"].waitForExistence(timeout:20))
        XCTAssertEqual(app.staticTexts["voice.note-count"].label,"3 notes")
        let pitch=app.steppers["voice.pitch"];reveal(pitch,in:app)
        pitch.buttons["Increment"].tap()
        let edit=app.buttons["voice.fixture-edit"];reveal(edit,in:app)
        let source=app.staticTexts["voice.fixture-source"].label
        XCTAssertEqual(app.staticTexts["voice.fixture-pitch"].label,"61")
        edit.tap()
        let apply=app.buttons["voice.apply"]
        XCTAssertFalse(apply.isEnabled)
        let rebase=app.buttons["voice.rebase"];reveal(rebase,in:app);rebase.tap()
        XCTAssertFalse(rebase.exists)
        XCTAssertTrue(apply.isEnabled)
        XCTAssertEqual(app.staticTexts["voice.fixture-source"].label,source)
        XCTAssertEqual(app.staticTexts["voice.fixture-pitch"].label,"61")
        XCTAssertEqual(app.staticTexts["voice.note-count"].label,"3 notes")
        let instrument=app.buttons["voice.instrument"];reveal(instrument,in:app,up:false);instrument.tap()
        XCTAssertEqual(app.staticTexts["voice.fixture-transport"].label,"PLAYING")
        let stop=app.buttons["Stop preview"];reveal(stop,in:app);stop.tap()
        XCTAssertEqual(app.staticTexts["voice.fixture-transport"].label,"PLAYING")
        reveal(apply,in:app)
        let attachment=XCTAttachment(data:XCUIScreen.main.screenshot().pngRepresentation,uniformTypeIdentifier:"public.png")
        attachment.name="OriginalVision-qa-voice-live-review";attachment.lifetime = .keepAlways;add(attachment)
        apply.tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["Undo"].exists)
        app.buttons["Stop"].tap()
    }
}
