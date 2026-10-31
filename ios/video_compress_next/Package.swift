// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

// No FlutterFramework dependency: Flutter 3.38 and older do not provide that
// package, and newer Flutter builds the plugin without it too.
let package = Package(
    name: "video_compress_next",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "video-compress-next", targets: ["video_compress_next"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "video_compress_next",
            dependencies: [],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
