// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClaudeSentinel",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ClaudeSentinel", targets: ["ClaudeSentinel"])],
    targets: [.executableTarget(name: "ClaudeSentinel")],
    swiftLanguageModes: [.v5]
)
