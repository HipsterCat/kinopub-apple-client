//
//  PlayerView.swift
//  KinoPubAppleClient
//
//  Created by Kirill Kunst on 3.08.2023.
//

import Foundation
import SwiftUI
import AVKit
#if os(macOS)
import AppKit
#endif
import Combine
import KinoPubBackend
import KinoPubUI
import KinoPubLogging
import OSLog

struct PlayerView: View {

  @ObservedObject private var playerManager: PlayerManager
#if os(tvOS)
  /// Publishes the manager swap an accepted Up Next proposal performs, so this screen
  /// follows to the next episode instead of holding the finished one.
  @ObservedObject private var playbackSession = PlaybackSession.shared
#endif
#if os(tvOS) || os(iOS)
  @Environment(NavigationState.self) private var navigationState
#endif
  @Environment(\.dismiss) private var dismiss
  @Environment(ErrorHandler.self) private var errorHandler
  @State private var showsFailureAlert = false
#if os(macOS)
  @Environment(\.dismissWindow) private var dismissWindow
#endif

  init(manager: PlayerManager) {
    _playerManager = ObservedObject(wrappedValue: manager)
  }

  /// The manager this screen shows. On tvOS an accepted Up Next swaps the session's
  /// manager for the next episode's; everywhere else the entry manager is the only one.
  /// (The load-failure alert stays on the entry manager — a post-swap failure is drawn
  /// by AVKit's own error state.)
  private var liveManager: PlayerManager {
#if os(tvOS)
    // `currentManager` is live even before the `@Published` mirror catches up after `play`.
    playbackSession.currentManager ?? playbackSession.manager ?? playerManager
#else
    playerManager
#endif
  }

  var body: some View {
    ZStack(alignment: .top) {
      videoPlayer
      // No chrome of ours anywhere: the system player draws the transport bar, the
      // subtitle menu and the audio menu, and the master playlist carries every
      // kino.pub subtitle as a real HLS rendition for it to list. The sidecar overlay
      // is the dual-subtitle stage, parked behind its flag.
#if os(tvOS)
      if FeatureFlags.tvOSSidecarSubtitles {
        subtitleLayers
      }
#endif
    }
    .ignoresSafeArea(.all)
    // The system player draws its own chrome for everything else — a spinner while it
    // buffers, Done/Menu/the window close button to get out. The one thing it can't
    // show on its own is *why* a stream failed, so that alone gets a system alert, and
    // we stay in the player rather than bouncing back to the page underneath it.
    .alert("Couldn't Load", isPresented: $showsFailureAlert, presenting: failureMessage) { _ in
      Button("Try Again") { playerManager.retryAfterFailure() }
      Button("Close", role: .cancel) { closeAfterFailure() }
    } message: { message in
      Text(message)
    }
    .onChange(of: playerManager.playbackState) { _, state in
      if case .failed(let message) = state {
#if os(tvOS)
        // Live has no quality ladder to fall back on. A dead stream (DNS, 404) left
        // AVKit in a width-0 / focus-broken chrome that ate Menu and sat over the TV
        // grid half-focused (Sasha, 2026-11-20). Leave instead of trapping; toast so
        // it reads as "channel unavailable", not a mis-press. Mid-play silent reload
        // (`recoverAfterMidStreamFailure`) only runs while `.ready`, so prepare
        // failures reach here without a prior reload.
        if playerManager.watchMode == .live {
          errorHandler.setMessage(message)
          closeAfterFailure()
          return
        }
#endif
        showsFailureAlert = true
#if os(macOS)
        // Alert alone was easy to miss in the player window — toast the reason too (KP-35).
        errorHandler.setMessage(message)
#endif
      }
    }
#if os(macOS)
    // The player has its own window (see `PlayerLink`), so the title bar stays: it
    // carries the film's name and the close button. It used to be hidden while the
    // player was pushed into the main window's detail column, which left the screen
    // with no way out at all once playback hid the custom chevron.
    .navigationTitle(playerManager.displayTitle ?? "")
    // Transparent title bar over the video — drop the opaque underlay strip (KP-35).
    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    .background(MacPlayerTitlebarChrome(title: playerManager.displayTitle ?? ""))
    // Escape leaves, the way it does out of full-screen video everywhere else. ⌘W still
    // works too, and now closes the film rather than the app's window.
    .onExitCommand {
      dismissWindow(id: PlaybackWindowState.windowID)
    }
#endif
#if os(iOS)
    .navigationBarHidden(true)
    .toolbar(.hidden, for: .tabBar)
    // No orientation forcing: the video opens as held — portrait included — and the
    // system player follows the device when the viewer rotates it. Forcing landscape
    // here fought AVKit's own fullscreen orientation transaction ("a new orientation
    // transaction token is being requested while a valid one already exists"), and the
    // churn recreated the presentation host mid-dismissal — the player reopening after
    // close. A "landscape by default" preference may come later, deliberately.
    .onAppear(perform: {
      UIApplication.shared.isIdleTimerDisabled = true
    })
    .onDisappear(perform: {
      UIApplication.shared.isIdleTimerDisabled = false
    })
#endif
#if os(tvOS)
    // The player is a full-screen surface, not a browse tab — the tab strip has no place
    // over it. Back/Menu leaves, the same as on the detail page.
    .toolbar(.hidden, for: .tabBar)
#endif
#if os(tvOS) || os(macOS)
    // **Leaving the player ends the film.** Menu on the TV, closing the window on the
    // Mac: the session outlives this screen by design, so without this the stream ran on
    // with nothing showing it — audio playing over the browse grid on tvOS, a paused-but
    // -still-loaded item on macOS.
    //
    // Only safe to hang off `onDisappear` on these two: on iOS this view stays mounted
    // under AVKit's own full-screen presentation and gets `onDisappear` on the way *in*,
    // so there the exit signal is the player controller's dismissal delegate instead.
    .onDisappear { endPlayback() }
#endif
  }

