import XCTest

/// I29 arpeggio patterns, I31 instrument from a sound, I32 voice treatment, I33 reverb spaces,
/// I34 pad layers, I37 automation, I54 MPE, U19 why this / another way, U26 save card and
/// U30 one order in every ⋯ menu.
final class RemainingIdeasUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 300 }

    @MainActor private func launch(_ screen: String = "grid", _ extra: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--device-output-startup", "--screen", screen, "--project-store-id", UUID().uuidString,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
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

    @MainActor private func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    /// A picker inside a menu is shown inline or as a submenu, depending on the system.
    @MainActor private func pick(_ option: String, from picker: String, in app: XCUIApplication) {
        let choice = app.buttons[option].firstMatch
        if !choice.waitForExistence(timeout: 3) {
            let submenu = app.buttons[picker].firstMatch
            XCTAssertTrue(submenu.waitForExistence(timeout: 5), "\(picker) in the menu")
            submenu.tap()
        }
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "\(option) in \(picker)")
        choice.tap()
    }

    @MainActor private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    // MARK: I29 · I54

    @MainActor func testArpPatternEditorTogglesStepsAndPlaysItsPattern() {
        // The arpeggiator starts at 1/16 with "My pattern" (UI-test fixture).
        let app = launch("grid", ["--arp-pattern"])
        let notes = app.buttons["notes.open"]
        XCTAssertTrue(notes.waitForExistence(timeout: 15))
        notes.tap()
        XCTAssertTrue(app.navigationBars["Piano roll"].waitForExistence(timeout: 8))
        app.buttons["keyboard.open"].tap()
        let layout = app.buttons["keyboard.layout"]
        XCTAssertTrue(layout.waitForExistence(timeout: 10))
        layout.tap()
        // I54: the MPE switch sits in the same menu.
        XCTAssertTrue(app.buttons["keyboard.mpe"].waitForExistence(timeout: 5) || app.switches["keyboard.mpe"].exists)
        XCTAssertTrue(app.buttons["Edit pattern…"].waitForExistence(timeout: 5))
        app.buttons["Edit pattern…"].tap()
        XCTAssertTrue(app.navigationBars["Arpeggio pattern"].waitForExistence(timeout: 8))
        let encoded = app.staticTexts["arp.encoded"]
        let before = encoded.label
        let cell = app.buttons["arp.step.1.0"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.tap()
        XCTAssertTrue(eventually { encoded.label != before }, "Tapping a cell changes the pattern")
        shoot("I29-arp-pattern")
        app.buttons["arp.done"].tap()
        XCTAssertTrue(eventually { !app.navigationBars["Arpeggio pattern"].exists })
    }

    // MARK: I31 · I34 · I32

    @MainActor func testSamplerAndPadLayersOpenFromTheSoundScreens() {
        let app = launch("jam")
        let drums = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sound.track.drums.'")).firstMatch
        XCTAssertTrue(drums.waitForExistence(timeout: 15))
        drums.tap()
        app.buttons["sound.samples"].tap()
        XCTAssertTrue(app.navigationBars["Pad samples"].waitForExistence(timeout: 10))
        // The pocket kit puts editable samples on the pads.
        app.buttons["pad-samples.pocket-kit"].tap()
        // I32: the pad editor offers the voice treatment.
        let edit = app.buttons["pad-samples.edit.0"]
        XCTAssertTrue(edit.waitForExistence(timeout: 15))
        edit.tap()
        let voice = app.buttons["pad-editor.voice"]
        for _ in 0..<6 where !voice.exists || !voice.isHittable { app.swipeUp() }
        XCTAssertTrue(voice.exists, "Voice treatment in the pad editor")
        app.navigationBars.buttons["Cancel"].firstMatch.tap()
        // I34: layers on a pad from the sample library.
        let library = app.buttons["pad-samples.library.0"]
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        library.tap()
        XCTAssertTrue(app.navigationBars["Sample library"].waitForExistence(timeout: 10))
        let layers = app.buttons["pad-library.layers"]
        for _ in 0..<6 where !layers.isHittable { app.swipeUp() }
        layers.tap()
        XCTAssertTrue(app.navigationBars["Layers on this pad"].waitForExistence(timeout: 8))
        XCTAssertTrue(any(app, "layers.mode").exists)
        XCTAssertFalse(app.buttons["layers.apply"].isEnabled, "Two sounds are needed first")
        shoot("I34-layers")
    }

    @MainActor func testInstrumentFromASoundWaitsForASound() {
        let app = launch("mixer")
        let harmony = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sound.track.harmony.'")).firstMatch
        XCTAssertTrue(harmony.waitForExistence(timeout: 15))
        harmony.tap()
        app.buttons["sound.banks"].tap()
        let sampler = app.buttons["sound-bank.sampler"]
        XCTAssertTrue(sampler.waitForExistence(timeout: 15))
        sampler.tap()
        XCTAssertTrue(app.navigationBars["Instrument from a sound"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["sampler.record"].exists)
        XCTAssertTrue(app.buttons["sampler.import"].exists)
        XCTAssertFalse(app.buttons["sampler.apply"].isEnabled, "Nothing to play until a sound is recorded or imported")
        shoot("I31-sampler")
    }

    // MARK: I33 · I37 · U30

    @MainActor func testMixerSpacesAutomationAndMenuOrder() {
        let app = launch("mixer")
        // I33: the master menu chooses the reverb space.
        let master = app.buttons["mixer.master-menu"]
        XCTAssertTrue(master.waitForExistence(timeout: 15))
        master.tap()
        pick("Hall", from: "Reverb space", in: app)
        XCTAssertTrue(app.buttons["Undo"].firstMatch.isEnabled, "Choosing a space is an undoable edit")
        // U30: Listen · Rename · … · Colour in that order in a track menu.
        let menu = app.buttons["mixer.track-menu.drums"]
        menu.tap()
        let listen = app.buttons["mixer.track.listen"], rename = app.buttons["mixer.track.rename"]
        XCTAssertTrue(listen.waitForExistence(timeout: 5))
        XCTAssertTrue(rename.exists)
        XCTAssertLessThan(listen.frame.minY, rename.frame.minY, "Listen comes first, then Rename")
        shoot("U30-track-menu")
        // I37: the track's automation editor.
        let automation = app.buttons["Automation…"].firstMatch
        XCTAssertTrue(automation.waitForExistence(timeout: 5))
        automation.tap()
        XCTAssertTrue(app.navigationBars["Automation"].waitForExistence(timeout: 8))
        XCTAssertTrue(any(app, "automation.chart").exists)
        XCTAssertTrue(any(app, "automation.parameter").exists)
        app.navigationBars["Automation"].buttons["Done"].tap()
        // The record switch shows its state.
        let write = app.buttons["mixer.automation"]
        XCTAssertTrue(write.waitForExistence(timeout: 8))
        write.tap()
        XCTAssertTrue(eventually { write.isSelected }, "Writing automation is on")
        write.tap()
        XCTAssertTrue(eventually { !write.isSelected })
    }

    // MARK: U26

    @MainActor func testSaveCardSavesAndOpensVersions() {
        let app = launch()
        let status = app.buttons["studio.save-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        status.tap()
        let now = app.buttons["save.now"]
        XCTAssertTrue(now.waitForExistence(timeout: 8))
        let status = app.staticTexts.matching(identifier: "save.status").firstMatch
        XCTAssertTrue(status.label.contains("Saved"), status.label)
        XCTAssertFalse(now.isEnabled, "Nothing to save on a freshly opened song")
        XCTAssertFalse(app.buttons["save.back"].isEnabled, "Nothing changed since opening")
        XCTAssertTrue(app.buttons["save.copy"].exists)
        shoot("U26-save-card")
        app.buttons["save.versions"].tap()
        XCTAssertTrue(app.navigationBars["Song versions"].waitForExistence(timeout: 8))
    }

    // MARK: U19

    @MainActor func testAssistantExplainsWhyAndOffersAnotherWay() {
        let app = launch()
        app.buttons["assistant.open"].tap()
        XCTAssertTrue(app.navigationBars["Assistant"].waitForExistence(timeout: 10))
        app.buttons["Examples"].tap()
        let example = app.buttons["assistant.example.jazzify"]
        XCTAssertTrue(example.waitForExistence(timeout: 8))
        example.tap()
        XCTAssertTrue(eventually { !example.exists })
        let scroll = app.scrollViews["assistant.review-scroll"]
        let generate = app.buttons["assistant.generate"]
        for _ in 0..<8 where !generate.isHittable { scroll.swipeUp() }
        generate.tap()
        XCTAssertTrue(any(app, "assistant.engine-badge").waitForExistence(timeout: 15))
        let reason = any(app, "assistant.why.0")
        let another = app.buttons["assistant.another"]
        for _ in 0..<10 where !another.isHittable { scroll.swipeUp() }
        XCTAssertTrue(reason.exists, "Why this lists its reasons")
        let first = reason.label
        shoot("U19-why")
        another.tap()
        XCTAssertTrue(eventually { any(app, "assistant.why.0").exists && any(app, "assistant.why.0").label != first },
                      "Another way gives a different answer: \(first)")
    }
}
