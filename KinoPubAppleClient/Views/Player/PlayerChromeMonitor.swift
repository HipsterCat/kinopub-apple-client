//
//  PlayerChromeMonitor.swift
//  KinoPubAppleClient
//
//  The skip chip follows the system player chrome, and leaves first.
//
//  **Apple API limitation:** `playerViewController(_:willTransitionToVisibilityOfTransportBar:withAnimationCoordinator:)`
//  is tvOS-only (`API_UNAVAILABLE` on iOS and macOS; header, iOS 27 / macOS 27). There is
//  no public "controls are visible" callback on the platforms that draw this chip.
//  macOS `AVPlayerView` does publish it, as the private KVO keys `controlsHidden` and
//  `showsControlsPane`, and `setCanHideControls:` keeps the chrome up (probed on the
//  macOS 27.2 SDK: pinning leaves the pane up, unpinning lets it hide). iOS has neither
//  key on the public controller, so the chrome view is found by class name and its
//  public `alpha` / `isHidden` are what we watch. Re-probe on the next SDK.
//
//  A menu owned by that chrome (subtitles, audio, anything else the transport bar
//  presents) hides the chip and pins the chrome. The menu must not be left up after
//  its parent chrome has gone.
//

import AVFoundation
import AVKit
import OSLog
import SwiftUI
import KinoPubLogging
import KinoPubUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Class-name heuristics for transport menus (Speed, Subtitles, Audio, …).
/// Shared by the iOS / macOS chrome monitor and the tvOS skip gate.
enum PlayerTransportMenu {
  static func looksLikeMenu(_ name: String) -> Bool {
    name.contains("ContextMenu")
      || name.contains("Popover")
      || name.contains("MediaSelection")
      || name.contains("Callout")
      || name.contains("PlaybackSpeed")
      || name.contains("SpeedMenu")
      || name.contains("SpeedPicker")
      || name.contains("AVKitMenu")
      || name.contains("DropDown")
      || (name.contains("Menu") && (name.contains("Transport") || name.contains("Playback")
                                    || name.contains("Speed") || name.contains("Audio")
                                    || name.contains("Subtitle") || name.contains("Legible")
                                    || name.contains("Audible")))
  }
}

#if os(tvOS)

/// tvOS Skip gate: menus that sit over the player while (or without) the transport bar.
@MainActor
enum TVPlayerChrome {
  static func menuActive(in controller: AVPlayerViewController) -> Bool {
    if controller.presentedViewController != nil { return true }
    if viewTreeHasMenu(controller.view) { return true }
    if windowsHaveMenu(besides: controller.view.window) { return true }
    return false
  }

  private static func viewTreeHasMenu(_ root: UIView) -> Bool {
    var found = false
    func walk(_ view: UIView, depth: Int) {
      if found || depth > 8 { return }
      let name = String(describing: type(of: view))
      if PlayerTransportMenu.looksLikeMenu(name), !view.isHidden, view.alpha > 0.05 {
        found = true
        return
      }
      for subview in view.subviews { walk(subview, depth: depth + 1) }
    }
    walk(root, depth: 0)
    return found
  }

  private static func windowsHaveMenu(besides playerWindow: UIWindow?) -> Bool {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
      for window in scene.windows where window !== playerWindow && !window.isHidden && window.alpha > 0.05 {
        let name = String(describing: type(of: window))
        if PlayerTransportMenu.looksLikeMenu(name) { return true }
        if window.subviews.contains(where: {
          PlayerTransportMenu.looksLikeMenu(String(describing: type(of: $0))) && !$0.isHidden
        }) {
          return true
        }
      }
    }
    return false
  }
}

#endif

#if !os(tvOS)

/// Address passed to KVO. File-scoped so the nonisolated observer callback can
/// recognise it; the class itself is main-actor isolated.
nonisolated(unsafe) private var skipChromeKVOContext = 0

@MainActor
final class PlayerChromeMonitor: NSObject, ObservableObject {

  @Published private(set) var controlsVisible = true
  @Published private(set) var menuActive = false
  /// Set while `revealChrome` writes, so the KVO it triggers cannot re-enter it.
  private var isRevealingChrome = false

