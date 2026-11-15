import XCTest

/// These flows exercise the native editor while the audio transport is running.
/// Sample-accurate audio/MIDI handover is covered by the host kernel tests.
final class LiveEditingTests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=180}

    @MainActor private func launchPlaying()->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--screen","grid","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout:15))
        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout:5))
        return app
    }

    @MainActor private func wait(_ element:XCUIElement,_ predicate:NSPredicate,timeout:TimeInterval=5){
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:element)],timeout:timeout),.completed)
    }

    @MainActor private func playing(_ element:XCUIElement){
        XCTAssertTrue(element.waitForExistence(timeout:5))
        wait(element,NSPredicate(format:"label == 'PLAYING'"))
    }
    @MainActor private func toggleThumb(_ toggle:XCUIElement){
        // SwiftUI exposes the whole Form row as the switch's AX frame. Its
        // center is the label; the visible native thumb is at the trailing edge.
        toggle.coordinate(withNormalizedOffset:CGVector(dx:0.9,dy:0.5)).tap()
    }

    @MainActor private func reveal(_ element:XCUIElement,in app:XCUIApplication){
        for _ in 0..<12 {
            if element.exists && element.isHittable{return}
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(element.exists);XCTAssertTrue(element.isHittable)
    }

    @MainActor private func screenshot(_ name:String){
        let attachment=XCTAttachment(data:XCUIScreen.main.screenshot().pngRepresentation,uniformTypeIdentifier:"public.png")
        attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }

    @MainActor func testBassAndMelodyTrackEditsKeepPlaybackRunning(){
        let app=launchPlaying()
        app.buttons["bass.open"].tap()
        let toggle=app.switches["bass.enabled"]
        XCTAssertTrue(toggle.waitForExistence(timeout:5))
        let initial=toggle.value as? String
        XCTAssertNotNil(initial)
        toggleThumb(toggle);wait(toggle,NSPredicate(format:"value != %@",initial ?? ""))
        playing(app.staticTexts["bass.playback-state"])
        toggleThumb(toggle);wait(toggle,NSPredicate(format:"value == %@",initial ?? ""))
        playing(app.staticTexts["bass.playback-state"])
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout:5))

        // Opening Notes creates the first melody if none exists. Both that path
        // and subsequent add/delete actions must retain the running transport.
        app.buttons["notes.open"].tap()
        playing(app.staticTexts["notes.status"])
        app.buttons["notes.tracks"].tap();app.buttons["Add melody"].tap()
        playing(app.staticTexts["notes.status"])
        XCTAssertTrue(app.buttons["notes.add"].exists)
        app.buttons["notes.add"].tap()
        wait(app.staticTexts["notes.count"],NSPredicate(format:"label == '1'"))
        app.buttons["notes.tracks"].tap();app.buttons["Delete track"].tap()
        playing(app.staticTexts["notes.status"])
        screenshot("OriginalVision-qa-live-track-editing")
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout:5));app.buttons["Stop"].tap()
    }

    @MainActor func testDuplicateMoveAndDeleteSectionDuringPlayback(){
        let app=launchPlaying();app.buttons["sections.open"].tap()
        XCTAssertTrue(app.navigationBars["Song sections"].waitForExistence(timeout:5))
        let menus=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'section.menu.'"))
        XCTAssertTrue(menus.firstMatch.waitForExistence(timeout:5))
        XCTAssertGreaterThan(menus.count,0)
        let original=menus.allElementsBoundByIndex.map(\.identifier)
        let first=original[0]
        app.buttons[first].tap();app.buttons["section.duplicate"].tap()
        let count=XCTNSPredicateExpectation(predicate:NSPredicate{_,_ in menus.count==original.count+1},object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[count],timeout:5),.completed)
        playing(app.staticTexts["section.playback-state"])
        let duplicate=menus.allElementsBoundByIndex.map(\.identifier).first{!original.contains($0)}
        guard let duplicate else{XCTFail("Duplicate section did not appear");return}
        app.buttons[duplicate].tap();app.buttons["section.earlier"].tap()
        wait(menus.element(boundBy:0),NSPredicate(format:"identifier == %@",duplicate))
        playing(app.staticTexts["section.playback-state"])
        app.buttons[duplicate].tap();app.buttons["section.later"].tap()
        wait(menus.element(boundBy:1),NSPredicate(format:"identifier == %@",duplicate))
        playing(app.staticTexts["section.playback-state"])
        screenshot("OriginalVision-qa-live-section-editing")
        app.buttons[duplicate].tap();app.buttons["section.delete"].tap()
        XCTAssertTrue(app.alerts["Delete section?"].waitForExistence(timeout:5));app.alerts.buttons["Delete"].tap()
        wait(app.buttons[duplicate],NSPredicate(format:"exists == false"))
        XCTAssertEqual(menus.count,original.count)
        playing(app.staticTexts["section.playback-state"])
        XCTAssertFalse(app.alerts["Stop playback first"].exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout:5));app.buttons["Stop"].tap()
    }

    @MainActor func testAssistantWholeSongABAndStopRestoreRunningProject(){
        let app=launchPlaying();app.buttons["assistant.open"].tap()
        XCTAssertTrue(app.navigationBars["Assistant"].waitForExistence(timeout:5))
        app.buttons["assistant.examples"].tap()
        XCTAssertTrue(app.navigationBars["Examples"].waitForExistence(timeout:5))
        let example=app.buttons["assistant.example.song-form"];reveal(example,in:app);example.tap()
        XCTAssertTrue(app.navigationBars["Assistant"].waitForExistence(timeout:5))
        let review=app.buttons["assistant.generate"];reveal(review,in:app);review.tap()
        let proposal=app.buttons["assistant.b"];reveal(proposal,in:app)
        XCTAssertTrue(app.descendants(matching:.any)["assistant.form-review"].exists)
        proposal.tap();playing(app.staticTexts["assistant.preview-state"])
        let original=app.buttons["assistant.a"];reveal(original,in:app);original.tap()
        playing(app.staticTexts["assistant.preview-state"])
        reveal(proposal,in:app);proposal.tap()
        let stop=app.buttons["assistant.stop-preview"];reveal(stop,in:app);stop.tap()
        playing(app.staticTexts["assistant.preview-state"])
        XCTAssertFalse(stop.exists)
        screenshot("OriginalVision-qa-live-assistant-preview")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["studio.tempo"].label,"120 BPM")
        app.buttons["Stop"].tap()
    }
}
