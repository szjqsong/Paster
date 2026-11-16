// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Paster",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Paster",
            path: "Sources/Paster"
        )
    ]
)
