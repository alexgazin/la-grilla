import XCTest

/// Real UI and persistence regressions for the first physical-device report.
/// Output ordering and unavailable-audio fault probes remain Simulator software
/// observations; they do not establish physical routing or human speech quality.
final class DeviceRecoveryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor private func launch(screen: String = "grid", arguments: [String] = [], resetMicrophone: Bool = false) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        if resetMicrophone { app.resetAuthorizationStatus(for: .microphone) }
        app.launchArguments = ["--uitesting", "--runtime-trace", "--screen", screen,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + arguments
        app.launch()
        let initial = screen == "assistant" ? app.navigationBars["Assistant"] : app.buttons["perform.transport"]
        XCTAssertTrue(initial.waitForExistence(timeout: 15))
        return app
    }

    @MainActor func testOutputOnlyStartupAndPlaybackNavigationKeepTheSameGraph() throws {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .microphone)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var microphoneAlertObserved = false
        func rejectUnexpectedMicrophonePrompt(_ alert: XCUIElement) -> Bool {
            let text = ([alert.label] + alert.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
            guard text.localizedCaseInsensitiveContains("microphone") else { return false }
            microphoneAlertObserved = true
            for title in ["Don’t Allow", "Don't Allow"] where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        let monitor = addUIInterruptionMonitor(withDescription: "Output startup must not request microphone") {
            rejectUnexpectedMicrophonePrompt($0)
        }
        defer {
            app.terminate()
            app.resetAuthorizationStatus(for: .microphone)
            removeUIInterruptionMonitor(monitor)
        }
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--uitesting", "--runtime-trace", "--device-output-startup", "--screen", "grid",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let transport = app.buttons["perform.transport"]
        XCTAssertTrue(transport.waitForExistence(timeout: 15))
        for alert in springboard.alerts.allElementsBoundByIndex { _ = rejectUnexpectedMicrophonePrompt(alert) }
        wait(transport, timeout: 8) {
            let current = self.currentTrace(transport)
            return current.contains("engineRunning=true") && current.contains("inputPriming=outputOnly")
                && current.contains("inputPrimed=false") && current.contains("error=none")
        }
        XCTAssertFalse(microphoneAlertObserved)
        XCTAssertFalse(app.alerts["La Grilla"].exists)
        let kernel = try XCTUnwrap(number("kernel", in: currentTrace(transport)))
        let initialClock = try XCTUnwrap(number("actualClock", in: currentTrace(transport)))
        app.buttons["Play"].tap()
        wait(transport, timeout: 8) {
            let current = self.currentTrace(transport)
            return current.contains("actualPlaying=1") && (self.number("actualClock", in: current) ?? 0) > initialClock
        }
        var previousClock = try XCTUnwrap(number("actualClock", in: currentTrace(transport)))
        for tab in ["Jam", "Mixer", "Grid"] {
            app.buttons[tab].tap()
            wait(transport, timeout: 8) {
                let current = self.currentTrace(transport)
                return current.contains("engineRunning=true") && current.contains("actualPlaying=1")
                    && self.number("kernel", in: current) == kernel
                    && (self.number("actualClock", in: current) ?? 0) > previousClock
            }
            previousClock = try XCTUnwrap(number("actualClock", in: currentTrace(transport)))
            for alert in springboard.alerts.allElementsBoundByIndex { _ = rejectUnexpectedMicrophonePrompt(alert) }
        }
        XCTAssertFalse(microphoneAlertObserved)
        XCTAssertTrue(currentTrace(transport).contains("inputPrimed=false"))
        keepReport(currentTrace(transport), name: "DeviceRecovery-output-only-software-trace")
        keepScreenshot("DeviceRecovery-output-only-grid-playing")
        app.buttons["Stop"].tap()
        wait(transport) { self.currentTrace(transport).contains("actualPlaying=0") }
    }

    @MainActor func testDictationAuthorizationCallbackDoesNotCrashAndTypedCommandsStillWork() {
        let app = launch(screen: "assistant", resetMicrophone: true)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        var permissionPrompts: [String] = []
        func denyCapturePrompt(_ alert: XCUIElement) -> Bool {
            let text = ([alert.label] + alert.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
            guard text.localizedCaseInsensitiveContains("speech") || text.localizedCaseInsensitiveContains("microphone") else { return false }
            for title in ["Don’t Allow", "Don't Allow"] where alert.buttons[title].exists {
                permissionPrompts.append(text)
                alert.buttons[title].tap()
                return true
            }
            return false
        }
        let monitor = addUIInterruptionMonitor(withDescription: "Actual dictation authorization denial") {
            denyCapturePrompt($0)
        }
        defer {
            app.terminate()
            app.resetAuthorizationStatus(for: .microphone)
            removeUIInterruptionMonitor(monitor)
        }
        let dictate = app.buttons["assistant.dictate"]
        revealFully(dictate, in: app)
        dictate.tap()
        let error = app.staticTexts["assistant.dictation-error"]
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            for alert in springboard.alerts.allElementsBoundByIndex { _ = denyCapturePrompt(alert) }
            if error.exists || app.state == .notRunning { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        // Do not activate/relaunch here: a crashed process must fail this check.
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(error.exists, "The real permission/availability completion must leave a recoverable explanation")
        let permittedErrors = [
            "Dictation permission was denied. You can still type a command.",
            "Microphone access was denied. You can still type a command.",
            "On-device dictation is unavailable for this language. Type a command."
        ]
        XCTAssertTrue(permittedErrors.contains(error.label), error.label)
        keepReport("Actual system completion: \(error.label)\nObserved permission prompts: \(permissionPrompts)",
                   name: "DeviceRecovery-dictation-authorization-observation")
        let input = app.textViews["assistant.input"]
        revealFully(input, in: app, upward: false)
        XCTAssertTrue(input.isEnabled)
        replaceText(input, with: "tempo 108")
        let generate = app.buttons["assistant.generate"]
        revealFully(generate, in: app)
        XCTAssertTrue(generate.isEnabled)
        generate.tap()
        let apply = app.buttons["assistant.apply"]
        revealFully(apply, in: app)
        XCTAssertTrue(app.staticTexts["108 BPM"].exists)
        keepScreenshot("DeviceRecovery-typed-command-after-dictation")
        apply.tap()
        wait(app.navigationBars["Assistant"]) { !app.navigationBars["Assistant"].exists }
        let tempo = app.staticTexts["studio.tempo"]
        XCTAssertTrue(tempo.waitForExistence(timeout: 5))
        XCTAssertEqual(tempo.label, "108 BPM")
        XCTAssertTrue(app.buttons["Undo"].isEnabled)
        app.buttons["Undo"].tap()
        XCTAssertEqual(tempo.label, "120 BPM")
    }

    @MainActor func testUnavailableAudioDoesNotBlockProjectCreateSaveReopenAndMIDIExport() {
        let storeID = UUID().uuidString
        let app = launch(arguments: ["--audio-unavailable", "--project-store-id", storeID])
        let transport = app.buttons["perform.transport"]
        XCTAssertTrue(currentTrace(transport).contains("qaAudioUnavailable=true"))
        XCTAssertFalse(app.alerts["La Grilla"].exists, "Audio failure must not cover the usable document editor")
        let audioError = app.staticTexts["Audio could not start. Check the audio route and retry."]
        XCTAssertTrue(audioError.exists)
        app.buttons["Projects"].tap()
        XCTAssertTrue(app.buttons["project.new"].waitForExistence(timeout: 5))
        app.buttons["project.new"].tap()
        // The name section sits below "Track in a minute" and "Start with a beat" (build 54).
        XCTAssertTrue(app.navigationBars["New project"].waitForExistence(timeout: 5))
        let name = app.textFields["project.name"]
        for _ in 0..<5 where !(name.exists && name.isHittable) { app.swipeUp() }
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Offline recovery")
        app.buttons["project.create"].tap()
        wait(app.navigationBars["New project"]) { !app.navigationBars["New project"].exists }
        XCTAssertTrue(app.staticTexts["Offline recovery"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["project.create-error"].exists)
        let chord = firstChord(in: app)
        wait(chord) { chord.exists && chord.isHittable }
        chord.tap()
        let symbol = app.textFields["chord.symbol"]
        XCTAssertTrue(symbol.waitForExistence(timeout: 5))
        replaceText(symbol, with: "Cmaj7")
        app.buttons["chord.set-symbol"].tap()
        XCTAssertEqual(symbol.value as? String, "Cmaj7")
        app.buttons["Apply"].tap()
        wait(app.navigationBars["Edit chord"]) { !app.navigationBars["Edit chord"].exists }
        wait(chord) { chord.exists && chord.label.contains("Cmaj7") }
        let saved = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Saved on this iPhone'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 8))
        XCTAssertFalse(app.alerts["La Grilla"].exists)
        keepScreenshot("DeviceRecovery-injected-audio-failure-edited-project")
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Offline recovery"].exists)
        XCTAssertTrue(currentTrace(transport).contains("qaAudioUnavailable=true"))
        wait(chord) { chord.exists && chord.isHittable }
        chord.tap()
        XCTAssertTrue(symbol.waitForExistence(timeout: 5))
        XCTAssertEqual(symbol.value as? String, "Cmaj7", "A fresh Session must load the actual saved project and chord")
        app.buttons["Cancel"].tap()
        wait(app.navigationBars["Edit chord"]) { !app.navigationBars["Edit chord"].exists }
        app.buttons["export.open"].tap()
        XCTAssertTrue(app.buttons["format.midi"].waitForExistence(timeout: 5))
        app.buttons["export.confirm"].tap()
        let share = app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout: 15) || app.buttons["Copy"].exists
                      || app.buttons["Save to Files"].exists || app.staticTexts["Save to Files"].exists)
        XCTAssertFalse(app.staticTexts["export.error"].exists)
        keepReport("Fault injected: --audio-unavailable\nReal store namespace: \(storeID)\nFresh-session project: Offline recovery\nReopened chord: Cmaj7\nSystem MIDI share offered: true\nPhysical audio unavailable acceptance: false",
                   name: "DeviceRecovery-injected-audio-failure-persistence")
        keepScreenshot("DeviceRecovery-injected-audio-failure-midi-share")
    }

    @MainActor func testUnavailableAIReviewsLocalHarmonyAndAppliesUndo() throws {
        // This journey opens the chord editor twice after a real Apply and Undo.
        // On a loaded Simulator the original two minutes expired during Apply.
        executionTimeAllowance = 180
        let app = launch(arguments: ["--device-output-startup"])
        let chord = firstChord(in: app)
        XCTAssertTrue(chord.exists || chord.waitForExistence(timeout: 5))
        let initial = try jazzPhase(app)
        let original = try XCTUnwrap(initial.firstChord?.label)
        XCTAssertEqual(initial.undo?.isEnabled, false)
        app.buttons["assistant.open"].tap()
        XCTAssertTrue(app.navigationBars["Assistant"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["assistant.use-commands"].exists, "This case requires the Simulator's actual unavailable model")
        app.buttons["On-device AI"].tap()
        chooseExample("assistant.example.jazzify", in: app)
        let generate = app.buttons["assistant.generate"]
        revealJazzControl(generate, identifier: "assistant.generate", in: app)
        generate.tap()

        let fallback = app.staticTexts["assistant.local-fallback"]
        revealJazzControl(fallback, identifier: "assistant.local-fallback", type: .staticText, in: app)
        let reviewed = try jazzPhase(app)
        XCTAssertEqual(reviewed.element("assistant.local-fallback", type: .staticText)?.label, "Reviewed with Commands because on-device AI is unavailable.")
        XCTAssertTrue(reviewed.hasText("LOCAL"))
        XCTAssertFalse(reviewed.hasText("ON-DEVICE AI"))
        let before = app.staticTexts["assistant.harmony.before.0.0"]
        revealJazzControl(before, identifier: "assistant.harmony.before.0.0", type: .staticText, in: app)
        let proposed = try jazzPhase(app)
        XCTAssertEqual(proposed.element("assistant.harmony.before.0.0", type: .staticText)?.label, "C")
        XCTAssertEqual(proposed.element("assistant.harmony.after.0.0", type: .staticText)?.label, "Cmaj9")
        keepScreenshot("DeviceRecovery-unavailable-ai-local-harmony-review")
        let apply = app.buttons["assistant.apply"]
        revealJazzControl(apply, identifier: "assistant.apply", in: app)
        apply.tap()
        wait(app.navigationBars["Assistant"]) { !app.navigationBars["Assistant"].exists }
        wait(chord) { chord.isHittable }
        let undo = app.buttons["Undo"]
        XCTAssertTrue(undo.isEnabled)
        chord.tap()
        let symbol = app.textFields["chord.symbol"]
        XCTAssertTrue(symbol.waitForExistence(timeout: 5))
        XCTAssertEqual(symbol.value as? String, "Cmaj9")
        app.buttons["Cancel"].tap()
        wait(app.navigationBars["Edit chord"]) { !app.navigationBars["Edit chord"].exists }
        undo.tap()
        let restored = try jazzPhase(app)
        XCTAssertEqual(restored.undo?.isEnabled, false)
        XCTAssertEqual(restored.firstChord?.label, original)
        chord.tap()
        XCTAssertTrue(symbol.waitForExistence(timeout: 5))
        XCTAssertEqual(symbol.value as? String, "C")
    }

    @MainActor func testAutomaticOpensOfflineBuilderForJazzHipHopDescription() {
        let app = launch(screen: "assistant")
        XCTAssertTrue(app.buttons["assistant.use-commands"].waitForExistence(timeout: 8))
        let input = app.textViews["assistant.input"]
        input.tap()
        input.typeText("Create jazz hip hop old school")
        let review = app.buttons["assistant.generate"]
        revealFully(review, in: app)
        review.tap()
        XCTAssertTrue(app.navigationBars["Build a track"].waitForExistence(timeout: 8))
        let chords = app.textFields["builder.chords"]
        for _ in 0..<6 where !chords.isHittable { app.swipeUp() }
        XCTAssertEqual(chords.value as? String, "Em7b5 A7 Dm7 Dm7")
    }

    @MainActor func testUnavailableAIFreeTextShowsReasonAndCommandsKeepsInput() {
        let app = launch(screen: "assistant")
        XCTAssertTrue(app.buttons["assistant.use-commands"].exists, "This case requires the Simulator's actual unavailable model")
        chooseExample("assistant.example.ai-song", in: app)
        let input = app.textViews["assistant.input"]
        revealFully(input, in: app, upward: false)
        let originalText = input.value as? String
        XCTAssertFalse(originalText?.isEmpty ?? true)
        let status = app.staticTexts["assistant.ai-status"]
        let unavailableReason = status.label
        let generate = app.buttons["assistant.generate"]
        revealFully(generate, in: app)
        generate.tap()
        let error = app.staticTexts["assistant.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertEqual(error.label, unavailableReason)
        XCTAssertFalse(app.buttons["assistant.apply"].exists)
        XCTAssertFalse(app.staticTexts["assistant.local-fallback"].exists)
        let useCommands = app.buttons["assistant.use-commands"]
        revealFully(useCommands, in: app, upward: false)
        useCommands.tap()
        XCTAssertEqual(input.value as? String, originalText)
        XCTAssertTrue(app.buttons["Commands"].isSelected)
        XCTAssertEqual(status.label, "Commands work without Apple Intelligence.")
        XCTAssertFalse(app.buttons["assistant.use-commands"].exists)
        XCTAssertFalse(app.staticTexts["assistant.error"].exists)
        keepScreenshot("DeviceRecovery-unavailable-ai-use-commands-preserves-input")
        app.buttons["Cancel"].tap()
        wait(app.navigationBars["Assistant"]) { !app.navigationBars["Assistant"].exists }
        XCTAssertEqual(app.staticTexts["studio.tempo"].label, "120 BPM")
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
    }

    @MainActor private func firstChord(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'grid.chord.'")).firstMatch
    }

    @MainActor private func currentTrace(_ transport: XCUIElement) -> String {
        (transport.value as? String ?? "").components(separatedBy: "\n").first ?? ""
    }

    private func number(_ key: String, in text: String) -> UInt64? {
        guard let regex = try? NSRegularExpression(pattern: "\\b" + NSRegularExpression.escapedPattern(for: key) + "=([0-9]+)"),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return UInt64(text[range])
    }

    @MainActor private func chooseExample(_ identifier: String, in app: XCUIApplication) {
        let examples = app.buttons["assistant.examples"]
        revealFully(examples, in: app, upward: false)
        examples.tap()
        let example = app.buttons[identifier]
        XCTAssertTrue(example.waitForExistence(timeout: 5))
        if !example.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(example.isHittable)
        example.tap()
        wait(app.navigationBars["Examples"]) { !app.navigationBars["Examples"].exists }
    }

    @MainActor private func replaceText(_ field: XCUIElement, with text: String) {
        field.tap()
        let old = field.value as? String ?? ""
        if !old.isEmpty { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text)
    }

    @MainActor private func revealFully(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        let scroll = app.scrollViews["assistant.review-scroll"]
        for _ in 0..<10 {
            let viewport = scroll.frame.intersection(app.frame)
            let frame = element.frame
            if element.isHittable, frame.minY >= viewport.minY + 8, frame.maxY <= viewport.maxY - 8 { return }
            if upward { scroll.swipeUp() } else { scroll.swipeDown() }
        }
        XCTFail("The actual Assistant control was not fully visible: \(element.identifier)")
    }

    @MainActor private func wait(_ element: XCUIElement, timeout: TimeInterval = 5, condition: () -> Bool) {
        // Evaluate UI state on this actor; do not pass its closure through an
        // Objective-C predicate callback with an unspecified executor contract.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("Expected UI state did not settle within \(timeout) seconds for \(element)")
    }

    private func keepReport(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation,
                                       uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