  private weak var manager: PlayerManager?
  private var timer: Timer?
  private var observations: [NSKeyValueObservation] = []
  private var notificationTokens: [NSObjectProtocol] = []
  private var menuDepth = 0
  private var chromePinned = false
  private var pipWanted = false
  private var artworkURL: URL?
  private var didLogMissingVideo = false
  private var kvoTargets: [(object: NSObject, key: String)] = []

#if os(macOS)
  private weak var playerView: AVPlayerView?
  private var videoView: NSView?
  private var savedVideoFrame: NSRect?
  private var savedAutoresizing: NSView.AutoresizingMask?
  private var artworkHost: NSHostingView<SkipArtworkFill>?
  private var pinningTarget: NSObject?
#else
  private weak var controller: AVPlayerViewController?
  private var videoView: UIView?
  private var controlsView: UIView?
  private var savedVideoFrame: CGRect?
  private var savedAutoresizing: UIView.AutoresizingMask?
  private var artworkHost: UIHostingController<SkipArtworkFill>?
  private var pinningTarget: NSObject?
#endif

  isolated deinit {
    // `detach` is idempotent, so a representable `dismantle` that already ran is a
    // no-op here.
    detach()
  }

#if os(macOS)
  func attach(manager: PlayerManager, playerView: AVPlayerView) {
    if self.manager === manager, self.playerView === playerView, timer != nil { return }
    detach()
    self.manager = manager
    self.playerView = playerView
    pinningTarget = playerView
    observeMacChrome(playerView)
    observeMacMenus()
    startTimer()
  }
#endif

#if os(iOS)
  func attach(manager: PlayerManager, controller: AVPlayerViewController) {
    if self.manager === manager, self.controller === controller, timer != nil { return }
    detach()
    self.manager = manager
    self.controller = controller
    if controller.responds(to: NSSelectorFromString("setCanHideControls:")) {
      pinningTarget = controller
    } else if (controller.view as NSObject).responds(to: NSSelectorFromString("setCanHideControls:")) {
      pinningTarget = controller.view
    }
    observeIOSChrome()
    startTimer()
  }
#endif

  func detach() {
    timer?.invalidate()
    timer = nil
    for token in notificationTokens {
      NotificationCenter.default.removeObserver(token)
    }
    notificationTokens.removeAll()
    observations.removeAll()
    for target in kvoTargets {
      target.object.removeObserver(self, forKeyPath: target.key, context: &skipChromeKVOContext)
    }
    kvoTargets.removeAll()
    if chromePinned {
      setCanHideControls(true)
      chromePinned = false
    }
    restoreVideo()
    manager = nil
  }

  func setPictureInPicture(active: Bool, artworkURL: URL?) {
    pipWanted = active
    self.artworkURL = artworkURL
    if active {
      applyPictureInPicture()
    } else {
      restoreVideo()
    }
  }

  // MARK: - Chrome visibility

