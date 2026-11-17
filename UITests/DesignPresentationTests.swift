import XCTest
import UIKit

/// Original native PNGs plus a narrow navigation contract. The existing notes
/// launch path creates its real, populated project before the read-only baseline.
final class DesignPresentationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor func testNightSurfacesRemainReachableWithoutEditingMusic() throws {
        try capturePresentation(appearance: "dark", name: "night")
    }

    @MainActor func testLightSurfacesRemainReachableWithoutEditingMusic() throws {
        try capturePresentation(appearance: "light", name: "light")
    }

    private enum PresentationError: Error { case unreachable, missingTrace, appearanceUnsettled }

    @MainActor private func capturePresentation(appearance: String, name: String) throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting", "--runtime-trace", "--device-output-startup",
            "--project-store-id", UUID().uuidString, "--appearance", appearance,
            "--screen", "notes", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
        ]
        app.launch()
        defer { app.terminate() }

        // These are the app's existing, real QA note events, not a test overlay.
        try requireReachable(app.navigationBars["Piano roll"])
        let noteCount = app.staticTexts["notes.count"]
        XCTAssertTrue(noteCount.waitForExistence(timeout: 5))
        XCTAssertEqual(noteCount.label, "5")
        try requireReachable(app.buttons["notes.add"], minimumTarget: true)
        try requireReachable(app.buttons["notes.play"], minimumTarget: true)
        try keepScreen(app, name: "Design26-" + name + "-piano", light: appearance == "light")
        app.buttons["Done"].tap()

        try requireReachable(app.buttons["perform.transport"])
        let baseline = try sourceState(app)
        let undoEnabled = app.buttons["Undo"].isEnabled
        let redoEnabled = app.buttons["Redo"].isEnabled
        XCTAssertEqual(baseline["preview"], "false")
        XCTAssertEqual(baseline["actualPlaying"], "0")
        for title in ["Grid", "Jam", "Mixer", "Play"] {
            try requireReachable(app.buttons[title], minimumTarget: true)
        }
        try requireReachable(app.buttons["grid.mode.clips"], minimumTarget: true)
        try keepScreen(app, name: "Design26-" + name + "-grid", light: appearance == "light")

        app.buttons["Jam"].tap()
        try requireReachable(app.buttons["jam.pad.0"], minimumTarget: true)
        try requireReachable(app.buttons["jam.recording-guide"], minimumTarget: true)
        try keepScreen(app, name: "Design26-" + name + "-jam", light: appearance == "light")
        try assertUnchanged(app, baseline: baseline, undoEnabled: undoEnabled, redoEnabled: redoEnabled)

        let sound = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sound.track.drums.'")).firstMatch
        try requireReachable(sound, minimumTarget: true)
        let originalSound = sound.value as? String
        XCTAssertEqual(originalSound, "Classic kit")
        sound.tap()
        try requireReachable(app.navigationBars["Sound"])
        try requireReachable(app.buttons["sound.palette.2"], minimumTarget: true)
        try requireReachable(app.buttons["sound.preview"], minimumTarget: true)
        XCTAssertFalse(app.buttons["sound.apply"].isEnabled, "An unchanged sound is not an edit to apply")
        try keepScreen(app, name: "Design26-" + name + "-sound", light: appearance == "light")
        app.buttons["Cancel"].tap()
        try requireReachable(sound, minimumTarget: true)
        XCTAssertEqual(sound.value as? String, originalSound)
        try assertUnchanged(app, baseline: baseline, undoEnabled: undoEnabled, redoEnabled: redoEnabled)

        app.buttons["Mixer"].tap()
        try requireReachable(app.buttons["mixer.mute.0"], minimumTarget: true)
        try requireReachable(app.buttons["mixer.solo.0"], minimumTarget: true)
        try requireReachable(app.sliders["mixer.pan.0"])
        try keepScreen(app, name: "Design26-" + name + "-mixer", light: appearance == "light")
        try assertUnchanged(app, baseline: baseline, undoEnabled: undoEnabled, redoEnabled: redoEnabled)

        app.buttons["Grid"].tap()
        try requireReachable(app.buttons["notes.open"], minimumTarget: true)
        app.buttons["notes.open"].tap()
        try requireReachable(app.navigationBars["Piano roll"])
        XCTAssertEqual(app.staticTexts["notes.count"].label, "5", "Reopening the editor must preserve the seeded notes")
        app.buttons["Done"].tap()
        try assertUnchanged(app, baseline: baseline, undoEnabled: undoEnabled, redoEnabled: redoEnabled)

        let receipt = XCTAttachment(string:
            "Requested appearance: \(appearance)\n" +
            "Real notes fixture created before baseline: 5 events\n" +
            "Navigation: Piano → Grid → Jam → Sound → Jam → Mixer → Grid → Piano → Grid\n" +
            "Baseline source fields: \(baseline)\n" +
            "Final source fields: \(try sourceState(app))\n" +
            "Final actual runtime:\n\(app.buttons["perform.transport"].value as? String ?? "missing")"
        )
        receipt.name = "Design26-" + name + "-navigation-receipt"
        receipt.lifetime = .keepAlways
        add(receipt)
    }

    @MainActor private func sourceState(_ app: XCUIApplication) throws -> [String: String] {
        let trace = app.buttons["perform.transport"].value as? String ?? ""
        let firstLine = trace.components(separatedBy: "\n").first ?? ""
        var result: [String: String] = [:]
        for token in firstLine.split(separator: " ") {
            let parts = token.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 { result[String(parts[0])] = String(parts[1]) }
        }
        let keys = ["project", "revision", "preview", "loopRangeStart", "loopRangeEnd", "actualPlaying"]
        guard keys.allSatisfy({ result[$0] != nil }) else {
            let evidence = XCTAttachment(string: trace + "\n" + app.debugDescription)
            evidence.name = "Design26-missing-original-runtime-trace"
            evidence.lifetime = .keepAlways
            add(evidence)
            XCTFail("The real runtime trace must identify the project, revision, range and playback state")
            throw PresentationError.missingTrace
        }
        return Dictionary(uniqueKeysWithValues: keys.map { ($0, result[$0]!) })
    }

    @MainActor private func assertUnchanged(
        _ app: XCUIApplication,
        baseline: [String: String],
        undoEnabled: Bool,
        redoEnabled: Bool
    ) throws {
        try requireReachable(app.buttons["perform.transport"])
        XCTAssertEqual(try sourceState(app), baseline, "Browsing tools must not change music or transport")
        XCTAssertEqual(app.buttons["Undo"].isEnabled, undoEnabled)
        XCTAssertEqual(app.buttons["Redo"].isEnabled, redoEnabled)
    }

    @MainActor private func requireReachable(_ element: XCUIElement, minimumTarget: Bool = false) throws {
        guard element.waitForExistence(timeout: 15), element.isHittable else {
            XCTFail("The original native control is not reachable: " + element.debugDescription)
            throw PresentationError.unreachable
        }
        if minimumTarget {
            XCTAssertGreaterThanOrEqual(element.frame.width, 44)
            XCTAssertGreaterThanOrEqual(element.frame.height, 44)
        }
    }

    @MainActor private func keepScreen(_ app: XCUIApplication, name: String, light: Bool) throws {
        let deadline = Date().addingTimeInterval(6)
        var consecutive = 0
        var last = XCUIScreen.main.screenshot()
        var lastLuminance: Double?
        repeat {
            last = XCUIScreen.main.screenshot()
            lastLuminance = medianLuminance(last)
            if let luma = lastLuminance, (light ? luma > 0.65 : luma < 0.35), !app.alerts.firstMatch.exists {
                consecutive += 1
            } else {
                consecutive = 0
            }
            if consecutive == 2 { break }
            Thread.sleep(forTimeInterval: 0.15)
        } while Date() < deadline
        let attachment = XCTAttachment(data: last.pngRepresentation, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard consecutive == 2 else {
            XCTFail("The actual rendered \(name) did not settle to its requested appearance; median luminance=\(String(describing: lastLuminance))")
            throw PresentationError.appearanceUnsettled
        }
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    @MainActor private func medianLuminance(_ screenshot: XCUIScreenshot) -> Double? {
        guard let image = UIImage(data: screenshot.pngRepresentation)?.cgImage else { return nil }
        let width = 40, height = 60
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(
                data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            return true
        }
        guard rendered else { return nil }
        var values: [Double] = []
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            values.append((0.2126 * Double(pixels[offset]) + 0.7152 * Double(pixels[offset + 1]) + 0.0722 * Double(pixels[offset + 2])) / 255)
        }
        values.sort()
        return values[values.count / 2]
    }
}
