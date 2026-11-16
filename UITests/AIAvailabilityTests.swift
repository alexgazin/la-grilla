import XCTest

/// The Simulator's real model availability is observed, never injected. This
/// covers setup/recheck and the local parser; it does not prove model generation.
final class AIAvailabilityTests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}

    @MainActor func testActualUnavailableModelRecheckPreservesLanguagesInputAndProjectThenLocalJazzAppliesUndo(){
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--runtime-trace","--screen","grid","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        let transport=app.buttons["perform.transport"]
        XCTAssertTrue(transport.waitForExistence(timeout:15))
        let chord=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.chord.'")).firstMatch
        XCTAssertTrue(chord.waitForExistence(timeout:5))
        let originalChord=chord.label
        let originalDocument=documentState(transport)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        app.buttons["assistant.open"].tap()
        XCTAssertTrue(app.navigationBars["Assistant"].waitForExistence(timeout:5))
        let status=app.staticTexts["assistant.ai-status"]
        XCTAssertTrue(status.waitForExistence(timeout:5))
        assertEnvironmentModelUnavailable(status)
        XCTAssertTrue(app.buttons["assistant.use-commands"].exists)
        let options=app.buttons["assistant.ai-options"]
        XCTAssertTrue(options.waitForExistence(timeout:5))
        XCTAssertEqual(options.value as? String,"Collapsed")
        keepScreenshot("AuthorizedInput-assistant-default-composer")
        app.buttons["On-device AI"].tap()
        revealFully(options,in:app)
        options.tap()

        let aiEnglish=app.buttons["assistant.ai-language.en"]
        let aiRussian=app.buttons["assistant.ai-language.ru"]
        let dictationRussian=app.buttons["assistant.language.ru"]
        let dictationEnglish=app.buttons["assistant.language.en"]
        XCTAssertTrue(aiRussian.waitForExistence(timeout:5))
        XCTAssertTrue(aiRussian.isSelected)
        XCTAssertTrue(dictationRussian.isSelected)
        revealFully(aiEnglish,in:app,upward:false)
        aiEnglish.tap()
        wait(aiEnglish){aiEnglish.isSelected}
        XCTAssertFalse(aiRussian.isSelected)
        XCTAssertTrue(dictationRussian.isSelected,"Choosing an AI request language must not change dictation")
        XCTAssertFalse(dictationEnglish.isSelected)

        let examples=app.buttons["assistant.examples"]
        revealFully(examples,in:app)
        examples.tap()
        let jazz=app.buttons["assistant.example.jazzify"]
        XCTAssertTrue(jazz.waitForExistence(timeout:5))
        XCTAssertTrue(jazz.isHittable)
        jazz.tap()
        wait(app.navigationBars["Examples"]){!app.navigationBars["Examples"].exists}
        let input=app.textViews["assistant.input"]
        XCTAssertEqual(input.value as? String,"Поджазуй","Use the real Russian example, without injecting a proposal")
        let request=input.value as? String

        let recheck=app.buttons["assistant.ai-recheck"]
        revealFully(recheck,in:app,upward:false)
        XCTAssertTrue(app.staticTexts["assistant.ai-language-guidance"].exists)
        recheck.tap()
        assertEnvironmentModelUnavailable(status)
        let observedReason=status.value as? String ?? "unknown"
        XCTAssertEqual(input.value as? String,request)
        XCTAssertTrue(aiEnglish.isSelected)
        XCTAssertTrue(dictationRussian.isSelected)
        XCTAssertFalse(dictationEnglish.isSelected)
        XCTAssertEqual(documentState(transport),originalDocument)
        XCTAssertEqual(chord.label,originalChord)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        XCTAssertFalse(app.buttons["assistant.apply"].exists)
        revealFully(aiEnglish,in:app,upward:false)
        keepScreenshot("AuthorizedInput-ai-setup-independent-language-recheck")
        // Finish the actual setup interaction before reviewing music. The
        // compact primary composer stays usable with advanced options closed.
        revealFully(options,in:app,upward:false)
        options.tap()
        XCTAssertEqual(options.value as? String,"Collapsed")

        let generate=app.buttons["assistant.generate"]
        revealFully(generate,in:app)
        generate.tap()
        let fallback=app.staticTexts["assistant.local-fallback"]
        XCTAssertTrue(fallback.waitForExistence(timeout:5))
        revealFully(fallback,in:app)
        XCTAssertEqual(fallback.label,"Reviewed with Commands because on-device AI is unavailable.")
        XCTAssertTrue(app.staticTexts["LOCAL"].exists)
        XCTAssertFalse(app.staticTexts["ON-DEVICE AI"].exists)
        let after=app.staticTexts["assistant.harmony.after.0.0"]
        revealFully(after,in:app)
        XCTAssertEqual(app.staticTexts["assistant.harmony.before.0.0"].label,"C")
        XCTAssertEqual(after.label,"Cmaj9")
        let apply=app.buttons["assistant.apply"]
        revealFully(apply,in:app)
        apply.tap()
        wait(app.navigationBars["Assistant"]){!app.navigationBars["Assistant"].exists}
        wait(chord){chord.exists && chord.isHittable}
        XCTAssertTrue(chord.label.contains("Cmaj9"))
        XCTAssertTrue(app.buttons["Undo"].isEnabled)
        app.buttons["Undo"].tap()
        wait(chord){chord.label==originalChord && !app.buttons["Undo"].isEnabled}
        keepReport("Observed actual model reason: \(observedReason)\nAI request language: en-US\nDictation language: ru-RU\nRequest: Поджазуй\nRecheck preserved input/project/revision/Undo: true\nActual Commands review: C → Cmaj9\nApply then one Undo restored the original Grid chord: true\nReal model generation verified: false",
                   name:"AuthorizedInput-ai-recheck-and-local-jazz-scope")
    }

    @MainActor private func assertEnvironmentModelUnavailable(_ status:XCUIElement){
        let reasons:Set<String>=["unsupportedDevice","notEnabled","modelNotReady","requiresSystem","notIncluded","unavailable"]
        XCTAssertTrue(reasons.contains(status.value as? String ?? ""),
                      "This test requires the Simulator's real environment-level model unavailability; it never overrides readiness or language support")
    }

    @MainActor private func documentState(_ transport:XCUIElement)->String {
        let current=(transport.value as? String ?? "").components(separatedBy:"\n").first ?? ""
        let regex=try! NSRegularExpression(pattern:"\\bproject=[A-Fa-f0-9-]+ revision=[0-9]+")
        guard let match=regex.firstMatch(in:current,range:NSRange(current.startIndex...,in:current)),
              let range=Range(match.range,in:current)else{XCTFail("Actual project/revision trace is missing");return ""}
        return String(current[range])
    }

    @MainActor private func revealFully(_ element:XCUIElement,in app:XCUIApplication,upward:Bool=true){
        let scroll=app.scrollViews["assistant.review-scroll"]
        let appFrame=app.frame
        for _ in 0..<8 {
            let viewport=scroll.frame.intersection(appFrame),frame=element.frame
            if frame.minY>=viewport.minY+8,frame.maxY<=viewport.maxY-8,element.isHittable{return}
            let targetAbove=frame.height>0 && frame.minY<viewport.minY+8
            let targetBelow=frame.height>0 && frame.maxY>viewport.maxY-8
            if targetAbove{scroll.swipeDown()}
            else if targetBelow || upward{scroll.swipeUp()}
            else{scroll.swipeDown()}
        }
        XCTFail("The actual Assistant control was not fully visible: \(element.identifier)")
    }

    @MainActor private func wait(_ element:XCUIElement,condition:()->Bool){
        let deadline=Date().addingTimeInterval(5)
        while Date()<deadline {
            if condition(){return}
            RunLoop.current.run(until:Date().addingTimeInterval(0.1))
        }
        XCTFail("Expected UI state did not settle for \(element)")
    }

    @MainActor private func keepScreenshot(_ name:String){
        let attachment=XCTAttachment(data:XCUIScreen.main.screenshot().pngRepresentation,uniformTypeIdentifier:"public.png")
        attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }

    private func keepReport(_ text:String,name:String){
        let attachment=XCTAttachment(string:text)
        attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
}
