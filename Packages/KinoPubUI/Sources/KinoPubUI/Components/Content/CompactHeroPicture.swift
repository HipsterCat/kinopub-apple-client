//
//  CompactHeroPicture.swift
//  KinoPubUI
//
//  The phone hero's picture, shared by the Home banner and the title page so both read
//  the same (Sasha, 2026-11-10: the banner was the one that looked right).
//

import SwiftUI

#if os(iOS)
/// A 16:10 still under the bars, and the same picture carried on above it (under the
/// status bar) and below it (under the words) by the system's background extension —
/// that whole layer blurred into glass, with the sharp still over it fading out toward
/// both edges, so it melts into the glass instead of stopping on a line (Sasha,
/// 2026-10-30). Cropped, the still keeps its middle; the layer is `height` tall from
/// the top of the screen.
public struct CompactHeroPicture: View {
  private let urls: [URL]
  private let width: CGFloat
  private let pictureWidth: CGFloat
  private let height: CGFloat
  private let topBleed: CGFloat
  private let onLoaded: (() -> Void)?
  private let onFailed: (() -> Void)?

  /// `pictureWidth`: wider than `width` when the picture drifts (the banner's pager).
  public init(urls: [URL], width: CGFloat, pictureWidth: CGFloat? = nil, height: CGFloat,
              topBleed: CGFloat, onLoaded: (() -> Void)? = nil, onFailed: (() -> Void)? = nil) {
    self.urls = urls
    self.width = width
    self.pictureWidth = pictureWidth ?? width
    self.height = height
    self.topBleed = topBleed
    self.onLoaded = onLoaded
    self.onFailed = onFailed
  }

  /// The phone's still: 16:10 of the width.
  public static func stillHeight(width: CGFloat) -> CGFloat { (width * 10 / 16).rounded() }

  public var body: some View {
    let still = Self.stillHeight(width: width)
    let below = max(height - topBleed - still, 0)
    ZStack(alignment: .top) {
      FallbackRemoteImage(urls: urls, contentMode: .fill)
        .frame(width: pictureWidth, height: still)
        .clipped()
        .backgroundExtensionEffect()
        .safeAreaPadding(.top, topBleed)
        .safeAreaPadding(.bottom, below)
        .blur(radius: width * 0.06, opaque: true)
      FallbackRemoteImage(urls: urls, contentMode: .fill, onLoaded: onLoaded, onFailed: onFailed)
        .frame(width: pictureWidth, height: still)
        .clipped()
        .mask {
          LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: 0.22),
            .init(color: .black, location: 0.55),
            .init(color: .clear, location: 1)
          ], startPoint: .top, endPoint: .bottom)
        }
        .padding(.top, topBleed)
    }
    .frame(width: pictureWidth, height: height, alignment: .top)
  }
}
#endif

/// The phone hero's shade: its words are centred, so it is the foot alone, the way the
/// Apple TV app's phone hero has it. `start` is where it begins, as a share of the hero.
public struct CompactHeroScrim: View {
  private let start: CGFloat

  public init(start: CGFloat = 0.38) {
    self.start = start
  }

  public var body: some View {
    LinearGradient(stops: [
      .init(color: .black.opacity(0), location: start),
      .init(color: .black.opacity(0.45), location: start + (1 - start) * 0.42),
      .init(color: .black.opacity(0.85), location: 1)
    ], startPoint: .top, endPoint: .bottom)
    .allowsHitTesting(false)
  }
}
