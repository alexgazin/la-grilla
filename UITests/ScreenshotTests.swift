import XCTest
final class ScreenshotTests:XCTestCase {
    override func setUp(){super.setUp();executionTimeAllowance=600}
    @MainActor func testCaptureNativeScreens(){capture(["grid","jam","mixer","projects","export","export-wav","export-stems","notes","notes-mixer","harmony","harmony-proposal","assistant","assistant-proposal","voice","voice-draft","perform","perform-take","perform-export","midi","midi-mapped","grid-light","jam-light","mixer-light","notes-light","export-light","grid-ru","assistant-ru","notes-large","mixer-large","jam-large","settings"])}
    private var russianRecapture:Bool{ProcessInfo.processInfo.environment["GRILLA_RU_RECAPTURE"]=="1"}
    @MainActor func testCaptureStoreScreens(){
        let locales=russianRecapture ? ["ru"]:["en-US","ru"]
        capture(locales.flatMap{locale in ["grid","jam","notes","harmony-proposal","perform-take","export"].map{"store-\(locale)-\($0)"}})
        if russianRecapture{capture(["grid-ru","assistant-ru","mixer-ru","voice-ru"])}
    }
    @MainActor func testCaptureCompactScreens(){capture(russianRecapture ? ["compact-grid-ru","compact-jam-ru","compact-mixer-ru"]:["compact-grid","compact-jam","compact-mixer"])}
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
            let app=XCUIApplication();app.launchArguments=args+["--screen",target,"-AppleLanguages","(\(language))","-AppleLocale",locale];app.launch()
            guard app.buttons["perform.transport"].waitForExistence(timeout:20)else{XCTFail("The app did not open for \(screen)");continue}
            if screen.hasPrefix("compact-"){
                for label in language=="ru" ? ["Сетка","Джем","Микшер","Играть"]:["Grid","Jam","Mixer","Play"]{XCTAssertTrue(app.buttons[label].isHittable)}
                if target=="jam"{XCTAssertTrue(app.buttons[language=="ru" ? "Перкуссия":"Perc"].isHittable)}
                if target=="mixer"{XCTAssertTrue(app.buttons["mixer.mute.0"].isHittable);XCTAssertTrue(app.buttons["mixer.solo.0"].isHittable);XCTAssertTrue(app.sliders["mixer.pan.0"].isHittable)}
            }
            if target=="voice-draft"{XCTAssertTrue(app.staticTexts["voice.note-count"].waitForExistence(timeout:15))}
            Thread.sleep(forTimeInterval:target.hasPrefix("perform-") ? 5:1)
            let png=XCUIScreen.main.screenshot().pngRepresentation
            if screen.hasPrefix("store-"){
                let width=png[16..<20].reduce(0){($0<<8)|Int($1)},height=png[20..<24].reduce(0){($0<<8)|Int($1)}
                XCTAssertEqual(width,1320,"Store screenshot must preserve the native display width");XCTAssertEqual(height,2868)
            }
            let shot=XCTAttachment(data:png,uniformTypeIdentifier:"public.png");shot.name="R10-"+screen;shot.lifetime = .keepAlways;add(shot)
        }
    }
}
