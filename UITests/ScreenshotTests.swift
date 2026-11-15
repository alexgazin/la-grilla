import XCTest
import UIKit
final class ScreenshotTests:XCTestCase {
    override func setUp(){super.setUp();executionTimeAllowance=600}
    @MainActor func testCaptureNativeScreens(){capture(["grid","jam","mixer","projects","export","export-wav","export-stems","notes","notes-mixer","harmony","harmony-proposal","harmony-custom","harmony-custom-ru","assistant","assistant-proposal","assistant-song-proposal","voice","voice-draft","perform","perform-take","perform-export","midi","midi-mapped","grid-light","jam-light","mixer-light","notes-light","export-light","grid-ru","assistant-ru","mixer-ru","voice-ru","notes-large","mixer-large","jam-large","settings"])}
    private var russianRecapture:Bool{ProcessInfo.processInfo.environment["GRILLA_RU_RECAPTURE"]=="1"}
    @MainActor func testCaptureStoreScreens(){
        let locales=russianRecapture ? ["ru"]:["en-US","ru"]
        capture(locales.flatMap{locale in ["grid","jam","notes","harmony-proposal","perform-take","export"].map{"store-\(locale)-\($0)"}})
        if russianRecapture{capture(["grid-ru","assistant-ru","mixer-ru","voice-ru"])}
    }
    @MainActor func testCaptureCompactScreens(){capture(russianRecapture ? ["compact-grid-ru","compact-jam-ru","compact-mixer-ru","compact-harmony-custom-ru"]:["compact-grid","compact-jam","compact-mixer","compact-harmony-custom","compact-grid-ru","compact-jam-ru","compact-mixer-ru","compact-harmony-custom-ru"])}
    @MainActor private func capture(_ screens:[String]){
        for screen in screens {
            XCUIDevice.shared.orientation = .portrait
            var target=screen,args=["--uitesting"],language="en",locale="en_US"
            if screen.hasSuffix("-light"){target=String(screen.dropLast(6));args += ["--appearance","light"]}
            if screen.hasSuffix("-ru"){target=String(screen.dropLast(3));language="ru";locale="ru_RU"}
            if screen.hasSuffix("-large"){target=String(screen.dropLast(6));args.append("--large-type")}
            if screen.hasPrefix("compact-"){target=String(target.dropFirst(8));args += ["--appearance","light"]}
            if screen.hasPrefix("store-en-US-"){target=String(screen.dropFirst(12))}
            if screen.hasPrefix("store-ru-"){target=String(screen.dropFirst(9));language="ru";locale="ru_RU"}
            let customHarmony=target=="harmony-custom"
            if customHarmony{target="grid"}
            let app=XCUIApplication();app.launchArguments=args+["--screen",target,"-AppleLanguages","(\(language))","-AppleLocale",locale];app.launch()
            guard app.buttons["perform.transport"].waitForExistence(timeout:20)else{XCTFail("The app did not open for \(screen)");continue}
            if screen.hasPrefix("compact-"){
                for label in language=="ru" ? ["Сетка","Джем","Микшер","Играть"]:["Grid","Jam","Mixer","Play"]{XCTAssertTrue(app.buttons[label].isHittable)}
                if target=="jam"{XCTAssertTrue(app.buttons[language=="ru" ? "Перкуссия":"Perc"].isHittable)}
                if target=="mixer"{XCTAssertTrue(app.buttons["mixer.mute.0"].isHittable);XCTAssertTrue(app.buttons["mixer.solo.0"].isHittable);XCTAssertTrue(app.sliders["mixer.pan.0"].isHittable)}
            }
            if customHarmony,!prepareCustomHarmony(app){continue}
            if target=="voice-draft"{XCTAssertTrue(app.staticTexts["voice.note-count"].waitForExistence(timeout:15))}
            Thread.sleep(forTimeInterval:target.hasPrefix("perform-") ? 5:1)
            let png=settledPNG()
            if screen.hasPrefix("store-"){
                let width=png[16..<20].reduce(0){($0<<8)|Int($1)},height=png[20..<24].reduce(0){($0<<8)|Int($1)}
                XCTAssertEqual(width,1320,"Store screenshot must preserve the native display width");XCTAssertEqual(height,2868)
            }
            let shot=XCTAttachment(data:png,uniformTypeIdentifier:"public.png");shot.name="OriginalVision-"+screen;shot.lifetime = .keepAlways;add(shot)
        }
    }
    @MainActor private func prepareCustomHarmony(_ app:XCUIApplication)->Bool {
        let chord=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","grid.chord.")).firstMatch
        guard chord.waitForExistence(timeout:5)else{XCTFail("No actual chord cell opened for the custom harmony capture");return false}
        chord.tap()
        let symbol=app.textFields["chord.symbol"]
        guard symbol.waitForExistence(timeout:5)else{XCTFail("The chord editor did not open");return false}
        symbol.coordinate(withNormalizedOffset:CGVector(dx:0.95,dy:0.5)).tap()
        let old=symbol.value as? String ?? ""
        symbol.typeText(String(repeating:XCUIKeyboardKey.delete.rawValue,count:old.count)+"C{0,3,7,11,14}\n")
        let notes=app.staticTexts["chord.notes"]
        let parsed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"label == %@","C4 · E♭4 · G4 · B4 · D5"),object:notes)
        guard XCTWaiter.wait(for:[parsed],timeout:5) == .completed else{XCTFail("The actual chord parser did not produce the written custom tones");return false}
        let formula=app.textFields["chord.formula"]
        guard formula.waitForExistence(timeout:5)else{XCTFail("The parsed custom formula field is missing");return false}
        let formulaValue=formula.value as? String,symbolValue=symbol.value as? String,custom=app.switches["chord.custom"].value as? String
        let hasError=app.staticTexts["chord.error"].exists
        XCTAssertEqual(formulaValue,"0, 3, 7, 11, 14")
        XCTAssertEqual(symbolValue,"C{0,3,7,11,14}")
        XCTAssertEqual(custom,"1")
        XCTAssertFalse(hasError)
        let dismissed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:app.keyboards.firstMatch)
        let keyboardDismissed=XCTWaiter.wait(for:[dismissed],timeout:5) == .completed
        XCTAssertTrue(keyboardDismissed)
        return formulaValue=="0, 3, 7, 11, 14" && symbolValue=="C{0,3,7,11,14}" && custom=="1" && !hasError && keyboardDismissed
    }
    @MainActor private func settledPNG()->Data {
        // AX readiness can precede the simulator compositor's completed frame.
        // Compare actual pixels, excluding timestamp/metadata differences; keep
        // the final native PNG unchanged. Live Perform views may keep moving.
        var previous=XCUIScreen.main.screenshot()
        for _ in 0..<4 {
            Thread.sleep(forTimeInterval:0.5)
            let current=XCUIScreen.main.screenshot()
            if let before=previous.image.cgImage?.dataProvider?.data,
               let after=current.image.cgImage?.dataProvider?.data,CFEqual(before,after){return current.pngRepresentation}
            previous=current
        }
        return previous.pngRepresentation
    }
}
