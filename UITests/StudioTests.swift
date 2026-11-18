import XCTest
import UIKit
final class StudioTests: XCTestCase {
    override func setUp(){super.setUp();continueAfterFailure=false;executionTimeAllowance=120}
    @MainActor func launch(_ screen: String = "grid") -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--uitesting","--screen",screen,"-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:15));waitForOrientation(app,landscape:false);return app
    }
    @MainActor func waitForOrientation(_ app:XCUIApplication,landscape:Bool){
        let deadline=Date().addingTimeInterval(8)
        while Date()<deadline {
            let frame=app.windows.firstMatch.frame
            if frame.width>0,frame.height>0,(frame.width>frame.height)==landscape{return}
            Thread.sleep(forTimeInterval:0.1)
        }
        XCTFail("The application window did not finish rotating")
    }
    @MainActor func testBackgroundPlaybackAndStoppedReturn() {
        let app=launch();app.buttons["Play"].tap();XCTAssertTrue(app.staticTexts["PLAYING"].waitForExistence(timeout:5))
        XCUIDevice.shared.press(.home);Thread.sleep(forTimeInterval:2);app.activate()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout:10));app.buttons["Stop"].tap()
        XCUIDevice.shared.press(.home);Thread.sleep(forTimeInterval:1);app.activate()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout:10));XCTAssertTrue(app.staticTexts["STOPPED"].exists)
        app.buttons["Play"].tap();XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout:5));app.buttons["Stop"].tap()
    }
    @MainActor func testWelcomeCanBeSkippedAndReopenedWithoutRepeatingOnLaunch() {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--respect-welcome","--show-welcome","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["welcome.title"].waitForExistence(timeout:15))
        XCTAssertTrue(app.buttons["welcome.skip"].isHittable)
        let welcomeShot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());welcomeShot.name="ProfessionalShell-welcome";welcomeShot.lifetime = .keepAlways;add(welcomeShot)
        app.buttons["welcome.skip"].tap()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:5))
        app.terminate();app.launchArguments.removeAll{$0=="--show-welcome"};app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:15))
        XCTAssertFalse(app.staticTexts["welcome.title"].waitForExistence(timeout:2),"A completed first session guide must not block the returning studio")
        app.buttons["tools.more"].tap();app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
        let help=app.buttons["settings.help"]
        let scroll=app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch:app.tables.firstMatch.exists ? app.tables.firstMatch:app.scrollViews.firstMatch
        reveal(help,in:scroll);XCTAssertTrue(help.isHittable);help.tap()
        XCTAssertTrue(app.staticTexts["welcome.title"].waitForExistence(timeout:5))
        app.buttons["welcome.skip"].tap()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:5))
    }
    @MainActor func testAppThemePersistsAndSystemSettingsEntryIsReachable() {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication()
        app.launchArguments=["--uitesting","--respect-appearance","-AppleLanguages","(en)","-AppleLocale","en_US"]
        app.launch();XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:15))
        app.buttons["tools.more"].tap();app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout:5))
        let theme=app.buttons["settings.theme"]
        XCTAssertTrue(theme.waitForExistence(timeout:5));theme.tap();app.buttons["Light"].tap()
        waitForSettingsTheme(theme,light:true)
        XCTAssertTrue(app.buttons["settings.system"].isHittable)
        let shot=XCTAttachment(data:XCUIScreen.main.screenshot().pngRepresentation,uniformTypeIdentifier:"public.png");shot.name="ProfessionalShell-settings-light";shot.lifetime = .keepAlways;add(shot)
        app.terminate();app.launch()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout:15))
        app.buttons["tools.more"].tap();app.buttons["Settings"].tap()
        XCTAssertTrue(theme.waitForExistence(timeout:5))
        XCTAssertTrue(theme.label.contains("Light") || (theme.value as? String)=="Light","Theme selection must survive relaunch")
        waitForSettingsTheme(theme,light:true)
        theme.tap();app.buttons["Dark"].tap()
        waitForSettingsTheme(theme,light:false)
        let darkShot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());darkShot.name="ProfessionalShell-settings-dark";darkShot.lifetime = .keepAlways;add(darkShot)
        app.buttons["Done"].tap()
    }
    /// A selected Picker value can update before its presented Form has adopted
    /// the requested appearance. Check rendered cell pixels, not the stored
    /// preference, before preserving a light/dark screenshot. A persistent modal
    /// trait mismatch fails instead of being accepted after a fixed sleep.
    @MainActor private func waitForSettingsTheme(_ element:XCUIElement,light:Bool) {
        let deadline=Date().addingTimeInterval(5)
        var matchingSamples=0
        var lastLuma:Double?
        var lastScreenshot:XCUIScreenshot?
        repeat {
            let shot=element.screenshot();lastScreenshot=shot
            if let luma=backgroundLuma(shot) {
                lastLuma=luma
                matchingSamples = (light ? luma>0.72:luma<0.28) ? matchingSamples+1:0
                if matchingSamples>=2{return}
            } else {matchingSamples=0}
            Thread.sleep(forTimeInterval:0.15)
        } while Date()<deadline
        if let lastScreenshot {
            let shot=XCTAttachment(screenshot:lastScreenshot)
            shot.name=light ? "ProfessionalShell-theme-unsettled-light":"ProfessionalShell-theme-unsettled-dark"
            shot.lifetime = .keepAlways;add(shot)
        }
        XCTFail("The presented Settings row did not adopt \(light ? "light":"dark") appearance; median rendered luminance=\(lastLuma.map(String.init(describing:)) ?? "unreadable")")
    }
    @MainActor private func backgroundLuma(_ screenshot:XCUIScreenshot)->Double? {
        guard let image=UIImage(data:screenshot.pngRepresentation)?.cgImage else{return nil}
        let width=40,height=20
        var pixels=[UInt8](repeating:0,count:width*height*4)
        let rendered=pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context=CGContext(data:bytes.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue|CGBitmapInfo.byteOrder32Big.rawValue)else{return false}
            context.interpolationQuality = .low
            context.draw(image,in:CGRect(x:0,y:0,width:CGFloat(width),height:CGFloat(height)))
            return true
        }
        guard rendered else{return nil}
        // Background occupies most of a normal Form row; the median ignores
        // text/checkmarks and remains independent of exact font/glyph geometry.
        var values:[Double]=[]
        values.reserveCapacity(width*height)
        for offset in stride(from:0,to:pixels.count,by:4) {
            let red=Double(pixels[offset])/255.0
            let green=Double(pixels[offset+1])/255.0
            let blue=Double(pixels[offset+2])/255.0
            let luminance:Double=0.2126*red+0.7152*green+0.0722*blue
            values.append(luminance)
        }
        values.sort()
        return values[values.count/2]
    }
    @MainActor func testRussianInterfaceAndLightAppearance() {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--uitesting","--screen","grid","--appearance","light","-AppleLanguages","(ru)","-AppleLocale","ru_RU"];app.launch()
        XCTAssertTrue(app.buttons["Сетка"].waitForExistence(timeout:15));app.buttons["export.open"].tap()
        XCTAssertTrue(app.navigationBars["Экспорт"].waitForExistence(timeout:5));XCTAssertTrue(app.buttons["Отмена"].exists)
        let shot=XCTAttachment(data:XCUIScreen.main.screenshot().pngRepresentation,uniformTypeIdentifier:"public.png");shot.name="OriginalVision-qa-russian-light-export";shot.lifetime = .keepAlways;add(shot)
        app.buttons["Отмена"].tap();app.buttons["Джем"].tap()
        for title in ["Пэды","Шаги"]{assertMinimumTouchDimension(app.buttons[title].frame.height)}
        let guide=app.buttons["jam.recording-guide"]
        for _ in 0..<5 {if guide.isHittable{break};app.scrollViews.firstMatch.swipeUp()}
        XCTAssertTrue(guide.exists);assertMinimumTouchDimension(guide.frame.height);XCTAssertEqual(guide.value as? String,"Свёрнуто")
        // Tap the row's center, including its empty spacer, as a finger would.
        guide.tap();XCTAssertEqual(guide.value as? String,"Развёрнуто")
        let hint=app.staticTexts["Сыграй свой собственный ритм."]
        for _ in 0..<4 {if hint.isHittable{break};app.scrollViews.firstMatch.swipeUp()}
        XCTAssertTrue(hint.waitForExistence(timeout:5))
        for _ in 0..<4 {if app.staticTexts["Создавай бит слой за слоем."].isHittable{break};app.scrollViews.firstMatch.swipeUp()}
        XCTAssertTrue(app.staticTexts["Создавай бит слой за слоем."].exists)
        XCTAssertFalse(app.staticTexts["Play something only you would."].exists)
        XCTAssertFalse(app.staticTexts["Build your beat, layer by layer."].exists)
        for _ in 0..<4 {if guide.isHittable{break};app.scrollViews.firstMatch.swipeDown()}
        guide.tap();XCTAssertEqual(guide.value as? String,"Свёрнуто");XCTAssertFalse(hint.exists)
        let scroll=app.scrollViews.firstMatch
        let steps=app.buttons["Шаги"];reveal(steps,in:scroll,up:false);steps.tap()
        let step=app.buttons["jam.step.0"];reveal(step,in:scroll)
        XCTAssertEqual(step.label,"Шаг 1");assertMinimumTouchDimension(step.frame.height)
        let original=step.value as? String
        XCTAssertTrue(original=="Вкл." || original=="Выкл.")
        let undo=app.buttons["Отменить"];XCTAssertFalse(undo.isEnabled)
        step.tap()
        let changed=original=="Вкл." ? "Выкл.":"Вкл."
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@",changed),object:step)],timeout:5),.completed)
        XCTAssertTrue(undo.isEnabled);undo.tap()
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate(format:"value == %@",original ?? ""),object:step)],timeout:5),.completed)
        XCTAssertFalse(undo.isEnabled)
        app.buttons["Микшер"].tap()
        let reset=app.buttons["mixer.reset.0"]
        XCTAssertTrue(reset.waitForExistence(timeout:5));reveal(reset,in:app.scrollViews.firstMatch)
        XCTAssertTrue(reset.label.contains("децибела"));XCTAssertTrue(reset.label.contains("Нажми для сброса."))
        XCTAssertFalse(reset.label.contains("decibels"));XCTAssertFalse(reset.label.contains("Tap to reset"))
        assertMinimumTouchDimension(reset.frame.height)
    }
    @MainActor func testLargeTypeMixerAndAccessibleNoteList() throws {
        XCUIDevice.shared.orientation = .portrait
        let app=XCUIApplication();app.launchArguments=["--uitesting","--screen","notes","--large-type","-AppleLanguages","(en)","-AppleLocale","en_US"];app.launch()
        XCTAssertTrue(app.navigationBars["Piano roll"].waitForExistence(timeout:15));XCTAssertTrue(app.descendants(matching:.any)["notes.list"].waitForExistence(timeout:5))
        let track=app.buttons["notes.tracks"],section=app.buttons["notes.section"]
        XCTAssertTrue(track.waitForExistence(timeout:5));XCTAssertTrue(section.waitForExistence(timeout:5))
        XCTAssertTrue(track.label.contains("Melody"));XCTAssertTrue(section.label.contains("Verse") || (section.value as? String)?.contains("Verse")==true)
        assertMinimumTouchDimension(track.frame.height)
        XCTAssertGreaterThanOrEqual(section.frame.minY,track.frame.maxY,"Accessibility-size track and section controls must occupy separate rows")
        let row=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH 'notes.row.'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout:5));XCTAssertTrue(row.isHittable)
        XCTAssertTrue(row.label.contains("G5"));XCTAssertTrue(row.label.contains("960 ticks"));XCTAssertTrue(row.label.contains("v100"))
        XCTAssertGreaterThanOrEqual(row.frame.height,88,"Large-type note rows must reserve height for pitch and wrapped metadata")
        let shot=XCTAttachment(data:XCUIScreen.main.screenshot().pngRepresentation,uniformTypeIdentifier:"public.png");shot.name="OriginalVision-qa-large-type-piano-roll";shot.lifetime = .keepAlways;add(shot)
        app.buttons["Done"].tap();app.buttons["Mixer"].tap();XCTAssertTrue(app.sliders["Gain Harmony"].waitForExistence(timeout:5))
        try app.performAccessibilityAudit(for:[.sufficientElementDescription])
    }
    @MainActor func testLandscapeKeepsPadsAndTransportReachable() {
        let app=launch();XCUIDevice.shared.orientation = .landscapeLeft;defer{XCUIDevice.shared.orientation = .portrait}
        waitForOrientation(app,landscape:true);app.buttons["Jam"].tap()
        let deadline=Date().addingTimeInterval(8)
        while Date()<deadline && (!app.buttons["Play"].isHittable || !app.buttons["Kick"].isHittable){Thread.sleep(forTimeInterval:0.1)}
        XCTAssertTrue(app.buttons["Play"].isHittable);XCTAssertTrue(app.buttons["Kick"].isHittable);app.buttons["Kick"].tap()
        let shot=XCTAttachment(data:XCUIScreen.main.screenshot().pngRepresentation,uniformTypeIdentifier:"public.png");shot.name="OriginalVision-qa-landscape-jam";shot.lifetime = .keepAlways;add(shot)
        app.buttons["Play"].tap();XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout:5));app.buttons["Stop"].tap()
    }
    @MainActor func testVirtualMIDILearnAndActualOutputDestination() {
        let app=launch("midi");guard app.staticTexts["midi.fixture"].waitForExistence(timeout:15)else{let shot=XCTAttachment(data:XCUIScreen.main.screenshot().pngRepresentation,uniformTypeIdentifier:"public.png");shot.name="R7-midi-error";shot.lifetime = .keepAlways;add(shot);let error=app.staticTexts["midi.error"];XCTFail("Virtual MIDI setup: "+(error.exists ? error.label:app.debugDescription));return}
        let form=app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch:app.tables.firstMatch.exists ? app.tables.firstMatch:app.scrollViews.firstMatch
        reveal(app.buttons["midi.learn"],in:form);app.buttons["midi.learn"].tap()
        reveal(app.buttons["midi.send-fixture"],in:form);app.buttons["midi.send-fixture"].tap()
        XCTAssertTrue(app.staticTexts["Ch 1 · CC 74"].waitForExistence(timeout:8))
        reveal(app.staticTexts["midi.last"],in:form);XCTAssertTrue(app.staticTexts["midi.last"].label.contains("CC 74"))
        let received=app.staticTexts["midi.fixture-received"]
        reveal(received,in:form,up:false);XCTAssertGreaterThan(Int(received.label) ?? 0,0)
        reveal(app.buttons["midi.panic"],in:form);app.buttons["midi.panic"].tap()
        app.buttons["Done"].tap();XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout:5))
    }
    @MainActor private func reveal(_ element:XCUIElement,in scroll:XCUIElement,up:Bool=true){
        // Form rows are virtualized. Scroll only the form and stop when the
        // target is reachable; an application-wide downward swipe can dismiss
        // the sheet before a row has been measured.
        for _ in 0..<8{
            if element.exists && element.isHittable{return}
            if up{scroll.swipeUp()}else{scroll.swipeDown()}
        }
        XCTAssertTrue(element.exists,"Expected the requested MIDI form row")
        XCTAssertTrue(element.isHittable,"Expected the MIDI form row to be reachable")
    }
    @MainActor func testPerformRecordingSurvivesNavigationAndReplays() {
        let app=launch("perform")
        XCTAssertTrue(app.buttons["perform.record"].waitForExistence(timeout:5));app.buttons["perform.record"].tap()
        XCTAssertTrue(app.staticTexts["perform.mode"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["perform.mode"].label,"RECORDING")
        app.buttons["perform.section.Chorus"].tap()
        app.buttons["perform.done"].tap();app.buttons["Jam"].tap();app.buttons["Kick"].tap()
        app.buttons["perform.transport"].tap();XCTAssertTrue(app.buttons["perform.record"].waitForExistence(timeout:5));app.buttons["perform.record"].tap()
        let replay=app.buttons["perform.replay"]
        for _ in 0..<6 {if replay.isHittable{break};app.scrollViews.firstMatch.swipeUp()}
        XCTAssertTrue(app.staticTexts["perform.saved"].waitForExistence(timeout:5));replay.tap()
        let mode=app.staticTexts["perform.mode"]
        // Stop at the header: another downward swipe at the top dismisses the sheet.
        for _ in 0..<6 {if mode.isHittable{break};app.scrollViews.firstMatch.swipeDown()}
        XCTAssertTrue(mode.waitForExistence(timeout:5));XCTAssertEqual(mode.label,"TAKE REPLAY")
        app.buttons["perform.panic"].tap();app.buttons["perform.done"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout:5))
    }
    @MainActor func testFinitePerformanceWAVExportOffersShare() {
        let app=launch("perform-export")
        XCTAssertTrue(app.staticTexts["Export your performance."].waitForExistence(timeout:12))
        XCTAssertFalse(app.buttons["format.stems"].exists);app.buttons["export.confirm"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout:20) || app.buttons["Copy"].exists || app.staticTexts["Save to Files"].exists)
    }
    @MainActor func testSavedPerformanceCreatesEditableSong() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--screen", "perform", "--project-store-id", UUID().uuidString,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch(); defer { app.terminate() }
        let record = app.buttons["perform.record"]
        XCTAssertTrue(record.waitForExistence(timeout: 15)); record.tap()
        let recording = app.staticTexts.matching(NSPredicate(format: "identifier == 'perform.mode' AND label == 'RECORDING'")).firstMatch
        XCTAssertTrue(recording.waitForExistence(timeout: 8))
        app.buttons["perform.section.Chorus"].tap()
        app.buttons["perform.play"].tap()
        let created = app.buttons["perform.create-song"]
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<5 {
            if created.isHittable { break }
            scroll.swipeUp()
        }
        XCTAssertTrue(created.isHittable)
        created.tap()
        let song = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS '· Live'")).firstMatch
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["sections.open"].waitForExistence(timeout: 8))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Release31-editable-live-song"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Projects"].tap()
        XCTAssertTrue(app.staticTexts["First light"].waitForExistence(timeout: 5))
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
        app.buttons["Show note list"].tap();XCTAssertTrue(app.descendants(matching:.any)["notes.list"].waitForExistence(timeout:5))
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
        let input=app.textViews["assistant.input"];XCTAssertTrue(input.waitForExistence(timeout:5));input.tap();input.typeText("tempo 110");app.swipeUp();app.buttons["assistant.generate"].tap();app.swipeUp()
        XCTAssertTrue(app.buttons["assistant.apply"].waitForExistence(timeout:5));app.buttons["assistant.apply"].tap()
        let tempo=app.staticTexts["studio.tempo"]
        XCTAssertTrue(tempo.waitForExistence(timeout:5));XCTAssertEqual(tempo.label,"110 BPM")
        app.buttons["Undo"].tap();XCTAssertEqual(tempo.label,"120 BPM")
    }
    @MainActor func testAssistantAmbiguityKeepsMusicUnchangedUntilApply() {
        let app=launch();app.buttons["assistant.open"].tap();let input=app.textViews["assistant.input"];XCTAssertTrue(input.waitForExistence(timeout:5));input.tap();input.typeText("Am F");app.swipeUp();app.buttons["assistant.generate"].tap();app.swipeUp()
        XCTAssertTrue(app.buttons["Stretch chords evenly"].waitForExistence(timeout:5));XCTAssertFalse(app.buttons["assistant.apply"].exists)
        app.buttons["Stretch chords evenly"].tap();app.swipeUp();XCTAssertTrue(app.buttons["assistant.apply"].exists)
        app.buttons["Cancel"].tap();XCTAssertEqual(app.staticTexts["studio.tempo"].label,"120 BPM")
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

// AX CGRect arithmetic may report 43.99999999999997 for an actual 44-point
// target. This tolerance is less than one millionth of a point; real undersized
// controls still fail, and source geometry / edge-tap checks remain unchanged.
extension XCTestCase {
    func assertMinimumTouchDimension(_ actual:CGFloat,file:StaticString=#filePath,line:UInt=#line){
        XCTAssertGreaterThanOrEqual(actual+0.000001,44,"Touch dimension must be at least 44 points",file:file,line:line)
    }
}
