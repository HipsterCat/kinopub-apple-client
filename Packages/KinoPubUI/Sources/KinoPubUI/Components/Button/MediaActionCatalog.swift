//
//  MediaActionCatalog.swift
//  KinoPubUI
//
//  Label / chrome / order for media primary-action rows. One mapping, used by the
//  detail hero today and reusable anywhere the same buttons appear — the view that
//  hosts them does not invent icons or weights per screen.
//
//  Human copy lives in `MediaActionCopy` and `docs/product/media-actions.md`.
//  The visual mold is `#Preview("Action chrome")` in `MediaActionButtonStyle.swift`.
//

import Foundation
import KinoPubBackend

// MARK: - Identity

/// Which control this is. Call sites wire behaviour by id; the catalog never owns
/// navigation, menus, or network.
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

/// System chrome vocabulary from `MediaActionButtonStyle` — nothing hand-drawn.
/// `playPill` is `.glassProminent`, `pill` / `circle` are `.glass`. White elevated
/// fill is focus, never a permanent tint on Play.
public enum MediaActionChrome: Hashable, Sendable {
  /// Entry Play / Resume — `.glassProminent` capsule.
  case playPill
  /// Labelled secondary — `.glass` capsule (Trailer, Mark Watched mid-title, Replay, Shuffle).
  case pill
  /// Icon-only — `.glass` circle (bookmark / follow / watched / download / more).
  case circle
}

// MARK: - Appearance

/// Everything a button needs to draw, and nothing about what tapping it does.
public struct MediaActionAppearance: Equatable, Identifiable, Sendable {
  public var id: MediaActionID
  public var chrome: MediaActionChrome
  /// SF Symbol name.
  public var systemImage: String
  /// Nil → icon-only circle (or loading spinner in its place).
  public var title: String?
  /// When set, the play label shows `MediaActionProgressTrack` between the glyph and
  /// the title — the one non-system piece of chrome.
  public var progress: Double?
  public var accessibilityLabel: String
  public var isLoading: Bool

  public init(
    id: MediaActionID,
    chrome: MediaActionChrome,
    systemImage: String,
    title: String? = nil,
    progress: Double? = nil,
    accessibilityLabel: String,
    isLoading: Bool = false
  ) {
    self.id = id
    self.chrome = chrome
    self.systemImage = systemImage
    self.title = title
    self.progress = progress
    self.accessibilityLabel = accessibilityLabel
    self.isLoading = isLoading
  }
}

// MARK: - Context

/// Facts the catalog needs. Kept free of `MediaItem` / view models so cards, sheets
/// and the hero can all build one.
public struct MediaActionContext: Equatable, Sendable {
  public var playback: PlaybackButtonContent
  public var kind: MediaPresentationKind
  public var isSeries: Bool
  public var isBookmarked: Bool
  public var isFollowing: Bool
  public var showsMarkWatched: Bool
  public var showsTrailer: Bool
  public var showsFollow: Bool
  public var showsDownload: Bool
  public var showsShuffle: Bool
  public var showsMore: Bool
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
    showsDownload: Bool = false,
    showsShuffle: Bool = false,
    showsMore: Bool = false,
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
    self.showsDownload = showsDownload
    self.showsShuffle = showsShuffle
    self.showsMore = showsMore
    self.loading = loading
  }

  var isMidTitle: Bool {
    if case .resume = playback { return true }
    return false
  }
}

// MARK: - Catalog

public enum MediaActionCatalog {

  /// Ordered primary row for the given state. Empty slots are simply absent — callers
  /// do not filter.
  public static func row(for context: MediaActionContext) -> [MediaActionAppearance] {
    var row: [MediaActionAppearance] = [play(for: context)]

    let mark = context.showsMarkWatched ? markWatched(for: context) : nil
    // Mid-title Mark Watched is a labelled pill and sits next to Play (preview mold).
    // Fresh-start checkmark is a circle and joins the state cluster after Trailer.
    if let mark, mark.chrome == .pill {
      row.append(mark)
    }
    if context.showsTrailer {
      row.append(trailer(for: context))
    }
    // Labelled Shuffle peers Trailer when the row is not already dense with Mark Watched.
    if context.showsShuffle, !context.isMidTitle {
      row.append(shuffle(for: context))
    }
    row.append(bookmark(for: context))
    if context.showsFollow {
      row.append(follow(for: context))
    }
    if let mark, mark.chrome == .circle {
      row.append(mark)
    }
    if context.showsDownload {
      row.append(download(for: context))
    }
    // In-progress: Shuffle is a quiet circle after the state cluster.
    if context.showsShuffle, context.isMidTitle {
      row.append(shuffle(for: context))
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

  public static func follow(for context: MediaActionContext) -> MediaActionAppearance {
    let following = context.isFollowing
    return MediaActionAppearance(
      id: .follow,
      chrome: .circle,
      systemImage: following
        ? "bell.and.waves.left.and.right.fill"
        : "bell",
      accessibilityLabel: following
        ? MediaActionCopy.localized("Remove from Watchlist")
        : MediaActionCopy.localized("Add to Watchlist"),
      isLoading: context.loading.contains(.follow)
    )
  }

  public static func download(for context: MediaActionContext) -> MediaActionAppearance {
    MediaActionAppearance(
      id: .download,
      chrome: .circle,
      systemImage: "arrow.down.to.line",
      accessibilityLabel: MediaActionCopy.localized("Download"),
      isLoading: context.loading.contains(.download)
    )
  }

  public static func shuffle(for context: MediaActionContext) -> MediaActionAppearance {
    let title = MediaActionCopy.localized("Shuffle")
    // Preview: labelled "Случайно" next to Trailer when the row is not mid-title;
    // quiet circle once Mark Watched is already a pill.
    let labelled = !context.isMidTitle
    return MediaActionAppearance(
      id: .shuffle,
      chrome: labelled ? .pill : .circle,
      systemImage: "shuffle",
      title: labelled ? title : nil,
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
}
