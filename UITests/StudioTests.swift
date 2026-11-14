import XCTest
final class StudioTests: XCTestCase {
    @MainActor func launch(_ screen: String = "grid") -> XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--uitesting","--screen",screen,"-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout:15));return app
    }
    @MainActor func testNavigationKeepsTransportAlive() {
        let app=launch();app.buttons["Play"].tap();XCTAssertTrue(app.staticTexts["PLAYING"].waitForExistence(timeout:5))
        app.buttons["Jam"].tap();XCTAssertTrue(app.staticTexts["Pocket kit"].exists);XCTAssertTrue(app.staticTexts["PLAYING"].exists)
        app.buttons["Kick"].tap();app.buttons["Mixer"].tap();XCTAssertTrue(app.staticTexts["Find your balance."].exists);XCTAssertTrue(app.buttons["Projects"].isHittable);XCTAssertTrue(app.buttons["Mixer"].isHittable);XCTAssertTrue(app.staticTexts["PLAYING"].exists)
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
    @MainActor func testPianoRollNotesUndoAndTransport() {
        let app=launch();app.buttons["notes.open"].tap()
        XCTAssertTrue(app.navigationBars["Piano roll"].waitForExistence(timeout:5))
        app.buttons["notes.add"].tap();XCTAssertTrue(app.staticTexts["notes.count"].label=="1")
        app.buttons["Copy note"].tap();app.buttons["Paste note"].tap();XCTAssertTrue(app.staticTexts["notes.count"].label=="2")
        app.buttons["notes.undo"].tap();XCTAssertTrue(app.staticTexts["notes.count"].label=="1")
        app.buttons["Show note list"].tap();XCTAssertTrue(app.tables.firstMatch.exists || app.collectionViews.firstMatch.exists)
        app.buttons["notes.play"].tap();XCTAssertTrue(app.staticTexts["notes.status"].waitForExistence(timeout:5))
        app.buttons["Done"].tap();XCTAssertTrue(app.staticTexts["PLAYING"].exists)
        app.buttons["Stop"].tap()
    }
    @MainActor func testEightTrackMixerMasterIsIndependent() {
        let app=launch("notes-mixer");XCTAssertTrue(app.staticTexts["Master"].exists)
        XCTAssertTrue(app.buttons["Mute Harmony"].isHittable)
        app.buttons["Mute Harmony"].tap();XCTAssertEqual(app.buttons["Mute Harmony"].value as? String,"On")
        XCTAssertTrue(app.buttons["Play"].isHittable);app.buttons["Play"].tap();XCTAssertTrue(app.staticTexts["PLAYING"].waitForExistence(timeout:5));app.buttons["Stop"].tap()
    }
    @MainActor func testHarmonyProposalPreviewApplyAndUndo() {
        let app=launch();app.buttons["harmony.open"].tap();XCTAssertTrue(app.navigationBars["Harmony lab"].waitForExistence(timeout:5))
        app.buttons["harmony.generate"].tap();app.swipeUp()
        XCTAssertTrue(app.buttons["harmony.b"].waitForExistence(timeout:5));app.buttons["harmony.b"].tap();XCTAssertTrue(app.buttons["Stop preview"].exists)
        app.buttons["harmony.a"].tap();app.buttons["harmony.apply"].tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout:5));app.buttons["Undo"].tap();XCTAssertTrue(app.buttons["Redo"].isEnabled)
    }
    @MainActor func testWAVExportOffersSystemShare() {
        let app=launch();app.buttons["Play"].tap();app.buttons["export.open"].tap()
        XCTAssertTrue(app.buttons["format.wav"].waitForExistence(timeout:5));app.buttons["format.wav"].tap();app.buttons["export.confirm"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout:30) || app.buttons["Copy"].exists || app.staticTexts["Save to Files"].exists)
    }
    @MainActor func testPortableExportOffersSystemShare() {
        let app=launch();app.buttons["export.open"].tap();app.buttons["format.project"].tap();app.buttons["export.confirm"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout:15) || app.buttons["Copy"].exists || app.staticTexts["Save to Files"].exists)
    }
    @MainActor func testMIDIExportOffersSystemShare() {
        let app=launch();app.buttons["export.open"].tap();XCTAssertTrue(app.buttons["format.midi"].waitForExistence(timeout:5))
        app.buttons["export.confirm"].tap();XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout:8) || app.buttons["Copy"].exists || app.buttons["Save to Files"].exists || app.staticTexts["Copy"].exists || app.staticTexts["Save to Files"].exists)
    }
}
