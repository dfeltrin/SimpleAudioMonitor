// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SimpleAudioMonitor",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "SimpleAudioMonitor", targets: ["SimpleAudioMonitor"])
    ],
    targets: [
        .executableTarget(name: "SimpleAudioMonitor")
    ]
)
