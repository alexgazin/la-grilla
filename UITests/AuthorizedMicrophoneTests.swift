import XCTest

/// These tests use actual iOS consent and the configured host HAL. They never
/// inject PCM, recognition results, authorization decisions or proposals.
final class AuthorizedMicrophoneTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor func testOutputOnlyFirstConsentCapturesActualCAFAndRetainsKernel() throws {
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.terminate()
        app.resetAuthorizationStatus(for: .microphone)
        var permitRequest = false
        var earlyRequest = false
        var grantedPrompt = false
        func handle(_ alert: XCUIElement) -> Bool {
            let description = alertDescription(alert)
            guard description.localizedCaseInsensitiveContains("microphone") else { return false }
            if !permitRequest {
                earlyRequest = true
                return tapFirst(["Don’t Allow", "Don't Allow"], in: alert)
            }
            grantedPrompt = true
            return tapFirst(["Allow", "OK"], in: alert)
        }
        let monitor = addUIInterruptionMonitor(withDescription: "Real first microphone consent after output-only playback") { handle($0) }
        defer {
            app.terminate()
            app.resetAuthorizationStatus(for: .microphone)
            removeUIInterruptionMonitor(monitor)
        }
        launch(app, arguments: ["--audio-runtime-qa", "--audio-runtime-output-privacy", "--device-output-startup"])
        let result = app.staticTexts["audio.runtime.result"]
        waitForResult(result, app: app, springboard: springboard, states: ["READY", "FAIL"], timeout: 20, handle: handle)
        let privacyText = app.staticTexts["audio.runtime.details"].label
        keep(privacyText, name: "AuthorizedInput-output-only-before-consent")
        XCTAssertFalse(earlyRequest)
        XCTAssertEqual(result.label, "READY", privacyText)
        let privacy = try object(privacyText)
        XCTAssertEqual(privacy["permissionBefore"] as? String, "undetermined")
        XCTAssertEqual(privacy["permissionAfter"] as? String, "undetermined")
        XCTAssertEqual(privacy["inputPriming"] as? String, "outputOnly")
        XCTAssertEqual(privacy["inputPrimedAtStartup"] as? Bool, false)
        XCTAssertEqual(privacy["inputConfigured"] as? Bool, false)
        XCTAssertEqual(privacy["inputTransitionCount"] as? Int, 0)
        XCTAssertEqual(privacy["softwareOutputPrivacyVerified"] as? Bool, true)
        XCTAssertEqual(privacy["referenceEngineKernelRetained"] as? Bool, true)
        XCTAssertEqual(privacy["outputEngineRunning"] as? Bool, true)
        XCTAssertGreaterThan(privacy["outputClockFramesAdvanced"] as? Int ?? 0, 0)
        XCTAssertGreaterThan(privacy["observedOutputPeak"] as? Double ?? 0, 0.0001)
        let process = try XCTUnwrap(privacy["processIdentifier"] as? Int)
        let start = app.buttons["audio.runtime.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        XCTAssertTrue(start.isHittable)
        permitRequest = true
        start.tap()
        waitForResult(result, app: app, springboard: springboard, states: ["PASS", "FAIL", "UNAVAILABLE"], timeout: 35, handle: handle)
        let capturedText = app.staticTexts["audio.runtime.details"].label
        keep(capturedText, name: "AuthorizedInput-output-only-real-CAF-first-transition")
        XCTAssertFalse(earlyRequest)
        XCTAssertTrue(grantedPrompt, "The real iOS recording prompt must be observed and accepted after Start")
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertEqual(result.label, "PASS", capturedText)
        let captured = try object(capturedText)
        XCTAssertEqual(captured["inputPriming"] as? String, "outputOnly")
        XCTAssertEqual(captured["inputPrimedAtStartup"] as? Bool, false)
        XCTAssertEqual(captured["inputConfigured"] as? Bool, true)
        XCTAssertEqual(captured["inputTransitionCount"] as? Int, 1)
        let transition = try XCTUnwrap(captured["inputTransitionMilliseconds"] as? Double)
        XCTAssertTrue(transition.isFinite)
        XCTAssertGreaterThan(transition, 0)
        XCTAssertEqual(captured["permissionBeforeCapture"] as? String, "undetermined")
        XCTAssertEqual(captured["permissionAfterCapture"] as? String, "granted")
        XCTAssertEqual(captured["physicalDropoutAbsenceVerified"] as? Bool, false)
        for key in ["sameEngineAndKernel", "backingClockAdvanced", "storedSourceMatches", "storedProjectReopened", "oneUndoRestoresBaseline", "redoRestoresExactSourceAndNotes", "sourceUnchangedAfterReview"] {
            XCTAssertEqual(captured[key] as? Bool, true, key)
        }
        let cold = try XCTUnwrap(captured["coldFirstUse"] as? [String: Any])
        XCTAssertEqual(cold["sameProcess"] as? Bool, true)
        XCTAssertEqual(cold["processIdentifier"] as? Int, process)
        XCTAssertEqual(cold["phaseOneEngineKernelRetained"] as? Bool, true)
        XCTAssertEqual(cold["referenceReusedWithoutPreparation"] as? Bool, true)
        let source = try XCTUnwrap(captured["source"] as? [String: Any])
        XCTAssertEqual(source["origin"] as? String, "microphone")
        XCTAssertEqual(source["sampleRate"] as? Double, 48000)
        XCTAssertEqual((source["sha256"] as? String)?.count, 64)
        XCTAssertGreaterThan(captured["sourceFrames"] as? Int ?? 0, 0)
        XCTAssertLessThanOrEqual(captured["sourceFrames"] as? Int ?? .max, 144000)
        XCTAssertGreaterThan(captured["sourcePeak"] as? Double ?? 0, 0.001)
        let detected = try XCTUnwrap(captured["detectedPitches"] as? [Int])
        let reviewed = try XCTUnwrap(captured["reviewedPitches"] as? [Int])
        XCTAssertFalse(detected.isEmpty)
        XCTAssertEqual(detected.count, reviewed.count)
        XCTAssertNotEqual(detected.first, reviewed.first)
        let timing = try XCTUnwrap(captured["outputHostTiming"] as? [String: Any])
        let baseline = try XCTUnwrap(captured["outputHostTimingBaseline"] as? [String: Any])
        XCTAssertEqual(timing["epoch"] as? Int, baseline["epoch"] as? Int)
        XCTAssertGreaterThan(timing["callbacks"] as? Int ?? 0, baseline["callbacks"] as? Int ?? .max)
        XCTAssertNotNil(timing["maxExcessNanoseconds"])
        // The first input activation deliberately pauses I/O. Retained musical
        // state and measured callback gaps do not imply uninterrupted speakers.
        XCTAssertLessThan(captured["maximumPhaseErrorTicks"] as? Double ?? .infinity, 128)
    }

