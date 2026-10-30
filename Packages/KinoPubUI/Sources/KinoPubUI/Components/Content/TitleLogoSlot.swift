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
      let fitted = Self.fittedSize(of: size ?? .zero, maxWidth: maxWidth, maxHeight: maxHeight)
      image
        .resizable()
        .scaledToFit()
        .frame(maxWidth: fitted.width, maxHeight: fitted.height, alignment: Alignment(horizontal: alignment, vertical: .top))
        .fixedSize(horizontal: false, vertical: true)
        .transition(.opacity)
    } else {
      Color.clear
    }
  }

  /// Width over height below which a logo is rejected. A near-square compact mark passes;
  /// a vertical lockup does not.
  static var minimumAspect: CGFloat { 0.8 }

  private static func fittedSize(of size: CGSize, maxWidth: CGFloat, maxHeight: CGFloat) -> CGSize {
    guard size.width > 0, size.height > 0 else { return CGSize(width: maxWidth, height: maxHeight) }
    let scale = min(maxWidth / size.width, maxHeight / size.height)
    return CGSize(width: size.width * scale, height: size.height * scale)
  }
}