  /// Ends the session this screen was showing — unless the viewer moved it into Picture
  /// in Picture, which is them keeping the film, not closing it.
  private func endPlayback() {
    guard !liveManager.isPictureInPictureActive else { return }
    forgetWindowRequest(ifSessionEnded: PlaybackSession.shared.stop(liveManager))
  }

#if os(tvOS)
  /// Info tab's *Go to Show / Go to Movie*: leave the player for the title's page. The
  /// player is the last route of the selected tab's stack; if the route under it already
  /// is this title's page (Play was pressed there) leaving is enough, otherwise the page
  /// takes the player's place. `onDisappear` ends the playback once the route is gone.
  private func goToTitle(_ itemID: Int) {
    let path = navigationState.path(for: navigationState.selectedTab)
    var routes = path.wrappedValue
    while let last = routes.last, last.isPlayerRoute { routes.removeLast() }
    if routes.last?.detailsItemID != itemID {
      routes.append(.detailsById(itemID))
    }
    path.wrappedValue = routes
  }
#endif

#if os(tvOS) || os(iOS)
  /// Picture in Picture back to full screen: the player's route again, on the tab the
  /// viewer is on now (`PictureInPictureKeeper`) — or, when that tab has no stack to push
  /// on (Settings), on the tab the player was opened from, which is selected first.
  /// Pushed onto Settings' inert path the route went nowhere: AVKit closed the window and
  /// waited for a player that never came, and only the sound was left, with no way to
  /// stop it (Sasha, 2026-10-25).
  private func restoreFromPictureInPicture(_ route: Route, origin: NavigationTabs) {
    var tab = navigationState.selectedTab
    if !navigationState.hasStack(tab) {
      tab = navigationState.hasStack(origin) ? origin : .home
      Logger.app.info("PiP: restoring on \(String(describing: tab), privacy: .public), the selected tab has no stack")
      navigationState.selectedTab = tab
    }
    navigationState.path(for: tab).wrappedValue.append(route)
  }
#endif

  /// The failure alert's way out: end the session, then leave the way this platform's
  /// player leaves — a route pop, or the window's own close on the Mac.
  private func closeAfterFailure() {
    endPlayback()
#if os(macOS)
    dismissWindow(id: PlaybackWindowState.windowID)
#else
    dismiss()
#endif
  }

  /// macOS: with nothing playing, the window must not sit on a request that would start a
  /// film again. Only when this screen really was the last one, though — swapping films in
  /// an open window takes the outgoing screen down *after* the incoming film has claimed
  /// the session, and clearing there would blank the window on the film that just started.
  private func forgetWindowRequest(ifSessionEnded ended: Bool) {
#if os(macOS)
    guard ended else { return }
    PlaybackWindowState.shared.request = nil
#endif
  }

  @ViewBuilder
  var videoPlayer: some View {
#if os(tvOS)
    // The system player screen is the whole point: its transport bar is the only chrome,
    // and it's fully Siri-Remote navigable. `PlayerManager` hangs the title, subtitle and
    // the Subtitles/Audio menus off the controller.
    TVVideoPlayer(manager: liveManager, onMenuPress: { dismiss() }, onGoToTitle: goToTitle,
                  onRestoreFromPictureInPicture: { [origin = navigationState.selectedTab] route in
                    restoreFromPictureInPicture(route, origin: origin)
                  })
      .task {
        // Playback starts itself once the stream is ready and the resume point applied.
        await playerManager.preparePlayback()
      }
#elseif os(iOS)
    // The system player, presented rather than embedded — that presentation is where the
    // close button comes from. Done ends the film and leaves the route with it.
    SystemVideoPlayer(manager: playerManager, onFinish: {
      endPlayback()
      dismiss()
    }, onRestoreFromPictureInPicture: { [origin = navigationState.selectedTab] route in
      restoreFromPictureInPicture(route, origin: origin)
    })
      .task {
        await playerManager.preparePlayback()
      }
#else
    // SwiftUI's `VideoPlayer` exposes none of `speeds` / `allowsPictureInPicturePlayback` /
    // `controlsStyle` on macOS — `AVPlayerView` is the only surface that does (see the
    // customization-surface table in player-and-media.md).
    MacVideoPlayer(manager: playerManager)
      .task {
        playerManager.onPlaybackEnded = { action in
          switch action {
          case .dismiss:
            closeAfterFailure()
          case .playNext(let episode):
            PlaybackWindowState.shared.show(item: episode, mode: .media)
          }
        }
        await playerManager.preparePlayback()
      }
#endif
  }

