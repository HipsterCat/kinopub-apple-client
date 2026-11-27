import Foundation

/// How a surface words an episode — one of `EpisodeText`'s shapes.
public enum EpisodeStyle: Hashable, Sendable {
  /// `EpisodeText.formatted(_:)` — the player's «S1, E2: Name», a capsule's «S1, E2».
  case formatted(TextLength)
  /// `EpisodeText.titled(_:)` — the reference, then «: Name» when there is one.
  case titled(TextLength)
  /// `EpisodeText.listItem()` — «7. Name», «Серия 7».
  case listItem
}

/// **Where a fact is shown, and at what length** — the one table. Two surfaces that word
/// the same fact differently differ *here*, on purpose, never in a second helper.
public enum MediaSurface: String, Hashable, Sendable, CaseIterable {
  /// The system player's subtitle line (`PlayerInfo`).
  case playerSubtitle
  /// The detail hero's action capsules — Play, Resume, Replay, Mark Watched.
  case heroAction
  /// A Continue Watching card's overlay.
  case continueWatchingCard
  /// The player's Up Next tab: the next episode may be in the next season.
  case upNextTile
  /// An episode tile on the detail page — the season switch is right there, or there is
  /// only one season.
  case episodeTile
  /// A history row.
  case historyRow
  /// A context-menu item.
  case contextMenu
  /// A settings row (remembered tracks).
  case settingsRow
  /// The runtime chip in a card's corner.
  case timeBadge
  /// The runtime in the detail page's meta line.
  case detailRuntime

  public var episodeStyle: EpisodeStyle {
    switch self {
    case .playerSubtitle: return .formatted(.medium)
    case .episodeTile: return .listItem
    case .upNextTile: return .titled(.short)
    case .heroAction, .continueWatchingCard, .historyRow, .contextMenu, .settingsRow,
         .timeBadge, .detailRuntime:
      return .formatted(.short)
    }
  }

  /// The length for anything else said here — a season on its own (`SeasonText`).
  public var textLength: TextLength {
    switch self {
    case .playerSubtitle: return .medium
    case .episodeTile: return .long
    case .heroAction, .continueWatchingCard, .upNextTile, .historyRow, .contextMenu,
         .settingsRow, .timeBadge, .detailRuntime:
      return .short
    }
  }

  public var runtimeLength: TextLength {
    switch self {
    // The capsule's «Ещё 53 мин» (`docs/product/media-actions.md`).
    case .heroAction: return .medium
    case .playerSubtitle, .continueWatchingCard, .upNextTile, .episodeTile, .historyRow,
         .contextMenu, .settingsRow, .timeBadge, .detailRuntime:
      return .short
    }
  }
}
