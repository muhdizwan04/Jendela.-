// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Jendela",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Jendela", targets: ["Jendela"])
    ],
    targets: [
        .executableTarget(
            name: "Jendela",
            path: "Sources/Jendela"
        ),
        .testTarget(name: "JendelaTests", dependencies: ["Jendela"], path: "Tests/JendelaTests")
    ]
)