  /// `nil` outside `.failed`, so the alert's `presenting:` item controls its own
  /// visibility together with `showsFailureAlert`.
  private var failureMessage: String? {
    if case .failed(let message) = playerManager.playbackState {
      return message
    }
    return nil
  }

  /// tvOS only, and only with `FeatureFlags.tvOSSidecarSubtitles` — the dual-subtitle
  /// stage's sidecar SRT overlay. Off, the system player renders subtitles itself.
  @ViewBuilder
  private var subtitleLayers: some View {
    VStack {
      Spacer()
      if playerManager.subtitlesEnabled,
         playerManager.isPlaying,
         let cue = playerManager.activeCue {
        SubtitleOverlayView(text: cue.displayText,
                            secondaryText: playerManager.activeSecondaryCue?.displayText)
          .padding(.bottom, 48)
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.2), value: playerManager.isPlaying)
    .animation(.easeOut(duration: 0.2), value: playerManager.activeCue)
    .animation(.easeOut(duration: 0.2), value: playerManager.activeSecondaryCue)
  }

}

#if os(tvOS)

/// Drives `AVPlayerViewController` directly so the system transport bar is the only
/// chrome — title/subtitle in the info panel, Subtitles and Audio in the transport-bar
/// menu, all reachable with the Siri Remote. `PlayerManager` owns the configuration; this
/// is just the bridge into UIKit.
private struct TVVideoPlayer: UIViewControllerRepresentable {
  let manager: PlayerManager
  /// This controller is a plain `NavigationStack` push, not a full-screen presentation —
  /// so AVKit's own "end full-screen presentation" dismiss path never fires. Menu is
  /// wired to exit through `playerViewControllerShouldDismiss` instead, the delegate
  /// call AVKit makes specifically for a Menu press on an embedded (non-presented)
  /// player, so leaving the player never depends on how the hosting navigation happens
  /// to react to the hardware button.
  let onMenuPress: () -> Void
  /// Info tab's *Go to Show / Go to Movie*, with the id of the page to show.
  let onGoToTitle: (Int) -> Void
  /// Picture in Picture back to full screen: push this route (`PictureInPictureKeeper`).
  let onRestoreFromPictureInPicture: (Route) -> Void

  func makeUIViewController(context: Context) -> AVPlayerViewController {
    // Back from Picture in Picture, the controller is the one AVKit animates the picture
    // into — not a new one.
    if let held = PictureInPictureKeeper.shared.takeController(for: manager) {
      held.delegate = context.coordinator
      context.coordinator.systemInfoActions = PictureInPictureKeeper.shared.systemInfoActions
      context.coordinator.install(on: manager, controller: held)
      manager.attach(to: held)
      return held
    }
    let controller = AVPlayerViewController()
    controller.player = manager.player
    controller.delegate = context.coordinator
    controller.speeds = AVPlaybackSpeed.systemDefaultSpeeds
    controller.allowsPictureInPicturePlayback = true
    // Before anything sets the list: afterwards the getter answers empty (tvOS 27.2).
    context.coordinator.systemInfoActions = controller.infoViewActions ?? []
    context.coordinator.install(on: manager, controller: controller)
    manager.attach(to: controller)
    return controller
  }

  func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
    // An accepted Up Next swaps the session's manager; the representable follows, and
    // the player swap the delegate already performed is simply confirmed here.
    context.coordinator.manager = manager
    if controller.player !== manager.player {
      controller.player = manager.player
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(manager: manager, onMenuPress: onMenuPress, onGoToTitle: onGoToTitle,
                onRestoreFromPictureInPicture: onRestoreFromPictureInPicture)
  }

  @MainActor
  final class Coordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
    /// Tracks the session's current manager — an accepted Up Next replaces it.
    var manager: PlayerManager
    let onMenuPress: () -> Void
    let onGoToTitle: (Int) -> Void
    let onRestoreFromPictureInPicture: (Route) -> Void

    init(manager: PlayerManager, onMenuPress: @escaping () -> Void,
         onGoToTitle: @escaping (Int) -> Void,
         onRestoreFromPictureInPicture: @escaping (Route) -> Void) {
      self.manager = manager
      self.onMenuPress = onMenuPress
      self.onGoToTitle = onGoToTitle
      self.onRestoreFromPictureInPicture = onRestoreFromPictureInPicture
    }

    /// Answers the Info tab's buttons for `manager`. Installed again for every manager an
    /// in-place swap brings in — the buttons are built by (and read from) the manager
    /// playing at the time.
    /// The system's own Info buttons for this controller, read once — every manager an
    /// in-place swap brings in gets the same list.
    var systemInfoActions: [UIAction] = []

