// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "native_photo_kit",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "native-photo-kit", targets: ["native_photo_kit"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "native_photo_kit",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
