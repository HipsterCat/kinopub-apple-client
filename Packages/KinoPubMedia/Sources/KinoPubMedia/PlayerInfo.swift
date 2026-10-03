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
  /// ISO 8601 at the precision we have — "2025" or "2025-03-14". The model keeps that
  /// precision; only `metadataItems()` turns it into the date AVKit wants.
  public var creationDate: String?
  /// Best first. The caller downloads the first that loads.
  public var artworkCandidates: [URL]

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

  /// - Parameter language: the viewer's — for the episode line and the genre's name.
  public init(context: MediaContext, language: MediaLanguage = .current) {
    let title = context.title
    self.init(title: title,
              subtitle: Self.subtitle(context: context, title: title, language: language),
              description: context.synopsis,
              genre: context.primaryGenre?.name.value(languageCode: language.rawValue),
              contentRating: context.contentRating?.value,
              creationDate: context.release?.iso8601,
              artworkCandidates: context.artworkCandidates)
  }

  /// Episode: `EpisodeText` at the player's length — «S2, E5: Name», «Season 2, Episode 5»,
  /// «Episode 1: Name» when the show has only its first season — the name dropped when it
  /// only repeats the title line. A film's edition: "48 fps". A trailer: nothing — the Info tab's heading
  /// is the subtitle when there is one, and «Trailer» there says nothing the viewer did not
  /// choose; with none, the heading is the film's or show's own name (user's call,
  /// 2026-10-01).
  private static func subtitle(context: MediaContext, title: String?,
                               language: MediaLanguage) -> String? {
    let item = context.item
    switch item.kind {
    case .episode:
      let name = item.title.nonBlank.flatMap { $0 == title ? nil : $0 }
      guard let number = item.episodeNumber else { return name }
      return EpisodeText(season: item.seasonNumber ?? context.season?.seasonNumber,
                         number: number, name: name,
                         seasonCount: context.parent?.seasonCount)
        .text(for: .playerSubtitle, language: language)
    case .movie:
      return item.edition
    case .show, .season, .extra:
      return nil
    }
  }
}

#if canImport(AVFoundation)
extension PlayerInfo {

  /// Everything but the artwork, which arrives later as bytes (`artworkItem`).
  ///
  /// **The year slot — an adapter for what AVKit does with `commonIdentifierCreationDate`.**
  /// Observed in the tvOS 27.2 simulator's title view (paused player, `AVPlayerViewController`):
  /// - a *string* "2025" renders as **2026** and "2025-01-01" as **12169** — the number seen
  ///   on device («12175 • …») — so a date-shaped string is not read as a date;
  /// - a string with a time ("2025-01-01T00:00:00Z"), an `NSDate`, and the same under
  ///   `quickTimeMetadataCreationDate` all render **2025**; leaving it out drops the year.
  ///
  /// So it is sent as an `NSDate`. The panel formats it in the *viewer's* time zone: midnight
  /// UTC on 1 January showed **2024** with `TZ=Pacific/Honolulu`, noon UTC showed 2025 there
  /// and at UTC+14. Hence noon. A year-only release becomes 1 January of that year, *here
  /// only* — the model keeps year precision and nothing else may read this date as a day.
  public func metadataItems() -> [AVMetadataItem] {
    let fields: [(AVMetadataIdentifier, (NSCopying & NSObjectProtocol)?)] = [
      (.commonIdentifierTitle, title.nonBlank as NSString?),
      (.iTunesMetadataTrackSubTitle, subtitle.nonBlank as NSString?),
      (.commonIdentifierDescription, description.nonBlank as NSString?),
      (.quickTimeMetadataGenre, genre.nonBlank as NSString?),
      (.iTunesMetadataContentRating, contentRating.nonBlank as NSString?),
      (.commonIdentifierCreationDate, creationDate.flatMap(Self.panelDate) as NSDate?),
    ]
    return fields.compactMap { identifier, value in
      value.map { Self.item(identifier, $0) }
    }
  }

  /// "2025" or "2025-03-14" → that day at 12:00 UTC (see `metadataItems()`).
  static func panelDate(_ iso: String) -> Date? {
    let parts = iso.split(separator: "-", omittingEmptySubsequences: false).map { Int($0) }
    guard (1...3).contains(parts.count), let year = parts[0], parts.allSatisfy({ $0 != nil }) else {
      return nil
    }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(
      year: year, month: parts.count > 1 ? parts[1] : 1, day: parts.count > 2 ? parts[2] : 1,
      hour: 12))
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

  private static func item(_ identifier: AVMetadataIdentifier,
                           _ value: NSCopying & NSObjectProtocol) -> AVMetadataItem {
    let item = AVMutableMetadataItem()
    item.identifier = identifier
    item.value = value
    // "und", as Apple's sample does: a tagged language makes AVFoundation filter the item
    // against the viewer's own, and the panel then shows nothing.
    item.extendedLanguageTag = "und"
    return item
  }
}
#endif