  private func startTimer() {
    let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated { self?.tick() }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func tick() {
    refreshMenu()
    #if os(iOS)
    if controlsView == nil { observeIOSChrome() }
    #endif
    #if os(macOS)
    pollMacChrome()
    #endif
    if pipWanted { applyPictureInPicture() }
    updateSuspension()
  }

  private func publish(visible: Bool) {
    if controlsVisible != visible {
      controlsVisible = visible
    }
    updateSuspension()
  }

  private func updateSuspension() {
    manager?.skipCountdownSuspended = SkipChipVisibility.countdownSuspended(
      chromeVisible: controlsVisible,
      menuActive: menuActive,
      chipFollowsChrome: SkipChipVisibility.followsChrome
    )
  }

  private func setMenu(_ active: Bool) {
    guard menuActive != active else { return }
    // A menu pins the chrome (`setCanHideControls:false`): logged, so a panel that stays
    // up can be told apart from one pinned by a menu we think is still open.
    Logger.app.info("Player chrome: menu \(active ? "open, controls pinned" : "closed, controls free", privacy: .public)")
    menuActive = active
    if active {
      setCanHideControls(false)
      chromePinned = true
      revealChrome()
    } else if chromePinned {
      setCanHideControls(true)
      chromePinned = false
    }
    updateSuspension()
  }

  /// `setCanHideControls:` — private, probed on macOS 27.2. A missing selector is a no-op.
  private func setCanHideControls(_ canHide: Bool) {
    guard let target = pinningTarget else { return }
    let selector = NSSelectorFromString("setCanHideControls:")
    guard target.responds(to: selector) else { return }
    let implementation = target.method(for: selector)
    typealias Setter = @convention(c) (AnyObject, Selector, Bool) -> Void
    let setter = unsafeBitCast(implementation, to: Setter.self)
    setter(target, selector, canHide)
  }

  // MARK: - Picture in Picture stage

  private func applyPictureInPicture() {
#if os(macOS)
    guard let playerView, let video = videoHost(in: playerView) else {
      logMissingVideo()
      return
    }
    installArtwork(behind: video, in: video.superview ?? playerView, url: artworkURL)
    if savedVideoFrame == nil {
      savedVideoFrame = video.frame
      savedAutoresizing = video.autoresizingMask
    }
    video.frame = pipFrame(in: (video.superview ?? playerView).bounds, flipped: video.isFlipped)
    video.autoresizingMask = video.isFlipped
      ? [.minXMargin, .minYMargin]
      : [.minXMargin, .maxYMargin]
    video.wantsLayer = true
    video.layer?.cornerRadius = 16
    video.layer?.masksToBounds = true
    self.videoView = video
#else
    guard let controller, let video = videoHost(in: controller.view) else {
      logMissingVideo()
      return
    }
    installArtwork(behind: video, in: video.superview ?? controller.view, url: artworkURL, parent: controller)
    if savedVideoFrame == nil {
      savedVideoFrame = video.frame
      savedAutoresizing = video.autoresizingMask
    }
    video.frame = pipFrame(in: (video.superview ?? controller.view).bounds)
    video.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin]
    video.layer.cornerRadius = 16
    video.layer.masksToBounds = true
    self.videoView = video
#endif
  }

  private func restoreVideo() {
#if os(macOS)
    if let video = videoView, let frame = savedVideoFrame {
      video.frame = frame
      if let savedAutoresizing { video.autoresizingMask = savedAutoresizing }
      video.layer?.cornerRadius = 0
      video.layer?.masksToBounds = false
    }
    artworkHost?.removeFromSuperview()
    artworkHost = nil
#else
    if let video = videoView, let frame = savedVideoFrame {
      video.frame = frame
      if let savedAutoresizing { video.autoresizingMask = savedAutoresizing }
      video.layer.cornerRadius = 0
      video.layer.masksToBounds = false
    }
    artworkHost?.willMove(toParent: nil)
    artworkHost?.view.removeFromSuperview()
    artworkHost?.removeFromParent()
    artworkHost = nil
#endif
    videoView = nil
    savedVideoFrame = nil
    savedAutoresizing = nil
  }

  private func logMissingVideo() {
    guard !didLogMissingVideo else { return }
    didLogMissingVideo = true
    Logger.app.debug("Skip PiP: no video view to shrink")
  }

#if os(macOS)
  private func pipFrame(in bounds: NSRect, flipped: Bool) -> NSRect {
    let width = max(240, bounds.width * 0.36)
    let height = width * 9 / 16
    let x = bounds.width - width - 32
    let y = flipped ? bounds.height - height - 110 : 110
    return NSRect(x: x, y: y, width: width, height: height)
  }

  private func videoHost(in root: NSView) -> NSView? {
    var best: NSView?
    var bestArea = CGFloat.greatestFiniteMagnitude
    func walk(_ view: NSView) {
      if view !== root, hasPlayerLayer(view) {
        let area = view.bounds.width * view.bounds.height
        if area > 0, area < bestArea {
          best = view
          bestArea = area
        }
      }
      for subview in view.subviews { walk(subview) }
    }
    walk(root)
    return best
  }

  private func hasPlayerLayer(_ view: NSView) -> Bool {
    if view.layer is AVPlayerLayer { return true }
    return view.layer?.sublayers?.contains { $0 is AVPlayerLayer } ?? false
  }

