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

    @MainActor func testProductionVoiceCaptureCAFAnalysisApplyStoreAndUndo()throws {try run(microphone:true,voiceCapture:true)}
    @MainActor func testLiveSnapshotMixRoutingAndClockStayCoherent()throws {try run(microphone:false)}
    @MainActor func testSessionMicrophoneLeaseRetainsLiveEngineAndPCM()throws {try run(microphone:true)}
    @MainActor func testMIDIOffTakesEffectBeforePendingStructuralBoundary()throws {try run(microphone:false,midiPolicy:true)}
    @MainActor func testDiagnosticOnlyFreshInputLifecycleControls()throws {
        guard ProcessInfo.processInfo.environment["GRILLA_INPUT_DIAGNOSTIC"]=="1" else{throw XCTSkip("Input lifecycle controls are opt-in diagnostics; production microphone acceptance is covered independently.")}
        try run(microphone:true,inputDiagnostic:true)
    }
}
