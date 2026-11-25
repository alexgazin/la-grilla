import XCTest

/// Build 55: arpeggiator to MIDI, live arpeggiator note length, natural or on-the-grid takes,
/// FM/analog sounds and classic drum machine kits, and the track builder's Listen button.
final class Build55UITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 300 }

    @MainActor private func launch(_ screen: String? = "grid", _ extra: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--device-output-startup", "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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

    @MainActor private func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }

    @MainActor private func command(_ text: String, in app: XCUIApplication) {
        app.buttons["commands.open"].tap()
        let field = app.textFields["commands.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(text + "\n")
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    @MainActor private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    // MARK: 1 · Arpeggiator

    @MainActor func testArpeggiatorWritesTheChordsAsNotesToEditInThePianoRoll() {
        let app = launch()
        app.buttons["harmony.open"].tap()
        XCTAssertTrue(app.navigationBars["Harmony lab"].waitForExistence(timeout: 10))
        let entry = app.buttons["harmony.arpeggiate"]
        reveal(entry, in: app)
        entry.tap()
        XCTAssertTrue(app.navigationBars["Arpeggiator"].waitForExistence(timeout: 10))
        let count = any(app, "arpeggiator.count")
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        let sixteenths = count.label
        app.buttons["arpeggiator.rate.2"].tap()          // 1/8T
        XCTAssertTrue(eventually { count.label != sixteenths }, "Triplet eighths give a different number of notes")
        app.buttons["arpeggiator.octaves.1"].tap()
        shoot("55-arpeggiator")
        let play = app.buttons["arpeggiator.play"]
        reveal(play, in: app)
        play.tap()
        XCTAssertTrue(eventually(15) { play.label == "Stop" }, "The arpeggio plays before anything is written")
        play.tap()
        XCTAssertTrue(eventually { play.label == "Play" })
        let write = app.buttons["arpeggiator.apply"]
        reveal(write, in: app)
        write.tap()
        XCTAssertTrue(app.navigationBars["Piano roll"].waitForExistence(timeout: 10), "The notes open in the piano roll")
        XCTAssertTrue(app.buttons["Undo"].firstMatch.isEnabled)
        shoot("55-arpeggio-notes")
    }

    @MainActor func testKeyboardArpeggiatorHasNoteLengthAndArpeggiateToMIDI() {
        let app = launch("grid", ["--arp-pattern"])
        app.buttons["notes.open"].tap()
        XCTAssertTrue(app.navigationBars["Piano roll"].waitForExistence(timeout: 8))
        app.buttons["keyboard.open"].tap()
        let layout = app.buttons["keyboard.layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 10))
        layout.tap()
        XCTAssertTrue(app.buttons["Note length"].waitForExistence(timeout: 5), "Gate for the live arpeggio")
        let toMIDI = app.buttons["Arpeggiate to MIDI…"]
        XCTAssertTrue(toMIDI.exists)
        shoot("55-keyboard-arp-menu")
        toMIDI.tap()
        XCTAssertTrue(app.navigationBars["Arpeggiator"].waitForExistence(timeout: 10))
    }

    // MARK: 4 · As played or on the grid

    @MainActor func testATakeMovesFromAsPlayedToTheGridAndBackInOneUndo() {
        let app = launch("jam")
        let timing = app.buttons["jam.timing"]
        XCTAssertTrue(timing.waitForExistence(timeout: 10))
        timing.tap()
        let natural = app.buttons["As played"]
        XCTAssertTrue(natural.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["1/16T"].exists && app.buttons["1/32"].exists, "Triplets and thirty-seconds")
        natural.tap()
        XCTAssertTrue(eventually { timing.label.contains("As played") })
        app.buttons["Record drums"].tap()
        XCTAssertTrue(app.staticTexts["REC · DRUMS"].waitForExistence(timeout: 8))
        for _ in 0..<3 { app.buttons["Clap"].tap(); Thread.sleep(forTimeInterval: 0.37) }
        app.buttons["Finish drum take"].tap()
        let summary = any(app, "jam.take.summary.1")
        reveal(summary, in: app)
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("As played"), summary.label)
        let takeTiming = app.buttons["jam.take.timing.1"]
        XCTAssertTrue(takeTiming.exists)
        takeTiming.tap()
        let grid = app.buttons["1/16"]
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        grid.tap()
        XCTAssertTrue(eventually { summary.label.contains("1/16") }, summary.label)
        shoot("55-take-on-grid")
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(eventually { summary.label.contains("As played") }, "One Undo returns the take to how it was played")
    }

    // MARK: 2 · 3 · Sounds and kits

    @MainActor func testClassicDrumMachineBeatsAndFMBassesAreInTheBeatMachine() {
        let app = launch("jam")
        command("beat machine", in: app)
        XCTAssertTrue(app.navigationBars["Beat machine"].waitForExistence(timeout: 10))
        let house = app.buttons["beat.genre.house"]
        XCTAssertTrue(house.waitForExistence(timeout: 5))
        house.tap()
        let preset = app.buttons["beat.preset.house-909"]
        XCTAssertTrue(preset.waitForExistence(timeout: 5))
        preset.tap()
        XCTAssertTrue(eventually { app.staticTexts["beat.title"].label == "909 House" }, app.staticTexts["beat.title"].label)
        let kit = app.buttons["beat.kit.punch909"]
        reveal(kit, in: app)
        XCTAssertTrue(kit.exists, "The 909-style kit is offered")
        XCTAssertTrue(app.buttons["beat.kit.classic808"].exists && app.buttons["beat.kit.digital707"].exists && app.buttons["beat.kit.mini606"].exists)
        let fmBass = app.buttons["beat.sound.fm-solid-bass"]
        reveal(fmBass, in: app)
        XCTAssertTrue(fmBass.exists, "The preset's FM bass is offered")
        shoot("55-909-house")
    }

    // MARK: 5 · Listen to sketch

    @MainActor func testListenToSketchAnswersEvenWhileTheTempoFieldIsStillEditing() {
        let app = launch()
        app.buttons["assistant.open"].tap()
        let builder = app.buttons["Build a track"]
        XCTAssertTrue(builder.waitForExistence(timeout: 8))
        builder.tap()
        let tempo = app.textFields["Tempo"]
        XCTAssertTrue(tempo.waitForExistence(timeout: 8))
        tempo.tap()
        tempo.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        tempo.typeText("98")
        XCTAssertTrue(app.keyboards.firstMatch.exists, "The tempo field is still being edited")
        let preview = app.buttons["builder.preview"]
        if !preview.exists { app.swipeUp() }
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let idle = preview.label
        preview.tap()
        XCTAssertTrue(eventually(45) { preview.label != idle && !preview.label.contains("Preparing") }, "The tap starts the sketch: \(preview.label)")
        XCTAssertTrue(preview.label.contains("Stop"), preview.label)
        shoot("55-sketch-plays")
        preview.tap()
    }
}
