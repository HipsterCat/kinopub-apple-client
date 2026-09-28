import Foundation
#if canImport(AVFoundation)
import AVFoundation
import CoreMedia
#endif

/// **What the system player is told about what is playing**, in Apple's own vocabulary —
/// projected from a `MediaContext`, knowing nothing about where any of it came from.
///
/// The field set is Apple's, from AVKit's "Customizing the tvOS Playback Experience":
///
/// | Field | Identifier | Where it shows |
/// | --- | --- | --- |
/// | Title | `commonIdentifierTitle` | title view above the transport bar |
/// | Subtitle | `iTunesMetadataTrackSubTitle` | title view |
/// | Artwork | `commonIdentifierArtwork` | Info tab |
/// | Description | `commonIdentifierDescription` | Info tab |
/// | Genre | `quickTimeMetadataGenre` | Info tab |
/// | Content rating | `iTunesMetadataContentRating` | Info tab |
///
/// `externalMetadata` also feeds iOS Now Playing, Control Center, the lock screen and
/// AirPlay. **Scores are not on that list** — `iTunesMetadataContentRating` is the age
/// rating, and no identifier carries an IMDb or Kinopoisk number; those belong to our own
/// Info tab (`customInfoViewControllers`, ROADMAP stage 7).
public struct PlayerInfo: Hashable, Sendable {
  public var title: String?
  public var subtitle: String?
  public var description: String?
  /// **One** genre, the primary. Apple's panel gives it one short line, and a comma list
  /// there is how "Comedy, Action, Fantastic, Adventure" ended up truncated.
  public var genre: String?
  /// "16+", "PG-13".
  public var contentRating: String?
  /// ISO 8601 at the precision we have. Not in Apple's documented tvOS set above —
  /// `commonIdentifierCreationDate` is sent because it costs nothing and other
  /// `externalMetadata` readers (AirPlay receivers) may show it. Unverified on device.
  public var creationDate: String?
  /// Best first. The caller downloads the first that loads.
  public var artworkCandidates: [URL]

  /// The words the projection needs in the viewer's language. The app passes its own
  /// localized strings; the English default keeps the package usable without them.
  public struct Labels: Sendable {
    public var languageCode: String?
    public var episode: @Sendable (_ season: Int?, _ episode: Int) -> String
    public var extra: @Sendable (ExtraKind) -> String?

    public init(languageCode: String?,
                episode: @escaping @Sendable (_ season: Int?, _ episode: Int) -> String,
                extra: @escaping @Sendable (ExtraKind) -> String?) {
      self.languageCode = languageCode
      self.episode = episode
      self.extra = extra
    }

    public static let english = Labels(
      languageCode: "en",
      episode: { season, episode in
        season.map { "Season \($0), Episode \(episode)" } ?? "Episode \(episode)"
      },
      extra: { kind in kind == .trailer ? "Trailer" : nil })
  }

  public init(title: String? = nil, subtitle: String? = nil, description: String? = nil,
              genre: String? = nil, contentRating: String? = nil, creationDate: String? = nil,
              artworkCandidates: [URL] = []) {
    self.title = title.nonBlank
    self.subtitle = subtitle.nonBlank
    self.description = description.nonBlank
    self.genre = genre.nonBlank
    self.contentRating = contentRating.nonBlank
    self.creationDate = creationDate.nonBlank
    self.artworkCandidates = artworkCandidates
  }

  public init(context: MediaContext, labels: Labels = .english) {
    let title = context.title
    self.init(title: title,
              subtitle: Self.subtitle(context: context, title: title, labels: labels),
              description: context.synopsis,
              genre: context.primaryGenre?.name.value(languageCode: labels.languageCode),
              contentRating: context.contentRating?.value,
              creationDate: context.release?.iso8601,
              artworkCandidates: context.artworkCandidates)
  }

  /// Episode: "Season 2, Episode 5: Name", the name dropped when it only repeats the
  /// title line. Trailer: what kind of extra it is. A film's edition: "48 fps".
  private static func subtitle(context: MediaContext, title: String?, labels: Labels) -> String? {
    let item = context.item
    switch item.kind {
    case .episode:
      let name = item.title.nonBlank.flatMap { $0 == title ? nil : $0 }
      guard let number = item.episodeNumber else { return name }
      let line = labels.episode(item.seasonNumber ?? context.season?.seasonNumber, number)
      return name.map { "\(line): \($0)" } ?? line
    case .extra:
      return item.extraKind.flatMap(labels.extra)
    case .movie:
      return item.edition
    case .show, .season:
      return nil
    }
  }
}

#if canImport(AVFoundation)
extension PlayerInfo {

  /// Everything but the artwork, which arrives later as bytes (`artworkItem`).
  public func metadataItems() -> [AVMetadataItem] {
    let fields: [(AVMetadataIdentifier, String?)] = [
      (.commonIdentifierTitle, title),
      (.iTunesMetadataTrackSubTitle, subtitle),
      (.commonIdentifierDescription, description),
      (.quickTimeMetadataGenre, genre),
      (.iTunesMetadataContentRating, contentRating),
      (.commonIdentifierCreationDate, creationDate),
    ]
    return fields.compactMap { identifier, value in
      value.nonBlank.map { Self.item(identifier, $0) }
    }
  }

  /// The panel wants the image itself, not a URL.
  public static func artworkItem(_ data: Data) -> AVMetadataItem {
    let artwork = AVMutableMetadataItem()
    artwork.identifier = .commonIdentifierArtwork
    artwork.value = data as NSData
    let isPNG = data.starts(with: [0x89, 0x50, 0x4E, 0x47])
    artwork.dataType = (isPNG ? kCMMetadataBaseDataType_PNG : kCMMetadataBaseDataType_JPEG) as String
    artwork.extendedLanguageTag = "und"
    return artwork
  }

  private static func item(_ identifier: AVMetadataIdentifier, _ value: String) -> AVMetadataItem {
    let item = AVMutableMetadataItem()
    item.identifier = identifier
    item.value = value as NSString
    // "und", as Apple's sample does: a tagged language makes AVFoundation filter the item
    // against the viewer's own, and the panel then shows nothing.
    item.extendedLanguageTag = "und"
    return item
  }
}
#endif
