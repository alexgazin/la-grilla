import XCTest

/// These flows exercise the native editor while the audio transport is running.
/// Sample-accurate audio/MIDI handover is covered by the host kernel tests.
final class LiveEditingTests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=180}

    @MainActor private func launchPlaying()->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--screen","grid","-AppleLanguages","(en)","-AppleLocale","en_US"]
        let trace=ProcessInfo.processInfo.environment["GRILLA_RUNTIME_TRACE"]=="1"
        if trace{app.launchArguments.append("--runtime-trace")}
        app.launch()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout:15))
        let before=trace ? (app.buttons["perform.transport"].value as? String ?? "Missing transport trace value"):""
        app.buttons["Play"].tap()
        let started=app.buttons["Stop"].waitForExistence(timeout:5)
        if trace{
            let after=app.buttons["perform.transport"].value as? String ?? "Missing transport trace value"
            let attachment=XCTAttachment(string:"BEFORE SINGLE PLAY TAP\n\(before)\nAFTER STOP WAIT (started=\(started))\n\(after)")
            attachment.name="Single-Play actual runtime trace";attachment.lifetime = .keepAlways;add(attachment)
        }
        XCTAssertTrue(started)
        return app
    }

    @MainActor private func wait(_ element:XCUIElement,_ predicate:NSPredicate,timeout:TimeInterval=5){
        let result=XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:element)],timeout:timeout)
        if result != .completed {
            let context=XCTAttachment(string:XCUIApplication().debugDescription)
            context.name="LiveEditing failed wait — actual app hierarchy"
            context.lifetime = .keepAlways
            add(context)
        }
        XCTAssertEqual(result,.completed)
    }

    @MainActor private func waitForBassValue(_ control:XCUIElement,initial:String,restored:Bool){
        var observed:String?
        // Query one fresh native snapshot per poll. The earlier KVC predicate
        // timed out while the recording and fresh whole-app AX already showed
        // the restored switch on; a retained XCUIElement value is insufficient.
        let predicate=NSPredicate{_,_ in
            guard let snapshot=try? control.snapshot(),snapshot.elementType == .switch,
                  snapshot.identifier=="bass.enabled",snapshot.isEnabled,
                  let value=snapshot.value as? String,["0","1"].contains(value)else{return false}
            observed=value
            return restored ? value==initial:value != initial
        }
        let result=XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:5)
        if result != .completed {
            let context=XCTAttachment(string:"Last actual switch value: \(observed ?? "unavailable")\n"+XCUIApplication().debugDescription)
            context.name="LiveEditing failed fresh bass observation — actual app hierarchy"
            context.lifetime = .keepAlways
            add(context)
        }
        XCTAssertEqual(result,.completed)
        if restored{XCTAssertEqual(observed,initial)}else{XCTAssertNotNil(observed);XCTAssertNotEqual(observed,initial)}
    }

    @MainActor private func waitForNoteCount(_ control:XCUIElement,expected:String){
        var observed:String?
        // Count is a changing label too. Observe its actual fresh node rather
        // than retain a KVC value; a missing node or the wrong count still fails.
        let predicate=NSPredicate{_,_ in
            guard let snapshot=try? control.snapshot(),snapshot.elementType == .staticText,
                  snapshot.identifier=="notes.count"else{return false}
            observed=snapshot.label
            return observed==expected
        }
        let result=XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:5)
        if result != .completed {
            let context=XCTAttachment(string:"Last actual note count: \(observed ?? "unavailable")\n"+XCUIApplication().debugDescription)
            context.name="LiveEditing failed fresh note count — actual app hierarchy"
            context.lifetime = .keepAlways
            add(context)
        }
        XCTAssertEqual(result,.completed)
        XCTAssertEqual(observed,expected)
    }

    @MainActor private func playing(_ element:XCUIElement){
        XCTAssertTrue(element.waitForExistence(timeout:5))
        let expectedIdentifier=element.identifier
        guard !expectedIdentifier.isEmpty else{XCTFail("The actual playback status must expose its stable identifier");return}
        var actual="No native snapshot observed"
        // After a List reorder the retained KVC label predicate timed out while
        // the original recording and fresh AX hierarchy both showed PLAYING.
        // Read the actual identified native node anew on every bounded poll.
        let predicate=NSPredicate{_,_ in
            guard let snapshot=try? element.snapshot()else{actual="Native snapshot unavailable";return false}
            actual="identifier=\(snapshot.identifier), type=\(snapshot.elementType.rawValue), label=\(snapshot.label), value=\(String(describing:snapshot.value))"
            return snapshot.elementType == .staticText && snapshot.identifier==expectedIdentifier && snapshot.label=="PLAYING"
        }
        let result=XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:nil)],timeout:5)
        if result != .completed {
            let context=XCTAttachment(string:"Expected identifier=\(expectedIdentifier), type=\(XCUIElement.ElementType.staticText.rawValue), label=PLAYING\nLast actual observation: \(actual)\n"+XCUIApplication().debugDescription)
            context.name="LiveEditing failed fresh playback observation — actual app hierarchy"
            context.lifetime = .keepAlways
            add(context)
        }
        XCTAssertEqual(result,.completed)
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
        XCTAssertTrue(toggle.isEnabled)
        XCTAssertLessThanOrEqual(toggle.frame.width,80,"The native switch must not inherit the entire Form row's hit region")
        assertMinimumTouchDimension(toggle.frame.height)
        let initial=toggle.value as? String
        XCTAssertNotNil(initial)
        guard let initial,["0","1"].contains(initial)else{XCTFail("The actual bass switch must expose a binary initial value");return}
        // These physical taps are outside the native ~27pt thumb, inside the
        // 44pt target. Each must toggle once through UISwitch.valueChanged.
        let center=toggle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5))
        center.withOffset(CGVector(dx:0,dy:-20)).tap()
        waitForBassValue(toggle,initial:initial,restored:false)
        playing(app.staticTexts["bass.playback-state"])
        center.withOffset(CGVector(dx:0,dy:20)).tap()
        waitForBassValue(toggle,initial:initial,restored:true)
        playing(app.staticTexts["bass.playback-state"])
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout:5))

        // Opening Notes creates the first melody if none exists. Both that path
        // and subsequent add/delete actions must retain the running transport.
        app.buttons["notes.open"].tap()
        playing(app.staticTexts["notes.status"])
        app.buttons["notes.tracks"].tap()
        XCTAssertTrue(app.navigationBars["Track"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["notes.track.add"].waitForExistence(timeout:5))
        screenshot("OriginalVision-qa-melody-track-actions")
        app.buttons["notes.track.add"].tap()
        XCTAssertTrue(app.navigationBars["Piano roll"].waitForExistence(timeout:5))
        playing(app.staticTexts["notes.status"])
        XCTAssertTrue(app.buttons["notes.add"].exists)
        app.buttons["notes.add"].tap()
        waitForNoteCount(app.staticTexts["notes.count"],expected:"1")
        app.buttons["notes.tracks"].tap()
        XCTAssertTrue(app.navigationBars["Track"].waitForExistence(timeout:5))
        app.buttons["notes.track.delete"].tap()
        XCTAssertTrue(app.navigationBars["Piano roll"].waitForExistence(timeout:5))
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
        screenshot("OriginalVision-qa-assistant-examples")
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
