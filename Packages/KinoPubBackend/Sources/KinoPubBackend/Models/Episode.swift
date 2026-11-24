//
//  Episode.swift
//
//
//  Created by Kirill Kunst on 21.07.2023.
//

import Foundation

/// A value: whoever holds one holds its own copy. A page that changes a mark writes it into
/// its own `MediaItem` (`MediaItem.updateEpisode`) and republishes that.
public struct Episode: Codable, Hashable, Identifiable, Sendable {
  
  public let id: Int
  public let title: String
  public let thumbnail: String
  public let duration: Int
  public let tracks: Int
  public let number: Int
  public let ac3: Int
  public let audios: [EpisodeAudio]
  /// Changed after `/v1/watching/toggle` so the episode rail can flip its state
  /// without refetching the whole title.
  public var watched: Int
  /// Overwritten from the local watch store when the player wrote a newer position than
  /// the payload knew about, so the rail and the hero redraw without refetching the title.
  public var watching: EpisodeWatching
  /// Both of these are empty when the details call asked for `nolinks=1`, and come from
  /// `/v1/items/media-links` the first time this episode is actually played:
  /// `MediaLinksResolver` gives back a copy with them and remembers the answer.
  public var subtitles: [Subtitle]
  public var files: [FileInfo]
  public var seasonNumber: Int?
  public var mediaId: Int?
  /// The series' own name. `Episode` arrives from the API with none of its parent's
  /// context, the same way `seasonNumber`/`mediaId` do — callers that already hold the
  /// series fill it in once they hand the episode to the player, so the transport bar's
  /// title line can read "Breaking Bad" instead of just the episode's own title.
  public var seriesTitle: String?

  public var fixedTitle: String {
    if title.isEmpty {
      return "Episode \(number)"
    }
    return title
  }
  
  public init(id: Int, title: String, thumbnail: String, duration: Int, tracks: Int, number: Int, ac3: Int, audios: [EpisodeAudio], watched: Int, watching: EpisodeWatching, subtitles: [Subtitle], files: [FileInfo]) {
    self.id = id
    self.title = title
    self.thumbnail = thumbnail
    self.duration = duration
    self.tracks = tracks
    self.number = number
    self.ac3 = ac3
    self.audios = audios
    self.watched = watched
    self.watching = watching
    self.subtitles = subtitles
    self.files = files
  }
  
  /// By id, which is enough for a hash and keeps hashing a series cheap. Equality is the
  /// whole value: SwiftUI skips a view whose episode "did not change", and one compared
  /// by id would keep showing the old watched mark.
  public func hash(into hasher: inout Hasher) {
    hasher.combine(id)
  }
}

public extension Episode {
  /// The episode as the player and `/v1/watching*` need it: the API sends it without its
  /// season, item or series name.
  func stamped(season: Int, mediaId: Int?, seriesTitle: String?) -> Episode {
    var copy = self
    copy.seasonNumber = season
    copy.mediaId = mediaId
    copy.seriesTitle = seriesTitle
    return copy
  }

  /// Resume progress for this episode (single source of truth for "watched / in progress").
  var watchProgress: WatchProgress {
    WatchProgress(position: Double(watching.time), duration: Double(duration))
  }
  /// "Finished" (watched to the credits) — so Continue offers the next episode, not this one's tail.
  var isWatchedToEnd: Bool { watchProgress.isFinished }
  /// Single "watched" verdict: the explicit server flag OR watched-to-the-credits.
  var isWatched: Bool { watched > 0 || isWatchedToEnd }

  /// Something to play on kino.pub: a files ladder (even `nolinks`, URLs still empty) or a
  /// runtime. Empty ladder + no duration is a placeholder for an episode that is not out
  /// yet — the season rail shows «Через N дней», and Continue Watching / Play must not
  /// advance to it. Same rule as `EpisodePlayability.onService` (duration ≥ 60 s).
  var isOnService: Bool {
    !files.isEmpty || duration >= 60
  }
}

extension Episode: PlayableItem {
  public var trailer: Trailer? { nil }
  /// 🔴 **`id` here is the item's, never the episode's.** `/v1/watching`,
  /// `/v1/watching/marktime` and `/v1/watching/toggle` all key on the item
  /// (`id=87940&season=1&video=2`), while `Episode.id` is a *media* id — the thing
  /// `MediaLinksRequest(mid:)` takes. Passing the media id answered **404** on
  /// `/v1/watching?id=928900&season=1&video=2` (seen live 2026-08-17), and a media id
  /// that happens to collide with a real item id would have written progress onto
  /// somebody else's title instead.
  ///
  /// Unstamped episodes therefore report `0`, and `WatchingMetadata.isResolved` is what
  /// the player checks before it says anything to the server.
  public var metadata: WatchingMetadata {
    WatchingMetadata(id: mediaId ?? 0, video: number, season: seasonNumber)
  }
  // `subtitles` already declared on Episode

  public var audioTracks: [AudioTrackInfo] {
    AudioTracks.catalog(audios)
  }
}
