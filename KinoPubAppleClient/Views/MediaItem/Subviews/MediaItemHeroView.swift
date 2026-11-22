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
  /// Multi-version film: one Play opens «Choose a Version» instead of several pills.
  @State private var showsVersionPicker = false
#if !os(tvOS)
  /// The band's size, for the corner poster and the column the title leaves it.
  @State private var heroBandSize: CGSize = .zero
  /// Trailer pressed before the details call brought its stream (iOS).
  @State private var awaitsTrailer = false
#endif
#if os(iOS)
  @Environment(NavigationState.self) private var navigationState
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
  /// The hero control that opened the player — Trailer, a version's pill, Play — for
  /// the return (`claimEntryAfterReturn`).
  @State private var playerOpener: MediaItemFocusTarget?
  @State private var lastPlayerControl: MediaItemFocusTarget?
  /// This appearance is a return to the page (`onAppear` saw it covered); the `.task`
  /// that follows leaves focus to `claimEntryAfterReturn`.
  @State private var returningAppearance = false
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
  /// A series from the first frame: a listing copy names the type but carries no
  /// seasons, and «Nocturne» opened from one painted as a film — no «Series», no bell —
  /// then rebuilt its row and facts when the details came (Sasha, 2026-11-21).
  private var isSeries: Bool {
    !(mediaItem.seasons?.isEmpty ?? true) || mediaItem.isEpisodicType
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
      // Over the hero, not in the system sheet: that sheet is a fixed platter with a
      // navigation bar (the green truncated «Выберите версию»).
      .fullScreenCover(isPresented: $showsVersionPicker) {
        VersionPickerSheet(
          variants: mediaItem.playbackVariants,
          fallbackStillURL: mediaItem.posters.wideURL
            ?? (mediaItem.posters.big.isEmpty ? nil : mediaItem.posters.big),
          linkProvider: linkProvider
        )
        .presentationBackground(.clear)
        .pageColorScheme()
      }
#else
      .sheet(isPresented: $showsVersionPicker) {
        VersionPickerSheet(
          variants: mediaItem.playbackVariants,
          fallbackStillURL: mediaItem.posters.wideURL
            ?? (mediaItem.posters.big.isEmpty ? nil : mediaItem.posters.big),
          linkProvider: linkProvider
        )
      }
#endif
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
        // Up from the sections lands on the entry control. To UIKit the whole SwiftUI
        // hero is one focus item (the hosting scroll view's group container); which
        // control inside it gets focus is SwiftUI's own search, and that went to the
        // circle nearest the card («…») or over the row onto the synopsis (Sasha,
        // 2026-11-17). Focus is already in the hero here, so this is a move between
        // two SwiftUI controls, not a write that pulls focus out of a UIKit card.
        if inDetails, old == nil, target != actionEntryTarget,
           target == .plot || target.isActionControl {
          FocusLog.decision("hero: up from the sections landed on \(target), entry is \(actionEntryTarget)")
          inDetails = false
          claim(actionEntryTarget, reason: "up from the sections")
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
          // Back from a page pushed over this one: focus goes back to where the viewer
          // left it (the card that opened that page) — only the player's return and a
          // return with nothing focused claim the entry control. Claiming Play here
          // unconditionally took focus off the card (focus reads nil while a UIKit card
          // holds it), so every Back landed on the hero (Sasha, 2026-11-17).
          isCovered = false
          returningAppearance = true
          claimEntryAfterReturn()
          return
        }
        claimActionEntryFocus()
      }
      .onDisappear {
        isCovered = true
        if let current = focus, current.opensPlayer {
          returnsFromPlayer = true
          playerOpener = current
        } else if let left = focusLeftPlayerControlAt, Date().timeIntervalSince(left) < 2 {
          returnsFromPlayer = true
          playerOpener = lastPlayerControl
        }
      }
      .task {
        // `.task` runs again on every appearance, after `onAppear`: on a return it took
        // Play over the control `claimEntryAfterReturn` had just given focus back to —
        // Trailer, after Menu from the trailer (Sasha, 2026-11-22).
        if returningAppearance {
          returningAppearance = false
          return
        }
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
      FocusLog.decision("hero: entry claim \(actionEntryTarget) on appearing (focus was \(focus.map { "\($0)" } ?? "nil"))")
      focus = actionEntryTarget
    }
  }

  private func claim(_ target: MediaItemFocusTarget, reason: String) {
    FocusLog.decision("hero: claim \(target) — \(reason)")
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
      lastPlayerControl = old
      // The page can be covered before focus lets go of the control.
      if isCovered {
        returnsFromPlayer = true
        playerOpener = old
      }
    }
  }

  /// Back on the page. From the main player, focus goes to the entry control — Follow
  /// when it leads, else Play / Replay — even where tvOS would restore the control that
  /// opened the player, or nothing at all because that control was rebuilt. From the
  /// trailer (or a version's pill, Shuffle) it goes back to that control, while it is
  /// still in the row: Menu from the trailer landed on Play (Sasha, 2026-11-22). From anywhere else the system's restoration stands, unless it restored
  /// nothing. Retried for a moment: the row repaints from the player's progress on the
  /// same appearance, and a control mid-transition does not take focus.
  private func claimEntryAfterReturn() {
    guard returnsFromPlayer else {
      // Back from another page: UIKit's own restore puts focus back on the card that
      // opened it, after the pop's transition. Probed at once, mid-pop, nothing was
      // focused yet, so the hero took Play over the card (round 6, 2026-11-17). Only a
      // page that is still focus-less well after the pop gets the entry control.
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(900))
        guard !isCovered, focus == nil, TVFocusProbe.nothingFocused else { return }
        claim(actionEntryTarget, reason: "back with nothing focused")
      }
      return
    }
    let opener = playerOpener
    playerOpener = nil
    Task { @MainActor in
      for delay in [0, 150, 250, 400, 500] {
        try? await Task.sleep(for: .milliseconds(delay))
        guard !isCovered else { return }
        let target = returnTarget(from: opener)
        // Already there — but keep watching through the window: on tvOS 27.2 the
        // entry control (Play) was re-asserted ~20 ms after UIKit had restored Trailer,
        // and focus landing on Play cleared `returnsFromPlayer`, so this loop stopped
        // claiming. The return is decided once, here, for the whole window.
        if focus == target { continue }
        if focus == nil || focus == .plot || focus?.isActionControl == true {
          claim(target, reason: "back from the player")
        }
      }
      returnsFromPlayer = false
    }
  }

  /// Where focus goes back to from the player: the control that opened it when that was
  /// not the main Play and it is still in the row, else the entry control.
  private func returnTarget(from opener: MediaItemFocusTarget?) -> MediaItemFocusTarget {
    let id: MediaActionID?
    switch opener {
    case .trailer: id = .trailer
    case .playAlternate: id = .playAlternate
    case .playThird: id = .playThird
    case .shuffle: id = .shuffle
    default: id = nil
    }
    guard let opener, let id, actionAppearances.contains(where: { $0.id == id }) else {
      return actionEntryTarget
    }
    return opener
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
        // Before the entry control has ever had focus, the claim is still ours to make:
        // the old control can be rebuilt by this very change (Replay leaves the white
        // chrome as Follow takes the lead), and the engine then parks focus on a view
        // `@FocusState` does not name, or on the synopsis — neither is "nothing", so the
        // old test never claimed and the page opened off Follow (#138 CI).
        let preClaim = !actionEntryClaimed && (focus == nil || focus == .plot)
        if focus == old || preClaim || (focus == nil && TVFocusProbe.nothingFocused) {
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
        .overlay(alignment: .bottom) {
          // Full width of the hero, the height of the button band. Up from a card
          // to the right of the buttons hits the guide and lands on Play (or Follow
          // when it leads), not on the ellipsis and not through the row.
          HeroButtonRowGuide(
            entryIdentifier: actionContext.promoteFollow ? "kinopub.hero.follow" : "kinopub.hero.play",
            suspended: focus?.isActionControl == true
          )
          .frame(maxWidth: .infinity)
          .frame(height: 96)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
        }
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
        .background(toolbarCrossingProbe)
#endif
    }
  }

