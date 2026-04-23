// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftDICOMDecoder",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v13),
        .macOS(.v12),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "DicomCore", targets: ["DicomCore"]),
        .library(name: "DicomSwiftUI", targets: ["DicomSwiftUI"])
    ],
    targets: [
        .target(
            name: "DicomCore",
            dependencies: [],
            path: "Sources/DicomCore",
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "DicomSwiftUI",
            dependencies: ["DicomCore"],
            path: "Sources/DicomSwiftUI"
        ),
        .testTarget(
            name: "DicomCoreTests",
            dependencies: ["DicomCore"],
            path: "Tests/DicomCoreTests",
            exclude: ["Fixtures"]
        )
    ]
)
