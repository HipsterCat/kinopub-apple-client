//
//  MediaCardContextPreview.swift
//  PiraticUI
//
//  Apple TV–style sneak peek for poster / video long-press: native art aspect
//  (poster 2:3, wide 16:9), plate hugs the loaded bitmap (no letterbox gutters),
//  and a metadata footer (title + year · genre / reason / duration).
//  SwiftUI surfaces use `MediaCardContextPreview`; tvOS UIKit menus use
//  `TVMediaCardContextPreviewController`.
//

import SwiftUI
import PiraticMedia
import PiraticMetadata
#if os(macOS)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Artwork + metadata for a card's long-press sneak peek.
public struct MediaCardContextPreviewSpec: Equatable, Sendable {
  public let url: URL?
  public let aspect: CardAspect
  public let title: String
  /// Secondary line under the title — `2026 · Drama`, `В закладках`, `1h 55m`, …
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

  /// Max art box while loading / before we know the bitmap's ratio.
  public var artSize: CGSize {
    switch aspect {
    case .poster: return CGSize(width: 280, height: 420)
    case .landscape: return CGSize(width: 340, height: 191)
    case .square: return CGSize(width: 280, height: 280)
    }
  }

  /// Decode at 2× the display box so KP / worker masters stay sharp in the peek.
  public var decodeSize: CGSize {
    CGSize(width: artSize.width * 2, height: artSize.height * 2)
  }

  /// Full peek including the metadata footer (preferredContentSize for UIKit).
  public var preferredSize: CGSize {
    preferredSize(art: artSize)
  }

  public func preferredSize(art: CGSize) -> CGSize {
    CGSize(width: art.width, height: art.height + footerHeight)
  }

  var footerHeight: CGFloat {
    // Title + optional subtitle + vertical padding — matches the SwiftUI footer.
    subtitle == nil ? 52 : 70
  }

  /// Shrink the max box so it matches the bitmap's aspect — no letterbox gutters.
  public func artDisplaySize(forImageSize imageSize: CGSize) -> CGSize {
    let maxBox = artSize
    guard imageSize.width > 1, imageSize.height > 1 else { return maxBox }
    let scale = min(maxBox.width / imageSize.width, maxBox.height / imageSize.height)
    let width = max(1, (imageSize.width * scale).rounded(.toNearestOrAwayFromZero))
    let height = max(1, (imageSize.height * scale).rounded(.toNearestOrAwayFromZero))
    return CGSize(width: width, height: height)
  }

  public static func from(card: MediaCard,
                          surface: MediaCardContextSurface,
                          images: TitleImageRoute = TitleImageRoute(baseURL: nil),
                          scale: CGFloat = 2) -> MediaCardContextPreviewSpec {
    let aspect: CardAspect
    switch surface {
    case .banner, .episodeRail:
      aspect = .landscape
    case .shelf:
      aspect = card.isLandscape ? .landscape : .poster
    }

    let url = card.sneakPeekArtworkURL(surface: surface, images: images, scale: scale)
    return MediaCardContextPreviewSpec(
      url: url,
      aspect: aspect,
      title: card.title,
      subtitle: card.sneakPeekSubtitle(surface: surface)
    )
  }
}

public extension MediaCard {
  /// Artwork URL for the long-press peek — same language ladder as the cell for
  /// posters (`coverURL`), and the same still as macOS hover for series/episodes.
  func sneakPeekArtworkURL(surface: MediaCardContextSurface,
                           images: TitleImageRoute = TitleImageRoute(baseURL: nil),
                           scale: CGFloat = 2) -> URL? {
    let points: CGFloat
    switch surface {
    case .shelf where !isLandscape:
      points = 280
    case .banner:
      points = 340
    default:
      points = 340
    }

    switch surface {
    case .shelf where !isLandscape:
      // Same vertical cover the cell paints — Russian KP when Covers = Russian.
      let raw = !coverURL.isEmpty ? coverURL : posterURL
      return raw.isEmpty ? nil : URL(string: raw)

    case .shelf, .episodeRail:
      if let pointer = pointerArtwork(images: images, points: points, scale: scale) {
        return pointer.primary
      }
      if let landscape = landscapeArtworkURL, !landscape.isEmpty {
        return URL(string: landscape)
      }
      if surface == .episodeRail, let cover = coverURL.isEmpty ? nil : coverURL {
        return URL(string: cover)
      }
      return nil

    case .banner:
      if let backdrop = backdropURL, !backdrop.isEmpty {
        return URL(string: backdrop)
      }
      if let landscape = landscapeArtworkURL, !landscape.isEmpty {
        return URL(string: landscape)
      }
      return coverURL.isEmpty ? nil : URL(string: coverURL)
    }
  }