#if !os(tvOS)
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  /// The page's side margins on a bleeding page (`PageMargins`), iOS only.
  @Environment(\.pageMargins) private var pageMargins
  /// The room between the margins at which the people's column did not fit.
  @State private var creditsOverflowWidth: CGFloat?

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
#if os(iOS)
        phoneHero
#endif
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
              .padding(.trailing, pageMargins?.trailing ?? Self.horizontalInset)
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

#if os(iOS)
  /// iPhone: the Home banner's phone hero (Sasha, 2026-11-10), reworked 2026-11-16 after
  /// a week of use. The picture runs from the top edge, sharp, taller than the banner's
  /// still, and fades into itself as blurred glass under the words — nothing blurred
  /// above it. Play sits at one place on every title, at the foot of the picture: what
  /// is above it (logo, caption, facts) grows upward from it, everything else (scores,
  /// two lines of synopsis, the playback line) follows under it. All of it centred.
  private var phoneHero: some View {
    phoneContent
      .environment(\.colorScheme, heroChromeColorScheme)
      .padding(.top, phase.topChromeInset)
      .frame(maxWidth: .infinity)
      .onGeometryChange(for: CGSize.self, of: \.size) { heroBandSize = $0 }
      .background(alignment: .top) { phoneBackdrop }
      // A clear edge where the hero ends, at the same place on every title: fading
      // into the page went muddy grey in the light appearance (Sasha, 2026-11-16).
      .clipped()
      .animation(Self.heroStateChange, value: showsPicture)
  }

  private var phoneContent: some View {
    VStack(spacing: Self.contentSpacing) {
      // Above Play, bottom-aligned in a box of fixed height: a long title or a second
      // facts line grows up over the picture and never moves Play.
      VStack(spacing: Self.contentSpacing) {
        // Over the logo, never between it and the facts (Sasha, 2026-11-16).
        if !FeatureFlags.heroStatusInFactsLine, let status = titleStatus {
          TitleStatusBadge(status.text)
            .font(Self.secondaryFont)
            // Half the gap to the logo it would have (Sasha, 2026-11-16).
            .padding(.bottom, -Self.phoneBadgeGapCut)
        }
        titleBlock
        factsLine
      }
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity)
      .frame(height: phoneAbovePlayHeight, alignment: .bottom)

      actions
        .padding(.top, Self.actionsGap)
        .padding(.bottom, Self.actionsGap)

      // Under Play every line keeps its room, filled or not — one line of scores, two of
      // synopsis, one playback line — so the hero ends at one place (Sasha, 2026-11-16).
      // The slots alone give the height; what is drawn in them never changes it.
      phoneLineSlot(lines: 1, font: Self.phoneMetaFont)
        .frame(maxWidth: .infinity)
        .overlay { scoresLine }
      phoneLineSlot(lines: Self.phonePlotLines, font: MediaItemPlotView.font)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .top) {
          if hasSynopsis {
            MediaItemPlotView(
              title: mediaItem.localizedTitle,
              plot: synopsis.plot,
              lead: synopsis.lead,
              maxLines: Self.phonePlotLines,
              centered: true,
              focus: $focus,
              popupSubtitle: popupOriginalTitle,
              summary: MediaItemSynopsisSummary(mediaItem: mediaItem, metadata: externalMetadata)
            )
          }
        }
      phoneLineSlot(lines: 1, font: Self.phoneMetaFont)
        .frame(maxWidth: .infinity)
        .overlay { playbackLine }
    }
    // Clear of the notch in landscape (`PageMargins`).
    .pageMarginPadding(fallback: Self.horizontalInset)
    .padding(.bottom, Self.bottomInset)
  }

  /// The room of `lines` lines of `font`, drawn as nothing.
  private func phoneLineSlot(lines: Int, font: Font) -> some View {
    Text(verbatim: Array(repeating: " ", count: max(lines, 1)).joined(separator: "\n"))
      .font(font)
      .hidden()
      .accessibilityHidden(true)
  }

  /// The picture's height under the bars: taller than the banner's 16:10 (Sasha,
  /// 2026-11-16: «растянуть повыше бекдропы»).
  private var phoneStillHeight: CGFloat {
    (heroBandSize.width * CompactHeroStill.tallness).rounded()
  }

  /// The box above Play, under the bars: Play's top lands at the same share of the
  /// picture on every title.
  private var phoneAbovePlayHeight: CGFloat {
    max(0, (phoneStillHeight * Self.phonePlayAt).rounded() - Self.actionsGap)
  }

  /// Where the bar takes over (`barTakesOver`): the words above Play are mostly under it.
  private var phoneWordsTop: CGFloat {
    (phoneAbovePlayHeight * 0.5).rounded()
  }

  @ViewBuilder
  private var phoneBackdrop: some View {
    let size = heroBandSize
    let still = phoneStillHeight
    ZStack(alignment: .top) {
      MediaItemPosterWash(url: heroWashURL, onOutcome: noteWash(loaded:))
      Color.black
        .opacity(!showsPicture && showsWash ? Self.posterWashDim : 0)
      Color.KinoPub.posterHeroPlate
        .opacity(usesAdaptivePosterHero ? 1 : 0)
      if !backdropCandidates.isEmpty, size.width > 0 {
        CompactHeroPicture(urls: backdropCandidates, width: size.width, height: size.height,
                           topBleed: phase.topChromeInset, stillHeight: still, fromTop: true,
                           onLoaded: { noteBackdrop(loaded: true) },
                           onFailed: { noteBackdrop(loaded: false) })
          .id(localCacheEpoch)
      }
      if showsCornerPoster, let url = heroPosterURL, still > 0 {
        let posterHeight = (still * Self.phonePosterShare).rounded()
        CachedRemoteImage(url: url, contentMode: .fit)
          .frame(width: (posterHeight * CardAspect.poster.ratio).rounded(), height: posterHeight)
          .clipShape(RoundedRectangle(cornerRadius: Self.trailingPosterCornerRadius, style: .continuous))
          .padding(.top, phase.topChromeInset)
          .transition(.opacity)
          .accessibilityHidden(true)
      }
      if !usesAdaptivePosterHero {
        // From a little way into the picture, so its top keeps its colour.
        CompactHeroScrim(start: size.height > 0
                         ? min(Self.phoneScrimMaxStart,
                               (phase.topChromeInset + still * Self.phoneScrimStillShare) / size.height)
                         : 0.38)
      }
    }
    .frame(width: size.width, height: size.height, alignment: .top)
    .clipped()
    .allowsHitTesting(false)
  }

  /// Half of what stands between the status capsule and the logo: the stack's
  /// spacing and the title block's own top inset.
  static let phoneBadgeGapCut: CGFloat = (contentSpacing + bottomInset / 1.5) / 2
  /// Play's top, as a share of the picture under the bars.
  static let phonePlayAt: CGFloat = 0.88
  /// A poster-only title's poster, as a share of the picture's height.
  static let phonePosterShare: CGFloat = 0.5
  /// Synopsis lines under Play before «ЕЩЁ» (Sasha, 2026-11-16).
  static let phonePlotLines = 2
  /// The shade starts this far down the picture…
  static let phoneScrimStillShare: CGFloat = 0.35
  /// …and never lower than this share of the hero.
  static let phoneScrimMaxStart: CGFloat = 0.5
