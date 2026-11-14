// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "MusicDomain",
    platforms: [.iOS(.v18), .macOS(.v13)],
    products: [.library(name: "MusicDomain", targets: ["MusicDomain"]), .library(name: "AudioDSP", targets: ["AudioDSP"])],
    targets: [
        .target(name: "AudioDSP", publicHeadersPath: "include"),
        .target(name: "MusicDomain", dependencies: ["AudioDSP"]),
        .testTarget(name: "MusicDomainTests", dependencies: ["MusicDomain", "AudioDSP"])
    ],
    cxxLanguageStandard: .cxx17
)
