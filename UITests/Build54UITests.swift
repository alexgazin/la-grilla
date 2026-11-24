import XCTest

/// Build 54: track in a minute and social clips, remix links, weekly challenge, harmony course,
/// DAWproject export, audio tracks and AUv3 plugins.
final class Build54UITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 300 }

    @MainActor private func launch(_ screen: String? = "grid", _ extra: [String] = []) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--device-output-startup", "--project-store-id", UUID().uuidString, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
            + (screen.map { ["--screen", $0] } ?? []) + extra
        app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 30))
        return app
    }

    @MainActor private func eventually(_ timeout: TimeInterval = 10, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return condition()
    }

    @MainActor private func any(_ app: XCUIApplication, _ identifier: String) -> XCUIElement { app.descendants(matching: .any)[identifier].firstMatch }

    @MainActor private func command(_ text: String, in app: XCUIApplication) {
        app.buttons["commands.open"].tap()
        let field = app.textFields["commands.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(text + "\n")
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !(element.exists && element.isHittable) { app.swipeUp() }
    }

    @MainActor private func shoot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    // MARK: 2 · Track in a minute and a clip for social

    @MainActor func testTrackInAMinuteMakesAVerseAndChorusAndOffersAClip() {
        let app = launch()
        command("new project", in: app)
        let trap = app.buttons["project.track.trap"]
        XCTAssertTrue(trap.waitForExistence(timeout: 10))
        trap.tap()
        let card = any(app, "quick.card")
        XCTAssertTrue(card.waitForExistence(timeout: 60), "The new track is ready in Grid")
        XCTAssertTrue(app.buttons["Chorus"].firstMatch.exists || any(app, "Chorus").exists, "A verse and a chorus")
        shoot("54-quick-track")
        app.buttons["quick.another"].tap()
        XCTAssertTrue(eventually(60) { app.buttons["quick.another"].isEnabled }, "Another one finishes")
        XCTAssertTrue(app.buttons["Undo"].firstMatch.isEnabled)
        app.buttons["quick.share"].tap()
        XCTAssertTrue(app.navigationBars["Export"].waitForExistence(timeout: 10))
        let summary = any(app, "export.clip-summary")
        XCTAssertTrue(summary.waitForExistence(timeout: 5), "A 15-second clip from the chorus")
        XCTAssertTrue(summary.label.contains("From the chorus"), summary.label)
        XCTAssertTrue(any(app, "export.video-style.1").exists, "Pictures: map, pads, levels")
        XCTAssertTrue(app.switches["export.credit"].exists)
        shoot("54-video-clip")
    }

    // MARK: 7 · Remix link and weekly challenge

    @MainActor func testARemixLinkOpensAsYourVersionWithCredit() {
        let app = launch()
        app.open(URL(string: Self.remixLink)!)
        let title = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'my version'")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 20), "The remix opens as a new song")
        shoot("54-remix-opened")
        command("export", in: app)
        XCTAssertTrue(app.navigationBars["Export"].waitForExistence(timeout: 10))
        let credit = any(app, "remix.credit")
        reveal(credit, in: app)
        XCTAssertTrue(credit.label.contains("Shared groove") && credit.label.contains("Ana"), credit.label)
        XCTAssertTrue(app.buttons["remix.share"].exists, "The licence came with the song, so it can be shared on")
    }

    @MainActor func testRemixSharingAsksForALicenceFirst() {
        let app = launch()
        command("export", in: app)
        XCTAssertTrue(app.navigationBars["Export"].waitForExistence(timeout: 10))
        let allow = app.buttons["remix.allow"]
        reveal(allow, in: app)
        XCTAssertTrue(allow.exists)
        allow.tap()
        let share = app.buttons["remix.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertTrue(any(app, "remix.author").exists)
    }

    @MainActor func testTheWeeklyChallengeIsCheckedOnTheOpenSong() {
        let app = launch()
        command("projects", in: app)
        let card = any(app, "challenge.card")
        reveal(card, in: app)
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(any(app, "challenge.rule.0").exists)
        shoot("54-challenge")
    }

    // MARK: 5 · Harmony course

    @MainActor func testALessonOpensAnExerciseThatTicksOnTheSong() {
        let app = launch()
        command("harmony course", in: app)
        XCTAssertTrue(app.navigationBars["Harmony course"].waitForExistence(timeout: 10))
        let lesson = app.buttons["course.lesson.pop-four"]
        XCTAssertTrue(lesson.waitForExistence(timeout: 5))
        lesson.tap()
        let tryIt = app.buttons["lesson.try"]
        reveal(tryIt, in: app)
        shoot("54-lesson")
        tryIt.tap()
        let card = any(app, "assignment.card")
        XCTAssertTrue(card.waitForExistence(timeout: 15), "The exercise shows on the new song")
        XCTAssertEqual(any(app, "assignment.rule.0").value as? String, "Not yet")
        shoot("54-exercise")
    }

    // MARK: 3 · DAWproject

    @MainActor func testDAWprojectIsAnExportFormat() {
        let app = launch()
        command("export", in: app)
        XCTAssertTrue(app.navigationBars["Export"].waitForExistence(timeout: 10))
        let format = app.buttons["format.dawproject"]
        reveal(format, in: app)
        XCTAssertTrue(format.exists)
        format.tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Cubase 14'")).firstMatch.waitForExistence(timeout: 5))
    }

    // MARK: 4 · Audio tracks

    @MainActor func testATakeSitsOnItsTrackAndMovesByABarInOneUndo() {
        let app = launch("audio-tracks")
        XCTAssertTrue(app.navigationBars["Audio tracks"].waitForExistence(timeout: 20))
        let clip = any(app, "audio.clip.0.0")
        XCTAssertTrue(clip.waitForExistence(timeout: 20), "The take is on the track")
        XCTAssertTrue(app.staticTexts["Bar 1, beat 1"].exists)
        shoot("54-audio-tracks")
        app.buttons["audio.clip-menu.0.0"].tap()
        let later = app.buttons["A bar later"]
        XCTAssertTrue(later.waitForExistence(timeout: 5))
        later.tap()
        XCTAssertTrue(app.staticTexts["Bar 2, beat 1"].waitForExistence(timeout: 5))
        app.buttons["audio.done"].tap()
        XCTAssertTrue(any(app, "grid.audio-track.0").waitForExistence(timeout: 10), "The audio track shows in Grid")
        XCTAssertTrue(app.buttons["Undo"].firstMatch.isEnabled)
        shoot("54-audio-lane")
    }

    // MARK: 8 · Plugins

    @MainActor func testPluginsListInstalledUnitsAndAddAnEffectAfterTheMix() {
        let app = launch("mixer")
        let master = app.buttons["mixer.master-menu"]
        XCTAssertTrue(master.waitForExistence(timeout: 15))
        master.tap()
        let plugins = app.buttons["mixer.plugins"]
        XCTAssertTrue(plugins.waitForExistence(timeout: 5))
        plugins.tap()
        XCTAssertTrue(app.navigationBars["Plugins"].waitForExistence(timeout: 10))
        let add = app.buttons["plugins.add-effect"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        shoot("54-plugins")
        XCTAssertTrue(add.isEnabled, "Apple's effect units are installed on every iPhone")
        add.tap()
        let delay = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'AUDelay'")).firstMatch
        XCTAssertTrue(delay.waitForExistence(timeout: 5), "Apple's delay is offered")
        delay.tap()
        XCTAssertTrue(any(app, "plugins.master.AUDelay").waitForExistence(timeout: 10), "The effect is after the mix")
        XCTAssertTrue(app.buttons["Undo"].firstMatch.isEnabled || app.buttons["plugins.done"].exists)
    }

    @MainActor func testAnInstrumentPluginBouncesATrackToAudio() {
        let app = launch("mixer")
        app.buttons["mixer.master-menu"].tap()
        app.buttons["mixer.plugins"].tap()
        XCTAssertTrue(app.navigationBars["Plugins"].waitForExistence(timeout: 10))
        let instrument = app.buttons["plugins.instrument"]
        XCTAssertTrue(instrument.waitForExistence(timeout: 10))
        instrument.tap()
        let sampler = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'AUSampler'")).firstMatch
        XCTAssertTrue(sampler.waitForExistence(timeout: 5), "Apple's sampler is an instrument unit")
        sampler.tap()
        let bounce = app.buttons["plugins.bounce"]
        XCTAssertTrue(bounce.waitForExistence(timeout: 5))
        XCTAssertTrue(eventually { bounce.isEnabled })
        bounce.tap()
        XCTAssertTrue(app.staticTexts["Bounced tracks"].waitForExistence(timeout: 120), "The track became audio")
        shoot("54-bounce")
    }

    /// The remix link fixture (a four-bar starter shared by "Ana" as "Remix with credit").
    static let remixLink = "lagrilla://remix#AQewIgYQIgOgIgQQbhAgLAIgYhAwOQNhCQZxAwLQMxCQaxDBCQbBAwIgYwYwLQYgeQIhCQbRAwdAcgdQZRCQbhGQUwaAYQcgZQZAIAZwcgbwbwdgZRIAIgcBAwWxAAaBOxAAYxAxAAaQbhNgcgcwaQbxKQOgMBCQcQdQYQbAaQdBHxBBIhCRMwbwdBDAfRCQZBAwMwOANBTQIhWxTBXRQBQgIhRBRhSBShAxZBTxURUxVQIhVwIhWRZgMhXQIhXwOhYRYxCRZhgAMBaBGhahbAZRRxSRSxcRUBUhVBGROBeRAwNRfBfhhBghAwNwNgOBhQLBaQOhQxRRihbhjRThjxdBkhWBNBZgNxlxYBYhZBZgMQMQNQMhhQXRFxAxtgMwNhnxABfgWwWxTRTQMQMAMBuhxALAMgLANwMhygNBnhzBzh0ALAWx0hxgLBxxyR1xTRzRzx0R0x4B1h2B0xxhyByh3x1R4h6x4R1x2R2x2x6R3h1B7x5h7h5R8R6B3Ryx5B7R9h-h0wMR8x_R-SAB_x8B5yBR6iASCB7CCh2h3CDSCR-CDiEQLB_CFCECFiFR8SBCEx9SHh4yHB-yDCIiJSJB9yHyJx_iKSByGCGiKCKyKiAiEh9CLiNCMCFiMiOSNiFyFiICOCOx8R_xugIhGAOhvRvwfSRwcxPySBvANRvhZBSwIgVhpRNxCSTxZyRxZhPBhwOiYCSSSxZBOhTCWxcCTRDxERDhORcBWBGRLAcgbRShHxhhQSYhACZCUxvxCSZyBAIiXBuSbAOgLSbiZxZAchGQZBJQbSTyeBOyRxEChiiCcBeBGQYgYQcykAXQfQ"
}