    func install(on manager: PlayerManager, controller: AVPlayerViewController) {
      manager.systemInfoActions = systemInfoActions
      manager.onPlay = { [weak self, weak controller] item in
        guard let self, let controller else { return }
        self.advance(controller, to: item)
      }
      manager.onGoToTitle = onGoToTitle
      manager.onPlaybackEnded = { [weak self, weak controller] action in
        guard let self else { return }
        switch action {
        case .dismiss:
          self.onMenuPress()
        case .playNext(let episode):
          guard let controller else { return }
          self.advance(controller, to: episode)
        }
      }
    }

    func playerViewControllerShouldDismiss(_ playerViewController: AVPlayerViewController) -> Bool {
      onMenuPress()
      return false
    }

    /// Skip (`contextualActions`) is only presented while the transport bar is
    /// hidden. Drive the auto-Skip countdown from the same signal so it cannot
    /// fire while chrome (or a menu that keeps chrome up) obscures the button.
    func playerViewController(
      _ playerViewController: AVPlayerViewController,
      willTransitionToVisibilityOfTransportBar visible: Bool,
      with coordinator: any AVPlayerViewControllerAnimationCoordinator
    ) {
      manager.noteTransportBar(visible: visible)
    }

    // MARK: Picture in Picture (`PictureInPictureKeeper`)

    func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
      manager.setPictureInPictureActive(true)
      PictureInPictureKeeper.shared.willStart(controller: playerViewController,
                                              delegate: self,
                                              manager: manager,
                                              systemInfoActions: systemInfoActions,
                                              push: onRestoreFromPictureInPicture)
    }

    /// The picture is in its window: leave the route, as Menu does, so the viewer is back
    /// in the app. The session stays — `endPlayback` skips a manager in PiP.
    func playerViewControllerDidStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
      onMenuPress()
    }

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              failedToStartPictureInPictureWithError error: any Error) {
      Logger.app.error("PiP: failed to start: \(error.localizedDescription)")
      manager.setPictureInPictureActive(false)
    }

    func playerViewController(
      _ playerViewController: AVPlayerViewController,
      restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
      PictureInPictureKeeper.shared.restore(completion: completionHandler)
    }

    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
      manager.setPictureInPictureActive(false)
      PictureInPictureKeeper.shared.didStop(manager: manager)
    }

    // MARK: Up Next (system content proposal)

    /// The panel only exists because `PlayerManager` resolved a next episode, so the
    /// two agree — but a swap could have happened in between, and presenting a panel
    /// whose answer is gone is a hang.
    func playerViewController(_ playerViewController: AVPlayerViewController,
                              shouldPresent proposal: AVContentProposal) -> Bool {
      manager.pendingNextEpisode != nil
    }

    /// Accepted (or the countdown ran out): swap the stream in place, same screen.
    func playerViewController(_ playerViewController: AVPlayerViewController,
                              didAccept proposal: AVContentProposal) {
      guard let episode = manager.pendingNextEpisode else { return }
      advance(playerViewController, to: episode)
    }

    /// The one way to play something else in place — the end-of-episode panel and the Up
    /// Next tab's tiles (the next episode, or a Continue Watching title) all end up here.
    private func advance(_ playerViewController: AVPlayerViewController, to item: any PlayableItem) {
      let context = AppContext.shared
      let next = PlaybackSession.shared.play(
        item: item,
        mode: .media,
        downloadedFilesDatabase: context.downloadedFilesDatabase,
        actionsService: context.actionsService
      )
      install(on: next, controller: playerViewController)
      next.attach(to: playerViewController)
      // Auto-play inside the floating window: the next episode is the one PiP now shows.
      PictureInPictureKeeper.shared.managerDidChange(from: manager, to: next)
      // Swap immediately — waiting on the SwiftUI round-trip would hold the finished
      // episode's last frame behind the countdown panel. `updateUIViewController`
      // then finds the player already current and only adopts the new manager.
      playerViewController.player = next.player
      manager = next
      Task { await next.preparePlayback() }
    }

    /// Rejected: the header's default is to dismiss the player, but this controller is
    /// a navigation push, not a presentation — leaving is routed the way Menu is.
    func playerViewController(_ playerViewController: AVPlayerViewController,
                              didReject proposal: AVContentProposal) {
      onMenuPress()
    }
  }
}

#endif

#if os(iOS)

/// The system player, presented the way AVKit wants to be presented: modally, full
/// screen, over everything.
///
/// **That presentation is the whole reason there is a way out.** An `AVPlayerViewController`
/// sitting inline in a view hierarchy draws a transport bar and nothing else — no Done, no
/// close button — and this screen hides the navigation bar and swallows the back swipe, so
/// the iPhone ended up with a film that could not be left. `entersFullScreenWhenPlaybackBegins`
/// was supposed to buy the same presentation for free; it did not, so the presentation is
/// asked for outright instead of hoped for.
///
/// The button belongs to AVKit, not to us — the player still draws no chrome of ours.
private struct SystemVideoPlayer: UIViewControllerRepresentable {
  let manager: PlayerManager
  /// Done, or a swipe down, on the presented player — and Picture in Picture starting,
  /// which takes the presented player down with it.
  let onFinish: () -> Void
  /// Picture in Picture back to full screen: push this route (`PictureInPictureKeeper`).
  let onRestoreFromPictureInPicture: (Route) -> Void

