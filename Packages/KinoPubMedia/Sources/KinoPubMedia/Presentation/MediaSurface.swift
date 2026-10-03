import Foundation

/// **Where a fact is shown, and at what length** — the one table. Two surfaces that word
/// the same fact differently differ *here*, on purpose, never in a second helper.
public enum MediaSurface: String, Hashable, Sendable, CaseIterable {
  /// The system player's subtitle line (`PlayerInfo`).
  case playerSubtitle
  /// The detail hero's action capsules — Play, Resume, Replay, Mark Watched.
  case heroAction
  /// A Continue Watching / Up Next card's overlay.
  case continueWatchingCard
  /// An episode tile on its own season's rail — the season goes without saying.
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

  public var episodeLength: TextLength {
    switch self {
    case .playerSubtitle: return .medium
    case .episodeTile: return .long
    case .heroAction, .continueWatchingCard, .historyRow, .contextMenu, .settingsRow,
         .timeBadge, .detailRuntime:
      return .short
    }
  }

  public var runtimeLength: TextLength {
    switch self {
    // The capsule's «Ещё 53 мин» (`docs/product/media-actions.md`).
    case .heroAction: return .medium
    case .playerSubtitle, .continueWatchingCard, .episodeTile, .historyRow, .contextMenu,
         .settingsRow, .timeBadge, .detailRuntime:
      return .short
    }
  }
}
