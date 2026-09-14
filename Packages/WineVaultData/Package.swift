// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "WineVaultData",
    platforms: [
        .iOS("26.0"),
        .macOS(.v15),
    ],
    products: [
        .library(name: "WineVaultData", targets: ["WineVaultData"]),
    ],
    dependencies: [
        .package(path: "../WineVaultDomain"),
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.10.0"),
    ],
    targets: [
        .target(
            name: "WineVaultData",
            dependencies: [
                "WineVaultDomain",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .testTarget(
            name: "WineVaultDataTests",
            dependencies: [
                "WineVaultData",
                "WineVaultDomain",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
    ]
)
