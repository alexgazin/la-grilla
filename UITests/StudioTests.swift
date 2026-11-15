import XCTest
final class StudioTests: XCTestCase {
    @MainActor func launch(_ screen: String = "grid") -> XCUIApplication {
        let app=XCUIApplication();app.launchArguments=["--uitesting","--screen",screen,"-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:15));return app
    }
    @MainActor func testRussianInterfaceAndLightAppearance() {
        let app=XCUIApplication();app.launchArguments=["--uitesting","--screen","grid","--appearance","light","-AppleLanguages","(ru)","-AppleLocale","ru_RU"];app.launch()
        XCTAssertTrue(app.buttons["Сетка"].waitForExistence(timeout:15));app.buttons["export.open"].tap()
        XCTAssertTrue(app.navigationBars["Экспорт"].waitForExistence(timeout:5));XCTAssertTrue(app.buttons["Отмена"].exists)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="R8-russian-light-export";shot.lifetime = .keepAlways;add(shot)
    }
    @MainActor func testLargeTypeMixerAndAccessibleNoteList() throws {
        let app=XCUIApplication();app.launchArguments=["--uitesting","--screen","notes","--large-type","-AppleLanguages","(en)","-AppleLocale","en_US"];app.launch()
        XCTAssertTrue(app.navigationBars["Piano roll"].waitForExistence(timeout:15));XCTAssertTrue(app.tables.firstMatch.exists || app.collectionViews.firstMatch.exists)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="R8-large-type-piano-roll";shot.lifetime = .keepAlways;add(shot)
        app.buttons["Done"].tap();app.buttons["Mixer"].tap();XCTAssertTrue(app.sliders["Gain Harmony"].waitForExistence(timeout:5))
        try app.performAccessibilityAudit(for:[.sufficientElementDescription])
    }
    @MainActor func testLandscapeKeepsPadsAndTransportReachable() {
        let app=launch();XCUIDevice.shared.orientation = .landscapeLeft;defer{XCUIDevice.shared.orientation = .portrait}
        app.buttons["Jam"].tap();XCTAssertTrue(app.buttons["Play"].isHittable);XCTAssertTrue(app.buttons["Kick"].isHittable);app.buttons["Kick"].tap()
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="R8-landscape-jam";shot.lifetime = .keepAlways;add(shot)
        app.buttons["Play"].tap();XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout:5));app.buttons["Stop"].tap()
    }
    @MainActor func testVirtualMIDILearnAndActualOutputDestination() {
        let app=launch("midi");XCTAssertTrue(app.staticTexts["midi.fixture"].waitForExistence(timeout:15))
        app.swipeUp();app.swipeUp()
        XCTAssertTrue(app.buttons["midi.learn"].waitForExistence(timeout:5));app.buttons["midi.learn"].tap();app.buttons["midi.send-fixture"].tap()
        XCTAssertTrue(app.staticTexts["Ch 1 · CC 74"].waitForExistence(timeout:8))
        app.swipeUp();XCTAssertTrue(app.staticTexts["midi.last"].waitForExistence(timeout:5));XCTAssertTrue(app.staticTexts["midi.last"].label.contains("CC 74"))
        app.swipeDown();let received=app.staticTexts["midi.fixture-received"]
        XCTAssertTrue(received.waitForExistence(timeout:5));XCTAssertGreaterThan(Int(received.label) ?? 0,0)
        app.swipeUp();app.buttons["midi.panic"].tap();app.buttons["Done"].tap();XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout:5))
    }
    @MainActor func testPerformRecordingSurvivesNavigationAndReplays() {
        let app=launch("perform")
        XCTAssertTrue(app.buttons["perform.record"].waitForExistence(timeout:5));app.buttons["perform.record"].tap()
        XCTAssertTrue(app.staticTexts["perform.mode"].waitForExistence(timeout:5))
        app.buttons["perform.section.Chorus"].tap()
        app.buttons["perform.done"].tap();app.buttons["Jam"].tap();app.buttons["Kick"].tap()
        app.buttons["perform.transport"].tap();XCTAssertTrue(app.buttons["perform.record"].waitForExistence(timeout:5));app.buttons["perform.record"].tap()
        app.swipeUp();app.swipeUp();app.swipeUp()
        XCTAssertTrue(app.staticTexts["perform.saved"].waitForExistence(timeout:5));app.buttons["perform.replay"].tap()
        app.swipeDown();app.swipeDown();app.swipeDown()
        XCTAssertTrue(app.staticTexts["perform.mode"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["perform.mode"].label,"TAKE REPLAY")
        app.buttons["perform.panic"].tap();app.buttons["perform.done"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout:5))
    }
    @MainActor func testFinitePerformanceWAVExportOffersShare() {
        let app=launch("perform-export")
        XCTAssertTrue(app.staticTexts["Export your performance."].waitForExistence(timeout:12))
        XCTAssertFalse(app.buttons["format.stems"].exists);app.buttons["export.confirm"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout:20) || app.buttons["Copy"].exists || app.staticTexts["Save to Files"].exists)
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
        app.buttons["notes.play"].tap();XCTAssertEqual(app.staticTexts["notes.status"].label,"PLAYING")
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
    @MainActor func testAssistantCommandReviewApplyAndUndo() {
        let app=launch();app.buttons["assistant.open"].tap();XCTAssertTrue(app.navigationBars["Assistant"].waitForExistence(timeout:5))
        app.buttons["Examples"].tap();app.buttons["Tempo 110"].tap();app.buttons["assistant.generate"].tap();app.swipeUp()
        XCTAssertTrue(app.buttons["assistant.apply"].waitForExistence(timeout:5));app.buttons["assistant.apply"].tap()
        XCTAssertTrue(app.staticTexts["110"].waitForExistence(timeout:5));app.buttons["Undo"].tap();XCTAssertTrue(app.staticTexts["120"].exists)
    }
    @MainActor func testAssistantAmbiguityKeepsMusicUnchangedUntilApply() {
        let app=launch();app.buttons["assistant.open"].tap();let input=app.textViews["assistant.input"];XCTAssertTrue(input.waitForExistence(timeout:5));input.tap();input.typeText("Am F");app.swipeUp();app.buttons["assistant.generate"].tap();app.swipeUp()
        XCTAssertTrue(app.buttons["Stretch chords evenly"].waitForExistence(timeout:5));XCTAssertFalse(app.buttons["assistant.apply"].exists)
        app.buttons["Stretch chords evenly"].tap();app.swipeUp();XCTAssertTrue(app.buttons["assistant.apply"].exists)
        app.buttons["Cancel"].tap();XCTAssertTrue(app.staticTexts["120"].exists)
    }
    @MainActor func testVoiceFixtureAnalyzePreviewApplyUndoAndPortableExport() {
        let app=launch("voice-draft");XCTAssertTrue(app.staticTexts["voice.note-count"].waitForExistence(timeout:15));XCTAssertEqual(app.staticTexts["voice.note-count"].label,"3 notes")
        app.swipeUp();app.buttons["voice.original"].tap();app.buttons["voice.instrument"].tap();app.swipeUp();app.swipeUp()
        XCTAssertTrue(app.buttons["voice.apply"].waitForExistence(timeout:5));app.buttons["voice.apply"].tap()
        XCTAssertTrue(app.buttons["Undo"].waitForExistence(timeout:5));app.buttons["Undo"].tap();app.buttons["Redo"].tap()
        app.buttons["export.open"].tap();app.buttons["format.project"].tap();app.buttons["export.confirm"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout:20) || app.buttons["Copy"].exists || app.staticTexts["Save to Files"].exists)
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
