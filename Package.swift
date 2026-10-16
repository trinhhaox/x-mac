// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Xmac",
    defaultLocalization: "vi",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Xmac", targets: ["Xmac"])
    ],
    targets: [
        .executableTarget(
            name: "Xmac",
            path: "Sources",
            resources: [
                .process("LocalizationResources")
            ]
        ),
        .testTarget(
            name: "XmacTests",
            dependencies: ["Xmac"],
            path: "Tests"
        )
    ]
)
