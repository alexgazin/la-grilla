import XCTest

final class PadTouchUITests:XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}
    @MainActor private func launch()->XCUIApplication{
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--runtime-trace","--device-output-startup","--screen","jam","--project-store-id",UUID().uuidString,"-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["jam.pad.0"].waitForExistence(timeout:15))
        return app
    }
    private func number(_ key:String,in value:String)->Double?{
        value.split(separator:" ").first{$0.hasPrefix(key+"=")}.flatMap{Double($0.dropFirst(key.count+1))}
    }
    @MainActor func testContactEnqueuesBeforeReleaseAndHoldDoesNotRetrigger()throws{
        let app=launch();defer{app.terminate()}
        let pad=app.buttons["jam.pad.0"]
        XCTAssertTrue(pad.isHittable)
        pad.press(forDuration:1.2)
        let value=try XCTUnwrap(pad.value as? String)
        XCTAssertEqual(number("accepted",in:value),1)
        XCTAssertEqual(number("held",in:value),0)
        let accepted=try XCTUnwrap(number("acceptedAt",in:value)),released=try XCTUnwrap(number("releasedAt",in:value))
        XCTAssertGreaterThan(accepted,0)
        XCTAssertGreaterThan(released-accepted,0.8,"The real native contact must enqueue before its long hold ends")
        pad.tap()
        XCTAssertEqual(number("accepted",in:try XCTUnwrap(pad.value as? String)),2)
        let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name="Touch21-Native-pads-sound-and-beat";shot.lifetime = .keepAlways;add(shot)
    }
    @MainActor func testSlidingFingerKeepsItsOriginalPadAndNeverStrikesNeighbour()throws{
        let app=launch();defer{app.terminate()}
        let first=app.buttons["jam.pad.0"],next=app.buttons["jam.pad.1"]
        first.press(forDuration:0.2,thenDragTo:next,withVelocity:120,thenHoldForDuration:0.4)
        XCTAssertEqual(number("accepted",in:try XCTUnwrap(first.value as? String)),1)
        XCTAssertEqual(number("held",in:try XCTUnwrap(first.value as? String)),0)
        XCTAssertEqual(number("accepted",in:try XCTUnwrap(next.value as? String)),0,"Moving one held finger must not create an unintended second hit")
        next.tap()
        XCTAssertEqual(number("accepted",in:try XCTUnwrap(next.value as? String)),1)
    }
}
