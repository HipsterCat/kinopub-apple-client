// swift-tools-version: 6.2

import PackageDescription

let package = Package(
  name: "KinoPubUI",
  platforms: [.macOS(.v26), .iOS(.v26), .tvOS("26.5")],
  products: [
    .library(
      name: "KinoPubUI",
      targets: ["KinoPubUI"])
  ],
  dependencies: [
    .package(name: "KinoPubBackend", path: "../KinoPubBackend"),
    .package(name: "KinoPubLogging", path: "../KinoPubLogging"),
    .package(name: "KinoPubMedia", path: "../KinoPubMedia"),
    // Artwork pipeline. Everything Nuke-shaped stays behind `Artwork` /
    // `CachedRemoteImage` / `TVUIKitRemoteImage` — no call site imports it.
    .package(url: "https://github.com/kean/Nuke.git", from: "13.2.0"),
    // Network log with bodies and history. Everything Pulse-shaped stays behind
    // `NetworkDiagnostics` / `NetworkConsoleView`.
    .package(url: "https://github.com/kean/Pulse.git", from: "5.2.3")
  ],
  targets: [
    .target(
      name: "KinoPubUI",
      dependencies: [
        .product(name: "KinoPubBackend", package: "KinoPubBackend"),
        .product(name: "KinoPubLogging", package: "KinoPubLogging"),
        .product(name: "KinoPubMedia", package: "KinoPubMedia"),
        .product(name: "Nuke", package: "Nuke"),
        // `TVPosterView` display path (`loadImage(into:)`). Imported only from
        // `TVUIKitRemoteImage` — no call site takes NukeExtensions. NukeUI is gone
        // with `ArtworkImage`.
        .product(name: "NukeExtensions", package: "Nuke"),
        .product(name: "Pulse", package: "Pulse"),
        .product(name: "PulseUI", package: "Pulse"),
        .product(name: "PulseProxy", package: "Pulse")
      ],
      // Declared explicitly: relying on SwiftPM to infer the asset catalogue meant
      // `Bundle.module` was not generated on every toolchain, and every
      // `Image(..., bundle: .module)` failed to compile.
      resources: [.process("Media.xcassets")]),
    .testTarget(
      name: "KinoPubUITests",
      dependencies: ["KinoPubUI", .product(name: "KinoPubMedia", package: "KinoPubMedia")])
  ],
  // Tools 6.2 is required for `.v26` platforms; stay on language mode 5 until
  // ObservableObject view models move to @Observable (see research/en/04 §4.4).
  swiftLanguageModes: [.v5]
)
