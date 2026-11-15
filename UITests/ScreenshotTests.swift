import XCTest
final class ScreenshotTests:XCTestCase {
    @MainActor func testCaptureNativeScreens() {
        let screens=["grid","jam","mixer","projects","export","export-wav","export-stems","notes","notes-mixer","harmony","harmony-proposal","assistant","assistant-proposal","voice","voice-draft","perform","perform-take","perform-export","midi","midi-mapped"]
        for screen in screens {
            let app=XCUIApplication();app.launchArguments=["--uitesting","--screen",screen,"-AppleLanguages","(en)","-AppleLocale","en_US"];app.launch()
            guard app.buttons["perform.transport"].waitForExistence(timeout:20)else{XCTFail("The app did not open for \(screen)");app.terminate();continue}
            if screen=="voice-draft"{XCTAssertTrue(app.staticTexts["voice.note-count"].waitForExistence(timeout:15))}
            if screen.hasPrefix("perform-"){Thread.sleep(forTimeInterval:5)}else{Thread.sleep(forTimeInterval:1)}
            let shot=XCTAttachment(screenshot:app.screenshot());shot.name="R7-"+screen;shot.lifetime = .keepAlways;add(shot)
            app.terminate()
        }
    }
}
