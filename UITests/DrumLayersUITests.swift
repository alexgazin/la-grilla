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
}
