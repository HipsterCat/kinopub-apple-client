//
//  DownloadMeta.swift
//  Piratic
//
//  Created by Kirill Kunst on 10.11.2023.
//

import Foundation
import KinoPubBackend
import PiraticKit
import PiraticUI
import PiraticMetadata

public struct DownloadMeta: PlayableItem, Codable, Equatable, Sendable {
  public var id: Int
  public var files: [FileInfo]
  public var trailer: Trailer? { nil }
  public var originalTitle: String
  public var localizedTitle: String
  public var imageUrl: String
  public var metadata: WatchingMetadata
  /// Sidecar subtitles captured when the download was enqueued (and rewritten to
  /// local `file://` URLs once the SRTs are saved). Older entries decode as `[]`.
  public var subtitles: [Subtitle]
  /// The quality the user chose to download (e.g. "1080p"). Optional so older saved entries decode.
  public var quality: String?
  /// Episode marker for series (e.g. "S4E4"); nil for movies.
  public var episode: String?
  /// Intro / recap / credits / preview markers fetched while online at download time.
  public var skipSegments: SkipSegments?
  /// True once SkipDB / TheIntroDB were asked for this download (even if nothing came back).
  public var skipSegmentsResolved: Bool?

  public init(id: Int,
              files: [FileInfo],
              originalTitle: String,
              localizedTitle: String,
              imageUrl: String,
              metadata: WatchingMetadata,
              subtitles: [Subtitle] = [],
              quality: String? = nil,
              episode: String? = nil,
              skipSegments: SkipSegments? = nil,
              skipSegmentsResolved: Bool? = nil) {
    self.id = id
    self.files = files
    self.originalTitle = originalTitle
    self.localizedTitle = localizedTitle
    self.imageUrl = imageUrl
    self.metadata = metadata
    self.subtitles = subtitles
    self.quality = quality
    self.episode = episode
    self.skipSegments = skipSegments
    self.skipSegmentsResolved = skipSegmentsResolved
  }

  private enum CodingKeys: String, CodingKey {
    case id, files, originalTitle, localizedTitle, imageUrl, metadata
    case subtitles, quality, episode, skipSegments, skipSegmentsResolved
  }

  /// Older on-disk entries predate stored subtitles / skip timings — missing keys decode empty.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(Int.self, forKey: .id)
    files = try c.decode([FileInfo].self, forKey: .files)
    originalTitle = try c.decode(String.self, forKey: .originalTitle)
    localizedTitle = try c.decode(String.self, forKey: .localizedTitle)
    imageUrl = try c.decode(String.self, forKey: .imageUrl)
    metadata = try c.decode(WatchingMetadata.self, forKey: .metadata)
    subtitles = (try? c.decode([Subtitle].self, forKey: .subtitles)) ?? []
    quality = try? c.decode(String.self, forKey: .quality)
    episode = try? c.decode(String.self, forKey: .episode)
    skipSegments = try? c.decode(SkipSegments.self, forKey: .skipSegments)
    skipSegmentsResolved = try? c.decode(Bool.self, forKey: .skipSegmentsResolved)
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(files, forKey: .files)
    try c.encode(originalTitle, forKey: .originalTitle)
    try c.encode(localizedTitle, forKey: .localizedTitle)
    try c.encode(imageUrl, forKey: .imageUrl)
    try c.encode(metadata, forKey: .metadata)
    try c.encode(subtitles, forKey: .subtitles)
    try c.encodeIfPresent(quality, forKey: .quality)
    try c.encodeIfPresent(episode, forKey: .episode)
    try c.encodeIfPresent(skipSegments, forKey: .skipSegments)
    try c.encodeIfPresent(skipSegmentsResolved, forKey: .skipSegmentsResolved)
  }
}

extension DownloadMeta: DownloadFileNaming {
  /// Human-readable base filename, e.g. "Бесстыжие S10E1 (480p)".
  public var downloadFileBaseName: String? {
    var name = localizedTitle
    if let episode, !episode.isEmpty { name += " \(episode)" }
    if let quality, !quality.isEmpty { name += " (\(quality))" }
    let cleaned = name
      .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? nil : cleaned
  }
}

extension DownloadMeta {
  /// Human-readable label for download notifications, e.g. "S1E3 · Title".
  var notificationTitle: String {
    [episode, localizedTitle]
      .compactMap { $0 }
      .filter { !$0.isEmpty }
      .joined(separator: " · ")
  }

  /// Whether Downloads should say skip timings are missing (asked, nothing stored).
  var showsMissingSkipTimings: Bool {
    skipSegmentsResolved == true && (skipSegments?.isEmpty ?? true)
  }

  static func make(from item: DownloadableMediaItem,
                   quality: String? = nil,
                   subtitles: [Subtitle]? = nil,
                   skipSegments: SkipSegments? = nil,
                   skipSegmentsResolved: Bool? = nil) -> DownloadMeta {
    let episodeSubs: [Subtitle] = {
      if let subtitles { return subtitles }
      if let season = item.watchingMetadata.season,
         let video = item.watchingMetadata.video,
         let episode = item.mediaItem.seasons?
          .first(where: { $0.number == season })?
          .episodes.first(where: { $0.number == video }) {
        return episode.subtitles
      }
      return item.mediaItem.subtitles
    }()
    return DownloadMeta(
      id: item.mediaItem.id,
      files: item.files,
      originalTitle: item.mediaItem.originalTitle,
      localizedTitle: item.mediaItem.localizedTitle,
      imageUrl: CoverArtwork.resolve(url: item.mediaItem.posters.small,
                                      kinopoiskID: item.mediaItem.kinopoisk),
      metadata: item.watchingMetadata,
      subtitles: episodeSubs,
      quality: quality,
      episode: item.mediaItem.isSeries ? item.name : nil,
      skipSegments: skipSegments,
      skipSegmentsResolved: skipSegmentsResolved
    )
  }
}
