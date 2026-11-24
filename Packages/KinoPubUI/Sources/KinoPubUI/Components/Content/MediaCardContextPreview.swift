//
//  MediaCardContextPreview.swift
//  KinoPubUI
//
//  Apple TV–style sneak peek for poster / video long-press: native art aspect
//  (poster 2:3, wide 16:9), full image (no centre-crop into a wrong box), and a
//  metadata footer (title + year · genre / duration / episode line) that adds
//  info the rail cell does not already show. SwiftUI surfaces use
//  `MediaCardContextPreview`; tvOS UIKit menus use
//  `TVMediaCardContextPreviewController`.
//

import SwiftUI

/// Artwork + metadata for a card's long-press sneak peek.
public struct MediaCardContextPreviewSpec: Equatable, Sendable {
  public let url: URL?
  public let aspect: CardAspect
  public let title: String
  /// Secondary line under the title — `2026 · Drama`, `1h 55m`, `S2, E5 · 42 min`, …
  public let subtitle: String?

  public init(url: URL?, aspect: CardAspect, title: String, subtitle: String? = nil) {
    self.url = url
    self.aspect = aspect
    self.title = title
    self.subtitle = subtitle.flatMap { line in
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      return trimmed.isEmpty ? nil : trimmed
    }
  }

  /// Art box only — footer is laid out on top of this in the preview view.
  public var artSize: CGSize {
    switch aspect {
    case .poster: return CGSize(width: 280, height: 420)
    case .landscape: return CGSize(width: 340, height: 191)
    case .square: return CGSize(width: 280, height: 280)
    }
  }

  /// Full peek including the metadata footer (preferredContentSize for UIKit).
  public var preferredSize: CGSize {
    let art = artSize
    let footer = footerHeight
    return CGSize(width: art.width, height: art.height + footer)
  }

  var footerHeight: CGFloat {
    // Title + optional subtitle + vertical padding — matches the SwiftUI footer.
    subtitle == nil ? 52 : 70
  }

  public static func from(card: MediaCard, surface: MediaCardContextSurface) -> MediaCardContextPreviewSpec {
    let aspect: CardAspect
    switch surface {
    case .banner, .episodeRail:
      aspect = .landscape
    case .shelf:
      aspect = card.isLandscape ? .landscape : .poster
    }

    let raw: String
    switch surface {
    case .shelf:
      if aspect == .landscape,
         let landscape = card.landscapeImageURL, !landscape.isEmpty {
        raw = landscape
      } else if !card.posterURL.isEmpty {
        // Portrait peek always uses the poster — never a wide still cropped into 2:3.
        raw = card.posterURL
      } else {
        raw = card.coverURL
      }
    case .episodeRail:
      if let landscape = card.landscapeImageURL, !landscape.isEmpty {
        raw = landscape
      } else {
        raw = card.coverURL
      }
    case .banner:
      if let backdrop = card.backdropURL, !backdrop.isEmpty {
        raw = backdrop
      } else if let landscape = card.landscapeImageURL, !landscape.isEmpty {
        raw = landscape
      } else {
        raw = card.coverURL
      }
    }

    return MediaCardContextPreviewSpec(
      url: URL(string: raw),
      aspect: aspect,
      title: card.title,
      subtitle: card.sneakPeekSubtitle(surface: surface)
    )
  }
}

public extension MediaCard {
  /// Secondary line for the context-menu sneak peek — more than the cell caption.
  func sneakPeekSubtitle(surface: MediaCardContextSurface,
                         language: MediaLanguage = .current) -> String? {
    switch surface {
    case .episodeRail:
      return episodePeekSubtitle() ?? durationLabel
    case .banner:
      return catalogPeekSubtitle(language: language) ?? durationLabel
    case .shelf:
      if isLandscape {
        return landscapePeekSubtitle(language: language)
      }
      return catalogPeekSubtitle(language: language)
    }
  }

  /// Poster / search / library style: `year · genre`, else duration, else one of them.
  private func catalogPeekSubtitle(language: MediaLanguage) -> String? {
    let year = yearLabel
    let genre = usefulGenre(language: language) ?? primaryGenre(language: language)
    switch (year, genre) {
    case let (year?, genre?):
      return "\(year) · \(genre)"
    case let (nil, genre?):
      if let durationLabel, !isSeries { return durationLabel }
      return genre
    case let (year?, nil):
      if let durationLabel, !isSeries { return "\(year) · \(durationLabel)" }
      return year
    case (nil, nil):
      return durationLabel
    }
  }

