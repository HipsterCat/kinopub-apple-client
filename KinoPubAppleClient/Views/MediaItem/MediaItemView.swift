//
//  MediaItemView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 28.07.2023.
//

import Foundation
import SwiftUI
import KinoPubUI
import KinoPubBackend
import KinoPubKit
import KinoPubMetadata

/// Focus targets owned by the hero. One case per button — SIX of them used to share
/// `heroOther`, which is why tvOS focus froze dead on Play: with multiple sibling
/// views bound to the same `@FocusState` equals-value, the engine has no way to
/// resolve which one is actually focused, and directional moves in and out of the
/// group (including Right into the row, and Down past it) simply stop resolving.
enum MediaItemFocusTarget: Hashable {
  case play
  case watchlist
  case bookmark
  case watched
  case trailer
  case more
  case plot
}

/// Whether the hero is on screen, measured by the hero's own frame on iOS and macOS and
/// used for one thing: pausing the ambient trailer once it has scrolled away. An
/// `@Observable` held by reference so the write lands in `MediaItemHeroView` alone and
/// never re-runs this page's body. tvOS does not use it: there the artwork is part of the
/// hero and scrolls away with it, so there is no page-wide state to keep.
@Observable
final class MediaItemHeroPhase {
  var isHeroOnScreen = true
}

struct MediaItemView: View {

  @Environment(ErrorHandler.self) var errorHandler
  @Environment(NavigationState.self) var navigationState
  @StateObject private var itemModel: MediaItemModel
  /// Shared with the hero (Up → fullscreen, the ambient preview behind the artwork).
  @StateObject private var trailer: TrailerPreviewModel
  /// See `MediaItemHeroPhase` — iOS and macOS only in practice.
  @State private var heroPhase = MediaItemHeroPhase()
  /// Bound by the hero's controls and read by nothing in this body. `.defaultFocus`
  /// takes the binding, not the value, so hero focus moves re-render the hero alone.
  @FocusState private var focus: MediaItemFocusTarget?
  /// Owns folder state + context-menu wiring for the related-item rows (Similar /
  /// More from Director / More with Actor) as ONE coordinator shared across all of
  /// them — see `MediaItemRelatedRowsSection`. Previously each of those three
  /// shelves created and bound its own `MediaCardMenuCoordinator` independently.
  @StateObject private var relatedRowsMenu = MediaCardMenuCoordinator()
#if os(macOS)
  /// The one-player rule (`PlaybackSession`) only covers the real film/trailer player.
  /// It says nothing about this page's own *ambient* hero preview, which is a second,
  /// independent `AVPlayer` (`TrailerPreviewModel`). Off macOS that preview stops for
  /// free: pushing the system player onto the stack fires `onDisappear` below. macOS
  /// opens a separate window instead — this page never disappears — so without this,
  /// the hero preview keeps animating behind the new window for as long as it's open.
  @ObservedObject private var playbackWindowState = PlaybackWindowState.shared
#endif

  init(model: @autoclosure @escaping () -> MediaItemModel) {
    _itemModel = StateObject(wrappedValue: model())
    _trailer = StateObject(wrappedValue: TrailerPreviewModel())
  }

  var body: some View {
    @Bindable var errorHandler = errorHandler
    details
      .background(pageBackground)
      .overlay {
        if itemModel.loadFailed {
          UnavailableView(
            title: "Couldn't Load",
            systemImage: "wifi.exclamationmark",
            message: itemModel.loadError?.userFacingMessage ?? "Check your connection and try again.".localized,
            retryTitle: "Try Again",
            onRetry: {
              itemModel.fetchData()
            }
          )
        } else if !itemModel.itemLoaded {
          LoadingIndicatorView(delay: .milliseconds(700))
        }
      }
      .animation(.easeInOut(duration: 0.3), value: itemModel.itemLoaded)
      .animation(.easeInOut(duration: 0.3), value: itemModel.loadFailed)
      // Top only: on macOS, ignoring horizontal safe area draws under the sidebar and
      // the first episode/poster gets clipped. tvOS/iOS still bleed the hero edge-to-edge.
#if os(macOS)
      .ignoresSafeArea(edges: .top)
#else
      .ignoresSafeArea(edges: [.top, .horizontal])
#endif
      // Tabs stay visible over the detail page for now (2026-08-09): the hide-on-enter
      // here plus the system's own tab-bar minimize timing was reading as "tabs fade in
      // and out in random places." Revisit properly later; until then, always-on beats
      // unpredictable. See `docs/archive/plans/detail-page-choreography.md`.
      // No navigation bar on this page, on either platform: the artwork runs to the
      // top edge and the title is already spelled out in 100pt over it. What stays is
      // the toolbar itself — Back and the overflow float over the picture.
#if os(iOS)
      .navigationBarTitleDisplayMode(.inline)
      .toolbarBackground(.hidden, for: .navigationBar)
//      .toolbarColorScheme(.dark, for: .navigationBar)
#endif
#if os(macOS)
      .toolbarBackground(.hidden, for: .windowToolbar)
      .toolbarColorScheme(.dark, for: .windowToolbar)
#endif
      .platformNavigationTitle("")
#if os(iOS) || os(macOS)
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          overflowMenu
        }
      }
