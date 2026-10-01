//
//  MediaListRowView.swift
//  KinoPubUI
//
//  A full-width text row for a list of collections. No cover art: the row is
//  title + meta on the page background, which is the shipped look.
//
//  **Background-art hook:** `backgroundArtURL` is the planned upgrade — the list's
//  own cover (a collection's `posters.big`) painted behind the text with a scrim,
//  the way the detail hero carries its artwork. Nothing feeds it yet on purpose
//  ("lists without covers for now"); the rendering path exists so turning it on is
//  a one-line change at the call site, not a redesign.
//

import SwiftUI

public struct MediaListRowView: View {

  public let title: String
  /// Secondary line under the title — "24 titles · 1.2K watchers". Built by the
  /// caller; the row holds no formatting rules of its own.
  public let meta: String?
  /// Future cover art behind the text — see the type's doc comment. Nil today.
  public let backgroundArtURL: URL?

  public init(title: String, meta: String? = nil, backgroundArtURL: URL? = nil) {
    self.title = title
    self.meta = meta
    self.backgroundArtURL = backgroundArtURL
  }

  public var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: Self.titleMetaSpacing) {
        Text(title)
          .font(Self.titleFont)
          .foregroundStyle(Color.KinoPub.text)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        if let meta, !meta.isEmpty {
          Text(meta)
            .font(Self.metaFont)
            .foregroundStyle(Color.KinoPub.subtitle)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Self.contentInset)
    .padding(.vertical, Self.verticalPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(backgroundArt)
    .clipShape(Self.shape)
    .contentShape(Self.shape)
  }

  /// Nothing paints until `backgroundArtURL` is fed: the row sits on the page (or on
  /// the system card platter on tvOS). With art, the scrim keeps the text readable —
  /// same dark-scrim rule as every other artwork-backed label in the app.
  @ViewBuilder
  private var backgroundArt: some View {
    if let backgroundArtURL {
      ZStack {
        CachedRemoteImage(url: backgroundArtURL, contentMode: .fill)
        // Text sits on the leading edge — the scrim is darkest under it.
        LinearGradient(
          colors: [Color.KinoPub.background.opacity(0.85), Color.KinoPub.background.opacity(0.25)],
          startPoint: .leading,
          endPoint: .trailing
        )
      }
    }
  }

  private static let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)

#if os(tvOS)
  private static let titleFont: Font = TypeScale.detailSection
  private static let metaFont: Font = TypeScale.cardTitle
  private static let titleMetaSpacing: CGFloat = 8
  private static let contentInset: CGFloat = 32
  private static let verticalPadding: CGFloat = 24
#else
  private static let titleFont: Font = TypeScale.detailSection
  private static let metaFont: Font = TypeScale.cardTitle
  private static let titleMetaSpacing: CGFloat = 4
  private static let contentInset: CGFloat = 16
  private static let verticalPadding: CGFloat = 12
#endif
}

#if DEBUG
#Preview("List rows") {
  VStack(spacing: 12) {
    MediaListRowView(title: "Топ 250 фильмов", meta: "250 titles · 1.2M watchers")
    MediaListRowView(title: "Оскар 2026 — все номинанты", meta: "38 titles")
    MediaListRowView(
      title: "С background art (hook demo)",
      meta: "12 titles",
      backgroundArtURL: URL(string: "https://cdn.kino.pub/example.jpg")
    )
  }
  .padding()
  .background(Color.KinoPub.background)
}
#endif
