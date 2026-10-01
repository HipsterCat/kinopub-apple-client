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
  /// Series ongoing, all watched, next episode within ~2 weeks → labelled Follow leads.
  public var promoteFollow: Bool
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
}

public enum MediaActionCatalog {

  public static func row(for context: MediaActionContext) -> [MediaActionAppearance] {
    if context.promoteFollow {
      return awaitingNextEpisodeRow(for: context)
    }

    var row: [MediaActionAppearance] = [play(for: context)]

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

  // MARK: Per-action

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
    let midTitle = context.isMidTitle
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

  /// Next episode within two weeks, series not finished, everything watched.
  public static func shouldPromoteFollow(
    isSeries: Bool,
    playback: PlaybackButtonContent,
    seriesFinished: Bool,
    nextEpisodeAirDate: Date?,
    now: Date = Date()
  ) -> Bool {
    guard isSeries, !seriesFinished, case .playAgain = playback,
          let air = nextEpisodeAirDate, air > now else { return false }
    let fortnight: TimeInterval = 14 * 24 * 60 * 60
    return air.timeIntervalSince(now) <= fortnight
  }
}
