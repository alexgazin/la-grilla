import XCTest

/// Assertions run inside the app against its actual AVAudioEngine and kernel.
/// The microphone case requires real simulator input callbacks and fails if
/// permission, a usable route or finite PCM delivery is unavailable.
final class AudioRuntimeContinuityTests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=90}

    @MainActor private func run(microphone:Bool)throws {
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--audio-runtime-qa","-AppleLanguages","(en)","-AppleLocale","en_US"]
        if microphone{app.launchArguments.append("--audio-runtime-microphone")}
        app.launch()
        let result=app.staticTexts["audio.runtime.result"]
        XCTAssertTrue(result.waitForExistence(timeout:15))
        let springboard=XCUIApplication(bundleIdentifier:"com.apple.springboard")
        let deadline=Date().addingTimeInterval(35)
        while Date()<deadline,result.label != "PASS",result.label != "FAIL" {
            if microphone {
                let allow=springboard.alerts.buttons["Allow"]
                if allow.exists{allow.tap()}
                let affirmative=springboard.alerts.buttons["OK"]
                if affirmative.exists{affirmative.tap()}
            }
            RunLoop.current.run(until:Date().addingTimeInterval(0.1))
        }
        let details=app.staticTexts["audio.runtime.details"].label
        let report=XCTAttachment(string:details);report.name=microphone ? "Native-microphone-engine-continuity":"Native-live-snapshot-continuity";report.lifetime = .keepAlways;add(report)
        XCTAssertEqual(result.label,"PASS",details)
    }

    @MainActor func testLiveSnapshotMixRoutingAndClockStayCoherent()throws {try run(microphone:false)}
    @MainActor func testSessionMicrophoneLeaseRetainsLiveEngineAndPCM()throws {try run(microphone:true)}
}
