// A standalone macOS recording utility, never linked into the iOS application.
// Record real host-loopback PCM; do not replace unavailable audio with a render.
#if os(macOS)
import AVFoundation
import AppKit
import AudioToolbox
import CoreAudio
import Darwin
import Foundation

var diagnosticDirectory: URL?

enum CaptureFailure: Error, CustomStringConvertible {
    case reason(String)
    var description: String { switch self { case .reason(let text): return text } }
}

func writeJSON(_ value: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url, options: .atomic)
}

func defaultInput() throws -> (AudioDeviceID, String) {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var identifier = AudioDeviceID(0), size = UInt32(MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
        0, nil, &size, &identifier) == noErr, identifier != 0 else {
        throw CaptureFailure.reason("No actual default host audio input device is available")
    }
    address.mSelector = kAudioDevicePropertyDeviceUID
    var uid: CFString?
    size = UInt32(MemoryLayout<CFString?>.size)
    guard AudioObjectGetPropertyData(identifier, &address, 0, nil, &size, &uid) == noErr,
          let uid else {
        throw CaptureFailure.reason("The actual host input UID could not be read")
    }
    return (identifier, uid as String)
}

func authorize() throws {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized: return
    case .denied, .restricted:
        throw CaptureFailure.reason("Host microphone access is denied/restricted; no policy is changed")
    case .notDetermined:
        // A normal macOS system dialog may appear. No TCC database mutation,
        // permission reset or attribution to SimulatorTrampoline is performed.
        fputs("Requesting normal macOS audio-input access for the virtual BlackHole device.\n", stderr)
        let semaphore = DispatchSemaphore(value: 0)
        var allowed = false
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            allowed = granted
            semaphore.signal()
        }
        let deadline = Date().addingTimeInterval(60)
        while semaphore.wait(timeout: .now()) != .success {
            guard Date() < deadline else {
                throw CaptureFailure.reason("Normal macOS audio-input authorization did not finish within 60 seconds")
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard allowed else { throw CaptureFailure.reason("The normal audio-input authorization request was not granted") }
    @unknown default:
        throw CaptureFailure.reason("Unknown host microphone authorization status")
    }
}

final class Recorder {
    let engine = AVAudioEngine()
    let lock = NSLock()
    var file: AVAudioFile?
    var frames: UInt64 = 0, samples: UInt64 = 0
    var peak: Double = 0, squareSum: Double = 0
    var firstHost: UInt64 = 0, lastHost: UInt64 = 0
    var firstSample: AVAudioFramePosition = 0, lastSample: AVAudioFramePosition = 0
    var previousFrames: AVAudioFrameCount = 0
    var sampleTimeDiscontinuities: UInt64 = 0
    var callbackError: String?
    var format: AVAudioFormat!
    let expectedUID: String

    init(url: URL, expectedUID: String) throws {
        self.expectedUID = expectedUID
        let actual = try defaultInput()
        guard actual.1 == expectedUID else {
            throw CaptureFailure.reason("Refusing physical/other host input UID \(actual.1); expected \(expectedUID)")
        }
        format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount == 2,
              format.commonFormat == .pcmFormatFloat32, !format.isInterleaved else {
            throw CaptureFailure.reason("BlackHole must expose finite-rate stereo Float32 input: \(format!)")
        }
        file = try AVAudioFile(forWriting: url, settings: format.settings,
            commonFormat: .pcmFormatFloat32, interleaved: format.isInterleaved)
    }

    func start() throws {
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [self] buffer, time in
            lock.lock(); defer { lock.unlock() }
            guard callbackError == nil, let file else { return }
            guard let channels = buffer.floatChannelData, time.isHostTimeValid,
                  time.isSampleTimeValid, buffer.frameLength > 0 else {
                callbackError = "Host loopback supplied no timestamped Float32 PCM"; return
            }
            if frames == 0 {
                firstHost = time.hostTime; firstSample = time.sampleTime
            } else if time.sampleTime != lastSample + AVAudioFramePosition(previousFrames) {
                sampleTimeDiscontinuities += 1
            }
            lastHost = time.hostTime; lastSample = time.sampleTime; previousFrames = buffer.frameLength
            for channel in 0..<Int(buffer.format.channelCount) {
                let source = channels[channel]
                for frame in 0..<Int(buffer.frameLength) {
                    let value = Double(source[frame * buffer.stride])
                    guard value.isFinite else { callbackError = "Nonfinite actual host PCM"; return }
                    peak = max(peak, abs(value)); squareSum += value * value
                }
            }
            do {
                // This capture utility has its own engine and file. The iOS
                // application's realtime render code is never changed.
                try file.write(from: buffer)
                frames += UInt64(buffer.frameLength)
                samples += UInt64(buffer.frameLength) * UInt64(buffer.format.channelCount)
            } catch { callbackError = "Writing actual host PCM failed: \(error)" }
        }
        engine.prepare()
        try engine.start()
    }

    func snapshot(status: String) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        var result: [String: Any] = ["status": status, "device_uid": expectedUID,
            "kind": "Actual Simulator host output recorded through BlackHole loopback",
            "sample_rate": format.sampleRate, "channels": Int(format.channelCount),
            "frames": frames, "samples": samples, "duration_seconds": Double(frames) / format.sampleRate,
            "peak": peak, "rms": samples > 0 ? sqrt(squareSum / Double(samples)) : 0,
            "first_host_time": firstHost, "last_host_time": lastHost,
            "first_host_seconds": AVAudioTime.seconds(forHostTime: firstHost),
            "last_host_seconds": AVAudioTime.seconds(forHostTime: lastHost),
            "first_sample_time": firstSample, "last_sample_time": lastSample,
            "sample_time_discontinuities": sampleTimeDiscontinuities,
            "receipt_host_time": mach_absolute_time(), "offline_audio_substitution": false,
            "physical_microphone_selected": false, "physical_device_acceptance": false]
        if let callbackError { result["error"] = callbackError }
        return result
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock(); file = nil; lock.unlock()
    }
}

