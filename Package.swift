// swift-tools-version:5.9
// Package.swift
import PackageDescription

let package = Package(
    name: "OpenTab",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "OpenTab",
            path: "Sources/OpenTab",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("Carbon"),
                .linkedFramework("ApplicationServices"),
                // Private SkyLight framework: cross-Space switching (see CrossSpaceFocus).
                .unsafeFlags(["-F", "/System/Library/PrivateFrameworks", "-framework", "SkyLight"])
            ]
        ),
        .testTarget(
            name: "OpenTabTests",
            dependencies: ["OpenTab"],
            path: "Tests/OpenTabTests"
        )
    ]
)