    @MainActor func testGrantedSpeechCallbackAndOutputOnlyAssistantRemainUsable() throws {
        let app = XCUIApplication()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        app.terminate()
        app.resetAuthorizationStatus(for: .microphone)
        var prompts: [String] = []
        func allow(_ alert: XCUIElement) -> Bool {
            let description = alertDescription(alert)
            guard description.localizedCaseInsensitiveContains("microphone") || description.localizedCaseInsensitiveContains("speech") else { return false }
            prompts.append(description)
            return tapFirst(["Allow", "OK"], in: alert)
        }
        let monitor = addUIInterruptionMonitor(withDescription: "Actual granted microphone and Speech consent") { allow($0) }
        defer {
            app.terminate()
            app.resetAuthorizationStatus(for: .microphone)
            removeUIInterruptionMonitor(monitor)
        }
        // Establish real microphone consent and actual finite HAL PCM first.
        // Speech availability must not let this test bypass microphone input.
        launch(app, arguments: ["--audio-runtime-qa", "--audio-runtime-microphone"])
        let result = app.staticTexts["audio.runtime.result"]
        waitForResult(result, app: app, springboard: springboard, states: ["READY", "FAIL"], timeout: 15, handle: allow)
        XCTAssertEqual(result.label, "READY")
        app.buttons["audio.runtime.start"].tap()
        waitForResult(result, app: app, springboard: springboard, states: ["PASS", "FAIL", "UNAVAILABLE"], timeout: 35, handle: allow)
        let pcmText = app.staticTexts["audio.runtime.details"].label
        keep(pcmText, name: "AuthorizedInput-real-microphone-consent-before-Speech")
        XCTAssertEqual(result.label, "PASS", pcmText)
        let pcm = try object(pcmText)
        XCTAssertGreaterThan(pcm["frames"] as? Int ?? 0, 0)
        XCTAssertEqual(pcm["outputKernelRetained"] as? Bool, true)
        XCTAssertTrue(prompts.contains { $0.localizedCaseInsensitiveContains("microphone") })

        // New process, genuine persisted TCC grant, fresh output-only graph.
        // Kernel identity below is compared only within this second process.
        app.terminate()
        launch(app, arguments: ["--screen", "grid", "--device-output-startup"])
        let transport = app.buttons["perform.transport"]
        XCTAssertTrue(transport.waitForExistence(timeout: 15))
        wait(transport, timeout: 8) { self.trace(transport).contains("engineRunning=true") }
        XCTAssertTrue(trace(transport).contains("inputPriming=outputOnly"))
        XCTAssertTrue(trace(transport).contains("inputPrimed=false"))
        XCTAssertTrue(trace(transport).contains("inputConfigured=false"))
        XCTAssertTrue(trace(transport).contains("error=none"))
        let kernel = try XCTUnwrap(traceValue("kernel", in: trace(transport)))
        let project = try XCTUnwrap(traceValue("project", in: trace(transport)))
        let revision = try XCTUnwrap(traceValue("revision", in: trace(transport)))
        let firstClock = try XCTUnwrap(UInt64(traceValue("actualClock", in: trace(transport)) ?? ""))
        app.buttons["Play"].tap()
        wait(transport, timeout: 8) { self.trace(transport).contains("actualPlaying=1") }
        app.buttons["assistant.open"].tap()
        XCTAssertTrue(app.navigationBars["Assistant"].waitForExistence(timeout: 5))
        let english = app.buttons["assistant.language.en"]
        reveal(english, in: app)
        english.tap()
        let dictate = app.buttons["assistant.dictate"]
        reveal(dictate, in: app)
        dictate.tap()
        let deadline = Date().addingTimeInterval(20)
        var diagnostic: [String: Any] = [:]
        while Date() < deadline {
            for alert in springboard.alerts.allElementsBoundByIndex { _ = allow(alert) }
            if app.state == .notRunning { break }
            if let value = dictate.value as? String, let current = try? object(value) {
                diagnostic = current
                let settled = current["requesting"] as? Bool == false
                if settled && (current["everStartedCapture"] as? Bool == true || app.staticTexts["assistant.dictation-error"].exists) { break }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(app.state, .runningForeground, "Do not relaunch a process that crashed at the granted authorization callback")
        XCTAssertEqual(diagnostic["speechAuthorization"] as? String, "authorized")
        XCTAssertEqual(diagnostic["microphonePermission"] as? String, "granted")
        XCTAssertTrue(prompts.contains { $0.localizedCaseInsensitiveContains("speech") }, "Run this consent regression on a fresh Simulator so the actual Speech grant is observed")
        if diagnostic["everStartedCapture"] as? Bool == true {
            XCTAssertEqual(diagnostic["speechAvailable"] as? Bool, true)
            XCTAssertEqual(diagnostic["supportsOnDeviceSpeech"] as? Bool, true)
            wait(dictate, timeout: 8) {
                guard let value = dictate.value as? String, let current = try? self.object(value) else { return false }
                return (current["receivedFrames"] as? Int ?? 0) > 0
            }
            diagnostic = try object(try XCTUnwrap(dictate.value as? String))
            XCTAssertGreaterThan(diagnostic["receivedFrames"] as? Int ?? 0, 0)
            if diagnostic["recording"] as? Bool == true { dictate.tap() }
            wait(dictate, timeout: 5) {
                guard let value = dictate.value as? String, let current = try? self.object(value) else { return false }
                return current["requesting"] as? Bool == false && current["finalizing"] as? Bool == false && current["recording"] as? Bool == false
            }
            diagnostic = try object(try XCTUnwrap(dictate.value as? String))
        } else {
            XCTAssertEqual(diagnostic["everStartedCapture"] as? Bool, false)
            XCTAssertEqual(app.staticTexts["assistant.dictation-error"].label, "On-device dictation is unavailable for this language. Type a command.")
            XCTAssertEqual(diagnostic["receivedFrames"] as? Int, 0)
            XCTAssertFalse(diagnostic["speechAvailable"] as? Bool == true && diagnostic["supportsOnDeviceSpeech"] as? Bool == true)
        }
        keep(try json(["diagnostic": diagnostic, "observedSystemPrompts": prompts, "successfulTranscriptionClaimed": false]), name: "AuthorizedInput-real-granted-Speech-completion")
        app.buttons["Cancel"].tap()
        wait(app.navigationBars["Assistant"], timeout: 5) { !app.navigationBars["Assistant"].exists }
        XCTAssertTrue(transport.waitForExistence(timeout: 5))
        wait(transport, timeout: 8) { self.trace(transport).contains("engineRunning=true") }
        let after = trace(transport)
        keep(after, name: "AuthorizedInput-output-only-after-Speech")
        XCTAssertEqual(traceValue("kernel", in: after), kernel)
        XCTAssertEqual(traceValue("project", in: after), project)
        XCTAssertEqual(traceValue("revision", in: after), revision)
        XCTAssertTrue(after.contains("actualPlaying=1"))
        XCTAssertTrue(after.contains("error=none"))
        if diagnostic["everStartedCapture"] as? Bool == true {
            XCTAssertEqual(traceValue("inputTransitionCount", in: after), "1")
            XCTAssertEqual(traceValue("inputConfigured", in: after), "true")
        } else {
            XCTAssertEqual(traceValue("inputTransitionCount", in: after), "0")
            XCTAssertEqual(traceValue("inputConfigured", in: after), "false")
        }
        XCTAssertGreaterThan(UInt64(traceValue("actualClock", in: after) ?? "") ?? 0, firstClock)
        XCTAssertFalse(app.alerts["La Grilla"].exists)
        app.buttons["assistant.open"].tap()
        let input = app.textViews["assistant.input"]
        reveal(input, in: app, upward: false)
        replace(input, with: "tempo 108")
        let review = app.buttons["assistant.generate"]
        reveal(review, in: app)
        review.tap()
        let apply = app.buttons["assistant.apply"]
        reveal(apply, in: app)
        XCTAssertTrue(app.staticTexts["108 BPM"].exists)
        keepScreenshot("AuthorizedInput-typed-command-after-granted-Speech")
        apply.tap()
        wait(app.navigationBars["Assistant"], timeout: 5) { !app.navigationBars["Assistant"].exists }
        let tempo = app.staticTexts["studio.tempo"]
        XCTAssertTrue(tempo.waitForExistence(timeout: 5))
        XCTAssertEqual(tempo.label, "108 BPM")
        app.buttons["Undo"].tap()
        XCTAssertEqual(tempo.label, "120 BPM")
    }

    @MainActor private func launch(_ app: XCUIApplication, arguments: [String]) {
        XCUIDevice.shared.orientation = .portrait
        app.launchArguments = ["--uitesting", "--runtime-trace", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + arguments
        app.launch()
    }

    @MainActor private func waitForResult(_ result: XCUIElement, app: XCUIApplication, springboard: XCUIApplication, states: Set<String>, timeout: TimeInterval, handle: (XCUIElement) -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            for alert in springboard.alerts.allElementsBoundByIndex { _ = handle(alert) }
            if result.exists && states.contains(result.label) { return }
            if app.state == .notRunning { XCTFail("Native process exited before its actual input receipt"); return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("Native input result did not reach \(states.sorted()) in \(timeout) seconds")
    }

    @MainActor private func alertDescription(_ alert: XCUIElement) -> String {
        ([alert.label] + alert.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator: " ")
    }

    @MainActor private func tapFirst(_ titles: [String], in alert: XCUIElement) -> Bool {
        for title in titles where alert.buttons[title].exists { alert.buttons[title].tap(); return true }
        return false
    }

    @MainActor private func wait(_ element: XCUIElement, timeout: TimeInterval, condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("Expected actual UI state did not settle within \(timeout) seconds for \(element)")
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = true) {
        let scroll = app.scrollViews["assistant.review-scroll"]
        for _ in 0..<7 {
            let viewport = scroll.frame.intersection(app.frame)
            if element.exists && element.isHittable && element.frame.minY >= viewport.minY + 8 && element.frame.maxY <= viewport.maxY - 8 { return }
            if upward { scroll.swipeUp() } else { scroll.swipeDown() }
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    @MainActor private func replace(_ field: XCUIElement, with value: String) {
        field.tap()
        if let current = field.value as? String, !current.isEmpty { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count)) }
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value)
    }

    @MainActor private func trace(_ element: XCUIElement) -> String { (element.value as? String ?? "").components(separatedBy: "\n").first ?? "" }

    private func traceValue(_ key: String, in value: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: "(?:^|[ |])" + NSRegularExpression.escapedPattern(for: key) + "=([^ |\\n]+)"), let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)), let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }

    private func object(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(text.data(using: .utf8))) as? [String: Any])
    }

    private func json(_ value: [String: Any]) throws -> String { String(decoding: try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .prettyPrinted]), as: UTF8.self) }

    private func keep(_ text: String, name: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
