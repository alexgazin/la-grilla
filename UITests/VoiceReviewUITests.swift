import XCTest

final class VoiceReviewUITests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}
    @MainActor private func reveal(_ element:XCUIElement,in app:XCUIApplication,up:Bool=true){
        let scroll=app.scrollViews.firstMatch
        func visible()->Bool {
            guard element.exists,element.isHittable else{return false}
            let frame=element.frame,window=app.windows.firstMatch.frame,scrollFrame=scroll.frame
            let navigationBottom=app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY:window.minY
            let viewport=CGRect(x:max(window.minX,scrollFrame.minX),y:max(navigationBottom,scrollFrame.minY),width:min(window.maxX,scrollFrame.maxX)-max(window.minX,scrollFrame.minX),height:min(window.maxY,scrollFrame.maxY)-max(navigationBottom,scrollFrame.minY)).insetBy(dx:4,dy:4)
            // SwiftUI can report clipped offscreen buttons as hittable. Require
            // the actual control to be entirely inside the visible viewport.
            return frame.minX.isFinite && frame.minY.isFinite && frame.width.isFinite && frame.height.isFinite && frame.width>0 && frame.height>0 && viewport.contains(frame)
        }
        for _ in 0..<12 {
            if visible(){return}
            if up{scroll.swipeUp()}else{scroll.swipeDown()}
        }
        XCTAssertTrue(element.exists);XCTAssertTrue(visible(),"Control is outside the visible scroll viewport: "+element.debugDescription)
    }
    @MainActor func testLiveMixEditRequiresExplicitReviewAndPreservesManualNotesAndSource(){
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--screen","voice-draft","--voice-review-fixture","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["voice.note-count"].waitForExistence(timeout:20))
        XCTAssertEqual(app.staticTexts["voice.note-count"].label,"3 notes")
        let pitch=app.steppers["voice.pitch"];reveal(pitch,in:app)
        // iOS 26 prefixes native Stepper child identifiers with the parent ID.
        let increment=pitch.buttons["voice.pitch-Increment"]
        XCTAssertTrue(increment.waitForExistence(timeout:3));increment.tap()
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
        let preview=app.staticTexts["voice.fixture-preview"]
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == 'PREVIEW'"),object:preview)],timeout:5),.completed,"Instrument tap must start the reviewed candidate before testing Stop")
        let stop=app.buttons["voice.stop-preview"];reveal(stop,in:app);stop.tap()
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == 'ORIGINAL'"),object:preview)],timeout:5),.completed)
        XCTAssertFalse(stop.exists)
        XCTAssertEqual(app.staticTexts["voice.fixture-transport"].label,"PLAYING")
        XCTAssertEqual(app.staticTexts["voice.fixture-source"].label,source)
        XCTAssertEqual(app.staticTexts["voice.fixture-pitch"].label,"61")
        reveal(apply,in:app)
        let attachment=XCTAttachment(data:XCUIScreen.main.screenshot().pngRepresentation,uniformTypeIdentifier:"public.png")
        attachment.name="OriginalVision-qa-voice-live-review";attachment.lifetime = .keepAlways;add(attachment)
        apply.tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout:10))
        XCTAssertTrue(app.buttons["Undo"].exists)
        app.buttons["Stop"].tap()
    }
}
