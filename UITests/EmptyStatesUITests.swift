import XCTest

/// U12: empty screens suggest how to start.
final class EmptyStatesUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 120 }

    @MainActor private func launch(_ screen: String) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--screen", screen, "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        return app
    }

    @MainActor func testEmptyBeatOffersStepsAndDisappearsWithTheFirstHit() {
        let app = launch("empty-jam")
        let card = app.descendants(matching: .any)["empty.jam"]
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["empty.jam.0"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Stage1-empty-jam"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["empty.jam.1"].tap()
        let lanes = app.descendants(matching: .any)["jam.lanes"]
        XCTAssertTrue(lanes.waitForExistence(timeout: 5), "Steps show the lanes")
        app.buttons["jam.step.0"].firstMatch.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: card)], timeout: 5), .completed)
    }

    @MainActor func testEmptyPartOffersHumToMIDI() {
        let app = launch("empty-notes")
        let hum = app.buttons["empty.notes.0"]
        XCTAssertTrue(hum.waitForExistence(timeout: 15))
        hum.tap()
        XCTAssertTrue(app.navigationBars["Voice to MIDI"].waitForExistence(timeout: 8))
    }
}
