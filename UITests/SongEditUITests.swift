import XCTest

/// Build 45: an edit of the open project in plain words, reviewed on screen
/// before applying, auditioned A/B from one place and undone in one step.
final class SongEditUITests: XCTestCase {
    override func setUp() { super.setUp(); continueAfterFailure = false; executionTimeAllowance = 180 }

    @MainActor private func launch(_ language: String) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--device-output-startup", "--screen", "assistant-song-edit",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ru" ? "ru_RU" : "en_US"]
        app.launch()
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 20))
        return app
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 { if element.exists && element.isHittable { return }; app.scrollViews["assistant.review-scroll"].swipeUp() }
        XCTAssertTrue(element.isHittable, "\(element) is not reachable")
    }

    /// Replaces the command text: a tap below the text puts the caret at its end, then the old
    /// text is deleted. A long press for "Select All" is not reliable on the simulator.
    @MainActor private func replaceText(_ input: XCUIElement, with text: String, in app: XCUIApplication) {
        reveal(input, in: app)
        for _ in 0..<3 {
            input.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.95)).tap()
            let focus = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: input)
            guard XCTWaiter.wait(for: [focus], timeout: 3) == .completed else { continue }
            let current = input.value as? String ?? ""
            if current.isEmpty { break }
            input.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
            if (input.value as? String ?? "").isEmpty { break }
        }
        input.typeText(text)
        XCTAssertEqual(input.value as? String, text)
    }

    @MainActor private func capture(_ name: String) {
        let shot = XCTAttachment(data: XCUIScreen.main.screenshot().pngRepresentation, uniformTypeIdentifier: "public.png")
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor private func controlCommandReviewAppliesAsOneUndo(_ language: String) {
        let app = launch(language)
        let first = app.descendants(matching: .any)["assistant.edit.op.0"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["assistant.edit.op.1"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["assistant.edit.op.2"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["assistant.edit.protected"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["assistant.edit.problem.0"].exists)
        capture("SongEdit45-plan-\(language)")
        let cells = app.descendants(matching: .any)["assistant.edit.cells"]
        reveal(cells, in: app)
        let affected = cells.value as? String ?? ""
        XCTAssertFalse(affected.isEmpty)
        XCTAssertEqual(affected.components(separatedBy: ";").count, 1, "Only the drum track is touched: \(affected)")
        capture("SongEdit45-cells-\(language)")
        // A/B from the same place.
        let state = app.staticTexts["assistant.preview-state"]
        let proposal = app.buttons["assistant.b"]; reveal(proposal, in: app); proposal.tap()
        expectation(for: NSPredicate(format: "value == 'Preview' OR value == 'Прослушать'"), evaluatedWith: state)
        waitForExpectations(timeout: 8)
        app.buttons["assistant.a"].tap()
        XCTAssertTrue(app.staticTexts["assistant.edit.window"].exists)
        let apply = app.buttons["assistant.apply"]; reveal(apply, in: app); apply.tap()
        // Back in the studio: exactly one Undo step restores the source.
        let undo = app.buttons["Undo"].exists ? app.buttons["Undo"] : app.buttons["Отменить"]
        XCTAssertTrue(undo.waitForExistence(timeout: 10))
        XCTAssertTrue(undo.isEnabled)
        capture("SongEdit45-applied-\(language)")
        undo.tap()
        XCTAssertFalse(undo.isEnabled, "The whole edit must be one Undo step")
        let redo = app.buttons["Redo"].exists ? app.buttons["Redo"] : app.buttons["Повторить"]
        XCTAssertTrue(redo.isEnabled)
    }

    @MainActor func testControlCommandReviewAuditionApplyAndOneUndoEnglish() { controlCommandReviewAppliesAsOneUndo("en") }
    @MainActor func testControlCommandReviewAuditionApplyAndOneUndoRussian() { controlCommandReviewAppliesAsOneUndo("ru") }

    @MainActor func testTwoChorusesAskWhichOneAndUnsupportedTextIsNamed() {
        let app = launch("en")
        XCTAssertTrue(app.descendants(matching: .any)["assistant.edit.op.0"].waitForExistence(timeout: 15))
        let input = app.textViews["assistant.input"]
        replaceText(input, with: "Add a fill before the chorus", in: app)
        app.buttons["assistant.generate"].tap()
        let second = app.buttons["assistant.edit.choice.1"]
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["assistant.edit.choice.0"].exists)
        XCTAssertFalse(app.buttons["assistant.apply"].exists, "Apply waits for the choice")
        capture("SongEdit45-choice-en")
        reveal(second, in: app); second.tap()
        XCTAssertTrue(app.buttons["assistant.apply"].waitForExistence(timeout: 5))
        // Unsupported wording keeps the draft and names the fragment.
        replaceText(input, with: "Add vocals to the second chorus", in: app)
        app.buttons["assistant.generate"].tap()
        let problem = app.descendants(matching: .any)["assistant.edit.problem.0"]
        XCTAssertTrue(problem.waitForExistence(timeout: 10))
        XCTAssertTrue(problem.label.lowercased().contains("vocals"), problem.label)
        XCTAssertFalse(app.buttons["assistant.apply"].exists)
        XCTAssertEqual(input.value as? String, "Add vocals to the second chorus")
        capture("SongEdit45-problem-en")
    }
}
