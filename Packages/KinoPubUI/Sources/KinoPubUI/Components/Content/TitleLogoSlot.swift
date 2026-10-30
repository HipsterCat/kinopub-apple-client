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
  private let onMarkChange: ((TitleLogoMark) -> Void)?
  private let onDeliveredLanguageChange: ((WorkerArtworkLanguageTag?) -> Void)?
  private let title: () -> Title

  @StateObject private var session: TitleLogoSession

  public init(
    resolution: TitleLogoResolution,
    maxWidth: CGFloat,
    maxHeight: CGFloat,
    textMaxWidth: CGFloat? = nil,
    policy: TitleLogoPresentationPolicy = .whenResolved,
    onMarkChange: ((TitleLogoMark) -> Void)? = nil,
    onDeliveredLanguageChange: ((WorkerArtworkLanguageTag?) -> Void)? = nil,
    @ViewBuilder title: @escaping () -> Title
  ) {
    self.resolution = resolution
    self.maxWidth = maxWidth
    self.maxHeight = maxHeight
    self.textMaxWidth = textMaxWidth
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
      policy: policy,
      onMarkChange: onMarkChange,
      onDeliveredLanguageChange: onDeliveredLanguageChange,
      title: title
    )
  }

  public var body: some View {
    // A cached decode must paint on this frame, before `.onAppear` runs the session.
    let cached = resolution.url.flatMap { Artwork.cachedImage(for: $0) }
    let mark: TitleLogoMark = cached != nil ? .logo : session.mark
    Group {
      switch mark {
      case .logo:
        logoView(
          session.image.map { Image(platformImage: $0) }
            ?? cached.map { Image(platformImage: $0) }
        )
      case .text:
        title()
          .frame(maxWidth: textMaxWidth ?? maxWidth, alignment: .leading)
          .transition(.opacity)
      case .empty:
        Color.clear
          .frame(maxWidth: maxWidth, minHeight: maxHeight, maxHeight: maxHeight, alignment: .topLeading)
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

  @ViewBuilder
  private func logoView(_ image: Image?) -> some View {
    if let image {
      image
        .resizable()
        .scaledToFit()
        .frame(maxWidth: maxWidth, maxHeight: maxHeight, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .transition(.opacity)
    } else {
      Color.clear
    }
  }
}
