// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dictee",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DicteeCoeur", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "Dictee", dependencies: ["DicteeCoeur"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "DicteeCoeurTests", dependencies: ["DicteeCoeur"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
