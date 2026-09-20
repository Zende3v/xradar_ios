// swift-tools-version: 6.2
import PackageDescription

// Pure Swift layers of EONA, free of UIKit/SwiftUI/CoreLocation so every rule
// is unit-testable without a simulator:
//   EonaCore — domain models, geometry, route maths, report relevance,
//                guidance text, sun cycle, nearby ranking.
//   EonaData — the single backend API client, DTOs, repositories, fixtures.
let package = Package(
    name: "EonaKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EonaCore", targets: ["EonaCore"]),
        .library(name: "EonaData", targets: ["EonaData"]),
    ],
    targets: [
        .target(name: "EonaCore"),
        .target(name: "EonaData", dependencies: ["EonaCore"]),
        .testTarget(name: "EonaCoreTests", dependencies: ["EonaCore"]),
        .testTarget(name: "EonaDataTests", dependencies: ["EonaData", "EonaCore"]),
    ]
)