  func makeUIViewController(context: Context) -> PlayerPresentationController {
    // Back from Picture in Picture, the controller is the one AVKit animates the picture
    // into — not a new one. Its stage tells the keeper once it is presented again.
    let held = PictureInPictureKeeper.shared.takeController(for: manager)
    let host = PlayerPresentationController(playerController: held ?? AVPlayerViewController())
    host.onPresented = held == nil ? nil : {
      PictureInPictureKeeper.shared.restoredControllerIsOnScreen()
    }
    context.coordinator.host = host
    context.coordinator.controller = host.playerController
    host.playerController.player = manager.player
    host.playerController.delegate = context.coordinator
    host.playerController.allowsPictureInPicturePlayback = true
    host.playerController.speeds = AVPlaybackSpeed.systemDefaultSpeeds
    context.coordinator.installEndHandler(on: manager)
    context.coordinator.observeSkip(on: manager)
    // Live Text over a paused frame: the floating text-recognition button and the
    // VisionKit overlay it summons are not part of watching a film.
    host.playerController.allowsVideoFrameAnalysis = false
    // **This is the exit signal, and it is UIKit's rather than AVKit's.** Apple API
    // limitation: `playerViewControllerDidEndDismissalTransition` is marked unavailable in
    // the iOS 26 SDK ("cannot override … which has been marked unavailable"), so the
    // delegate has nothing to say about Done. This stage getting the screen back means the
    // player is gone, which is the same fact from a layer that still exists. Re-probe the
    // delegate on the next SDK.
    host.onPlayerDismissed = { [weak coordinator = context.coordinator] in
      coordinator?.finish()
    }
    return host
  }

  func updateUIViewController(_ host: PlayerPresentationController, context: Context) {
    if host.playerController.player !== manager.player {
      host.playerController.player = manager.player
    }
  }

  /// The route can be popped from elsewhere while the player is up; the presentation is
  /// AVKit's, so it has to be taken down by hand rather than left orphaned over the app.
  static func dismantleUIViewController(_ host: PlayerPresentationController,
                                        coordinator: Coordinator) {
    coordinator.skip.detach()
    host.dismissPlayerIfNeeded()
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(manager: manager, onFinish: onFinish,
                onRestoreFromPictureInPicture: onRestoreFromPictureInPicture)
  }

  @MainActor
  final class Coordinator: NSObject, @preconcurrency AVPlayerViewControllerDelegate {
    private var manager: PlayerManager
    private let onFinish: () -> Void
    private let onRestoreFromPictureInPicture: (Route) -> Void
    private var didFinish = false
    weak var host: PlayerPresentationController?
    /// The player itself, not through the stage: in Picture in Picture the stage has left
    /// with its route and only `PictureInPictureKeeper` holds the controller.
    weak var controller: AVPlayerViewController?

    init(manager: PlayerManager, onFinish: @escaping () -> Void,
         onRestoreFromPictureInPicture: @escaping (Route) -> Void) {
      self.manager = manager
      self.onFinish = onFinish
      self.onRestoreFromPictureInPicture = onRestoreFromPictureInPicture
    }

    func installEndHandler(on manager: PlayerManager) {
      manager.onPlaybackEnded = { [weak self] action in
        Task { @MainActor in
          guard let self else { return }
          switch action {
          case .dismiss:
            self.finish()
          case .playNext(let episode):
            self.advance(to: episode)
          }
        }
      }
    }

    private func advance(to item: any PlayableItem) {
      let context = AppContext.shared
      let next = PlaybackSession.shared.play(
        item: item,
        mode: .media,
        downloadedFilesDatabase: context.downloadedFilesDatabase,
        actionsService: context.actionsService
      )
      installEndHandler(on: next)
      observeSkip(on: next)
      // Auto-play inside the floating window: the next episode is the one PiP now shows.
      PictureInPictureKeeper.shared.managerDidChange(from: manager, to: next)
      controller?.player = next.player
      manager = next
      Task { await next.preparePlayback() }
    }

    // MARK: Skip

    let skip = SkipChipHost()

    /// The skip chip over the presented player. AVKit on iOS has no `contextualActions`.
    /// Ordinary glass, and it leaves before the transport bar does.
    func observeSkip(on manager: PlayerManager) {
      guard let controller else { return }
      skip.install(on: controller, manager: manager)
      skip.bringToFront()
    }

    /// Leaving happens once, however many times the host reports it.
    func finish() {
      guard !didFinish else { return }
      didFinish = true
      onFinish()
    }

    // MARK: Picture in Picture (`PictureInPictureKeeper`)

    func playerViewControllerWillStartPictureInPicture(_ playerViewController: AVPlayerViewController) {
      // Before the stage reappears: leaving the route now must not end the film.
      manager.setPictureInPictureActive(true)
      PictureInPictureKeeper.shared.willStart(controller: playerViewController,
                                              delegate: self,
                                              manager: manager,
                                              systemInfoActions: [],
                                              push: onRestoreFromPictureInPicture)
    }

