// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PriceFetcher",
    products: [
        .library(name: "PriceFetcher", targets: ["PriceFetcher"])
    ],
    targets: [
        .target(name: "PriceFetcher", path: "Sources"),
        .testTarget(name: "PriceFetcherTests", dependencies: ["PriceFetcher"], path: "Tests")
    ]
)
