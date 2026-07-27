// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Deadwood",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Deadwood", targets: ["Deadwood"])
    ],
    targets: [
        .executableTarget(
            name: "Deadwood",
            path: "Sources/Deadwood"
        ),
        .testTarget(
            name: "DeadwoodTests",
            dependencies: ["Deadwood"],
            path: "Tests/DeadwoodTests"
        )
    ]
)
