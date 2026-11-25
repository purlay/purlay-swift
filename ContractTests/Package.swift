// swift-tools-version: 6.2
import PackageDescription

// The real client against a real server of the pinned version (§16.3). Gated on the environment: without a server these
// are skipped, and say so, and `scripts/contract-test` is what starts one.
let strict: [SwiftSetting] = [.treatAllWarnings(as: .error)]

let package = Package(
    name: "ContractTests",
    platforms: [.macOS(.v26), .iOS(.v18)],
    dependencies: [
        .package(path: "..")
    ],
    targets: [
        .testTarget(
            name: "ContractTests",
            dependencies: [
                .product(name: "PurlayContract", package: "purlay-swift"),
                .product(name: "PurlayKit", package: "purlay-swift"),
                .product(name: "PurlayTestSupport", package: "purlay-swift"),
            ],
            swiftSettings: strict)
    ],
    swiftLanguageModes: [.v6]
)
