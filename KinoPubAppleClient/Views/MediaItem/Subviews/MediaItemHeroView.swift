//
//  MediaItemHeroView.swift
//  KinoPubAppleClient
//

import SwiftUI
import AVKit
import AVFoundation
import Combine
import KinoPubUI
import KinoPubBackend
import KinoPubMedia
import KinoPubMetadata

/// Loads the trailer alongside the artwork and reports when it is actually ready to
/// show, so the hero only swaps once there is something to swap to.
@MainActor
final class TrailerPreviewModel: ObservableObject {

  @Published private(set) var player: AVPlayer?
  @Published private(set) var isReady: Bool = false

  private var statusObservation: NSKeyValueObservation?
  // `deinit` is nonisolated; the token is only removed, never read as shared state.
  nonisolated(unsafe) private var endObserver: Any?
  private var startedURL: URL?
  /// False while the hero is scrolled off screen. Playback is gated on it rather than
  /// started unconditionally, so a trailer that becomes ready after the page has been
  /// scrolled past never starts decoding in the first place.
  private var isActive = true
  /// True while the page is off screen (another section, a page pushed over it). The
  /// player is kept, paused, so coming back resumes it rather than starting over.
  private var isSuspended = false
  private var canPlay: Bool { isActive && !isSuspended }

  /// Plays the trailer muted behind the artwork. A repeat call for the URL already
  /// running is ignored, so a re-rendered hero doesn't restart it from the top.
  func start(url: URL) {
    guard startedURL != url else { return }
    teardown()
    startedURL = url

    let item = AVPlayerItem(url: url)
    let player = AVPlayer(playerItem: item)
    player.isMuted = true
    // Nothing here is worth keeping the screen awake for — the real player is.
    player.preventsDisplaySleepDuringVideoPlayback = false
    // The artwork comes back at the end rather than the trailer looping.
    player.actionAtItemEnd = .pause
    self.player = player

    // Observed on the item: `\.currentItem?.status` through the player is a key path
    // through an optional and does not reliably deliver.
    statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
      let status = item.status
      Task { @MainActor in
        self?.handle(status: status)
      }
    }

    endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                        object: item,
                                                        queue: .main) { [weak self] _ in
      Task { @MainActor in
        self?.teardown()
      }
    }
  }

  /// Pauses rather than tears down when the hero scrolls away: the player stays
  /// warm so scrolling back up resumes mid-trailer, while the backdrop hides the
  /// layer and shows a blurred still. Stopping the decode is what keeps the seasons
  /// rail from stuttering under a live `AVPlayerLayer`.
  func setActive(_ active: Bool) {
    guard isActive != active else { return }
    isActive = active

    guard let player else { return }
    if active {
      if isReady, canPlay { player.play() }
    } else {
      player.pause()
    }
  }

  private func handle(status: AVPlayerItem.Status) {
    switch status {
    case .readyToPlay:
      isReady = true
      if canPlay { player?.play() }
    case .failed:
      // A trailer that won't load just leaves the artwork in place.
      teardown()
    default:
      break
    }
  }

  /// Hands the preview over to the full-screen presentation and back. It is the same
  /// `AVPlayer` either way — that is the whole point of the gesture, the trailer keeps
  /// running rather than starting over — so all that changes is the sound and whether
  /// it is worth keeping the screen awake for.
  func setFullScreen(_ fullScreen: Bool) {
    guard let player else { return }
    player.isMuted = !fullScreen
    player.preventsDisplaySleepDuringVideoPlayback = fullScreen
    if fullScreen, isActive, isReady {
      player.play()
    }
  }

  /// The page left the screen / came back. Unlike `stop`, the trailer resumes where it
  /// was: the page kept in its section (`MediaItemModelCache`) comes back as it was.
  func setSuspended(_ suspended: Bool) {
    guard isSuspended != suspended else { return }
    isSuspended = suspended
    guard let player else { return }
    if suspended {
      player.pause()
    } else if isReady, canPlay {
      player.play()
    }
  }

  /// Drops back to the artwork and forgets what was playing: the real player took over.
  func stop() {
    teardown()
    startedURL = nil
  }

  private func teardown() {
    player?.pause()
    isReady = false
    statusObservation?.invalidate()
    statusObservation = nil
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
      self.endObserver = nil
    }
    player = nil
  }

  deinit {
    if let endObserver {
      NotificationCenter.default.removeObserver(endObserver)
    }
    statusObservation?.invalidate()
  }
}

/// The trailer as a bare `AVPlayerLayer`. `VideoPlayer` brings the transport UI and
/// its own focus behaviour along, and fits the video inside the frame — behind a
/// title it has to fill the hero and stay out of the way instead.
struct TrailerVideoLayer {
  let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspectFill
}

#if os(macOS)
extension TrailerVideoLayer: NSViewRepresentable {
  func makeNSView(context: Context) -> TrailerLayerHostView {
    TrailerLayerHostView(player: player, gravity: gravity)
  }

  func updateNSView(_ view: TrailerLayerHostView, context: Context) {
    view.playerLayer.player = player
    view.playerLayer.videoGravity = gravity
  }
}

/// The `AVPlayerLayer` *is* the view's backing layer — the AppKit twin of the
/// `layerClass` override the UIKit side uses.
///
/// It used to be a sublayer of a plain `CALayer`, with `layout()` copying `bounds`
/// onto it by hand. Assigning `layer` after `wantsLayer` leaves the view host-backed
/// rather than layer-backed, so that `layout()` did not reliably fire on resize and
/// the video kept whatever frame it was first given — which is why aspect-fill looked
/// like it was fitting: the layer was simply the wrong size for the hero. A backing
/// layer tracks bounds itself, and there is nothing left to keep in sync.
final class TrailerLayerHostView: NSView {

  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

  override func makeBackingLayer() -> CALayer {
    AVPlayerLayer()
  }

