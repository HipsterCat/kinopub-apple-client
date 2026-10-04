//
//  MediaActionCatalog.swift
//  KinoPubUI
//
//  Label / chrome / order for media primary-action rows.
//  Copy rules: `docs/product/media-actions.md`.
//

import Foundation
import KinoPubBackend

// MARK: - Identity

public enum MediaActionID: String, Hashable, Sendable, CaseIterable {
  case play
  /// The second version of a film that has several: its own play pill beside Play.
  case playAlternate
  case markWatched
  case trailer
  case bookmark
  case follow
  case download
  case shuffle
  case more
}

public enum MediaActionChrome: Hashable, Sendable {
  case playPill
  case pill
  case circle
}

/// Download control phase. `downloaded` means the circle is absent — Delete lives in More.
public enum MediaActionDownloadPhase: Equatable, Sendable {
  case idle
  case downloading(progress: Double)
  case downloaded
}

public struct MediaActionAppearance: Equatable, Identifiable, Sendable {
  public var id: MediaActionID
  public var chrome: MediaActionChrome
  public var systemImage: String
  public var title: String?
  public var progress: Double?
  /// Circle download: ring progress with a pause glyph in the middle.
  public var circularProgress: Double?
  public var accessibilityLabel: String
  public var isLoading: Bool

  public init(
    id: MediaActionID,
    chrome: MediaActionChrome,
    systemImage: String,
    title: String? = nil,
    progress: Double? = nil,
    circularProgress: Double? = nil,
    accessibilityLabel: String,
    isLoading: Bool = false
  ) {
    self.id = id
    self.chrome = chrome
    self.systemImage = systemImage
    self.title = title
    self.progress = progress
    self.circularProgress = circularProgress
    self.accessibilityLabel = accessibilityLabel
    self.isLoading = isLoading
  }
}

/// One version of a film, as a play button: the name kino.pub gave it (nil when it gave
/// none) and how far into *this* version the viewer is.
public struct MediaActionVersion: Equatable, Sendable {
  public var name: String?
  public var playback: PlaybackButtonContent

  public init(name: String?, playback: PlaybackButtonContent) {
    self.name = name
    self.playback = playback
  }
}

public struct MediaActionContext: Equatable, Sendable {
  public var playback: PlaybackButtonContent
  public var kind: MediaPresentationKind
  public var isSeries: Bool
  public var isBookmarked: Bool
  public var isFollowing: Bool
  public var showsMarkWatched: Bool
  public var showsTrailer: Bool
  public var showsFollow: Bool
  /// `nil` = downloads off for this surface/platform. Otherwise the live phase.
  public var download: MediaActionDownloadPhase?
  public var showsShuffle: Bool
  public var showsMore: Bool
  /// Series ongoing, everything watched, and the next episode of the season kino.pub is
  /// on has a known date → labelled Follow leads.
  public var promoteFollow: Bool
  /// A film's versions in number order. Two or more → the first two are play pills of
  /// their own in place of Play; a third is reached from the Versions rail.
  public var versions: [MediaActionVersion]
  public var loading: Set<MediaActionID>

  public init(
    playback: PlaybackButtonContent,
    kind: MediaPresentationKind = .fiction,
    isSeries: Bool,
    isBookmarked: Bool = false,
    isFollowing: Bool = false,
    showsMarkWatched: Bool = false,
    showsTrailer: Bool = false,
    showsFollow: Bool = false,
    download: MediaActionDownloadPhase? = nil,
    showsShuffle: Bool = false,
    showsMore: Bool = false,
    promoteFollow: Bool = false,
    versions: [MediaActionVersion] = [],
    loading: Set<MediaActionID> = []
  ) {
    self.playback = playback
    self.kind = kind
    self.isSeries = isSeries
    self.isBookmarked = isBookmarked
    self.isFollowing = isFollowing
    self.showsMarkWatched = showsMarkWatched
    self.showsTrailer = showsTrailer
    self.showsFollow = showsFollow
    self.download = download
    self.showsShuffle = showsShuffle
    self.showsMore = showsMore
    self.promoteFollow = promoteFollow
    self.versions = versions
    self.loading = loading
  }

