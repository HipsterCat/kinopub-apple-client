// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "PiraticKit",
  platforms: [.macOS(.v26), .iOS(.v26), .tvOS("26.5")],
  products: [
    .library(
      name: "PiraticKit",
      targets: ["PiraticKit"])
  ],
  dependencies: [
    .package(name: "PiraticLogging", path: "../PiraticLogging")
  ],
  targets: [
    .target(
      name: "PiraticKit",
      dependencies: [
        .product(name: "PiraticLogging", package: "PiraticLogging")
      ]),
    .testTarget(
      name: "PiraticKitTests",
      dependencies: ["PiraticKit"])
  ],
  swiftLanguageModes: [.v6]
)
