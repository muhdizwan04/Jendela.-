// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WidgetMac",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "WidgetMac", targets: ["WidgetMac"])
    ],
    targets: [
        .executableTarget(
            name: "WidgetMac",
            path: "Sources/WidgetMac"
        ),
        .testTarget(name: "WidgetMacTests", dependencies: ["WidgetMac"], path: "Tests/WidgetMacTests")
    ]
)
