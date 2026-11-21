//
//  ArtworkPixelWidth.swift
//  KinoPubAppleClient
//
//  The `w` the app asks the worker's image route for (`TitleImageRoute`).
//

import Foundation
import KinoPubMetadata
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
import CoreGraphics
#endif

/// Pixel widths for title artwork, derived once from the screen the app runs on.
///
/// Read once and kept: the Home banner and the detail hero must build the **same** URL
/// for a title so the hero draws the banner's bytes from the artwork cache. A width
/// that changed between the two would be a second download of the same logo.
@MainActor
enum ArtworkPixelWidth {
  /// Full-screen textless backdrop: the screen's native width, capped on MacBook-class
  /// panels at 2400 once the worker serves via wsrv.nl WebP (KP-68), and capped at
  /// 1920 on Apple TV 4K to avoid large decodes. Snapped onto ``TitleImageRoute/bucketedWidth``.
  static var backdrop: Int {
    TitleImageRoute.bucketedWidth(.backdrop, pixels: rawBackdrop)
  }

  /// One logo `w` per platform: largest slot × scale, then TMDB 780 / 1280 — never
  /// `/original`. Slots are `MediaItemHeroView.logoMaxWidth` (680 tvOS / 440 Mac /
  /// 360 iPhone). A 5K iMac used to send `screen/2` (2560) and get a 2000–4000 px PNG.
  static var logo: Int {
    TitleImageRoute.bucketedWidth(.logo, pixels: rawLogo)
  }

  private static var rawBackdrop: Int {
#if os(macOS)
    macBackdrop
#else
    min(screen, 1920)
#endif
  }

  /// Drawn pixels of the largest logo slot. Scale is the platform's typical density
  /// (2× tvOS 4K / Mac, 3× iPhone), not the live window — Home and the title page
  /// must build the same URL.
  private static var rawLogo: Int {
#if os(tvOS)
    Int((680 * 2 as CGFloat).rounded(.up))
#elseif os(macOS)
    Int((440 * 2 as CGFloat).rounded(.up))
#else
    Int((360 * 3 as CGFloat).rounded(.up))
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

#if os(macOS)
  /// Worker `w=` for backdrops on Mac. MacBook panels (~286–360 mm wide) cap at 2400;
  /// iMac / Studio-class (≥ ~400 mm) keep native Retina width so a large desktop is not starved.
  private static let macBookBackdropCap = 2400

  private static let macBackdrop: Int = {
    guard let screen = NSScreen.main else { return min(Self.screen, macBookBackdropCap) }
    let native = Int(max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor)
    return isMacBookClassDisplay(screen) ? min(native, macBookBackdropCap) : native
  }()

  /// Physical panel width separates laptops from desktop displays better than pixel count
  /// (a 16″ MBP on "More Space" can exceed 4k px while still being a laptop).
  private static func isMacBookClassDisplay(_ screen: NSScreen) -> Bool {
    let laptopWidthMM: CGFloat = 400
    guard
      let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
    else {
      // Unknown display id: treat ≤ 16″ Retina native (3456) as laptop-class.
      return Int(max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor) <= 3456
    }
    let mm = CGDisplayScreenSize(CGDirectDisplayID(number.uint32Value))
    if mm.width > 0 { return mm.width < laptopWidthMM }
    return Int(max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor) <= 3456
  }
#endif
}
