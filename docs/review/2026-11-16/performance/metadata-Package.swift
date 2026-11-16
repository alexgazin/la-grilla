// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GrillaArchitectureProfile",
    dependencies: [.package(path: "source/Packages/MusicDomain")],
    targets: [
        .executableTarget(name: "GrillaArchitectureProfile", dependencies: [.product(name: "MusicDomain", package: "MusicDomain")])
    ]
)
