//
//  TitleLogoSlot.swift
//  KinoPubUI
//
//  One slot: the title logo, or the lettered name after a confirmed miss. Empty
//  (layout reserved) while a lookup is in flight. State lives in ``TitleLogoSession``
//  so the banner cell and every hero share it.
//

import KinoPubMetadata
import SwiftUI

/// The hero / banner title slot. See ``TitleLogoPresentationPolicy``.
public struct TitleLogoSlot<Title: View>: View {
  private let resolution: TitleLogoResolution
  private let maxWidth: CGFloat
  private let maxHeight: CGFloat
  /// Lettered title width when it differs from the logo box (detail hero uses ~80% of
  /// the column). `nil` keeps the logo `maxWidth`.
  private let textMaxWidth: CGFloat?
  /// Where a logo or a name narrower than the slot sits in it: leading on the detail
  /// hero and the wide Home hero, centred in the phone's centred hero.
  private let alignment: HorizontalAlignment
  private let onMarkChange: ((TitleLogoMark) -> Void)?
  private let onDeliveredLanguageChange: ((WorkerArtworkLanguageTag?) -> Void)?
  private let title: () -> Title

  @StateObject private var session: TitleLogoSession
  @Environment(\.displayScale) private var displayScale

  public init(
    resolution: TitleLogoResolution,
    maxWidth: CGFloat,
    maxHeight: CGFloat,
    textMaxWidth: CGFloat? = nil,
    alignment: HorizontalAlignment = .leading,
    policy: TitleLogoPresentationPolicy = .whenResolved,
    onMarkChange: ((TitleLogoMark) -> Void)? = nil,
    onDeliveredLanguageChange: ((WorkerArtworkLanguageTag?) -> Void)? = nil,
    @ViewBuilder title: @escaping () -> Title
  ) {
    self.resolution = resolution
    self.maxWidth = maxWidth
    self.maxHeight = maxHeight
    self.textMaxWidth = textMaxWidth
    self.alignment = alignment
    self.onMarkChange = onMarkChange
    self.onDeliveredLanguageChange = onDeliveredLanguageChange
    self.title = title
    _session = StateObject(wrappedValue: TitleLogoSession(policy: policy))
  }

  public init(
    url: URL?,
    lookupComplete: Bool,
    maxWidth: CGFloat,
    maxHeight: CGFloat,
    textMaxWidth: CGFloat? = nil,
    alignment: HorizontalAlignment = .leading,
    policy: TitleLogoPresentationPolicy = .whenResolved,
    onMarkChange: ((TitleLogoMark) -> Void)? = nil,
    onDeliveredLanguageChange: ((WorkerArtworkLanguageTag?) -> Void)? = nil,
    @ViewBuilder title: @escaping () -> Title
  ) {
    self.init(
      resolution: TitleLogoResolution(url: url, lookupComplete: lookupComplete),
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      textMaxWidth: textMaxWidth,
      alignment: alignment,
      policy: policy,
      onMarkChange: onMarkChange,
      onDeliveredLanguageChange: onDeliveredLanguageChange,
      title: title
    )
  }

  public var body: some View {
    // A cached decode must paint on this frame, before `.onAppear` runs the session.
    let cached = resolution.url.flatMap { Artwork.cachedImage(for: $0) }
    let decodedLogo = session.image ?? cached
    // A logo taller than it is wide is a vertical lockup, unreadable at the slot's
    // height: the lettered title stands in (Sasha, 2026-10-30, Mission: Impossible).
    let tooTall = decodedLogo.map { $0.size.height > 0 && $0.size.width / $0.size.height < Self.minimumAspect } ?? false
    let mark: TitleLogoMark = tooTall ? .text : (cached != nil ? .logo : session.mark)
    Group {
      switch mark {
      case .logo:
        let decoded = session.image ?? cached
        logoView(decoded.map { Image(platformImage: $0) }, size: decoded?.size)
      case .text:
        title()
          .frame(maxWidth: textMaxWidth ?? maxWidth, alignment: Alignment(horizontal: alignment, vertical: .center))
          .transition(.opacity)
      case .empty:
        Color.clear
          .frame(maxWidth: maxWidth, minHeight: maxHeight, maxHeight: maxHeight, alignment: Alignment(horizontal: alignment, vertical: .top))
      }
    }
    // A logo or lettered title that arrives after the first frame fades in; one painted
    // from the cache is there on the first frame and has nothing to animate.
    .animation(.easeInOut(duration: 0.4), value: mark)
    .animation(.easeInOut(duration: 0.4), value: session.image != nil)
    .onAppear {
      session.setResolution(resolution)
      onMarkChange?(mark)
      publishDeliveredLanguage()
    }
    .onChange(of: resolution) { _, new in
      session.setResolution(new)
    }
    .onChange(of: mark) { _, new in
      onMarkChange?(new)
    }
    .onChange(of: session.deliveredLanguage) { _, _ in
      publishDeliveredLanguage()
    }
  }

  private func publishDeliveredLanguage() {
    let fromRequest = resolution.url.flatMap { Artwork.workerLanguage(on: $0) }
    onDeliveredLanguageChange?(fromRequest ?? session.deliveredLanguage)
  }

