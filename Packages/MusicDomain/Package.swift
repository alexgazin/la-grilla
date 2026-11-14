// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "MusicDomain", products: [.library(name: "MusicDomain", targets: ["MusicDomain"])], targets: [.target(name: "MusicDomain"), .testTarget(name: "MusicDomainTests", dependencies: ["MusicDomain"])])
