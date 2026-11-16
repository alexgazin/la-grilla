import XCTest
import Foundation

/// An authored screen-recording tour, deliberately outside release UITests.
/// Every edit is made through the visible production controls. The test flag
/// only selects a disposable project store and the app's built-in demo song.
final class NativeDemoTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 300
    }

    @MainActor private func launch(runtimeTrace: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--screen", "grid", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if runtimeTrace {
            app.launchArguments += ["--runtime-trace", "--device-output-startup", "--project-store-id", UUID().uuidString]
        }
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10))
        mark("app.ready", app: app)
        pause(1)
        return app
    }

    @MainActor private func mark(_ phase: String, app: XCUIApplication, facts: [String: Any] = [:]) {
        var event: [String: Any] = [
            "phase": phase,
            "uptime_seconds": ProcessInfo.processInfo.systemUptime,
            "unix_seconds": Date().timeIntervalSince1970,
            "window_width": app.windows.firstMatch.frame.width,
            "window_height": app.windows.firstMatch.frame.height
        ]
        event.merge(facts) { _, observed in observed }
        let data = try! JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
        print("NATIVE_DEMO_EVENT " + String(decoding: data, as: UTF8.self))
        let receipt = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        receipt.name = "NativeDemo-" + phase
        receipt.lifetime = .keepAlways
        add(receipt)
        let frame = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        frame.name = "NativeDemo-" + phase
        frame.lifetime = .keepAlways
        add(frame)
    }

    private func pause(_ seconds: TimeInterval = 1.3) {
        Thread.sleep(forTimeInterval: seconds)
    }

    @MainActor private func reveal(_ control: XCUIElement, in app: XCUIApplication, scroll: XCUIElement? = nil) {
        let viewport = scroll ?? app.scrollViews.firstMatch
        for _ in 0..<8 {
            if control.exists, control.isHittable { return }
            viewport.swipeUp()
        }
        XCTAssertTrue(control.exists && control.isHittable, "Visible demo control missing: \(control.identifier)")
    }

    @MainActor private func play(_ app: XCUIApplication) {
        mark("transport.before-play", app: app)
        app.buttons["Play"].tap()
        XCTAssertTrue(app.staticTexts["PLAYING"].waitForExistence(timeout: 8))
        mark("transport.playing", app: app)
        pause(3)
    }

    @MainActor func test01ComposeJamAndMix() {
        let app = launch()
        mark("grid", app: app)
        play(app)

        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'grid.chord.'")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.tap()
        let symbol = app.textFields["chord.symbol"]
        XCTAssertTrue(symbol.waitForExistence(timeout: 5))
        symbol.tap()
        let value = symbol.value as? String ?? ""
        symbol.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count) + "Cmaj7")
        app.buttons["chord.set-symbol"].tap()
        XCTAssertFalse(app.staticTexts["chord.error"].exists)
        mark("chord.edit", app: app)
        reveal(app.buttons["chord.apply"], in: app)
        app.buttons["chord.apply"].tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Undo"].isEnabled)
        pause(2)
        mark("chord.applied", app: app)

        let timeline = app.scrollViews["grid.timeline"]
        XCTAssertTrue(timeline.exists)
        timeline.pinch(withScale: 1.1, velocity: 1)
        pause()
        mark("grid.pinch", app: app)
        timeline.pinch(withScale: 0.75, velocity: -1)
        pause()

        app.buttons["Jam"].tap()
        XCTAssertTrue(app.buttons["Kick"].waitForExistence(timeout: 5))
        mark("jam.pads", app: app)
        for pad in ["Kick", "Closed hat", "Snare", "Open hat"] {
            app.buttons[pad].tap()
            pause(0.25)
        }
        app.buttons["Record drums"].tap()
        XCTAssertTrue(app.staticTexts["REC · DRUMS"].waitForExistence(timeout: 10))
        mark("jam.recording", app: app)
        for pad in ["Kick", "Closed hat", "Snare", "Closed hat", "Kick", "Snare"] {
            app.buttons[pad].tap()
            pause(0.22)
        }
        app.buttons["Finish drum take"].tap()
        XCTAssertTrue(app.buttons["Undo"].isEnabled)
        pause(2)
        app.buttons["Steps"].tap()
        let step = app.buttons["jam.step.1"]
        reveal(step, in: app)
        let before = step.value as? String
        step.tap()
        XCTAssertNotEqual(step.value as? String, before)
        mark("jam.steps", app: app)
        pause(2)

        app.buttons["Mixer"].tap()
        let pan = app.sliders["mixer.pan.0"]
        XCTAssertTrue(pan.waitForExistence(timeout: 5))
        mark("mixer", app: app)
        pan.adjust(toNormalizedSliderPosition: 0.75)
        pause(1.5)
        pan.adjust(toNormalizedSliderPosition: 0.5)
        app.buttons["mixer.mute.0"].tap()
        XCTAssertEqual(app.buttons["mixer.mute.0"].value as? String, "On")
        pause(1.2)
        app.buttons["mixer.mute.0"].tap()
        pause(1.5)
        mark("mixer.changed", app: app)

        app.buttons["Grid"].tap()
        app.buttons["notes.open"].tap()
        XCTAssertTrue(app.navigationBars["Piano roll"].waitForExistence(timeout: 5))
        for _ in 0..<3 { app.buttons["notes.add"].tap(); pause(0.4) }
        XCTAssertEqual(app.staticTexts["notes.count"].label, "3")
        mark("notes.added", app: app)
        app.buttons["Copy note"].tap()
        app.buttons["Paste note"].tap()
        XCTAssertEqual(app.staticTexts["notes.count"].label, "4")
        pause(2)
        app.buttons["notes.undo"].tap()
        XCTAssertEqual(app.staticTexts["notes.count"].label, "3")
        mark("notes.undo", app: app)
        app.buttons["Done"].tap()
        app.buttons["Stop"].tap()
        mark("compose.end", app: app)
    }

    @MainActor func test02HarmonyCommandsAndVoiceSetup() {
        let app = launch()
        app.buttons["harmony.open"].tap()
        XCTAssertTrue(app.navigationBars["Harmony lab"].waitForExistence(timeout: 5))
        app.buttons["harmony.generate"].tap()
        reveal(app.buttons["harmony.b"], in: app)
        mark("harmony.proposal", app: app)
        app.buttons["harmony.b"].tap()
        XCTAssertTrue(app.buttons["Stop preview"].exists)
        pause(4)
        mark("harmony.preview-b", app: app)
        app.buttons["harmony.a"].tap()
        pause(3)
        app.buttons["harmony.apply"].tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout: 5))
        pause(2)
        mark("harmony.applied", app: app)

        app.buttons["assistant.open"].tap()
        XCTAssertTrue(app.navigationBars["Assistant"].waitForExistence(timeout: 5))
        let input = app.textViews["assistant.input"]
        input.tap()
        input.typeText("tempo 108")
        app.swipeUp()
        reveal(app.buttons["assistant.generate"], in: app, scroll: app.scrollViews["assistant.review-scroll"])
        app.buttons["assistant.generate"].tap()
        reveal(app.buttons["assistant.apply"], in: app, scroll: app.scrollViews["assistant.review-scroll"])
        mark("assistant.local-review", app: app)
        pause(2)
        app.buttons["assistant.apply"].tap()
        let tempo = app.staticTexts["studio.tempo"]
        XCTAssertTrue(tempo.waitForExistence(timeout: 5))
        XCTAssertEqual(tempo.label, "108 BPM")
        mark("assistant.applied", app: app)
        pause(2)
        app.buttons["Undo"].tap()
        XCTAssertEqual(tempo.label, "120 BPM")

        app.buttons["More studio tools"].tap()
        app.buttons["voice.open"].tap()
        XCTAssertTrue(app.navigationBars["Voice to MIDI"].waitForExistence(timeout: 5))
        mark("voice.beta-preparation", app: app)
        pause(3)
        app.buttons["Cancel"].tap()
        mark("commands.end", app: app)
    }

    @MainActor func test03PerformAndExport() {
        let app = launch()
        app.buttons["More studio tools"].tap()
        app.buttons["perform.open"].tap()
        XCTAssertTrue(app.buttons["perform.record"].waitForExistence(timeout: 5))
        mark("perform", app: app)
        app.buttons["perform.record"].tap()
        let knob = app.sliders["perform.filter"]
        XCTAssertTrue(knob.waitForExistence(timeout: 5))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: knob)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
        pause(2)
        let center = knob.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.withOffset(CGVector(dx: 0, dy: -44)).press(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: 44, dy: 0)))
        pause(2)
        mark("perform.filter", app: app)
        app.buttons["perform.filter.reset"].tap()
        app.sliders["Delay wet"].adjust(toNormalizedSliderPosition: 0.5)
        pause(3)
        app.buttons["perform.repeat"].tap()
        pause(2)
        app.buttons["perform.repeat"].tap()
        app.buttons["perform.record"].tap()
        mark("perform.saved-take", app: app)
        reveal(app.buttons["perform.edit"], in: app)
        app.buttons["perform.edit"].tap()
        XCTAssertTrue(app.buttons["export.open"].waitForExistence(timeout: 8))

        app.buttons["export.open"].tap()
        app.buttons["format.wav"].tap()
        mark("export.wav-options", app: app)
        pause(2)
        reveal(app.buttons["export.confirm"], in: app)
        app.buttons["export.confirm"].tap()
        let shared = app.otherElements["ActivityListView"].waitForExistence(timeout: 30) || app.buttons["Copy"].exists || app.staticTexts["Save to Files"].exists
        XCTAssertTrue(shared, "Actual WAV export must reach the iOS share sheet")
        mark("export.actual-share-sheet", app: app)
        pause(3)
    }

    /// The built-in example is a real local command, entered through the
    /// production examples sheet. No proposal, score or sound is injected.
    @MainActor func test04EmptyLocalSketchAndTranspose() throws {
        let app = launch(runtimeTrace: true)
        let transport = app.buttons["perform.transport"]
        app.buttons["Projects"].tap()
        XCTAssertTrue(app.buttons["project.new"].waitForExistence(timeout: 5))
        app.buttons["project.new"].tap()
        let empty = app.buttons["project.template.empty"]
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        XCTAssertTrue(empty.isSelected)
        mark("sketch.empty-starting-point", app: app)
        pause()
        app.buttons["project.create"].tap()
        XCTAssertTrue(app.staticTexts["grid.empty-state"].waitForExistence(timeout: 8))
        let original = trace(transport)
        let projectID = try XCTUnwrap(field("project", in: original))
        let originalRevision = try XCTUnwrap(field("revision", in: original))
        mark("sketch.empty", app: app, facts: ["runtime": original])
        pause(2)

        app.buttons["assistant.open"].tap()
        XCTAssertTrue(app.navigationBars["Assistant"].waitForExistence(timeout: 5))
        app.buttons["assistant.language.en"].tap()
        app.buttons["assistant.examples"].tap()
        let example = app.buttons["assistant.example.sketch"]
        XCTAssertTrue(example.waitForExistence(timeout: 5))
        example.tap()
        let generate = app.buttons["assistant.generate"]
        reveal(generate, in: app, scroll: app.scrollViews["assistant.review-scroll"])
        mark("sketch.command", app: app)
        pause(2)
        generate.tap()
        let parts = app.staticTexts["assistant.sketch.parts"]
        XCTAssertTrue(parts.waitForExistence(timeout: 8))
        reveal(parts, in: app, scroll: app.scrollViews["assistant.review-scroll"])
        let data = Data(try XCTUnwrap(parts.value as? String).utf8)
        let facts = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(facts["style"] as? String, "house")
        XCTAssertEqual(facts["bars"] as? Int, 8)
        XCTAssertEqual(facts["seed"] as? Int, 42)
        XCTAssertEqual(facts["modelInterpretedParameters"] as? Bool, false)
        for role in ["chords", "drums", "bass", "melody"] {
            XCTAssertGreaterThan(facts[role] as? Int ?? 0, 0, role)
        }
        XCTAssertTrue(app.staticTexts["LOCAL"].exists)
        XCTAssertFalse(app.staticTexts["ON-DEVICE AI"].exists)
        mark("sketch.local-review", app: app, facts: ["sketch": facts])
        pause(3)

        let a = app.buttons["assistant.a"], b = app.buttons["assistant.b"]
        reveal(a, in: app, scroll: app.scrollViews["assistant.review-scroll"])
        a.tap()
        waitForRuntime(transport) { report in
            report.contains("preview=true") && report.contains("actualPlaying=1") && self.number("outputPeak", in: report) < 0.0001
        }
        XCTAssertEqual(field("revision", in: trace(transport)), originalRevision)
        mark("sketch.preview-a-empty", app: app, facts: ["runtime": trace(transport)])
        pause(2)
        b.tap()
        waitForRuntime(transport) { report in
            report.contains("preview=true") && report.contains("actualPlaying=1") && self.number("outputPeak", in: report) > 0.001
        }
        XCTAssertEqual(field("revision", in: trace(transport)), originalRevision)
        mark("sketch.preview-b-local", app: app, facts: ["runtime": trace(transport)])
        pause(4)
        let apply = app.buttons["assistant.apply"]
        reveal(apply, in: app, scroll: app.scrollViews["assistant.review-scroll"])
        apply.tap()
        XCTAssertTrue(app.buttons["assistant.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Assistant"].exists)
        XCTAssertFalse(app.staticTexts["grid.empty-state"].exists)
        let chords = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'grid.chord.'"))
        XCTAssertEqual(chords.count, 8)
        XCTAssertEqual(field("project", in: trace(transport)), projectID)
        XCTAssertNotEqual(field("revision", in: trace(transport)), originalRevision)
        XCTAssertEqual(number("loopRangeCount", in: trace(transport)), 8 * 3840)
        XCTAssertTrue(app.buttons["Undo"].isEnabled)
        mark("sketch.applied", app: app, facts: ["runtime": trace(transport)])
        pause(2)

        app.buttons["Play"].tap()
        waitForRuntime(transport) { report in
            report.contains("preview=false") && report.contains("actualPlaying=1") && self.number("outputPeak", in: report) > 0.001
                && self.field("actualRevision", in: report) == self.field("revision", in: report)
        }
        let bpm = try XCTUnwrap(facts["bpm"] as? Double)
        XCTAssertGreaterThan(bpm, 0)
        let fullLoopSeconds = 8 * 4 * 60 / bpm
        let startClock = number("actualClock", in: trace(transport))
        mark("sketch.live-eight-bars-start", app: app, facts: ["runtime": trace(transport), "bars": 8, "bpm": bpm, "minimum_hold_seconds": fullLoopSeconds])
        // One uninterrupted real eight-bar loop. It remains at captured speed
        // in the final film; these seconds are not an idle-wait cut candidate.
        pause(fullLoopSeconds + 0.5)
        XCTAssertGreaterThan(number("actualClock", in: trace(transport)), startClock)
        XCTAssertTrue(app.buttons["Stop"].exists)
        mark("sketch.live-eight-bars-end", app: app, facts: ["runtime": trace(transport)])

        app.buttons["studio.tempo"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let transpose = app.buttons["settings.transpose"]
        revealFormControl(transpose, in: app)
        transpose.tap()
        XCTAssertTrue(app.navigationBars["Transpose arrangement"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.steppers["transpose.semitones"].value as? String, "2")
        mark("sketch.transpose-plus-two-review", app: app)
        pause(2)
        let transposeApply = app.buttons["transpose.apply"]
        revealFormControl(transposeApply, in: app)
        XCTAssertTrue(transposeApply.isEnabled)
        let beforeTranspose = field("revision", in: trace(transport))
        transposeApply.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        waitForRuntime(transport) { report in
            report.contains("actualPlaying=1") && self.field("revision", in: report) != beforeTranspose
                && self.field("actualRevision", in: report) == self.field("revision", in: report)
                && self.number("outputPeak", in: report) > 0.001
        }
        mark("sketch.transpose-plus-two-applied", app: app, facts: ["runtime": trace(transport)])
        pause(4)
        app.buttons["Stop"].tap()
        mark("sketch.end", app: app)
        pause(3)
    }

    @MainActor private func trace(_ transport: XCUIElement) -> String {
        (transport.value as? String ?? "").components(separatedBy: "\n").first ?? ""
    }

    private func field(_ key: String, in report: String) -> String? {
        report.split(separator: " ").first(where: { $0.hasPrefix(key + "=") }).map { String($0.dropFirst(key.count + 1)) }
    }

    private func number(_ key: String, in report: String) -> Double {
        Double(field(key, in: report) ?? "") ?? -1
    }

    @MainActor private func waitForRuntime(_ transport: XCUIElement, condition: (String) -> Bool) {
        let deadline = Date().addingTimeInterval(8)
        repeat {
            if condition(trace(transport)) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        XCTFail("The actual audio runtime did not reach the authored state: \(trace(transport))")
    }

    @MainActor private func revealFormControl(_ control: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            let scroll = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch.exists ? app.tables.firstMatch : app.scrollViews.firstMatch
            let visible = scroll.frame.intersection(app.frame.insetBy(dx: 0, dy: 44))
            if control.exists {
                let frame = control.frame
                if control.isHittable && !frame.isEmpty && visible.contains(frame) { return }
                if !frame.isEmpty && frame.maxY > visible.maxY { scroll.swipeUp(); continue }
                if !frame.isEmpty && frame.minY < visible.minY { scroll.swipeDown(); continue }
            }
            scroll.swipeUp()
        }
        XCTFail("The actual Form control must be wholly visible: \(control.identifier)")
    }
}