  private func installArtwork(behind video: NSView, in parent: NSView, url: URL?) {
    let host: NSHostingView<SkipArtworkFill>
    if let artworkHost {
      host = artworkHost
      host.rootView = SkipArtworkFill(url: url)
    } else {
      host = NSHostingView(rootView: SkipArtworkFill(url: url))
      host.translatesAutoresizingMaskIntoConstraints = true
      host.autoresizingMask = [.width, .height]
      artworkHost = host
    }
    host.frame = parent.bounds
    if host.superview !== parent {
      parent.addSubview(host, positioned: .below, relativeTo: video)
    }
  }
#else
  private func pipFrame(in bounds: CGRect) -> CGRect {
    let width = max(160, bounds.width * 0.36)
    let height = width * 9 / 16
    return CGRect(x: bounds.width - width - 24,
                  y: bounds.height - height - 120,
                  width: width,
                  height: height)
  }

  private func videoHost(in root: UIView) -> UIView? {
    var best: UIView?
    var bestArea = CGFloat.greatestFiniteMagnitude
    func walk(_ view: UIView) {
      if view !== root, hasPlayerLayer(view) {
        let area = view.bounds.width * view.bounds.height
        if area > 0, area < bestArea {
          best = view
          bestArea = area
        }
      }
      for subview in view.subviews { walk(subview) }
    }
    walk(root)
    return best
  }

  private func hasPlayerLayer(_ view: UIView) -> Bool {
    if view.layer is AVPlayerLayer { return true }
    return view.layer.sublayers?.contains { $0 is AVPlayerLayer } ?? false
  }

  private func installArtwork(behind video: UIView, in parent: UIView, url: URL?, parent controller: AVPlayerViewController) {
    let host: UIHostingController<SkipArtworkFill>
    if let artworkHost {
      host = artworkHost
      host.rootView = SkipArtworkFill(url: url)
    } else {
      host = UIHostingController(rootView: SkipArtworkFill(url: url))
      host.view.backgroundColor = .clear
      host.view.isUserInteractionEnabled = false
      host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      artworkHost = host
      controller.addChild(host)
      host.didMove(toParent: controller)
    }
    host.view.frame = parent.bounds
    if host.view.superview !== parent {
      parent.insertSubview(host.view, belowSubview: video)
    }
  }
#endif

  // MARK: - Menus

  private func refreshMenu() {
#if os(macOS)
    let tracking = menuDepth > 0 || auxiliaryMenuWindow()
    setMenu(tracking)
    if tracking { revealChrome() }
#else
    guard let controller else { return }
    let presented = controller.presentedViewController != nil
    let hierarchy = viewTreeHasMenu(controller.view)
    let window = windowsHaveMenu(besides: controller.view.window)
    let active = presented || hierarchy || window
    setMenu(active)
    if active { revealChrome() }
#endif
  }

#if os(macOS)
  private func observeMacChrome(_ view: AVPlayerView) {
    // The keys are private but KVO-compliant (macOS 27.2). Observing a missing key
    // would raise; both getters answer here.
    if view.responds(to: NSSelectorFromString("controlsHidden")) {
      view.addObserver(self, forKeyPath: "controlsHidden", options: [.new], context: &skipChromeKVOContext)
      kvoTargets.append((view, "controlsHidden"))
    }
    if view.responds(to: NSSelectorFromString("showsControlsPane")) {
      view.addObserver(self, forKeyPath: "showsControlsPane", options: [.new], context: &skipChromeKVOContext)
      kvoTargets.append((view, "showsControlsPane"))
    }
    if let controls = view.value(forKey: "playbackControlsViewController") as? NSViewController {
      observations.append(controls.view.observe(\.alphaValue, options: [.new]) { [weak self] host, _ in
        MainActor.assumeIsolated {
          guard let self, !self.menuActive else { return }
          if host.alphaValue < 0.98 { self.publish(visible: false) }
        }
      })
    }
  }

