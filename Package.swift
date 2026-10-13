// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Xmac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Xmac", targets: ["Xmac"])
    ],
    targets: [
        .executableTarget(
            name: "Xmac",
            path: "Sources"
        )
    ]
)
