// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "PiraticLogging",
  platforms: [.macOS(.v26), .iOS(.v26), .tvOS("26.5")],
  products: [
    .library(
      name: "PiraticLogging",
      targets: ["PiraticLogging"])
  ],
  targets: [
    .target(
      name: "PiraticLogging"),
    .testTarget(
      name: "PiraticLoggingTests",
      dependencies: ["PiraticLogging"])
  ],
  swiftLanguageModes: [.v6]
)