  /// `controlsHidden` does not post KVO for every change: a hide through AVKit's
  /// `_hideControlsWithTrigger:` in full screen (as full screen opens) left the key at
  /// true with no notification, and the chip stayed up over a bare picture (probed on
  /// macOS 27.2). The tick reads it as well; KVO stays for the quick edge.
  private func pollMacChrome() {
    guard !menuActive, let view = playerView, view.responds(to: NSSelectorFromString("controlsHidden")),
          let hidden = view.value(forKey: "controlsHidden") as? Bool else { return }
    if controlsVisible == hidden { publish(visible: !hidden) }
  }

  private func observeMacMenus() {
    let center = NotificationCenter.default
    notificationTokens.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, self.menuOwnsThisPlayer() else { return }
        self.menuDepth += 1
        self.setMenu(true)
      }
    })
    notificationTokens.append(center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self else { return }
        self.menuDepth = max(0, self.menuDepth - 1)
        if self.menuDepth == 0, !self.auxiliaryMenuWindow() { self.setMenu(false) }
      }
    })
  }

  private func menuOwnsThisPlayer() -> Bool {
    guard let window = playerView?.window else { return false }
    let key = NSApp.keyWindow
    return key === window || key?.parent === window
  }

  private func auxiliaryMenuWindow() -> Bool {
    guard let window = playerView?.window else { return false }
    let extras = [window] + (window.childWindows ?? [])
    return extras.contains { candidate in
      let name = String(describing: type(of: candidate))
      // AppKit menus often land in a child window whose class is simply *Menu* /
      // *Popover*; the shared heuristics cover Speed and track pickers too.
      return candidate !== window
        && (name.contains("Menu") || name.contains("Popover")
            || PlayerTransportMenu.looksLikeMenu(name))
    }
  }

  private func revealChrome() {
    guard !isRevealingChrome, let view = playerView else { return }
    if let controls = view.value(forKey: "playbackControlsViewController") as? NSViewController {
      isRevealingChrome = true
      defer { isRevealingChrome = false }
      if controls.view.alphaValue < 1 { controls.view.alphaValue = 1 }
      if controls.view.isHidden { controls.view.isHidden = false }
    }
  }

  nonisolated override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
    guard context == &skipChromeKVOContext else { return }
    let hidden = (change?[.newKey] as? NSNumber)?.boolValue ?? false
    let path = keyPath
    Task { @MainActor [weak self] in
      guard let self else { return }
      guard !self.menuActive else {
        self.revealChrome()
        return
      }
      if path == "controlsHidden" {
        self.publish(visible: !hidden)
      } else if path == "showsControlsPane" {
        if !hidden { self.publish(visible: true) }
      }
    }
  }
