// swift-tools-version: 5.9
import PackageDescription

// Focused tests of the actual production transport, schemas and local parser.
let package = Package(
    name: "AuraAI",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AuraAI", targets: ["AuraAI"])],
    targets: [
        .target(name: "AuraAI", path: "AuraHealth/Services", sources: ["AI", "KeychainService.swift", "LocalLabParser.swift"]),
        .testTarget(name: "AuraAITests", dependencies: ["AuraAI"], path: "Tests")
    ]
)
