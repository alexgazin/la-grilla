import XCTest

/// U11 demo tour, U14 one-hand reach, U31 selected clips, U39 density, U60 simple mode,
/// U64 rotation, U67 hold to preview, U20 launch time and U49 heavy screens.
final class InterfaceWaveUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 300 }
    override func tearDown() { XCUIDevice.shared.orientation = .portrait; super.tearDown() }

    @MainActor private func launch(_ extra: [String] = [], screen: String? = "grid") -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            + (screen.map { ["--screen", $0] } ?? []) + extra
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 30))
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

    @MainActor private func reach(_ element: XCUIElement, in scroll: XCUIElement, up: Bool = true) {
        for _ in 0..<10 where !(element.exists && element.isHittable) { up ? scroll.swipeUp() : scroll.swipeDown() }
        XCTAssertTrue(element.exists && element.isHittable, "\(element.identifier) should be reachable")
    }

    @MainActor private func openSettings(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["tools.more"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 10))
        return app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
    }

    @MainActor private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    // MARK: U11

    @MainActor func testTourIsCompletedSkippedAndReopened() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--respect-welcome", "--show-welcome", "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let start = app.buttons["welcome.tour"]
        XCTAssertTrue(start.waitForExistence(timeout: 30))
        start.tap()
        let number = app.staticTexts["tour.number"], show = app.buttons["tour.show"], finish = app.buttons["tour.finish"]
        func step(_ n: Int) -> Bool { eventually { number.exists && number.label == "STEP \(n) OF 5" } }
        XCTAssertTrue(step(1), "The tour starts on the demo song at step 1")
        shoot("U11-tour-step-1")
        // 1 · pads: Show me opens Jam; hitting a pad finishes the step.
        show.tap()
        let pad = app.buttons["jam.pad.0"]
        XCTAssertTrue(pad.waitForExistence(timeout: 10))
        pad.tap()
        XCTAssertTrue(step(2))
        // 2 · chords: Show me opens the first chord; choosing another one finishes the step.
        show.tap()
        let input = app.textFields["chord.symbol"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        let previous = input.value as? String ?? ""
        input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + "Fmaj7\n")
        let apply = app.buttons["chord.apply"]
        for _ in 0..<6 where !apply.isHittable { app.scrollViews.firstMatch.swipeUp() }
        apply.tap()
        XCTAssertTrue(step(3))
        // 3 · hum: Show me opens Voice to MIDI.
        show.tap()
        XCTAssertTrue(app.navigationBars["Voice to MIDI"].waitForExistence(timeout: 10))
        app.navigationBars["Voice to MIDI"].buttons["Cancel"].tap()
        XCTAssertTrue(step(4))
        // 4 · layers: Show me opens Mixer.
        show.tap()
        XCTAssertTrue(step(5))
        // 5 · export: Show me opens Export.
        show.tap()
        XCTAssertTrue(app.navigationBars["Export"].waitForExistence(timeout: 10))
        app.navigationBars["Export"].buttons["Cancel"].tap()
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "All five steps done")
        shoot("U11-tour-complete")
        finish.tap()
        XCTAssertTrue(eventually { !show.exists && !finish.exists })
        // Reopen from Settings, then skip it.
        let form = openSettings(app)
        let again = app.buttons["settings.tour"]
        reach(again, in: form)
        again.tap()
        XCTAssertTrue(step(1), "Settings → Show me around starts the tour again")
        app.buttons["tour.skip"].tap()
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        finish.tap()
        XCTAssertTrue(eventually { !finish.exists && !show.exists })
    }

    // MARK: U14

    @MainActor func testOneHandReachPutsTheTopButtonsBelowTheMiddle() {
        let app = launch(["--one-hand"])
        let middle = app.windows.firstMatch.frame.midY
        for element in [app.buttons["commands.open"], app.buttons["export.open"], app.buttons["Undo"].firstMatch, app.buttons["Projects"].firstMatch] {
            XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element) exists")
            XCTAssertGreaterThan(element.frame.midY, middle, "\(element.label) sits in the bottom half")
        }
        XCTAssertTrue(app.otherElements["studio.one-hand-bar"].exists || app.descendants(matching: .any)["studio.one-hand-bar"].exists)
        shoot("U14-one-hand")
        // The setting is in Settings → Comfort.
        let form = openSettings(app)
        let toggle = app.switches["settings.one-hand"]
        reach(toggle, in: form)
        XCTAssertEqual(toggle.value as? String, "1")
    }

    // MARK: U31

    @MainActor func testSelectingThreeClipsDeletesThemAtOnceAndUndoBringsThemBack() {
        let app = launch(["--arrangement-clips"])
        let clips = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'grid.clip.' AND NOT identifier BEGINSWITH 'grid.clip.add' AND NOT identifier BEGINSWITH 'grid.clip.list' AND NOT identifier BEGINSWITH 'grid.clip.options'"))
        XCTAssertTrue(clips.firstMatch.waitForExistence(timeout: 15))
        // The demo has a chord clip and a drum clip; add one more drum clip from the clip list.
        app.buttons["grid.clips.list"].tap()
        XCTAssertTrue(app.navigationBars["Clip list"].waitForExistence(timeout: 8))
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'grid.clip.add.drums.'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Clip settings"].waitForExistence(timeout: 8))
        app.buttons["Done"].tap()
        XCTAssertTrue(eventually { clips.count >= 3 })
        let before = clips.count
        app.buttons["grid.select"].tap()
        let count = app.staticTexts["grid.select.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        // A tap picks a clip; a section chip adds every clip that plays in it.
        let first = clips.firstMatch
        XCTAssertTrue(first.isHittable)
        first.tap()
        XCTAssertTrue(eventually { count.label == "1 selected" }, count.label)
        let section = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'grid.section.'")).firstMatch
        XCTAssertTrue(section.isHittable)
        section.tap()
        XCTAssertTrue(eventually { count.label == "\(before) selected" }, count.label)
        XCTAssertEqual(before, 3)
        shoot("U31-three-selected")
        app.buttons["grid.batch.delete"].tap()
        XCTAssertTrue(eventually { clips.count == 0 }, "All three clips go at once")
        app.buttons["grid.select.done"].tap()
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(eventually { clips.count == before }, "One Undo brings all three back")
    }

    // MARK: U39

    @MainActor func testDensityChangesHowTallTheBarsAre() {
        var heights: [String: CGFloat] = [:]
        for density in ["compact", "normal", "large"] {
            let app = launch(["--density", density])
            let jam = app.buttons["Jam"].firstMatch
            XCTAssertTrue(jam.waitForExistence(timeout: 10))
            heights[density] = jam.frame.height
            shoot("U39-density-\(density)")
            app.terminate()
        }
        let compact = heights["compact"] ?? 0, normal = heights["normal"] ?? 0, large = heights["large"] ?? 0
        XCTAssertGreaterThanOrEqual(compact, 44, "Never under the touch minimum")
        XCTAssertLessThan(compact, normal, "\(heights)")
        XCTAssertLessThan(normal, large, "\(heights)")
    }

    // MARK: U60

    @MainActor func testSimpleModeHidesMIDIDevicesUntilShowMore() {
        let app = launch(["--feature-level", "simple"])
        let form = openSettings(app)
        let more = app.buttons["settings.show-more"]
        reach(more, in: form)
        XCTAssertFalse(app.buttons["settings.midi"].exists, "Simple mode hides MIDI devices")
        more.tap()
        let midi = app.buttons["settings.midi"]
        reach(midi, in: form, up: false)
        XCTAssertTrue(midi.exists)
        app.navigationBars["Settings"].buttons["Done"].tap()
        // The mixer keeps automation behind Show more too.
        app.buttons["Mixer"].firstMatch.tap()
        XCTAssertTrue(app.buttons["mixer.show-more"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["mixer.automation"].exists)
        app.buttons["mixer.show-more"].tap()
        XCTAssertTrue(app.buttons["mixer.automation"].waitForExistence(timeout: 5))
    }

    // MARK: U64

    @MainActor func testSelectedNoteStaysSelectedAfterRotation() {
        let app = launch()
        let open = app.buttons["notes.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
        XCTAssertTrue(app.navigationBars["Piano roll"].waitForExistence(timeout: 8))
        app.buttons["notes.add"].tap()
        let pitch = app.steppers["Note pitch"]
        XCTAssertTrue(pitch.waitForExistence(timeout: 8), "Adding a note selects it")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(eventually { app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height })
        XCTAssertTrue(app.navigationBars["Piano roll"].exists, "The sheet stays open")
        XCTAssertTrue(pitch.waitForExistence(timeout: 8), "The note is still selected in landscape")
        shoot("U64-landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(eventually { app.windows.firstMatch.frame.width < app.windows.firstMatch.frame.height })
        XCTAssertTrue(pitch.waitForExistence(timeout: 8), "…and back in portrait")
    }

    // MARK: U67

    @MainActor func testHoldingABeatPlaysItAndLettingGoStops() {
        let app = launch()
        app.buttons["commands.open"].tap()
        let field = app.textFields["commands.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("new project\n")
        let quick = app.buttons["project.quick.house"]
        XCTAssertTrue(quick.waitForExistence(timeout: 10))
        XCTAssertTrue((quick.value as? String ?? "").hasPrefix("0 previews"), quick.value as? String ?? "")
        quick.press(forDuration: 2.0)
        XCTAssertTrue(eventually { (quick.value as? String ?? "") == "1 previews, not playing" }, quick.value as? String ?? "")
        // Holding is not a tap: no project was made and the sheet is still here.
        XCTAssertFalse(app.navigationBars["Beat machine"].exists)
        XCTAssertTrue(quick.exists)
        // The starter template is held the same way.
        let starter = app.buttons["project.template.starter"]
        for _ in 0..<4 where !starter.isHittable { app.swipeDown() }
        starter.press(forDuration: 1.5)
        XCTAssertTrue(eventually { (starter.value as? String ?? "") == "1 previews, not playing" }, starter.value as? String ?? "")
    }

    // MARK: U20 · U49

    @MainActor func testLaunchAndHeavyScreensStayQuick() {
        let app = launch(["--prewarm"])
        let readout = app.staticTexts["studio.launch-ms"]
        XCTAssertTrue(readout.waitForExistence(timeout: 10))
        let launchMs = Int(readout.label) ?? 0
        XCTAssertGreaterThan(launchMs, 0)
        #if targetEnvironment(simulator)
        let limit = 6000 // shared CI simulators; the device target is 1000 ms
        #else
        let limit = 1000
        #endif
        XCTAssertLessThanOrEqual(launchMs, limit, "Launch to a ready studio took \(launchMs) ms")
        let receipt = XCTAttachment(string: "launch to ready: \(launchMs) ms (limit \(limit) ms)"); receipt.name = "U20-launch"; receipt.lifetime = .keepAlways; add(receipt)
        // The piano roll opens inside the signpost interval measured by XCTOSSignpostMetric.
        let options = XCTMeasureOptions(); options.iterationCount = 2
        let open = app.buttons["notes.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        measure(metrics: [XCTOSSignpostMetric(subsystem: "com.lagrilla.studio", category: "Screens", name: "Open piano roll"), XCTClockMetric()], options: options) {
            open.tap()
            XCTAssertTrue(app.navigationBars["Piano roll"].waitForExistence(timeout: 10))
            app.navigationBars["Piano roll"].buttons["Done"].tap()
            XCTAssertTrue(open.waitForExistence(timeout: 10))
        }
        let started = Date()
        app.buttons["Mixer"].firstMatch.tap()
        XCTAssertTrue(app.buttons["mixer.palettes"].waitForExistence(timeout: 10))
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "The mixer opens quickly")
    }
}