  /// Backward-compatible bool for older call sites / tests.
  public var showsDownload: Bool {
    get {
      switch download {
      case .idle, .downloading: return true
      case .downloaded, .none: return false
      }
    }
    set {
      if newValue {
        if download == nil || download == .downloaded { download = .idle }
      } else {
        download = nil
      }
    }
  }

  var isMidTitle: Bool {
    if case .resume = playback { return true }
    return false
  }

  /// Two version pills stand where Play would.
  public var showsVersionButtons: Bool {
    versions.count >= 2
  }
}

public enum MediaActionCatalog {

  public static func row(for context: MediaActionContext) -> [MediaActionAppearance] {
    if context.promoteFollow {
      return awaitingNextEpisodeRow(for: context)
    }

    var row: [MediaActionAppearance] = playButtons(for: context)

    let mark = context.showsMarkWatched ? markWatched(for: context) : nil
    if let mark, mark.chrome == .pill {
      row.append(mark)
    }
    if context.showsTrailer {
      row.append(trailer(for: context))
    }
    row.append(bookmark(for: context))
    if context.showsFollow {
      row.append(follow(for: context))
    }
    if let mark, mark.chrome == .circle {
      row.append(mark)
    }
    if let download = download(for: context) {
      row.append(download)
    }
    // Icon only, always just before More — never a labelled Trailer peer.
    if context.showsShuffle {
      row.append(shuffle(for: context))
    }
    if context.showsMore {
      row.append(more(for: context))
    }
    return row
  }

  /// `[Отслеживать] · Trailer · Replay · bookmark · …`
  private static func awaitingNextEpisodeRow(
    for context: MediaActionContext
  ) -> [MediaActionAppearance] {
    var row: [MediaActionAppearance] = [
      follow(for: context, chrome: .playPill, titled: true)
    ]
    if context.showsTrailer {
      row.append(trailer(for: context))
    }
    row.append(play(for: context)) // Replay — playAgain chrome/title
    row.append(bookmark(for: context))
    if let download = download(for: context) {
      row.append(download)
    }
    if context.showsMore {
      row.append(more(for: context))
    }
    return row
  }

  /// Play — or, for a film with several versions, one play pill for each of the first
  /// two. A third version is not a button; the Versions rail under the hero has it.
  static func playButtons(for context: MediaActionContext) -> [MediaActionAppearance] {
    guard context.showsVersionButtons else { return [play(for: context)] }
    return [version(context.versions[0], at: 0, for: context),
            version(context.versions[1], at: 1, for: context)]
  }

  // MARK: Per-action

  /// One version's play pill. The label is the version's name ("24 fps"), else
  /// «Смотреть» for the first and «Вторая версия» for the second. Its state is that
  /// version's own: a progress bar when started, the Replay glyph and the quieter pill
  /// when watched — the same rules as the single Play button.
  public static func version(_ version: MediaActionVersion,
                             at index: Int,
                             for context: MediaActionContext) -> MediaActionAppearance {
    let id: MediaActionID = index == 0 ? .play : .playAlternate
    let title = MediaActionCopy.versionTitle(name: version.name, index: index)
    switch version.playback {
    case .playAgain:
      return MediaActionAppearance(
        id: id,
        chrome: .pill,
        systemImage: "arrow.clockwise",
        title: title,
        accessibilityLabel: title,
        isLoading: context.loading.contains(id)
      )
    case .resume(let progress, _, _, _):
      return MediaActionAppearance(
        id: id,
        chrome: index == 0 ? .playPill : .pill,
        systemImage: "play.fill",
        title: title,
        progress: progress,
        accessibilityLabel: title,
        isLoading: context.loading.contains(id)
      )
    case .play:
      return MediaActionAppearance(
        id: id,
        chrome: index == 0 ? .playPill : .pill,
        systemImage: "play.fill",
        title: title,
        accessibilityLabel: title,
        isLoading: context.loading.contains(id)
      )
    }
  }

  public static func play(for context: MediaActionContext) -> MediaActionAppearance {
    let loading = context.loading.contains(.play)
    let caption = MediaActionCopy.playCaption(playback: context.playback, kind: context.kind)
    switch context.playback {
    case .playAgain:
      return MediaActionAppearance(
        id: .play,
        chrome: .pill,
        systemImage: "arrow.clockwise",
        title: caption.title,
        accessibilityLabel: caption.accessibility,
        isLoading: loading
      )
    case .play, .resume:
      return MediaActionAppearance(
        id: .play,
        chrome: .playPill,
        systemImage: "play.fill",
        title: caption.title,
        progress: caption.progress,
        accessibilityLabel: caption.accessibility,
        isLoading: loading
      )
    }
  }

