import XCTest

final class SoundPickerUITests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}

    @MainActor private func launch(appearance: String? = nil)->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--runtime-trace","--device-output-startup","--screen","jam","--project-store-id",UUID().uuidString,"-AppleLanguages","(en)","-AppleLocale","en_US"]
        if let appearance { app.launchArguments += ["--appearance", appearance] }
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

    @MainActor func testPocketKickTrimPreviewsAppliesUndoesAndPersists() throws {
        executionTimeAllowance = 300
        let app = launch(appearance: "dark")
        defer { app.terminate() }
        let edit = app.buttons["pad-samples.edit.0"]
        let start = app.staticTexts["pad-editor.start.value"]
        let preview = app.buttons["pad-editor.preview"]
        let apply = app.buttons["pad-editor.apply"]

        func openKick() {
            XCTAssertTrue(edit.waitForExistence(timeout: 15))
            edit.tap()
            XCTAssertTrue(start.waitForExistence(timeout: 10))
        }
        func previewFrames() throws -> Int {
            preview.tap()
            let started = NSPredicate(format: "value CONTAINS 'frames=' AND value CONTAINS 'rate='")
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: started, object: preview)], timeout: 10), .completed)
            let diagnostics = try XCTUnwrap(preview.value as? String)
            let frames = try XCTUnwrap(field("frames", in: diagnostics).flatMap(Int.init))
            XCTAssertGreaterThan(frames, 0)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(field("rate", in: diagnostics).flatMap(Double.init)), 8000)
            return frames
        }

        openPadSounds(app)
        app.buttons["pad-samples.pocket-kit"].tap()
        openKick()
        let original = start.label
        XCTAssertFalse(original.isEmpty)
        XCTAssertTrue(app.descendants(matching: .any)["pad-editor.waveform"].exists)
        let originalFrames = try previewFrames()
        app.buttons["pad-editor.start.plus"].tap()
        let trimmed = start.label
        XCTAssertNotEqual(trimmed, original)
        let editedFrames = try previewFrames()
        XCTAssertLessThan(editedFrames, originalFrames, "The trimmed preview must submit a shorter buffer for playback")
        // A normalized XCUI slider drag travels different distances on different
        // simulator sizes. The musician's gain nudge is exactly half a dB.
        let louder = app.buttons["pad-editor.gain.plus"]
        for direction in ["minus", "plus"] {
            let frame = app.buttons["pad-editor.gain." + direction].frame
            XCTAssertGreaterThanOrEqual(frame.width, 44)
            XCTAssertGreaterThanOrEqual(frame.height, 44)
        }
        for _ in 0..<10 { louder.tap() }
        XCTAssertEqual(app.staticTexts["pad-editor.gain.value"].label, "5 dB")
        let correction = app.buttons["pad-editor.headroom"]
        XCTAssertTrue(correction.waitForExistence(timeout: 10))
        let peak = app.descendants(matching: .any)["pad-editor.peak"]
        let clippedPeak = peak.label
        XCTAssertTrue(clippedPeak.contains("clipped frames"), clippedPeak)
        let clippedLevel = try XCTUnwrap(clippedPeak.split(separator: " ").dropFirst().first.flatMap { Double($0) })
        XCTAssertGreaterThanOrEqual(clippedLevel, 1)
        correction.tap()
        let corrected = NSPredicate(format: "identifier == 'pad-editor.peak' AND NOT (label CONTAINS 'clipped frames')")
        let correctedPeak = app.descendants(matching: .any).matching(corrected).firstMatch
        XCTAssertTrue(correctedPeak.waitForExistence(timeout: 10))
        let correctedLevel = try XCTUnwrap(correctedPeak.label.split(separator: " ").dropFirst().first.flatMap { Double($0.replacingOccurrences(of: "−", with: "-")) })
        XCTAssertEqual(correctedLevel, -1, accuracy: 0.11)
        let savedGain = app.staticTexts["pad-editor.gain.value"].label
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Sampler-pad-waveform-night"
        shot.lifetime = .keepAlways
        add(shot)
        apply.tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 15))
        closePadSounds(app)

        app.buttons["Undo"].tap()
        openPadSounds(app)
        openKick()
        XCTAssertEqual(start.label, original, "One Undo restores the trim of the original Pocket Kick")
        app.buttons["pad-editor.cancel"].tap()
        closePadSounds(app)
        app.buttons["Redo"].tap()
        let saved = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Saved on this iPhone'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 12))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 15))
        openPadSounds(app)
        openKick()
        XCTAssertEqual(start.label, trimmed, "The assigned kick must reopen with the saved edit")
        XCTAssertEqual(app.staticTexts["pad-editor.gain.value"].label, savedGain)
        let receipt = XCTAttachment(string: "Pocket Kick: \(original) → \(trimmed). Playback: \(originalFrames) → \(editedFrames) frames. \(clippedPeak) → \(correctedLevel) dBFS. After relaunch: \(start.label).")
        receipt.name = "Sampler-pad-trim-playback"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    @MainActor func testDustyAndCoastAuditionWithoutEditingThenLoadDistinctPads() throws {
        let app = launch(appearance: "dark")
        defer { app.terminate() }
        entry(app).tap()
        app.buttons["sound.samples"].tap()
        let preview = app.buttons["pad-samples.preview-kit"]
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        var auditions: [String] = []

        for kit in ["Dusty", "Coast"] {
            let key = kit.lowercased()
            app.buttons[kit].tap()
            let load = app.buttons["pad-samples.load-" + key]
            for button in [preview, load] {
                XCTAssertGreaterThanOrEqual(button.frame.width, 90, "Each action must show its text beside the icon")
                XCTAssertGreaterThanOrEqual(button.frame.height, 44)
            }
            let before = try XCTUnwrap(preview.value as? String)
            XCTAssertEqual(field("kit", in: before), key)
            XCTAssertEqual(try XCTUnwrap(field("duration", in: before).flatMap(Double.init)), 0)
            let revision = try XCTUnwrap(field("revision", in: before).flatMap(Int.init))
            preview.tap()
            let played = NSPredicate(format: "value != %@ AND value CONTAINS 'duration='", before)
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: played, object: preview)], timeout: 15), .completed)
            // The short audition ends by itself; tapping on a stale "Stop preview" label could
            // start it again on a slow simulator, where one accessibility query can take 20 s.
            let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Audition beat'"), object: preview)
            XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 60), .completed, preview.label)
            let after = try XCTUnwrap(preview.value as? String)
            XCTAssertGreaterThan(try XCTUnwrap(field("duration", in: after).flatMap(Double.init)), 0)
            XCTAssertEqual(field("revision", in: after).flatMap(Int.init), revision, "Auditioning cannot edit the project")
            auditions.append(after)
            load.tap()
            for (pad, name) in [(0, "Kick"), (1, "Snare")] {
                let assigned = app.buttons.matching(NSPredicate(format: "identifier == %@ AND value == %@", "pad-samples.library.\(pad)", "\(kit) · \(name)")).firstMatch
                XCTAssertTrue(assigned.waitForExistence(timeout: 30))
            }
            XCTAssertEqual(field("revision", in: preview.value as? String ?? "").flatMap(Int.init), revision + 1)
        }
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Sampler-factory-kit-coast-night"
        shot.lifetime = .keepAlways
        add(shot)
        let receipt = XCTAttachment(string: auditions.joined(separator: "\n"))
        receipt.name = "Sampler-factory-auditions"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    @MainActor func testSavedCustomKitRestoresAllPadAssignmentsInAnotherProject() throws {
        executionTimeAllowance = 300
        let app = launch(appearance: "dark")
        defer { app.terminate() }
        let kits = app.buttons["pad-samples.my-kits"]
        let kickEditor = app.buttons["pad-samples.edit.0"]
        let trim = app.staticTexts["pad-editor.start.value"]
        let name = "After Hours"
        let savedKit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'pad-kits.load.' AND label == %@", name)).firstMatch

        openPadSounds(app)
        app.buttons["pad-samples.pocket-kit"].tap()
        XCTAssertTrue(kickEditor.waitForExistence(timeout: 15))
        kickEditor.tap()
        app.buttons["pad-editor.start.plus"].tap()
        let editedStart = trim.label
        app.buttons["pad-editor.apply"].tap()
        XCTAssertTrue(kits.waitForExistence(timeout: 15))
        let source = try XCTUnwrap(kits.value as? String)
        let sourceProject = try XCTUnwrap(field("project", in: source))
        let assignment = try XCTUnwrap(field("pads", in: source))
        XCTAssertEqual(assignment.split(separator: ",").count, 16)
        kits.tap()
        let names = app.textFields["pad-kits.name"]
        XCTAssertTrue(names.waitForExistence(timeout: 8))
        names.tap()
        names.typeText(name)
        app.buttons["pad-kits.save"].tap()
        XCTAssertTrue(savedKit.waitForExistence(timeout: 15))
        XCTAssertTrue((savedKit.value as? String)?.contains("16/16") == true)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Sampler-personal-kit-library-night"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["pad-kits.close"].tap()
        XCTAssertEqual(kits.value as? String, source, "Saving a reusable kit must leave the source project unchanged")
        closePadSounds(app)

        app.buttons["Projects"].tap()
        app.buttons["project.new"].tap()
        app.buttons["project.create"].tap()
        wait(app) { value in
            guard let id = self.field("project", in: value) else { return false }
            return id != sourceProject
        }
        openPadSounds(app)
        let before = try XCTUnwrap(kits.value as? String)
        let destination = try XCTUnwrap(field("project", in: before))
        XCTAssertNotEqual(sourceProject, destination)
        XCTAssertNotEqual(field("pads", in: before), assignment)
        kits.tap()
        XCTAssertTrue(savedKit.waitForExistence(timeout: 15))
        savedKit.tap()
        let restored = NSPredicate(format: "value CONTAINS %@", "pads=" + assignment)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: restored, object: kits)], timeout: 20), .completed)
        XCTAssertEqual(field("project", in: kits.value as? String ?? ""), destination)
        kickEditor.tap()
        XCTAssertTrue(trim.waitForExistence(timeout: 8))
        XCTAssertEqual(trim.label, editedStart)
        app.buttons["pad-editor.cancel"].tap()
        closePadSounds(app)
        app.buttons["Undo"].tap()
        openPadSounds(app)
        XCTAssertEqual(field("pads", in: kits.value as? String ?? ""), field("pads", in: before), "One Undo restores all 16 original assignments")
        let receipt = XCTAttachment(string: "Source: \(source)\nDestination before recall: \(before)\nRestored 16 pads and a \(editedStart) kick trim. Reverted all assignments with Undo.")
        receipt.name = "Sampler-personal-kit-recall"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    @MainActor private func openPadSounds(_ app: XCUIApplication) {
        entry(app).tap()
        app.buttons["sound.samples"].tap()
    }

    @MainActor private func closePadSounds(_ app: XCUIApplication) {
        app.navigationBars["Pad samples"].buttons["Done"].tap()
        app.navigationBars["Sound"].buttons["Cancel"].tap()
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
