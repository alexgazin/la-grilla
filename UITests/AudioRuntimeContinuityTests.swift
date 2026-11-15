import XCTest

/// Assertions run inside the app against its actual AVAudioEngine and kernel.
/// The microphone case requires real simulator input callbacks and fails if
/// permission, a usable route or finite PCM delivery is unavailable.
final class AudioRuntimeContinuityTests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=90}

    @MainActor private func run(microphone:Bool,midiPolicy:Bool=false)throws {
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--audio-runtime-qa","-AppleLanguages","(en)","-AppleLocale","en_US"]
        if microphone{app.launchArguments.append("--audio-runtime-microphone")}
        if midiPolicy{app.launchArguments.append("--audio-runtime-midi-policy")}
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
            if result.exists,result.label == "PASS" || result.label == "FAIL"{break}
            RunLoop.current.run(until:Date().addingTimeInterval(0.1))
        }
        let details=app.staticTexts["audio.runtime.details"].label
        let report=XCTAttachment(string:details);report.name=midiPolicy ? "Native-immediate-MIDI-policy":microphone ? "Native-microphone-engine-continuity":"Native-live-snapshot-continuity";report.lifetime = .keepAlways;add(report)
        XCTAssertEqual(result.label,"PASS",details)
    }

    @MainActor func testLiveSnapshotMixRoutingAndClockStayCoherent()throws {try run(microphone:false)}
    @MainActor func testSessionMicrophoneLeaseRetainsLiveEngineAndPCM()throws {try run(microphone:true)}
    @MainActor func testMIDIOffTakesEffectBeforePendingStructuralBoundary()throws {try run(microphone:false,midiPolicy:true)}
}