  init(player: AVPlayer, gravity: AVLayerVideoGravity) {
    super.init(frame: .zero)
    wantsLayer = true
    // Without this the layer animates its way to every new size as the window resizes.
    layerContentsRedrawPolicy = .duringViewResize
    playerLayer.player = player
    playerLayer.videoGravity = gravity
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
#else
extension TrailerVideoLayer: UIViewRepresentable {
  func makeUIView(context: Context) -> TrailerLayerHostView {
    TrailerLayerHostView(player: player, gravity: gravity)
  }

  func updateUIView(_ view: TrailerLayerHostView, context: Context) {
    view.playerLayer.player = player
    view.playerLayer.videoGravity = gravity
  }
}

final class TrailerLayerHostView: UIView {

  override class var layerClass: AnyClass { AVPlayerLayer.self }

  var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

  init(player: AVPlayer, gravity: AVLayerVideoGravity) {
    super.init(frame: .zero)
    playerLayer.player = player
    playerLayer.videoGravity = gravity
    isUserInteractionEnabled = false
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}
#endif


/// The item page's secondary actions, as menu content. Shared so the same list can be
/// a circle in the hero row (tvOS) or a toolbar item (iPhone / Mac) without either
/// copy drifting from the other.
struct MediaItemOverflowMenu: View {

  var isSeries: Bool
  var isWatched: Bool
  var isBookmarked: Bool
  var onWatchedToggle: () -> Void
  var onClearFromContinueWatching: () -> Void
  var onBrowseWatchlist: (() -> Void)?

  var body: some View {
    Button(action: onClearFromContinueWatching) {
      Label("Remove from Recently Watched", systemImage: "trash")
    }

    if isWatched {
      Button(action: onWatchedToggle) {
        Label("Mark as New", systemImage: "eye")
      }
    }

    if isSeries, isBookmarked, let onBrowseWatchlist {
      Button(action: onBrowseWatchlist) {
        Label("Browse My Watchlist", systemImage: "rectangle.grid.3x2")
      }
    }
  }
}

/// Full-bleed artwork that gives way to the trailer, with the title, metadata and
/// actions laid over it — the shape the Apple TV app uses. On iPhone the picture keeps
/// its own 16:9 band and the chrome sits under it instead.
struct MediaItemHeroView: View {

  var mediaItem: MediaItem
  /// The page's focus target — the primary action claims it, so a page whose content
  /// lands late still opens at the top rather than wherever the focus engine drifted.
  @FocusState.Binding var focus: MediaItemFocusTarget?
  /// Owned by the page so the same player plays behind the artwork and in the hero's
  /// Up-to-fullscreen gesture.
  @ObservedObject var trailer: TrailerPreviewModel
  /// iOS / macOS: pauses the ambient trailer once the hero has scrolled away. The hero
  /// never leaves the hierarchy on scroll, so this is measured rather than
  /// `onDisappear`. Read and written only inside this view. See `MediaItemHeroPhase`.
  var phase: MediaItemHeroPhase
  var linkProvider: NavigationLinkProvider
  var isWatched: Bool
  var isBookmarked: Bool
  var folders: [Bookmark]
  var folderIDsContainingItem: Set<Int>
  var onWatchedToggle: () -> Void
  /// Bulk form of the above: marks every episode of the season the primary button is
  /// pointing at. Nil collapses the checkmark back to a plain single-episode toggle.
  var onSeasonWatchedToggle: ((Season) -> Void)? = nil
  var onFolderToggle: (Bookmark) -> Void
  var onCreateFolder: ((String) -> Void)? = nil
  var onClearFromContinueWatching: () -> Void = {}
  /// Opens the Saved / watchlist tab — same destination as the CW long-press action.
  var onBrowseWatchlist: (() -> Void)? = nil
  /// Series watchlist toggle for the shared context menu (not the hero checkmark).
  var isInWatchlist: Bool = false
  var onToggleWatchlist: (() -> Void)? = nil
  /// When the next episode of the season kino.pub is on comes out — ahead, or aired and
  /// not uploaded yet (`MediaItemModel.awaitedEpisodeAirDate`). Drives Follow-as-primary.
  var awaitedEpisodeAirDate: Date? = nil
  /// TMDB's name and overview of the episode Play opens (`MediaItemModel.primaryEpisodeSchedule`).
  var primaryEpisodeSchedule: EpisodeSchedule? = nil
  /// `Season.id` → the number the chips show, once the episode grid has aligned.
  /// The play button uses it so it cannot say «11 сезон» while the row has no 11.
  var seasonLabels: [Int: Int] = [:]
  /// Download phase for the current playable; `nil` hides the control (flag off / TV).
  var downloadPhase: MediaActionDownloadPhase? = nil
  var onDownload: (() -> Void)? = nil
  var onPauseDownload: (() -> Void)? = nil
  var onDeleteDownload: (() -> Void)? = nil
  var onDownloadSeason: ((Season) -> Void)? = nil
  var onDownloadUnwatchedInSeason: ((Season) -> Void)? = nil
  var onDownloadAllEpisodes: (() -> Void)? = nil
  var onMarkUnwatchedInSeason: ((Season) -> Void)? = nil
  var onMarkAllEpisodesWatched: (() -> Void)? = nil
  /// TMDB / Kinopoisk title logo when enrichment supplied one.
  var titleLogoURL: URL? = nil
  /// Which logo language the image route asked for (worker `lang` or default ru-first).
  var titleLogoRequestKind: TitleLogoRequestKind = .russianPreferred
  /// International / original title for the subtitle line (`heroTitlePartnerLine`).
  var titlePartnerLine: String? = nil
  /// Clean textless TMDB backdrop when enrichment supplied one.
  var preferredBackdropURL: URL? = nil
  /// Changes when this title's local picture cache is dropped, so the logo and
  /// backdrop load again instead of keeping the image they already decoded.
  var localCacheEpoch: Int = 0
  /// Certification from enrichment ("TV-14", "16+"). Rendered as one more capability
  /// chip in the metadata row — the item payload has no rating of its own.
  var ageRating: String? = nil
  /// TMDB's answer — air dates and status for the synopsis popup's facts line.
  var externalMetadata: TitleMetadata = TitleMetadata()
  /// False until external metadata settles. While false, the title slot stays empty
  /// (a logo is expected). Defaults to `false` so a missed flag cannot paint the
  /// lettered title and then swap it for a logo. Previews that want the name pass
  /// `true`. Text appears only after a confirmed miss.
  var externalMetadataLoaded: Bool = false
  /// «+ ещё N»: the page moves focus into the versions rail.
  var onShowMoreVersions: (() -> Void)? = nil
  /// tvOS: called whenever one of the hero's own controls takes focus, including moves
  /// between them. The page scrolls back to the top with it.
  var onFocusEntered: (() -> Void)? = nil
  /// Warm `BookmarkFoldersStore` once so a cold install is not an empty bookmark menu.
  var ensureBookmarkFoldersLoaded: (() async -> Void)? = nil
  /// TMDB proxy `/admin` panel — circle before ⋯ when a token is configured.
  /// Change Images and the worker's maintenance actions, in More; `nil` for a viewer.
  var imageAdmin: TitleImageAdminActions? = nil

  /// tvOS only: the Up gesture lifts the muted inline preview into a real full-screen
  /// player. Kept here so the same view that owns the preview owns its promotion.
  @State private var isTrailerFullScreen = false
#if !os(tvOS)
  /// The band's size, for the corner poster and the column the title leaves it.
  @State private var heroBandSize: CGSize = .zero
#endif
  @State private var showNewFolderAlert = false
  @State private var newFolderName = ""
  /// Actions currently showing a spinner (Mark Watched, Follow, …). Cleared when the
  /// underlying flag flips, or by the control itself once the tap returns.
  @State private var loadingActions: Set<MediaActionID> = []
  /// What became of the backdrop candidates, keyed by them: the hero is a picture hero
  /// once one has loaded, whether or not kino.pub sent a `wide` (the worker often has a
  /// backdrop when it did not), and a poster hero once all have failed. Kept in `phase`
  /// (the page's model), so a page rebuilt on coming back shows the same hero.
  private var backdropOutcome: (key: String, loaded: Bool)? {
    get { phase.backdropOutcome }
    nonmutating set { phase.backdropOutcome = newValue }
  }
  /// What the shared title slot is drawing — subtitle waits until this is not `.empty`.
  private var titleLogoMark: TitleLogoMark {
    get { phase.titleLogoMark }
    nonmutating set { phase.titleLogoMark = newValue }
  }
  private var deliveredLogoLanguage: WorkerArtworkLanguageTag? {
    get { phase.deliveredLogoLanguage }
    nonmutating set { phase.deliveredLogoLanguage = newValue }
  }
  /// The version play control that last held focus — its runtime stays in the metadata
  /// row once focus moves on (`runtimeVersion`).
  @State private var lastFocusedVersionID: Int?
#if os(tvOS)
  /// Once Play (or Follow-primary) has held focus, the synopsis joins the focus
  /// chain. Until then it stays a plain paragraph so it cannot steal entry focus
  /// and blink Play when `.task` corrects it.
  @State private var actionEntryClaimed = false
  /// The page is covered — the player, or another pushed page — so the next `onAppear`
  /// is a return rather than the first appearance.
  @State private var isCovered = false
  /// The page went away while (or right after) a control that opens the player held
  /// focus. On the way back focus goes to the entry control, whatever the row turned
  /// into meanwhile — see `claimEntryAfterReturn`.
  @State private var returnsFromPlayer = false
  /// When focus last left a control of the row, and whether that control opens the
  /// player. Read within a fraction of a second, to tell "the row changed under the
  /// focused control" and "the player took focus" from a move down the page.
  @State private var focusLeftRowAt: Date?
  @State private var focusLeftPlayerControlAt: Date?
  /// Focus is in the sections below, not in the hero: the app's backdrop puts the
  /// material over the picture (`pageBackdropDetails`).
  @State private var inDetails = false
  @Environment(\.pageBackdropStage) private var backdropStage
  @Environment(\.colorScheme) private var systemColorScheme

  /// Dark only while a picture is actually behind the text. In the details the picture
  /// fades out, and a title with no picture at all (portrait poster in the corner, or a
  /// backdrop that never loaded) never had one: both sit on the system background, so
  /// the text follows the appearance — white on light grey was the bug (Sasha,
  /// 2026-10-25). While the picture is still loading, a catalogue `wide` is the guess.
  private var heroChromeColorScheme: ColorScheme {
    guard !inDetails else { return systemColorScheme }
    let key = Route.backdropKey(itemID: mediaItem.id)
    let onPicture = backdropStage?.hasPicture(for: key) ?? mediaItem.posters.hasSpecifiedWide
    return onPicture ? .dark : systemColorScheme
  }
#endif
  private var isSeries: Bool {
    !(mediaItem.seasons?.isEmpty ?? true)
  }

  /// Films and series both get the checkmark, in progress or not started. It only
  /// disappears once there is nothing left to mark — a finished title reverses through
  /// Mark as New in More instead.
  private var showsWatchedButton: Bool {
    !isWatched
  }

  var body: some View {
    platformBody
#if !os(tvOS)
      // The window toolbar goes dark over a picture too — the page reads it from here.
      .onChange(of: hasArtBackdrop, initial: true) { _, picture in
        phase.showsPicture = picture
      }
#endif
      // The hero is the only reader of `phase`, so the write lands here alone and the
      // page's body never re-runs for it.
      .onChange(of: phase.isHeroOnScreen) { _, onScreen in
        trailer.setActive(onScreen)
      }
#if os(tvOS)
      // `focus` is non-nil exactly while a hero control holds focus. Read here rather
      // than on the page, so a focus move re-renders the hero and nothing else.
      .onChange(of: focus) { old, target in
        noteFocusLeavingRow(from: old, to: target)
        if let target, let id = Self.actionID(forPlay: target), let version = choice(for: id) {
          lastFocusedVersionID = version.id
        }
        guard let target else {
          // The synopsis has only the action row below it, so focus leaving it never
          // means the details: it is the synopsis popup, which is not a presented
          // controller and slips past the overlay probe — the picture faded and the
          // text flipped scheme behind it (Sasha, 2026-10-25).
          if old != .plot { noteFocusLeftHero() }
          return
        }
        // «+ ещё N» sent focus to the versions rail: that is the details, not the hero.
        guard target != .versionsRail else {
          inDetails = true
          return
        }
        inDetails = false
        onFocusEntered?()
        if target == actionEntryTarget {
          returnsFromPlayer = false
        }
        if target.isActionControl, !actionEntryClaimed {
          // Defer unlocking the synopsis until after Play has settled — swapping
          // the paragraph for a Button in the same turn can steal entry focus back.
          Task { @MainActor in
            actionEntryClaimed = true
          }
        }
      }
      // Claim Play (or Follow-primary) as early as the hero appears. The synopsis
      // stays out of the chain until this lands (`allowsFocus`), so we do not
      // briefly paint plot-focused and then jump — that was the entry blink.
      .onAppear {
        if isCovered {
          isCovered = false
          claimEntryAfterReturn()
        }
        claimActionEntryFocus()
      }
      .onDisappear {
        isCovered = true
        if let current = focus, current.opensPlayer {
          returnsFromPlayer = true
        } else if let left = focusLeftPlayerControlAt, Date().timeIntervalSince(left) < 2 {
          returnsFromPlayer = true
        }
      }
      .task {
        claimActionEntryFocus()
      }
      // Follow became the main button (TMDB answered after the page opened, or the last
      // episode was just watched) while focus still sat on the old one: move with it.
      .onChange(of: actionEntryTarget) { old, new in
        guard focus == old || focus == nil else { return }
        moveEntryFocus(from: old, to: new)
      }
      // A row change can take the focused control with it: Play turning into Replay is
      // a different button style, so SwiftUI builds a new control and the focused one
      // is gone. tvOS then has nothing focused at all (Sasha, 2026-10-03, after
      // watching the last episodes). Hand focus to the entry control instead.
      .onChange(of: actionRowSignature) { _, _ in
        actionRowChanged()
      }
      .pageBackdropDetails(inDetails, key: Route.backdropKey(itemID: mediaItem.id))
#endif
  }

#if os(tvOS)
  /// Entry control for the action row: Follow when promote-Follow leads, else Play
  /// (whatever it reads — Replay included).
  private var actionEntryTarget: MediaItemFocusTarget {
    .entry(promotesFollow: actionContext.promoteFollow)
  }

  /// Ids and chrome, in order — what decides whether a control survives an update.
  private var actionRowSignature: [String] {
    actionAppearances.map { "\($0.id.rawValue):\($0.chrome)" }
  }

  private func claimActionEntryFocus() {
    if focus == nil || focus == .plot {
      focus = actionEntryTarget
    }
  }

  private func claim(_ target: MediaItemFocusTarget, reason: String) {
    FocusLog.moved(section: "hero", element: "claim \(target) — \(reason)", focused: true)
    focus = target
  }

  /// Focus left the hero. It is the details only once something below has it and the
  /// page is still in front — not when the player or another page took it, not in
  /// the instant nothing is focused while a control is rebuilt, and not while a
  /// menu, alert or cover holds focus. Those take `@FocusState` off the row without
  /// moving into the sections, and treating them as the details faded the picture
  /// out from behind the menu (Sasha, 2026-10-25).
  private func noteFocusLeftHero() {
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(120))
      guard focus == nil, !isCovered, !TVFocusProbe.nothingFocused else { return }
      guard !TVFocusProbe.focusedItemIsOverlay else { return }
      inDetails = true
    }
  }

  private func noteFocusLeavingRow(from old: MediaItemFocusTarget?, to new: MediaItemFocusTarget?) {
    guard new == nil, let old, old.isActionControl else { return }
    focusLeftRowAt = Date()
    if old.opensPlayer {
      focusLeftPlayerControlAt = Date()
      // The page can be covered before focus lets go of the control.
      if isCovered { returnsFromPlayer = true }
    }
  }

  /// Back on the page. From the player opened by a hero control, focus goes to the entry
  /// control — Follow when it leads, else Play / Replay — even where tvOS would restore
  /// the control that opened the player, or nothing at all because that control was
  /// rebuilt. From anywhere else the system's restoration stands, unless it restored
  /// nothing. Retried for a moment: the row repaints from the player's progress on the
  /// same appearance, and a control mid-transition does not take focus.
  private func claimEntryAfterReturn() {
    Task { @MainActor in
      for delay in [0, 150, 250, 400, 500] {
        try? await Task.sleep(for: .milliseconds(delay))
        guard !isCovered else { return }
        let target = actionEntryTarget
        if focus == target {
          returnsFromPlayer = false
          return
        }
        if returnsFromPlayer {
          if focus == nil || focus == .plot || focus?.isActionControl == true {
            claim(target, reason: "back from the player")
          }
        } else if focus == nil, TVFocusProbe.nothingFocused {
          claim(target, reason: "back with nothing focused")
        }
      }
      returnsFromPlayer = false
    }
  }

  /// The main control changed — Follow promoted once TMDB dated the next episode, or
  /// after the last episode was watched — while focus sat on the old one (or nowhere).
  /// Retried until it lands: Follow arrives with an insertion transition, and a control
  /// mid-transition does not take focus, so the first claim can come to nothing (on
  /// opening, focus stayed on Replay beside a promoted Follow). Stops as soon as focus
  /// is somewhere the viewer put it.
  private func moveEntryFocus(from old: MediaItemFocusTarget, to new: MediaItemFocusTarget) {
    Task { @MainActor in
      for delay in [0, 80, 120, 150, 200, 250, 400] {
        try? await Task.sleep(for: .milliseconds(delay))
        guard !isCovered, actionEntryTarget == new, focus != new else { return }
        if focus == old || (focus == nil && TVFocusProbe.nothingFocused) {
          claim(new, reason: "entry control changed \(old) → \(new)")
        } else if focus != nil {
          return
        }
      }
    }
  }

  private func actionRowChanged() {
    let heldFocus = focus?.isActionControl == true
      || focusLeftRowAt.map { Date().timeIntervalSince($0) < 0.5 } == true
    guard heldFocus, !isCovered else { return }
    Task { @MainActor in
      // Until focus lands: a control still running its insertion transition does not
      // take it, so one claim can come to nothing.
      for delay in [80, 120, 150, 200, 250, 400] {
        try? await Task.sleep(for: .milliseconds(delay))
        guard !isCovered, focus == nil else { return }
        if TVFocusProbe.nothingFocused {
          claim(actionEntryTarget, reason: "row changed under the focused control")
        }
      }
    }
  }
#endif

  @ViewBuilder
  private var platformBody: some View {
    Group {
#if os(tvOS)
      // The page gives the hero its height (`MediaItemLayout.heroFraction` of the screen)
      // and the chrome sits at its bottom edge. The hero draws no picture: the artwork and
      // its scrim are the navigation stack's backdrop, behind the scroll (`MediaItemView`
      // claims it), so the hero's text scrolls away over a picture that stays.
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) { cornerPosterAccent }
        .clipped()
        // The same muted preview, promoted to sound and full screen without restarting.
        // Menu on the remote dismisses it — no chrome of our own over the picture.
        .fullScreenCover(isPresented: $isTrailerFullScreen, onDismiss: { trailer.setFullScreen(false) }) {
          fullScreenTrailer
        }
#else
      // 16:9 is the floor rather than the height, so a narrow window or a phone grows
      // the band instead of clipping the buttons off the top of it.
      //
      // Backdrop stays in the ambient scheme so the bottom seam still blends into the
      // page colour; only the overlay chrome is forced dark.
      heroCanvas
        .frame(maxWidth: .infinity)
        .background(visibilityProbe)
#if os(macOS)
        .background(toolbarCrossingProbe)
#endif
#endif
    }
  }

#if !os(tvOS)
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass

