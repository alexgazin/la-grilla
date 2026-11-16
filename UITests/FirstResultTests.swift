import XCTest

/// Real UI, canonical persistence and actual DSP-output observations. These
/// checks do not substitute for hearing the physical iPhone's audio route.
final class FirstResultTests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}

    @MainActor private func launch()->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--runtime-trace","--device-output-startup","--project-store-id",UUID().uuidString,"-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:15))
        return app
    }

    @MainActor private func create(_ name:String,starter:Bool,in app:XCUIApplication){
        app.buttons["Projects"].tap()
        XCTAssertTrue(app.buttons["project.new"].waitForExistence(timeout:5))
        app.buttons["project.new"].tap()
        let empty=app.buttons["project.template.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout:5))
        XCTAssertTrue(empty.isSelected,"Empty remains an explicit, silent default")
        if starter{app.buttons["project.template.starter"].tap()}
        let field=app.textFields["project.name"]
        reveal(field,in:app)
        field.tap();field.typeText(name)
        app.buttons["project.create"].tap()
        wait(app.navigationBars["New project"]){!app.navigationBars["New project"].exists}
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["Stop"].exists,"Choosing a starting point must not auto-play")
    }

    @MainActor func testEmptyProjectGuidesFirstChordToRealOutputAndPersists()throws {
        let app=launch()
        create("My first idea",starter:false,in:app)
        let transport=app.buttons["perform.transport"]
        let projectID=try XCTUnwrap(field("project",in:current(transport)))
        let guide=app.staticTexts["grid.empty-state"]
        XCTAssertTrue(guide.waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["grid.empty-chord"].isHittable)
        XCTAssertTrue(app.buttons["grid.empty-jam"].isHittable)
        keepScreenshot("Audit-empty-project-first-actions")
        app.buttons["grid.empty-jam"].tap()
        XCTAssertTrue(app.buttons["Pads"].waitForExistence(timeout:5))
        app.buttons["Grid"].tap()
        app.buttons["grid.empty-chord"].tap()
        XCTAssertTrue(app.textFields["chord.symbol"].waitForExistence(timeout:5))
        XCTAssertEqual(app.textFields["chord.symbol"].value as? String,"C")
        let apply=app.buttons["chord.apply"];reveal(apply,in:app);apply.tap()
        wait(app.navigationBars["Edit chord"]){!app.navigationBars["Edit chord"].exists}
        XCTAssertFalse(guide.exists)
        XCTAssertTrue(app.buttons["Undo"].isEnabled)
        assertRealOutput(in:app)
        app.buttons["Stop"].tap()
        awaitSaved(in:app)
        let revision=try XCTUnwrap(field("revision",in:current(transport)))
        keepScreenshot("Audit-first-chord-saved")
        app.terminate();app.launch()
        XCTAssertTrue(transport.waitForExistence(timeout:15))
        XCTAssertEqual(field("project",in:current(transport)),projectID)
        XCTAssertEqual(field("revision",in:current(transport)),revision)
        XCTAssertTrue(app.staticTexts["My first idea"].exists)
        XCTAssertFalse(guide.exists)
        let chord=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.chord.'")).firstMatch
        XCTAssertTrue(chord.waitForExistence(timeout:5));XCTAssertTrue(chord.label.contains("C"))
        assertRealOutput(in:app)
        keepReport(current(transport),name:"Audit-empty-first-real-output-after-reopen")
        app.buttons["Stop"].tap()
    }

    @MainActor func testStarterAndExampleAreAudibleIndependentAndKeepSavedProject()throws {
        let app=launch()
        create("My starter sketch",starter:true,in:app)
        let transport=app.buttons["perform.transport"]
        let originalID=try XCTUnwrap(field("project",in:current(transport)))
        XCTAssertFalse(app.staticTexts["grid.empty-state"].exists)
        let chords=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.chord.'"))
        XCTAssertEqual(chords.count,4)
        let chordLabels=chords.allElementsBoundByIndex.map(\.label)
        assertRealOutput(in:app)
        app.buttons["Stop"].tap()
        awaitSaved(in:app)
        keepScreenshot("Audit-local-starter-groove")
        app.buttons["Projects"].tap()
        let example=app.buttons["project.example"]
        XCTAssertTrue(example.waitForExistence(timeout:5))
        XCTAssertTrue(example.isHittable,"An example must be available in a non-empty library")
        example.tap()
        wait(example){!example.exists}
        let exampleID=try XCTUnwrap(field("project",in:current(transport)))
        XCTAssertNotEqual(exampleID,originalID)
        XCTAssertTrue(app.staticTexts["First light"].waitForExistence(timeout:5))
        XCTAssertFalse(app.buttons["Stop"].exists,"Opening a saved example must not auto-play")
        assertRealOutput(in:app)
        app.buttons["Stop"].tap()
        app.buttons["Projects"].tap()
        let original=app.buttons.matching(NSPredicate(format:"label BEGINSWITH %@","My starter sketch")).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout:5));reveal(original,in:app);original.tap()
        wait(transport){field("project",in:self.current(transport))==originalID}
        XCTAssertEqual(chords.allElementsBoundByIndex.map(\.label),chordLabels)
        app.terminate();app.launch()
        XCTAssertTrue(transport.waitForExistence(timeout:15))
        XCTAssertEqual(field("project",in:current(transport)),originalID)
        XCTAssertTrue(app.staticTexts["My starter sketch"].exists)
        keepReport("Original=\(originalID)\nSeparate example=\(exampleID)\n"+current(transport),name:"Audit-example-independent-store-reopen")
    }

    @MainActor private func assertRealOutput(in app:XCUIApplication){
        let transport=app.buttons["perform.transport"]
        let clock=Double(field("actualClock",in:current(transport)) ?? "") ?? 0
        app.buttons["Play"].tap()
        wait(transport,timeout:10){
            let observed=self.current(transport)
            return observed.contains("actualPlaying=1") && observed.contains("engineRunning=true")
                && self.field("actualRevision",in:observed)==self.field("revision",in:observed)
                && self.field("actualGeneration",in:observed)==self.field("submittedGeneration",in:observed)
                && (Double(self.field("actualClock",in:observed) ?? "") ?? 0)>clock
                && (Double(self.field("outputPeak",in:observed) ?? "") ?? 0)>0.001
        }
    }
    @MainActor func testAcceptedMIDIInterleavingsKeepLatestWorkAndActiveRetryPreservesDisk()throws {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--runtime-trace","--device-output-startup","--project-change-probe","--project-store-id",UUID().uuidString,"-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        let transport=app.buttons["perform.transport"]
        XCTAssertTrue(transport.waitForExistence(timeout:15))
        app.buttons["Projects"].tap()
        let probe=app.buttons["project.change-probe"]
        XCTAssertTrue(probe.waitForExistence(timeout:5));reveal(probe,in:app);probe.tap()
        wait(transport,timeout:45){(transport.value as? String ?? "").contains("PROJECT_CHANGE_QA ")}
        let trace=try XCTUnwrap(transport.value as? String)
        let encoded=try XCTUnwrap(trace.components(separatedBy:"\nPROJECT_CHANGE_QA ").last)
        let report=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(encoded.utf8)) as? [String:Any])
        XCTAssertEqual(report["complete"] as? Bool,true)
        XCTAssertNil(report["error"],encoded)
        XCTAssertEqual(report["hardwareMIDIClaimed"] as? Bool,false)
        let cases=try XCTUnwrap(report["interleavings"] as? [[String:Any]])
        XCTAssertEqual(cases.count,3)
        XCTAssertEqual(Set(cases.compactMap{$0["stage"] as? String}),Set(["checkpoint.saved","stored.loaded","candidate.saved"]))
        for observed in cases {
            XCTAssertEqual(observed["sourceRetained"] as? Bool,true)
            XCTAssertEqual(observed["concurrentChangeRejected"] as? Bool,true)
            let before=try XCTUnwrap(observed["beforeRevision"] as? Int),accepted=try XCTUnwrap(observed["acceptedRevision"] as? Int)
            XCTAssertGreaterThan(accepted,before)
            XCTAssertEqual(observed["activeRevision"] as? Int,accepted)
            XCTAssertEqual(observed["savedRevision"] as? Int,accepted)
            XCTAssertEqual(observed["activeID"] as? String,observed["acceptedSourceID"] as? String)
            XCTAssertEqual(observed["masterAfterAbort"] as? Double,observed["acceptedMaster"] as? Double)
            XCTAssertEqual(observed["savedMaster"] as? Double,observed["acceptedMaster"] as? Double)
            XCTAssertFalse((observed["retryReason"] as? String ?? "").isEmpty)
            if observed["stage"] as? String=="candidate.saved" {
                XCTAssertEqual(observed["createResult"] as? Bool,false)
                XCTAssertEqual(observed["newDocumentCount"] as? Int,1)
                XCTAssertEqual(observed["retainedCopyVisible"] as? Bool,true)
                XCTAssertEqual(observed["returnedToProjects"] as? Bool,true)
            }else{XCTAssertEqual(observed["newDocumentCount"] as? Int,0)}
        }
        let retry=try XCTUnwrap(report["activeRetry"] as? [String:Any])
        for key in ["workingProjectRetained","futureBytesRetained","blockedSaveRetainedFutureBytes","invalidVelocityRejected","validRetryKeptUnsavedWork","validRetryClearedLoadFailure","savedWorkingProject","saveCopyEscapedToHealthyDocument","saveCopyKeptWorkingMusic","saveCopyDidNotOverwriteBadSource","escapedCopyCanOpenAnotherProject"]{XCTAssertEqual(retry[key] as? Bool,true,key+": "+encoded)}
        XCTAssertFalse((retry["canonicalLoadError"] as? String ?? "").isEmpty)
        let original=try XCTUnwrap(retry["originalVelocity"] as? Int)
        XCTAssertEqual(retry["acceptedVelocity"] as? Int,original+1)
        XCTAssertEqual(retry["savedVelocity"] as? Int,original+1)
        keepReport(encoded,name:"Audit-real-store-gated-MIDI-interleavings-and-active-Retry")
        keepScreenshot("Audit-project-change-work-preserved")
    }
    @MainActor private func awaitSaved(in app:XCUIApplication){
        let saved=app.descendants(matching:.any).matching(NSPredicate(format:"label == 'Saved on this iPhone'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout:8))
    }
    @MainActor private func current(_ transport:XCUIElement)->String {
        (transport.value as? String ?? "").components(separatedBy:"\n").first ?? ""
    }
    private func field(_ key:String,in report:String)->String? {
        report.split(separator:" ").first(where:{$0.hasPrefix(key+"=")}).map{String($0.dropFirst(key.count+1))}
    }
    @MainActor private func reveal(_ element:XCUIElement,in app:XCUIApplication){
        for _ in 0..<5{if element.isHittable{return};if app.collectionViews.firstMatch.exists{app.collectionViews.firstMatch.swipeUp()}else{app.scrollViews.firstMatch.swipeUp()}}
        XCTAssertTrue(element.isHittable)
    }
    @MainActor private func wait(_ element:XCUIElement,timeout:TimeInterval=5,condition:()->Bool){
        let deadline=Date().addingTimeInterval(timeout)
        repeat{if condition(){return};RunLoop.current.run(until:Date().addingTimeInterval(0.1))}while Date()<deadline
        XCTFail("Condition not reached: \(element.debugDescription)")
    }
    @MainActor private func keepScreenshot(_ name:String){let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)}
    private func keepReport(_ report:String,name:String){let receipt=XCTAttachment(string:report);receipt.name=name;receipt.lifetime = .keepAlways;add(receipt)}
}