#endif
      .task {
        itemModel.fetchData()
      }
      // Back from the player: the page never unmounted, so repaint the rail and the hero
      // from what the player just wrote locally. No-op until the payload has loaded.
      .onAppear {
        itemModel.repaintFromLocalProgress()
      }
      .task {
        relatedRowsMenu.bind(errorHandler: errorHandler)
        await relatedRowsMenu.refreshFolders()
      }
      .mediaCardNewFolderAlert(relatedRowsMenu)
      // Ambient muted trailer behind the hero:
      // - iPhone: off (short band, chrome on top — legibility / battery).
      // - tvOS: off for now (1C) — video without scrims looked broken; Trailer button
      //   still opens the real player. Revisit when the hero pass lands.
      // - macOS: on, unless `FeatureFlags.heroAmbientTrailerEnabled` says otherwise —
      //   the guard below is what keeps an off flag from building the player at all.
#if os(macOS)
      .task(id: itemModel.itemLoaded ? itemModel.mediaItem.trailerURL : nil) {
        guard FeatureFlags.heroAmbientTrailerEnabled,
              itemModel.itemLoaded,
              let url = itemModel.mediaItem.trailerURL else { return }
        try? await Task.sleep(for: .seconds(MediaItemHeroView.trailerLeadIn))
        guard !Task.isCancelled else { return }
        trailer.start(url: url)
      }
#endif
      // `trailer.setActive` lives on `MediaItemHeroView`'s own `onChange` — see
      // `MediaItemHeroPhase` — so this page never reads `heroPhase.isHeroOnScreen`.
      .onDisappear {
        trailer.stop()
      }
#if os(macOS)
      .onChange(of: playbackWindowState.request?.id) { _, requestID in
        guard requestID != nil else { return }
        trailer.stop()
      }
#endif
      .handleError(state: $errorHandler.state)
      .hudToast($itemModel.hudToast)
  }

#if os(iOS) || os(macOS)
  /// The page's secondary actions, in the one place a platform with a toolbar puts
  /// them. Same list the tvOS hero shows in its overflow circle.
  private var overflowMenu: some View {
    Menu {
      MediaItemOverflowMenu(isSeries: itemModel.mediaItem.isSeries,
                            isWatched: itemModel.isWatched,
                            isBookmarked: itemModel.isBookmarked,
                            onWatchedToggle: { itemModel.toggleWatched() },
                            onClearFromContinueWatching: { itemModel.clearFromContinueWatching() },
                            onBrowseWatchlist: { Self.openWatchlist(navigationState) })
    } label: {
      Label("More", systemImage: "ellipsis")
    }
    .disabled(!itemModel.itemLoaded)
  }
