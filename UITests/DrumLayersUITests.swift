import XCTest

/// Pocket beat layers: Mute keeps the hits, Clear removes one layer, one Undo restores it.
final class DrumLayersUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 180 }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 { if element.exists && element.isHittable { return }; app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor func testMuteSoloAndClearALayerWithOneUndo() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--screen", "jam", "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 15))
        let layers = app.descendants(matching: .any)["jam.layers"]
        XCTAssertTrue(layers.waitForExistence(timeout: 8), "The demo beat shows its layers")
        let mute = app.buttons["jam.layer.mute.0"]
        reveal(mute, in: app)
        XCTAssertEqual(mute.value as? String, "Off")
        mute.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'On'"), object: mute)], timeout: 5), .completed)
        // Muting keeps the layer listed; clearing removes it.
        let more = app.buttons["jam.layer.more.0"]
        reveal(more, in: app)
        more.tap()
        let clear = app.buttons["Clear layer"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        // The muted pad stays listed (0 hits) until it is unmuted.
        XCTAssertTrue(app.staticTexts["0 hits"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Layers46-cleared-kick"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["0 hits"])], timeout: 5), .completed)
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Off'"), object: mute)], timeout: 5), .completed)
    }

    @MainActor func testDeleteOnlyTheLastRecordedTakeKeepsTheProgrammedBeat() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--screen", "jam", "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 15))
        app.buttons["Record drums"].tap()
        XCTAssertTrue(app.staticTexts["REC · DRUMS"].waitForExistence(timeout: 8))
        // Clap is not in the demo beat, so every hit is new material of this take.
        for _ in 0..<3 { app.buttons["Clap"].tap(); Thread.sleep(forTimeInterval: 0.3) }
        app.buttons["Finish drum take"].tap()
        let deleteLast = app.buttons["jam.takes.delete-last"]
        reveal(deleteLast, in: app)
        XCTAssertTrue(app.staticTexts["Take 1"].exists)
        XCTAssertTrue(app.buttons["jam.layer.mute.4"].exists, "The take's clap is a layer")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Takes46-recorded-take"; shot.lifetime = .keepAlways; add(shot)
        deleteLast.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["jam.layer.mute.4"])], timeout: 5), .completed)
        XCTAssertFalse(app.staticTexts["Take 1"].exists)
        XCTAssertTrue(app.buttons["jam.layer.mute.0"].exists, "The programmed kick is untouched")
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Take 1"].waitForExistence(timeout: 5), "One Undo brings the take back")
    }

    /// U8: a deleted take waits in Recently deleted and comes back in one step.
    @MainActor func testDeletedTakeComesBackFromRecentlyDeleted() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--screen", "jam", "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 15))
        app.buttons["Record drums"].tap()
        XCTAssertTrue(app.staticTexts["REC · DRUMS"].waitForExistence(timeout: 8))
        for _ in 0..<3 { app.buttons["Clap"].tap(); Thread.sleep(forTimeInterval: 0.3) }
        app.buttons["Finish drum take"].tap()
        let deleteLast = app.buttons["jam.takes.delete-last"]
        reveal(deleteLast, in: app)
        deleteLast.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.staticTexts["Take 1"])], timeout: 5), .completed)
        app.staticTexts["studio.tempo"].tap()
        let trash = app.buttons["settings.trash"]
        XCTAssertTrue(trash.waitForExistence(timeout: 5))
        trash.tap()
        let restore = app.buttons["trash.restore.0"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Stage1-recently-deleted"; shot.lifetime = .keepAlways; add(shot)
        restore.tap()
        XCTAssertTrue(app.staticTexts["trash.empty"].waitForExistence(timeout: 5))
        app.buttons["trash.done"].tap()
        let take = app.staticTexts["Take 1"]
        for _ in 0..<10 where !take.exists { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(take.waitForExistence(timeout: 5), "The take is back with its hits")
        XCTAssertTrue(app.buttons["jam.layer.mute.4"].exists)
    }
}