#else
  private func observeIOSChrome() {
    guard let root = controller?.view else { return }
    guard let controls = controlsHost(in: root) else { return }
    controlsView = controls
    observations.append(controls.observe(\.alpha, options: [.new]) { [weak self] host, _ in
      MainActor.assumeIsolated {
        self?.noteControls(alpha: host.alpha, hidden: host.isHidden)
      }
    })
    observations.append(controls.observe(\.isHidden, options: [.new]) { [weak self] host, _ in
      MainActor.assumeIsolated {
        self?.noteControls(alpha: host.alpha, hidden: host.isHidden)
      }
    })
  }

  private func noteControls(alpha: CGFloat, hidden: Bool) {
    if menuActive {
      revealChrome()
      return
    }
    // Alpha leaving 1 is the chrome starting its fade. The chip dissolves on that
    // edge, and its 0.22s finishes while the chrome is still going.
    publish(visible: !hidden && alpha > 0.98)
  }

  private func controlsHost(in root: UIView) -> UIView? {
    var best: UIView?
    var bestArea: CGFloat = 0
    func walk(_ view: UIView) {
      let name = String(describing: type(of: view))
      let looksLikeChrome = name.contains("PlaybackControls")
        || name.contains("TransportControls")
        || name.contains("ChromelessControls")
        || name.hasSuffix("ControlsView")
      if looksLikeChrome {
        let area = view.bounds.width * view.bounds.height
        if area >= bestArea {
          best = view
          bestArea = area
        }
      }
      for subview in view.subviews { walk(subview) }
    }
    walk(root)
    return best
  }

  /// KVO on `alpha` / `isHidden` fires on every set, even of the same value, and the
  /// observer above calls back here while a menu is open — so setting unconditionally
  /// recursed until the stack ran out (crash on the audio-track menu, 2026-11-16).
  /// Write only what changed, and never from inside our own write.
  private func revealChrome() {
    guard !isRevealingChrome, let controls = controlsView else { return }
    guard controls.alpha < 1 || controls.isHidden else { return }
    isRevealingChrome = true
    defer { isRevealingChrome = false }
    if controls.alpha < 1 { controls.alpha = 1 }
    if controls.isHidden { controls.isHidden = false }
  }

  private func viewTreeHasMenu(_ root: UIView) -> Bool {
    var found = false
    func walk(_ view: UIView, depth: Int) {
      if found || depth > 8 { return }
      let name = String(describing: type(of: view))
      if menuClassName(name), !view.isHidden, view.alpha > 0.05 {
        found = true
        return
      }
      for subview in view.subviews { walk(subview, depth: depth + 1) }
    }
    walk(root, depth: 0)
    return found
  }

  private func windowsHaveMenu(besides playerWindow: UIWindow?) -> Bool {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    for scene in scenes {
      for window in scene.windows where window !== playerWindow && !window.isHidden && window.alpha > 0.05 {
        let name = String(describing: type(of: window))
        if menuClassName(name) { return true }
        if window.subviews.contains(where: { menuClassName(String(describing: type(of: $0))) && !$0.isHidden }) {
          return true
        }
      }
    }
    return false
  }

  private func menuClassName(_ name: String) -> Bool {
    PlayerTransportMenu.looksLikeMenu(name)
  }
#endif
}

/// Hosts the chip over the system player and lets taps through everywhere except the buttons.
@MainActor
final class SkipChipHost {
  let chrome = PlayerChromeMonitor()
  let hitRegions = SkipHitRegions()
#if os(macOS)
  private var box: PlayerHitThroughView?
  private var hosting: NSHostingView<SkipChipOverlay>?
#else
  private var box: PlayerHitThroughView?
  private var hosting: UIHostingController<SkipChipOverlay>?
#endif

#if os(macOS)
  private weak var attachedView: AVPlayerView?
  private weak var attachedManager: PlayerManager?

  func install(on playerView: AVPlayerView, manager: PlayerManager) {
    let same = attachedView === playerView && attachedManager === manager && hosting != nil
    if !same {
      chrome.attach(manager: manager, playerView: playerView)
      attachedView = playerView
      attachedManager = manager
    }
    let overlay = SkipChipOverlay(manager: manager, chrome: chrome, hitRegions: hitRegions)
    if let hosting {
      if !same { hosting.rootView = overlay }
      return
    }
    let host = NSHostingView(rootView: overlay)
    host.translatesAutoresizingMaskIntoConstraints = false
    let box = PlayerHitThroughView()
    box.hosting = host
    box.regions = hitRegions
    box.translatesAutoresizingMaskIntoConstraints = false
    box.addSubview(host)
    NSLayoutConstraint.activate([
      host.leadingAnchor.constraint(equalTo: box.leadingAnchor),
      host.trailingAnchor.constraint(equalTo: box.trailingAnchor),
      host.topAnchor.constraint(equalTo: box.topAnchor),
      host.bottomAnchor.constraint(equalTo: box.bottomAnchor),
    ])
    self.box = box
    self.hosting = host
    place(box, in: Self.chipParent(of: playerView))
  }

