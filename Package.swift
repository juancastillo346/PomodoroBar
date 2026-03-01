// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FocusTimer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FocusTimer", targets: ["FocusTimer"])
    ],
    targets: [
        .executableTarget(
            name: "FocusTimer",
            path: "Sources"
        )
    ]
)
