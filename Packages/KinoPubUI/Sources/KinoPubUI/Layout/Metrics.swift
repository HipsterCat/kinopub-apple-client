//
//  Metrics.swift
//  KinoPubUI
//

import SwiftUI

/// Shared hairlines, radii and spacing. Prefer `@ScaledMetric` at call sites for
/// square / circular chrome; these are the unscaled baselines.
///
/// Two of these decide the rhythm of a page of sections and must not be re-picked at a
/// call site: `sectionHeaderSpacing` is extra header → cards, `rowSpacing` is one
/// section → the next. Do not stack a large pad on top of Section’s own gap. Do not
/// subtract a rail’s focus padding from that gap either — tighten the rail’s *top*
/// inset instead of collapsing the chrome.
public enum Metrics {
  public static let cardCornerRadius: CGFloat = 14
  public static let progressBarHeight: CGFloat = 6
  public static let hairline: CGFloat = 0.5

#if os(tvOS)
  public static let cardCaptionSpacing: CGFloat = 20
  /// Titled-row spacing. Was 100; Sasha 2026-09: reduce by 20 → **80**.
  public static let rowSpacing: CGFloat = 80
  /// Extra padding under a `Section` header. The stacked **+8** is gone
  /// (`MediaPosterShelf` halves Section’s remaining default gap instead).
  public static let sectionHeaderSpacing: CGFloat = 0
  /// Section’s own header→content gap is the stack default (**8**). Sasha:
  /// cut that remaining gap in half after dropping the extra +8.
  public static let sectionHeaderToContentAdjustment: CGFloat = -4
  public static let focusPadding: CGFloat = 32
  /// Extra room for Continue Watching / landscape focus lift (wider tiles grow more
  /// in absolute points; poster shelves keep `focusPadding`).
  public static let landscapeFocusPadding: CGFloat = 56
  /// Apple TV Alerts / Light / Glyph + Title squircle.
  public static let hudSide: CGFloat = 220
  public static let hudCornerRadius: CGFloat = 36
  public static let hudGlyphPointSize: CGFloat = 56
  public static let hudGlyphTitleSpacing: CGFloat = 16
  public static let hudContentInset: CGFloat = 28
#else
  public static let cardCaptionSpacing: CGFloat = 6
  public static let rowSpacing: CGFloat = 36
  public static let sectionHeaderSpacing: CGFloat = 18
  public static let focusPadding: CGFloat = 4
  /// The same as `focusPadding` off tvOS, and that is the point. It is lift room for
  /// the focus engine, which only exists on TV; giving landscape rails their own
  /// number here made Continue Watching sit 4pt further from its header than every
  /// poster rail, and 4pt further from the section under it.
  public static let landscapeFocusPadding: CGFloat = focusPadding
  /// Music-style confirmation HUD.
  public static let hudSide: CGFloat = 154
  public static let hudCornerRadius: CGFloat = 28
  public static let hudGlyphPointSize: CGFloat = 44
  public static let hudGlyphTitleSpacing: CGFloat = 12
  public static let hudContentInset: CGFloat = 20
#endif
}