  /// **The chip rides in AVKit's content view, so it goes to full screen with the picture.**
  /// AVKit's full screen is a window of its own (`AVDetachedFullscreenWindow`) that takes
  /// `AVPlayerView`'s content view — video, controls and all — and leaves the
  /// `AVPlayerView` behind in the player window, which we order out. A box added to the
  /// `AVPlayerView` itself stayed there, unseen (Sasha, 2026-11-23). Inside the content
  /// view it moves with the picture both ways, and the controls' `controlsHidden` KVO on
  /// the `AVPlayerView` still follows the full-screen panel (probed on macOS 27.2).
  /// The content view is AVKit's private `_contentView` ivar, made lazily; until it
  /// exists, and on an SDK without it, the box sits on the `AVPlayerView` as before.
  private static func chipParent(of playerView: AVPlayerView) -> NSView {
    guard let ivar = class_getInstanceVariable(AVPlayerView.self, "_contentView"),
          let content = object_getIvar(playerView, ivar) as? NSView else { return playerView }
    return content
  }

  private func place(_ box: NSView, in parent: NSView) {
    guard box.superview !== parent || parent.subviews.last !== box else { return }
    // Re-adding drops the box's constraints to its parent, so they are made again.
    box.removeFromSuperview()
    parent.addSubview(box)
    NSLayoutConstraint.activate([
      box.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
      box.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
      box.topAnchor.constraint(equalTo: parent.topAnchor),
      box.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
    ])
  }
#endif

#if os(iOS)
  private weak var attachedManager: PlayerManager?

  func install(on controller: AVPlayerViewController, manager: PlayerManager) {
    let overlay = SkipChipOverlay(manager: manager, chrome: chrome, hitRegions: hitRegions)
    if attachedManager !== manager || hosting == nil {
      chrome.attach(manager: manager, controller: controller)
      attachedManager = manager
      hosting?.rootView = overlay
    }
    if let hosting {
      return
    }
    let host = UIHostingController(rootView: overlay)
    host.view.backgroundColor = .clear
    host.safeAreaRegions = []
    let box = PlayerHitThroughView()
    box.hosting = host.view
    box.regions = hitRegions
    box.backgroundColor = .clear
    box.translatesAutoresizingMaskIntoConstraints = false
    host.view.translatesAutoresizingMaskIntoConstraints = false
    controller.addChild(host)
    controller.view.addSubview(box)
    box.addSubview(host.view)
    NSLayoutConstraint.activate([
      box.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
      box.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
      box.topAnchor.constraint(equalTo: controller.view.topAnchor),
      box.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
      host.view.leadingAnchor.constraint(equalTo: box.leadingAnchor),
      host.view.trailingAnchor.constraint(equalTo: box.trailingAnchor),
      host.view.topAnchor.constraint(equalTo: box.topAnchor),
      host.view.bottomAnchor.constraint(equalTo: box.bottomAnchor),
    ])
    host.didMove(toParent: controller)
    self.box = box
    self.hosting = host
  }
#endif

  func detach() {
    chrome.detach()
#if os(macOS)
    attachedView = nil
    attachedManager = nil
    box?.removeFromSuperview()
#else
    attachedManager = nil
    hosting?.willMove(toParent: nil)
    box?.removeFromSuperview()
    hosting?.removeFromParent()
#endif
    box = nil
    hosting = nil
  }

  func bringToFront() {
#if os(macOS)
    guard let box, let playerView = attachedView else { return }
    place(box, in: Self.chipParent(of: playerView))
#else
    guard let box, let parent = box.superview else { return }
    parent.bringSubviewToFront(box)
#endif
  }
}

#if os(macOS)
private final class PlayerHitThroughView: NSView {
  weak var hosting: NSView?
  weak var regions: SkipHitRegions?

  override func hitTest(_ point: NSPoint) -> NSView? {
    guard let hosting, let regions, !isHidden else { return nil }
    // `point` is in the superview's coordinates.
    let local = hosting.convert(point, from: superview)
    let flipped = hosting.isFlipped ? local : NSPoint(x: local.x, y: hosting.bounds.height - local.y)
    guard regions.contains(flipped) else { return nil }
    return super.hitTest(point) ?? hosting
  }
}
#else
private final class PlayerHitThroughView: UIView {
  weak var hosting: UIView?
  weak var regions: SkipHitRegions?

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    guard let hosting, let regions, !isHidden else { return nil }
    guard regions.contains(convert(point, to: hosting)) else { return nil }
    let hit = super.hitTest(point, with: event)
    return hit === self || hit == nil ? hosting : hit
  }
}
#endif

#endif
