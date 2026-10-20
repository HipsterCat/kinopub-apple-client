//
//  PictureInPictureKeeper.swift
//  KinoPubAppleClient
//
//  Picture in Picture on tvOS, for a player that is a navigation push.
//

#if os(tvOS)
import AVKit
import KinoPubLogging
import OSLog

/// **What Picture in Picture needs that a pushed player does not give it.**
///
/// Apple's tvOS sample (*Adopting Picture in Picture Playback in tvOS*) *presents* its
/// `AVPlayerViewController`: AVKit dismisses it when PiP starts
/// (`playerViewControllerShouldAutomaticallyDismissAtPictureInPictureStart`) and the app
/// presents the same controller again in
/// `playerViewController(_:restoreUserInterfaceForPictureInPictureStopWithCompletionHandler:)`.
/// It also declares `UIBackgroundModes: audio` and the `.playback` session — both are in
/// place (`Info.plist`, `PlaybackAudioSession`).
///
/// Ours is a route on the tab's `NavigationStack`, so this does both halves by hand:
///
/// 1. **Start** — the screen leaves the route, the way Menu does, and the session is kept
///    (`PlayerView.endPlayback` skips a manager in PiP). The controller and its delegate
///    would go with the route, so they are held here; AVKit only holds its delegate weakly.
/// 2. **Back to full screen** — a fresh player route is pushed for what is playing. The
///    session is told the new route's token first (`PlaybackSession.adopt`), so the route
///    finds the same manager, and `TVVideoPlayer` takes the held controller rather than
///    making one — the picture AVKit is animating back belongs to it.
/// 3. **Closed** — the viewer shut the window: the film ends, as leaving the player does.
///
/// Not verifiable in the simulator: `AVPictureInPictureController.isPictureInPictureSupported()`
/// answers false on the tvOS 26.5 runtime, and Apple's sample says "physical device". Every
/// step logs under `PiP:` for a device run.
@MainActor
final class PictureInPictureKeeper {
  static let shared = PictureInPictureKeeper()

  private init() {}

  private var controller: AVPlayerViewController?
  /// The coordinator that was the controller's delegate when PiP started.
  private var delegate: AVPlayerViewControllerDelegate?
  private var manager: PlayerManager?
  /// The system's own Info buttons, read from the controller before anything set them — a
  /// later read answers empty (tvOS 27.2), and the restored screen needs them.
  private(set) var systemInfoActions: [UIAction] = []
  /// Pushes a route on the stack the player left; set by the screen as PiP starts.
  private var push: ((Route) -> Void)?
  private var pendingRestore: ((Bool) -> Void)?
  private var isRestoring = false

  /// PiP is about to start: hold what the leaving route would release.
  func willStart(controller: AVPlayerViewController,
                 delegate: AVPlayerViewControllerDelegate,
                 manager: PlayerManager,
                 systemInfoActions: [UIAction],
                 push: @escaping (Route) -> Void) {
    Logger.app.info("PiP: will start, item \(manager.pictureInPictureLogID)")
    self.controller = controller
    self.delegate = delegate
    self.manager = manager
    self.systemInfoActions = systemInfoActions
    self.push = push
    isRestoring = false
  }

  /// The held controller, when it is `manager`'s — a restored route takes it instead of a
  /// new one. Hands over the restore AVKit is waiting on.
  func takeController(for manager: PlayerManager) -> AVPlayerViewController? {
    guard isRestoring, manager === self.manager, let controller else { return nil }
    Logger.app.info("PiP: restored route took the held controller")
    if let pendingRestore {
      self.pendingRestore = nil
      // AVKit animates the picture back into this controller's view; the route has just
      // put it in the hierarchy, and it is on screen by the next turn of the run loop.
      DispatchQueue.main.async { pendingRestore(true) }
    }
    return controller
  }

  /// An episode played on inside the window (`Coordinator.advance`): it is what PiP holds now.
  func managerDidChange(from old: PlayerManager, to new: PlayerManager) {
    guard old === manager else { return }
    Logger.app.info("PiP: played on to item \(new.pictureInPictureLogID)")
    new.setPictureInPictureActive(true)
    manager = new
  }

  /// AVKit asks for the full-screen player back.
  func restore(completion: @escaping (Bool) -> Void) {
    let token = UUID()
    guard let manager, let push, let route = manager.pictureInPictureRoute(token: token),
          PlaybackSession.shared.adopt(manager, token: token) else {
      Logger.app.error("PiP: restore refused — nothing held, or the session moved on")
      completion(false)
      return
    }
    Logger.app.info("PiP: restoring item \(manager.pictureInPictureLogID)")
    isRestoring = true
    pendingRestore = completion
    push(route)
  }

  /// PiP ended — back to full screen, or the window was closed.
  func didStop(manager: PlayerManager) {
    guard manager === self.manager else { return }
    if isRestoring {
      Logger.app.info("PiP: stopped into the restored player")
    } else {
      Logger.app.info("PiP: closed — ending item \(manager.pictureInPictureLogID)")
      PlaybackSession.shared.stop(manager)
    }
    pendingRestore?(false)
    controller = nil
    delegate = nil
    self.manager = nil
    push = nil
    pendingRestore = nil
    isRestoring = false
  }
}
#endif
