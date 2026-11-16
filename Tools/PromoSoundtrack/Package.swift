// swift-tools-version: 6.0
import PackageDescription
import Foundation

// Set GRILLA_REPOSITORY when this tool is outside the repository's Tools folder.
let repository = ProcessInfo.processInfo.environment["GRILLA_REPOSITORY"]
    ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../..").standardizedFileURL.path
let package = Package(
    name: "PromoSoundtrack",
    dependencies: [.package(path: repository + "/Packages/MusicDomain")],
    targets: [.executableTarget(name: "PromoSoundtrack", dependencies: [
        .product(name: "MusicDomain", package: "MusicDomain")
    ])]
)
