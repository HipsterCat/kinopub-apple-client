//
//  RouteDestination.swift
//  KinoPubAppleClient
//
//  Single destination registry for every tab's NavigationStack.
//

import SwiftUI
import KinoPubBackend
import KinoPubKit
import KinoPubMetadata
import KinoPubUI

struct RouteDestination: View {
  let route: Route
  let linkProvider: NavigationLinkProvider
  /// Namespace for system zoom transitions sourced from cards / banners / cast.
  var transitionNamespace: Namespace.ID?

  @Environment(\.appContext) private var appContext
  @Environment(ErrorHandler.self) private var errorHandler
  @EnvironmentObject private var authState: AuthState
  @Environment(NavigationState.self) private var navigationState

  var body: some View {
    destination
      .modifier(ZoomDestinationModifier(route: route, namespace: transitionNamespace))
#if os(tvOS)
      // Product decision 2026-09-21 (Sasha): a pushed page owns the whole screen. The
      // tab bar stays with the tab root — no switching tabs from inside a stack, no bar
      // floating over a detail page fading in and out, and Menu pops instead of finding
      // the bar focused and quitting the app.
      .toolbar(.hidden, for: .tabBar)
#endif
  }

  @ViewBuilder
  private var destination: some View {
    switch route {
    case .details(let item):
      detailsView(for: item.id, knownItem: item)
    case .detailsById(let id):
      detailsView(for: id)
    case .history:
      HistoryView()
    case .bookmark(let bookmark):
      BookmarkView(model: BookmarkModel(bookmark: bookmark,
                                        itemsService: appContext.contentService,
                                        errorHandler: errorHandler))
    case .seasons(let seasons):
      SeasonsView(model: SeasonsModel(seasons: seasons, linkProvider: linkProvider))
    case .season(let season):
      SeasonView(model: SeasonModel(season: season, linkProvider: linkProvider))
    case .person(let person):
      PersonItemsView.make(person: person,
                           linkProvider: linkProvider,
                           context: appContext,
                           authState: authState,
                           errorHandler: errorHandler)
    case .collections:
      CollectionsView.make(context: appContext,
                           authState: authState,
                           errorHandler: errorHandler)
    case .collection(let collection):
      CollectionDetailView.make(collection: collection,
                                context: appContext,
                                errorHandler: errorHandler)
    case .shortcutItems(let shortcut, let contentType, let title):
      ShortcutItemsView.make(shortcut: shortcut,
                             contentType: contentType,
                             title: title,
                             context: appContext,
                             authState: authState,
                             errorHandler: errorHandler)
    case .ratingsAndReviews(let payload):
      MediaItemRatingsAndReviewsPage(payload: payload)
    case .player(let item, let token):
#if os(macOS)
      MacPlayerRouteGuard(item: item, mode: .media)
#else
      PlayerView(manager: PlaybackSession.shared.play(
        item: item,
        mode: .media,
        token: token,
        downloadedFilesDatabase: appContext.downloadedFilesDatabase,
        actionsService: appContext.actionsService
      ))
#endif
    case .trailerPlayer(let item, let token):
#if os(macOS)
      MacPlayerRouteGuard(item: item, mode: .trailer)
#else
      PlayerView(manager: PlaybackSession.shared.play(
        item: item,
        mode: .trailer,
        token: token,
        downloadedFilesDatabase: appContext.downloadedFilesDatabase,
        actionsService: appContext.actionsService
      ))
#endif
    }
  }

  private func detailsView(for id: Int, knownItem: MediaItem? = nil) -> some View {
    MediaItemView(model: MediaItemModel(mediaItemId: id,
                                        knownItem: knownItem,
                                        itemsService: appContext.contentService,
                                        downloadManager: appContext.downloadManager,
                                        linkProvider: linkProvider,
                                        errorHandler: errorHandler))
  }
}

/// Applies `navigationTransition(.zoom)` when a matched source namespace is present.
///
/// tvOS: only when a `TVPage` registered a source for this id (`TVZoomSourceStore`).
/// Asking for a zoom with no source on screen is what made the card jump and vanish in
/// one frame; every other push stays the plain system push.
private struct ZoomDestinationModifier: ViewModifier {
  let route: Route
  let namespace: Namespace.ID?

#if os(tvOS)
  @Environment(\.zoomSourceStore) private var zoomSources
#endif

  func body(content: Content) -> some View {
#if os(iOS) || os(tvOS)
    if let namespace, let sourceID = route.zoomSourceID, hasSource(for: sourceID) {
      content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
    } else {
      content
    }
#else
    content
#endif
  }

  private func hasSource(for sourceID: String) -> Bool {
#if os(tvOS)
    zoomSources?.hasSource(for: sourceID) ?? false
#else
    true
#endif
  }
}

#if os(macOS)
/// Safety net, not the fix: the player is never supposed to reach the main stack on
/// macOS — every Play entry point either uses `PlayerLink` or routes through
/// `NavigationState.push`, both of which open the dedicated window directly (see
/// `ROADMAP.md`, "macOS presentation"). If a
/// `.player` / `.trailerPlayer` route still lands here, open the window and pop this
/// destination instead of showing the player inline next to the sidebar.
private struct MacPlayerRouteGuard: View {
  let item: any PlayableItem
  let mode: WatchMode

  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    Color.clear
      .onAppear {
        assertionFailure("'.player'/'.trailerPlayer' reached the main stack on macOS — route through PlayerLink instead")
        PlaybackWindowState.shared.show(item: item, mode: mode)
        openWindow(id: PlaybackWindowState.windowID)
        dismiss()
      }
  }
}
#endif

extension Route {
  /// Stable zoom source id shared with `matchedTransitionSource` on cards.
  var zoomSourceID: String? {
    switch self {
    case .details(let item):
      return "media-\(item.id)"
    case .detailsById(let id):
      return "media-\(id)"
    case .person(let person):
      return "person-\(person.id)"
    default:
      return nil
    }
  }
}
