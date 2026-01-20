// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ScreenshotManager",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ScreenshotManagerApp",
            targets: ["ScreenshotManagerApp"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ScreenshotManagerApp",
            path: "Sources/ScreenshotManagerApp"
        )
    ]
)