  /// Secondary line for the context-menu sneak peek — more than the cell caption.
  func sneakPeekSubtitle(surface: MediaCardContextSurface,
                         language: MediaLanguage = .current) -> String? {
    switch surface {
    case .episodeRail:
      // True episode tiles (season rail): keep the episode line.
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

  /// Continue Watching / wide still: reason («В закладках», «Недосмотрено»), version
  /// name, or genre — never «Ep. 1» / «1 серия» on a title-level landscape card.
  private func landscapePeekSubtitle(language: MediaLanguage) -> String? {
    if let hint = continuePeekHint?.trimmingCharacters(in: .whitespacesAndNewlines),
       !hint.isEmpty {
      return hint
    }
    if let offered = offeredName?.trimmingCharacters(in: .whitespacesAndNewlines),
       !offered.isEmpty,
       offered.caseInsensitiveCompare(title) != .orderedSame {
      return offered
    }
    if let catalog = catalogPeekSubtitle(language: language) {
      return catalog
    }
    return durationLabel
  }

  /// Episode reference for a real episode tile only — never for films (`video` is often 1).
  private func episodePeekSubtitle() -> String? {
    guard isSeries, let video else { return nil }
    let label = EpisodeText(season: season, number: video, seasonCount: seasonCount)
      .listItem()
    if let durationLabel { return "\(label) · \(durationLabel)" }
    return label
  }
}

/// Sneak peek card: plate hugs the loaded art's aspect + title / secondary footer.
public struct MediaCardContextPreview: View {
  private let spec: MediaCardContextPreviewSpec
  @State private var image: Image?
  @State private var artFrame: CGSize
  @State private var loadFailed = false

  public init(spec: MediaCardContextPreviewSpec) {
    self.spec = spec
    _artFrame = State(initialValue: spec.artSize)
  }

  public var body: some View {
    VStack(spacing: 0) {
      ZStack {
        if let image {
          image
            .resizable()
            .scaledToFill()
            .frame(width: artFrame.width, height: artFrame.height)
            .clipped()
        } else if !loadFailed {
          ProgressView()
            .controlSize(.regular)
            .frame(width: artFrame.width, height: artFrame.height)
            .background(Color.primary.opacity(0.08))
        } else {
          Color.primary.opacity(0.08)
            .frame(width: artFrame.width, height: artFrame.height)
        }
      }
      .frame(width: artFrame.width, height: artFrame.height)

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
      .frame(width: artFrame.width, alignment: .leading)
      .frame(minHeight: spec.footerHeight)
      // Peek footer rides the system surface (Apple TV: white / dark plate under art).
      .background(footerBackground)
    }
    .frame(width: artFrame.width)
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
    artFrame = spec.artSize
    guard let url = spec.url else {
      loadFailed = true
      return
    }
    let decodeBox = spec.decodeSize
    // Do not name Nuke's `PlatformImage` here — only ArtworkPipeline imports Nuke.
    if let cached = Artwork.cachedImage(for: url, size: decodeBox, mode: .fit) {
      artFrame = spec.artDisplaySize(forImageSize: cached.size)
      image = Image(platformImage: cached)
      return
    }
    do {
      let loaded = try await Artwork.image(for: url, size: decodeBox, mode: .fit)
      artFrame = spec.artDisplaySize(forImageSize: loaded.size)
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
    // tvOS has no systemBackground; `Color.Piratic.background` is clear (page fill).
    Color.Piratic.glassSubstitute
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
        id: 9944,
        posterURL: "https://m.staticpop.net/poster/item/big/9944.jpg",
        title: "Иностранная интрига",
        year: 2024,
        genres: [Genre(id: "thriller", domain: .video,
                       name: LocalizedName(en: "Thriller", ru: "Триллер"))]
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
        // wide/15042.jpg 404s; MediaCardView episode fixture uses 10524.
        id: 10524,
        posterURL: "https://m.staticpop.net/poster/item/big/10524.jpg",
        title: "Название эпизода",
        landscapeImageURL: "https://m.staticpop.net/poster/item/wide/10524.jpg",
        overlayLabel: "S2, E5",
        video: 5,
        season: 2,
        isSeries: true,
        durationSeconds: 42 * 60,
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
