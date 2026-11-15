import XCTest

/// Drives Session's normal recording lifecycle against the actual native audio
/// callback, including a partial take finalized by the finite transport itself.
final class DrumRuntimeContinuityTests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=75}
    @MainActor func testFocusedClipRecordingAndNaturalStopRetainLiveEngine()throws {
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--audio-runtime-qa","--audio-runtime-drum-clip","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        let result=app.staticTexts["audio.runtime.result"]
        XCTAssertTrue(result.waitForExistence(timeout:15))
        let completed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == 'PASS' OR label == 'FAIL'"),object:result)
        let status=XCTWaiter.wait(for:[completed],timeout:35)
        let details=app.staticTexts["audio.runtime.details"].label
        let report=XCTAttachment(string:details);report.name="Native-focused-drum-recording-continuity";report.lifetime = .keepAlways;add(report)
        XCTAssertEqual(status,.completed,details);XCTAssertEqual(result.label,"PASS",details)
        let data=try XCTUnwrap(details.data(using:.utf8)),json=try XCTUnwrap(try JSONSerialization.jsonObject(with:data) as? [String:Any])
        XCTAssertEqual(json["scenario"] as? String,"focused-drum-clip")
        for field in ["engineRetained","kernelRetained","focusedSourceIndependent","siblingClipUnchanged","sharedSourceUnchanged","originalHeardEventsPreserved","oneUndoRedo","finiteNaturalStop","finiteRecordingUnlocked","finalPartialPassCommitted","outOfClipPadExcluded"]{XCTAssertEqual(json[field] as? Bool,true,"Missing actual lifecycle evidence: "+field+"; "+details)}
        XCTAssertEqual(json["focusedNewPads"] as? [Int],[14,15]);XCTAssertEqual(json["finiteNewPads"] as? [Int],[13])
        XCTAssertGreaterThanOrEqual(json["passesCrossed"] as? Int ?? 0,1)
        XCTAssertLessThan(json["loopPhaseDifferenceTicks"] as? Double ?? .infinity,128)
        XCTAssertGreaterThan(json["drumMeterPeak"] as? Double ?? 0,0.0001)
        XCTAssertLessThan(json["elapsedSeconds"] as? Double ?? .infinity,35)
    }
}