  public static func markWatched(for context: MediaActionContext) -> MediaActionAppearance {
    let title = MediaActionCopy.localized("Mark as Watched")
    // Two version pills already make the row long; the checkmark stays a circle there.
    let midTitle = context.isMidTitle && !context.showsVersionButtons
    return MediaActionAppearance(
      id: .markWatched,
      chrome: midTitle ? .pill : .circle,
      systemImage: "checkmark",
      title: midTitle ? title : nil,
      accessibilityLabel: title,
      isLoading: context.loading.contains(.markWatched)
    )
  }

  public static func trailer(for context: MediaActionContext) -> MediaActionAppearance {
    let title = MediaActionCopy.localized("Trailer")
    return MediaActionAppearance(
      id: .trailer,
      chrome: .pill,
      systemImage: "play.fill",
      title: title,
      accessibilityLabel: title,
      isLoading: context.loading.contains(.trailer)
    )
  }

  public static func bookmark(for context: MediaActionContext) -> MediaActionAppearance {
    MediaActionAppearance(
      id: .bookmark,
      chrome: .circle,
      systemImage: context.isBookmarked ? "bookmark.fill" : "bookmark",
      accessibilityLabel: MediaActionCopy.localized("Bookmarks"),
      isLoading: context.loading.contains(.bookmark)
    )
  }

  public static func follow(
    for context: MediaActionContext,
    chrome: MediaActionChrome = .circle,
    titled: Bool = false
  ) -> MediaActionAppearance {
    let following = context.isFollowing
    let title = titled ? MediaActionCopy.followTitle(isFollowing: following) : nil
    return MediaActionAppearance(
      id: .follow,
      chrome: chrome,
      systemImage: following
        ? "bell.and.waves.left.and.right.fill"
        : "bell",
      title: title,
      accessibilityLabel: MediaActionCopy.followTitle(isFollowing: following),
      isLoading: context.loading.contains(.follow)
    )
  }

  public static func download(for context: MediaActionContext) -> MediaActionAppearance? {
    switch context.download {
    case .none, .downloaded:
      return nil
    case .idle:
      return MediaActionAppearance(
        id: .download,
        chrome: .circle,
        systemImage: "arrow.down.to.line",
        accessibilityLabel: MediaActionCopy.localized("Download"),
        isLoading: context.loading.contains(.download)
      )
    case .downloading(let progress):
      return MediaActionAppearance(
        id: .download,
        chrome: .circle,
        systemImage: "pause.fill",
        circularProgress: progress,
        accessibilityLabel: MediaActionCopy.localized("Pause Download"),
        isLoading: false
      )
    }
  }

  public static func shuffle(for context: MediaActionContext) -> MediaActionAppearance {
    let title = MediaActionCopy.localized("Shuffle")
    return MediaActionAppearance(
      id: .shuffle,
      chrome: .circle,
      systemImage: "shuffle",
      title: nil,
      accessibilityLabel: title,
      isLoading: context.loading.contains(.shuffle)
    )
  }

  public static func more(for context: MediaActionContext) -> MediaActionAppearance {
    MediaActionAppearance(
      id: .more,
      chrome: .circle,
      systemImage: "ellipsis",
      accessibilityLabel: MediaActionCopy.localized("More"),
      isLoading: context.loading.contains(.more)
    )
  }

  /// Everything kino.pub has is watched, the series is not finished, and the next
  /// episode of the season kino.pub is on has a known date — ahead, or already aired and
  /// not uploaded yet. Either way there is nothing to play and something to wait for.
  /// No window on the date: a premiere a month out is still the next thing to follow.
  public static func shouldPromoteFollow(
    isSeries: Bool,
    playback: PlaybackButtonContent,
    seriesFinished: Bool,
    awaitedEpisodeAirDate: Date?
  ) -> Bool {
    guard isSeries, !seriesFinished, case .playAgain = playback else { return false }
    return awaitedEpisodeAirDate != nil
  }
}
