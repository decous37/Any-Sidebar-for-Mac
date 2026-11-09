// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "AnySidebarMac", platforms: [.macOS(.v14)], products: [
    .library(name: "ReadingCore", targets: ["ReadingCore"]),
    .executable(name: "AnySidebarMac", targets: ["AnySidebarMac"])
], targets: [
    .target(name: "ReadingCore"),
    .systemLibrary(name: "CSQLite"),
    .target(name: "ReadingStorage", dependencies: ["ReadingCore","CSQLite"]),
    .target(name: "DeepSeekTransport", dependencies: ["ReadingCore"]),
    .target(name: "MacServices", dependencies: ["ReadingCore"]),
    .executableTarget(name: "AnySidebarMac", dependencies: ["ReadingCore","ReadingStorage","MacServices","DeepSeekTransport"]),
    .testTarget(name: "ReadingCoreTests", dependencies: ["ReadingCore"]),
    .testTarget(name: "ReadingStorageTests", dependencies: ["ReadingStorage","ReadingCore"]),
    .testTarget(name: "DeepSeekTransportTests", dependencies: ["DeepSeekTransport","ReadingCore"]),
    .testTarget(name: "MacServicesTests", dependencies: ["MacServices","ReadingCore"]),
])
