import XCTest

/// Build 53: U29 hold to hear, U33 song previews, U37 levels, U63 eco mode, U55 EQ comparison,
/// U5 Discard, U69 hints, I6 slice editor, U27 pad drag, I52 Assign MIDI, I68 recovery,
/// U15 song table, U20/U49 launch time, the beat machine's own sound.
final class Build53UITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 300 }

    @MainActor private func launch(_ screen: String? = "grid", _ extra: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--device-output-startup", "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            + (screen.map { ["--screen", $0] } ?? []) + extra
        app.launch()
        if screen != "projects" { XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 30)) }
        return app
    }

    @MainActor private func eventually(_ timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return condition()
    }

    @MainActor private func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }

    @MainActor private func openSettings(_ app: XCUIApplication) -> XCUIElement {
        let more = app.buttons["tools.more"]
        if !more.waitForExistence(timeout: 3) { app.buttons["Grid"].firstMatch.tap() }
        XCTAssertTrue(more.waitForExistence(timeout: 10))
        more.tap(); app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        return app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
    }

    @MainActor private func reach(_ element: XCUIElement, in scroll: XCUIElement, _ name: String) {
        for _ in 0..<12 where !(element.exists && element.isHittable) { scroll.swipeUp() }
        XCTAssertTrue(element.exists, "\(name) should be on the screen")
    }

    @MainActor private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    // MARK: U29

    @MainActor func testHeldChordSoundsUntilReleaseAndChangesNothing() {
        let app = launch()
        let chord = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'grid.chord.'")).firstMatch
        XCTAssertTrue(chord.waitForExistence(timeout: 15))
        let hold = any(app, "studio.hold")
        XCTAssertTrue(hold.waitForExistence(timeout: 5))
        XCTAssertEqual(hold.label, "0 off")
        // A hold sounds the chord until the finger lifts (press() returns after the release).
        chord.press(forDuration: 1.2)
        XCTAssertTrue(eventually { hold.label == "1 off" }, "The held chord sounded and stopped on release: \(hold.label)")
        shoot("U29-held-chord")
        XCTAssertFalse(app.navigationBars["Edit chord"].exists, "The release that ends a hold opens nothing")
        XCTAssertFalse(app.buttons["Undo"].firstMatch.isEnabled, "Holding a chord never edits the song")
        // A plain tap still opens the chord editor, whose ⋯ menu has voice editing and Delete.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        chord.tap()
        XCTAssertTrue(app.navigationBars["Edit chord"].waitForExistence(timeout: 8))
        app.buttons["chord.more"].tap()
        XCTAssertTrue(app.buttons["chord.voice"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chord.delete"].exists)
    }

    // MARK: U33

    @MainActor func testHoldingASongPictureIsAPreview() {
        let app = launch("projects")
        let picture = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'project.preview.'")).firstMatch
        XCTAssertTrue(picture.waitForExistence(timeout: 30))
        picture.press(forDuration: 2.0)
        XCTAssertTrue(eventually { (picture.value as? String ?? "") == "1 previews, not playing" }, picture.value as? String ?? "")
    }

    // MARK: U37 · U15

    @MainActor func testTrackLevelsMoveAndTheSongTableReadsBars() {
        let app = launch("grid", ["--voiceover-table"])
        let row = app.buttons["grid.table.row.1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.label.hasPrefix("Bar 1,"), row.label)
        XCTAssertTrue(app.buttons["grid.table.row.2"].label.contains("Am"), app.buttons["grid.table.row.2"].label)
        shoot("U15-song-table")
        app.buttons["Play"].tap()
        let levels = app.descendants(matching: .any).matching(identifier: "grid.level")
        XCTAssertTrue(eventually(15) { (0..<levels.count).contains { levels.element(boundBy: $0).value as? String == "Playing" } }, "A track level moves while the song plays")
        app.buttons["Stop"].tap()
    }

    // MARK: U63 · U20 · U49

    @MainActor func testEcoModeAndLaunchTimeInSettings() {
        let app = launch("grid", ["--low-power"])
        let form = openSettings(app)
        reach(any(app, "settings.eco"), in: form, "Eco mode note")
        let launchTime = any(app, "settings.launch-time")
        reach(launchTime, in: form, "Launch time")
        XCTAssertTrue((launchTime.label + (launchTime.value as? String ?? "")).contains("ms"))
    }

    // MARK: U55

    @MainActor func testEQComparesWithAndWithoutAtTheSameLoudness() {
        let app = launch("mixer")
        // The EQ button carries an identifier, so it is found by that, not by its label.
        let eq = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'mixer.eq.'")).firstMatch
        XCTAssertTrue(eq.waitForExistence(timeout: 15))
        for _ in 0..<6 where !eq.isHittable { app.swipeUp() }
        eq.tap()
        XCTAssertTrue(app.navigationBars["Parametric EQ"].waitForExistence(timeout: 8))
        let without = app.buttons["eq.listen.1"]
        for _ in 0..<8 where !without.isHittable { app.swipeUp() }
        without.tap()
        app.buttons["eq.play"].tap()
        XCTAssertTrue(any(app, "eq.match").waitForExistence(timeout: 60), "Levels are matched before the version without the EQ plays")
        shoot("U55-eq-compare")
        app.buttons["eq.play"].tap()
    }

    // MARK: U5 · U69

    @MainActor func testAssistantHintsAndDiscardLeaveTheSongAlone() {
        let app = launch()
        app.buttons["assistant.open"].tap()
        XCTAssertTrue(app.navigationBars["Assistant"].waitForExistence(timeout: 10))
        let hint = app.buttons["assistant.hint.0"]
        XCTAssertTrue(hint.waitForExistence(timeout: 8), "Hints under the field")
        let text = hint.label
        hint.tap()
        XCTAssertTrue(eventually { (app.textViews.firstMatch.value as? String ?? "") == text }, "The hint goes into the field")
        app.buttons["Examples"].tap()
        let example = app.buttons["assistant.example.jazzify"]
        XCTAssertTrue(example.waitForExistence(timeout: 8)); example.tap()
        let scroll = app.scrollViews["assistant.review-scroll"]
        let generate = app.buttons["assistant.generate"]
        for _ in 0..<8 where !generate.isHittable { scroll.swipeUp() }
        generate.tap()
        let discard = app.buttons["assistant.discard"]
        XCTAssertTrue(discard.waitForExistence(timeout: 20))
        for _ in 0..<8 where !discard.isHittable { scroll.swipeUp() }
        discard.tap()
        XCTAssertTrue(eventually { !app.buttons["assistant.apply"].exists }, "Discard closes the proposal")
        app.navigationBars["Assistant"].buttons["Cancel"].firstMatch.tap()
        XCTAssertFalse(app.buttons["Undo"].firstMatch.isEnabled, "Nothing reached the song")
        // Name ideas for a new song.
        app.buttons["commands.open"].tap()
        let field = app.textFields["commands.field"]; XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("new project\n")
        let idea = app.buttons["project.name-idea.0"]
        XCTAssertTrue(idea.waitForExistence(timeout: 10))
        let name = idea.label
        idea.tap()
        XCTAssertEqual(app.textFields["project.name"].value as? String, name)
    }

    // MARK: I6

    @MainActor func testSliceEditorShowsTheCutsBeforeThePads() {
        let app = launch("jam", ["--slicer-fixture"])
        let drums = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sound.track.drums.'")).firstMatch
        XCTAssertTrue(drums.waitForExistence(timeout: 15)); drums.tap()
        app.buttons["sound.samples"].tap()
        XCTAssertTrue(app.navigationBars["Slice a loop"].waitForExistence(timeout: 15))
        let count = app.staticTexts["slicer.count"]
        XCTAssertTrue(eventually(15) { count.exists && count.label == "8 slices" }, count.label)
        XCTAssertTrue(app.buttons["slicer.marker.7"].exists || any(app, "slicer.marker.7").exists)
        shoot("I6-slicer")
        app.buttons["slicer.apply"].tap()
        XCTAssertTrue(eventually(20) { !app.navigationBars["Slice a loop"].exists })
        XCTAssertTrue(app.navigationBars["Pad samples"].waitForExistence(timeout: 10))
    }

    // MARK: U27

    @MainActor func testDraggingAPadOntoAnotherSwapsThemInOneUndo() {
        let app = launch("jam")
        let kick = any(app, "jam.layer.drag.0"), hats = any(app, "jam.layer.drag.2")
        XCTAssertTrue(kick.waitForExistence(timeout: 15) && hats.waitForExistence(timeout: 5))
        for _ in 0..<6 where !(kick.isHittable && hats.isHittable) { app.swipeUp() }
        kick.press(forDuration: 1.2, thenDragTo: hats, withVelocity: .slow, thenHoldForDuration: 0.6)
        XCTAssertTrue(eventually(10) { app.buttons["Undo"].firstMatch.isEnabled }, "The swap is one edit")
    }

    // MARK: I52

    @MainActor func testSynthKnobOffersAssignMIDI() {
        let app = launch("mixer")
        let menu = app.buttons["mixer.track-menu.harmony"]
        XCTAssertTrue(menu.waitForExistence(timeout: 15)); menu.tap()
        let effects = app.buttons["Effects"].firstMatch
        XCTAssertTrue(effects.waitForExistence(timeout: 5)); effects.tap()
        let synth = app.buttons["Synth…"].firstMatch
        XCTAssertTrue(synth.waitForExistence(timeout: 5)); synth.tap()
        let use = app.switches["synth.enabled"]
        XCTAssertTrue(use.waitForExistence(timeout: 8))
        // The row is one element; the switch inside it is what turns the synth on.
        if (use.value as? String) != "1" {
            let inner = use.switches.firstMatch
            if inner.exists { inner.tap() } else { use.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap() }
        }
        XCTAssertTrue(eventually { (use.value as? String) == "1" }, "The synth is on")
        // "Assign a MIDI knob" lists the synth's knobs.
        let midi = app.buttons["synth.midi"]
        XCTAssertTrue(midi.waitForExistence(timeout: 8)); midi.tap()
        let assign = app.buttons["midi.assign.synthCutoff"]
        XCTAssertTrue(assign.waitForExistence(timeout: 5)); assign.tap()
        // The open sheet itself says it is waiting for a controller and offers a way out.
        XCTAssertTrue(any(app, "midi.learning").waitForExistence(timeout: 5), "The synth sheet shows it is listening")
        shoot("I52-assign-midi")
        app.buttons["midi.learning.cancel"].tap()
        XCTAssertTrue(eventually { !any(app, "midi.learning").exists })
    }

    // MARK: I68

    @MainActor func testRecoveryBringsBackUnsavedChangesInOneUndo() {
        let app = launch("grid", ["--recovery-fixture"])
        let notice = any(app, "studio.recovery")
        XCTAssertTrue(notice.waitForExistence(timeout: 10), "The studio offers the unsaved changes")
        shoot("I68-recovery")
        let tempo = app.staticTexts["studio.tempo"]
        let before = Int(tempo.label.split(separator: " ").first ?? "") ?? 0
        app.buttons["Restore"].firstMatch.tap()
        XCTAssertTrue(eventually { (Int(tempo.label.split(separator: " ").first ?? "") ?? 0) == before + 7 }, tempo.label)
        XCTAssertTrue(app.buttons["Undo"].firstMatch.isEnabled)
        XCTAssertFalse(notice.exists)
    }

    // MARK: Own 808 sound

    @MainActor func testBeatMachineOffersYourOwnSoundForThe808() {
        let app = launch("jam")
        app.buttons["commands.open"].tap()
        let field = app.textFields["commands.field"]; XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("beat machine\n")
        XCTAssertTrue(app.navigationBars["Beat machine"].waitForExistence(timeout: 15))
        let own = app.buttons["beat.sound.own"]
        for _ in 0..<8 where !own.exists || !own.isHittable { app.swipeUp() }
        XCTAssertTrue(own.exists, "My sound sits with the bass sounds")
    }
}
