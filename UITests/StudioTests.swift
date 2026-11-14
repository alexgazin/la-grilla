import XCTest
final class StudioTests: XCTestCase {
    @MainActor func launch(_ screen: String = "grid") -> XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--uitesting","--screen",screen,"-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout:15));return app
    }
    @MainActor func testNavigationKeepsTransportAlive() {
        let app=launch();app.buttons["Play"].tap();XCTAssertTrue(app.staticTexts["PLAYING"].waitForExistence(timeout:5))
        app.buttons["Jam"].tap();XCTAssertTrue(app.staticTexts["Pocket kit"].exists);XCTAssertTrue(app.staticTexts["PLAYING"].exists)
        app.buttons["Kick"].tap();app.buttons["Mixer"].tap();XCTAssertTrue(app.staticTexts["Find your balance."].exists);XCTAssertTrue(app.staticTexts["PLAYING"].exists)
        app.buttons["Stop"].tap();XCTAssertTrue(app.staticTexts["STOPPED"].waitForExistence(timeout:5))
    }
    @MainActor func testCreateProjectAndChord() {
        let app=launch();app.buttons["Projects"].tap();app.buttons["New project"].tap()
        let name=app.textFields["Project name"];XCTAssertTrue(name.waitForExistence(timeout:5));name.tap();name.typeText("Night walk")
        app.buttons["Create"].tap();XCTAssertTrue(app.staticTexts["Night walk"].waitForExistence(timeout:5))
        app.buttons.matching(NSPredicate(format:"label == '+'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Edit chord"].waitForExistence(timeout:5));app.buttons["Minor"].tap();app.buttons["Apply"].tap()
        XCTAssertTrue(app.buttons["Undo"].isEnabled);app.buttons["Undo"].tap();XCTAssertTrue(app.buttons["Redo"].isEnabled)
    }
    @MainActor func testDrumTakeIsUndoable() {
        let app=launch("jam");app.buttons["Record drums"].tap()
        XCTAssertTrue(app.staticTexts["REC · DRUMS"].waitForExistence(timeout:8));app.buttons["Kick"].tap();app.buttons["Snare"].tap();app.buttons["Finish drum take"].tap()
        XCTAssertTrue(app.buttons["Undo"].isEnabled);app.buttons["Undo"].tap();XCTAssertTrue(app.buttons["Redo"].isEnabled)
    }
    @MainActor func testMIDIExportOffersSystemShare() {
        let app=launch();app.buttons["Export MIDI"].tap();XCTAssertTrue(app.staticTexts["Standard MIDI"].waitForExistence(timeout:5))
        app.buttons["Export MIDI"].tap();XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout:8) || app.buttons["Copy"].exists || app.buttons["Save to Files"].exists)
    }
}
