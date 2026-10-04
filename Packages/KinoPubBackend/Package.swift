// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "KinoPubBackend",
  defaultLocalization: "en",
  platforms: [.macOS(.v26), .iOS(.v26), .tvOS("26.5")],
  products: [
    .library(
      name: "KinoPubBackend",
      targets: ["KinoPubBackend"])
  ],
  dependencies: [
    .package(name: "KinoPubLogging", path: "../KinoPubLogging"),
    .package(name: "KinoPubMedia", path: "../KinoPubMedia")
  ],
  targets: [
    .target(
      name: "KinoPubBackend",
      dependencies: [
        .product(name: "KinoPubLogging", package: "KinoPubLogging"),
        .product(name: "KinoPubMedia", package: "KinoPubMedia")
      ],
      resources: [
        .process("Resources")
      ]),
    .testTarget(
      name: "KinoPubBackendTests",
      dependencies: [
        "KinoPubBackend",
        .product(name: "KinoPubMedia", package: "KinoPubMedia")
      ],
      resources: [
        .copy("Fixtures")
      ])
  ],
  swiftLanguageModes: [.v5]
)
