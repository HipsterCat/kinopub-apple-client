//
//  MediaActionCatalog.swift
//  KinoPubUI
//
//  Label / chrome / order for media primary-action rows. One mapping, used by the
//  detail hero today and reusable anywhere the same buttons appear — the view that
//  hosts them does not invent icons or weights per screen.
//
//  The visual mold is the `#Preview` at the bottom of `MediaActionButtonStyle.swift`
//  (settled LazyHStack rows): play weight, quieter replay, labelled Mark Watched only
//  mid-title, Trailer as a pill, state circles after that.
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
/// `playPill` and `pill` draw the same plate; `playPill` only names the entry control
/// (default focus). White fill is focus, never a permanent tint on Play.
public enum MediaActionChrome: Hashable, Sendable {
  /// Capsule for Play / Resume — same look as `pill`; kept distinct so callers can
  /// still ask "is this the entry action?" without inventing a second visual system.
  case playPill
  /// `.borderedProminent` capsule — Trailer, Mark Watched (mid-title), Replay.
  case pill
  /// `.bordered` circle — bookmark / follow / watched / download / more.
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
    if context.showsShuffle {
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
    switch context.playback {
    case .play(let episodeLabel):
      let title: String
      let accessibility: String
      if let episodeLabel, !episodeLabel.isEmpty {
        // Series mold: the episode *is* the label — no "Play" prefix beside Trailer.
        title = episodeLabel
        accessibility = localized("Play") + " " + episodeLabel
      } else {
        title = localized("Play")
        accessibility = title
      }
      return MediaActionAppearance(
        id: .play,
        chrome: .playPill,
        systemImage: "play.fill",
        title: title,
        accessibilityLabel: accessibility,
        isLoading: loading
      )

    case .resume(let progress, let episodeLabel, let durationSeconds):
      let title = resumeTitle(episodeLabel: episodeLabel, durationSeconds: durationSeconds)
      let accessibility: String = {
        if let episodeLabel { return localized("Resume") + " " + episodeLabel }
        return localized("Resume")
      }()
      return MediaActionAppearance(
        id: .play,
        chrome: .playPill,
        systemImage: "play.fill",
        title: title,
        progress: progress,
        accessibilityLabel: accessibility,
        isLoading: loading
      )

    case .playAgain:
      // Watched: clockwise glyph + same capsule weight as Trailer. White is focus.
      let title = localized("Play Again")
      return MediaActionAppearance(
        id: .play,
        chrome: .pill,
        systemImage: "arrow.clockwise",
        title: title,
        accessibilityLabel: title,
        isLoading: loading
      )
    }
  }

  public static func markWatched(for context: MediaActionContext) -> MediaActionAppearance {
    let title = localized("Mark as Watched")
    // Mid-title: labelled pill. Fresh start: icon circle. Matches the preview rows.
    let midTitle: Bool = {
      if case .resume = context.playback { return true }
      return false
    }()
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
    let title = localized("Trailer")
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
      accessibilityLabel: localized("Bookmarks"),
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
        ? localized("Remove from Watchlist")
        : localized("Add to Watchlist"),
      isLoading: context.loading.contains(.follow)
    )
  }

  public static func download(for context: MediaActionContext) -> MediaActionAppearance {
    MediaActionAppearance(
      id: .download,
      chrome: .circle,
      systemImage: "arrow.down.to.line",
      accessibilityLabel: localized("Download"),
      isLoading: context.loading.contains(.download)
    )
  }

  public static func shuffle(for context: MediaActionContext) -> MediaActionAppearance {
    let title = localized("Shuffle")
    return MediaActionAppearance(
      id: .shuffle,
      chrome: .circle,
      systemImage: "shuffle",
      accessibilityLabel: title,
      isLoading: context.loading.contains(.shuffle)
    )
  }

  public static func more(for context: MediaActionContext) -> MediaActionAppearance {
    MediaActionAppearance(
      id: .more,
      chrome: .circle,
      systemImage: "ellipsis",
      accessibilityLabel: localized("More"),
      isLoading: context.loading.contains(.more)
    )
  }

  // MARK: Copy helpers

  /// Meta beside the resume bar — "S1, E2 · 39m" or "39m". Falls back to Resume copy
  /// when neither episode nor duration is worth saying.
  public static func resumeTitle(episodeLabel: String?, durationSeconds: Int) -> String {
    var parts: [String] = []
    if let episodeLabel, !episodeLabel.isEmpty { parts.append(episodeLabel) }
    if durationSeconds >= 60 {
      let duration = Duration.compactHoursMinutes(seconds: durationSeconds)
      if !duration.isEmpty { parts.append(duration) }
    }
    if !parts.isEmpty { return parts.joined(separator: " · ") }
    if let episodeLabel, !episodeLabel.isEmpty {
      return localized("Resume") + " " + episodeLabel
    }
    return localized("Resume")
  }

  /// Package code has no `String.localized`; resolve against the app catalogue the
  /// same way `PaginationState` does.
  static func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
  }
}
