//
//  CatalogMediaRow.swift
//  KinoPubUI
//
//  Poster + title + meta table row for Catalog / Search list layout
//  (macOS search list reference: compact poster, title, type · genre · year).
//

import SwiftUI
import KinoPubBackend

/// A full-width list row for a media title: small poster, title, secondary meta.
public struct CatalogMediaRow: View {
  public let card: MediaCard

  public init(card: MediaCard) {
    self.card = card
  }

  public init(item: MediaItem) {
    self.card = MediaCard(item)
  }

  public var body: some View {
    HStack(alignment: .center, spacing: Metrics.spacing) {
      CachedRemoteImage(url: URL(string: card.posterURL), contentMode: .fill)
        .frame(width: Metrics.posterWidth, height: Metrics.posterHeight)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.posterCorner, style: .continuous))

      VStack(alignment: .leading, spacing: 4) {
        Text(card.title)
          .font(TypeScale.detailSection)
          .foregroundStyle(Color.KinoPub.text)
          .lineLimit(2)
          .multilineTextAlignment(.leading)

        if let meta = metaLine, !meta.isEmpty {
          Text(meta)
            .font(TypeScale.cardMeta)
            .foregroundStyle(Color.KinoPub.subtitle)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, Metrics.verticalPadding)
    .contentShape(Rectangle())
  }

  /// "Series · 2024 Drama" — same facts the poster caption already carries.
  private var metaLine: String? {
    var parts: [String] = []
    if card.isSeries {
      parts.append(String(localized: String.LocalizationValue("Kind_series_One")))
    }
    if let caption = card.catalogCaption() {
      parts.append(caption)
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  private enum Metrics {
    static let spacing: CGFloat = 14
    static let posterWidth: CGFloat = 52
    static let posterHeight: CGFloat = 78
    static let posterCorner: CGFloat = 8
    static let verticalPadding: CGFloat = 10
  }
}

#if DEBUG
#Preview("Catalog list row") {
  VStack(spacing: 0) {
    CatalogMediaRow(card: MediaCard(
      id: 1,
      posterURL: "",
      title: "Insidious: Out of the Further",
      isSeries: false,
      year: 2026
    ))
    Divider()
    CatalogMediaRow(card: MediaCard(
      id: 2,
      posterURL: "",
      title: "The Last Airbender",
      isSeries: true,
      year: 2010
    ))
  }
  .padding(.horizontal)
  .background(Color.KinoPub.background)
}
#endif
