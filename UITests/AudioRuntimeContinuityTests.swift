import XCTest

/// Assertions run inside the app against its actual AVAudioEngine and kernel.
/// The microphone case requires real simulator input callbacks and fails if
/// permission or finite PCM fails on an available route. Only independently
/// evidenced absence of host input can skip, after output continuity passes.
final class AudioRuntimeContinuityTests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=90}

    @MainActor private func run(microphone:Bool,midiPolicy:Bool=false,voiceCapture:Bool=false)throws {
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--audio-runtime-qa","-AppleLanguages","(en)","-AppleLocale","en_US"]
        if microphone{app.launchArguments.append("--audio-runtime-microphone")}
        if midiPolicy{app.launchArguments.append("--audio-runtime-midi-policy")}
        if voiceCapture{app.launchArguments.append("--audio-runtime-voice-capture")}
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
            if result.exists,result.label == "PASS" || result.label == "FAIL" || result.label == "UNAVAILABLE"{break}
            RunLoop.current.run(until:Date().addingTimeInterval(0.1))
        }
        let details=app.staticTexts["audio.runtime.details"].label
        let report=XCTAttachment(string:details);report.name=voiceCapture ? "Native-production-voice-capture-lifecycle":midiPolicy ? "Native-immediate-MIDI-policy":microphone ? "Native-microphone-engine-continuity":"Native-live-snapshot-continuity";report.lifetime = .keepAlways;add(report)
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
    }

    @MainActor func testProductionVoiceCaptureCAFAnalysisApplyStoreAndUndo()throws {try run(microphone:true,voiceCapture:true)}
    @MainActor func testLiveSnapshotMixRoutingAndClockStayCoherent()throws {try run(microphone:false)}
    @MainActor func testSessionMicrophoneLeaseRetainsLiveEngineAndPCM()throws {try run(microphone:true)}
    @MainActor func testMIDIOffTakesEffectBeforePendingStructuralBoundary()throws {try run(microphone:false,midiPolicy:true)}
}