  /// Continue Watching / wide still: episode meta, offered name, duration, else genre.
  private func landscapePeekSubtitle(language: MediaLanguage) -> String? {
    if let overlay = overlayLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
       !overlay.isEmpty {
      if let durationLabel, !overlay.contains(durationLabel) {
        return "\(overlay) · \(durationLabel)"
      }
      return overlay
    }
    if let offered = offeredName?.trimmingCharacters(in: .whitespacesAndNewlines),
       !offered.isEmpty,
       offered.caseInsensitiveCompare(title) != .orderedSame {
      if let durationLabel { return "\(offered) · \(durationLabel)" }
      return offered
    }
    if let episode = episodePeekSubtitle() { return episode }
    if let genre = usefulGenre(language: language) ?? primaryGenre(language: language) {
      return genre
    }
    return durationLabel
  }

  private func episodePeekSubtitle() -> String? {
    guard let video else { return nil }
    let label = EpisodeText(season: season, number: video, seasonCount: seasonCount)
      .listItem()
    if let durationLabel { return "\(label) · \(durationLabel)" }
    return label
  }
}

/// Sneak peek card: native-aspect art (fit, not crop) + title / secondary footer.
public struct MediaCardContextPreview: View {
  private let spec: MediaCardContextPreviewSpec
  @State private var image: Image?
  @State private var loadFailed = false

  public init(spec: MediaCardContextPreviewSpec) {
    self.spec = spec
  }

  public var body: some View {
    let art = spec.artSize
    VStack(spacing: 0) {
      ZStack {
        Rectangle()
          .fill(Color.primary.opacity(0.08))
        if let image {
          image
            .resizable()
            .scaledToFit()
            .frame(width: art.width, height: art.height)
        } else if !loadFailed {
          ProgressView()
            .controlSize(.regular)
        }
      }
      .frame(width: art.width, height: art.height)

      VStack(alignment: .leading, spacing: 2) {
        Text(spec.title)
          .font(.headline)
          .foregroundStyle(.primary)
          .lineLimit(2)
          .multilineTextAlignment(.leading)
        if let subtitle = spec.subtitle {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .frame(width: art.width, alignment: .leading)
      .frame(minHeight: spec.footerHeight)
      // Peek footer rides the system surface (Apple TV: white / dark plate under art).
      .background(footerBackground)
    }
    .frame(width: art.width)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
#if os(iOS) || os(macOS)
    .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
#endif
    .task(id: spec.url?.absoluteString) {
      await loadArt()
    }
    .onAppear {
      Artwork.prefetch([spec.url])
    }
  }

  @MainActor
  private func loadArt() async {
    image = nil
    loadFailed = false
    guard let url = spec.url else {
      loadFailed = true
      return
    }
    let size = spec.artSize
    if let cached = Artwork.cachedImage(for: url, size: size, mode: .fit) {
      image = Image(platformImage: cached)
      return
    }
    do {
      let loaded = try await Artwork.image(for: url, size: size, mode: .fit)
      image = Image(platformImage: loaded)
    } catch is CancellationError {
      return
    } catch {
      loadFailed = true
    }
  }

  private var footerBackground: Color {
#if os(macOS)
    Color(nsColor: .windowBackgroundColor)
#elseif os(tvOS)
    Color.KinoPub.background
#else
    Color(uiColor: .systemBackground)
#endif
  }
}

#if DEBUG
#Preview("Sneak peek portrait") {
  MediaCardContextPreview(
    spec: .from(
      card: MediaCard(
        id: 1,
        posterURL: "https://m.staticpop.net/poster/item/big/10581.jpg",
        title: "Декстер: Воскрешение",
        isSeries: true,
        year: 2025,
        genres: [Genre(id: "drama", domain: .video,
                       name: LocalizedName(en: "Drama", ru: "Драма"))]
      ),
      surface: .shelf
    )
  )
  .padding(40)
  .background(Color.gray.opacity(0.35))
}

#Preview("Sneak peek landscape") {
  MediaCardContextPreview(
    spec: .from(
      card: MediaCard(
        id: 2,
        posterURL: "https://m.staticpop.net/poster/item/big/10581.jpg",
        title: "Декстер: Воскрешение",
        landscapeImageURL: "https://m.staticpop.net/poster/item/wide/10581.jpg",
        overlayLabel: "S2, E1",
        video: 1,
        season: 2,
        isSeries: true,
        durationSeconds: 58 * 60,
        genres: [Genre(id: "drama", domain: .video,
                       name: LocalizedName(en: "Drama", ru: "Драма"))]
      ),
      surface: .shelf
    )
  )
  .padding(40)
  .background(Color.gray.opacity(0.35))
}
#endif
