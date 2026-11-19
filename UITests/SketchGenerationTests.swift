import XCTest

/// Real local composition, audio, history, store and share UI. No proposal,
/// note array, PCM or model response is injected into either journey.
final class SketchGenerationTests:XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = name.contains("testAndrey") ? 240 : 120
    }

    @MainActor func testEmptyProjectLocalSketchABApplyUndo()throws {
        let app=launch(),transport=app.buttons["perform.transport"]
        let (original,observed)=try createEmptyAndReview(app)
        XCTAssertEqual(state(transport),original)
        XCTAssertFalse(app.buttons["Undo"].isEnabled)
        keepScreenshot("Completion-new-editable-local-sketch-review")
        let a=app.buttons["assistant.a"],b=app.buttons["assistant.b"]
        reveal(a,in:app);a.tap()
        wait(transport){let t=self.current(transport);return t.contains("preview=true") && t.contains("actualPlaying=1") && self.number("outputPeak",in:t)<0.0001}
        XCTAssertEqual(state(transport),original)
        b.tap()
        wait(transport){let t=self.current(transport);return t.contains("preview=true") && self.number("outputPeak",in:t)>0.001}
        XCTAssertEqual(state(transport),original)
        let apply=app.buttons["assistant.apply"];reveal(apply,in:app);apply.tap()
        wait(transport){!app.navigationBars["Assistant"].exists}
        XCTAssertFalse(app.staticTexts["grid.empty-state"].exists)
        let applied=state(transport)
        XCTAssertEqual(applied.id,original.id);XCTAssertGreaterThan(applied.revision,original.revision)
        let chords=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.chord.'"))
        XCTAssertEqual(chords.count,8)
        XCTAssertEqual(number("loopRangeCount",in:current(transport)),8*3840)
        let labels=chords.allElementsBoundByIndex.prefix(4).map(\.label)
        app.buttons["Undo"].tap()
        XCTAssertTrue(app.staticTexts["grid.empty-state"].waitForExistence(timeout:5))
        XCTAssertEqual(number("loopRangeCount",in:current(transport)),4*3840)
        app.buttons["Redo"].tap()
        wait(transport){!app.staticTexts["grid.empty-state"].exists}
        XCTAssertEqual(chords.allElementsBoundByIndex.prefix(4).map(\.label),labels)
        XCTAssertEqual(number("loopRangeCount",in:current(transport)),8*3840)
        keepReport(observed+"\n"+current(transport),name:"Completion-local-sketch-AB-atomic-Undo-Redo")
        keepScreenshot("Completion-generated-sketch-applied")
    }

    @MainActor func testGeneratedSketchReopensWithRealAudioAndMIDIShare()throws {
        let app=launch(),transport=app.buttons["perform.transport"]
        let (original,observed)=try createEmptyAndReview(app)
        let apply=app.buttons["assistant.apply"];reveal(apply,in:app);apply.tap()
        wait(transport){!app.navigationBars["Assistant"].exists}
        let chords=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'grid.chord.'"))
        XCTAssertEqual(chords.count,8)
        XCTAssertEqual(number("loopRangeCount",in:current(transport)),8*3840)
        let labels=chords.allElementsBoundByIndex.prefix(4).map(\.label)
        let saved=app.descendants(matching:.any).matching(NSPredicate(format:"label == 'Saved on this iPhone'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout:8))
        let persisted=state(transport)
        XCTAssertEqual(persisted.id,original.id);XCTAssertGreaterThan(persisted.revision,original.revision)
        app.terminate();app.launch()
        XCTAssertTrue(transport.waitForExistence(timeout:15))
        XCTAssertEqual(state(transport),persisted)
        XCTAssertTrue(app.staticTexts["Untitled"].exists)
        XCTAssertEqual(chords.allElementsBoundByIndex.prefix(4).map(\.label),labels)
        XCTAssertEqual(number("loopRangeCount",in:current(transport)),8*3840)
        app.buttons["Play"].tap()
        wait(transport,timeout:14){let t=self.current(transport);return t.contains("actualPlaying=1") && self.number("outputPeak",in:t)>0.001 && self.number("actualTick",in:t)>4*3840 && self.number("actualTick",in:t)<8*3840}
        app.buttons["Stop"].tap()
        app.buttons["export.open"].tap()
        XCTAssertTrue(app.buttons["format.midi"].waitForExistence(timeout:5))
        app.buttons["export.confirm"].tap()
        let share=app.otherElements["ActivityListView"]
        XCTAssertTrue(share.waitForExistence(timeout:15) || app.buttons["Copy"].exists || app.buttons["Save to Files"].exists || app.staticTexts["Save to Files"].exists)
        XCTAssertFalse(app.staticTexts["export.error"].exists)
        keepReport(observed+"\n"+current(transport),name:"Completion-real-local-sketch-score-and-reopened-runtime")
        keepScreenshot("Completion-generated-sketch-midi-share")
    }

    @MainActor func testOfflineBuilderCreatesTwoSectionBeatFromExample() {
        let app = launch()
        let old = state(app.buttons["perform.transport"])
        app.buttons["assistant.open"].tap()
        let builder = app.buttons["Build a track"]
        XCTAssertTrue(builder.waitForExistence(timeout: 8))
        builder.tap()
        let example = app.buttons["Try a boom-bap arrangement"]
        XCTAssertTrue(example.waitForExistence(timeout: 8))
        example.tap()
        app.buttons["Suggest settings"].tap()
        let feedback = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Local suggestions")).firstMatch
        XCTAssertTrue(feedback.waitForExistence(timeout: 8))
        keepScreenshot("Groove37-offline-builder")
        let save = app.buttons["builder.create"]
        for _ in 0..<10 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable)
        save.tap()
        let transport = app.buttons["perform.transport"]
        XCTAssertTrue(transport.waitForExistence(timeout: 10))
        wait(transport) {
            let next = self.state(transport)
            return !next.id.isEmpty && next.id != old.id
        }
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Intro")).firstMatch.exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format:"label CONTAINS %@", "Hook")).firstMatch.exists)
        keepScreenshot("Groove37-editable-arrangement")
    }

    @MainActor func testWorkoutFormReviewAndCreate() {
        let app = launch()
        let transport = app.buttons["perform.transport"]
        let old = state(transport)
        app.buttons["assistant.open"].tap()
        let builder = app.buttons["Build a track"]
        XCTAssertTrue(builder.waitForExistence(timeout: 8))
        builder.tap()
        let example = app.buttons["Try a workout arrangement"]
        XCTAssertTrue(example.waitForExistence(timeout: 8))
        example.tap()
        app.buttons["Suggest settings"].tap()
        let repeatSource = app.staticTexts["Repeats the source part, including edits."]
        for _ in 0..<10 where !repeatSource.isHittable { app.swipeUp() }
        XCTAssertTrue(repeatSource.isHittable)
        XCTAssertTrue(app.staticTexts["25–32"].exists)
        keepScreenshot("SongForm39-workout-review")
        let save = app.buttons["builder.create"]
        for _ in 0..<10 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable)
        save.tap()
        wait(transport, timeout: 12) {
            self.state(transport).id != old.id && self.number("loopRangeCount", in: self.current(transport)) == 32*3840
        }
        keepScreenshot("SongForm39-workout-project")
    }

    @MainActor func testAndreyWorkoutCreatesAndReopens() throws {
        try reviewOriginalBrief("workout", promptTerms: ["трениров", "16 тактов", "возвращаемся"], bars: [8, 16, 8])
    }

    @MainActor func testAndreyChillhopCreatesAndReopens() throws {
        try reviewOriginalBrief("chillhop", promptTerms: ["chillhop", "90", "гонг"], bars: [1, 16, 8, 1])
    }

    @MainActor func testAndreyAmbientCreatesAndReopens() throws {
        try reviewOriginalBrief("ambient", promptTerms: ["медитац", "бансури", "клавиш"], bars: [8, 8, 8])
    }

    @MainActor private func reviewOriginalBrief(_ name: String, promptTerms: [String], bars: [Int]) throws {
        let app = launch(language: "ru")
        let transport = app.buttons["perform.transport"]
        let original = state(transport)
        XCTAssertFalse(original.id.isEmpty)
        app.buttons["assistant.open"].tap()
        let examples = app.buttons["assistant.examples"]
        XCTAssertTrue(examples.waitForExistence(timeout: 8))
        examples.tap()
        let example = app.buttons["assistant.example." + name]
        revealInList(example, app: app)
        example.tap()
        let input = try XCTUnwrap(app.textViews["assistant.input"].value as? String).lowercased()
        for term in promptTerms { XCTAssertTrue(input.contains(term), input) }
        let generate = app.buttons["assistant.generate"]
        revealInList(generate, app: app)
        generate.tap()

        let expectedHarmony: [Int: [String]]
        let inheritance: Set<Int>
        switch name {
        case "chillhop":
            expectedHarmony = [1: ["C","D","B","E"], 2: ["C","D","B","E"]]
            inheritance = [2]
        case "ambient":
            let cycle = ["C","Bb","G","Ab"]
            expectedHarmony = [0: cycle, 1: cycle, 2: cycle]
            inheritance = [1, 2]
        default:
            expectedHarmony = [0: ["A","Bb","C","D"], 1: ["D","E","F","G"]]
            inheritance = []
        }
        var first = 1
        for (index, count) in bars.enumerated() {
            let range = app.staticTexts["builder.part.\(index).range"]
            revealInList(range, app: app)
            let end = first + count - 1
            XCTAssertTrue(range.label.contains("\(first)–\(end)") || (count == 1 && range.label == String(first)), range.label)
            if let expected = expectedHarmony[index] {
                let id = "builder.part.\(index).chords"
                let chords = inheritance.contains(index) ? app.staticTexts[id] : app.textFields[id]
                revealInList(chords, app: app)
                let spelling = (chords.value as? String ?? chords.label).replacingOccurrences(of: "♭", with: "b")
                let symbols = spelling.split { !($0.isLetter || $0.isNumber || $0 == "#") }.map(String.init)
                XCTAssertEqual(symbols, expected, spelling)
                if inheritance.contains(index) {
                    XCTAssertTrue(app.staticTexts["builder.part.\(index).inheritance"].exists)
                }
            }
            first = end + 1
        }
        keepScreenshot("Andrey41-" + name + "-plan")

        let preview = app.buttons["builder.preview"]
        revealInList(preview, app: app)
        let idleLabel = preview.label
        XCTAssertTrue(preview.isEnabled)
        preview.tap()
        wait(preview, timeout: 30) { preview.isEnabled && preview.label != idleLabel }
        preview.tap()
        wait(preview) { preview.label == idleLabel }
        let save = app.buttons["builder.create"]
        revealInList(save, app: app)
        save.tap()
        XCTAssertTrue(transport.waitForExistence(timeout: 25))
        let ticks = Double(bars.reduce(0, +) * 3840)
        wait(transport, timeout: 20) {
            let saved = self.state(transport)
            return !saved.id.isEmpty && saved.id != original.id && self.number("loopRangeCount", in: self.current(transport)) == ticks
        }
        let saved = state(transport)
        let loopMode = name == "workout" ? "true" : "false"
        XCTAssertEqual(field("loopEnabled", in: current(transport)), loopMode)
        keepScreenshot("Andrey41-" + name + "-grid")
        app.terminate()
        app.launch()
        XCTAssertTrue(transport.waitForExistence(timeout: 20))
        wait(transport) { self.state(transport) == saved && self.number("loopRangeCount", in: self.current(transport)) == ticks }
        XCTAssertEqual(field("loopEnabled", in: current(transport)), loopMode)
        if name == "chillhop" {
            app.buttons["assistant.open"].tap()
            let editPlan = app.buttons["assistant.edit-saved-arrangement"]
            XCTAssertTrue(editPlan.waitForExistence(timeout: 8))
            editPlan.tap()
            let idea = app.descendants(matching: .any).matching(identifier: "builder.idea").firstMatch
            XCTAssertTrue(idea.waitForExistence(timeout: 8))
            XCTAssertEqual((idea.value as? String)?.lowercased(), input)
            let inherited = app.staticTexts["builder.part.2.inheritance"]
            revealInList(inherited, app: app)
            app.navigationBars.buttons["Отмена"].tap()
            wait(transport) { self.state(transport) == saved }
        }
        app.buttons["Играть"].tap()
        wait(transport, timeout: 14) {
            let trace = self.current(transport)
            return trace.contains("actualPlaying=1") && self.number("outputPeak", in: trace) > 0.001
        }
        keepReport(input + "\n" + current(transport), name: "Andrey41-" + name + "-reopened-playback")
        app.buttons["Стоп"].tap()

        if name != "workout" {
            app.buttons["Микшер"].tap()
            let selectors = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sound.track."))
            XCTAssertTrue(selectors.firstMatch.waitForExistence(timeout: 6))
            let required = name == "chillhop"
                ? [["пианино", "piano"], ["флейт", "flute"], ["гонг", "gong"]]
                : [["пианино", "piano"], ["бансури", "bansuri"]]
            var names = Set<String>()
            for attempt in 0..<8 {
                for button in selectors.allElementsBoundByIndex {
                    if let sound = button.value as? String { names.insert(sound.lowercased()) }
                }
                if required.allSatisfy({ aliases in names.contains { sound in aliases.contains(where: sound.contains) } }) { break }
                if attempt < 7 {
                    let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.62, dy: 0.36))
                    let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.36))
                    from.press(forDuration: 0.02, thenDragTo: to)
                }
            }
            for aliases in required {
                XCTAssertTrue(names.contains { sound in aliases.contains(where: sound.contains) }, "Missing \(aliases) from mixer sample assignments \(names)")
            }
            keepReport(names.sorted().joined(separator: "\n"), name: "Andrey41-" + name + "-reopened-instruments")
        }
    }

    @MainActor func testChangingReviewedTextRequiresNewInterpretation() {
        let app = launch()
        app.buttons["assistant.open"].tap()
        app.buttons["Build a track"].tap()
        let example = app.buttons["builder.example.workout"]
        revealInList(example, app: app)
        example.tap()
        app.buttons["builder.suggest"].tap()
        let idea = app.descendants(matching: .any).matching(identifier: "builder.idea").firstMatch
        XCTAssertTrue(idea.waitForExistence(timeout: 8))
        idea.tap()
        idea.typeText(" at 111 BPM")
        XCTAssertTrue(app.buttons["builder.suggest"].isEnabled)
        XCTAssertTrue(app.staticTexts["builder.unreviewed"].exists)
        // Begin the drag above the software keyboard so the Form dismisses it.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.55))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.25))
        start.press(forDuration: 0.02, thenDragTo: end)
        let create = app.buttons["builder.create"]
        for _ in 0..<14 where !create.exists { app.swipeUp() }
        XCTAssertTrue(create.exists)
        XCTAssertFalse(create.isEnabled)
        XCTAssertFalse(app.buttons["builder.preview"].isEnabled)
    }

    @MainActor private func revealInList(_ element: XCUIElement, app: XCUIApplication) {
        for _ in 0..<22 {
            if element.exists && element.isHittable { return }
            // A short, slow drag keeps adjacent rows visible across scrolls,
            // including cards materialized lazily by the native SwiftUI Form.
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.72))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.42))
            start.press(forDuration: 0.02, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.05)
        }
        XCTFail("Could not reach \(element.debugDescription)")
    }

    @MainActor private func launch(language: String = "en")->XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--runtime-trace","--device-output-startup","--project-store-id",UUID().uuidString,"--appearance","dark","-AppleLanguages","(\(language))","-AppleLocale",language == "ru" ? "ru_RU" : "en_US"]
        app.launch();XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:15))
        return app
    }
    @MainActor private func createEmptyAndReview(_ app:XCUIApplication)throws->(State,String) {
        app.buttons["Projects"].tap()
        XCTAssertTrue(app.buttons["project.new"].waitForExistence(timeout:5));app.buttons["project.new"].tap()
        XCTAssertTrue(app.buttons["project.template.empty"].waitForExistence(timeout:5))
        XCTAssertTrue(app.buttons["project.template.empty"].isSelected)
        app.buttons["project.create"].tap()
        XCTAssertTrue(app.staticTexts["grid.empty-state"].waitForExistence(timeout:5))
        let original=state(app.buttons["perform.transport"])
        XCTAssertFalse(original.id.isEmpty);XCTAssertGreaterThanOrEqual(original.revision,0)
        app.buttons["assistant.open"].tap()
        XCTAssertTrue(app.buttons["assistant.examples"].waitForExistence(timeout:5));app.buttons["assistant.examples"].tap()
        let example=app.buttons["assistant.example.sketch"]
        XCTAssertTrue(example.waitForExistence(timeout:5));example.tap()
        let generate=app.buttons["assistant.generate"];reveal(generate,in:app);generate.tap()
        let parts=app.staticTexts["assistant.sketch.parts"]
        XCTAssertTrue(parts.waitForExistence(timeout:8));reveal(parts,in:app)
        let observed=try XCTUnwrap(parts.value as? String)
        let facts=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(observed.utf8)) as? [String:Any])
        XCTAssertEqual(facts["style"] as? String,"house")
        XCTAssertEqual(facts["bars"] as? Int,8);XCTAssertEqual(facts["seed"] as? Int,42)
        XCTAssertEqual(facts["modelInterpretedParameters"] as? Bool,false)
        for role in ["chords","drums","bass","melody"]{XCTAssertGreaterThan(facts[role] as? Int ?? 0,0,role)}
        XCTAssertTrue(app.staticTexts["LOCAL"].exists);XCTAssertFalse(app.staticTexts["ON-DEVICE AI"].exists)
        return (original,observed)
    }
    private struct State:Equatable{let id:String;let revision:Int}
    @MainActor private func state(_ transport:XCUIElement)->State{let t=current(transport);return State(id:field("project",in:t) ?? "",revision:Int(field("revision",in:t) ?? "") ?? -1)}
    @MainActor private func current(_ transport:XCUIElement)->String{(transport.value as? String ?? "").components(separatedBy:"\n").first ?? ""}
    private func field(_ key:String,in report:String)->String?{report.split(separator:" ").first(where:{$0.hasPrefix(key+"=")}).map{String($0.dropFirst(key.count+1))}}
    private func number(_ key:String,in report:String)->Double{Double(field(key,in:report) ?? "") ?? -1}
    @MainActor private func reveal(_ element:XCUIElement,in app:XCUIApplication){for _ in 0..<10{if element.isHittable{return};app.scrollViews.firstMatch.swipeUp()};XCTAssertTrue(element.isHittable)}
    @MainActor private func wait(_ element:XCUIElement,timeout:TimeInterval=8,condition:()->Bool){let deadline=Date().addingTimeInterval(timeout);repeat{if condition(){return};RunLoop.current.run(until:Date().addingTimeInterval(0.1))}while Date()<deadline;XCTFail("Condition not reached: \(element.debugDescription)")}
    @MainActor private func keepScreenshot(_ name:String){let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)}
    private func keepReport(_ report:String,name:String){let receipt=XCTAttachment(string:report);receipt.name=name;receipt.lifetime = .keepAlways;add(receipt)}
}
