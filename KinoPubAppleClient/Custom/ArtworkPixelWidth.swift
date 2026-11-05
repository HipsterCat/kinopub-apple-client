//
//  ArtworkPixelWidth.swift
//  KinoPubAppleClient
//
//  The `w` the app asks the worker's image route for (`TitleImageRoute`).
//

import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Pixel widths for title artwork, derived once from the screen the app runs on.
///
/// Read once and kept: the Home banner and the detail hero must build the **same** URL
/// for a title so the hero draws the banner's bytes from the artwork cache. A width
/// that changed between the two would be a second download of the same logo.
@MainActor
enum ArtworkPixelWidth {
  /// Full-screen textless backdrop: the screen's native width.
  static var backdrop: Int { screen }

  /// Title logo: the widest place it is drawn is the tvOS title page's hero, 680 pt of a
  /// 1920 pt screen (`MediaItemHeroView.logoMaxWidth`); the banner draws it narrower
  /// (28 %). So a little over a third of the screen's pixels, not half: 1360 px on an
  /// Apple TV 4K instead of 1920, 680 on a 1080p one (Sasha, 2026-11-05).
  /// iPhone, iPad and Mac keep half the screen: an iPhone's hero logo (360 pt at 3x) is
  /// wider than a third of its long side.
  static var logo: Int {
#if os(tvOS)
    Int((Double(screen) * 680 / 1920).rounded(.up))
#else
    screen / 2
#endif
  }

  /// Native pixels across the longer side — Apple TV 4K reports 3840, not the 1920 pt
  /// UI buffer; an iPhone in portrait still reports its long side, since a banner
  /// rotates with it.
  private static let screen: Int = {
#if canImport(UIKit)
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let screen = scenes.first(where: { $0.activationState == .foregroundActive })?.screen
      ?? scenes.first?.screen
    guard let bounds = screen?.nativeBounds.size else { return 1920 }
    return Int(max(bounds.width, bounds.height))
#elseif canImport(AppKit)
    guard let screen = NSScreen.main else { return 1920 }
    return Int(max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor)
#else
    return 1920
#endif
  }()
}
