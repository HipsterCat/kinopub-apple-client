//
//  MediaCardContextMenus.swift
//  Piratic
//

import Foundation
import KinoPubBackend
import PiraticMedia
import PiraticUI

/// Single source of card context-menu items (ids, titles, icons, grouping).
/// Call sites pass handlers / folder state — missing pieces omit those rows.
@MainActor
enum MediaCardContextMenus {

  /// The "Add to Bookmarks" submenu — what the Home hero's Bookmark button opens.
  static let bookmarksMenuID = "bookmarks"
  /// Watched submenu — same shape as the detail page's «…» Mark as Watched menu.
  static let watchedMenuID = "watched"

  struct BookmarkFolderOption: Identifiable {
    let id: Int
    let title: String
    let isContaining: Bool
  }

  /// Series CW / watching card: Mark Episode · Season · Unwatched in Season · All.
  struct WatchedSubmenu {
    let season: Int
    let episode: Int
    let seasonCount: Int?
    let onMarkEpisode: () -> Void
    let onMarkSeason: () -> Void
    let onMarkUnwatchedInSeason: () -> Void
    let onMarkAllEpisodes: () -> Void
  }

  /// Full Home / Library / banner menu driven by optional handlers.
  static func entries(
    for card: MediaCard,
    surface: MediaCardContextSurface = .shelf,
    bookmarkFolders: [BookmarkFolderOption] = [],
    onPlay: (() -> Void)? = nil,
    onDownload: (() -> Void)? = nil,
    onGoToTitle: (() -> Void)? = nil,
    onToggleWatchlist: (() -> Void)? = nil,
    onToggleBookmarkFolder: ((Int) -> Void)? = nil,
    onCreateBookmarkFolder: (() -> Void)? = nil,
    onToggleWatched: (() -> Void)? = nil,
    /// When set (and the card is not already watched), Watched is a submenu like «…».
    watchedSubmenu: WatchedSubmenu? = nil,
    onHide: (() -> Void)? = nil,
    /// Admin only: the Change Images sheet for this title.
    onChangeImages: (() -> Void)? = nil,
    onOpenImageURL: ((URL) -> Void)? = nil,
    /// DEBUG menu rows — when empty, falls back to the card's painted artwork URL.
    debugImageURLs: [URL] = []
  ) -> [MediaCardContextEntry] {
    // TODO(downloads): when `FeatureFlags.downloadsEnabled` ships, add Download here.
    var entries: [MediaCardContextEntry] = []
    var needsDivider = false

    func appendDivider() {
      if needsDivider {
        entries.append(.divider(id: "divider-\(entries.count)"))
      }
      needsDivider = false
    }

    func markGroup() {
      needsDivider = false
    }

    // MARK: Playback
    if let onPlay {
      appendDivider()
      entries.append(.action(MediaCardContextAction(
        id: "play",
        title: "Play".localized,
        systemImage: "play.fill",
        handler: onPlay
      )))
      markGroup()
         
    }
       
       // MARK: Navigation
       if let onDownload {
         appendDivider()
         entries.append(.action(MediaCardContextAction(
           id: "download",
           title: "Download",
           systemImage: "arrow.down",
           handler: onDownload
         )))
         markGroup()
       }
       
       // MARK: Watched
       // Series with a known S/E: dropdown like the detail «…» menu. Films / already
       // watched stay a single row ("Mark as New").
       if let watchedSubmenu, !card.isWatched {
         appendDivider()
         let episodeLabel = EpisodeText(
           season: watchedSubmenu.season,
           number: watchedSubmenu.episode,
           seasonCount: watchedSubmenu.seasonCount
         ).text(for: .contextMenu)
         let seasonLabel = SeasonText(watchedSubmenu.season)
           .formatted(MediaSurface.contextMenu.textLength)
         entries.append(.submenu(
           id: watchedMenuID,
           title: String(localized: "MediaAction_MarkWatchedMenu"),
           systemImage: "checkmark.circle",
           children: [
             MediaCardContextAction(
               id: "mark-episode-watched",
               title: "\("Mark Episode Watched".localized) · \(episodeLabel)",
               systemImage: "checkmark",
               handler: watchedSubmenu.onMarkEpisode
             ),
             MediaCardContextAction(
               id: "mark-season-watched",
               title: "\("Mark Season Watched".localized) · \(seasonLabel)",
               systemImage: "checkmark.circle",
               handler: watchedSubmenu.onMarkSeason
             ),
             MediaCardContextAction(
               id: "mark-unwatched-in-season",
               title: "Mark Unwatched in Season".localized,
               systemImage: "checkmark.circle",
               handler: watchedSubmenu.onMarkUnwatchedInSeason
             ),
             MediaCardContextAction(
               id: "mark-all-episodes-watched",
               title: "Mark All Episodes Watched".localized,
               systemImage: "checkmark.circle.fill",
               handler: watchedSubmenu.onMarkAllEpisodes
             )
           ],
           footer: []
         ))
         markGroup()
       } else if let onToggleWatched {
         appendDivider()
         entries.append(.action(MediaCardContextAction(
           id: "toggle-watched",
           title: (card.isWatched ? "Mark as New" : "Mark as Watched").localized,
           systemImage: card.isWatched ? "eye.slash" : "checkmark",
           handler: onToggleWatched
         )))
         markGroup()
       }

    // MARK: Navigation / Info
    if let onGoToTitle {
      appendDivider()
      let infoTitle: String
      if surface == .episodeRail {
        infoTitle = "Info".localized
      } else {
        infoTitle = (card.isSeries ? "Go to Show" : "Go to Movie").localized
      }
      entries.append(.action(MediaCardContextAction(
        id: surface == .episodeRail ? "info" : "go-to-title",
        title: infoTitle,
        systemImage: "info",
        handler: onGoToTitle
      )))
      markGroup()
    }

    // MARK: Library
    // Episode rail: bookmarks / Follow belong on the series, not one episode tile.
    let showBookmarks = surface != .episodeRail
      && (onToggleBookmarkFolder != nil || onCreateBookmarkFolder != nil)
    // Follow is a series' alone; a film is kept with bookmarks (user's call, 2026-10-03).
    let onToggleFollow = surface != .episodeRail && card.isSeries ? onToggleWatchlist : nil
    // Read when the menu opens, not from the card: a follow toggled since the row was
    // built already counts.
    let isFollowing = onToggleFollow != nil
      && AppContext.shared.viewerState.state(for: card.ref, reported: card.reportedState).isFollowing == true
    let hasLibrary = onToggleFollow != nil || showBookmarks
    if hasLibrary {
      appendDivider()
      if let onToggleFollow {
        entries.append(.action(MediaCardContextAction(
          id: "toggle-watchlist",
          title: MediaActionCopy.followMenuTitle(isFollowing: isFollowing),
          systemImage: isFollowing ? "bell.slash" : "bell",
          handler: onToggleFollow
        )))
      }
      if showBookmarks {
        let children: [MediaCardContextAction]
        if let onToggleBookmarkFolder {
          children = bookmarkFolders.map { folder in
            MediaCardContextAction(
              id: "bookmark-folder-\(folder.id)",
              title: folder.title,
              systemImage: "folder",
              isSelection: true,
              isOn: folder.isContaining,
              handler: { onToggleBookmarkFolder(folder.id) }
            )
          }
        } else {
          children = []
        }
        let footer: [MediaCardContextAction]
        if let onCreateBookmarkFolder {
          footer = [
            MediaCardContextAction(
              id: "new-bookmark-folder",
              title: "New Folder".localized,
              systemImage: "folder.badge.plus",
              handler: onCreateBookmarkFolder
            )
          ]
        } else {
          footer = []
        }
        entries.append(.submenu(
          id: bookmarksMenuID,
          title: "Add to Bookmarks".localized,
          systemImage: "bookmark",
          children: children,
          footer: footer
        ))
      }
      markGroup()
    }


    // MARK: Destructive / CW
    if let onHide, surface != .episodeRail {
      appendDivider()
      entries.append(.action(MediaCardContextAction(
        id: "hide",
        title: "Hide",
        systemImage: "trash",
        handler: onHide
      )))
      markGroup()
    }

    // MARK: Admin
    if let onChangeImages {
      appendDivider()
      entries.append(.action(MediaCardContextAction(
        id: "change-images",
        title: String(localized: "Change Images"),
        systemImage: "photo.on.rectangle",
        handler: onChangeImages
      )))
      markGroup()
    }

    // MARK: Debug
#if DEBUG
    var debugURLs = debugImageURLs
    if debugURLs.isEmpty,
       let raw = artworkURL(for: card, surface: surface),
       let url = URL(string: raw) {
      debugURLs = [url]
    }
    if let onOpenImageURL, !debugURLs.isEmpty {
      appendDivider()
      for (index, url) in debugURLs.enumerated() {
        entries.append(.action(MediaCardContextAction(
          id: "debug-image-url-\(index)",
          title: url.absoluteString,
          systemImage: "photo",
          handler: { onOpenImageURL(url) }
        )))
      }
    }
#else
    _ = debugImageURLs
    _ = onOpenImageURL
    _ = surface
#endif

    return entries
  }

