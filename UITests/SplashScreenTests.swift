import XCTest
import UIKit

/// Deterministic visual previews use the production loading component while
/// real bootstrap still runs. They are not cold-launch latency measurements.
final class SplashScreenTests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        executionTimeAllowance = 120
    }

    @MainActor func testBrandedLoadingPreviewAndRealStartupPreserveOnboarding() throws {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        let store = UUID().uuidString
        defer { app.terminate() }
        let variants: [(name: String, appearance: String, language: String, flags: [String])] = [
            ("dark-en", "dark", "en", []),
            ("light-en", "light", "en", []),
            ("dark-ru-large-reduced-motion", "dark", "ru", ["--large-type", "--splash-reduce-motion"])
        ]
        var observations: [[String: Any]] = []
        for variant in variants {
            app.launchArguments = arguments(store: store, appearance: variant.appearance, language: variant.language)
                + ["--splash-preview"] + variant.flags
            app.launch()
            let status = app.staticTexts["splash.status"]
            XCTAssertTrue(status.waitForExistence(timeout: 15))
            let frame = try settledPreview(in: app, appearance: variant.appearance,
                                           largeType: variant.flags.contains("--large-type"),
                                           reduceMotionRequired: variant.flags.contains("--splash-reduce-motion"))
            let state = try previewState(status)
            XCTAssertTrue(state.qaPreview)
            XCTAssertEqual(state.qaReduceMotionOverride, variant.flags.contains("--splash-reduce-motion"))
            XCTAssertTrue(state.bootstrapReady, "The preview holds presentation after actual bootstrap; it must not delay bootstrap work")
            XCTAssertTrue(app.staticTexts["splash.brand"].isHittable)
            XCTAssertTrue(status.isHittable)
            XCTAssertGreaterThanOrEqual(status.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(status.frame.maxX, app.frame.maxX)
            XCTAssertLessThanOrEqual(status.frame.maxY, app.frame.maxY)
            XCTAssertFalse(app.buttons["perform.transport"].exists, "A preview is the loading component, not an interactive studio overlay")
            keep(frame, name: "Splash-preview-" + variant.name)
            observations.append([
                "name": variant.name, "qaPreview": true, "realBootstrapReady": state.bootstrapReady,
                "appearance": state.appearance, "reduceMotion": state.reduceMotion,
                "systemReduceMotion": state.systemReduceMotion,
                "qaReduceMotionOverride": state.qaReduceMotionOverride,
                "largeType": state.largeType, "uiLanguage": variant.language,
                "bootstrapLatencyMeasured": false
            ])
            app.terminate()
        }

        // Remove the preview flag and go through the real readiness/onboarding
        // route. The same actual UUID-scoped ProjectStore is reopened.
        app.launchArguments = arguments(store: store, appearance: "dark", language: "en") + ["--show-welcome"]
        app.launch()
        XCTAssertTrue(app.staticTexts["welcome.title"].waitForExistence(timeout: 15))
        app.buttons["welcome.skip"].tap()
        XCTAssertTrue(app.buttons["perform.transport"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["splash.status"].exists)
        app.terminate()

        app.launchArguments = arguments(store: store, appearance: "dark", language: "en") + ["--respect-welcome"]
        app.launch()
        let transport = app.buttons["perform.transport"]
        XCTAssertTrue(transport.waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["welcome.title"].waitForExistence(timeout: 2))
        XCTAssertTrue(transport.isHittable)
        XCTAssertFalse(app.staticTexts["splash.status"].exists)
        let receipt: [String: Any] = [
            "previews": observations, "realNormalLaunchReachedStudio": true,
            "realWelcomeSkipAndRelaunchPassed": true, "projectStoreID": store,
            "productionMinimumDelayAdded": false, "launchPerformanceAccepted": false
        ]
        let data = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(string: String(decoding: data, as: UTF8.self))
        attachment.name = "Splash-preview-and-real-startup-observations"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private struct PreviewState: Decodable {
        let qaPreview: Bool
        let bootstrapReady: Bool
        let appearance: String
        let reduceMotion: Bool
        let systemReduceMotion: Bool
        let qaReduceMotionOverride: Bool
        let largeType: Bool
    }

    private enum VisualFailure: Error { case previewDidNotSettle, previewStateUnavailable, screenshotUnavailable }

    private func arguments(store: String, appearance: String, language: String) -> [String] {
        ["--uitesting", "--project-store-id", store, "--appearance", appearance,
         "-AppleLanguages", "(\(language))", "-AppleLocale", language == "ru" ? "ru_RU" : "en_US"]
    }

    @MainActor private func previewState(_ element: XCUIElement) throws -> PreviewState {
        guard let value = element.value as? String else { throw VisualFailure.previewStateUnavailable }
        return try JSONDecoder().decode(PreviewState.self, from: Data(value.utf8))
    }

    @MainActor private func settledPreview(in app: XCUIApplication, appearance: String,
                                          largeType: Bool, reduceMotionRequired: Bool) throws -> XCUIScreenshot {
        let status = app.staticTexts["splash.status"]
        let deadline = Date().addingTimeInterval(8)
        var consecutive = 0
        while Date() < deadline {
            if let state = try? previewState(status), state.qaPreview, state.bootstrapReady,
               state.appearance == appearance, state.largeType == largeType,
               !reduceMotionRequired || state.reduceMotion {
                let screenshot = XCUIScreen.main.screenshot()
                let luminance = try backgroundLuminance(screenshot.image, appFrame: app.frame)
                let matches = appearance == "dark" ? luminance < 0.3 : luminance > 0.75
                consecutive = matches ? consecutive + 1 : 0
                if consecutive == 2 { return screenshot }
            } else { consecutive = 0 }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("The actual splash state and rendered background did not settle for \(appearance)")
        throw VisualFailure.previewDidNotSettle
    }

    private func backgroundLuminance(_ image: UIImage, appFrame: CGRect) throws -> Double {
        guard let source = image.cgImage, appFrame.width > 0, appFrame.height > 0 else {
            throw VisualFailure.screenshotUnavailable
        }
        let x = 20 * CGFloat(source.width) / appFrame.width
        let y = 120 * CGFloat(source.height) / appFrame.height
        guard let pixel = source.cropping(to: CGRect(x: x.rounded(.down), y: y.rounded(.down), width: 1, height: 1)) else {
            throw VisualFailure.screenshotUnavailable
        }
        var rgba = [UInt8](repeating: 0, count: 4)
        let success = rgba.withUnsafeMutableBytes { storage -> Bool in
            guard let context = CGContext(data: storage.baseAddress, width: 1, height: 1,
                                          bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard success else { throw VisualFailure.screenshotUnavailable }
        return (0.2126 * Double(rgba[0]) + 0.7152 * Double(rgba[1]) + 0.0722 * Double(rgba[2])) / 255
    }

    private func keep(_ screenshot: XCUIScreenshot, name: String) {
        let attachment = XCTAttachment(data: screenshot.pngRepresentation, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
