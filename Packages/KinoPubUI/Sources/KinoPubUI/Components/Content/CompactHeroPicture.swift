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
  private let stillHeight: CGFloat?
  private let fromTop: Bool

  /// `pictureWidth`: wider than `width` when the picture drifts (the banner's pager).
  /// `stillHeight`: the sharp picture's height under the bars, 16:10 of the width when nil.
  /// `fromTop`: the sharp picture starts at the top of the screen, under the bars, with
  /// no blurred extension above it — the title page (Sasha, 2026-11-16).
  public init(urls: [URL], width: CGFloat, pictureWidth: CGFloat? = nil, height: CGFloat,
              topBleed: CGFloat, stillHeight: CGFloat? = nil, fromTop: Bool = false,
              onLoaded: (() -> Void)? = nil, onFailed: (() -> Void)? = nil) {
    self.urls = urls
    self.width = width
    self.pictureWidth = pictureWidth ?? width
    self.height = height
    self.topBleed = topBleed
    self.stillHeight = stillHeight
    self.fromTop = fromTop
    self.onLoaded = onLoaded
    self.onFailed = onFailed
  }

  /// The phone's still: 16:10 of the width.
  public static func stillHeight(width: CGFloat) -> CGFloat { (width * 10 / 16).rounded() }

  public var body: some View {
    if fromTop {
      fromTopBody
    } else {
      bannerBody
    }
  }

  /// One picture from the top edge down to the end of the still, fading out over its
  /// lower part into the same picture carried on below as blurred glass.
  private var fromTopBody: some View {
    let picture = topBleed + (stillHeight ?? Self.stillHeight(width: width))
    let below = max(height - picture, 0)
    return ZStack(alignment: .top) {
      FallbackRemoteImage(urls: urls, contentMode: .fill,
                          size: CGSize(width: pictureWidth, height: picture))
        .frame(width: pictureWidth, height: picture)
        .clipped()
        .backgroundExtensionEffect()
        .safeAreaPadding(.bottom, below)
        .blur(radius: width * 0.06, opaque: true)
      FallbackRemoteImage(urls: urls, contentMode: .fill,
                          size: CGSize(width: pictureWidth, height: picture),
                          onLoaded: onLoaded, onFailed: onFailed)
        .frame(width: pictureWidth, height: picture)
        .clipped()
        .mask {
          LinearGradient(stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: 0.6),
            .init(color: .clear, location: 1)
          ], startPoint: .top, endPoint: .bottom)
        }
    }
    .frame(width: pictureWidth, height: height, alignment: .top)
  }

  private var bannerBody: some View {
    let still = stillHeight ?? Self.stillHeight(width: width)
    let below = max(height - topBleed - still, 0)
    return ZStack(alignment: .top) {
      FallbackRemoteImage(urls: urls, contentMode: .fill,
                          size: CGSize(width: pictureWidth, height: still))
        .frame(width: pictureWidth, height: still)
        .clipped()
        .backgroundExtensionEffect()
        .safeAreaPadding(.top, topBleed)
        .safeAreaPadding(.bottom, below)
        .blur(radius: width * 0.06, opaque: true)
      FallbackRemoteImage(urls: urls, contentMode: .fill,
                          size: CGSize(width: pictureWidth, height: still),
                          onLoaded: onLoaded, onFailed: onFailed)
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

/// The phone hero's logo box, against the width — the Home banner's and the title
/// page's. 70% × 26% let every wordmark run to the edges and stand tall (Sasha,
/// 2026-11-16: «стремятся только в ширину»).
public enum CompactHeroLogo {
  public static let widthShare: CGFloat = 0.6
  public static let heightShare: CGFloat = 0.2
}

/// The phone's still under the bars, against the width: taller than 16:10, so heads
/// are not cut (Sasha, 2026-11-16) — the title page's and the Home banner's alike.
public enum CompactHeroStill {
  public static let tallness: CGFloat = 0.95
}

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
