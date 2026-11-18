import XCTest

final class SoundPickerUITests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}

    @MainActor private func launch()->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--runtime-trace","--device-output-startup","--screen","jam","--project-store-id",UUID().uuidString,"-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:15))
        return app
    }
    @MainActor private func entry(_ app:XCUIApplication)->XCUIElement {
        app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'sound.track.drums.'")).firstMatch
    }
    @MainActor private func report(_ app:XCUIApplication,preview:Bool=false)->String {
        (app.buttons[preview ? "sound.preview":"perform.transport"].value as? String ?? "").components(separatedBy:"\n").first ?? ""
    }
    private func field(_ key:String,in report:String)->String? {
        report.split(separator:" ").first(where:{$0.hasPrefix(key+"=")}).map{String($0.dropFirst(key.count+1))}
    }
    @MainActor private func wait(_ app:XCUIApplication,preview:Bool=false,condition:@escaping(String)->Bool){
        let deadline=Date().addingTimeInterval(10)
        while Date()<deadline {
            if condition(report(app,preview:preview)){return}
            Thread.sleep(forTimeInterval:0.1)
        }
        XCTFail("The actual audio runtime did not reach the expected state")
    }

    @MainActor func testSoundPreviewHasActualOutputAndCancelKeepsMusicUntouched()throws {
        let app=launch();defer{app.terminate()}
        let original=report(app)
        let project=try XCTUnwrap(field("project",in:original)),revision=try XCTUnwrap(field("revision",in:original))
        let originalGeneration=try XCTUnwrap(Int(field("submittedGeneration",in:original) ?? ""))
        let sound=entry(app)
        XCTAssertTrue(sound.waitForExistence(timeout:5));XCTAssertEqual(sound.value as? String,"Classic kit")
        sound.tap()
        app.buttons["sound.palette.3"].tap()
        app.buttons["sound.preview"].tap()
        wait(app,preview:true){value in
            guard let generation=self.field("submittedGeneration",in:value),let number=Int(generation) else{return false}
            return number>originalGeneration && self.field("actualGeneration",in:value)==generation
                && self.field("actualRevision",in:value)==revision && value.contains("actualPlaying=1")
                && (Double(self.field("outputPeak",in:value) ?? "") ?? 0)>0.001
        }
        XCTAssertEqual(field("project",in:report(app,preview:true)),project)
        XCTAssertEqual(field("revision",in:report(app,preview:true)),revision)
        let previewGeneration=try XCTUnwrap(Int(field("submittedGeneration",in:report(app,preview:true)) ?? ""))
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot());image.name="Touch21-warm-kit-real-preview";image.lifetime = .keepAlways;add(image)
        app.buttons["Cancel"].tap()
        wait(app){value in
            guard let generation=self.field("submittedGeneration",in:value),let number=Int(generation)else{return false}
            return number>previewGeneration && self.field("actualGeneration",in:value)==generation && value.contains("actualPlaying=0")
        }
        XCTAssertEqual(field("revision",in:report(app)),revision)
        XCTAssertEqual(entry(app).value as? String,"Classic kit")
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
    }

    @MainActor func testAppliedSoundIsOneUndoAndPersistsInTheRealStore()throws {
        let app=launch();defer{app.terminate()}
        let original=try XCTUnwrap(field("revision",in:report(app)))
        let sound=entry(app)
        XCTAssertTrue(sound.waitForExistence(timeout:5));sound.tap()
        app.buttons["sound.palette.4"].tap();app.buttons["sound.apply"].tap()
        XCTAssertEqual(entry(app).value as? String,"Bright kit")
        XCTAssertNotEqual(field("revision",in:report(app)),original)
        app.buttons["Undo"].tap()
        XCTAssertEqual(entry(app).value as? String,"Classic kit")
        XCTAssertFalse(app.buttons["Undo"].isEnabled,"A sound selection must add exactly one source edit")
        app.buttons["Redo"].tap()
        XCTAssertEqual(entry(app).value as? String,"Bright kit")
        let saved=app.descendants(matching:.any).matching(NSPredicate(format:"label == 'Saved on this iPhone'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout:8))
        let appliedRevision=try XCTUnwrap(field("revision",in:report(app)))
        app.terminate();app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:15))
        XCTAssertEqual(entry(app).value as? String,"Bright kit")
        XCTAssertEqual(field("revision",in:report(app)),appliedRevision)
        let image=XCTAttachment(screenshot:XCUIScreen.main.screenshot());image.name="Touch21-bright-kit-real-store-reopen";image.lifetime = .keepAlways;add(image)
    }

    @MainActor func testLiveSoundPreviewRetainsTheGrooveAndSourceRevision()throws {
        let app=launch();defer{app.terminate()}
        app.buttons["Play"].tap()
        wait(app){$0.contains("actualPlaying=1")}
        let original=report(app)
        let kernel=try XCTUnwrap(field("kernel",in:original)),revision=try XCTUnwrap(field("revision",in:original))
        let startClock=try XCTUnwrap(UInt64(field("actualClock",in:original) ?? ""))
        let originalGeneration=try XCTUnwrap(Int(field("submittedGeneration",in:original) ?? ""))
        entry(app).tap();app.buttons["sound.palette.3"].tap();app.buttons["sound.preview"].tap()
        wait(app,preview:true){value in
            guard let generation=self.field("submittedGeneration",in:value),let number=Int(generation)else{return false}
            return value.contains("actualPlaying=1") && value.contains("preview=true")
                && number>originalGeneration
                && self.field("actualGeneration",in:value)==generation
                && self.field("actualRevision",in:value)==revision
                && (Double(self.field("actualTick",in:value) ?? "") ?? 0)>4080
                && (Double(self.field("outputPeak",in:value) ?? "") ?? 0)>0.001
        }
        let live=report(app,preview:true)
        XCTAssertEqual(field("kernel",in:live),kernel)
        XCTAssertEqual(field("revision",in:live),revision)
        XCTAssertEqual(field("loopRangeEnd",in:live),field("loopRangeEnd",in:original))
        let liveClock=try XCTUnwrap(UInt64(field("actualClock",in:live) ?? ""))
        let liveGeneration=try XCTUnwrap(Int(field("submittedGeneration",in:live) ?? ""))
        XCTAssertGreaterThan(liveClock,startClock)
        let proof=XCTAttachment(string:"ORIGINAL\n"+original+"\nLIVE SOUND PREVIEW\n"+live)
        proof.name="Touch21-sound-preview-actual-groove-clock-and-range";proof.lifetime = .keepAlways;add(proof)
        app.buttons["Cancel"].tap()
        wait(app){value in
            guard let generation=self.field("submittedGeneration",in:value),let number=Int(generation)else{return false}
            return number>liveGeneration && self.field("actualGeneration",in:value)==generation
                && value.contains("actualPlaying=1") && value.contains("preview=false")
        }
        let restored=report(app)
        XCTAssertEqual(field("kernel",in:restored),kernel)
        XCTAssertEqual(field("revision",in:restored),revision)
        XCTAssertGreaterThan(try XCTUnwrap(UInt64(field("actualClock",in:restored) ?? "")),liveClock)
        XCTAssertEqual(entry(app).value as? String,"Classic kit")
        app.buttons["Stop"].tap()
    }

    @MainActor func testPocketKitIsAnUndoableEditAndReopensWithTheSamePadSamples() {
        let app = launch(); defer { app.terminate() }
        let sound = entry(app)
        XCTAssertTrue(sound.waitForExistence(timeout: 5))
        sound.tap()
        app.buttons["sound.samples"].tap()
        let pocket = app.buttons["pad-samples.pocket-kit"]
        XCTAssertTrue(pocket.waitForExistence(timeout: 5))
        pocket.tap()
        let kick = app.buttons.matching(NSPredicate(format: "identifier == 'pad-samples.library.0' AND value == 'Pocket · Kick'")).firstMatch
        XCTAssertTrue(kick.waitForExistence(timeout: 15))
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Sound28-pocket-kit"; image.lifetime = .keepAlways; add(image)
        app.buttons["Done"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertEqual(entry(app).value as? String, "Custom kit")
        app.buttons["Undo"].tap()
        XCTAssertEqual(entry(app).value as? String, "Classic kit")
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        app.buttons["Redo"].tap()
        XCTAssertEqual(entry(app).value as? String, "Custom kit")
        let saved = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Saved on this iPhone'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 15))
        XCTAssertEqual(entry(app).value as? String, "Custom kit")
        entry(app).tap(); app.buttons["sound.samples"].tap()
        XCTAssertTrue(kick.waitForExistence(timeout: 10))
        if ProcessInfo.processInfo.environment["GRILLA_TEST_SOUNDFONT"] == "1" {
            app.buttons["Done"].tap()
            app.navigationBars["Sound"].buttons["Cancel"].tap()
            verifySeededSoundFont(app)
        }
    }

    @MainActor private func verifySeededSoundFont(_ app: XCUIApplication) {
        app.buttons["Mixer"].tap()
        let harmony = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sound.track.harmony.'")).firstMatch
        XCTAssertTrue(harmony.waitForExistence(timeout: 5))
        harmony.tap()
        app.buttons["sound.banks"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 12))
        search.tap(); search.typeText("Nylon")
        let guitar = app.buttons["sound-bank.program.0.24"]
        XCTAssertTrue(guitar.waitForExistence(timeout: 12), "The search should reveal Nylon Guitar from the actual bank")
        XCTAssertFalse(app.buttons["sound-bank.program.0.0"].exists)
        if app.keyboards.buttons["Search"].exists { app.keyboards.buttons["Search"].tap() }
        guitar.tap()
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Sound29-soundfont-search"; image.lifetime = .keepAlways; add(image)
        app.buttons["sound-bank.apply"].tap()
        let selected = app.staticTexts["Nylon Guitar"]
        XCTAssertTrue(selected.waitForExistence(timeout: 30))
        XCTAssertTrue(app.navigationBars["Sound"].buttons["Cancel"].waitForExistence(timeout: 30))
        app.navigationBars["Sound"].buttons["Cancel"].tap()
        XCTAssertEqual(harmony.value as? String, "Nylon Guitar")
        wait(app) { trace in
            guard let submitted = self.field("submittedGeneration", in: trace) else { return false }
            return self.field("actualGeneration", in: trace) == submitted
        }
        let proof = XCTAttachment(string: report(app))
        proof.name = "Sound28-assigned-instrument-adopted"; proof.lifetime = .keepAlways; add(proof)
    }

    @MainActor func testSavedPadSampleCanBeUsedInTwoProjects() {
        let app = launch(); defer { app.terminate() }
        openSampleLibrary(app)
        XCTAssertTrue(app.buttons["pad-library.import"].waitForExistence(timeout: 8))
        guard ProcessInfo.processInfo.environment["GRILLA_TEST_SOUNDFONT"] == "1" else { return }
        let item = app.buttons["pad-library.sample.326FA160-F668-4DEB-B58F-A9B24B5E4086"]
        XCTAssertTrue(item.waitForExistence(timeout: 8))
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Sound29-sample-library"; image.lifetime = .keepAlways; add(image)
        item.tap()
        assertAssignedSample(app)
        app.terminate()

        let another = launch(); defer { another.terminate() }
        XCTAssertEqual(entry(another).value as? String, "Classic kit")
        openSampleLibrary(another)
        let reusable = another.buttons["pad-library.sample.326FA160-F668-4DEB-B58F-A9B24B5E4086"]
        XCTAssertTrue(reusable.waitForExistence(timeout: 8))
        reusable.tap()
        assertAssignedSample(another)
    }

    @MainActor func testIncludedInstrumentCanBeAssignedWithoutImport() {
        let app = launch(); defer { app.terminate() }
        app.buttons["Mixer"].tap()
        let harmony = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sound.track.harmony.'")).firstMatch
        XCTAssertTrue(harmony.waitForExistence(timeout: 5)); harmony.tap()
        app.buttons["sound.banks"].tap()
        let piano = app.buttons["sound-bank.included.piano"]
        XCTAssertTrue(piano.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["sound-bank.included.nylon-guitar"].exists)
        piano.tap()
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Sound30-recorded-instruments"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["sound-bank.apply"].tap()
        let label = app.navigationBars["Sound"].buttons["Cancel"]
        let parent = NSPredicate(format: "hittable == true")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: parent, object: label)], timeout: 15), .completed)
        label.tap()
        XCTAssertEqual(harmony.value as? String, "Acoustic piano")
    }

    @MainActor private func openSampleLibrary(_ app: XCUIApplication) {
        let sound = entry(app)
        XCTAssertTrue(sound.waitForExistence(timeout: 5)); sound.tap()
        app.buttons["sound.samples"].tap()
        let pad = app.buttons["pad-samples.library.0"]
        XCTAssertTrue(pad.waitForExistence(timeout: 5)); pad.tap()
        XCTAssertTrue(app.navigationBars["Sample library"].waitForExistence(timeout: 5))
    }

    @MainActor private func assertAssignedSample(_ app: XCUIApplication) {
        let predicate = NSPredicate(format: "identifier == 'pad-samples.library.0' AND value == 'Studio Click'")
        XCTAssertTrue(app.buttons.matching(predicate).firstMatch.waitForExistence(timeout: 12))
    }
}
