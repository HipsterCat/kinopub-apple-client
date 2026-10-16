//
//  TitleLogoSlot.swift
//  KinoPubUI
//
//  One slot: the title logo, or the lettered name after a confirmed miss. Empty
//  (layout reserved) while a lookup is in flight. State lives in ``TitleLogoSession``
//  so the banner cell and every hero share it.
//

import SwiftUI

/// The hero / banner title slot. See ``TitleLogoPresentationPolicy``.
public struct TitleLogoSlot<Title: View>: View {
  private let resolution: TitleLogoResolution
  private let maxWidth: CGFloat
  private let maxHeight: CGFloat
  private let title: () -> Title

  @StateObject private var session: TitleLogoSession

  public init(
    resolution: TitleLogoResolution,
    maxWidth: CGFloat,
    maxHeight: CGFloat,
    policy: TitleLogoPresentationPolicy = .whenResolved,
    @ViewBuilder title: @escaping () -> Title
  ) {
    self.resolution = resolution
    self.maxWidth = maxWidth
    self.maxHeight = maxHeight
    self.title = title
    _session = StateObject(wrappedValue: TitleLogoSession(policy: policy))
  }

  public init(
    url: URL?,
    lookupComplete: Bool,
    maxWidth: CGFloat,
    maxHeight: CGFloat,
    policy: TitleLogoPresentationPolicy = .whenResolved,
    @ViewBuilder title: @escaping () -> Title
  ) {
    self.init(
      resolution: TitleLogoResolution(url: url, lookupComplete: lookupComplete),
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      policy: policy,
      title: title
    )
  }

  public var body: some View {
    // A cached decode must paint on this frame, before `.onAppear` runs the session.
    let cached = resolution.url.flatMap { Artwork.cachedImage(for: $0) }
    let mark: TitleLogoMark = cached != nil ? .logo : session.mark
    ZStack(alignment: .leading) {
      switch mark {
      case .logo:
        logoView(
          session.image.map { Image(platformImage: $0) }
            ?? cached.map { Image(platformImage: $0) }
        )
      case .text:
        title()
      case .empty:
        Color.clear
      }
    }
    // Reserved to the logo box so empty → logo / text does not shove the actions.
    .frame(maxWidth: maxWidth, minHeight: maxHeight, maxHeight: maxHeight, alignment: .leading)
    .onAppear { session.setResolution(resolution) }
    .onChange(of: resolution) { _, new in
      session.setResolution(new)
    }
  }

  @ViewBuilder
  private func logoView(_ image: Image?) -> some View {
    if let image {
      image
        .resizable()
        .scaledToFit()
        .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .leading)
    } else {
      Color.clear
    }
  }
}
