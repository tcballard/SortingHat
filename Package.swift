// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SortingHat",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "sorting-hat", targets: ["SortingHat"]),
        .executable(name: "SortingHatApp", targets: ["SortingHatApp"]),
    ],
    targets: [
        .target(name: "SortingHatCore"),
        .executableTarget(name: "SortingHat", dependencies: ["SortingHatCore"]),
        .executableTarget(
            name: "SortingHatApp",
            dependencies: ["SortingHatCore"],
            resources: [.copy("Resources/install_quick_action.sh")]
        ),
        .testTarget(
            name: "SortingHatTests",
            dependencies: ["SortingHatCore"],
            resources: [.process("Fixtures")]
        ),
    ]
)
