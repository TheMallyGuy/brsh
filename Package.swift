// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "brsh",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        // An xtool project should contain exactly one library product,
        // representing the main app.
        .library(
            name: "brsh",
            targets: ["brsh"]
        ),
    ],
    targets: [
        .target(
            name: "brsh"
        ),
    ]
)
