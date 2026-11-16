import XCTest

/// Native UI/persistence and actual DSP revision adoption. Pitch names are
/// checked as notation; this does not infer acoustic frequency from a label.
final class TranspositionUITests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}

    @MainActor private func launch()->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--runtime-trace","--device-output-startup","--screen","grid","--project-store-id",UUID().uuidString,"-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:15))
        return app
    }

    @MainActor func testTransposePreviewCancelApplyLiveUndoRedoAndReopen()throws {
        let app=launch();defer{app.terminate()}
        let transport=app.buttons["perform.transport"]
        let originalID=try XCTUnwrap(field("project",in:current(transport)))
        let originalRevision=try XCTUnwrap(field("revision",in:current(transport)))
        let chords=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.chord.'"))
        XCTAssertEqual(chords.count,4)
        let originalLabels=chords.allElementsBoundByIndex.map(\.label)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        app.buttons["Play"].tap()
        assertAdopted(transport,afterClock:0)
        let kernel=try XCTUnwrap(field("kernel",in:current(transport)))
        let initialClock=try XCTUnwrap(UInt64(field("actualClock",in:current(transport)) ?? ""))
        openSettings(app)
        openTranspose(app)
        let key=app.descendants(matching:.any).matching(NSPredicate(format:"identifier == 'transpose.key'")).firstMatch
        XCTAssertTrue(key.waitForExistence(timeout:5))
        let keyDescription=key.label+" "+(key.value as? String ?? "")
        XCTAssertTrue(keyDescription.contains("C major") && keyDescription.contains("D major"))
        let range=app.staticTexts["transpose.pitch-range"]
        XCTAssertTrue(range.exists);XCTAssertTrue(range.label.contains("→"))
        XCTAssertEqual(field("project",in:current(transport)),originalID)
        XCTAssertEqual(field("revision",in:current(transport)),originalRevision,"Review must not mutate the project")
        keepScreenshot("Audit-transpose-real-preview")
        app.buttons["transpose.cancel"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
        XCTAssertEqual(field("revision",in:current(transport)),originalRevision)
        openTranspose(app)
        let apply=app.buttons["transpose.apply"]
        reveal(apply,in:app);XCTAssertTrue(apply.isEnabled);apply.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
        app.buttons["Done"].tap()
        wait(app.navigationBars["Settings"]){!app.navigationBars["Settings"].exists}
        assertAdopted(transport,afterClock:initialClock)
        XCTAssertEqual(field("kernel",in:current(transport)),kernel)
        XCTAssertEqual(field("project",in:current(transport)),originalID)
        XCTAssertNotEqual(field("revision",in:current(transport)),originalRevision)
        for (index,symbol) in ["D","Em","G","A"].enumerated(){
            XCTAssertTrue(chords.element(boundBy:index).label.hasPrefix(symbol),"Transposed grid chord \(index)")
        }
        XCTAssertTrue(app.staticTexts["D major"].exists)
        let transposedLabels=chords.allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(app.buttons["Undo"].isEnabled)
        app.buttons["Undo"].tap()
        wait(chords.firstMatch){chords.allElementsBoundByIndex.map(\.label)==originalLabels}
        assertAdopted(transport,afterClock:initialClock)
        XCTAssertEqual(field("kernel",in:current(transport)),kernel)
        XCTAssertFalse(app.buttons["Undo"].isEnabled,"One Undo must restore the entire transpose")
        XCTAssertTrue(app.buttons["Redo"].isEnabled)
        app.buttons["Redo"].tap()
        wait(chords.firstMatch){chords.allElementsBoundByIndex.map(\.label)==transposedLabels}
        assertAdopted(transport,afterClock:initialClock)
        XCTAssertEqual(field("kernel",in:current(transport)),kernel)
        keepScreenshot("Audit-transpose-live-adopted")
        keepReport(current(transport),name:"Audit-transpose-actual-live-kernel-and-generation")
        app.buttons["Stop"].tap()
        awaitSaved(app)
        let savedRevision=field("revision",in:current(transport))
        app.terminate();app.launch()
        XCTAssertTrue(transport.waitForExistence(timeout:15))
        XCTAssertEqual(field("project",in:current(transport)),originalID)
        XCTAssertEqual(field("revision",in:current(transport)),savedRevision)
        XCTAssertEqual(chords.allElementsBoundByIndex.map(\.label),transposedLabels)
        XCTAssertTrue(app.staticTexts["D major"].exists)
        app.buttons["Play"].tap();assertAdopted(transport,afterClock:0)
        keepReport("Same-store reopen matched project/revision and transposed Grid; actual output peak/clock adopted. Acoustic frequency was not measured.\n"+current(transport),name:"Audit-transpose-real-store-reopen")
        app.buttons["Stop"].tap()
    }

    @MainActor func testFlatsAndScaleDegreesPersistWithoutNotationChangingMusic()throws {
        let app=launch();defer{app.terminate()}
        let transport=app.buttons["perform.transport"]
        let originalID=try XCTUnwrap(field("project",in:current(transport)))
        openSettings(app)
        let root=app.buttons["settings.key-root"]
        reveal(root,in:app);root.tap()
        let f=app.buttons["F"];XCTAssertTrue(f.waitForExistence(timeout:5));f.tap()
        let revisionAfterKey=field("revision",in:current(transport))
        let spelling=app.buttons["settings.pitch-spelling"]
        reveal(spelling,in:app);spelling.tap();app.buttons["Flats"].tap()
        let degrees=app.switches["settings.show-degrees"]
        reveal(degrees,in:app)
        if degrees.value as? String != "1"{degrees.tap()}
        XCTAssertEqual(degrees.value as? String,"1")
        XCTAssertEqual(field("revision",in:current(transport)),revisionAfterKey,"Display preferences must not edit music")
        app.buttons["Done"].tap()
        openChord(app)
        let symbol=app.textFields["chord.symbol"]
        symbol.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:0.5)).tap()
        let old=symbol.value as? String ?? ""
        symbol.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count)+"Bb\n")
        let degree=app.staticTexts["chord.degree"]
        XCTAssertTrue(degree.waitForExistence(timeout:5));XCTAssertEqual(degree.label,"IV")
        XCTAssertTrue(app.staticTexts["chord.notes"].label.contains("B♭"))
        XCTAssertFalse(app.staticTexts["chord.notes"].label.contains("A♯"))
        let apply=app.buttons["chord.apply"];reveal(apply,in:app);apply.tap()
        wait(app.navigationBars["Edit chord"]){!app.navigationBars["Edit chord"].exists}
        awaitSaved(app)
        app.terminate();app.launch()
        XCTAssertTrue(transport.waitForExistence(timeout:15))
        XCTAssertEqual(field("project",in:current(transport)),originalID)
        openChord(app)
        XCTAssertEqual(app.staticTexts["chord.degree"].label,"IV")
        XCTAssertTrue(app.staticTexts["chord.notes"].label.contains("B♭"))
        keepScreenshot("Audit-flats-degrees-real-store-reopen")
        app.buttons["Cancel"].tap()
        openSettings(app)
        reveal(spelling,in:app)
        XCTAssertTrue(spelling.label.contains("Flats") || (spelling.value as? String)=="Flats")
        reveal(degrees,in:app);XCTAssertEqual(degrees.value as? String,"1")
        let revisionBeforeRestore=field("revision",in:current(transport))
        // Restore the suite's ordinary display preferences through real UI.
        // The persisted Bb project stays isolated in this test's UUID store.
        reveal(spelling,in:app,up:false);spelling.tap();app.buttons["Auto (key)"].tap()
        reveal(degrees,in:app);degrees.tap()
        XCTAssertEqual(degrees.value as? String,"0")
        XCTAssertEqual(field("revision",in:current(transport)),revisionBeforeRestore)
        app.buttons["Done"].tap()
    }

    @MainActor private func openSettings(_ app:XCUIApplication){
        // The ordinary 44pt tempo/key button opens the same Settings screen.
        // Source18 stalled in the system menu's invalid activation point
        // before either transposition scenario reached its first control.
        let entry=app.buttons["studio.tempo"]
        XCTAssertTrue(entry.waitForExistence(timeout:5))
        XCTAssertTrue(entry.isHittable)
        entry.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
    }
    @MainActor private func openTranspose(_ app:XCUIApplication){
        let link=app.buttons["settings.transpose"]
        reveal(link,in:app);link.tap()
        XCTAssertTrue(app.navigationBars["Transpose arrangement"].waitForExistence(timeout:5))
        XCTAssertEqual(app.steppers["transpose.semitones"].value as? String,"2")
    }
    @MainActor private func openChord(_ app:XCUIApplication){
        let chord=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.chord.'")).firstMatch
        XCTAssertTrue(chord.waitForExistence(timeout:5));chord.tap()
        XCTAssertTrue(app.navigationBars["Edit chord"].waitForExistence(timeout:5))
    }
    @MainActor private func assertAdopted(_ transport:XCUIElement,afterClock:UInt64){
        wait(transport,timeout:10){
            let report=self.current(transport)
            return report.contains("engineRunning=true") && report.contains("actualPlaying=1")
                && self.field("actualRevision",in:report)==self.field("revision",in:report)
                && self.field("actualGeneration",in:report)==self.field("submittedGeneration",in:report)
                && (UInt64(self.field("actualClock",in:report) ?? "") ?? 0)>afterClock
                && (Double(self.field("outputPeak",in:report) ?? "") ?? 0)>0.001
        }
    }
    @MainActor private func awaitSaved(_ app:XCUIApplication){
        let saved=app.descendants(matching:.any).matching(NSPredicate(format:"label == 'Saved on this iPhone'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout:8))
    }
    @MainActor private func current(_ transport:XCUIElement)->String{(transport.value as? String ?? "").components(separatedBy:"\n").first ?? ""}
    private func field(_ key:String,in report:String)->String?{report.split(separator:" ").first(where:{$0.hasPrefix(key+"=")}).map{String($0.dropFirst(key.count+1))}}
    @MainActor private func reveal(_ element:XCUIElement,in app:XCUIApplication,up:Bool=true){
        for _ in 0..<7{
            if element.isHittable{return}
            let scroll=app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch:app.tables.firstMatch.exists ? app.tables.firstMatch:app.scrollViews.firstMatch
            if up{scroll.swipeUp()}else{scroll.swipeDown()}
        }
        XCTAssertTrue(element.isHittable,"A real native control must be reachable")
    }
    @MainActor private func wait(_ element:XCUIElement,timeout:TimeInterval=5,condition:()->Bool){
        let deadline=Date().addingTimeInterval(timeout)
        repeat{if condition(){return};RunLoop.current.run(until:Date().addingTimeInterval(0.1))}while Date()<deadline
        XCTFail("Condition not reached: \(element.debugDescription)")
    }
    @MainActor private func keepScreenshot(_ name:String){let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)}
    private func keepReport(_ text:String,name:String){let receipt=XCTAttachment(string:text);receipt.name=name;receipt.lifetime = .keepAlways;add(receipt)}
}