  /// Phone: the band grows with the title, plot and buttons. A fixed 16:9 clipped
  /// all of that into one short strip, and none of it was further up the scroll.
  /// Wider canvases keep the 16:9 floor.
  private var phoneHeroGrows: Bool {
#if os(iOS)
    horizontalSizeClass == .compact
#else
    false
#endif
  }

  /// The band at its aspect, whatever the words grew it to — the poster's size and
  /// column are measured against this, so a taller band does not grow the poster.
  private var heroBaseBandSize: CGSize {
    CGSize(width: heroBandSize.width, height: heroBandSize.width / Self.bandAspect)
  }

  static let bandAspect: CGFloat = 16 / 11

  /// 16:9 band — backdrop or clear fill, portrait poster top-trailing, chrome at the bottom.
  private var heroCanvas: some View {
    Group {
      if phoneHeroGrows {
        content
          .padding(.top, phase.topChromeInset)
          .frame(maxWidth: .infinity, alignment: .topLeading)
          .background {
            ZStack {
              scrollingBackdrop
              if !usesAdaptivePosterHero {
                scrollingScrim
              }
            }
          }
      } else {
        // At least the band's aspect, taller when the words need it — the poster hero
        // shows its whole synopsis, and nothing may run off the top (Sasha, 2026-11-08).
        HeroBandLayout(aspect: Self.bandAspect) {
          // The picture runs under the toolbar; the title starts below it.
          content
            .padding(.top, phase.topChromeInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGSize.self, of: \.size) { heroBandSize = $0 }
        .background(alignment: .topTrailing) {
          // Top-trailing, below the toolbar, in the band's upper half: it was centred
          // and filled the band, over the synopsis (Sasha, 2026-10-30).
          if showsCornerPoster, let url = heroPosterURL {
            cornerPosterImage(url: url, bandSize: heroBaseBandSize)
              .padding(.top, phase.topChromeInset + Self.horizontalInset)
              .padding(.trailing, Self.horizontalInset)
              .transition(.opacity)
          }
        }
        .background {
          ZStack {
            scrollingBackdrop
            if !usesAdaptivePosterHero {
              scrollingScrim
            }
          }
        }
        .clipped()
        .animation(Self.heroStateChange, value: showsPicture)
      }
    }
  }
#endif

  private func cornerPosterImage(url: URL, bandSize: CGSize) -> some View {
    let size = Self.posterAccentSize(in: bandSize)
    return CachedRemoteImage(url: url, contentMode: .fit)
      .frame(width: size.width, height: size.height)
      .clipShape(RoundedRectangle(cornerRadius: Self.trailingPosterCornerRadius, style: .continuous))
  }

#if os(tvOS)
  /// 2:3 at `trailingPosterWidth`, scaled down only when the band is too short.
  static func posterAccentSize(in bandSize: CGSize) -> CGSize {
    let width = trailingPosterWidth
    var height = width / CardAspect.poster.ratio
    let maxHeight = max(0, bandSize.height - horizontalInset * 2)
    if height > maxHeight, maxHeight > 0 {
      height = maxHeight
      return CGSize(width: height * CardAspect.poster.ratio, height: height)
    }
    return CGSize(width: width, height: height)
  }
#else
  /// 2:3, as tall as half the band — the upper half, which the title shares with it; the
  /// synopsis and the buttons below stay clear.
  static func posterAccentSize(in bandSize: CGSize) -> CGSize {
    let height = max(0, bandSize.height * posterAccentBandShare)
    return CGSize(width: height * CardAspect.poster.ratio, height: height)
  }

  static let posterAccentBandShare: CGFloat = 0.5
  /// Black over the blurred poster behind a poster hero, so the light chrome reads.
  static let posterWashDim: Double = 0.35
#endif

#if os(tvOS)
  @ViewBuilder
  private var cornerPosterAccent: some View {
    GeometryReader { band in
      if showsCornerPoster, let url = heroPosterURL {
        cornerPosterImage(url: url, bandSize: band.size)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
          .padding(.top, Self.horizontalInset)
          .padding(.trailing, Self.horizontalInset)
          .accessibilityHidden(true)
      }
    }
  }

  /// The trailer with nothing on it: black surround, aspect-fit so nothing is cropped,
  /// and the preview's own player so it carries on from where the hero left it.
  @ViewBuilder
  private var fullScreenTrailer: some View {
    ZStack {
//      Color.black.ignoresSafeArea()
      if let player = trailer.player {
        TrailerVideoLayer(player: player, gravity: .resizeAspect)
          .ignoresSafeArea()
      }
    }
    .onAppear { trailer.setFullScreen(true) }
  }
#endif

  // MARK: - Background

#if !os(tvOS)
  /// The hero sits in a plain `VStack` inside the page's `ScrollView`, so it is never
  /// removed from the hierarchy and `onDisappear` only fires when the whole page goes
  /// away — not when the hero scrolls off the top. Its frame in the scroll view's own
  /// space is what actually says whether it is on screen.
  private var visibilityProbe: some View {
    GeometryReader { proxy in
      let frame = proxy.frame(in: .named(MediaItemLayout.scrollSpace))
      Color.clear
        .onChange(of: frame.minY >= -Self.onScreenSlop) { _, onScreen in
          phase.isHeroOnScreen = onScreen
        }
    }
  }
#endif

#if os(macOS)
  /// Mac: whether the hero's bottom edge has gone up under the window toolbar. One write
  /// per crossing, read by the title page's toolbar alone.
  private var toolbarCrossingProbe: some View {
    GeometryReader { proxy in
      let past = proxy.frame(in: .named(MediaItemLayout.scrollSpace)).maxY <= phase.topChromeInset
      Color.clear
        .onChange(of: past, initial: true) { _, past in
          if phase.isHeroPastToolbar != past { phase.isHeroPastToolbar = past }
        }
    }
  }
#endif

  /// Textless enrichment first, then kino.pub's own `wide` when the payload sent one.
  /// Portrait sizes are never stretched into the hero — they sit in `trailingPosterAccent`.
  static func backdropCandidates(for mediaItem: MediaItem, preferredBackdropURL: URL? = nil) -> [URL] {
    var seen = Set<String>()
    var urls: [URL] = []
    if let preferredBackdropURL, seen.insert(preferredBackdropURL.absoluteString).inserted {
      urls.append(preferredBackdropURL)
    }
    if mediaItem.posters.hasSpecifiedWide, let wide = mediaItem.posters.wide, !wide.isEmpty {
      let resolved = CoverArtwork.resolve(url: wide, kinopoiskID: mediaItem.kinopoisk)
      if seen.insert(resolved).inserted, let url = URL(string: resolved) {
        urls.append(url)
      }
    }
    return urls
  }

#if os(tvOS)
  private var needsPosterAccent: Bool { !mediaItem.posters.hasSpecifiedWide }
#else
  /// A picture behind the chrome — from the load, not a guess: loaded is a picture,
  /// failed is a poster. Until it answers, a `wide` from kino.pub says to expect one.
  private var showsPicture: Bool {
    if let backdropOutcome, backdropOutcome.key == backdropKey {
      return backdropOutcome.loaded
    }
    return mediaItem.posters.hasSpecifiedWide && !backdropCandidates.isEmpty
  }

  private var needsPosterAccent: Bool { !showsPicture }

  private var backdropKey: String {
    "\(localCacheEpoch)|" + backdropCandidates.map(\.absoluteString).joined(separator: "|")
  }

  private func noteBackdrop(loaded: Bool) {
    let key = backdropKey
    withAnimation(Self.heroStateChange) {
      backdropOutcome = (key, loaded)
    }
  }

  /// One crossfade for every change of what the hero is: wash → picture, poster →
  /// picture, the chrome going dark over it.
  static let heroStateChange = Animation.easeInOut(duration: 0.5)
#endif

  /// Portrait accent whenever the catalogue sent no `wide` still.
  private var showsCornerPoster: Bool {
    needsPosterAccent && heroPosterURL != nil
  }

#if !os(tvOS)
  @Environment(\.colorScheme) private var systemColorScheme

  /// No picture and no poster to wash the band with — system labels on the page plate.
  /// A poster-only title keeps the blurred poster it opened on as its background, dimmed,
  /// with the same dark chrome a picture gets (Sasha, 2026-11-08): the plain plate under
  /// a corner poster read as a grey slab, and the toolbar went white on white over it.
  private var usesAdaptivePosterHero: Bool {
    !hasArtBackdrop
  }

  /// A picture, or the blurred poster standing in for one.
  private var hasArtBackdrop: Bool {
    showsPicture || heroWashURL != nil
  }

  private var heroChromeColorScheme: ColorScheme {
    usesAdaptivePosterHero ? systemColorScheme : .dark
  }
#endif

  /// Trailing column reserved in the title row — matches the poster in `heroCanvas`.
  private var posterColumnWidth: CGFloat {
#if os(tvOS)
    Self.trailingPosterWidth + Self.horizontalInset
#else
    Self.posterAccentSize(in: heroBaseBandSize).width + Self.horizontalInset
#endif
  }

  private var heroPrimaryForeground: Color {
#if os(tvOS)
    Color.KinoPub.text
#else
    usesAdaptivePosterHero ? .primary : Color.KinoPub.text
#endif
  }

  private var heroSecondaryForeground: Color {
#if os(tvOS)
    Color.KinoPub.subtitle
#else
       usesAdaptivePosterHero ? Color.KinoPub.text.opacity(0.85) : Color.KinoPub.text.opacity(0.85)
#endif
  }

  private var heroMetaForeground: Color {
#if os(tvOS)
    Self.metaStyle
#else
    usesAdaptivePosterHero ? Color.primary.opacity(0.85) : Self.metaStyle
#endif
  }

#if !os(tvOS)
  /// The cover the cards draw (`medium`), so the wash comes out of the image cache.
  private var heroWashURL: URL? {
    _ = coverLanguage
    guard !mediaItem.posters.medium.isEmpty else { return heroPosterURL }
    return URL(string: CoverArtwork.resolve(url: mediaItem.posters.medium, kinopoiskID: mediaItem.kinopoisk))
  }
#endif

  private var heroPosterURL: URL? {
#if !os(tvOS)
    _ = coverLanguage
#endif
    let raw = [mediaItem.posters.big, mediaItem.posters.medium, mediaItem.posters.small]
      .first(where: { !$0.isEmpty }) ?? ""
    guard !raw.isEmpty else { return nil }
    return URL(string: CoverArtwork.resolve(url: raw, kinopoiskID: mediaItem.kinopoisk))
  }

#if !os(tvOS)
  @AppStorage(CoverArtworkPreferences.languageKey) private var coverLanguage = ""

  private var backdropCandidates: [URL] {
    _ = coverLanguage
    return Self.backdropCandidates(for: mediaItem, preferredBackdropURL: preferredBackdropURL)
  }

  /// The candidates always load, whatever the hero currently is, so a backdrop the
  /// worker has for a title kino.pub sent no `wide` for still arrives and takes over.
  /// Under it the page's blurred poster, unwashed: the plain page under a picture still on
  /// its way read as a grey slab (Sasha, 2026-10-30). Over both, the poster hero's plate
  /// while there is no picture.
  @ViewBuilder
  private var scrollingBackdrop: some View {
    ZStack {
      MediaItemPosterWash(url: heroWashURL)
      if !backdropCandidates.isEmpty {
        FallbackRemoteImage(urls: backdropCandidates, contentMode: .fill,
                            onLoaded: { noteBackdrop(loaded: true) },
                            onFailed: { noteBackdrop(loaded: false) })
          .id(localCacheEpoch)
          .onAppear {
#if DEBUG
            let list = backdropCandidates.map(\.absoluteString).joined(separator: " | ")
            print("[Artwork] hero id=\(mediaItem.id) candidates=\(list)")
#endif
          }
      }
      // Poster hero: the wash, dimmed under the dark chrome; no poster at all: the plate.
      Color.black
        .opacity(!showsPicture && heroWashURL != nil ? Self.posterWashDim : 0)
      Color.KinoPub.posterHeroPlate
        .opacity(usesAdaptivePosterHero ? 1 : 0)

      if let player = trailer.player, trailer.isReady {
        TrailerVideoLayer(player: player)
          .allowsHitTesting(false)
          .transition(.opacity)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .clipped()
    .animation(.easeInOut(duration: 0.6), value: trailer.isReady)
  }

  /// Mac: the tvOS Home hero's legibility texture (`HeroBannerOverlay`: a 6% wash, the
  /// leading edge ramping in from a third of the way down, an eased bottom fade), and
  /// nothing fading the picture into the page — it ends on a clean edge. The flat
  /// top-and-bottom bands of the old backdrop scrim read as two slabs (Sasha, 2026-10-30).
  ///
  /// Phone / iPad: barely there, the way the Apple TV app leaves its hero video alone:
  /// clear for most of the frame, a light shade under the text, and the background colour
  /// only at the last few percent — without that the hero would meet the page on a
  /// visible seam.
  @ViewBuilder
  private var scrollingScrim: some View {
#if os(macOS)
    HeroLegibilityTexture(tone: .black)
#else
    LinearGradient(stops: [
      .init(color: .clear, location: 0),
      .init(color: .clear, location: 0.62),
      .init(color: Color.KinoPub.background.opacity(0.32), location: 0.82),
      .init(color: Color.KinoPub.background.opacity(0.9), location: 0.97),
      .init(color: Color.KinoPub.background, location: 1)
    ], startPoint: .top, endPoint: .bottom)
#endif
  }
#endif

  // MARK: - Foreground

  /// Wide screens (tvOS / Mac): two columns — title + actions | everything written.
  /// The third "starring" column is gone; its lines moved under the synopsis.
  /// Phone keeps a single stacked column, with the metadata row above the buttons.
  /// Hero chrome reads as dark over a picture: plot/credits use `Color.primary` via
  /// `Color.KinoPub.text`, and tvOS does not pin `preferredColorScheme` — light
  /// appearance made the synopsis black on dark artwork (unreadable). With no picture
  /// behind it, it follows the appearance instead (`heroChromeColorScheme`).
  private var content: some View {
    contentBody
      .environment(\.colorScheme, heroChromeColorScheme)
#if os(tvOS)
      // In step with the picture fading out of / back into the backdrop.
      .animation(.easeInOut(duration: 0.45), value: heroChromeColorScheme)
#endif
  }

  /// Title / logo at the top, synopsis and actions on the bottom — Yellowstone layout.
  @ViewBuilder
  private var contentBody: some View {
    VStack(alignment: .leading, spacing: 0) {
      heroTitleRow
      Spacer(minLength: 0)
      heroBottomBlock
    }
#if os(iOS)
    .padding(.horizontal, Self.horizontalInset)
    .padding(.bottom, Self.bottomInset)
#else
    .padding(.bottom, Self.horizontalInset)
    .padding(.horizontal, Self.bottomInset)
#endif
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  /// The written column and the buttons under it, with the people in a column of their
  /// own on the right once the hero is wide enough for one (Sasha, 2026-11-08) — bottom
  /// aligned with the buttons, as the Apple TV app sets «В главных ролях».
  @ViewBuilder
  private var heroBottomBlock: some View {
    HStack(alignment: .bottom, spacing: Self.columnGutter) {
      leadingBottomColumn
      if showsCreditsColumn {
        creditsBlock
          .frame(width: creditsColumnWidth, alignment: .leading)
      }
#if !os(tvOS)
      // The corner poster's column stays clear all the way down: the whole synopsis ran
      // under it (Sasha, 2026-11-08).
      if showsCornerPoster, !phoneHeroGrows {
        Color.clear
          .frame(width: max(0, posterColumnWidth - Self.columnGutter))
          .accessibilityHidden(true)
      }
#endif
    }
  }

  @ViewBuilder
  private var leadingBottomColumn: some View {
#if os(iOS)
    VStack(alignment: .leading, spacing: Self.contentSpacing) {
      detailColumn
      actions
        .padding(.top, Self.actionsGap)
    }
#else
    VStack(alignment: .leading, spacing: Self.columnGutter) {
      detailColumn
      actions
    }
#endif
  }

  /// What it is, how it scores, what it is about, what it plays in (Sasha, 2026-11-08):
  /// «[Новый сезон] 2025–26 сериал  3 сезона, окончен  Триллер, драма, спорт  США  18+»,
  /// then «IMDb 6.8 (1.9K)  КП 6.8 (139)  TMDB 67% (44)», the synopsis, and
  /// «[4K]  Дубляж  Рус, англ». The people follow inline only when there is no room for
  /// their column and the screen is not a phone's.
  private var detailColumn: some View {
    VStack(alignment: .leading, spacing: Self.contentSpacing) {
      factsLine
      scoresLine
      // No overview at all: no paragraph, so no lone «ЕЩЁ» capsule taking focus
      // (2026-11-08). The popup's facts stay reachable from More.
      if hasSynopsis {
#if os(tvOS)
        MediaItemPlotView(
          title: mediaItem.localizedTitle,
          plot: synopsis.plot,
          lead: synopsis.lead,
          focus: $focus,
          allowsFocus: actionEntryClaimed,
          popupSubtitle: popupOriginalTitle,
          summary: MediaItemSynopsisSummary(mediaItem: mediaItem, metadata: externalMetadata)
        )
        .padding(.vertical, Self.contentSpacing / 2)
#else
        MediaItemPlotView(
          title: mediaItem.localizedTitle,
          plot: synopsis.plot,
          lead: synopsis.lead,
          expandsFully: showsCornerPoster,
          focus: $focus,
          popupSubtitle: popupOriginalTitle,
          summary: MediaItemSynopsisSummary(mediaItem: mediaItem, metadata: externalMetadata)
        )
        .padding(.vertical, Self.contentSpacing / 2)
#endif
      }
      playbackLine
      if showsCreditsInline {
        creditsBlock
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
#if os(tvOS)
    // Separate from the action row so Down leaves this section at the page's
    // `defaultFocus` (Play), not the geometrically nearest trailing circle.
    .focusSection()
#endif
  }

  @ViewBuilder
  private var heroTitleRow: some View {
    if showsCornerPoster {
      HStack(alignment: .top, spacing: Self.columnGutter) {
        titleBlock
          .frame(maxWidth: .infinity, alignment: .leading)
        Color.clear
          .frame(width: posterColumnWidth)
          .accessibilityHidden(true)
      }
    } else {
      titleBlock
    }
  }

  @ViewBuilder
  private var titleBlock: some View {
    // Same session as the Home banner: empty while a logo is expected, cached
    // logo on the first frame, lettered title only after a confirmed miss.
    // Under a logo the subtitle is no wider than the logo is drawn — a long romaji title
    // ran across the window (Sasha, 2026-10-30). Under lettered type it keeps its width.
    SecondLineCappedToFirst(capsWidth: resolvedTitleLogoMark == .logo) {
      TitleLogoSlot(
        resolution: TitleLogoResolution(
          url: titleLogoURL,
          lookupComplete: externalMetadataLoaded
        ),
        maxWidth: Self.logoMaxWidth,
        maxHeight: Self.logoMaxHeight,
        textMaxWidth: .infinity,
        onMarkChange: { titleLogoMark = $0 },
        // A slot rebuilt on coming back paints the logo from the cache and knows no
        // served language: keep the one it said before, or the subtitle flips.
        onDeliveredLanguageChange: { if let language = $0 { deliveredLogoLanguage = language } }
      ) {
        titlePrimaryText
      }
      .id(localCacheEpoch)
      titleSupplementaryBlock
        .padding(.top, titleSupplementaryTopInset)
    }
    .id(mediaItem.id)
    .padding(.top, Self.bottomInset / 1.5)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(mediaItem.localizedTitle)
    .modifier(TitleBlockHorizontalBounds(reservePosterColumn: showsCornerPoster))
  }

  private var titlePrimaryText: some View {
    Text(mediaItem.localizedTitle)
      .font(Self.titleFont)
      .foregroundStyle(heroPrimaryForeground)
      .multilineTextAlignment(.leading)
      .fixedSize(horizontal: false, vertical: true)
      .shadow(color: .black.opacity(titleShadowOpacity), radius: 12, x: 0, y: 2)
  }

  /// A shadow lifts the title off a picture; over the poster hero's wash it only smudged
  /// (Sasha, 2026-11-08).
  private var titleShadowOpacity: Double {
#if os(tvOS)
    0.5
#else
    showsPicture ? 0.5 : 0
#endif
  }

  /// Under the logo: localized vs original from the **served** worker stamp (`ru` /
  /// `en`), not only the `?lang=` query. Under lettered type: original when it differs.
  @ViewBuilder
  private var titleSupplementaryBlock: some View {
    if let line = supplementaryUnderTitle {
      Text(line)
        .font(Self.secondaryFont)
        .foregroundStyle(heroSecondaryForeground)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .shadow(color: .black.opacity(titleShadowOpacity), radius: 8, x: 0, y: 2)
    }
  }

  /// Cached logo paints before ``TitleLogoSlot`` calls ``onMarkChange`` — treat as `.logo`.
  private var resolvedTitleLogoMark: TitleLogoMark {
    TitleLogoCaption.resolvedMark(titleLogoMark, logoURL: titleLogoURL)
  }

  /// Gap above the subtitle: looser under a wordmark than under lettered type.
  private var titleSupplementaryTopInset: CGFloat {
    guard supplementaryUnderTitle != nil else { return 0 }
    switch resolvedTitleLogoMark {
    case .logo: return Self.contentSpacing * 1.5
    case .text: return Self.contentSpacing
    case .empty: return 0
    }
  }

  private var supplementaryUnderTitle: String? {
    TitleLogoCaption.line(mark: resolvedTitleLogoMark,
                          deliveredLanguage: deliveredLogoLanguage,
                          logoURL: titleLogoURL,
                          localized: mediaItem.localizedTitle,
                          original: mediaItem.originalTitle,
                          partner: titlePartnerLine)
  }

  /// The other name, under the synopsis popup's title — whatever the hero's own subtitle
  /// line would say when the title is lettered, whether or not a logo replaced it.
  private var popupOriginalTitle: String? {
    let localized = mediaItem.localizedTitle
    if let partner = titlePartnerLine, partner != localized { return partner }
    return mediaItem.originalTitle != localized ? mediaItem.originalTitle : nil
  }

  /// Heads the written column: the scores, when and how long, then the capability
  /// chips. IMDb, Kinopoisk, TMDB — the ratings block's sources except kino.pub,
  /// whose thumbs are not a rating. Kinopoisk with voters and no number is "?".
  private var lineScores: MediaScores {
    MediaScores(mediaItem).adding(tmdb: externalMetadata.tmdbRating,
                                 tmdbVotes: externalMetadata.tmdbVotes)
  }

  // MARK: - Facts, scores, playback, people

  /// The status capsule, then the facts in blocks that wrap whole — never a genre list
  /// broken across two lines.
  @ViewBuilder
  private var factsLine: some View {
    let status = titleStatus
    let blocks = factBlocks
    if status != nil || !blocks.isEmpty {
      AboutFlowLayout(spacing: Self.metaSpacing, lineSpacing: Self.contentSpacing / 2) {
        if let status {
          TitleStatusBadge(status.text)
        }
        ForEach(blocks, id: \.self) { block in
          Text(verbatim: block)
            .lineLimit(1)
        }
      }
      .font(Self.secondaryFont)
      .foregroundStyle(heroMetaForeground)
    }
  }

  private var titleStatus: TitleStatus? {
    TitleStatus.resolve(mediaItem, externalMetadata, awaitedEpisodeAirDate: awaitedEpisodeAirDate)
  }

  /// «2025–26 аниме-сериал», «3 сезона, окончен», «Триллер, драма, спорт», «США», «18+».
  /// A film: «2026 мультфильм», «2ч 53м», genres, country. The kind is the Home hero's
  /// vocabulary (`MediaPresentationProfile.kindTitleKey`), and the genre it already says
  /// (anime, animation, documentary) is not repeated after it.
  private var factBlocks: [String] {
    let card = MediaCard(mediaItem)
    let profile = mediaItem.presentation
    var blocks: [String] = []

    let kindKey = profile.kindTitleKey(isSeries: isSeries)
    // A plain film says nothing about being a film: the runtime says it.
    let kind = kindKey == "Kind_movies_One" ? nil : kindKey.localized
    let years = isSeries ? card.bannerYearSpan : (mediaItem.year > 0 ? String(mediaItem.year) : nil)
    // «2011  Документальный фильм»: the kind keeps its capital, two spaces from the year
    // (Sasha, 2026-11-08).
    let head = [years, kind].compactMap { $0 }
    if !head.isEmpty { blocks.append(head.joined(separator: "  ")) }

    if isSeries {
      let seasons = mediaItem.seasons ?? []
      let episodes = seasons.reduce(0) { $0 + $1.episodes.count }
      var volume: [String] = []
      if seasons.count > 1, let text = SeasonCountText(seasons.count)?.formatted() {
        volume.append(text)
      } else if let text = EpisodesLeftText(episodes)?.formatted() {
        volume.append(text)
      }
      if SeriesFacts.isFinished(mediaItem, externalMetadata) {
        volume.append("MediaItem_StatusEndedShort".localized)
      }
      if !volume.isEmpty { blocks.append(volume.joined(separator: ", ")) }
    }

    let genres = card.usefulGenres(limit: Self.genreLimit,
                                   omittingDocumentary: profile.kind == .documentary)
    if let first = genres.first {
      let rest = genres.dropFirst().map { $0.lowercased() }
      blocks.append(([first] + rest).joined(separator: ", "))
    }
    if let country = mediaItem.countryNames.first, !country.isEmpty {
      blocks.append(country)
    }
    // Always: the «show age rating» preference is the poster's, not this line's (Sasha,
    // 2026-11-08).
    if let ageRating, !ageRating.isEmpty {
      blocks.append(ageRating)
    }
    return blocks
  }

  /// How long what Play offers runs — the episode it opens; for a film the version in focus, else the last one that was,
  /// else the first not yet watched (Sasha, 2026-10-25); the film's own runtime otherwise.
  private var runtimeText: String? {
    if isSeries {
      guard let (_, episode) = mediaItem.primaryEpisode, episode.duration > 0 else { return nil }
      return RuntimeText(seconds: episode.duration).text(for: .detailRuntime)
    }
    if let version = runtimeVersion, version.duration > 0 {
      return RuntimeText(seconds: version.duration).text(for: .detailRuntime)
    }
    return mediaItem.mediaEntity.runtime.flatMap { RuntimeText(seconds: $0).text(for: .detailRuntime) }
  }

  @ViewBuilder
  private var scoresLine: some View {
    if lineScores.hasDisplayableScore {
      HStack(spacing: Self.metaSpacing) {
        if FeatureFlags.combinedRatingEnabled, let rating = lineScores.aggregate {
          RatingBadgeView(rating: rating)
          MediaScoresView(lineScores, deduplicateAgainstAggregate: true, detailLine: true)
        } else {
          // No aggregate: each score keeps its own logo rather than becoming one number.
          MediaScoresView(lineScores, detailLine: true)
        }
      }
      .font(Self.secondaryFont)
      .foregroundStyle(heroMetaForeground)
    }
  }

  /// What the synopsis says. A series the viewer is into but has not finished speaks of
  /// the episode Play opens, the way the Apple TV app does: «3 серия: Название.» in bold,
  /// then that episode's overview — the series' own plot when TMDB has none (Sasha,
  /// 2026-11-08).
  private var synopsis: (lead: String?, plot: String) {
    guard isSeries, isSeriesUnderWay, let (_, episode) = mediaItem.primaryEpisode else {
      return (nil, mediaItem.plot)
    }
    let name = EpisodeTitle.meaningful(primaryEpisodeSchedule?.name)
      ?? EpisodeTitle.meaningful(episode.title)
    var lead = name.map { String(format: "MediaItem_EpisodeLead".localized, episode.number, $0) }
      ?? String(format: "MediaItem_EpisodeLeadNumber".localized, episode.number)
    if let last = lead.last, !".!?…".contains(last) { lead += "." }
    let overview = primaryEpisodeSchedule?.overview?.trimmingCharacters(in: .whitespacesAndNewlines)
    return (lead, overview.flatMap { $0.isEmpty ? nil : $0 } ?? mediaItem.plot)
  }

  private var hasSynopsis: Bool {
    let synopsis = self.synopsis
    return !synopsis.plot.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || synopsis.lead != nil
  }

  /// Started — an episode watched or one in progress — and not finished.
  private var isSeriesUnderWay: Bool {
    guard mediaItem.playbackAction != .playAgain else { return false }
    if case .resume = mediaItem.playbackButtonContent { return true }
    return (mediaItem.seasons ?? []).contains { season in
      season.episodes.contains { $0.watched > 0 || $0.watching.time > 0 }
    }
  }

  /// «2ч 47м  [4K]  Русский, дубляж + ещё 5  Английский  Русский, Английский»: how long
  /// what Play opens runs, the drawn quality badges, then the sound and the subtitles in
  /// the viewer's own languages only (Sasha, 2026-11-08).
  @ViewBuilder
  private var playbackLine: some View {
    let runtime = runtimeText
    let badges = MediaCapabilityBadges.from(item: mediaItem).detailBadgeAssets
    let audio = audioSummary
    let subtitles = subtitleSummary
    if runtime != nil || !badges.isEmpty || audio != nil || subtitles != nil {
      AboutFlowLayout(spacing: Self.metaSpacing, lineSpacing: Self.contentSpacing / 2) {
        if let runtime {
          Text(verbatim: runtime)
        }
        if !badges.isEmpty {
          MediaBadgeImages(badges)
        }
        if let audio {
          HStack(spacing: Self.glyphSpacing) {
            Image(systemName: Self.voicingSymbol)
            Text(verbatim: audio)
          }
        }
        if let subtitles {
          HStack(spacing: Self.glyphSpacing) {
            Image(systemName: Self.subtitlesSymbol)
            Text(verbatim: subtitles)
          }
        }
      }
      .lineLimit(1)
      .font(Self.secondaryFont)
      .foregroundStyle(heroMetaForeground)
    }
  }

  /// Each of the viewer's languages the title has, in their order: the language, its
  /// best voicing by the player's ladder (kino.pub's own word for it), and how many more
  /// tracks there are in it — «Русский, дубляж + ещё 5  Английский». The original says
  /// no voicing. Other languages are left out; nil when none of the viewer's is there.
  private var audioSummary: String? {
    let tracks = mediaItem.detailAudioTracks.filter { !$0.isAudioDescription }
    let parts = viewerLanguages.compactMap { key -> String? in
      let inLanguage = tracks.filter { SubtitleTracks.languageKey($0.lang) == key }
      guard let name = languageName(key), !inLanguage.isEmpty else { return nil }
      var text = name
      let best = inLanguage.min { rank($0) < rank($1) }
      if let best, let voice = best.typeId.flatMap(VoiceType.init(rawValue:)),
         voice != .original, voice != .undetermined,
         let title = best.typeTitle?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
        text += ", " + title.lowercased()
      }
      if inLanguage.count > 1 {
        text += " " + String(format: "MediaItem_PlusMoreCount".localized, inLanguage.count - 1)
      }
      return text
    }
    return parts.isEmpty ? nil : parts.joined(separator: "  ")
  }

  /// The viewer's languages among the subtitles: «Русский, Английский».
  private var subtitleSummary: String? {
    let keys = Set(mediaItem.subtitleLanguageGroups(preferredLanguages: mediaItemPreferredLanguages()).map(\.key))
    let names = viewerLanguages.filter(keys.contains).compactMap(languageName)
    return names.isEmpty ? nil : names.joined(separator: ", ")
  }

  /// The viewer's languages, as audio and subtitle keys, first-preferred first.
  private var viewerLanguages: [String] {
    var seen = Set<String>()
    return mediaItemPreferredLanguages()
      .map(SubtitleTracks.languageKey)
      .filter { seen.insert($0).inserted }
  }

  private func languageName(_ key: String) -> String? {
    let groups = mediaItem.audioLanguageGroups(preferredLanguages: mediaItemPreferredLanguages())
      + mediaItem.subtitleLanguageGroups(preferredLanguages: mediaItemPreferredLanguages())
    guard let name = groups.first(where: { $0.key == key })?.name, !name.isEmpty else { return nil }
    return name.prefix(1).uppercased() + name.dropFirst()
  }

  private func rank(_ track: AudioTrackInfo) -> Int {
    track.typeId.flatMap(VoiceType.init(rawValue:))?.preferenceRank ?? AudioTracks.kindRankUnknown
  }

  /// The column on the right: present on the TV; elsewhere once the hero leaves room for
  /// it beside a full synopsis measure. Never on a phone.
  private var showsCreditsColumn: Bool {
    guard !creditLines.isEmpty else { return false }
#if os(tvOS)
    return true
#else
    // The poster has the right side; the people go under the synopsis.
    guard !showsCornerPoster else { return false }
    let available = heroBandSize.width - 2 * Self.contentHorizontalInset
    return available >= MediaItemPlotView.maxWidth + Self.columnGutter + creditsColumnWidth
#endif
  }

  /// No room for the column: the people go under the playback line — on a Mac window or
  /// an iPad too narrow for the column, never on a phone.
  private var showsCreditsInline: Bool {
#if os(tvOS)
    false
#else
    !creditLines.isEmpty && !showsCreditsColumn && !phoneHeroGrows && heroBandSize.width > 0
#endif
  }

  /// Half the synopsis measure, as the Apple TV app's column is beside its text.
  private var creditsColumnWidth: CGFloat {
    MediaItemPlotView.maxWidth * Self.creditsColumnRatio
  }

  /// One line per role, each wrapping on its own: «В ролях Мэтт Дэймон, Том Холланд,
  /// Энн Хэтэуэй», then «Режиссёр Кристофер Нолан» on a new line (Sasha, 2026-11-08).
  private var creditsBlock: some View {
    VStack(alignment: .leading, spacing: Self.creditLineSpacing) {
      ForEach(creditLines, id: \.role) { line in
        Text(creditLine(line))
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .font(Self.secondaryFont)
    .multilineTextAlignment(.leading)
  }

  /// One run of attributed text rather than two concatenated `Text`s: the styling
  /// overloads that return `Text` are either iOS 17 or deprecated, and the label has
  /// to flow into the names on the same line anyway.
  private func creditLine(_ line: (role: String, names: String)) -> AttributedString {
    var label = AttributedString(line.role.localized + " ")
    label.foregroundColor = heroSecondaryForeground

    var names = AttributedString(line.names)
    names.foregroundColor = heroPrimaryForeground

    return label + names
  }

  /// A handful of leads, then whoever directed or created it, each on its own line.
  ///
  /// Nobody stars in a stand-up set, a concert or a documentary, and their director is
  /// not who one picks them by: those name nobody here — their people are a Credits card
  /// in the information table. `MediaPresentationProfile` owns which is which. One person
  /// is «Режиссёр» / «Создатель», never the plural.
  private var creditLines: [(role: String, names: String)] {
    var lines: [(String, String)] = []
    let profile = mediaItem.presentation
    let cast: [String] = profile.showsHeroCastLine
      ? Array(mediaItem.castMembers.prefix(Self.creditNameLimit))
      : []
    if !cast.isEmpty {
      lines.append(("Starring.short", cast.joined(separator: ", ")))
    }
    if profile.showsHeroAuthorLine {
      let makers = Array(mediaItem.directorNames.prefix(Self.authorNameLimit))
      if !makers.isEmpty {
        lines.append((profile.authorLabelKey(count: makers.count), makers.joined(separator: ", ")))
      }
    }
    return lines
  }

  /// One catalog-driven row. Order/chrome from `MediaActionCatalog`; this view wires
  /// behaviour. Dark over the hero artwork so glass samples against it the same way in
  /// light and dark. tvOS keeps them dark everywhere; iPhone / Mac follow the appearance
  /// with no picture behind.
  private var actions: some View {
    MediaActionRow {
      ForEach(actionAppearances) { appearance in
        actionControl(for: appearance)
          .accessibilityIdentifier("kinopub.hero.\(appearance.id.rawValue)")
#if os(tvOS)
          // The row does not animate on tvOS at all — not as the page opens or closes,
          // not when the details call adds a button. Scaling glass in from 85 % was the
          // flicker and blur on every visit (Sasha, 2026-11-05).
          .transition(.identity)
#else
          .transition(.asymmetric(
            insertion: .scale(scale: 0.85).combined(with: .opacity),
            removal: .scale(scale: 0.85).combined(with: .opacity)
          ))
#endif
      }
    }
#if os(tvOS)
    // Always dark, the way the Apple TV app keeps them: light circles on the light
    // details were the brightest thing on screen (Sasha, 2026-10-25).
    .environment(\.colorScheme, .dark)
#else
    .environment(\.colorScheme, heroChromeColorScheme)
#endif
#if os(tvOS)
    // Own focus section so Down from the plot section enters here at `defaultFocus`
    // Play — never `.disabled` on siblings to steer the remote (that killed Menus).
    .focusSection()
    // Up from the season tabs or the episodes lands on the main button too, not on the
    // circle that happens to be above (Sasha, 2026-10-11). `.userInitiated`: a remote
    // move is user-initiated, and the default priority only seeds the first focus.
    .defaultFocus($focus, actionEntryTarget, priority: .userInitiated)
#endif
    // Animate only membership changes (Mark Watched appearing/disappearing) — not
    // glyph swaps inside a stable id, which used to look like the gaps grew.
#if !os(tvOS)
    .animation(.easeOut(duration: 0.25), value: actionAppearances.map(\.id))
#endif
    .onChange(of: isWatched) { _, _ in
      loadingActions.remove(.markWatched)
    }
    .onChange(of: isInWatchlist) { _, _ in
      loadingActions.remove(.follow)
    }
    .task {
      // Folder names live in BookmarkFoldersStore; cold installs have nothing until
      // Library/Bookmarks adopt. Ask once so the menu is not an empty "New Folder".
      await ensureBookmarkFoldersLoaded?()
    }
  }

  /// The grid's season, when it has one, else the number already on the button
  /// (the title's, which is the chip's).
  private func relabel(_ playback: PlaybackButtonContent) -> PlaybackButtonContent {
    guard let season = mediaItem.primaryEpisode?.season,
          let label = seasonLabels[season.id] else { return playback }
    return playback.replacingSeason(label)
  }

  private var actionContext: MediaActionContext {
#if os(tvOS)
    let showsMore = true
#else
    let showsMore = false
#endif
    let choices = mediaItem.playChoices
    // One version left of several: it is Play itself, in its own state — not a pill of one.
    let playback = relabel(choices.count == 1 ? choices[0].playbackButtonContent : mediaItem.playbackButtonContent)
    let promote = Self.promotesFollow(mediaItem: mediaItem,
                                      awaitedEpisodeAirDate: awaitedEpisodeAirDate,
                                      canFollow: onToggleWatchlist != nil)
    return MediaActionContext(
      playback: playback,
      kind: mediaItem.presentation.kind,
      isSeries: isSeries,
      isBookmarked: isBookmarked,
      isFollowing: isInWatchlist,
      showsMarkWatched: showsWatchedButton && !promote,
      showsTrailer: mediaItem.trailerURL != nil,
      showsFollow: isSeries && onToggleWatchlist != nil && !promote,
      download: downloadPhase,
      showsShuffle: showsShuffleButton && !promote,
      showsMore: showsMore,
      promoteFollow: promote,
      versions: choices.count > 1
        ? choices.map {
          MediaActionVersion(name: $0.name, playback: $0.playbackButtonContent,
                             isMain: mediaItem.isMainVersion($0))
        }
        : [],
      loading: loadingActions,
      seasonCount: mediaItem.seasons?.count
    )
  }

  /// Whether labelled Follow leads the row. Shared with the page, whose `defaultFocus`
  /// has to name the same control the hero claims.
  static func promotesFollow(mediaItem: MediaItem,
                             awaitedEpisodeAirDate: Date?,
                             canFollow: Bool) -> Bool {
    canFollow && MediaActionCatalog.shouldPromoteFollow(
      isSeries: mediaItem.isSeries,
      playback: mediaItem.playbackButtonContent,
      seriesFinished: mediaItem.finished,
      awaitedEpisodeAirDate: awaitedEpisodeAirDate
    )
  }

  /// Random episode — only long series that are not already on the watchlist.
  /// Interim rule: more than five seasons and not subscribed. Icon sits before More.
  private var showsShuffleButton: Bool {
    guard isSeries, !isInWatchlist, let seasons = mediaItem.seasons else { return false }
    return seasons.count > 5
  }

  private var actionAppearances: [MediaActionAppearance] {
#if os(macOS)
    // The window toolbar carries these on a Mac (`MediaItemView`).
    MediaActionCatalog.row(for: actionContext).filter { $0.id != .bookmark && $0.id != .markWatched }
#else
    MediaActionCatalog.row(for: actionContext)
#endif
  }

  @ViewBuilder
  private func actionControl(for appearance: MediaActionAppearance) -> some View {
    switch appearance.id {
    case .play, .playAlternate, .playThird:
      playControl(appearance)
    case .moreVersions:
      moreVersionsControl(appearance)
    case .trailer:
      trailerControl(appearance)
    case .bookmark:
      bookmarkControl(appearance)
    case .follow:
      followControl(appearance)
    case .markWatched:
      markWatchedControl(appearance)
    case .more:
      moreControl(appearance)
    case .download:
      downloadControl(appearance)
    case .shuffle:
      shuffleControl(appearance)
    }
  }

  @ViewBuilder
  private func downloadControl(_ appearance: MediaActionAppearance) -> some View {
    Button {
      switch downloadPhase {
      case .downloading:
        onPauseDownload?()
      default:
        onDownload?()
      }
    } label: {
      MediaActionLabel(appearance)
    }
    .mediaActionStyle(appearance)
    .focused($focus, equals: .download)
    .contextMenu {
      if isSeries, let (season, _) = mediaItem.primaryEpisode {
        Button {
          onDownloadSeason?(season)
        } label: {
          Label("Season", systemImage: "arrow.down.to.line")
        }
        Button {
          onDownloadUnwatchedInSeason?(season)
        } label: {
          Label("Unwatched in Season", systemImage: "arrow.down.to.line")
        }
        Button {
          onDownloadAllEpisodes?()
        } label: {
          Label("All Episodes", systemImage: "arrow.down.to.line")
        }
      }
    }
  }

  /// Random unwatched episode — circle before More; same player entry as Play.
  @ViewBuilder
  private func shuffleControl(_ appearance: MediaActionAppearance) -> some View {
    if let target = randomUnwatchedEpisode {
      PlayerLink(route: linkProvider.player(for: target), item: target, mode: .media) {
        MediaActionLabel(appearance)
      }
      .mediaActionStyle(appearance)
      .focused($focus, equals: .shuffle)
      .accessibilityLabel(Text(appearance.accessibilityLabel))
    } else {
      MediaActionButton(appearance) {}
    }
  }

  private var randomUnwatchedEpisode: Episode? {
    guard let seasons = mediaItem.seasons else { return nil }
    var pool: [Episode] = []
    for season in seasons {
      for episode in season.episodes where !episode.isWatched {
        episode.seasonNumber = season.number
        episode.mediaId = season.mediaId
        episode.seriesTitle = mediaItem.localizedTitle
        pool.append(episode)
      }
    }
    return pool.randomElement()
  }

  /// Play, or one version's pill — same control, different target.
  @ViewBuilder
  private func playControl(_ appearance: MediaActionAppearance) -> some View {
    let target = playTarget(for: appearance.id)
    PlayerLink(route: linkProvider.player(for: target), item: target, mode: .media) {
      MediaActionLabel(appearance)
    }
    .mediaActionStyle(appearance)
    .focused($focus, equals: Self.focusTarget(forPlay: appearance.id))
    .accessibilityLabel(Text(appearance.accessibilityLabel))
    .accessibilityHint(Text("Starts playback"))
    .task(id: target.id) {
      await PlaybackPreflight.shared.warm(target)
    }
  }

  @ViewBuilder
  private func trailerControl(_ appearance: MediaActionAppearance) -> some View {
    PlayerLink(route: linkProvider.trailerPlayer(for: mediaItem), item: mediaItem, mode: .trailer) {
      MediaActionLabel(appearance)
    }
    .mediaActionStyle(appearance)
    .focused($focus, equals: .trailer)
  }

  /// Bookmark folders — multi-select with a section title (the circle has no label).
  /// Stays open while toggling; do **not** `.id` the menu on membership or focus
  /// jumps back to Play after one checkmark.
  @ViewBuilder
  private func bookmarkControl(_ appearance: MediaActionAppearance) -> some View {
    Menu {
      Section {
        if folders.isEmpty {
          Text("No bookmark folders yet")
            .foregroundStyle(.secondary)
        } else {
          ForEach(folders, id: \.id) { folder in
            Toggle(isOn: Binding(
              get: { folderIDsContainingItem.contains(folder.id) },
              set: { _ in onFolderToggle(folder) }
            )) {
              Text(folder.title)
            }
          }
        }
      } header: {
        Text("Bookmarks")
      }

      if onCreateFolder != nil {
        Button {
          newFolderName = ""
          showNewFolderAlert = true
        } label: {
          Label("New Folder", systemImage: "plus.circle")
        }
      }
    } label: {
      MediaActionLabel(appearance)
    }
#if !os(macOS)
    .menuActionDismissBehavior(.disabled)
#endif
    .mediaActionStyle(appearance)
    .focused($focus, equals: .bookmark)
    .accessibilityLabel(Text(appearance.accessibilityLabel))
    .alert("New Folder", isPresented: $showNewFolderAlert) {
      TextField("Folder name", text: $newFolderName)
      Button("Create") {
        onCreateFolder?(newFolderName)
        newFolderName = ""
      }
      Button("Cancel", role: .cancel) { newFolderName = "" }
    }
  }

  @ViewBuilder
  private func followControl(_ appearance: MediaActionAppearance) -> some View {
    Button {
      guard MediaItemHeroActionAvailability.isInteractable(isLoading: appearance.isLoading) else { return }
      loadingActions.insert(.follow)
      onToggleWatchlist?()
    } label: {
      MediaActionLabel(appearance)
    }
    .mediaActionStyle(appearance)
    .focused($focus, equals: .watchlist)
  }

  /// Tap marks watched. Long-press (series): episode · season · unwatched in season · all.
  @ViewBuilder
  private func markWatchedControl(_ appearance: MediaActionAppearance) -> some View {
    Button {
      guard MediaItemHeroActionAvailability.isInteractable(isLoading: appearance.isLoading) else { return }
      beginMarkWatched()
      onWatchedToggle()
    } label: {
      MediaActionLabel(appearance)
    }
    .mediaActionStyle(appearance)
    .focused($focus, equals: .watched)
    .accessibilityLabel(Text(appearance.accessibilityLabel))
    .contextMenu {
      if let (season, episode) = mediaItem.primaryEpisode {
        Button {
          guard MediaItemHeroActionAvailability.isInteractable(isLoading: appearance.isLoading) else { return }
          beginMarkWatched()
          onWatchedToggle()
        } label: {
          Label("\("Mark Episode Watched".localized) · \(EpisodeText(season: season.number, number: episode.number).text(for: .contextMenu))",
                systemImage: "checkmark")
        }
        if onSeasonWatchedToggle != nil {
          Button {
            guard MediaItemHeroActionAvailability.isInteractable(isLoading: appearance.isLoading) else { return }
            beginMarkWatched()
            onSeasonWatchedToggle?(season)
          } label: {
            Label("\("Mark Season Watched".localized) · \(SeasonText(season.number).formatted(MediaSurface.contextMenu.textLength))",
                  systemImage: "checkmark.circle")
          }
        }
        if onMarkUnwatchedInSeason != nil {
          Button {
            guard MediaItemHeroActionAvailability.isInteractable(isLoading: appearance.isLoading) else { return }
            beginMarkWatched()
            onMarkUnwatchedInSeason?(season)
          } label: {
            Label("Mark Unwatched in Season", systemImage: "checkmark.circle")
          }
        }
        if onMarkAllEpisodesWatched != nil {
          Button {
            guard MediaItemHeroActionAvailability.isInteractable(isLoading: appearance.isLoading) else { return }
            beginMarkWatched()
            onMarkAllEpisodesWatched?()
          } label: {
            Label("Mark All Episodes Watched", systemImage: "checkmark.circle.fill")
          }
        }
      }
    }
  }

  private func beginMarkWatched() {
    loadingActions.insert(.markWatched)
  }

  @ViewBuilder
  private func moreControl(_ appearance: MediaActionAppearance) -> some View {
    Menu {
      MediaItemOverflowMenu(isSeries: isSeries,
                            isWatched: isWatched,
                            isBookmarked: isBookmarked,
                            onWatchedToggle: onWatchedToggle,
                            onClearFromContinueWatching: onClearFromContinueWatching,
                            onBrowseWatchlist: onBrowseWatchlist)
      if downloadPhase == .downloaded, let onDeleteDownload {
        Divider()
        Button(role: .destructive, action: onDeleteDownload) {
          Label("Delete Download", systemImage: "trash")
        }
      }
      if let imageAdmin {
        Divider()
        TitleImageAdminMenuItems(actions: imageAdmin)
      }
    } label: {
      MediaActionLabel(appearance)
    }
    .mediaActionStyle(appearance)
    .focused($focus, equals: .more)
    .accessibilityLabel(Text(appearance.accessibilityLabel))
  }

  private static func focusTarget(forPlay id: MediaActionID) -> MediaItemFocusTarget {
    switch id {
    case .playAlternate: .playAlternate
    case .playThird: .playThird
    default: .play
    }
  }

  /// «+ ещё N» — the versions without a pill are in the rail right under the hero.
  private func moreVersionsControl(_ appearance: MediaActionAppearance) -> some View {
    MediaActionButton(appearance) {
      onShowMoreVersions?()
    }
    .focused($focus, equals: .moreVersions)
  }

  /// What a play pill opens. A title shown as version pills: that version, by position
  /// in `playChoices` (the catalog's `versions` are the same list). One choice left: that
  /// one. Everything else: `playTarget`.
  private func playTarget(for id: MediaActionID) -> any PlayableItem {
    choice(for: id) ?? playTarget
  }

  /// The version a play control stands for, when the title is in several.
  private func choice(for id: MediaActionID) -> PlaybackVariant? {
    let choices = mediaItem.playChoices
    guard !choices.isEmpty else { return nil }
    let index = switch id {
    case .playAlternate: 1
    case .playThird: 2
    default: 0
    }
    return choices[min(index, choices.count - 1)]
  }

  private static func actionID(forPlay target: MediaItemFocusTarget) -> MediaActionID? {
    switch target {
    case .play: .play
    case .playAlternate: .playAlternate
    case .playThird: .playThird
    default: nil
    }
  }

  /// The version whose runtime the metadata row shows: the play control in focus, else the
  /// last one that was, else the first not yet watched (Sasha, 2026-10-25). Nil for a title
  /// in one version — its own runtime stands.
  private var runtimeVersion: PlaybackVariant? {
    let choices = mediaItem.playChoices
    guard !choices.isEmpty else { return nil }
    if let target = focus, let id = Self.actionID(forPlay: target), let focused = choice(for: id) {
      return focused
    }
    if let last = lastFocusedVersionID, let remembered = choices.first(where: { $0.id == last }) {
      return remembered
    }
    return choices.first { !$0.isWatched } ?? choices.first
  }

  /// For a series, play the first episode that still has something left; the rail
  /// below is there for picking any other one.
  private var playTarget: any PlayableItem {
    guard let (season, episode) = mediaItem.primaryEpisode else { return mediaItem }
    episode.seasonNumber = season.number
    episode.mediaId = season.mediaId
    episode.seriesTitle = mediaItem.localizedTitle
    return episode
  }

  // MARK: - Metrics

  /// Seconds of artwork before the trailer takes over.????? it must start no sooner than this interval after open - but only if the player is ready and asset can play while in hero focus
  static let trailerLeadIn: Double = 3
  /// Non-tvOS only: fade as soon as the hero has scrolled up at all. The old
  /// half-height threshold left the trailer running under the first section below.
  static let onScreenSlop: CGFloat = 150

  /// Leads named in the hero, before the list turns into a paragraph.
  static let creditNameLimit = 3
  /// Directors / creators named in the hero; the Credits card names them all.
  static let authorNameLimit = 2

  /// Genres in the facts line, one block; kino.pub happily returns six.
  static let genreLimit = 3

  /// The people's column, as a share of the synopsis measure beside it.
  static let creditsColumnRatio: CGFloat = 0.5

  /// Glyph before the voicing and before the subtitle languages in the playback line.
  static let voicingSymbol = "waveform"
  static let subtitlesSymbol = "captions.bubble"
  static let glyphSpacing: CGFloat = 6

  /// The content's side inset, as `contentBody` pads it.
  static var contentHorizontalInset: CGFloat {
#if os(iOS)
    horizontalInset
#else
    bottomInset
#endif
  }

  /// Everything under the title is one size — real body text, not a caption — and it
  /// is the same size the ratings captions and the information table use further down
  /// the page. See `TypeScale.detailBody`, which is where that decision lives.
  static let secondaryFont: Font = TypeScale.detailBody

  /// Not `text`, not `subtitle`: the row Apple puts under the title looks like primary
  /// text with the artwork faintly coming through it.
  static let metaStyle = Color.KinoPub.text.opacity(0.85)

#if os(tvOS)
  // Unused for layout — the slideshow slide sizes the hero. Kept so shared metrics
  // below stay in one `#if` block.
  static let heroHeight: CGFloat = 1280
  static let horizontalInset: CGFloat = 80
  static let bottomInset: CGFloat = 80
  static let contentSpacing: CGFloat = 12
  static let leadingWidth: CGFloat = .infinity
  static let logoMaxWidth: CGFloat = 680
  static let logoMaxHeight: CGFloat = 170
  static let titleFont: Font = TypeScale.heroTitle
  static let metaSpacing: CGFloat = 20
  static let actionsGap: CGFloat = 20
  static let actionsRowGap: CGFloat = 16
  static let creditLineSpacing: CGFloat = 8
  static let columnGutter: CGFloat = 48
  static let trailingPosterWidth: CGFloat = 500
  static let trailingPosterCornerRadius: CGFloat = 14
#elseif os(macOS)
  /// Preview / fallback only — live layout uses `.aspectRatio(16/9)`.
  static let heroHeight: CGFloat = 420
  static let horizontalInset: CGFloat = 40
  static let bottomInset: CGFloat = 28
  static let contentSpacing: CGFloat = 8
  static let leadingWidth: CGFloat = 400
  static let logoMaxWidth: CGFloat = 440
  static let logoMaxHeight: CGFloat = 120
  static let titleFont: Font = TypeScale.heroTitle
  static let metaSpacing: CGFloat = 12
  static let actionsGap: CGFloat = 12
  static let actionsRowGap: CGFloat = 10
  static let creditLineSpacing: CGFloat = 3
  static let columnGutter: CGFloat = 28
  static let trailingPosterCornerRadius: CGFloat = 14
#else
  /// Preview / fallback only — live layout uses `.aspectRatio(16/9)`.
  static let heroHeight: CGFloat = 380
  static let horizontalInset: CGFloat = 20
  static let bottomInset: CGFloat = 20
  static let contentSpacing: CGFloat = 8
  static let leadingWidth: CGFloat = 560
  static let logoMaxWidth: CGFloat = 360
  static let logoMaxHeight: CGFloat = 96
  static let titleFont: Font = TypeScale.heroTitle
  static let metaSpacing: CGFloat = 10
  static let actionsGap: CGFloat = 10
  static let actionsRowGap: CGFloat = 10
  static let creditLineSpacing: CGFloat = 3
  static let columnGutter: CGFloat = 16
  static let trailingPosterCornerRadius: CGFloat = 12
#endif
}

/// Title width: ~80% of the hero, or the full column left of the portrait poster.
private struct TitleBlockHorizontalBounds: ViewModifier {
  let reservePosterColumn: Bool

  func body(content: Content) -> some View {
    if reservePosterColumn {
      content.frame(maxWidth: .infinity, alignment: .leading)
    } else {
      content.containerRelativeFrame(.horizontal, count: 5, span: 4, spacing: 0, alignment: .leading)
    }
  }
}

private extension View {

  /// Was a per-glyph drop shadow; removed 2026-08-09 (real cost, `.shadow` forces an
  /// offscreen pass on every focus/wash animation tick this text rides). Legibility now
  /// has to come from contrast — `bottomScrim` / `titleScrim` under the text — rather
  /// than a shadow chasing the letters. Placeholder kept so call sites don't need
  /// touching again once that contrast pass lands; see
  /// `docs/archive/plans/detail-page-choreography.md`.
  func heroTextShadow() -> some View {
    self
  }
}

#if DEBUG
private struct MediaItemHeroPreview: View {
  @FocusState private var focus: MediaItemFocusTarget?
  @StateObject private var trailer = TrailerPreviewModel()
  @State private var navigationState = NavigationState()
  @State private var heroPhase = MediaItemHeroPhase()

  var body: some View {
    MediaItemHeroView(
      mediaItem: MediaItem.mock(),
      focus: $focus,
      trailer: trailer,
      phase: heroPhase,
      linkProvider: AppRoutesLinkProvider(),
      isWatched: false,
      isBookmarked: true,
      folders: [],
      folderIDsContainingItem: [],
      onWatchedToggle: {},
      onFolderToggle: { _ in },
      titleLogoURL: nil,
      externalMetadataLoaded: true
    )
    .environment(navigationState)
//    .aspectRatio(16 / 9, contentMode: .fit)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
//    .background(Color.black)
    // .preferredColorScheme(.dark)
  }
}

#Preview("Hero + capability badges") {
  MediaItemHeroPreview()
}
#endif

/// The hero band: as tall as `aspect` makes it at its width, taller when the content needs
/// more — and the content is offered the band's full height, so its spacer still pushes
/// the synopsis and buttons to the bottom.
private struct HeroBandLayout: Layout {
  var aspect: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? subviews.first?.sizeThatFits(.unspecified).width ?? 0
    let natural = subviews.first?.sizeThatFits(ProposedViewSize(width: width, height: nil)).height ?? 0
    return CGSize(width: width, height: max(natural, width / aspect))
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for subview in subviews {
      subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
  }
}
