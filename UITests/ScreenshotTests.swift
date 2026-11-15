import XCTest
final class ScreenshotTests:XCTestCase {
    @MainActor func testCaptureNativeScreens(){capture(["grid","jam","mixer","projects","export","export-wav","export-stems","notes","notes-mixer","harmony","harmony-proposal","assistant","assistant-proposal","voice","voice-draft","perform","perform-take","perform-export","midi","midi-mapped","grid-light","jam-light","mixer-light","notes-light","export-light","grid-ru","assistant-ru","notes-large","mixer-large","jam-large"])}
    @MainActor func testCaptureCompactScreens(){capture(["compact-grid","compact-jam","compact-mixer"])}
    @MainActor private func capture(_ screens:[String]){
        for screen in screens {
            var target=screen,args=["--uitesting"],language="en",locale="en_US"
            if screen.hasSuffix("-light"){target=String(screen.dropLast(6));args += ["--appearance","light"]}
            if screen.hasSuffix("-ru"){target=String(screen.dropLast(3));language="ru";locale="ru_RU"}
            if screen.hasSuffix("-large"){target=String(screen.dropLast(6));args.append("--large-type")}
            if screen.hasPrefix("compact-"){target=String(screen.dropFirst(8));args += ["--appearance","light"]}
            let app=XCUIApplication();app.launchArguments=args+["--screen",target,"-AppleLanguages","(\(language))","-AppleLocale",locale];app.launch()
            guard app.buttons["perform.transport"].waitForExistence(timeout:20)else{XCTFail("The app did not open for \(screen)");app.terminate();continue}
            if target=="voice-draft"{XCTAssertTrue(app.staticTexts["voice.note-count"].waitForExistence(timeout:15))}
            Thread.sleep(forTimeInterval:target.hasPrefix("perform-") ? 5:1)
            let shot=XCTAttachment(screenshot:XCUIScreen.main.screenshot());shot.name="R8-"+screen;shot.lifetime = .keepAlways;add(shot);app.terminate()
        }
    }
}
