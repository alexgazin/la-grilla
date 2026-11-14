// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MusicDomain", platforms: [.iOS(.v18), .macOS(.v13)], products: [.library(name: "MusicDomain", targets: ["MusicDomain"])], targets: [.target(name: "MusicDomain"), .testTarget(name: "MusicDomainTests", dependencies: ["MusicDomain"])])
