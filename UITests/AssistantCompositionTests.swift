import XCTest

final class AssistantCompositionTests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}
    @MainActor private func launch(screen:String="assistant-song-proposal")->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--uitesting","--device-output-startup","--screen",screen,"-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        if screen=="grid"{XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:15))}
        else{XCTAssertTrue(app.navigationBars["Assistant"].waitForExistence(timeout:15))}
        return app
    }
    @MainActor private func reveal(_ element:XCUIElement,in app:XCUIApplication){
        for _ in 0..<8{if element.isHittable{return};app.scrollViews["assistant.review-scroll"].swipeUp()}
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
    @MainActor func testJazzCommandShowsActualHarmonyBeforeApplyAndUndoesOnce(){
        let app=launch(screen:"grid")
        let firstChord=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.chord.'")).firstMatch
        XCTAssertTrue(firstChord.waitForExistence(timeout:5))
        let originalLabel=firstChord.label
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        openJazzReview(app)
        let before=app.staticTexts["assistant.harmony.before.0.0"]
        let after=app.staticTexts["assistant.harmony.after.0.0"]
        revealFully(before,in:app);XCTAssertEqual(before.label,"C")
        XCTAssertEqual(after.label,"Cmaj9")
        XCTAssertEqual(app.staticTexts["assistant.harmony.section.0"].label,"Verse")
        XCTAssertEqual(app.staticTexts["assistant.harmony.before.0.0.timing"].label,"Bar 1:1 · 4 beats")
        XCTAssertEqual(app.staticTexts["assistant.harmony.after.0.0.timing"].label,"Bar 1:1 · 4 beats")
        XCTAssertEqual(app.staticTexts["assistant.harmony.before.0.1"].label,"Am")
        XCTAssertEqual(app.staticTexts["assistant.harmony.after.0.1"].label,"Am9")
        let shot=XCTAttachment(data:XCUIScreen.main.screenshot().pngRepresentation,uniformTypeIdentifier:"public.png")
        shot.name="OriginalVision-qa-assistant-harmony-diff";shot.lifetime = .keepAlways;add(shot)
        // Reviewing and cancelling must leave both the actual grid and Undo untouched.
        app.buttons["Cancel"].tap();XCTAssertTrue(firstChord.waitForExistence(timeout:5))
        XCTAssertEqual(firstChord.label,originalLabel);XCTAssertFalse(app.buttons["Undo"].isEnabled)
        openJazzReview(app)
        let apply=app.buttons["assistant.apply"];revealFully(apply,in:app);apply.tap()
        XCTAssertTrue(firstChord.waitForExistence(timeout:5));XCTAssertTrue(app.buttons["Undo"].isEnabled)
        firstChord.tap();XCTAssertTrue(app.textFields["chord.symbol"].waitForExistence(timeout:5))
        XCTAssertEqual(app.textFields["chord.symbol"].value as? String,"Cmaj9")
        app.buttons["Cancel"].tap();app.buttons["Undo"].tap()
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        firstChord.tap();XCTAssertTrue(app.textFields["chord.symbol"].waitForExistence(timeout:5))
        XCTAssertEqual(app.textFields["chord.symbol"].value as? String,"C")
    }
    @MainActor func testIdleProposalEndsOnModeChangeWithoutEditing(){
        verifyIdleProposalEndsWithoutEditing(change:"mode")
    }
    @MainActor func testIdleProposalEndsOnLanguageChangeWithoutEditing(){
        verifyIdleProposalEndsWithoutEditing(change:"language")
    }
    @MainActor private func verifyIdleProposalEndsWithoutEditing(change:String){
            let app=launch()
            let state=app.staticTexts["assistant.preview-state"]
            XCTAssertTrue(state.waitForExistence(timeout:5));XCTAssertEqual(state.label,"STOPPED")
            XCTAssertEqual(state.value as? String,"Original")
            let proposal=app.buttons["assistant.b"];revealFully(proposal,in:app);proposal.tap()
            wait(state,NSPredicate(format:"label == 'PLAYING' AND value == 'Preview'"))
            let control=change=="mode" ? app.buttons["Commands"]:app.buttons["assistant.language.en"]
            let scroll=app.scrollViews["assistant.review-scroll"]
            for _ in 0..<10 {
                let viewport=scroll.frame.intersection(app.frame),frame=control.frame
                if control.isHittable,frame.minY>=viewport.minY+8,frame.maxY<=viewport.maxY-8{break}
                scroll.swipeDown()
            }
            XCTAssertTrue(control.isHittable)
            if change=="language"{assertMinimumTouchDimension(control.frame.height);XCTAssertFalse(control.isSelected)}
            control.tap()
            if change=="language" {
                wait(control,NSPredicate{_,_ in control.exists && control.isSelected})
                XCTAssertEqual(control.label,"EN")
                XCTAssertFalse(app.buttons["assistant.language.ru"].isSelected)
            }
            // Check the actual Session preview flag and transport even after
            // the review controls disappear; hiding the proposal is insufficient.
            wait(state,NSPredicate(format:"label == 'STOPPED' AND value == 'Original'"))
            XCTAssertFalse(app.buttons["assistant.b"].exists)
            app.buttons["Cancel"].tap()
            // Grid's accessibility elements can exist beneath Assistant.
            // Require the actual sheet to close before touching the editor.
            wait(app.navigationBars["Assistant"],NSPredicate(format:"exists == false"))
            let tempo=app.staticTexts["studio.tempo"];XCTAssertTrue(tempo.waitForExistence(timeout:5))
            XCTAssertEqual(tempo.label,"120 BPM");XCTAssertTrue(app.buttons["Play"].exists)
            XCTAssertFalse(app.buttons["Undo"].isEnabled)
            XCTAssertFalse(app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.section.' AND label CONTAINS 'Intro'")).firstMatch.exists)
            let chord=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.chord.'")).firstMatch
            XCTAssertTrue(chord.exists)
            guard tapMeasuredGridChord(chord,in:app)else{app.terminate();return}
            XCTAssertTrue(app.textFields["chord.symbol"].waitForExistence(timeout:5))
            XCTAssertEqual(app.textFields["chord.symbol"].value as? String,"C")
            app.terminate()
    }
    @MainActor private func tapMeasuredGridChord(_ control:XCUIElement,in app:XCUIApplication)->Bool {
        func finite(_ frame:CGRect)->Bool{!frame.isEmpty && [frame.minX,frame.minY,frame.maxX,frame.maxY].allSatisfy{$0.isFinite}}
        func fail(_ reason:String)->Bool {
            let context=XCTAttachment(string:reason+"\n"+app.debugDescription)
            context.name="Assistant post-dismiss Grid — actual app hierarchy";context.lifetime = .keepAlways;add(context)
            XCTFail(reason);return false
        }
        guard let observed=try? control.snapshot(),observed.elementType == .button,
              observed.identifier.hasPrefix("grid.chord."),observed.isEnabled,finite(observed.frame),
              let root=try? app.snapshot(),finite(root.frame)else{return fail("The real enabled Grid chord must be observable after closing Assistant")}
        var matches:[(node:any XCUIElementSnapshot,ancestors:[any XCUIElementSnapshot])]=[]
        var pending:[(node:any XCUIElementSnapshot,ancestors:[any XCUIElementSnapshot])]=[(root,[])]
        while let entry=pending.popLast(){
            let node=entry.node
            if node.identifier=="assistant.review-scroll" || (node.elementType == .navigationBar && (node.identifier=="Assistant" || node.label=="Assistant")){
                return fail("Assistant must be absent from the fresh hierarchy before touching Grid")
            }
            if node.identifier==observed.identifier{matches.append(entry)}
            for child in node.children{pending.append((child,entry.ancestors+[node]))}
        }
        guard matches.count==1,let target=matches.first,
              target.node.elementType == .button,target.node.isEnabled,
              target.node.label==observed.label,target.node.frame==observed.frame,
              let window=target.ancestors.last(where:{$0.elementType == .window}),finite(window.frame)else{
            return fail("The fresh app hierarchy must contain exactly the same actual Grid chord")
        }
        let scrollTypes:[XCUIElement.ElementType]=[.scrollView,.collectionView,.table]
        let owners=target.ancestors.filter{scrollTypes.contains($0.elementType)}
        guard !owners.isEmpty,owners.allSatisfy({finite($0.frame)})else{return fail("A real scroll viewport must own the Grid chord")}
        let viewport=owners.reduce(root.frame.intersection(window.frame)){$0.intersection($1.frame)}
        let frame=target.node.frame
        guard finite(viewport),viewport.contains(frame)else{return fail("The whole actual Grid chord must be visible inside its owning viewport")}
        // One physical contact at the measured native center. No fallback,
        // guessed screen coordinates or injected editor state; the following
        // symbol assertion still requires the actual chord editor to open C.
        app.coordinate(withNormalizedOffset:.zero).withOffset(CGVector(dx:frame.midX-root.frame.minX,dy:frame.midY-root.frame.minY)).tap()
        return true
    }

    @MainActor private func wait(_ element:XCUIElement,_ predicate:NSPredicate){
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:predicate,object:element)],timeout:5),.completed)
    }
    @MainActor private func openJazzReview(_ app:XCUIApplication){
        app.buttons["assistant.open"].tap();XCTAssertTrue(app.navigationBars["Assistant"].waitForExistence(timeout:5))
        app.buttons["Examples"].tap()
        let example=app.buttons["assistant.example.jazzify"];XCTAssertTrue(example.waitForExistence(timeout:5));example.tap()
        let dismissed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:example)
        XCTAssertEqual(XCTWaiter.wait(for:[dismissed],timeout:5),.completed)
        let generate=app.buttons["assistant.generate"];revealFully(generate,in:app);generate.tap()
        XCTAssertTrue(app.staticTexts["assistant.harmony.before.0.0"].waitForExistence(timeout:5))
    }
    @MainActor private func revealFully(_ element:XCUIElement,in app:XCUIApplication){
        let scroll=app.scrollViews["assistant.review-scroll"]
        for _ in 0..<10 {
            let viewport=scroll.frame.intersection(app.frame),frame=element.frame
            if element.isHittable,frame.minY>=viewport.minY+8,frame.maxY<=viewport.maxY-8{return}
            scroll.swipeUp()
        }
        XCTFail("The actual Assistant control was not fully visible: \(element.identifier)")
    }
}
