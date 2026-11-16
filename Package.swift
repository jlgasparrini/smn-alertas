// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SMNAlertas",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SMNCore"),
        .executableTarget(name: "SMNAlertas", dependencies: ["SMNCore"]),
        .testTarget(name: "SMNCoreTests", dependencies: ["SMNCore"]),
    ]
)
