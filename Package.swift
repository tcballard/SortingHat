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
        .executableTarget(name: "SortingHatApp", dependencies: ["SortingHatCore"]),
        .testTarget(name: "SortingHatTests", dependencies: ["SortingHatCore"]),
    ]
)
