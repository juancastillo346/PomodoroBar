// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StudyPulse",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "StudyPulse", targets: ["StudyPulse"])
    ],
    targets: [
        .executableTarget(
            name: "StudyPulse",
            path: "Sources"
        )
    ]
)