    func playerViewController(_ playerViewController: AVPlayerViewController,
                              failedToStartPictureInPictureWithError error: any Error) {
      Logger.app.error("PiP: failed to start: \(error.localizedDescription)")
      manager.setPictureInPictureActive(false)
    }

    func playerViewController(
      _ playerViewController: AVPlayerViewController,
      restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
      PictureInPictureKeeper.shared.restore(completion: completionHandler)
    }

    func playerViewControllerDidStopPictureInPicture(_ playerViewController: AVPlayerViewController) {
      manager.setPictureInPictureActive(false)
      PictureInPictureKeeper.shared.didStop(manager: manager)
    }

    /// **Picture in Picture takes the full-screen player away**, as in the TV app: the
    /// viewer is back on the page they came from while the film plays in the window. Kept
    /// up, the presented player stayed behind the window as a black «playing in Picture in
    /// Picture» placeholder that had to be closed by hand (Sasha, 2026-11-23). The stage
    /// appearing again leaves the route (`finish`); the session stays, because
    /// `PlayerView.endPlayback` skips a manager in PiP. Restore pushes the route back.
    func playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart(
      _ playerViewController: AVPlayerViewController
    ) -> Bool {
      true
    }
  }
}

/// Nothing but a stage for the presentation above: it holds the player controller and
/// puts it on screen once it has a window to present from.
final class PlayerPresentationController: UIViewController {

  let playerController: AVPlayerViewController
  /// Called when the player has been dismissed and this stage is on screen again.
  var onPlayerDismissed: (() -> Void)?
  /// Called once the player's presentation has finished.
  var onPresented: (() -> Void)?
  private var didPresent = false

  init(playerController: AVPlayerViewController) {
    self.playerController = playerController
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    playerController.modalPresentationStyle = .fullScreen
    playerController.modalPresentationCapturesStatusBarAppearance = true
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard presentedViewController == nil else { return }
    guard !didPresent else {
      onPlayerDismissed?()
      return
    }
    // A churned SwiftUI rebuild can resurrect this stage while its hierarchy is
    // detached ("Attempt to present … whose view is not in the window hierarchy").
    // No window → don't present, and don't mark `didPresent` either: a later real
    // appearance must still get its player.
    guard view.window != nil else { return }
    didPresent = true
    present(playerController, animated: true) { [weak self] in
      self?.onPresented?()
      self?.onPresented = nil
    }
  }

  func dismissPlayerIfNeeded() {
    guard playerController.presentingViewController != nil else { return }
    playerController.dismiss(animated: false)
  }
}

#endif

#if os(macOS)

