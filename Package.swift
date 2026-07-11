// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift Package Manager required to build this package.

import PackageDescription

let package = Package(
    name: "VocaMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "VocaMac",
            targets: ["VocaMac"]
        )
    ],
    targets: [
        // Objective-C helpers used by the Swift app.
        .target(
            name: "VocaMacObjC",
            path: "Sources/VocaMacObjC",
            publicHeadersPath: "include"
        ),
        // Main application target
        .executableTarget(
            name: "VocaMac",
            dependencies: [
                "VocaMacObjC",
            ],
            path: "Sources/VocaMac",
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        // Test target
        .testTarget(
            name: "VocaMacTests",
            dependencies: ["VocaMac"],
            path: "Tests/VocaMacTests"
        )
    ]
)
