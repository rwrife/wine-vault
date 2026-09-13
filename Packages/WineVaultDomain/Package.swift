// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WineVaultDomain",
    platforms: [
        .iOS("26.0"),
    ],
    products: [
        .library(name: "WineVaultDomain", targets: ["WineVaultDomain"]),
    ],
    targets: [
        .target(
            name: "WineVaultDomain",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "WineVaultDomainTests",
            dependencies: ["WineVaultDomain"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
