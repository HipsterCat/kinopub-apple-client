// swift-tools-version: 6.2

import PackageDescription

/// **Our model of a thing to watch** — provider-neutral. Nothing here knows kino.pub, TMDB
/// or Kinopoisk exist: each source maps its own payload into `MediaFragment`s in its own
/// package, and every surface (the player's info panel, cards, the hero) reads the merged
/// result. See the `metadata-service` skill, "The media model".
let package = Package(
  name: "KinoPubMedia",
  platforms: [.macOS(.v26), .iOS(.v26), .tvOS(.v26)],
  products: [
    .library(
      name: "KinoPubMedia",
      targets: ["KinoPubMedia"])
  ],
  targets: [
    .target(name: "KinoPubMedia"),
    .testTarget(
      name: "KinoPubMediaTests",
      dependencies: ["KinoPubMedia"])
  ],
  swiftLanguageModes: [.v5]
)
