import XCTest

/// U16: recording over a late route asks first.
final class RouteWarningUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 90 }

    @MainActor func testBluetoothAsksBeforeRecordingAndRecordAnywayStarts() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--route-bluetooth", "--screen", "jam", "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 15))
        app.buttons["Record drums"].tap()
        let alert = app.alerts["Record over this route?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        // iOS 26 can expose an alert action twice (glass and title); both are the same action.
        alert.buttons["Record anyway"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["REC · DRUMS"].waitForExistence(timeout: 8))
        app.buttons["Finish drum take"].tap()
    }
}