  /// First artwork request the preview makes, with the same worker route as the card.
  static func artworkURL(for card: MediaCard, surface: MediaCardContextSurface) -> String? {
    card.sneakPeekArtworkURL(surface: surface, images: AppContext.shared.metadataService.images)?.absoluteString
  }

  /// Builds entries for a card using the shared coordinator + navigation hooks.
  @MainActor
  static func entries(
    for card: MediaCard,
    surface: MediaCardContextSurface,
    menu: MediaCardMenuCoordinator,
    pushRoute: @escaping (Route) -> Void,
    openURL: @escaping (URL) -> Void,
    isContinueWatchingStyle: Bool = false,
    includePlay: Bool = false,
    includeGoToTitle: Bool = true
  ) -> [MediaCardContextEntry] {
    let containing = menu.containingFolders(for: card)
    let folderOptions = menu.folders.map {
      BookmarkFolderOption(id: $0.id, title: $0.title, isContaining: containing.contains($0.id))
    }

    let canMarkWatched: Bool = {
      if isContinueWatchingStyle { return card.canToggleWatched || !card.isSeries }
      return !card.isSeries
    }()
    let watchedSubmenu: WatchedSubmenu? = {
      guard canMarkWatched, !card.isWatched,
            card.isSeries, let season = card.season, let episode = card.video else { return nil }
      return WatchedSubmenu(
        season: season,
        episode: episode,
        seasonCount: card.seasonCount,
        onMarkEpisode: {
          menu.toggleWatched(card, removeFromContinueWatching: isContinueWatchingStyle)
        },
        onMarkSeason: {
          menu.markSeasonWatched(card, removeFromContinueWatching: isContinueWatchingStyle)
        },
        onMarkUnwatchedInSeason: {
          menu.markUnwatchedInSeason(card)
        },
        onMarkAllEpisodes: {
          menu.markAllEpisodesWatched(card, removeFromContinueWatching: isContinueWatchingStyle)
        }
      )
    }()

    return entries(
      for: card,
      surface: surface,
      bookmarkFolders: folderOptions,
      onPlay: includePlay ? { menu.play(card, push: pushRoute) } : nil,
      onDownload: nil,
      onGoToTitle: includeGoToTitle ? { pushRoute(.detailsById(card.itemID)) } : nil,
      onToggleWatchlist: card.isSeries ? { menu.toggleWatchlist(card) } : nil,
      onToggleBookmarkFolder: { folderID in
        guard let folder = menu.folders.first(where: { $0.id == folderID }) else { return }
        menu.toggleBookmark(itemID: card.itemID,
                            folder: folder,
                            serverHint: card.viewerState.bookmarkFolderIDs ?? [])
      },
      onCreateBookmarkFolder: { menu.promptNewFolder(for: card.itemID) },
      onToggleWatched: canMarkWatched && watchedSubmenu == nil
        ? { menu.toggleWatched(card, removeFromContinueWatching: isContinueWatchingStyle) }
        : nil,
      watchedSubmenu: watchedSubmenu,
      onHide: isContinueWatchingStyle
        ? { menu.hideFromContinueWatching(card) }
        : nil,
      onChangeImages: menu.canChangeImages ? { menu.changeImages(card) } : nil,
      onOpenImageURL: openURL
    )
  }

  /// Catalog / Search / person-credits / bookmark-folder grids (`MediaItem` → card).
  @MainActor
  static func entries(
    for item: MediaItem,
    menu: MediaCardMenuCoordinator,
    pushRoute: @escaping (Route) -> Void,
    openURL: @escaping (URL) -> Void
  ) -> [MediaCardContextEntry] {
    entries(for: MediaCard(item),
            surface: .shelf,
            menu: menu,
            pushRoute: pushRoute,
            openURL: openURL)
  }

  /// DEBUG-only image URL rows (cast photos, etc.).
  static func debugImageEntries(urls: [URL],
                                openURL: @escaping (URL) -> Void) -> [MediaCardContextEntry] {
#if DEBUG
    guard !urls.isEmpty else { return [] }
    return urls.enumerated().map { index, url in
      .action(MediaCardContextAction(
        id: "debug-image-url-\(index)",
        title: url.absoluteString,
        systemImage: "photo",
        handler: { openURL(url) }
      ))
    }
#else
    _ = (urls, openURL)
    return []
#endif
  }
}
