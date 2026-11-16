// swift-tools-version: 6.0
import PackageDescription
let package = Package(name:"GrillaMixProfile",dependencies:[.package(path:"source/MusicDomain")],targets:[.executableTarget(name:"GrillaMixProfile",dependencies:[.product(name:"MusicDomain",package:"MusicDomain")])])