#endif

  /// The phone's one centred column (Sasha, 2026-11-10) instead of the leading one.
  private var centersColumn: Bool {
#if os(iOS)
    phoneHeroGrows
#else
    false
#endif
  }

  private var columnAlignment: HorizontalAlignment { centersColumn ? .center : .leading }
  private var columnTextAlignment: TextAlignment { centersColumn ? .center : .leading }

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
  /// synopsis and the buttons below stay clear. A narrower window gets a smaller share, so
  /// the synopsis beside the poster keeps a reading width (Sasha, 2026-11-09).
  static func posterAccentSize(in bandSize: CGSize) -> CGSize {
    let share = posterAccentBandShares.first { bandSize.width >= $0.minWidth }?.share
      ?? posterAccentBandShares.last?.share ?? 0.5
    let height = max(0, bandSize.height * share)
    return CGSize(width: height * CardAspect.poster.ratio, height: height)
  }

  /// Band width breakpoints, widest first: a full Mac window or a landscape iPad Pro,
  /// a half-screen window or a portrait iPad, anything narrower.
  static let posterAccentBandShares: [(minWidth: CGFloat, share: CGFloat)] = [
    (1200, 0.5), (900, 0.42), (0, 0.34)
  ]
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

#if !os(tvOS)
  /// Whether the hero's bottom edge has gone up under the window toolbar (Mac) or the
  /// navigation bar (iPhone, iPad). One write per crossing, read by the title page's bar
  /// alone.
  /// Mac: once the whole hero is under the toolbar. iPhone: once its words reach the
  /// bar — the hero is a screen tall there, and a bare bar let the synopsis run under the
  /// clock while the picture was still partly under it.
  private func barTakesOver(heroFrame frame: CGRect) -> Bool {
#if os(iOS)
    if phoneHeroGrows {
      return frame.minY <= -phoneWordsTop
    }
#endif
    return frame.maxY <= phase.topChromeInset
  }

  private var toolbarCrossingProbe: some View {
    GeometryReader { proxy in
      let frame = proxy.frame(in: .named(MediaItemLayout.scrollSpace))
      let past = barTakesOver(heroFrame: frame)
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

  /// A picture, or the blurred poster standing in for one — once it has drawn, not
  /// merely because there is a URL for it.
  private var hasArtBackdrop: Bool {
    showsPicture || showsWash
  }

  /// The blurred poster drew. Kept in the phase, so a page rebuilt on coming back
  /// starts from what it already knew.
  private var showsWash: Bool {
    guard let heroWashURL, let outcome = phase.washOutcome else { return false }
    return outcome.key == heroWashURL.absoluteString && outcome.loaded
  }

  private func noteWash(loaded: Bool) {
    guard let key = heroWashURL?.absoluteString else { return }
    if let outcome = phase.washOutcome, outcome.key == key, outcome.loaded == loaded { return }
    withAnimation(Self.heroStateChange) {
      phase.washOutcome = (key, loaded)
    }
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
      MediaItemPosterWash(url: heroWashURL, onOutcome: noteWash(loaded:))
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
        .opacity(!showsPicture && showsWash ? Self.posterWashDim : 0)
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
  /// iPad takes the Mac's: fading into the page background went muddy grey in the light
  /// appearance, right under the white-on-glass buttons (Sasha, 2026-11-16) — the same
  /// fault the phone hero had, fixed there with a clean edge too.
  private var scrollingScrim: some View {
    ZStack {
      HeroLegibilityTexture(tone: .black)
      bottomShade
    }
  }

  /// A little more dark under the words than the shared texture gives (Sasha,
  /// 2026-11-09), and about twice that while the trailer plays behind them — moving
  /// pictures fight the text harder than a still.
  private var bottomShade: some View {
    LinearGradient(stops: [
      .init(color: .clear, location: Self.bottomShadeTop),
      .init(color: .black.opacity(trailer.isReady ? Self.bottomShadeTrailer : Self.bottomShadeStill),
            location: 1)
    ], startPoint: .top, endPoint: .bottom)
    .allowsHitTesting(false)
    .animation(.easeInOut(duration: 0.6), value: trailer.isReady)
  }

  static let bottomShadeTop: CGFloat = 0.4
  static let bottomShadeStill: Double = 0.25
  static let bottomShadeTrailer: Double = 0.5
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
    VStack(alignment: columnAlignment, spacing: 0) {
      heroTitleRow
      Spacer(minLength: 0)
      heroBottomBlock
    }
#if os(iOS)
    // Clear of the iPad's sidebar and the iPhone's notch, as every section under the
    // hero (`PageMargins`).
    .pageMarginPadding(fallback: Self.horizontalInset)
    .padding(.bottom, Self.bottomInset)
#else
    .padding(.bottom, Self.horizontalInset)
    .padding(.horizontal, Self.bottomInset)
#endif
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centersColumn ? .top : .topLeading)
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
#if !os(tvOS)
    // Wider than the band between the margins: the written column could not give way
    // (the iPad's open sidebar, 2026-11-16) and the people ran off the screen. Drop
    // their column for this width.
    .onGeometryChange(for: CGFloat.self, of: \.size.width) { width in
      guard showsCreditsColumn, heroBandSize.width > 0 else { return }
      if width > bandWidthBetweenMargins + 1 {
        creditsOverflowWidth = bandWidthBetweenMargins
      }
    }
#endif
  }

  @ViewBuilder
  private var leadingBottomColumn: some View {
#if os(iOS)
    VStack(alignment: columnAlignment, spacing: Self.contentSpacing) {
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
    VStack(alignment: columnAlignment, spacing: Self.contentSpacing) {
      // Above the facts, not in them, for now (Sasha, 2026-11-09); the Diagnostics
      // switch puts it back first in the line.
      if !FeatureFlags.heroStatusInFactsLine, let status = titleStatus {
        TitleStatusBadge(status.text)
          .font(Self.secondaryFont)
          .padding(.bottom, Self.contentSpacing / 2)
      }
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
          // Not on a phone: there the poster is above the words, not beside them.
          expandsFully: showsCornerPoster && !centersColumn,
          focus: $focus,
          popupSubtitle: popupOriginalTitle,
          summary: MediaItemSynopsisSummary(mediaItem: mediaItem, metadata: externalMetadata)
        )
        .padding(.vertical, Self.contentSpacing / 2)
#endif
      }
      playbackLine
    }
    .frame(maxWidth: .infinity, alignment: centersColumn ? .center : .leading)
#if os(tvOS)
    // Separate from the action row so Down leaves this section at the page's
    // `defaultFocus` (Play), not the geometrically nearest trailing circle.
    .focusSection()
#endif
  }

  @ViewBuilder
  private var heroTitleRow: some View {
    if showsCornerPoster, !centersColumn {
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
    // The phone's caption carries the country and keeps its own width: capped to the
    // logo it wrapped at « · США» (Sasha, 2026-11-16).
    SecondLineCappedToFirst(capsWidth: resolvedTitleLogoMark == .logo && !centersColumn,
                            alignment: columnAlignment) {
      TitleLogoSlot(
        resolution: TitleLogoResolution(
          url: titleLogoURL,
          lookupComplete: externalMetadataLoaded
        ),
        maxWidth: logoMaxWidth,
        maxHeight: logoMaxHeight,
        textMaxWidth: .infinity,
        alignment: columnAlignment,
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
    .modifier(TitleBlockHorizontalBounds(reservePosterColumn: showsCornerPoster && !centersColumn,
                                         alignment: centersColumn ? .center : .leading))
  }

  /// The logo's box. Phone: the Home banner's phone budget, 70% × 26% of the width.
  private var logoMaxWidth: CGFloat {
#if os(iOS)
    if centersColumn, heroBandSize.width > 0 { return (heroBandSize.width * CompactHeroLogo.widthShare).rounded() }
#endif
    return Self.logoMaxWidth
  }

  private var logoMaxHeight: CGFloat {
#if os(iOS)
    if centersColumn, heroBandSize.width > 0 { return (heroBandSize.width * CompactHeroLogo.heightShare).rounded() }
#endif
    return Self.logoMaxHeight
  }

  private var titlePrimaryText: some View {
    Text(mediaItem.localizedTitle)
      .font(Self.titleFont)
      .foregroundStyle(heroPrimaryForeground)
      .multilineTextAlignment(columnTextAlignment)
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
    if centersColumn, let caption = phoneCaption {
      // One text, one line, so the other name arriving morphs into it rather than
      // fading in over the country; a long name gives way in its middle and the
      // country at the end stays.
      Text(verbatim: caption)
        .lineLimit(1)
        .truncationMode(.middle)
        .contentTransition(.interpolate)
        .animation(.smooth, value: caption)
        .font(Self.phoneMetaFont)
        .foregroundStyle(heroSecondaryForeground)
        .shadow(color: .black.opacity(titleShadowOpacity), radius: 8, x: 0, y: 2)
    } else if let line = supplementaryUnderTitle {
      Text(line)
        .font(centersColumn ? Self.phoneMetaFont : Self.secondaryFont)
        .foregroundStyle(heroSecondaryForeground)
        .multilineTextAlignment(columnTextAlignment)
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
    guard (centersColumn ? phoneCaption : supplementaryUnderTitle) != nil else { return 0 }
    switch resolvedTitleLogoMark {
    case .logo: return Self.contentSpacing * 1.5
    case .text: return Self.contentSpacing
    case .empty: return 0
    }
  }

  /// The phone's caption: the other name, then where it was made — the name alone does
  /// not always say in what language it is (Sasha, 2026-11-16): «Dexter: Resurrection · США».
  private var phoneCaption: String? {
    let parts = [supplementaryUnderTitle, phoneCountry].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
    MediaScores(mediaItem)
      .preferringIMDb(externalMetadata.relayedIMDbRating, votes: externalMetadata.relayedIMDbVotes)
      .adding(tmdb: externalMetadata.tmdbRating,
              tmdbVotes: externalMetadata.tmdbVotes)
      .adding(extras: RatingSources.lineExtras(externalMetadata))
  }

  // MARK: - Facts, scores, playback, people

  /// The status capsule, then the facts in blocks that wrap whole — never a genre list
  /// broken across two lines.
  @ViewBuilder
  private var factsLine: some View {
    if centersColumn {
      phoneFactsLine
    } else {
      regularFactsLine
    }
  }

  @ViewBuilder
  private var regularFactsLine: some View {
    let status = FeatureFlags.heroStatusInFactsLine ? titleStatus : nil
    let blocks = factBlocks
    // On a phone the age rating closes the playback line instead (Sasha, 2026-11-16).
    let rating = centersColumn ? nil : ageRating.flatMap { $0.isEmpty ? nil : $0 }
    if status != nil || !blocks.isEmpty || rating != nil {
      AboutFlowLayout(spacing: Self.metaSpacing, lineSpacing: Self.contentSpacing / 2,
                      centersRows: centersColumn) {
        if let status {
          TitleStatusBadge(status.text)
        }
        ForEach(blocks, id: \.self) { block in
          Text(verbatim: block)
            .lineLimit(1)
            .modifier(HeroVibrantLabel(isOverArt: isChromeOverArt))
        }
        // Always: the «show age rating» preference is the poster's, not this line's
        // (Sasha, 2026-11-08). Drawn where `badges/` has the mark (2026-11-09).
        if let rating {
          if let asset = MediaBadgeImages.ageRatingAssetName(rating) {
            MediaBadgeImages([asset])
              .modifier(HeroVibrantLabel(isOverArt: isChromeOverArt))
          } else {
            Text(verbatim: rating)
              .lineLimit(1)
              .modifier(HeroVibrantLabel(isOverArt: isChromeOverArt))
          }
        }
      }
      .font(Self.secondaryFont)
      .foregroundStyle(heroMetaForeground)
    }
  }

  /// The chrome is the forced-dark kind, over a picture or the blurred poster — where
  /// the meta lines go vibrant (`HeroVibrantLabel`).
  private var isChromeOverArt: Bool {
#if os(tvOS)
    heroChromeColorScheme == .dark
#else
    hasArtBackdrop
#endif
  }

  private var titleStatus: TitleStatus? {
    TitleStatus.resolve(mediaItem, externalMetadata, awaitedEpisodeAirDate: awaitedEpisodeAirDate)
  }

  /// «Аниме-сериал 2025–26 окончен», «3 сезона», «Триллер, драма, спорт», «США», «18+».
  /// A film: «Мультфильм 2026», «2ч 53м», genres, country. The kind is the Home hero's
  /// vocabulary (`MediaPresentationProfile.kindTitleKey`), and the genre it already says
  /// (anime, animation, documentary) is not repeated after it.
  private var factBlocks: [String] { factBlocks() }

  /// `genreLimit` genres at most; `place` false leaves the country out (the phone writes
  /// it beside the original title).
  private func factBlocks(genreLimit: Int = MediaItemHeroView.genreLimit, place showsPlace: Bool = true) -> [String] {
    let card = MediaCard(mediaItem)
    let profile = mediaItem.presentation
    var blocks: [String] = []

    let kindKey = profile.kindTitleKey(isSeries: isSeries)
    // A plain film says nothing about being a film: the runtime says it. On a phone a
    // series does not say it either — the season count and the episodes under the hero
    // do; a documentary series stays one by its genre (Sasha, 2026-11-16).
    let dropsKind = kindKey == "Kind_movies_One" || (centersColumn && isSeries)
    let kind = dropsKind ? nil : kindKey.localized
    let years = isSeries
      ? SeriesFacts.heroYears(mediaItem, externalMetadata, fallbackSpan: card.bannerYearSpan)
      : (mediaItem.year > 0 ? String(mediaItem.year) : nil)
    // «Сериал с 2013 в эфире», «Документальный фильм 2011»: the kind first with its
    // capital, then the years, then where the series stands, whatever anyone knows of it
    // (Sasha, 2026-11-09).
    let statusKey = isSeries ? SeriesFacts.shortStatusKey(mediaItem, externalMetadata) : nil
    let status = statusKey?.localized
    // «с 2011 в эфире» reads as one; «с 2011 продлён» does not, so the word stands apart.
    let statusJoins = statusKey != "MediaItem_StatusReturningShort"
    let head = [kind, years, statusJoins ? status : nil].compactMap { $0 }
    if !head.isEmpty { blocks.append(head.joined(separator: " ")) }
    if !statusJoins, let status { blocks.append(status) }

    if isSeries {
      let seasons = mediaItem.seasons ?? []
      let episodes = seasons.reduce(0) { $0 + $1.episodes.count }
      if seasons.count > 1, let text = SeasonCountText(seasons.count)?.formatted() {
        blocks.append(text)
      } else if let text = EpisodesLeftText(episodes)?.formatted() {
        blocks.append(text)
      }
    }

    // Not the genre the kind already says: «Концерт  …, концерт», «ТВ-шоу  Развлекательные».
    let restated = kind == nil ? [] : Set(card.genres.filter { profile.kindGenreIDs.contains($0.id) }
      .map { $0.name.value(languageCode: MediaLanguage.current.rawValue) })
    let genres = card.usefulGenres(limit: genreLimit + restated.count,
                                   omittingDocumentary: kind != nil && profile.kind == .documentary)
      .filter { !restated.contains($0) }
      .prefix(genreLimit)
    let place = showsPlace ? phoneCountry : nil
    // A concert is told apart by where it was played, not by its genres — the artist's
    // are the same on every live record — so the place goes first (Sasha, 2026-11-09).
    let placeLeads = profile.kind == .concert
    if placeLeads, let place { blocks.append(place) }
    if let first = genres.first {
      let rest = genres.dropFirst().map { $0.lowercased() }
      blocks.append(([first] + rest).joined(separator: ", "))
    }
    if !placeLeads, let place { blocks.append(place) }
    return blocks
  }

  /// The first production country.
  private var phoneCountry: String? {
    mediaItem.countryNames.first.flatMap { $0.isEmpty ? nil : $0 }
  }

  /// The phone's facts: one line under the original title, never two — a second line
  /// pushed the logo up (Sasha, 2026-11-16). Genres give way one by one; the country
  /// is beside the original title (`phoneCaption`).
  /// Between the facts' blocks: the stack's spacing, as spaces. Outside the iOS-only
  /// block: the facts line is built on every platform.
  static let phoneFactsSeparator = "   "

  @ViewBuilder
  private var phoneFactsLine: some View {
    let status = FeatureFlags.heroStatusInFactsLine ? titleStatus : nil
    ViewThatFits(in: .horizontal) {
      ForEach((0...Self.genreLimit).reversed(), id: \.self) { limit in
        HStack(spacing: Self.metaSpacing) {
          if let status {
            TitleStatusBadge(status.text)
          }
          // One text, so the details' fuller line morphs out of the listing's.
          Text(verbatim: factBlocks(genreLimit: limit, place: false).joined(separator: Self.phoneFactsSeparator))
            .contentTransition(.interpolate)
        }
        .lineLimit(1)
        .fixedSize()
      }
    }
    .animation(.smooth, value: factBlocks(place: false))
    .font(Self.phoneMetaFont)
    .foregroundStyle(heroMetaForeground)
    .modifier(HeroVibrantLabel(isOverArt: isChromeOverArt))
  }

  /// How long what Play offers runs — the episode it opens; for a film the version in focus, else the last one that was,
  /// else the first not yet watched (Sasha, 2026-10-25); the film's own runtime otherwise.
  private var runtimeText: String? {
    if isSeries {
      guard let (_, episode) = mediaItem.primaryEpisode, episode.duration > 0 else { return nil }
      return RuntimeText(seconds: episode.duration).formatted(Self.runtimeLength)
    }
    if let version = runtimeVersion, version.duration > 0 {
      return RuntimeText(seconds: version.duration).formatted(Self.runtimeLength)
    }
    return mediaItem.mediaEntity.runtime.flatMap { RuntimeText(seconds: $0).formatted(Self.runtimeLength) }
  }

  /// The scores and kino.pub's views on one line. When the whole of it does not fit, it
  /// gives way in steps instead of squeezing (Sasha, 2026-11-09): the vote counts go
  /// first, then the views, then the sources with under a tenth of the votes and the
  /// Popcornmeter, then the smallest of what is left. Tomatometer and Metascore stay
  /// at the end throughout.
  @ViewBuilder
  private var scoresLine: some View {
    // Views alone are no line of their own: they close the playback line (Sasha, 2026-11-16).
    if centersColumn, lineScores.hasDisplayableScore || mediaItem.views > 0 {
      // The phone: IMDb first, scales after numbers that could mislead, no vote counts,
      // the views last; the tail gives way when the line is full (Sasha, 2026-11-16).
      ViewThatFits(in: .horizontal) {
        // IMDb's and Kinopoisk's own counts, as on the Home banner; then one total.
        ForEach([false, true], id: \.self) { total in
          phoneScoresRow(limit: nil, views: true, votes: true, totalVotes: total)
          phoneScoresRow(limit: nil, views: false, votes: true, totalVotes: total)
          // The niche audiences (Douban, MyShows, Trakt…) give way before the critics and
          // before the counts.
          phoneScoresRow(limit: nil, views: true, others: false, votes: true, totalVotes: total)
          phoneScoresRow(limit: nil, views: false, others: false, votes: true, totalVotes: total)
        }
        phoneScoresRow(limit: nil, views: false, others: false)
        ForEach([3, 2, 1], id: \.self) { limit in
          phoneScoresRow(limit: limit, views: false, others: false)
        }
      }
      .font(Self.phoneMetaFont)
      .foregroundStyle(heroMetaForeground)
    } else if lineScores.hasDisplayableScore {
      ViewThatFits(in: .horizontal) {
        scoresRow(votes: true, views: true)
        scoresRow(votes: false, views: true)
        scoresRow(votes: false, views: false)
        ForEach([0, 4, 3, 2, 1], id: \.self) { limit in
          scoresRow(votes: false, views: false, compactLimit: limit)
        }
      }
      .font(Self.secondaryFont)
      .foregroundStyle(heroMetaForeground)
    }
  }

  private func phoneScoresRow(limit: Int?, views showsViews: Bool, others: Bool = true,
                              votes: Bool = false, totalVotes: Bool = false) -> some View {
    let views = mediaItem.views
    // No scores at all: the views are the line.
    let viewsShown = showsViews || !lineScores.hasDisplayableScore
    return HStack(spacing: Self.metaSpacing) {
      MediaScoresView(lineScores, limit: limit, showsVotes: votes, phoneLine: true,
                      phoneLineOthers: others, phoneLineTotalVotes: totalVotes)
      if viewsShown, views > 0 {
        HStack(spacing: Self.glyphSpacing) {
          Image(systemName: Self.viewsSymbol)
          Text(verbatim: formattedViewCount(views))
        }
        .modifier(HeroVibrantLabel(isOverArt: isChromeOverArt))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("MediaItem_Views") + Text(verbatim: " " + views.formatted()))
      }
    }
    .fixedSize()
  }

  private func scoresRow(votes: Bool, views showsViews: Bool, compactLimit: Int? = nil) -> some View {
    let views = mediaItem.views
    return HStack(spacing: Self.metaSpacing) {
      if lineScores.hasDisplayableScore {
        if FeatureFlags.combinedRatingEnabled, let rating = lineScores.aggregate {
          RatingBadgeView(rating: rating)
          MediaScoresView(lineScores, showsVotes: votes, deduplicateAgainstAggregate: true, detailLine: true,
                          compactLimit: compactLimit)
        } else {
          // No aggregate: each score keeps its own logo rather than becoming one number.
          MediaScoresView(lineScores, showsVotes: votes, detailLine: true, compactLimit: compactLimit)
        }
      }
      // kino.pub's own count, last (Sasha, 2026-11-09): the eyes of the ratings
      // section's views tile.
      if showsViews, views > 0 {
        HStack(spacing: Self.glyphSpacing) {
          Image(systemName: Self.viewsSymbol)
          Text(verbatim: formattedViewCount(views))
        }
        .modifier(HeroVibrantLabel(isOverArt: isChromeOverArt))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("MediaItem_Views") + Text(verbatim: " " + views.formatted()))
      }
    }
    .fixedSize()
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
    // Multi-season: «1 сезон, 8 серия: Title» — Sasha circled the missing season (2026-11-14).
    let seasonCount = mediaItem.seasons?.count ?? 0
    let seasonNumber = mediaItem.primaryEpisode.map {
      $0.season.titleSeasonNumber ?? $0.season.number
    }
    var lead: String = {
      if seasonCount > 1, let seasonNumber {
        if let name {
          return String(format: "MediaItem_EpisodeLeadWithSeason".localized,
                        seasonNumber, episode.number, name)
        }
        return String(format: "MediaItem_EpisodeLeadSeasonNumber".localized,
                      seasonNumber, episode.number)
      }
      if let name {
        return String(format: "MediaItem_EpisodeLead".localized, episode.number, name)
      }
      return String(format: "MediaItem_EpisodeLeadNumber".localized, episode.number)
    }()
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
    if centersColumn {
      phonePlaybackLine
    } else {
      regularPlaybackLine
    }
  }

  /// The phone's playback line, always one line, short the way Kinopoisk writes it
  /// (Sasha, 2026-11-16): «45 мин  Рус, Eng [DUB] [CC] [4K] [16+]». The details are a
  /// tap away in the synopsis sheet. What does not fit gives way from the front of the
  /// tags: the voicing, then the runtime, then all but the first language.
  @ViewBuilder
  private var phonePlaybackLine: some View {
    let runtime = runtimeText
    let languages = audioLanguageCodes
    let voicing = preferredVoicingTag
    let captions = subtitleSummary != nil
    let rating = ageRating.flatMap { $0.isEmpty ? nil : $0 }
    // The views stand in the scores' slot when there are no scores (`scoresLine`).
    let views = 0
    let badges = MediaCapabilityBadges.from(item: mediaItem).detailBadgeAssets
      + (rating.flatMap(MediaBadgeImages.ageRatingAssetName).map { [$0] } ?? [])
    let typedRating = rating.flatMap { MediaBadgeImages.ageRatingAssetName($0) == nil ? $0 : nil }
    if runtime != nil || !languages.isEmpty || !badges.isEmpty || typedRating != nil {
      ViewThatFits(in: .horizontal) {
        phonePlaybackRow(runtime: runtime, languages: languages, voicing: voicing, captions: captions,
                         badges: badges, typedRating: typedRating, views: views)
        phonePlaybackRow(runtime: runtime, languages: languages, voicing: nil, captions: captions,
                         badges: badges, typedRating: typedRating, views: views)
        phonePlaybackRow(runtime: nil, languages: languages, voicing: nil, captions: captions,
                         badges: badges, typedRating: typedRating, views: views)
        phonePlaybackRow(runtime: nil, languages: Array(languages.prefix(1)), voicing: nil, captions: captions,
                         badges: badges, typedRating: typedRating, views: 0)
      }
      .font(Self.phoneMetaFont)
      .foregroundStyle(heroMetaForeground)
      .modifier(HeroVibrantLabel(isOverArt: isChromeOverArt))
    }
  }

  private func phonePlaybackRow(runtime: String?, languages: [String], voicing: String?, captions: Bool,
                                badges: [String], typedRating: String?, views: Int) -> some View {
    HStack(spacing: Self.metaSpacing) {
      if let runtime {
        Text(verbatim: runtime)
      }
      if !languages.isEmpty {
        Text(verbatim: languages.joined(separator: ", "))
      }
      if let voicing {
        PlaybackTag(voicing)
      }
      if captions {
        MediaBadgeImages(["CC"])
      }
      if !badges.isEmpty {
        MediaBadgeImages(badges)
      }
      if let typedRating {
        PlaybackTag(typedRating)
      }
      if views > 0 {
        HStack(spacing: Self.glyphSpacing) {
          Image(systemName: Self.viewsSymbol)
          Text(verbatim: formattedViewCount(views))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("MediaItem_Views") + Text(verbatim: " " + views.formatted()))
      }
    }
    .lineLimit(1)
    .fixedSize()
  }

  /// The viewer's languages among the sound tracks, each by the first three letters of
  /// its own name: «Рус», «Eng», «Укр».
  private var audioLanguageCodes: [String] {
    let tracks = mediaItem.detailAudioTracks.filter { !$0.isAudioDescription }
    // The viewer's languages, then the original sound's — «Рус, Eng» — and for a title
    // with neither (a concert's one track), whatever language its first track is in.
    let originals = tracks
      .filter { $0.typeId.flatMap(VoiceType.init(rawValue:)) == .original }
      .map { SubtitleTracks.languageKey($0.lang) }
    var seen = Set<String>()
    var keys = (viewerLanguages + originals).filter { key in
      !key.isEmpty && tracks.contains { SubtitleTracks.languageKey($0.lang) == key } && seen.insert(key).inserted
    }
    if keys.isEmpty, let first = tracks.first.map({ SubtitleTracks.languageKey($0.lang) }), !first.isEmpty {
      keys = [first]
    }
    return keys.prefix(Self.phoneLanguageLimit).compactMap { key -> String? in
      let own = Locale(identifier: key).localizedString(forLanguageCode: key) ?? languageName(key)
      guard let own, !own.isEmpty else { return nil }
      let short = own.prefix(3)
      return short.prefix(1).uppercased() + short.dropFirst()
    }
  }

  static let phoneLanguageLimit = 3

  /// kino.pub's short word for the best voicing in the viewer's first language that is
  /// voiced at all: «DUB», «MVO», «VO». Nil for the original sound.
  private var preferredVoicingTag: String? {
    let tracks = mediaItem.detailAudioTracks.filter { !$0.isAudioDescription }
    for key in viewerLanguages {
      let inLanguage = tracks.filter { SubtitleTracks.languageKey($0.lang) == key }
      guard let best = inLanguage.min(by: { rank($0) < rank($1) }),
            let voice = best.typeId.flatMap(VoiceType.init(rawValue:)) else { continue }
      if voice == .original || voice == .undetermined { continue }
      return voice.shortTitle
    }
    return nil
  }

  @ViewBuilder
  private var regularPlaybackLine: some View {
    let runtime = runtimeText
    let badges = MediaCapabilityBadges.from(item: mediaItem).detailBadgeAssets
    let audio = audioSummary
    let subtitles = subtitleSummary
    // kino.pub's views, when there is no score for them to follow (`scoresLine`).
    let views = lineScores.hasDisplayableScore ? 0 : mediaItem.views
    if runtime != nil || !badges.isEmpty || audio != nil || subtitles != nil || views > 0 {
      AboutFlowLayout(spacing: Self.metaSpacing, lineSpacing: Self.contentSpacing / 2,
                      centersRows: centersColumn) {
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
        if views > 0 {
          HStack(spacing: Self.glyphSpacing) {
            Image(systemName: Self.viewsSymbol)
            Text(verbatim: formattedViewCount(views))
          }
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(Text("MediaItem_Views") + Text(verbatim: " " + views.formatted()))
        }
      }
      .lineLimit(1)
      .font(Self.secondaryFont)
      .foregroundStyle(heroMetaForeground)
      .modifier(HeroVibrantLabel(isOverArt: isChromeOverArt))
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

  /// The column on the right, on every screen but a phone's — never moved under the
  /// synopsis: the synopsis and the column both narrow instead (Sasha, 2026-11-09). Beside
  /// a corner poster it sits left of the poster's column.
  private var showsCreditsColumn: Bool {
    guard !creditLines.isEmpty else { return false }
#if os(tvOS)
    return true
#else
    // And only where it fits beside the written column: with the iPad's sidebar open
    // the scores line alone left it no room, and it ran off the screen (2026-11-16).
    // Hidden for the width it overflowed at; any other width (a turn, the sidebar
    // closing) tries the column again.
    guard !phoneHeroGrows else { return false }
    return creditsOverflowWidth == nil || creditsOverflowWidth != bandWidthBetweenMargins
#endif
  }

#if !os(tvOS)
  /// The band between the page margins — keyed on this, not on the band: the band is as
  /// wide with the iPad's sidebar open as closed, the room beside it is not.
  private var bandWidthBetweenMargins: CGFloat {
    let margins = pageMargins.map { $0.leading + $0.trailing } ?? 2 * Self.contentHorizontalInset
    return (heroBandSize.width - margins).rounded()
  }

  /// The band's width less the page margins, the gutter and the corner poster: what the
  /// written column and the people's column share.
  private var creditsRoom: CGFloat? {
    guard heroBandSize.width > 0 else { return nil }
    let margins = pageMargins.map { $0.leading + $0.trailing } ?? 2 * Self.contentHorizontalInset
    var available = heroBandSize.width - margins - Self.columnGutter
    if showsCornerPoster { available -= posterColumnWidth }
    return available
  }
#endif

  /// A little under half the synopsis measure at most, as the Apple TV app's column is
  /// beside its text; a share of what is left beside the poster and the margins once
  /// the window is narrower than both at full width.
  private var creditsColumnWidth: CGFloat {
    let widest = MediaItemPlotView.maxWidth * Self.creditsColumnRatio
#if os(tvOS)
    return widest
#else
    guard let available = creditsRoom, available > 0 else { return widest }
    return min(widest, (available * Self.creditsColumnShare).rounded())
#endif
  }

  /// One line per role, each wrapping on its own: «В ролях Мэтт Дэймон, Том Холланд,
  /// Энн Хэтэуэй», then «Режиссёр Кристофер Нолан» on a new line (Sasha, 2026-11-08).
  private var creditsBlock: some View {
    VStack(alignment: .leading, spacing: Self.creditLineSpacing) {
      ForEach(creditLines, id: \.role) { line in
        Text(creditLine(line))
          .lineSpacing(Self.creditLeading)
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
    MediaActionRow(alignment: columnAlignment) {
      ForEach(actionAppearances) { appearance in
        actionControl(for: appearance)
          .accessibilityIdentifier("kinopub.hero.\(appearance.id.rawValue)")
#if os(tvOS)
          // Where the button-row guide finds the entry control's focus item.
          .background {
            if appearance.id == (actionContext.promoteFollow ? .follow : .play) {
              HeroEntryMarker()
            }
          }
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
    // Seeds the first focus only. Up from a card under the row is the full-width
    // guide on the hero (`HeroButtonRowGuide`), which redirects to this same control
    // (Sasha, 2026-10-11) — a `defaultFocus` priority does not run again on re-entry.
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
#if os(iOS)
    .onChange(of: mediaItem.trailerURL) { _, url in
      guard awaitsTrailer, url != nil else { return }
      awaitsTrailer = false
      navigationState.push(Route.trailerPlayer(mediaItem, token: UUID()))
    }
#endif
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
    // Multi-version films use one Play + sheet; concerts / parts keep version pills.
    let versionPills = offersVersionPills
      ? choices.map {
        MediaActionVersion(name: $0.name, playback: $0.playbackButtonContent,
                           isMain: mediaItem.isMainVersion($0))
      }
      : []
    return MediaActionContext(
      playback: playback,
      kind: mediaItem.presentation.kind,
      isSeries: isSeries,
      isBookmarked: isBookmarked,
      isFollowing: isInWatchlist,
      showsMarkWatched: showsWatchedButton && !promote,
      // The listing already says whether there is one: no waiting for the details call
      // to show the button (Sasha, 2026-11-16).
      showsTrailer: showsTrailer,
      showsFollow: isSeries && onToggleWatchlist != nil && !promote,
      download: downloadPhase,
      showsShuffle: showsShuffleButton && !promote,
      showsMore: showsMore,
      promoteFollow: promote,
      versions: versionPills,
      choosesVersion: presentsVersionPicker,
      loading: loadingActions,
      seasonCount: mediaItem.seasons?.count
    )
  }

  /// iPhone: as soon as the listing names a trailer (its stream comes with the details;
  /// a press waits for it, `trailerControl`). Elsewhere once it can play.
  private var showsTrailer: Bool {
#if os(iOS)
    mediaItem.trailerURL != nil || mediaItem.trailer != nil
#else
    mediaItem.trailerURL != nil
#endif
  }

  /// Concerts and multi-part titles still get a play pill per choice. A film that
  /// ships as `subtype: multi` opens one Play and the version sheet instead.
  private var offersVersionPills: Bool {
    !mediaItem.isMultiVersion && mediaItem.playChoices.count > 1
  }

  private var presentsVersionPicker: Bool {
    mediaItem.isMultiVersion && mediaItem.playbackVariants.count > 1
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
#elseif os(iOS)
    let row = MediaActionCatalog.row(for: actionContext)
    // iPad: the Mac's row — Mark as Watched is in «…» (Sasha, 2026-11-16).
    guard phoneHeroGrows else { return row.filter { $0.id != .markWatched } }
    // iPhone: what plays, and Bookmarks, as on the Home banner (Sasha, 2026-11-10,
    // 2026-11-16). The bell is in the navigation bar, top right; Download and Mark as
    // Watched in «…»; Shuffle and starting over in Play's long press. Trailer says its
    // word alone, as Apple's does.
    return row
      .filter { appearance in
        switch appearance.id {
        case .markWatched, .download, .shuffle, .more: false
        // The bell is in the bar, top right; Bookmarks stay here, as on the Home banner.
        case .follow: appearance.chrome != .circle
        default: true
        }
      }
      .map { appearance in
        var compact = MediaActionCatalog.compactPlay(appearance)
        if compact.id == .trailer, compact.title != nil { compact.systemImage = "" }
        return compact
      }
#else
    MediaActionCatalog.row(for: actionContext)
#endif
  }

#if os(iOS)
  /// Play's long press: start over, and a random unwatched episode (Sasha, 2026-11-10).
  /// Starting over is offered where Play shows a resume bar — the same answer as the bar.
  @ViewBuilder
  private func playMenu(for target: any PlayableItem, appearance: MediaActionAppearance) -> some View {
    if appearance.progress != nil {
      Button {
        let token = UUID()
        PlaybackSession.shared.startFromBeginning(token: token)
        navigationState.push(.player(target, token: token))
      } label: {
        Label("MediaAction_PlayFromBeginning", systemImage: "backward.end")
      }
    }
    if isSeries, randomUnwatchedEpisode != nil {
      Button {
        guard let episode = randomUnwatchedEpisode else { return }
        navigationState.push(.player(episode, token: UUID()))
      } label: {
        Label("MediaAction_RandomEpisode", systemImage: "shuffle")
      }
    }
  }
#endif

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
          .frame(minWidth: playMinWidth(appearance))
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

  /// Play, or one version's pill — same control, different target. A multi-version
  /// film's single Play opens «Choose a Version» instead of jumping straight in.
  @ViewBuilder
  private func playControl(_ appearance: MediaActionAppearance) -> some View {
    if presentsVersionPicker, appearance.id == .play {
      Button {
        showsVersionPicker = true
      } label: {
        MediaActionLabel(appearance)
          .frame(minWidth: playMinWidth(appearance))
      }
      .mediaActionStyle(appearance)
      .focused($focus, equals: .play)
      .accessibilityLabel(Text(appearance.accessibilityLabel))
      .accessibilityHint(Text("Choose a Version"))
      .task(id: mediaItem.playbackVariants.map(\.id)) {
        for variant in mediaItem.playbackVariants.prefix(3) {
          await PlaybackPreflight.shared.warm(variant)
        }
      }
    } else {
      let target = playTarget(for: appearance.id)
      PlayerLink(route: linkProvider.player(for: target), item: target, mode: .media) {
        MediaActionLabel(appearance)
          .frame(minWidth: playMinWidth(appearance))
      }
      .mediaActionStyle(appearance)
#if os(iOS)
      .contextMenu { playMenu(for: target, appearance: appearance) }
#endif
      .focused($focus, equals: Self.focusTarget(forPlay: appearance.id))
      .accessibilityLabel(Text(appearance.accessibilityLabel))
      .accessibilityHint(Text("Starts playback"))
      .task(id: target.id) {
        await PlaybackPreflight.shared.warm(target)
      }
    }
  }

  /// The phone's Play is never the smaller button beside Trailer: «Play» alone read
  /// as a stub (Sasha, 2026-11-16, his 110 pt).
  private func playMinWidth(_ appearance: MediaActionAppearance) -> CGFloat? {
    centersColumn && appearance.id == .play ? Self.phonePlayMinWidth : nil
  }

  static let phonePlayMinWidth: CGFloat = 110

  @ViewBuilder
  private func trailerControl(_ appearance: MediaActionAppearance) -> some View {
#if os(iOS)
    if mediaItem.trailerURL == nil {
      // Shown from the listing, which names the trailer but not its stream (that comes
      // with the details call): a press waits for it, then plays (Sasha, 2026-11-16).
      let waiting = Self.loading(appearance, awaitsTrailer)
      Button {
        awaitsTrailer = true
      } label: {
        MediaActionLabel(waiting)
      }
      .mediaActionStyle(waiting)
      .focused($focus, equals: .trailer)
    } else {
      trailerLink(appearance)
    }
#else
    trailerLink(appearance)
#endif
  }

  private static func loading(_ appearance: MediaActionAppearance, _ isLoading: Bool) -> MediaActionAppearance {
    var copy = appearance
    copy.isLoading = isLoading
    return copy
  }

  private func trailerLink(_ appearance: MediaActionAppearance) -> some View {
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
  static let creditsColumnRatio: CGFloat = 0.42
  /// The column's share of the room beside the margins (and the poster) when the window
  /// is too narrow for both measures at full width.
  static let creditsColumnShare: CGFloat = 0.34
  /// Extra room between the lines of one role: «В ролях» with five names was tight
  /// (Sasha, 2026-11-09).
#if os(tvOS)
  static let creditLeading: CGFloat = 2
#else
  static let creditLeading: CGFloat = 1
#endif
  static let viewsSymbol = "eyes"
  /// «1ч 15 мин», not «1ч 15м»: the facts line has the room (Sasha, 2026-11-09).
  static let runtimeLength: TextLength = .medium

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
  /// The phone's lines around the title and Play: the Home banner's size, so the same
  /// facts read the same on both (Sasha, 2026-11-16).
  static let phoneMetaFont: Font = TypeScale.heroSecondary

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
  static let creditLineSpacing: CGFloat = 10
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
  static let creditLineSpacing: CGFloat = 5
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
  static let creditLineSpacing: CGFloat = 5
  static let columnGutter: CGFloat = 16
  static let trailingPosterCornerRadius: CGFloat = 12
#endif
}

/// Title width: ~80% of the hero, or the full column left of the portrait poster.
/// A short word framed like the drawn badges beside it: «DUB», «MVO», «6+».
private struct PlaybackTag: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(verbatim: text)
      .font(.caption2.weight(.bold))
      .padding(.horizontal, 3)
      .overlay {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
          .strokeBorder(lineWidth: 1)
      }
  }
}

private struct TitleBlockHorizontalBounds: ViewModifier {
  let reservePosterColumn: Bool
  var alignment: Alignment = .leading

  func body(content: Content) -> some View {
    if reservePosterColumn {
      content.frame(maxWidth: .infinity, alignment: alignment)
    } else {
      content.containerRelativeFrame(.horizontal, count: 5, span: 4, spacing: 0, alignment: alignment)
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

/// The Apple TV app's weight between its lines: the facts, scores and playback lines a
/// step back from the synopsis, lightening what is behind them rather than covering it —
/// vibrancy over the picture (Sasha, 2026-11-09). Over the plain page, and with Increase
/// Contrast, the solid colour the line already has.
struct HeroVibrantLabel: ViewModifier {
  var isOverArt: Bool
  @Environment(\.colorSchemeContrast) private var contrast

  func body(content: Content) -> some View {
    if isOverArt, contrast != .increased {
      content
        .opacity(Self.opacity)
        .blendMode(.plusLighter)
    } else {
      content
    }
  }

  static let opacity: Double = 0.78
}