#endif

  @ViewBuilder
  private var details: some View {
    if itemModel.itemLoaded {
      scrollDetails
        .defaultFocus($focus, .play)
    } else {
      Color.clear
    }
  }

  /// One native vertical scroll: the hero, its artwork and the sections below are one
  /// view and focus graph, and the focus engine scrolls it. The only scroll this page
  /// asks for itself is back to the top whenever a hero control takes focus: the hero's
  /// controls sit at its bottom edge, and left alone the engine nudges the page just far
  /// enough to frame whichever one was focused (the same drift Plozz corrects the same
  /// way). Below the hero there is nothing to correct and nothing is written.
  ///
  /// The artwork is the hero's own `.background`, so it scrolls away with the hero. The
  /// page keeps no fold state, no scroll target behaviour and no pinned layer, which is
  /// what used to re-render every shelf on each hero↔section move.
  private var scrollDetails: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: MediaItemLayout.sectionSpacing) {
          MediaItemHeroView(mediaItem: itemModel.mediaItem,
                            focus: $focus,
                            trailer: trailer,
                            phase: heroPhase,
                            linkProvider: itemModel.linkProvider,
                            isWatched: itemModel.isWatched,
                            isBookmarked: itemModel.isBookmarked,
                            folders: itemModel.folders,
                            folderIDsContainingItem: itemModel.folderIDsContainingItem,
                            onWatchedToggle: { itemModel.toggleWatched() },
                            onSeasonWatchedToggle: { itemModel.toggleWatched(season: $0) },
                            onFolderToggle: { itemModel.toggleFolder($0) },
                            onCreateFolder: { itemModel.createFolderAndAdd(named: $0) },
                            onClearFromContinueWatching: { itemModel.clearFromContinueWatching() },
                            onBrowseWatchlist: { Self.openWatchlist(navigationState) },
                            isInWatchlist: itemModel.isInWatchlist,
                            onToggleWatchlist: { itemModel.toggleWatchlist() },
                            titleLogoURL: itemModel.externalMetadata.titleLogoURL,
                            ageRating: itemModel.externalMetadata.ageRating,
                            externalMetadataLoaded: itemModel.externalMetadataLoaded,
                            onFocusEntered: {
                              withAnimation(.easeInOut(duration: 0.4)) {
                                proxy.scrollTo(Self.heroAnchor, anchor: .top)
                              }
                            })
            .id(Self.heroAnchor)
#if os(tvOS)
            // Screen height minus a peek strip: the slice of the first section showing
            // under the hero at rest is what says there is more below.
            .containerRelativeFrame(.vertical, alignment: .topLeading) { length, _ in
              length * MediaItemLayout.heroFraction
            }
            // Apple's tvOS layout guidance: without a full-width focus section on the
            // header, Up from the right side of the shelves below can miss it or jump
            // to the tab bar, because the engine searches straight up.
            .frame(maxWidth: .infinity, alignment: .leading)
            .focusSection()
#endif

          contentSections
        }
        .padding(.bottom, MediaItemLayout.bottomPadding)
      }
      .coordinateSpace(name: MediaItemLayout.scrollSpace)
#if os(tvOS)
      // A focused card's lift and a focused button's scale are drawn outside their
      // frames; the page's own edges must not cut them.
      .scrollClipDisabled()
