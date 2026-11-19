import XCTest

/// Real local composition, audio, history, store and share UI. No proposal,
/// note array, PCM or model response is injected into either journey.
final class SketchGenerationTests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}

    @MainActor func testEmptyProjectLocalSketchABApplyUndo()throws {
        let app=launch(),transport=app.buttons["perform.transport"]
        let (original,observed)=try createEmptyAndReview(app)
        XCTAssertEqual(state(transport),original)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        keepScreenshot("Completion-new-editable-local-sketch-review")
        let a=app.buttons["assistant.a"],b=app.buttons["assistant.b"]
        reveal(a,in:app);a.tap()
        wait(transport){let t=self.current(transport);return t.contains("preview=true") && t.contains("actualPlaying=1") && self.number("outputPeak",in:t)<0.0001}
        XCTAssertEqual(state(transport),original)
        b.tap()
        wait(transport){let t=self.current(transport);return t.contains("preview=true") && self.number("outputPeak",in:t)>0.001}
        XCTAssertEqual(state(transport),original)
        let apply=app.buttons["assistant.apply"];reveal(apply,in:app);apply.tap()
        wait(transport){!app.navigationBars["Assistant"].exists}
        XCTAssertFalse(app.staticTexts["grid.empty-state"].exists)
        let applied=state(transport)
        XCTAssertEqual(applied.id,original.id);XCTAssertGreaterThan(applied.revision,original.revision)
        let chords=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.chord.'"))
        XCTAssertEqual(chords.count,8)
        XCTAssertEqual(number("loopRangeCount",in:current(transport)),8*3840)
        let labels=chords.allElementsBoundByIndex.prefix(4).map(\.label)
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.staticTexts["grid.empty-state"].waitForExistence(timeout:5))
        XCTAssertEqual(number("loopRangeCount",in:current(transport)),4*3840)
        app.buttons["Redo"].tap()
        wait(transport){!app.staticTexts["grid.empty-state"].exists}
        XCTAssertEqual(chords.allElementsBoundByIndex.prefix(4).map(\.label),labels)
        XCTAssertEqual(number("loopRangeCount",in:current(transport)),8*3840)
        keepReport(observed+"\n"+current(transport),name:"Completion-local-sketch-AB-atomic-Undo-Redo")
        keepScreenshot("Completion-generated-sketch-applied")
    }

    @MainActor func testGeneratedSketchReopensWithRealAudioAndMIDIShare()throws {
        let app=launch(),transport=app.buttons["perform.transport"]
        let (original,observed)=try createEmptyAndReview(app)
        let apply=app.buttons["assistant.apply"];reveal(apply,in:app);apply.tap()
        wait(transport){!app.navigationBars["Assistant"].exists}
        let chords=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.chord.'"))
        XCTAssertEqual(chords.count,8)
        XCTAssertEqual(number("loopRangeCount",in:current(transport)),8*3840)
        let labels=chords.allElementsBoundByIndex.prefix(4).map(\.label)
        let saved=app.descendants(matching:.any).matching(NSPredicate(format:"label == 'Saved on this iPhone'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout:8))
        let persisted=state(transport)
        XCTAssertEqual(persisted.id,original.id);XCTAssertGreaterThan(persisted.revision,original.revision)
        app.terminate();app.launch()
        XCTAssertTrue(transport.waitForExistence(timeout:15))
        XCTAssertEqual(state(transport),persisted)
        XCTAssertTrue(app.staticTexts["Untitled"].exists)
        XCTAssertEqual(chords.allElementsBoundByIndex.prefix(4).map(\.label),labels)
        XCTAssertEqual(number("loopRangeCount",in:current(transport)),8*3840)
        app.buttons["Play"].tap()
        wait(transport,timeout:14){let t=self.current(transport);return t.contains("actualPlaying=1") && self.number("outputPeak",in:t)>0.001 && self.number("actualTick",in:t)>4*3840 && self.number("actualTick",in:t)<8*3840}
        app.buttons["Stop"].tap()
        app.buttons["export.open"].tap()
        XCTAssertTrue(app.buttons["format.midi"].waitForExistence(timeout:5))
        app.buttons["export.confirm"].tap()
        let share=app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout:15) || app.buttons["Copy"].exists || app.buttons["Save to Files"].exists || app.staticTexts["Save to Files"].exists)
        XCTAssertFalse(app.staticTexts["export.error"].exists)
        keepReport(observed+"\n"+current(transport),name:"Completion-real-local-sketch-score-and-reopened-runtime")
        keepScreenshot("Completion-generated-sketch-midi-share")
    }

    @MainActor func testOfflineBuilderCreatesTwoSectionBeatFromExample() {
        let app = launch()
        let old = state(app.buttons["perform.transport"])
        app.buttons["assistant.open"].tap()
        let builder = app.buttons["Build a track"]
        XCTAssertTrue(builder.waitForExistence(timeout: 8))
        builder.tap()
        let example = app.buttons["Try a boom-bap arrangement"]
        XCTAssertTrue(example.waitForExistence(timeout: 8))
        example.tap()
        app.buttons["Suggest settings"].tap()
        let feedback = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Local suggestions")).firstMatch
        XCTAssertTrue(feedback.waitForExistence(timeout: 8))
        keepScreenshot("Groove37-offline-builder")
        let save = app.buttons["builder.create"]
        for _ in 0..<10 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable)
        save.tap()
        let transport = app.buttons["perform.transport"]
        XCTAssertTrue(transport.waitForExistence(timeout: 10))
        wait(transport) {
            let next = self.state(transport)
            return !next.id.isEmpty && next.id != old.id
        }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Intro")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Hook")).firstMatch.exists)
        keepScreenshot("Groove37-editable-arrangement")
    }

    @MainActor func testWorkoutFormReviewAndCreate() {
        let app = launch()
        let transport = app.buttons["perform.transport"]
        let old = state(transport)
        app.buttons["assistant.open"].tap()
        let builder = app.buttons["Build a track"]
        XCTAssertTrue(builder.waitForExistence(timeout: 8))
        builder.tap()
        let example = app.buttons["Try a workout arrangement"]
        XCTAssertTrue(example.waitForExistence(timeout: 8))
        example.tap()
        app.buttons["Suggest settings"].tap()
        let repeatSource = app.staticTexts["Repeats the source part, including edits."]
        for _ in 0..<10 where !repeatSource.isHittable { app.swipeUp() }
        XCTAssertTrue(repeatSource.isHittable)
        XCTAssertTrue(app.staticTexts["25–32"].exists)
        keepScreenshot("SongForm39-workout-review")
        let save = app.buttons["builder.create"]
        for _ in 0..<10 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable)
        save.tap()
        wait(transport, timeout: 12) {
            self.state(transport).id != old.id && self.number("loopRangeCount", in: self.current(transport)) == 32*3840
        }
        keepScreenshot("SongForm39-workout-project")
    }

    @MainActor private func launch()->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--runtime-trace","--device-output-startup","--project-store-id",UUID().uuidString,"-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:15))
        return app
    }
    @MainActor private func createEmptyAndReview(_ app:XCUIApplication)throws->(State,String) {
        app.buttons["Projects"].tap()
        XCTAssertTrue(app.buttons["project.new"].waitForExistence(timeout:5));app.buttons["project.new"].tap()
        XCTAssertTrue(app.buttons["project.template.empty"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["project.template.empty"].isSelected)
        app.buttons["project.create"].tap()
        XCTAssertTrue(app.staticTexts["grid.empty-state"].waitForExistence(timeout:5))
        let original=state(app.buttons["perform.transport"])
        XCTAssertFalse(original.id.isEmpty);XCTAssertGreaterThanOrEqual(original.revision,0)
        app.buttons["assistant.open"].tap()
        XCTAssertTrue(app.buttons["assistant.examples"].waitForExistence(timeout:5));app.buttons["assistant.examples"].tap()
        let example=app.buttons["assistant.example.sketch"]
        XCTAssertTrue(example.waitForExistence(timeout:5));example.tap()
        let generate=app.buttons["assistant.generate"];reveal(generate,in:app);generate.tap()
        let parts=app.staticTexts["assistant.sketch.parts"]
        XCTAssertTrue(parts.waitForExistence(timeout:8));reveal(parts,in:app)
        let observed=try XCTUnwrap(parts.value as? String)
        let facts=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(observed.utf8)) as? [String:Any])
        XCTAssertEqual(facts["style"] as? String,"house")
        XCTAssertEqual(facts["bars"] as? Int,8);XCTAssertEqual(facts["seed"] as? Int,42)
        XCTAssertEqual(facts["modelInterpretedParameters"] as? Bool,false)
        for role in ["chords","drums","bass","melody"]{XCTAssertGreaterThan(facts[role] as? Int ?? 0,0,role)}
        XCTAssertTrue(app.staticTexts["LOCAL"].exists);XCTAssertFalse(app.staticTexts["ON-DEVICE AI"].exists)
        return (original,observed)
    }
    private struct State:Equatable{let id:String;let revision:Int}
    @MainActor private func state(_ transport:XCUIElement)->State{let t=current(transport);return State(id:field("project",in:t) ?? "",revision:Int(field("revision",in:t) ?? "") ?? -1)}
    @MainActor private func current(_ transport:XCUIElement)->String{(transport.value as? String ?? "").components(separatedBy:"\n").first ?? ""}
    private func field(_ key:String,in report:String)->String?{report.split(separator:" ").first(where:{$0.hasPrefix(key+"=")}).map{String($0.dropFirst(key.count+1))}}
    private func number(_ key:String,in report:String)->Double{Double(field(key,in:report) ?? "") ?? -1}
    @MainActor private func reveal(_ element:XCUIElement,in app:XCUIApplication){for _ in 0..<10{if element.isHittable{return};app.scrollViews.firstMatch.swipeUp()};XCTAssertTrue(element.isHittable)}
    @MainActor private func wait(_ element:XCUIElement,timeout:TimeInterval=8,condition:()->Bool){let deadline=Date().addingTimeInterval(timeout);repeat{if condition(){return};RunLoop.current.run(until:Date().addingTimeInterval(0.1))}while Date()<deadline;XCTFail("Condition not reached: \(element.debugDescription)")}
    @MainActor private func keepScreenshot(_ name:String){let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)}
    private func keepReport(_ report:String,name:String){let receipt=XCTAttachment(string:report);receipt.name=name;receipt.lifetime = .keepAlways;add(receipt)}
}
