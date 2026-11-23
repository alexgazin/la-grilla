import XCTest

/// Musician feedback (build 47): parts, bars and chords are set in a table with ready
/// choices instead of guessing the wording.
final class SongFormTableUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 180 }

    @MainActor func testPartsAreBuiltInATableWithPickedChords() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 15))
        app.buttons["assistant.open"].tap()
        let builder = app.buttons["Build a track"]
        XCTAssertTrue(builder.waitForExistence(timeout: 8))
        builder.tap()

        let table = app.buttons["builder.table"]
        for _ in 0..<8 where !table.isHittable { app.swipeUp() }
        XCTAssertTrue(table.isHittable)
        table.tap()
        let order = app.buttons["builder.order"]
        for _ in 0..<8 where !order.isHittable { app.swipeDown() }
        XCTAssertTrue(order.waitForExistence(timeout: 5))
        XCTAssertTrue(order.label.contains("A · B · A"), order.label)

        // Add a chord to part A by tapping it, not typing it.
        let chords = app.textFields["builder.part.0.chords"]
        XCTAssertTrue(chords.waitForExistence(timeout: 5))
        let before = chords.value as? String ?? ""
        let addChord = app.buttons["builder.part.0.chord.add"]
        for _ in 0..<6 where !addChord.isHittable { app.swipeUp() }
        addChord.tap()
        let choice = app.buttons["Dm"]
        XCTAssertTrue(choice.waitForExistence(timeout: 5), "C major offers its own chords")
        choice.tap()
        XCTAssertEqual(chords.value as? String, before + ", Dm")

        // A third part, then a ready order that uses it.
        let addPart = app.buttons["builder.add-part"]
        for _ in 0..<8 where !addPart.isHittable { app.swipeUp() }
        addPart.tap()
        for _ in 0..<10 where !order.isHittable { app.swipeDown() }
        order.tap()
        let ready = app.buttons["A · B · C · B"]
        XCTAssertTrue(ready.waitForExistence(timeout: 5))
        ready.tap()
        XCTAssertTrue(order.label.contains("A · B · C · B"), order.label)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "SongForm-table"; shot.lifetime = .keepAlways; add(shot)

        let create = app.buttons["builder.create"]
        for _ in 0..<12 where !create.isHittable { app.swipeUp() }
        XCTAssertTrue(create.isEnabled)
        create.tap()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.navigationBars["Build a track"])
        wait(for: [closed], timeout: 25)
    }
}
