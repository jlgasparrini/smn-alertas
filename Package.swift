// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SMNAlertas",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "SMNCore"),
        .executableTarget(name: "SMNAlertas", dependencies: ["SMNCore"]),
        // Assert-based self-check: Command Line Tools ship without XCTest.
        .executableTarget(name: "SelfCheck", dependencies: ["SMNCore"]),
    ]
)