/// The AppKit surface with real chrome knobs — `speeds`, PiP, the full-screen toggle,
/// sharing — none of which SwiftUI's `VideoPlayer` exposes on macOS (see the
/// customization-surface table in player-and-media.md). Still no chrome of ours: every
/// control here is `AVPlayerView`'s own.
private struct MacVideoPlayer: NSViewRepresentable {
  let manager: PlayerManager

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.player = manager.player
    view.allowsPictureInPicturePlayback = true
    view.showsFullScreenToggleButton = true
    view.showsSharingServiceButton = true
    view.speeds = AVPlaybackSpeed.systemDefaultSpeeds
    view.delegate = context.coordinator
    // PiP callbacks are a protocol of their own, on a property of their own.
    view.pictureInPictureDelegate = context.coordinator
    context.coordinator.manager = manager
    context.coordinator.skip.install(on: view, manager: manager)
    context.coordinator.idleControls.attach(to: view)
    return view
  }

  func updateNSView(_ nsView: AVPlayerView, context: Context) {
    if nsView.player !== manager.player {
      nsView.player = manager.player
    }
    context.coordinator.manager = manager
    context.coordinator.skip.install(on: nsView, manager: manager)
    context.coordinator.skip.bringToFront()
  }

  static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
    coordinator.skip.detach()
    coordinator.idleControls.detach()
    nsView.delegate = nil
    nsView.pictureInPictureDelegate = nil
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  /// **The player window steps aside while the picture is elsewhere.** AVKit's full screen
  /// and Picture in Picture both take the video out of this view into a window of their
  /// own and leave a black «playing in full screen / Picture in Picture» placeholder
  /// behind — a second, empty window over the main one (it covered the whole monitor
  /// when zoomed, Sasha 2026-11-21). The `AVPlayerViewDelegate` hooks are Apple's answer
  /// for exactly this: hide the source window once the picture has left, bring it back
  /// in `restoreUserInterfaceFor…` when the picture comes home, and treat a Picture in
  /// Picture closed with its own ✕ as the film being closed.
  ///
  /// Seen on macOS 27.2 (2026-11-22): full screen is `AVDetachedFullscreenWindow`, a window
  /// of AVKit's; the window is ordered out here on did-enter and brought back in
  /// `restoreUserInterfaceForFullScreenExit…`, which AVKit calls before will-exit. With a
  /// `pictureInPictureDelegate` set, AVKit orders the window out at PiP start and back in
  /// on Restore by itself; `stepAside` / `comeBack` are then no-ops. PiP's ✕ calls
  /// did-stop with no restore first — that is the close branch.
  @MainActor
  final class Coordinator: NSObject, @preconcurrency AVPlayerViewDelegate,
    @preconcurrency AVPlayerViewPictureInPictureDelegate {
    let skip = SkipChipHost()
    let idleControls = MacIdleControlsHider()
    weak var manager: PlayerManager?
    /// The player window, held while it is ordered out (a hidden window still owns the
    /// `AVPlayerView`, so the picture can animate back into it).
    private weak var hiddenWindow: NSWindow?
    private var isFullScreen = false
    private var isPictureInPicture = false
    private var restoresFromPictureInPicture = false

    private func stepAside(_ playerView: AVPlayerView) {
      guard let window = playerView.window, window.isVisible else { return }
      hiddenWindow = window
      window.orderOut(nil)
    }

    private func comeBack(_ playerView: AVPlayerView) {
      guard !isFullScreen, !isPictureInPicture else { return }
      let window = playerView.window ?? hiddenWindow
      hiddenWindow = nil
      window?.makeKeyAndOrderFront(nil)
    }

    // MARK: Full screen

    func playerViewWillEnterFullScreen(_ playerView: AVPlayerView) {
      isFullScreen = true
    }

    func playerViewDidEnterFullScreen(_ playerView: AVPlayerView) {
      stepAside(playerView)
    }

    func playerView(_ playerView: AVPlayerView,
                    restoreUserInterfaceForFullScreenExitWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
      isFullScreen = false
      comeBack(playerView)
      completionHandler(true)
    }

    func playerViewDidExitFullScreen(_ playerView: AVPlayerView) {
      isFullScreen = false
      comeBack(playerView)
    }

    // MARK: Picture in Picture

    func playerViewWillStartPicture(inPicture playerView: AVPlayerView) {
      isPictureInPicture = true
      restoresFromPictureInPicture = false
      // Before the window goes: closing it now must not end the film (`endPlayback`).
      manager?.setPictureInPictureActive(true)
    }

    func playerViewDidStartPicture(inPicture playerView: AVPlayerView) {
      stepAside(playerView)
    }

    func playerView(_ playerView: AVPlayerView, failedToStartPictureInPictureWithError error: any Error) {
      Logger.app.error("PiP: failed to start: \(error.localizedDescription)")
      isPictureInPicture = false
      manager?.setPictureInPictureActive(false)
      comeBack(playerView)
    }

    func playerView(_ playerView: AVPlayerView,
                    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
      restoresFromPictureInPicture = true
      isPictureInPicture = false
      comeBack(playerView)
      completionHandler(true)
    }

    func playerViewDidStopPicture(inPicture playerView: AVPlayerView) {
      isPictureInPicture = false
      manager?.setPictureInPictureActive(false)
      if restoresFromPictureInPicture {
        restoresFromPictureInPicture = false
        comeBack(playerView)
        return
      }
      // Closed from the Picture in Picture window: the film is over, as closing the
      // player window is. Closing the scene's window runs `PlayerView.onDisappear`.
      let window = playerView.window ?? hiddenWindow
      hiddenWindow = nil
      window?.close()
    }
  }
}

/// Hides AVKit's floating controls once the pointer has been away from them for 15 s
/// (Sasha, 2026-11-21). AVKit hides them by itself only while the pointer idles over the
/// video; with the pointer on another display or window, the panel stayed up for good.
@MainActor
final class MacIdleControlsHider {
  static let timeout: TimeInterval = 15

  private weak var playerView: AVPlayerView?
  private var timer: Timer?
  private var awaySince: Date?

