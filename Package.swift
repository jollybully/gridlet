// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gridlet",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Gridlet", targets: ["Gridlet"]),
    ],
    targets: [
        .executableTarget(
            name: "Gridlet",
            path: "Sources/Gridlet"
        ),
        .testTarget(
            name: "GridletTests",
            dependencies: ["Gridlet"],
            path: "Tests/GridletTests"
        ),
    ]
)
