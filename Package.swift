// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SortingHat",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SortingHatCore", targets: ["SortingHatCore"]),
        .library(name: "SortingHatFMResearch", targets: ["SortingHatFMResearch"]),
        .library(name: "SortingHatFinderAdapter", targets: ["SortingHatFinderAdapter"]),
        .executable(name: "sorting-hat", targets: ["SortingHat"]),
        .executable(name: "SortingHatApp", targets: ["SortingHatApp"]),
    ],
    targets: [
        .target(name: "SortingHatQueueLock"),
        .target(name: "SortingHatCore", dependencies: ["SortingHatQueueLock"]),
        .target(name: "SortingHatFMResearch", dependencies: ["SortingHatCore"]),
        .target(name: "SortingHatFinderAdapter", dependencies: ["SortingHatCore"]),
        .executableTarget(name: "SortingHat", dependencies: ["SortingHatCore", "SortingHatFMResearch"]),
        .executableTarget(name: "SortingHatApp", dependencies: ["SortingHatCore"]),
        .testTarget(
            name: "SortingHatTests",
            dependencies: ["SortingHatCore", "SortingHatFMResearch", "SortingHatFinderAdapter"],
            resources: [.process("Fixtures")]
        ),
    ]
)
