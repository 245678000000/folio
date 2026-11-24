// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Folio",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "FolioCore", targets: ["FolioCore"]),
        .executable(name: "Folio", targets: ["Folio"]),
    ],
    targets: [
        .target(
            name: "FolioCore",
            path: "Sources/FolioCore"
        ),
        .executableTarget(
            name: "Folio",
            dependencies: ["FolioCore"],
            path: "Sources/Folio"
        ),
        .testTarget(
            name: "FolioCoreTests",
            dependencies: ["FolioCore"],
            path: "Tests/FolioCoreTests"
        ),
    ]
)
