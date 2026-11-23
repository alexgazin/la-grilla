import XCTest

/// Stage 3: fills, variations and structure templates.
final class StageThreeUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 150 }

    @MainActor private func launch(_ screen: String) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--screen", screen, "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 15))
        return app
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 { if element.exists && element.isHittable { return }; app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    @MainActor func testFillIsItsOwnTakeAndOneUndoRemovesIt() {
        let app = launch("jam")
        let tools = app.buttons["jam.beat-tools"]
        reveal(tools, in: app)
        tools.tap()
        app.buttons["Add a fill at the end"].tap()
        app.buttons["Tom run"].tap()
        let fill = app.staticTexts["Fill 1"]
        reveal(fill, in: app)
        XCTAssertTrue(fill.exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Stage3-fill-take"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Undo"].firstMatch.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: fill)], timeout: 5), .completed)
    }

    @MainActor func testVariationIsHeardThenAppliedWithOneUndo() {
        let app = launch("jam")
        let tools = app.buttons["jam.beat-tools"]
        reveal(tools, in: app)
        tools.tap()
        app.buttons["Variations of this beat…"].tap()
        let card = app.buttons["variations.card.0"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        let play = app.buttons["variations.play"]
        XCTAssertTrue(play.waitForExistence(timeout: 3))
        play.tap()
        XCTAssertEqual(play.label, "Stop")
        app.buttons["variations.listen.0"].tap()
        XCTAssertEqual(play.label, "Stop", "Switching to the original keeps playing")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Stage3-variations"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["variations.apply"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: card)], timeout: 5), .completed)
        XCTAssertTrue(app.buttons["Undo"].firstMatch.isEnabled)
    }

    @MainActor func testTemplateAddsTheSectionsAfterTheMusic() {
        let app = launch("grid")
        app.buttons["sections.open"].tap()
        let open = app.buttons["form.open"]
        reveal(open, in: app)
        open.tap()
        let short = app.buttons["form.template.4"]
        reveal(short, in: app)
        short.tap()
        XCTAssertTrue(app.buttons["form.open"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["16 bars"].waitForExistence(timeout: 5), "4 sections of 4 bars")
    }
}
