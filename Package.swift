// swift-tools-version: 6.2
import PackageDescription

// Swift 6 language mode, every warning an error. macOS 26 is the floor of the Mac app, iOS 18 of the iPhone app.
let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "purlay-swift",
    platforms: [.macOS(.v26), .iOS(.v18)],
    products: [
        .library(name: "PurlayContract", targets: ["PurlayContract"]),
        .library(name: "PurlayTokens", targets: ["PurlayTokens"]),
        .library(name: "PurlayKit", targets: ["PurlayKit"]),
        .library(name: "PurlayTestSupport", targets: ["PurlayTestSupport"]),
    ],
    targets: [
        .target(name: "PurlayContract", swiftSettings: strict),
        .target(name: "PurlayTokens", swiftSettings: strict),
        .target(name: "PurlayKit", dependencies: ["PurlayContract"], swiftSettings: strict),
        .target(name: "PurlayTestSupport", dependencies: ["PurlayKit", "PurlayContract"], swiftSettings: strict),
        .testTarget(name: "PurlayContractTests", dependencies: ["PurlayContract"], swiftSettings: strict),
        .testTarget(name: "PurlayTokensTests", dependencies: ["PurlayTokens"], swiftSettings: strict),
        .testTarget(name: "PurlayKitTests", dependencies: ["PurlayKit"], swiftSettings: strict),
        .testTarget(
            name: "PurlayTestSupportTests", dependencies: ["PurlayTestSupport", "PurlayKit", "PurlayContract"],
            swiftSettings: strict),
    ],
    swiftLanguageModes: [.v6]
)
