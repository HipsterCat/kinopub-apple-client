// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "PiraticMetadata",
  platforms: [.macOS(.v26), .iOS(.v26), .tvOS("26.5")],
  products: [
    .library(
      name: "PiraticMetadata",
      targets: ["PiraticMetadata"])
  ],
  dependencies: [
    .package(name: "PiraticLogging", path: "../PiraticLogging"),
    .package(name: "PiraticMedia", path: "../PiraticMedia")
  ],
  targets: [
    .target(
      name: "PiraticMetadata",
      dependencies: [
        .product(name: "PiraticLogging", package: "PiraticLogging"),
        .product(name: "PiraticMedia", package: "PiraticMedia")
      ]),
    .testTarget(
      name: "PiraticMetadataTests",
      dependencies: [
        "PiraticMetadata",
        .product(name: "PiraticMedia", package: "PiraticMedia")
      ],
      resources: [
        .copy("Fixtures")
      ])
  ],
  swiftLanguageModes: [.v6]
)