func main() throws {
    let arguments = CommandLine.arguments
    guard arguments.count == 4, arguments[2] == "--max-seconds",
          let limit = Double(arguments[3]), limit > 0, limit <= 900 else {
        throw CaptureFailure.reason("Usage: LaGrillaDemoAudioRecorder <output-directory> --max-seconds <1...900>")
    }
    let directory = URL(fileURLWithPath: arguments[1]).standardizedFileURL
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    diagnosticDirectory = directory
    let logPath = directory.appendingPathComponent("helper.log").path
    guard freopen(logPath, "a", stdout) != nil,
          freopen(logPath, "a", stderr) != nil else {
        throw CaptureFailure.reason("Cannot open the capture helper log at \(logPath)")
    }
    setbuf(stdout, nil)
    setbuf(stderr, nil)
    let beforeAuthorization = try? defaultInput()
    try writeJSON([
        "phase": "before-authorization",
        "authorization_status_raw": AVCaptureDevice.authorizationStatus(for: .audio).rawValue,
        "default_input_uid": beforeAuthorization?.1 ?? "unavailable",
        "expected_input_uid": "BlackHole2ch_UID",
        "host_time": mach_absolute_time(),
        "process_id": ProcessInfo.processInfo.processIdentifier
    ], to: directory.appendingPathComponent("startup.json"))
    let readyURL = directory.appendingPathComponent("ready.json")
    let receiptURL = directory.appendingPathComponent("audio-receipt.json")
    let stopURL = directory.appendingPathComponent("stop-audio")
    try? FileManager.default.removeItem(at: readyURL)
    try? FileManager.default.removeItem(at: stopURL)
    let actual = try defaultInput()
    guard actual.1 == "BlackHole2ch_UID" else {
        throw CaptureFailure.reason("Refusing host input UID \(actual.1); BlackHole2ch_UID must be selected first")
    }
    try authorize()
    let recorder = try Recorder(url: directory.appendingPathComponent("audio.caf"), expectedUID: actual.1)
    var stopRequested = false
    let signals = [SIGINT, SIGTERM].map { number -> DispatchSourceSignal in
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
        source.setEventHandler { stopRequested = true }; source.resume(); return source
    }
    defer { for source in signals { source.cancel() } }
    try recorder.start()
    let deadline = Date().addingTimeInterval(limit), readyDeadline = Date().addingTimeInterval(10)
    var ready = false
    while !stopRequested, Date() < deadline, !FileManager.default.fileExists(atPath: stopURL.path) {
        let current = recorder.snapshot(status: "recording")
        if current["error"] != nil { break }
        if !ready, (current["frames"] as? UInt64 ?? 0) > 0 {
            try writeJSON(current, to: readyURL)
            print("HOST_AUDIO_READY \(readyURL.path)"); fflush(stdout); ready = true
        }
        if !ready, Date() >= readyDeadline { break }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    recorder.stop()
    let result = recorder.snapshot(status: "finished")
    try writeJSON(result, to: receiptURL)
    guard result["error"] == nil, ready,
          (result["frames"] as? UInt64 ?? 0) > 0,
          (result["peak"] as? Double ?? 0) > 0.001,
          (result["rms"] as? Double ?? 0) > 0.00001 else {
        throw CaptureFailure.reason("Actual host capture was unavailable, invalid or silent; inspect \(receiptURL.path)")
    }
    print("HOST_AUDIO_CAPTURED \(receiptURL.path)")
}

func runCapture() {
do { try main(); exit(0) } catch {
    if let directory = diagnosticDirectory {
        try? writeJSON([
            "status": "failed", "error": String(describing: error),
            "authorization_status_raw": AVCaptureDevice.authorizationStatus(for: .audio).rawValue,
            "default_input_uid": (try? defaultInput())?.1 ?? "unavailable",
            "host_time": mach_absolute_time()
        ], to: directory.appendingPathComponent("failure.json"))
    }
    fputs("Host audio capture failed: \(error)\n", stderr)
    exit(1)
}
}

/// LaunchServices starts a real foreground Cocoa application. Keep AppKit's
/// main event loop running while the capture worker requests normal consent.
/// A bare Foundation executable nested in an app bundle had no active Cocoa
/// application in the first runner attempt; its consent request never replied.
final class CaptureApplicationDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let frame = NSRect(x: 0, y: 0, width: 480, height: 170)
        let panel = NSWindow(contentRect: frame, styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
        panel.title = "La Grilla Demo Audio Recorder"
        let label = NSTextField(wrappingLabelWithString:
            "Recording only the virtual BlackHole audio output for the app demonstration.\n\nNo physical microphone is selected. Use the normal macOS permission dialog to allow this capture.")
        label.frame = NSRect(x: 24, y: 24, width: 432, height: 120)
        panel.contentView?.addSubview(label)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        window = panel
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.global(qos: .userInitiated).async { runCapture() }
    }
}

let captureApplication = NSApplication.shared
let captureDelegate = CaptureApplicationDelegate()
captureApplication.delegate = captureDelegate
captureApplication.run()
#else
import Foundation
fputs("Host audio capture requires macOS and an actual BlackHole audio route.\n", stderr)
exit(1)
#endif
