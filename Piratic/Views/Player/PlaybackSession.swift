//
//  PlaybackSession.swift
//  Piratic
//
//  App-scoped playback coordinator: one AVPlayer/session for the whole app.
//

import Foundation
import SwiftUI
import Combine
import AVFoundation
import KinoPubBackend
import PiraticKit

/// Owns the single active `PlayerManager`. Navigation destinations and the macOS
/// player window host this session instead of constructing independent managers.
@MainActor
final class PlaybackSession: ObservableObject {
  static let shared = PlaybackSession()

  /// One playback request. The token is the identity of the *route instance* that
  /// started it (minted where the route value is created); callers with no route —
  /// the macOS player window, an accepted Up Next — pass nil and match by item alone.
  struct Request: Hashable {
    let itemID: Int
    let mode: WatchMode
    let token: UUID?

    /// Live-request matching: a tokenless caller addresses whatever is playing by
    /// item; a routed caller matches only its own route instance.
    func matches(_ other: Request) -> Bool {
      itemID == other.itemID && mode == other.mode
        && (token == nil || other.token == nil || token == other.token)
    }
  }

  @Published private(set) var request: Request?
  @Published private(set) var manager: PlayerManager?

  /// Always-current session identity. `@Published` `manager` / `request` catch up on
  /// the next main-actor turn so a SwiftUI view body that calls `play`
  /// (`RouteDestination.systemPlayer`) does not publish during an update.
  private var activeRequest: Request?
  private var activeManager: PlayerManager?

  /// Live manager even before the `@Published` mirror updates. Prefer this for
  /// "is something playing?" checks that must not wait a turn.
  var currentManager: PlayerManager? { activeManager }

  /// Requests whose playback has ended, by strict identity (token included). A
  /// navigation destination is re-evaluated while its route is leaving, and creating
  /// a manager there is what re-armed a dismissed stream — the "player reopens
  /// forever" loop. A tombstoned request instead hands the dying view an inert
  /// manager: `preparePlayback` on it is a no-op and its player has no item. A legit
  /// replay never collides — a fresh push mints a fresh token.
  private var tombstonedRequests: Set<Request> = []
  /// Insertion order for `tombstonedRequests` so repeated Play / dismiss cycles cannot
  /// retain an unbounded set of route identities across a long Mac session.
  private var tombstoneOrder: [Request] = []
  private static let maxTombstones = 24
  /// The most recently torn-down manager, kept so a dying destination has something
  /// inert to hold. Which dead manager it is doesn't matter — the view is leaving.
  private var stoppedManager: PlayerManager?
  /// Routes that asked to start from the beginning (`startFromBeginning`), by token.
  private var fromBeginningTokens: Set<UUID> = []

  private init() {}

  private func rememberTombstone(_ request: Request) {
    if tombstonedRequests.insert(request).inserted {
      tombstoneOrder.append(request)
    }
    while tombstoneOrder.count > Self.maxTombstones {
      let oldest = tombstoneOrder.removeFirst()
      tombstonedRequests.remove(oldest)
    }
  }

  /// Installs the live identity immediately, then mirrors into `@Published` off the
  /// current view-update turn.
  private func setActive(manager: PlayerManager?, request: Request?) {
    activeManager = manager
    activeRequest = request
    Task { @MainActor [weak self] in
      guard let self else { return }
      // A later `play` / `stop` may have won before this turn ran.
      guard self.activeManager === manager, self.activeRequest == request else { return }
      if self.manager !== manager { self.manager = manager }
      if self.request != request { self.request = request }
    }
  }

