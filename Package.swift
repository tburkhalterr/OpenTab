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
                .linkedFramework("ApplicationServices")
            ]
        ),
        .testTarget(
            name: "OpenTabTests",
            dependencies: ["OpenTab"],
            path: "Tests/OpenTabTests"
        )
    ]
)
