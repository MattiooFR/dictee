// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Dictee",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "DicteeCoeur", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "Dictee", dependencies: ["DicteeCoeur"],
                          swiftSettings: [.swiftLanguageMode(.v5)]),
        // Les tests localisent le faux worker via #filePath, pas via le bundle :
        // `exclude` empêche seulement SwiftPM de traiter le .py comme une source.
        .testTarget(name: "DicteeCoeurTests", dependencies: ["DicteeCoeur"],
                    exclude: ["Fixtures"],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
