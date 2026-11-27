//
//  BestVideoQualityFinder.swift
//  Piratic
//
//  Created by Kirill Kunst on 11.08.2023.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import SystemConfiguration
import Reachability
import KinoPubBackend

@MainActor
struct BestVideoQualityFinder {

#if canImport(UIKit) && !os(macOS)
  /// Vertical display capability in pixels, matched against `FileInfo.resolution` (e.g. 1080 from "1080p").
  /// Uses `nativeBounds` so Apple TV 4K reports ~2160 rather than the 1080pt UI buffer.
  private static var deviceCapabilitySize: CGFloat {
    guard let screen = preferredScreen() else { return 1080 }
    let pixels = screen.nativeBounds.size
    return min(pixels.width, pixels.height)
  }

  private static func preferredScreen() -> UIScreen? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    if let active = scenes.first(where: { $0.activationState == .foregroundActive }) {
      return active.screen
    }
    return scenes
      .max {
        min($0.screen.nativeBounds.width, $0.screen.nativeBounds.height)
          < min($1.screen.nativeBounds.width, $1.screen.nativeBounds.height)
      }?
      .screen
  }
#endif

  private static func currentNetworkStatus() -> Reachability.Connection {
    guard let reachability = try? Reachability() else { return .unavailable }
    return reachability.connection
  }

  private static func isConnectionGood() -> Bool {
    currentNetworkStatus() == .wifi
  }

  /// Prefers **hls4** at the highest available rung. kino.pub's hls4 master is adaptive, but
  /// the CDN still stamps a different URL per `files[]` entry — pick the max-quality one,
  /// never `http` / `hls` / `hls2` first (KP-35).
  static func findBestURL(for files: [FileInfo]) -> String {
    let withHLS4 = files.filter { !$0.url.hls4.isEmpty }

#if canImport(UIKit) && !os(macOS)
    if isConnectionGood(), !withHLS4.isEmpty {
      let capability = Int(deviceCapabilitySize)
      var bestURL = ""
      var closestResolutionDifference = Int.max
      for fileInfo in withHLS4 {
        let resolutionDifference = abs(fileInfo.resolution - capability)
        if fileInfo.resolution <= capability && resolutionDifference < closestResolutionDifference {
          bestURL = fileInfo.url.hls4
          closestResolutionDifference = resolutionDifference
        }
      }
      if !bestURL.isEmpty { return bestURL }
    }
#endif

    if let best = withHLS4.max(by: { $0.resolution < $1.resolution }) {
      return best.url.hls4
    }
    if let hls2 = files.filter({ !$0.url.hls2.isEmpty }).max(by: { $0.resolution < $1.resolution }) {
      return hls2.url.hls2
    }
    if let hls = files.filter({ !$0.url.hls.isEmpty }).max(by: { $0.resolution < $1.resolution }) {
      return hls.url.hls
    }
    if let http = files.filter({ !$0.url.http.isEmpty }).max(by: { $0.resolution < $1.resolution }) {
      return http.url.http
    }
    return ""
  }
}