  /// As big as fits `maxWidth` × `maxHeight` at the logo's own aspect, and no bigger:
  /// the slot is as wide as the logo is drawn, so what sits under it can match it (the
  /// detail hero's subtitle). A `maxWidth` frame reported the whole box for a tall logo.
  @ViewBuilder
  private func logoView(_ image: Image?, size: CGSize?) -> some View {
    if let image {
      let fitted = Self.fittedSize(of: size ?? .zero, pixelWidth: pixelWidth(of: image, size: size),
                                   maxWidth: maxWidth, maxHeight: maxHeight, displayScale: displayScale)
      image
        .resizable()
        .scaledToFit()
        .frame(maxWidth: fitted.width, maxHeight: fitted.height, alignment: Alignment(horizontal: alignment, vertical: .top))
        .fixedSize(horizontal: false, vertical: true)
        .transition(.opacity)
        .shadow(color: .black.opacity(0.5), radius: 18, x: 0, y: 0)
    } else {
      Color.clear
    }
  }

  /// Width over height below which a logo is rejected. A near-square compact mark passes;
  /// a vertical lockup does not.
  static var minimumAspect: CGFloat { 0.8 }

  /// How far past its own pixels a logo may be drawn: a small TMDB logo blown up 2–3×
  /// to fill the slot read soft (Sasha, 2026-11-04). A quarter over is not seen.
  static var maximumUpscale: CGFloat { 1.25 }

  private static func fittedSize(of size: CGSize, pixelWidth: CGFloat?, maxWidth: CGFloat,
                                 maxHeight: CGFloat, displayScale: CGFloat) -> CGSize {
    guard size.width > 0, size.height > 0 else { return CGSize(width: maxWidth, height: maxHeight) }
    var scale = min(maxWidth / size.width, maxHeight / size.height)
    if let pixelWidth, pixelWidth > 0, displayScale > 0 {
      // The logo's own width in points on this screen, a little over at most.
      let native = pixelWidth / displayScale * maximumUpscale
      scale = min(scale, native / size.width)
    }
    return CGSize(width: size.width * scale, height: size.height * scale)
  }

  /// The decoded logo's width in pixels, not points: what the worker actually sent (the
  /// request asks for a width; TMDB's original can be far smaller).
  private func pixelWidth(of image: Image, size: CGSize?) -> CGFloat? {
    let cached = resolution.url.flatMap { Artwork.cachedImage(for: $0) }
    guard let decoded = session.image ?? cached else { return nil }
#if os(macOS)
    if let rep = decoded.representations.first, rep.pixelsWide > 0 { return CGFloat(rep.pixelsWide) }
    return decoded.size.width
#else
    return decoded.size.width * decoded.scale
#endif
  }
}

/// The line under the title slot: the other name, by what the slot shows — under a logo,
/// whichever name the logo's served language leaves out; under lettered type, the original
/// when it differs. Shared by the title page's hero and the Home hero, so both say the
/// same (Sasha, 2026-11-04).
public enum TitleLogoCaption {
  /// What the slot is drawing: a cached logo paints before the slot reports its mark.
  public static func resolvedMark(_ reported: TitleLogoMark, logoURL: URL?) -> TitleLogoMark {
    // The slot turned a cached logo down (too tall): it says so, and that wins.
    if reported == .text { return .text }
    if let url = logoURL, Artwork.cachedImage(for: url) != nil { return .logo }
    return reported
  }

  public static func line(mark: TitleLogoMark,
                          deliveredLanguage: WorkerArtworkLanguageTag?,
                          logoURL: URL?,
                          localized: String,
                          original: String,
                          partner: String? = nil) -> String? {
    switch mark {
    case .empty:
      return nil
    case .logo:
      let stamp = deliveredLanguage ?? logoURL.flatMap { Artwork.workerLanguage(on: $0) }
      let kind = stamp.map(TitleLogoRequestKind.init(deliveredLanguage:))
        ?? (TitleImageRoute.appLanguage == "en" ? .english : .russianPreferred)
      return kind.supplementaryUnderLogo(localized: localized, original: original, partner: partner)
    case .text:
      guard let partner else {
        guard !original.isEmpty, original != localized else { return nil }
        return original
      }
      guard partner != localized else { return nil }
      return partner
    }
  }
}

/// A column of two: the first line at its own size, the second under it proposed no more
/// than the first's width when `capsWidth` — the subtitle under a title logo wraps at the
/// logo's edge.
public struct SecondLineCappedToFirst: Layout {
  public var capsWidth: Bool
  /// Never narrower than this, however narrow the logo: a tall logo left the line a
  /// syllable wide (Sasha, 2026-10-30: 200).
  public var minimumWidth: CGFloat
  /// Leading on the title page and the wide Home hero, centred in the phone's hero.
  public var alignment: HorizontalAlignment

  public init(capsWidth: Bool, minimumWidth: CGFloat = 230, alignment: HorizontalAlignment = .leading) {
    self.capsWidth = capsWidth
    self.minimumWidth = minimumWidth
    self.alignment = alignment
  }

  private func sizes(_ proposal: ProposedViewSize, _ subviews: Subviews) -> [CGSize] {
    guard let first = subviews.first else { return [] }
    let head = first.sizeThatFits(proposal)
    let capped = max(head.width, minimumWidth)
    let width = capsWidth ? min(proposal.width ?? capped, capped) : proposal.width
    let rest = subviews.dropFirst().map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
    return [head] + rest
  }

  public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let all = sizes(proposal, subviews)
    return CGSize(width: all.map(\.width).max() ?? 0, height: all.map(\.height).reduce(0, +))
  }

  public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for (subview, size) in zip(subviews, sizes(proposal, subviews)) {
      let x = alignment == .center ? bounds.midX - size.width / 2 : bounds.minX
      subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      y += size.height
    }
  }
}