#endif
    }
  }

  private static let heroAnchor = "media-item-hero"

  /// Real seasons, or — under `FeatureFlags.fakeSeasonsOnMovies` — a fabricated one for
  /// titles that have none. **Temporary diagnostic, delete with the flag.**
  private var seasonsForDisplay: [Season]? {
    if let real = itemModel.mediaItem.seasons, !real.isEmpty { return real }
    guard FeatureFlags.fakeSeasonsOnMovies, itemModel.itemLoaded else { return nil }
    return Self.probeSeason(for: itemModel.mediaItem).map { [$0] }
  }

  /// One season of six unplayable episodes reusing the title's own artwork, so the rail
  /// renders at realistic size. **Temporary diagnostic, delete with the flag.**
  ///
  /// `EpisodeWatching` / `SeasonWatching` are `Codable` structs whose memberwise init is
  /// internal to `KinoPubBackend`, so they are decoded from literals here rather than
  /// widening those models' API for a throwaway probe.
  private static func probeSeason(for item: MediaItem) -> Season? {
    func decoded<T: Decodable>(_ json: String) -> T? {
      try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
    guard let seasonWatching: SeasonWatching = decoded(#"{"status":-1}"#) else { return nil }

    let still = item.posters.wideURL ?? item.posters.medium
    let episodes: [Episode] = (1...6).compactMap { number in
      // Two watched, one mid-progress, rest fresh — enough states to see the rail's chrome.
      let status = number <= 2 ? 1 : -1
      let time = number == 3 ? 600 : 0
      guard let watching: EpisodeWatching = decoded(#"{"status":\#(status),"time":\#(time)}"#)
      else { return nil }
      return Episode(id: item.id * 1000 + number,
                     title: "Probe episode \(number)",
                     thumbnail: still,
                     duration: 60 * 42,
                     tracks: 1,
                     number: number,
                     ac3: 0,
                     audios: [],
                     watched: number <= 2 ? 1 : 0,
                     watching: watching,
                     subtitles: [],
                     files: [])
    }
    guard !episodes.isEmpty else { return nil }
    return Season(id: item.id * 1000,
                  title: "Probe season",
                  number: 1,
                  watching: seasonWatching,
                  episodes: episodes)
  }

  @ViewBuilder
  private var contentSections: some View {
    VStack(alignment: .leading, spacing: MediaItemLayout.sectionSpacing) {
      // Versions of one film sit where a series' episodes would: directly under the hero,
      // because "what can I play right now" is the cheapest thing to reach on a remote.
      // Empty for everything with one video, which is almost every film.
      if !itemModel.mediaItem.playbackVariants.isEmpty {
        VersionsRailView(variants: itemModel.mediaItem.playbackVariants,
                         linkProvider: itemModel.linkProvider,
                         stillURL: itemModel.mediaItem.posters.wideURL ?? itemModel.mediaItem.posters.medium,
                         showsChrome: true)
      }

      if let seasons = seasonsForDisplay, !seasons.isEmpty {
        SeasonsRailView(seasons: seasons,
                        linkProvider: itemModel.linkProvider,
                        seriesTitle: itemModel.mediaItem.localizedTitle,
                        showsChrome: true,
                        onUnavailableSelected: { message in
                          itemModel.hudToast = HudToast(systemImage: "clock", title: message)
                        },
                        onHide: { episode, season in
                          itemModel.hide(episode: episode, season: season)
                        },
                        onToggleWatched: { episode, season in
                          itemModel.toggleWatched(episode: episode, season: season)
                        },
                        seasonSchedules: itemModel.seasonSchedules,
                        externalMetadata: itemModel.externalMetadata,
                        onSeasonVisible: { seasonNumber in
                          Task { await itemModel.ensureSeasonSchedule(seasonNumber) }
                        })
      }

      // The shipped ratings row, on every platform. It is the validated one; the
      // block experiment below runs beside it, not instead of it.
      MediaItemRatingsSection(mediaItem: itemModel.mediaItem,
                              externalMetadata: itemModel.externalMetadata,
                              likeCount: itemModel.likeCount,
                              dislikeCount: itemModel.dislikeCount,
                              showsHeader: true)
#if !os(tvOS)
      // Experiment: scores and opinions as one block section.
      MediaItemRatingsAndReviewsSection(mediaItem: itemModel.mediaItem,
                                        externalMetadata: itemModel.externalMetadata,
                                        summary: itemModel.externalMetadata.reviewsSummary,
                                        likeCount: itemModel.likeCount,
                                        dislikeCount: itemModel.dislikeCount,
                                        destination: ratingsAndReviewsDestination)
#endif
      MediaItemCommunityVoteSection(likeCount: itemModel.likeCount,
                                    dislikeCount: itemModel.dislikeCount,
                                    myVote: itemModel.myVote,
                                    onVote: { itemModel.vote(up: $0) })
        .detailFocusSection()
      MediaItemCastSection(mediaItem: itemModel.mediaItem,
                           linkProvider: itemModel.linkProvider,
                           externalMetadata: itemModel.externalMetadata)
        .detailFocusSection()
      MediaItemAwardsSection(awards: itemModel.externalMetadata.awards)
        .detailFocusSection()
      // Where to go next comes before the reading matter: the shelves are the page's
      // recommendations, and stills and trivia are the tail you reach only if you are
      // still here. Everything about *this* title (ratings and reviews, vote, cast,
      // awards) stays above them. Reviews used to be in this tail; they moved up into
      // the ratings block on the pointer platforms.
      MediaItemRelatedRowsSection(rows: itemModel.relatedRows,
                                  relatedItem: { itemModel.relatedItem(forCardID: $0) },
                                  linkProvider: itemModel.linkProvider,
                                  cardMenu: relatedRowsMenu,
                                  pendingShelves: itemModel.pendingRelatedShelfTitles)
        .detailFocusSection()
      MediaItemPhotosSection(stills: itemModel.externalMetadata.stills)
        .detailFocusSection()
#if !os(tvOS)
      MediaItemFactsSection(facts: itemModel.externalMetadata.facts)
      // Both variants are on the page while the block experiment runs: the merged
      // Ratings and Reviews block above, and the standalone Reviews section here,
      // where it shipped. Comparing them needs both visible; one of them goes with
      // this comment.
      MediaItemReviewsSection(reviews: itemModel.externalMetadata.reviews,
                              summary: itemModel.externalMetadata.reviewsSummary,
                              destination: ratingsAndReviewsDestination)
      // Same rail shape as Facts/Reviews, for the two things worth a glance before
      // the table below: what this release technically is, and whether it's OK for
      // the room. `InfoFooter` (Uploaded / Last Update / source credit), inside
      // `MediaItemInfoColumns`, is untouched.
      MediaItemBadgeCardsSection(mediaItem: itemModel.mediaItem,
                                externalMetadata: itemModel.externalMetadata)
#endif
      MediaItemInfoColumns(mediaItem: itemModel.mediaItem,
                           externalMetadata: itemModel.externalMetadata)
        .detailFocusSection()
    }
  }

  /// Always present. The block's header and every card in it lead to the same page,
  /// and that has to be true before the reviews arrive as well as after — a chevron
  /// that appears halfway through enrichment is a control the user watched grow.
  private var ratingsAndReviewsDestination: any Hashable {
    itemModel.linkProvider.ratingsAndReviews(
      RatingsAndReviews(item: itemModel.mediaItem,
                        metadata: itemModel.externalMetadata,
                        likeCount: itemModel.likeCount,
                        dislikeCount: itemModel.dislikeCount)
    )
  }

  /// tvOS: the plain page. The artwork belongs to the hero and scrolls away with it,
  /// so everything below the hero sits on the app background. iOS / macOS keep the
  /// optional blurred-poster wash behind the whole page.
  @ViewBuilder
  private var pageBackground: some View {
#if os(tvOS)
    genericBackground
#else
    if FeatureFlags.detailAmbientBackdropEnabled {
      ambientBackground
    } else {
      genericBackground
    }
#endif
  }

  /// What the page sits on with `detailAmbientBackdropEnabled` off: the app background
  /// and nothing else — no still, no blur buffer, nothing decoded for it.
  private var genericBackground: some View {
    Color.KinoPub.background
#if os(macOS)
      // Same reason as `ambientBackground`: ignoring horizontally paints under the
      // sidebar and makes every rail look clipped.
      .ignoresSafeArea(edges: .top)
#else
      .ignoresSafeArea()
#endif
  }

  private var ambientBackground: some View {
    ZStack {
      Color.KinoPub.background
/// TODO IT MUST BE SAME IDENTICAL PICTURE - WIDE ONE. TVOS, IOS, MACOS, etc
      CachedRemoteImage(url: URL(string: itemModel.mediaItem.posters.medium), contentMode: .fill)
        .frame(width: Self.ambientBuffer.width, height: Self.ambientBuffer.height)
        .clipped()
        .blur(radius: Self.ambientBlur, opaque: true)
        .saturation(1.6)
        .drawingGroup()
        .scaleEffect(Self.ambientScale)
        .opacity(0.55)

      Color.KinoPub.background.opacity(0.55)
    }
    .clipped()
#if os(macOS)
    // Horizontal ignore paints the wash under the sidebar and makes every rail
    // look clipped; keep the bleed on tvOS/iOS only.
    .ignoresSafeArea(edges: .top)
#else
    .ignoresSafeArea()
#endif
  }

  private static let ambientBuffer = CGSize(width: 160, height: 90)
  private static let ambientBlur: CGFloat = 10
  private static let ambientScale: CGFloat = 14

  private static func openWatchlist(_ navigationState: NavigationState) {
#if os(macOS)
    navigationState.selectedTab = .watchlist
#else
    navigationState.selectedTab = .library
#endif
  }
}

extension View {
  /// One focus section per detail-page content section, so Up/Down travels
  /// section-to-section instead of creeping element-by-element, and a section holds
  /// focus internally while you move across it. The hero is the same shape one level up.
  ///
  /// Only applied to sections that do not already declare their own: the ratings row
  /// and `SeasonsRailView` build theirs internally, and nesting would fight them.
  @ViewBuilder
  func detailFocusSection() -> some View {
#if os(tvOS)
    focusSection()
#else
    self
#endif
  }
}

struct MediaItemView_Previews: PreviewProvider {
  struct Preview: View {
    var body: some View {
      MediaItemView(model: MediaItemModel(mediaItemId: MediaItem.mock().id,
                                          itemsService: VideoContentServiceMock(),
                                          downloadManager: DownloadManager<DownloadMeta>(fileSaver: FileSaver(),
                                                                                      database: DownloadedFilesDatabase<DownloadMeta>(fileSaver: FileSaver())),
                                          linkProvider: AppRoutesLinkProvider(),
                                          errorHandler: ErrorHandler()))
    }
  }
  static var previews: some View {
    NavigationStack {
      Preview()
    }
  }
}
