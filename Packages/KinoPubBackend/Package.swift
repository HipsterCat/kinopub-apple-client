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
    .package(name: "PiraticLogging", path: "../PiraticLogging"),
    .package(name: "PiraticMedia", path: "../PiraticMedia")
  ],
  targets: [
    .target(
      name: "KinoPubBackend",
      dependencies: [
        .product(name: "PiraticLogging", package: "PiraticLogging"),
        .product(name: "PiraticMedia", package: "PiraticMedia")
      ],
      resources: [
        .process("Resources")
      ]),
    .testTarget(
      name: "KinoPubBackendTests",
      dependencies: [
        "KinoPubBackend",
        .product(name: "PiraticMedia", package: "PiraticMedia")
      ],
      resources: [
        .copy("Fixtures")
      ])
  ],
  swiftLanguageModes: [.v6]
)
