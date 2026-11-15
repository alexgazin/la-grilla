import XCTest

/// Assertions run inside the app against its actual AVAudioEngine and kernel.
/// The microphone case requires real simulator input callbacks and fails if
/// permission or finite PCM fails on an available route. Only independently
/// evidenced absence of host input can skip, after output continuity passes.
final class AudioRuntimeContinuityTests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=90}

    @MainActor private func run(microphone:Bool,midiPolicy:Bool=false,voiceCapture:Bool=false,inputDiagnostic:Bool=false)throws {
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--audio-runtime-qa","-AppleLanguages","(en)","-AppleLocale","en_US"]
        if microphone{app.launchArguments.append("--audio-runtime-microphone")}
        if midiPolicy{app.launchArguments.append("--audio-runtime-midi-policy")}
        if voiceCapture{app.launchArguments.append("--audio-runtime-voice-capture")}
        if inputDiagnostic{app.launchArguments.append("--audio-input-lifecycle-controls")}
        let interruption=addUIInterruptionMonitor(withDescription:"Native microphone permission"){alert in
            guard microphone else{return false}
            if alert.buttons["Allow"].exists{alert.buttons["Allow"].tap();return true}
            if alert.buttons["OK"].exists{alert.buttons["OK"].tap();return true}
            return false
        }
        defer{removeUIInterruptionMonitor(interruption)}
        app.launch()
        let result=app.staticTexts["audio.runtime.result"]
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        func allowMicrophonePrompt(){
            guard microphone else{return}
            let allow=springboard.alerts.buttons["Allow"]
            if allow.exists{allow.tap();return}
            let affirmative=springboard.alerts.buttons["OK"]
            if affirmative.exists{affirmative.tap()}
        }
        // A system permission alert may hide the app's accessibility tree.
        // Dismiss it before waiting for the fixture beneath that alert.
        let appearanceDeadline=Date().addingTimeInterval(15)
        var fixtureAppeared=false
        while Date()<appearanceDeadline {
            allowMicrophonePrompt()
            if result.exists{fixtureAppeared=true;break}
            RunLoop.current.run(until:Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(fixtureAppeared)
        if microphone {
            let start=app.buttons["audio.runtime.start"]
            XCTAssertTrue(start.waitForExistence(timeout:15))
            XCTAssertEqual(result.label,"READY")
            XCTAssertGreaterThanOrEqual(start.frame.height,44)
            start.tap()
        }
        let deadline=Date().addingTimeInterval(35)
        while Date()<deadline {
            allowMicrophonePrompt()
            if result.exists,result.label == "PASS" || result.label == "FAIL" || result.label == "UNAVAILABLE" || (inputDiagnostic && result.label == "DIAGNOSTIC"){break}
            RunLoop.current.run(until:Date().addingTimeInterval(0.1))
        }
        let details=app.staticTexts["audio.runtime.details"].label
        let report=XCTAttachment(string:details);report.name=inputDiagnostic ? "Diagnostic-only-input-lifecycle-controls":voiceCapture ? "Native-production-voice-capture-lifecycle":midiPolicy ? "Native-immediate-MIDI-policy":microphone ? "Native-microphone-engine-continuity":"Native-live-snapshot-continuity";report.lifetime = .keepAlways;add(report)
        if inputDiagnostic {
            XCTAssertEqual(result.label,"DIAGNOSTIC",details)
            let data=try XCTUnwrap(details.data(using:.utf8))
            let diagnostic=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
            XCTAssertEqual(diagnostic["diagnosticOnly"] as? Bool,true)
            XCTAssertEqual(diagnostic["productionAcceptance"] as? Bool,false)
            XCTAssertEqual(diagnostic["humanVoiceAccuracyVerified"] as? Bool,false)
            XCTAssertEqual(diagnostic["permissionAfter"] as? String,"granted")
            XCTAssertEqual(diagnostic["permissionRequestGranted"] as? Bool,true)
            XCTAssertEqual(diagnostic["originalSessionEngineReleased"] as? Bool,true)
            let cases=try XCTUnwrap(diagnostic["cases"] as? [[String:Any]])
            XCTAssertEqual(cases.count,4)
            XCTAssertEqual(Set(cases.compactMap{$0["id"] as? String}),Set(["duplex-input-first","playback-disabled-input-precreated","playback-output-first-late-input","duplex-output-first-late-input"]))
            XCTAssertLessThan(diagnostic["elapsedSeconds"] as? Double ?? .infinity,20)
            return
        }
        if voiceCapture,result.label=="UNAVAILABLE"{XCTFail("Production VoiceCapture acceptance requires real HAL input: "+details);return}
        if microphone,result.label=="UNAVAILABLE" {
            guard let data=details.data(using:.utf8),let report=try JSONSerialization.jsonObject(with:data) as? [String:Any],report["outcome"] as? String=="UNAVAILABLE",
                  let routes=report["routes"] as? [[String:Any]],routes.count==1,let route=routes.first,route["stage"] as? String=="activated-playAndRecord",
                  route["category"] as? String=="AVAudioSessionCategoryPlayAndRecord",route["isInputAvailable"] as? Bool==false,
                  let inputs=route["inputs"] as? [[String:Any]],inputs.isEmpty,
                  let available=route["availableInputs"] as? [[String:Any]],available.isEmpty,
                  report["outputEngineRetained"] as? Bool==true,report["outputKernelRetained"] as? Bool==true,
                  report["outputClockAdvanced"] as? Bool==true,report["outputPlaying"] as? Bool==true,report["categoryRestored"] as? Bool==true,
                  let phaseDifference=report["phaseDifferenceTicks"] as? Double,phaseDifference<128
            else{XCTFail("UNAVAILABLE lacks real no-input and output-continuity evidence: "+details);return}
            if ProcessInfo.processInfo.environment["GRILLA_REQUIRE_MIC_INPUT"]=="1" {
                XCTFail("The configured CI audio fixture did not expose a microphone route: "+details);return
            }
            throw XCTSkip("Host exposes no microphone input; output engine/kernel/clock continuity passed. Actual route: "+details)
        }
        XCTAssertEqual(result.label,"PASS",details)
        if voiceCapture{try assertVoiceReceipt(details)}
    }
    @MainActor private func assertVoiceReceipt(_ details:String)throws {
        guard let data=details.data(using:.utf8),let report=try JSONSerialization.jsonObject(with:data) as? [String:Any],let source=report["source"] as? [String:Any],let frames=report["sourceFrames"] as? Int,let detected=report["detectedPitches"] as? [Int],let reviewed=report["reviewedPitches"] as? [Int]else{XCTFail("Missing production voice-capture receipt: "+details);return}
        XCTAssertEqual(report["outcome"] as? String,"PASS")
        XCTAssertEqual(source["origin"] as? String,"microphone")
        XCTAssertEqual(source["sampleRate"] as? Double,48000)
        XCTAssertEqual((source["sha256"] as? String)?.count,64)
        XCTAssertGreaterThan(frames,0);XCTAssertLessThanOrEqual(frames,144000)
        XCTAssertFalse(detected.isEmpty);XCTAssertEqual(detected.count,reviewed.count)
        XCTAssertNotEqual(detected.first,reviewed.first,"Manual review must preserve capture while correcting a detected note")
        for key in ["storedSourceMatches","storedProjectReopened","oneUndoRestoresBaseline","redoRestoresExactSourceAndNotes","sourceUnchangedAfterReview","sameEngineAndKernel","backingClockAdvanced"]{XCTAssertEqual(report[key] as? Bool,true,key)}
        XCTAssertGreaterThan(report["continuitySamples"] as? Int ?? 0,10)
        XCTAssertLessThan(report["maximumPhaseErrorTicks"] as? Double ?? .infinity,128)
        XCTAssertLessThan(report["elapsedSeconds"] as? Double ?? .infinity,35)
        let baseline=try XCTUnwrap(report["outputHostTimingBaseline"] as? [String:Any])
        let timing=try XCTUnwrap(report["outputHostTiming"] as? [String:Any])
        XCTAssertGreaterThan(timing["epoch"] as? Int ?? 0,0)
        XCTAssertEqual(timing["epoch"] as? Int,baseline["epoch"] as? Int)
        XCTAssertGreaterThan(timing["callbacks"] as? Int ?? 0,baseline["callbacks"] as? Int ?? .max)
        XCTAssertGreaterThanOrEqual(baseline["comparedCallbacks"] as? Int ?? 0,8)
        XCTAssertEqual(baseline["inheritedAnchor"] as? Bool,true)
        XCTAssertEqual(report["physicalDropoutAbsenceVerified"] as? Bool,false)
    }

    @MainActor func testAAOutputOnlyLaunchDoesNotRequestMicrophone()throws {
        let app=XCUIApplication(),springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        app.terminate()
        app.resetAuthorizationStatus(for:.microphone)
        app.launchArguments=["--uitesting","--audio-runtime-qa","--audio-runtime-output-privacy","-AppleLanguages","(en)","-AppleLocale","en_US"]
        var allowExplicitRequest=false,earlyMicrophoneAlert=false,requestedAlertObserved=false
        func handleMicrophoneAlert(_ alert:XCUIElement)->Bool {
            let text=([alert.label]+alert.staticTexts.allElementsBoundByIndex.map(\.label)).joined(separator:" ")
            guard text.localizedCaseInsensitiveContains("microphone") else{return false}
            if allowExplicitRequest {
                requestedAlertObserved=true
                for title in ["Allow","OK"] where alert.buttons[title].exists{alert.buttons[title].tap();return true}
                return false
            }
            earlyMicrophoneAlert=true
            // Until phase one's receipt is attached and Start is about to be
            // tapped, an automatic request is a privacy failure, never consent.
            for title in ["Don’t Allow","Don't Allow"] where alert.buttons[title].exists{alert.buttons[title].tap();return true}
            return false
        }
        let interruption=addUIInterruptionMonitor(withDescription:"Cold output then explicit first recording consent"){handleMicrophoneAlert($0)}
        defer {
            allowExplicitRequest=false
            app.terminate()
            for alert in springboard.alerts.allElementsBoundByIndex{_ = handleMicrophoneAlert(alert)}
            app.resetAuthorizationStatus(for:.microphone)
            removeUIInterruptionMonitor(interruption)
        }
        app.launch()
        let result=app.staticTexts["audio.runtime.result"]
        let phaseOneDeadline=Date().addingTimeInterval(20)
        while Date()<phaseOneDeadline {
            for alert in springboard.alerts.allElementsBoundByIndex{_ = handleMicrophoneAlert(alert)}
            if result.exists,result.label=="READY" || result.label=="FAIL"{break}
            RunLoop.current.run(until:Date().addingTimeInterval(0.1))
        }
        for alert in springboard.alerts.allElementsBoundByIndex{_ = handleMicrophoneAlert(alert)}
        let privacyDetails=app.staticTexts["audio.runtime.details"].label
        let privacyAttachment=XCTAttachment(string:privacyDetails);privacyAttachment.name="Cold-output-only-privacy-software-observation";privacyAttachment.lifetime = .keepAlways;add(privacyAttachment)
        XCTAssertFalse(earlyMicrophoneAlert,"Output-only startup requested microphone access.")
        XCTAssertEqual(result.label,"READY",privacyDetails)
        let data=try XCTUnwrap(privacyDetails.data(using:.utf8))
        let privacy=try XCTUnwrap(JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertEqual(privacy["permissionBefore"] as? String,"undetermined")
        XCTAssertEqual(privacy["permissionAfter"] as? String,"undetermined")
        XCTAssertEqual(privacy["softwareOutputPrivacyVerified"] as? Bool,true)
        XCTAssertEqual(privacy["preparedMonophonicReference"] as? Bool,true)
        XCTAssertEqual(privacy["referenceEngineKernelRetained"] as? Bool,true)
        XCTAssertEqual(privacy["outputPlaying"] as? Bool,true)
        XCTAssertEqual(privacy["outputEngineRunning"] as? Bool,true)
        XCTAssertGreaterThan(privacy["outputClockFramesAdvanced"] as? Int ?? 0,0)
        XCTAssertGreaterThan(privacy["observedOutputPeak"] as? Double ?? 0,0.0001)
        XCTAssertEqual(privacy["physicalMicrophoneIndicatorVerified"] as? Bool,false)
        XCTAssertEqual(privacy["productionAcceptance"] as? Bool,false)
        let process=try XCTUnwrap(privacy["processIdentifier"] as? Int)
        XCTAssertGreaterThan(process,0)
        let start=app.buttons["audio.runtime.start"]
        XCTAssertTrue(start.waitForExistence(timeout:5));XCTAssertGreaterThanOrEqual(start.frame.height,44)
        for alert in springboard.alerts.allElementsBoundByIndex{_ = handleMicrophoneAlert(alert)}
        guard !earlyMicrophoneAlert,result.label=="READY",
              privacy["softwareOutputPrivacyVerified"] as? Bool==true,
              privacy["permissionBefore"] as? String=="undetermined",
              privacy["permissionAfter"] as? String=="undetermined",
              start.exists,start.isHittable
        else{XCTFail("Cold output privacy/READY preconditions failed; recording consent will not be granted");return}
        // Same app and engine: no terminate/relaunch, music setup or seek between
        // the privacy observation and the production capture/application flow.
        allowExplicitRequest=true
        start.tap()
        let phaseTwoDeadline=Date().addingTimeInterval(35)
        while Date()<phaseTwoDeadline {
            for alert in springboard.alerts.allElementsBoundByIndex{_ = handleMicrophoneAlert(alert)}
            if result.exists,result.label=="PASS" || result.label=="FAIL" || result.label=="UNAVAILABLE"{break}
            RunLoop.current.run(until:Date().addingTimeInterval(0.1))
        }
        let captureDetails=app.staticTexts["audio.runtime.details"].label
        let captureAttachment=XCTAttachment(string:captureDetails);captureAttachment.name="Cold-first-use-production-voice-capture-lifecycle";captureAttachment.lifetime = .keepAlways;add(captureAttachment)
        XCTAssertFalse(earlyMicrophoneAlert)
        XCTAssertTrue(requestedAlertObserved,"Fresh first-use recording permission prompt was not observed after Start")
        XCTAssertEqual(result.label,"PASS",captureDetails)
        try assertVoiceReceipt(captureDetails)
        let captureData=try XCTUnwrap(captureDetails.data(using:.utf8))
        let capture=try XCTUnwrap(JSONSerialization.jsonObject(with:captureData) as? [String:Any])
        XCTAssertEqual(capture["referenceReusedWithoutPreparation"] as? Bool,true)
        XCTAssertEqual(capture["permissionBeforeCapture"] as? String,"undetermined")
        XCTAssertEqual(capture["permissionAfterCapture"] as? String,"granted")
        let cold=try XCTUnwrap(capture["coldFirstUse"] as? [String:Any])
        XCTAssertEqual(cold["sameProcess"] as? Bool,true)
        XCTAssertEqual(cold["processIdentifier"] as? Int,process)
        XCTAssertEqual(cold["phaseOneEngineKernelRetained"] as? Bool,true)
        XCTAssertEqual(cold["referenceReusedWithoutPreparation"] as? Bool,true)
        XCTAssertEqual(cold["permissionAtExplicitStart"] as? String,"undetermined")
        XCTAssertEqual(cold["permissionAfterCapture"] as? String,"granted")
        XCTAssertLessThan(cold["phaseErrorBeforeCaptureTicks"] as? Double ?? .infinity,128)
    }
    @MainActor func testProductionVoiceCaptureCAFAnalysisApplyStoreAndUndo()throws {try run(microphone:true,voiceCapture:true)}
    @MainActor func testLiveSnapshotMixRoutingAndClockStayCoherent()throws {try run(microphone:false)}
    @MainActor func testSessionMicrophoneLeaseRetainsLiveEngineAndPCM()throws {try run(microphone:true)}
    @MainActor func testMIDIOffTakesEffectBeforePendingStructuralBoundary()throws {try run(microphone:false,midiPolicy:true)}
    @MainActor func testDiagnosticOnlyFreshInputLifecycleControls()throws {
        guard ProcessInfo.processInfo.environment["GRILLA_INPUT_DIAGNOSTIC"]=="1" else{throw XCTSkip("Input lifecycle controls are opt-in diagnostics; production microphone acceptance is covered independently.")}
        try run(microphone:true,inputDiagnostic:true)
    }
}
