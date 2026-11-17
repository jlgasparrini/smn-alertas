// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Truenito",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Automatic updates (signed appcast); the only third-party dependency.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.6.4"),
    ],
    targets: [
        .target(name: "SMNCore"),
        .executableTarget(name: "Truenito", dependencies: ["SMNCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "SMNCoreTests", dependencies: ["SMNCore"], resources: [.copy("Fixtures")]),
    ]
)
