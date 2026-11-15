// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "VoiceBenchmark",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../../Packages/MusicDomain")],
    targets: [
        .executableTarget(
            name: "VoiceBenchmark",
            dependencies: [.product(name: "MusicDomain", package: "MusicDomain")]
        )
    ]
)
