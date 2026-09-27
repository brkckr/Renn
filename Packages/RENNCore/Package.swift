// swift-tools-version: 6.0
import PackageDescription

// RENNCore holds the platform-independent layers of the app:
//   RENNDomain - value models, product rules and service contracts. It must not import
//                SwiftUI, SwiftData, AVFoundation or provider SDKs (04_ARCHITECTURE A02).
//   RENNFeatures - @MainActor @Observable ViewModels and the app router. Presentation
//                logic only: no SwiftUI views, no frame processing, no SDKs.
//   RENNFakes  - in-memory development/test implementations of the contracts. They are
//                never production adapters (see docs/adr/0001-project-foundation.md).
// Keeping these in a package lets the pure rules compile and run on any Swift toolchain,
// including Linux CI, independently of Xcode.
let package = Package(
    name: "RENNCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RENNDomain", targets: ["RENNDomain"]),
        .library(name: "RENNFeatures", targets: ["RENNFeatures"]),
        .library(name: "RENNFakes", targets: ["RENNFakes"]),
    ],
    targets: [
        .target(name: "RENNDomain"),
        .target(name: "RENNFeatures", dependencies: ["RENNDomain"]),
        .target(name: "RENNFakes", dependencies: ["RENNDomain"]),
        .testTarget(name: "RENNDomainTests", dependencies: ["RENNDomain"]),
        .testTarget(name: "RENNFakesTests", dependencies: ["RENNFakes", "RENNDomain"]),
        .testTarget(name: "RENNFeaturesTests", dependencies: ["RENNFeatures", "RENNFakes", "RENNDomain"]),
    ],
    swiftLanguageModes: [.v6]
)
