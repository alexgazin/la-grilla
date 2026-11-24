import XCTest

/// U3: what Siri and Shortcuts open (the intent leaves a request; the app handles it).
final class IntentLaunchUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 90 }

    @MainActor private func launch(_ intent: String) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--launch-intent", intent, "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    @MainActor func testRecordIdeaOpensHumToMIDI() {
        let app = launch("recordIdea")
        XCTAssertTrue(app.navigationBars["Voice to MIDI"].waitForExistence(timeout: 15))
    }

    @MainActor func testExportIntentOpensExport() {
        let app = launch("export")
        XCTAssertTrue(app.buttons["export.confirm"].waitForExistence(timeout: 15))
    }
}