  /// Returns the shared manager for `item`, replacing the previous request when the
  /// id/mode changes so only one stream runs at a time.
  @discardableResult
  func play(
    item: any PlayableItem,
    mode: WatchMode,
    token: UUID? = nil,
    downloadedFilesDatabase: DownloadedFilesDatabase<DownloadMeta>,
    actionsService: UserActionsService
  ) -> PlayerManager {
    let next = Request(itemID: item.id, mode: mode, token: token)
    if let activeManager, let activeRequest, activeRequest.matches(next) {
      return activeManager
    }
    if tombstonedRequests.contains(next), let stoppedManager {
      return stoppedManager
    }

    if let activeRequest {
      rememberTombstone(activeRequest)
      stoppedManager = activeManager
    }
    let profile = Self.trackProfile(for: item)
    let plan = PlaybackPreflight.shared.plan(for: item, profile: profile)
    // macOS window (and other tokenless) swaps: retarget the live manager so the picture
    // stays up until the next item replaces it — tearing down to nil first was the wipe
    // between concert parts (KP-35). Routed plays keep minting a fresh manager.
    if let activeManager, token == nil {
      if let media = item as? MediaItem {
        AppContext.shared.localProgressStore.cacheItem(media)
      }
      activeManager.retarget(playItem: item, watchMode: mode, trackProfile: profile, plan: plan)
      setActive(manager: activeManager, request: next)
      return activeManager
    }
    // The outgoing manager is torn down on the next turn: a route's destination builder
    // calls `play` from a view body, and the teardown publishes on the old manager
    // («Publishing changes from within view updates»). It is a different object from the
    // one returned, so nothing about the new stream waits on it.
    if let outgoing = activeManager {
      Task { @MainActor in outgoing.tearDownForReplacement() }
    }
    if let media = item as? MediaItem {
      AppContext.shared.localProgressStore.cacheItem(media)
    }
    // The plan is made here rather than inside the player so the hand-off is the thing
    // that travels: whatever a card or a Play button already said about this title is what
    // the player starts from, and the player refines it once it sees the real renditions.
    let created = PlayerManager(
      playItem: item,
      watchMode: mode,
      downloadedFilesDatabase: downloadedFilesDatabase,
      actionsService: actionsService,
      trackProfile: profile,
      plan: plan
    )
    if let token, fromBeginningTokens.remove(token) != nil {
      created.startsFromBeginning = true
    }
    setActive(manager: created, request: next)
    return created
  }

  /// The player route pushed with this token opens at zero, not at the resume point —
  /// Play's «Начать сначала». Called just before the push that mints the token.
  func startFromBeginning(token: UUID) {
    fromBeginningTokens.insert(token)
  }

  /// Anime-ness and the original language, for track selection.
  ///
  /// Both come off the **item** payload, which an `Episode` is not: it carries no genres
  /// and no countries. The series snapshot the user browsed to get here does, so that is
  /// what is read — and when there is none, the resolver simply falls back to the ladder.
  private static func trackProfile(for item: any PlayableItem) -> TitleTrackProfile {
    let snapshot = (item as? MediaItem)
      ?? AppContext.shared.localProgressStore.snapshot(for: item.metadata.id)
    guard let snapshot else { return TitleTrackProfile() }
    let languages = item.audioTracks.map(\.lang) + item.subtitles.map(\.lang)
    let presentation = MediaPresentationProfile(type: snapshot.type, genres: snapshot.genres)
    return TitleTrackProfile.infer(presentation: presentation,
                                   countries: snapshot.countries.map(\.title),
                                   trackLanguages: languages)
  }

  /// Picture in Picture back to full screen: the route pushed for it carries a new token, and
  /// must find `manager` — the stream in the floating window — rather than start the film
  /// again. False when the session has moved on to something else.
  @discardableResult
  func adopt(_ manager: PlayerManager, token: UUID) -> Bool {
    guard activeManager === manager, let activeRequest else { return false }
    setActive(manager: manager,
              request: Request(itemID: activeRequest.itemID, mode: activeRequest.mode, token: token))
    return true
  }

  func clear() {
    activeManager?.tearDownForReplacement()
    setActive(manager: nil, request: nil)
  }

  /// **Leaving the player ends the stream.** Called when the player surface goes away —
  /// Menu on tvOS, Done on iOS, closing the window on macOS — because nothing else does
  /// it: the session outlives the screen by design, so without this the `AVPlayer` kept
  /// running with no picture and the film played on in the background.
  ///
  /// Takes the manager the screen was showing rather than clearing blindly: a route can
  /// tear down after the next film has already claimed the session — swapping films in the
  /// open macOS window does exactly that — and that one must keep playing. `false` says so:
  /// this screen's stream is over, but the session belongs to something else now.
  @discardableResult
  func stop(_ manager: PlayerManager) -> Bool {
    manager.tearDownForReplacement()
    guard activeManager === manager else { return false }
    if let activeRequest {
      rememberTombstone(activeRequest)
    }
    stoppedManager = manager
    setActive(manager: nil, request: nil)
    return true
  }
}
