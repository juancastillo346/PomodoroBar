// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PomodoroBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PomodoroBar", targets: ["PomodoroBar"])
    ],
    targets: [
        .executableTarget(
            name: "PomodoroBar",
            path: "Sources"
        )
    ]
)