  func attach(to view: AVPlayerView) {
    playerView = view
    guard timer == nil else { return }
    let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  func detach() {
    timer?.invalidate()
    timer = nil
    awaySince = nil
  }

  private func tick() {
    guard let view = playerView, controlsShown(view),
          let panel = controlsPanel(in: view), let window = panel.window, window.isVisible,
          NSApp.windows.allSatisfy({ !$0.isVisible || !PlayerTransportMenu.looksLikeMenu(String(describing: type(of: $0))) })
    else {
      awaySince = nil
      return
    }
    let frame = window.convertToScreen(panel.convert(panel.bounds, to: nil))
    if frame.contains(NSEvent.mouseLocation) {
      awaySince = nil
      return
    }
    let since = awaySince ?? Date()
    awaySince = since
    if Date().timeIntervalSince(since) >= Self.timeout {
      awaySince = nil
      hideControls(view)
    }
  }

  /// `controlsHidden`: the private, KVO-compliant getter `PlayerChromeMonitor` observes.
  /// The panel's own `isHidden` / `alphaValue` stay put while it is faded out.
  private func controlsShown(_ view: AVPlayerView) -> Bool {
    guard view.responds(to: NSSelectorFromString("controlsHidden")) else { return false }
    return (view.value(forKey: "controlsHidden") as? Bool) == false
  }

  /// The floating panel: AVKit's controls view controller's view, in whichever window it
  /// is in now. In AVKit's full screen that is its own `AVDetachedFullscreenWindow`, with
  /// a different controller (`AVFloatingPlaybackControlsViewController`) — so the window
  /// is the panel's, never the player view's (probed on macOS 27.2, 2026-11-22).
  private func controlsPanel(in view: AVPlayerView) -> NSView? {
    guard let controller = view.value(forKey: "playbackControlsViewController") as? NSViewController,
          controller.isViewLoaded else { return nil }
    return controller.view
  }

  /// No public call hides `AVPlayerView`'s controls, and there is no `setControlsHidden:`.
  /// AVKit's own idle hide is `-[AVDesktopPlayerViewContentView _hideControlsWithTrigger:]`
  /// (`NSUInteger`); trigger 0 fades the panel out in the window and in full screen, and the
  /// next pointer move brings it back as usual. Missing on a future SDK → AVKit's behaviour.
  private func hideControls(_ view: AVPlayerView) {
    guard let ivar = class_getInstanceVariable(AVPlayerView.self, "_contentView"),
          let content = object_getIvar(view, ivar) as? NSView else { return }
    let selector = NSSelectorFromString("_hideControlsWithTrigger:")
    guard content.responds(to: selector),
          let imp = class_getMethodImplementation(type(of: content), selector) else { return }
    typealias Hide = @convention(c) (AnyObject, Selector, UInt) -> Void
    unsafeBitCast(imp, to: Hide.self)(content, selector, 0)
  }
}


/// Transparent title bar over the video — no opaque underlay behind the traffic lights.
private struct MacPlayerTitlebarChrome: NSViewRepresentable {
  var title: String

  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    view.isHidden = true
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      guard let window = nsView.window else { return }
      window.title = title
      window.titlebarAppearsTransparent = true
      if !window.styleMask.contains(.fullSizeContentView) {
        window.styleMask.insert(.fullSizeContentView)
      }
    }
  }
}

#endif

/// Opens the player wherever the platform puts it, so no call site has to know.
///
/// tvOS and iOS push it onto the navigation stack — on TV the system player screen owns
/// the display and Menu leaves, on iOS AVKit lifts itself full-screen and draws Done.
/// macOS gets its own window, the way the stock TV app takes a film out of the page it
/// was on: the title bar carries the name and the close button, and ⌘W works.
struct PlayerLink<Label: View>: View {

  private let route: any Hashable
  private let item: any PlayableItem
  private let mode: WatchMode
  private let label: Label

#if os(macOS)
  @Environment(\.openWindow) private var openWindow
#endif

  init(route: any Hashable,
       item: any PlayableItem,
       mode: WatchMode,
       @ViewBuilder label: () -> Label) {
    self.route = route
    self.item = item
    self.mode = mode
    self.label = label()
  }

  var body: some View {
#if os(macOS)
    Button {
      PlaybackWindowState.shared.show(item: item, mode: mode)
      openWindow(id: PlaybackWindowState.windowID)
    } label: {
      label
    }
#else
    NavigationLink(value: route) {
      label
    }
#endif
  }
}

#if os(macOS)

/// What the player window is currently showing. One window: a second film replaces the
/// first rather than piling up, which is what the stock TV app does too.
///
/// Shared rather than injected, following `AppContext.shared`: a `Button` deep in the
/// item page needs to write to it, and threading an `@EnvironmentObject` down for that
/// would crash every preview that doesn't know to inject one.
@MainActor
final class PlaybackWindowState: ObservableObject {

  static let shared = PlaybackWindowState()
  static let windowID = "player"

  struct Request: Identifiable {
    let id = UUID()
    let item: any PlayableItem
    let mode: WatchMode
  }

  @Published var request: Request?

  /// Put a film in the window. **A play for what is already in there is that window coming
  /// forward, not a new screen:** the request identifies the player's view (see
  /// `PlayerWindowContent`), so replacing it would tear the screen down and rebuild it on
  /// top of a stream that is already running.
  func show(item: any PlayableItem, mode: WatchMode) {
    if let request, request.item.id == item.id, request.mode == mode { return }
    request = Request(item: item, mode: mode)
  }
}

/// Contents of the player window. Identity follows the live `PlayerManager`: a next-item
/// swap retargets that manager in place (KP-35), so keying by request UUID — which forced
/// a teardown and a black flash — is gone. A fresh manager after close still gets a new id.
struct PlayerWindowContent: View {

  @ObservedObject private var playback = PlaybackWindowState.shared
  @ObservedObject private var session = PlaybackSession.shared
  @Environment(\.appContext) private var appContext
  @Environment(ErrorHandler.self) private var errorHandler

  var body: some View {
    if let request = playback.request {
      let manager = session.play(
        item: request.item,
        mode: request.mode,
        downloadedFilesDatabase: appContext.downloadedFilesDatabase,
        actionsService: appContext.actionsService
      )
      PlayerView(manager: manager)
        .id(ObjectIdentifier(manager))
        .handleError(state: Bindable(errorHandler).state)
    } else {
      // Reachable by reopening the window from the Window menu after it was closed.
      Text("Nothing is playing")
        .foregroundStyle(.secondary)
        .frame(minWidth: 480, minHeight: 270)
    }
  }
}

#endif
