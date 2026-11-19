import XCTest

/// Build 46: three palettes on the selected section, A/B without editing the
/// project, and Apply as one Undo.
final class PaletteUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 240 }

    @MainActor func testPaletteComparisonIsLevelMatchedAppliesOnceAndUndoes() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--device-output-startup", "--screen", "mixer", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let open = app.buttons["mixer.palettes"]
        XCTAssertTrue(open.waitForExistence(timeout: 20))
        let undo = app.buttons["Undo"]
        let undoInitially = undo.exists && undo.isEnabled
        open.tap()
        XCTAssertTrue(app.navigationBars["Palettes"].waitForExistence(timeout: 10))
        for style in ["boomBap", "westCoast", "atmosphericChillhop"] {
            XCTAssertTrue(app.buttons["palettes.choose.\(style)"].exists, style)
        }
        app.buttons["palettes.choose.boomBap"].tap()
        let level = app.staticTexts["palettes.level"]
        XCTAssertTrue(level.waitForExistence(timeout: 90), "Loudness matching did not finish")
        // "difference +0.3 LU": matched within 1 LU.
        let label = level.label
        let difference = label.components(separatedBy: "difference ").last?.components(separatedBy: " LU").first.flatMap { Double($0) }
        XCTAssertNotNil(difference, label)
        XCTAssertLessThanOrEqual(abs(difference ?? 99), 1.0, label)
        let shot = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        shot.name = "Palettes46-boombap-en"; shot.lifetime = .keepAlways; add(shot)
        // Fast A/B leaves the project untouched.
        let b = app.buttons["palettes.b"], a = app.buttons["palettes.a"]
        for _ in 0..<5 { if !b.isHittable { app.scrollViews["palettes.scroll"].swipeUp() } }
        b.tap(); a.tap(); b.tap()
        let apply = app.buttons["palettes.apply"]
        for _ in 0..<5 { if !apply.isHittable { app.scrollViews["palettes.scroll"].swipeUp() } }
        apply.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        XCTAssertTrue(undo.waitForExistence(timeout: 5) && undo.isEnabled)
        let applied = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        applied.name = "Palettes46-applied-mixer-en"; applied.lifetime = .keepAlways; add(applied)
        undo.tap()
        if !undoInitially { XCTAssertFalse(undo.isEnabled, "Applying a palette must be exactly one Undo step") }
    }
}
