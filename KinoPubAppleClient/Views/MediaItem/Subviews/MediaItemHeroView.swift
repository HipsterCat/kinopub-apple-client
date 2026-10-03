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
      if isReady { player.play() }
    } else {
      player.pause()
    }
  }

  private func handle(status: AVPlayerItem.Status) {
    switch status {
    case .readyToPlay:
      isReady = true
      if isActive { player?.play() }
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

  /// Drops back to the artwork and forgets what was playing, so leaving the page and
  /// coming back starts the trailer over.
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
  /// `.resizeAspectFill` behind the title so the trailer fills the hero; the
  /// full-screen presentation asks for `.resizeAspect` so nothing is cropped away.
    var gravity: AVLayerVideoGravity = .resizeAspect
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
  /// Certification from enrichment ("TV-14", "16+"). Rendered as one more capability
  /// chip in the metadata row — the item payload has no rating of its own.
  var ageRating: String? = nil
  /// False until external metadata settles. While false, the title slot stays empty
  /// (optimistic: a logo is expected). Defaults to `true` so previews without the
  /// enrichment pipeline still show the lettered title.
  var externalMetadataLoaded: Bool = true
  /// tvOS: called whenever one of the hero's own controls takes focus, including moves
  /// between them. The page scrolls back to the top with it.
  var onFocusEntered: (() -> Void)? = nil
  /// Warm `BookmarkFoldersStore` once so a cold install is not an empty bookmark menu.
  var ensureBookmarkFoldersLoaded: (() async -> Void)? = nil

  /// tvOS only: the Up gesture lifts the muted inline preview into a real full-screen
  /// player. Kept here so the same view that owns the preview owns its promotion.
  @State private var isTrailerFullScreen = false
  @State private var showNewFolderAlert = false
  @State private var newFolderName = ""
  /// Actions currently showing a spinner (Mark Watched, Follow, …). Cleared when the
  /// underlying flag flips, or by the control itself once the tap returns.
  @State private var loadingActions: Set<MediaActionID> = []
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
#endif
  /// Opt-in, off by default. Read as `@AppStorage` so flipping it in Settings redraws
  /// the metadata row without leaving the page.
  @AppStorage(MediaItemDisplayPreferences.showAgeRatingBadgeKey)
  private var showsAgeRatingBadge = false


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
        guard let target else { return }
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
#if os(tvOS)
    // The page gives the hero its height (`MediaItemLayout.heroFraction` of the screen)
    // and the chrome sits at its bottom edge. The artwork is the hero's `.background`, so
    // it adds nothing to the layout and scrolls away with the hero, but it is as tall as
    // the screen, not the hero: the first section peeks over the picture instead of over
    // a band of bare page, and the picture dissolves into the page at the bottom.
    content
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
      .background(alignment: .top) {
        backdropLayer
      }
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
    ZStack(alignment: .bottomLeading) {
      Color.clear
        .aspectRatio(16 / 9, contentMode: .fit)

      content
//        .environment(\.colorScheme, .dark)
    }
    .frame(maxWidth: .infinity, alignment: .bottomLeading)
    .background {
      ZStack {
        scrollingBackdrop
        scrollingScrim
      }
    }
    .clipped()
    .background(visibilityProbe)
#endif
  }


#if os(tvOS)
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

  /// wide → big → medium. Same chain as Home banners — list/detail payloads differ and
  /// a `/wide/` derivation frequently 404s, so one URL is not enough. See
  /// `FallbackRemoteImage`.
  private var backdropCandidates: [URL] {
    var seen = Set<String>()
    var urls: [URL] = []
    for raw in [mediaItem.posters.wideURL, mediaItem.posters.big, mediaItem.posters.medium]
      .compactMap({ $0 }) where !raw.isEmpty && seen.insert(raw).inserted {
      if let url = URL(string: raw) { urls.append(url) }
    }
    return urls
  }

  @ViewBuilder
  private var scrollingBackdrop: some View {
    ZStack {
      FallbackRemoteImage(urls: backdropCandidates, contentMode: .fill)
        .onAppear {
#if DEBUG
          let list = backdropCandidates.map(\.absoluteString).joined(separator: " | ")
          print("[Artwork] hero id=\(mediaItem.id) candidates=\(list)")
#endif
        }

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

#if os(tvOS)
  /// Artwork, then the legibility scrim, both dissolved into the page at the bottom and
  /// sized to the screen (`containerRelativeFrame` resolves against the page's scroll
  /// view, not the hero).
  private var backdropLayer: some View {
    ZStack {
      scrollingBackdrop
      scrollingScrim
    }
//    .containerRelativeFrame(.vertical, alignment: .top)
    .mask {
      // The picture's own alpha goes to zero, so whatever the page is drawn on shows
      // through: no second colour to match, in light or dark.
      LinearGradient(stops: [
        .init(color: .clear, location: 0),
        .init(color: .black, location: 0.4),
        .init(color: .black, location: 1)
      ], startPoint: .top, endPoint: .bottom)
    }
  }

  /// Always black under the hero chrome. Content forces `.colorScheme(.dark)`, so
  /// text is light; the scrim stays dark regardless of the ambient scheme.
  private var scrimTone: Color { .black }

  /// Where our text is, and nowhere else: the chrome runs the whole bottom edge (title
  /// and actions on the left, synopsis and credits on the right), so the floor is full
  /// width; the left edge gets extra weight for the title. The top of the picture is left
  /// alone. Stops are in screen height — the hero's content spans roughly 0.3 to 0.75.
  /// The old scrim stacked a 0.92 diagonal on a 0.45 floor, which is what read as black.
  private var scrollingScrim: some View {
    ZStack {
      // Floor under the written column — light artwork otherwise washes out
      // white `.primary` copy even with colorScheme forced dark.
      scrimTone.opacity(0.22)

      LinearGradient(stops: [
        .init(color: .clear, location: 0.35),
        .init(color: scrimTone.opacity(0.28), location: 0.55),
        .init(color: scrimTone.opacity(0.55), location: 0.82),
        .init(color: scrimTone.opacity(0.72), location: 1)
      ], startPoint: .top, endPoint: .bottom)

      LinearGradient(stops: [
        .init(color: scrimTone.opacity(0.35), location: 0),
        .init(color: .clear, location: 0.35)
      ], startPoint: .leading, endPoint: .trailing)
    }
  }
#else
  /// Barely there, the way the Apple TV app leaves its hero video alone: clear for
  /// most of the frame, a light shade under the text, and the background colour only
  /// at the last few percent — without that the hero would meet the page on a visible
  /// seam. What carries the text is `heroTextShadow` on the type itself, not a slab
  /// over the picture.
  private var scrollingScrim: some View {
    LinearGradient(stops: [
      .init(color: .clear, location: 0),
      .init(color: .clear, location: 0.62),
      .init(color: Color.KinoPub.background.opacity(0.32), location: 0.82),
      .init(color: Color.KinoPub.background.opacity(0.9), location: 0.97),
      .init(color: Color.KinoPub.background, location: 1)
    ], startPoint: .top, endPoint: .bottom)
  }
#endif

  // MARK: - Foreground

  /// Wide screens (tvOS / Mac): two columns — title + actions | everything written.
  /// The third "starring" column is gone; its lines moved under the synopsis.
  /// Phone keeps a single stacked column, with the metadata row above the buttons.
  /// Hero chrome always reads as dark: plot/credits use `Color.primary` via
  /// `Color.KinoPub.text`, and tvOS does not pin `preferredColorScheme` — light
  /// appearance made the synopsis black on dark artwork (unreadable).
  private var content: some View {
    contentBody
      .environment(\.colorScheme, .dark)
  }

  @ViewBuilder
  private var contentBody: some View {
#if os(iOS)
    VStack(alignment: .leading, spacing: Self.contentSpacing) {
      titleBlock
//        .heroTextShadow()

      actions
        .padding(.top, Self.actionsGap)

      detailColumn
        .padding(.top, Self.actionsGap)
    }
    .padding(.horizontal, Self.horizontalInset)
    .padding(.bottom, Self.bottomInset)
    .frame(maxWidth: .infinity, alignment: .leading)
#else
    VStack(alignment: .leading, spacing: Self.columnGutter) {
      // Fixed, not proportional: the title block and the action stack are a known
      // size, and letting them share the width evenly with the prose left the
      // synopsis in a narrow ravine on a wide window.
         titleBlock
               Spacer()
      detailColumn
         actions
//         leadingColumn
//           .frame(width: Self.leadingWidth, alignment: .leading)
    }
    .padding(.bottom, Self.horizontalInset)
    .padding(.horizontal, Self.bottomInset)
    .frame(maxWidth: .infinity,  maxHeight: .infinity, alignment: .bottomLeading)
#endif
  }

  /// Logo / title, then the action stack — left column on wide layouts. The metadata
  /// row moved across to head the written column, the way the reference layout has it.
  private var leadingColumn: some View {
       VStack(alignment: .leading) {
      // Shadowed on its own, with the actions left out of it: the buttons carry their
      // own material, and a drop shadow under one that scales on focus is an extra
      // offscreen pass on every frame of the animation.
      titleBlock
            Spacer()
//        .heroTextShadow()

      // Actions sit with the title so Up from Play is a dead end → fullscreen trailer.
      // Everything written is the sibling column (or below on phone), not above the row.
//        .padding(.top, 80)
    }
  }

  /// Synopsis first, then who made it, then the facts. What someone is deciding on is
  /// what the film is about — year, genres and the score are what they check after,
  /// so they sit at the foot of the column rather than heading it.
  private var detailColumn: some View {
       VStack(alignment: .leading, spacing: Self.contentSpacing*1.75) {
#if os(tvOS)
      MediaItemPlotView(
        title: mediaItem.localizedTitle,
        plot: mediaItem.plot,
        focus: $focus,
        allowsFocus: actionEntryClaimed
      )
#else
      MediaItemPlotView(title: mediaItem.localizedTitle, plot: mediaItem.plot, focus: $focus)
#endif
         VStack(alignment: .leading, spacing: Self.contentSpacing) {
              credits
              metadata
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
  private var titleBlock: some View {
    // Label title is always on until the logo actually paints. Holding an empty
    // view while TMDB settles (or while the image is still downloading) left the
    // hero without a name; long-press PCM on the cover is gone for the same reason
    // — the cover is not a card.
    Group {
      if let titleLogoURL, externalMetadataLoaded {
        ArtworkImage(
          url: titleLogoURL,
          transaction: Transaction(animation: .easeOut(duration: 0.15))
        ) { phase in
          switch phase {
          case .success(let image):
            image
              .resizable()
              .scaledToFit()
              .frame(maxWidth: Self.logoMaxWidth, maxHeight: Self.logoMaxHeight, alignment: .leading)
              .padding(.top, Self.bottomInset/1.5)
              .transition(.opacity)
          case .failure, .empty:
            titleTextBlock
              .padding(.top, Self.bottomInset)
              .transition(.opacity)
          }
        }
      } else {
        titleTextBlock
          .padding(.top, Self.bottomInset)
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.15), value: externalMetadataLoaded)
    .animation(.easeOut(duration: 0.15), value: titleLogoURL)
  }

  private var titleTextBlock: some View {
       VStack(alignment: .leading, spacing: Self.contentSpacing) {
            // Above the localized title, as an eyebrow: it is the same title, not a second
            // piece of information, so it leads into the big one rather than trailing it.
            Text(mediaItem.localizedTitle)
                 .font(Self.titleFont)
                 .foregroundStyle(Color.KinoPub.text)
                 .lineLimit(4)
            
            if mediaItem.originalTitle != mediaItem.localizedTitle {
                 Text(mediaItem.originalTitle)
                      .font(Self.secondaryFont)
                      .foregroundStyle(Color.KinoPub.subtitle)
                      .lineLimit(1)
            }}
  }

  /// Heads the written column: the score, when and how long, then the capability
  /// chips. Whatever is drawn here is the same component the posters wear — a title
  /// scores the same wherever it is shown, so it should not be spelled two ways.
  private var metadata: some View {
    HStack(spacing: Self.metaSpacing) {
         if FeatureFlags.combinedRatingEnabled {
           if let rating = MediaScores(mediaItem).aggregate {
             RatingBadgeView(rating: rating)
               MediaScoresView(MediaScores(mediaItem))

           }
         } else {
           // No aggregate: each score keeps its own logo rather than becoming one number.
           MediaScoresView(MediaScores(mediaItem))
         }
         if !genreCountryLine.isEmpty {
           Text(genreCountryLine)
             .foregroundStyle(Color.KinoPub.subtitle)
         }
         let releaseLine = mediaItem.releaseLine
         if !releaseLine.isEmpty {
           Text(releaseLine)
             .lineLimit(1)
         }
         



      // Certification only when it was asked for — see `MediaItemDisplayPreferences`.
      let badges = MediaCapabilityBadges.from(item: mediaItem,
                                              ageRating: showsAgeRatingBadge ? ageRating : nil)
      if !badges.isEmpty {
        MediaCapabilityBadgesView(badges: badges, mode: .detail)
      }
    }
    .font(Self.secondaryFont)
    .foregroundStyle(Self.metaStyle)
  }

  /// Under the synopsis: what kind of thing it is and where it is from, then who is
  /// in it. Labels greyed, names picked out. The phone has no room for a cast list
  /// over the artwork — the detail sections below carry the full one anyway.
  @ViewBuilder
  private var credits: some View {
    if !genreCountryLine.isEmpty || showsCreditNames {
      HStack(alignment: .bottom, spacing: Self.creditLineSpacing) {
        if showsCreditNames {
          ForEach(creditLines, id: \.role) { line in
            Text(creditLine(line))
          }
        }
      }
      .font(Self.secondaryFont)
      .multilineTextAlignment(.leading)
      .frame(maxWidth: .infinity, alignment: .leading)
//      .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// Cast and director are wide-layout only.
  private var showsCreditNames: Bool {
#if os(iOS)
    false
#else
       !creditLines.isEmpty // and not anime, animation, documentary, tvshow
#endif
  }

  /// One run of attributed text rather than two concatenated `Text`s: the styling
  /// overloads that return `Text` are either iOS 17 or deprecated, and the label has
  /// to flow into the names on the same line anyway.
  private func creditLine(_ line: (role: String, names: String)) -> AttributedString {
    var label = AttributedString(line.role.localized + "  ")
    label.foregroundColor = Color.KinoPub.subtitle

    var names = AttributedString(line.names)
    names.foregroundColor = Color.KinoPub.text
    names.font = Self.secondaryFont.weight(.medium)

    return label + names
  }

  /// Genres and country carry no labels — the words say what they are, and a "Genre:"
  /// in front of them is the kind of form-field caption the Apple TV app never shows.
  /// Genres lead, because that is what someone is deciding on.
  private var genreCountryLine: String {
    var parts: [String] = []
    let genres = mediaItem.genreNames.prefix(Self.genreLimit)
    if !genres.isEmpty { parts.append(genres.joined(separator: "  ")) }
//    let countries = mediaItem.countryNames.prefix(Self.countryLimit)
//    if !countries.isEmpty { parts.append(countries.joined(separator: "  ")) }
    return parts.joined(separator: "  ")
  }

  /// A handful of leads and whoever directed it — the whole cast is what the section
  /// further down the page is for. A series has no one director to name, so it gets
  /// the cast alone.
  ///
  /// Nobody stars in a stand-up set, a concert or a documentary, so those name no
  /// leads here at all — their people are a Credits card in the information table.
  /// `MediaPresentationProfile` owns which is which.
  private var creditLines: [(role: String, names: String)] {
    var lines: [(String, String)] = []
    let cast: [String] = mediaItem.presentation.showsHeroCastLine
      ? Array(mediaItem.castMembers.prefix(Self.creditNameLimit))
      : []
    if !cast.isEmpty {
         lines.append(("Starring.short".localized, cast.joined(separator: ",  ")))
    }
    if !isSeries {
      let directors = mediaItem.directorNames.prefix(Self.creditNameLimit)
      if !directors.isEmpty {
        // The same word the Credits card and the "More by…" shelf use — the hero read
        // "Director" over a title whose shelf below it said "More by This Creator".
        lines.append((mediaItem.presentation.authorCaptionKey,
                      directors.joined(separator: ", ")))
      }
    }
    return lines
  }

  /// One catalog-driven row. Order/chrome from `MediaActionCatalog`; this view wires
  /// behaviour. Forced dark for now so glass samples against the hero artwork the
  /// same way in light and dark until the light-theme stage owns these controls.
  private var actions: some View {
    MediaActionRow {
      ForEach(actionAppearances) { appearance in
        actionControl(for: appearance)
          .accessibilityIdentifier("kinopub.hero.\(appearance.id.rawValue)")
          .transition(.asymmetric(
            insertion: .scale(scale: 0.85).combined(with: .opacity),
            removal: .scale(scale: 0.85).combined(with: .opacity)
          ))
      }
    }
    .environment(\.colorScheme, .dark)
#if os(tvOS)
    // Own focus section so Down from the plot section enters here at `defaultFocus`
    // Play — never `.disabled` on siblings to steer the remote (that killed Menus).
    .focusSection()
#endif
    // Animate only membership changes (Mark Watched appearing/disappearing) — not
    // glyph swaps inside a stable id, which used to look like the gaps grew.
    .animation(.easeOut(duration: 0.25), value: actionAppearances.map(\.id))
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

  private var actionContext: MediaActionContext {
#if os(tvOS)
    let showsMore = true
#else
    let showsMore = false
#endif
    let playback = mediaItem.playbackButtonContent
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
      versions: mediaItem.playbackVariants.map {
        MediaActionVersion(name: $0.name, playback: $0.playbackButtonContent)
      },
      loading: loadingActions
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
    MediaActionCatalog.row(for: actionContext)
  }

  @ViewBuilder
  private func actionControl(for appearance: MediaActionAppearance) -> some View {
    switch appearance.id {
    case .play, .playAlternate:
      playControl(appearance)
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
    .mediaActionStyle(appearance.chrome)
    .focused($focus, equals: .download)
    .contextMenu {
      if isSeries, let (season, _) = mediaItem.primaryEpisode {
        Button {
          onDownloadSeason?(season)
        } label: {
          Label("Download Season", systemImage: "arrow.down.to.line")
        }
        Button {
          onDownloadUnwatchedInSeason?(season)
        } label: {
          Label("Download Unwatched in Season", systemImage: "arrow.down.to.line")
        }
        Button {
          onDownloadAllEpisodes?()
        } label: {
          Label("Download All Episodes", systemImage: "arrow.down.to.line")
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
      .mediaActionStyle(appearance.chrome)
      .focused($focus, equals: .shuffle)
      .accessibilityLabel(Text(appearance.accessibilityLabel))
    } else {
      MediaActionButton(appearance) {}
        .disabled(true)
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
    .mediaActionStyle(appearance.chrome)
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
    .mediaActionStyle(appearance.chrome)
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
          Label("New Folder", systemImage: "circle.plus")
        }
      }
    } label: {
      MediaActionLabel(appearance)
    }
#if !os(macOS)
    .menuActionDismissBehavior(.disabled)
#endif
    .mediaActionStyle(appearance.chrome)
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
      loadingActions.insert(.follow)
      onToggleWatchlist?()
    } label: {
      MediaActionLabel(appearance)
    }
    .mediaActionStyle(appearance.chrome)
    .focused($focus, equals: .watchlist)
    .disabled(!MediaItemHeroActionAvailability.isInteractable(isLoading: appearance.isLoading))
  }

  /// Tap marks watched. Long-press (series): episode · season · unwatched in season · all.
  @ViewBuilder
  private func markWatchedControl(_ appearance: MediaActionAppearance) -> some View {
    Button {
      beginMarkWatched()
      onWatchedToggle()
    } label: {
      MediaActionLabel(appearance)
    }
    .mediaActionStyle(appearance.chrome)
    .focused($focus, equals: .watched)
    .disabled(!MediaItemHeroActionAvailability.isInteractable(isLoading: appearance.isLoading))
    .accessibilityLabel(Text(appearance.accessibilityLabel))
    .contextMenu {
      if let (season, episode) = mediaItem.primaryEpisode {
        Button {
          beginMarkWatched()
          onWatchedToggle()
        } label: {
          Label("\("Mark Episode Watched".localized) · S\(season.number), E\(episode.number)",
                systemImage: "checkmark")
        }
        if onSeasonWatchedToggle != nil {
          Button {
            beginMarkWatched()
            onSeasonWatchedToggle?(season)
          } label: {
            Label("\("Mark Season Watched".localized) · \(season.number)",
                  systemImage: "checkmark.circle")
          }
        }
        if onMarkUnwatchedInSeason != nil {
          Button {
            beginMarkWatched()
            onMarkUnwatchedInSeason?(season)
          } label: {
            Label("Mark Unwatched in Season", systemImage: "checkmark.circle")
          }
        }
        if onMarkAllEpisodesWatched != nil {
          Button {
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
    } label: {
      MediaActionLabel(appearance)
    }
    .mediaActionStyle(appearance.chrome)
    .focused($focus, equals: .more)
    .accessibilityLabel(Text(appearance.accessibilityLabel))
  }

  private static func focusTarget(forPlay id: MediaActionID) -> MediaItemFocusTarget {
    id == .playAlternate ? .playAlternate : .play
  }

  /// What a play pill opens. A film shown as version pills: that version, by position
  /// (`playbackVariants` is in number order, as the catalog's `versions` are).
  /// Everything else: `playTarget`.
  private func playTarget(for id: MediaActionID) -> any PlayableItem {
    let variants = mediaItem.playbackVariants
    if variants.count >= 2 {
      return variants[id == .playAlternate ? 1 : 0]
    }
    return playTarget
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
  static let trailerLeadIn: Double = 2
  /// Non-tvOS only: fade as soon as the hero has scrolled up at all. The old
  /// half-height threshold left the trailer running under the first section below.
  static let onScreenSlop: CGFloat = 150

  /// Leads and directors named in the corner, before the list turns into a paragraph.
  static let creditNameLimit = 3

  /// Genres shown above the names; kino.pub happily returns six.
  static let genreLimit = 2

  /// Co-productions run long — two is enough to say where a title is from.
  static let countryLimit = 1

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
#elseif os(macOS)
  /// Preview / fallback only — live layout uses `.aspectRatio(16/9)`.
  static let heroHeight: CGFloat = 420
  static let horizontalInset: CGFloat = 32
  static let bottomInset: CGFloat = 28
  static let contentSpacing: CGFloat = 8
  static let leadingWidth: CGFloat = 400
  static let logoMaxWidth: CGFloat = 360
  static let logoMaxHeight: CGFloat = 110
  static let titleFont: Font = TypeScale.heroTitle
  static let metaSpacing: CGFloat = 12
  static let actionsGap: CGFloat = 12
  static let actionsRowGap: CGFloat = 10
  static let creditLineSpacing: CGFloat = 3
  static let columnGutter: CGFloat = 28
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
#endif
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
      titleLogoURL: nil
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
