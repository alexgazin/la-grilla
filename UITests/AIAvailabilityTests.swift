import XCTest

/// The Simulator's real model availability is observed, never injected. This
/// covers setup/recheck and the local parser; it does not prove model generation.
final class AIAvailabilityTests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}

    @MainActor func testActualUnavailableModelRecheckPreservesIndependentLanguagesInputAndProject(){
        let app=launch()
        let transport=app.buttons["perform.transport"]
        let chord=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.chord.'")).firstMatch
        XCTAssertTrue(chord.waitForExistence(timeout:5))
        let originalChord=chord.label
        let originalDocument=documentState(transport,verifyOutputOnlyStartup:true)
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
        // End this setup journey with the compact primary composer visible.
        // The separate music-review journey starts with a fresh app launch.
        revealFully(options,in:app,upward:false)
        options.tap()
        XCTAssertEqual(options.value as? String,"Collapsed")
        keepReport("Observed actual model reason: \(observedReason)\nAI request language: en-US\nDictation language: ru-RU\nRequest: Поджазуй\nRecheck preserved input/project/revision/chord/Undo: true\nAdvanced options closed after the actual setup interaction: true\nReal model generation verified: false",
                   name:"AuthorizedInput-ai-recheck-independent-language-scope")
    }

    @MainActor func testActualUnavailableModelLocallyReviewsJazzAppliesAndUndoesOnce()throws {
        let app=launch()
        let transport=app.buttons["perform.transport"]
        let chord=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.chord.'")).firstMatch
        XCTAssertTrue(chord.exists || chord.waitForExistence(timeout:5))
        let originalUI=try jazzPhase(app)
        let originalChord=try XCTUnwrap(originalUI.firstChord?.label)
        let originalDocument=documentState(transport,verifyOutputOnlyStartup:true)
        XCTAssertEqual(originalUI.undo?.isEnabled,false)
        app.buttons["assistant.open"].tap()
        XCTAssertTrue(app.navigationBars["Assistant"].waitForExistence(timeout:5))
        let status=app.staticTexts["assistant.ai-status"]
        XCTAssertTrue(status.waitForExistence(timeout:5))
        assertEnvironmentModelUnavailable(status)
        let observedReason=status.value as? String ?? "unknown"
        XCTAssertTrue(app.buttons["assistant.use-commands"].exists)
        app.buttons["On-device AI"].tap()
        let examples=app.buttons["assistant.examples"]
        revealJazzControl(examples,identifier:"assistant.examples",in:app)
        examples.tap()
        let jazz=app.buttons["assistant.example.jazzify"]
        XCTAssertTrue(jazz.waitForExistence(timeout:5))
        XCTAssertTrue(jazz.isHittable)
        jazz.tap()
        wait(app.navigationBars["Examples"]){!app.navigationBars["Examples"].exists}
        XCTAssertEqual(app.textViews["assistant.input"].value as? String,"Поджазуй",
                       "Use the real Russian example, without injecting a proposal")

        let generate=app.buttons["assistant.generate"]
        revealJazzControl(generate,identifier:"assistant.generate",in:app)
        generate.tap()
        let fallback=app.staticTexts["assistant.local-fallback"]
        XCTAssertTrue(fallback.waitForExistence(timeout:5))
        revealJazzControl(fallback,identifier:"assistant.local-fallback",type:.staticText,in:app)
        let fallbackUI=try jazzPhase(app)
        XCTAssertEqual(fallbackUI.element("assistant.local-fallback",type:.staticText)?.label,"Reviewed with Commands because on-device AI is unavailable.")
        XCTAssertTrue(fallbackUI.hasText("LOCAL"))
        XCTAssertFalse(fallbackUI.hasText("ON-DEVICE AI"))
        let after=app.staticTexts["assistant.harmony.after.0.0"]
        revealJazzControl(after,identifier:"assistant.harmony.after.0.0",type:.staticText,in:app)
        let reviewedUI=try jazzPhase(app)
        XCTAssertEqual(reviewedUI.element("assistant.harmony.before.0.0",type:.staticText)?.label,"C")
        XCTAssertEqual(reviewedUI.element("assistant.harmony.after.0.0",type:.staticText)?.label,"Cmaj9")
        XCTAssertEqual(documentState(transport),originalDocument,"Review must not edit the actual project")
        // A modal hierarchy omits the underlying Grid; query its actual live
        // elements directly while keeping visible review fields coherent.
        XCTAssertEqual(chord.label,originalChord)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        let apply=app.buttons["assistant.apply"]
        revealJazzControl(apply,identifier:"assistant.apply",in:app)
        apply.tap()
        wait(app.navigationBars["Assistant"]){!app.navigationBars["Assistant"].exists}
        var appliedUI:JazzPhase?
        wait(chord){
            guard let observed=try? self.jazzPhase(app)else{return false}
            appliedUI=observed
            return observed.firstChord?.label.contains("Cmaj9")==true
                && observed.undo?.isEnabled==true && chord.isHittable
        }
        XCTAssertTrue(try XCTUnwrap(appliedUI?.firstChord?.label).contains("Cmaj9"))
        XCTAssertEqual(appliedUI?.undo?.isEnabled,true)
        app.buttons["Undo"].tap()
        wait(chord){
            guard let observed=try? self.jazzPhase(app)else{return false}
            return observed.firstChord?.label==originalChord && observed.undo?.isEnabled==false
        }
        keepReport("Observed actual model reason: \(observedReason)\nRequest: Поджазуй\nActual Commands review: C → Cmaj9\nReview preserved project/revision/chord/Undo before Apply: true\nApply then one Undo restored the original Grid chord and empty Undo stack: true\nReal model generation verified: false",
                   name:"AuthorizedInput-ai-local-jazz-apply-undo-scope")
    }

    /// One public hierarchy observation per UI phase. Only short labels and
    /// geometry are read here; full runtime values still use transport.value.
    @MainActor private struct JazzPhase {
        let frame:CGRect
        let elements:[any XCUIElementSnapshot]
        func element(_ identifier:String,type:XCUIElement.ElementType)->(any XCUIElementSnapshot)?{
            elements.first{$0.elementType==type && $0.identifier==identifier}
        }
        var firstChord:(any XCUIElementSnapshot)?{elements.first{$0.elementType == .button && $0.identifier.hasPrefix("grid.chord.")}}
        var undo:(any XCUIElementSnapshot)?{elements.first{$0.elementType == .button && $0.label=="Undo"}}
        func hasText(_ label:String)->Bool{elements.contains{$0.elementType == .staticText && $0.label==label}}
    }

    @MainActor private func jazzPhase(_ app:XCUIApplication)throws->JazzPhase {
        let root=try app.snapshot()
        var pending:[any XCUIElementSnapshot]=[root],elements:[any XCUIElementSnapshot]=[]
        while let element=pending.popLast(){elements.append(element);pending.append(contentsOf:element.children.reversed())}
        return JazzPhase(frame:root.frame,elements:elements)
    }

    @MainActor private func revealJazzControl(_ element:XCUIElement,identifier:String,type:XCUIElement.ElementType = .button,in app:XCUIApplication){
        let scroll=app.scrollViews["assistant.review-scroll"]
        for _ in 0..<8 {
            guard let observed=try? jazzPhase(app)else{XCTFail("Actual Assistant hierarchy is unavailable");return}
            let viewport=observed.element("assistant.review-scroll",type:.scrollView)?.frame.intersection(observed.frame) ?? .null
            let frame=observed.element(identifier,type:type)?.frame ?? .null
            if !frame.isNull,!frame.isEmpty,frame.minY>=viewport.minY+8,frame.maxY<=viewport.maxY-8,element.isHittable{return}
            if !frame.isNull,frame.height>0,frame.minY<viewport.minY+8{scroll.swipeDown()}
            else{scroll.swipeUp()}
        }
        XCTFail("The actual Assistant control was not fully visible: \(identifier)")
    }

    @MainActor private func launch()->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        // Typed fallback follows the production output-only startup policy.
        // Simulator shared-input priming belongs to dedicated capture tests.
        app.launchArguments=["--uitesting","--runtime-trace","--device-output-startup","--screen","grid","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        let transport=app.buttons["perform.transport"]
        XCTAssertTrue(transport.exists || transport.waitForExistence(timeout:15))
        return app
    }

    @MainActor private func assertEnvironmentModelUnavailable(_ status:XCUIElement){
        let reasons:Set<String>=["unsupportedDevice","notEnabled","modelNotReady","requiresSystem","notIncluded","unavailable"]
        XCTAssertTrue(reasons.contains(status.value as? String ?? ""),
                      "This test requires the Simulator's real environment-level model unavailability; it never overrides readiness or language support")
    }

    @MainActor private func documentState(_ transport:XCUIElement,verifyOutputOnlyStartup:Bool=false)->String {
        // Read the actual full runtime value once; snapshots truncate it.
        let report=transport.value as? String ?? ""
        let current=report.components(separatedBy:"\n").first ?? ""
        if verifyOutputOnlyStartup {
            let fields=Set(current.split(separator:" ").map(String.init))
            XCTAssertTrue(fields.contains("inputPriming=outputOnly"),"Typed fallback must use the production startup policy")
            XCTAssertTrue(fields.contains("inputConfigured=false"),"Typed fallback must not configure microphone input")
            XCTAssertTrue(fields.contains("error=none"),"The actual output-only startup must complete without an audio error")
            keepReport(report,name:"AuthorizedInput-ai-output-only-startup-runtime")
        }
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
