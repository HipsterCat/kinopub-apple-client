//
//  MacPlayerWindowChrome.swift
//  KinoPubAppleClient
//
//  The macOS player window dressed the way IINA dresses its own (Sasha, 2026-11-23):
//  always dark, the title bar over the picture and only while the controls are up, the
//  green button taking the window itself to full screen, the window shaped like the video.
//  Behaviour modelled on IINA's `MainWindowController` (https://github.com/iina/iina,
//  GPLv3) — title bar views faded with the on-screen controls, `contentAspectRatio` from
//  the video size, native full screen — reimplemented here with public AppKit API; no
//  IINA code is copied.
//

#if os(macOS)
import AppKit
import AVKit
import Combine
import KinoPubLogging
import OSLog

/// `AVPlayerView` that says when it lands in a window. SwiftUI hands the representable its
/// view before the window exists; the window is what the chrome dresses.
final class MacPlayerHostView: AVPlayerView {
  var onWindowChange: ((NSWindow?) -> Void)?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    onWindowChange?(window)
  }
}

@MainActor
final class MacPlayerWindowChrome: NSObject, NSGestureRecognizerDelegate {

  /// Runs once the window is in full screen — the controls leave at once there.
  var onEnterFullScreen: (() -> Void)?

  private weak var window: NSWindow?
  private weak var playerView: AVPlayerView?
  private weak var manager: PlayerManager?
  private var controlsVisible = true
  private var controlsCancellable: AnyCancellable?
  private var windowTokens: [NSObjectProtocol] = []
  private var sizeObservation: NSKeyValueObservation?
  private var itemObservation: NSKeyValueObservation?
  /// The video size the window was last shaped to, so a same-size item does not move it.
  private var shapedFor: CGSize?
  private var hoverRecheck: Timer?
  private var doubleClick: NSClickGestureRecognizer?
  private var appearanceObservation: NSKeyValueObservation?
  private weak var titlebarBacking: NSVisualEffectView?

  // MARK: Attach

  func attach(to playerView: AVPlayerView, manager: PlayerManager,
              controlsVisible: Published<Bool>.Publisher) {
    self.playerView = playerView
    controlsCancellable = controlsVisible
      .removeDuplicates()
      .sink { [weak self] visible in
        MainActor.assumeIsolated { self?.controlsChanged(visible) }
      }
    if doubleClick == nil {
      let recognizer = NSClickGestureRecognizer(target: self, action: #selector(doubleClicked(_:)))
      recognizer.numberOfClicksRequired = 2
      // The clicks wait for the recognizer: AVKit takes a double-click on its content
      // view as «enter *its* full screen» (a detached window of its own), and with the
      // clicks passed through both full screens opened at once — the window's and AVKit's
      // — leaving AVKit's content view constrained to width 0 (Sasha's log, 2026-11-24).
      // A recognized double-click is the window's alone; single clicks arrive a double-click
      // interval late, as in IINA. Clicks on AVKit's controls are not held (see the
      // delegate below).
      recognizer.delaysPrimaryMouseButtonEvents = true
      recognizer.delegate = self
      playerView.addGestureRecognizer(recognizer)
      doubleClick = recognizer
    }
    follow(manager)
    adopt(playerView.window)
  }

  func detach() {
    controlsCancellable = nil
    appearanceObservation = nil
    sizeObservation = nil
    itemObservation = nil
    hoverRecheck?.invalidate()
    hoverRecheck = nil
    windowTokens.forEach(NotificationCenter.default.removeObserver)
    windowTokens = []
    if let doubleClick { playerView?.removeGestureRecognizer(doubleClick) }
    doubleClick = nil
    setTitlebar(visible: true, animated: false)
  }

  /// Watches the video size of whatever `manager` plays now (a next episode retargets the
  /// same player, so the item, not the player, is what changes).
  func follow(_ manager: PlayerManager) {
    guard self.manager !== manager else { return }
    self.manager = manager
    itemObservation = manager.player.observe(\.currentItem, options: [.initial, .new]) { [weak self] player, _ in
      MainActor.assumeIsolated { self?.observeSize(of: player.currentItem) }
    }
  }

  /// Dresses the window the player view landed in. AVKit's own Picture in Picture and
  /// full screen move the picture, not the view, so this is the player window throughout.
  func adopt(_ window: NSWindow?) {
    guard let window, window !== self.window else { return }
    self.window = window
    Logger.app.info("Player window: adopted, collectionBehavior=\(window.collectionBehavior.rawValue) appearance=\(window.appearance?.name.rawValue ?? "nil", privacy: .public)")
    dress(window)
    // SwiftUI finishes its own window setup after the view lands, and puts back the
    // scene's appearance and «+» zoom over ours (seen on Sasha's Mac, 2026-11-23).
    DispatchQueue.main.async { [weak self, weak window] in
      guard let self, let window else { return }
      self.dress(window)
      Logger.app.info("Player window: dressed, collectionBehavior=\(window.collectionBehavior.rawValue) appearance=\(window.appearance?.name.rawValue ?? "nil", privacy: .public)")
    }
    appearanceObservation = window.observe(\.appearance, options: [.new]) { [weak self] _, _ in
      MainActor.assumeIsolated { self?.redress() }
    }

    windowTokens.forEach(NotificationCenter.default.removeObserver)
    let center = NotificationCenter.default
    windowTokens = [
      // Cheap when nothing changed; catches SwiftUI re-applying the scene's settings.
      center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.redress() }
      },
      center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.redress() }
      },
      center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.setTitlebar(visible: true, animated: false) }
      },
      center.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated { self?.onEnterFullScreen?() }
      },
      center.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.setTitlebar(visible: self.controlsVisible, animated: false)
          self.shapeWindow(force: true)
        }
      },
    ]
    shapeWindow(force: true)
    setTitlebar(visible: controlsVisible, animated: false)
  }

  private static let dark = NSAppearance(named: .darkAqua)

  private func redress() {
    if let window { dress(window) }
  }

  /// The window's dress, re-applied whenever SwiftUI may have put its own back. Every
  /// line is a no-op when already so.
  private func dress(_ window: NSWindow) {
    // Always dark, as every video player is: the title over the picture followed the
    // system theme and went black on black in Light mode (Sasha, 2026-11-23).
    if window.appearance?.name != .darkAqua { window.appearance = Self.dark }
    if !window.titlebarAppearsTransparent { window.titlebarAppearsTransparent = true }
    if !window.styleMask.contains(.fullSizeContentView) { window.styleMask.insert(.fullSizeContentView) }
    // The green button is this window's full screen, not a «+» zoom.
    var behavior = window.collectionBehavior
    // SwiftUI opens this scene as `.auxiliary | .fullScreenAuxiliary` (logged on macOS 27.2,
    // 2026-11-23): a «+» zoom, and a window kept out of Window ›, the Dock's window list
    // and ⌘` — not the separate window Sasha asked for.
    behavior.remove([.fullScreenAuxiliary, .fullScreenNone, .auxiliary, .transient])
    behavior.insert([.fullScreenPrimary, .managed, .participatesInCycle])
    if behavior != window.collectionBehavior { window.collectionBehavior = behavior }
    if window.backgroundColor != .black { window.backgroundColor = .black }
    // A window of its own in Window › and the Dock's window list, as IINA's player is.
    if window.isExcludedFromWindowsMenu { window.isExcludedFromWindowsMenu = false }
    installTitlebarBacking(in: window)
  }

  /// IINA's title bar sits on a dark frosted strip (its `titleBarView`), so the title and
  /// the traffic lights read over any picture. A transparent title bar alone had nothing
  /// under them (Sasha, 2026-11-23). The strip lives in the title bar view, under the
  /// buttons, and fades with it.
  private func installTitlebarBacking(in window: NSWindow) {
    guard let titlebar = window.standardWindowButton(.closeButton)?.superview else { return }
    titlebar.superview?.appearance = Self.dark
    if let backing = titlebarBacking, backing.superview === titlebar { return }
    titlebarBacking?.removeFromSuperview()
    let backing = NSVisualEffectView(frame: titlebar.bounds)
    backing.material = .hudWindow
    backing.blendingMode = .withinWindow
    backing.state = .active
    backing.appearance = Self.dark
    backing.autoresizingMask = [.width, .height]
    titlebar.addSubview(backing, positioned: .below, relativeTo: nil)
    titlebarBacking = backing
  }

  // MARK: Title bar follows the controls

  /// The title bar comes and goes with AVKit's controls, as IINA's does with its OSC: up
  /// while the pointer moves over the picture, gone with the controls when it idles or
  /// leaves. It stays while the pointer is on the title bar itself, so the traffic lights
  /// and a drag by the title never vanish under it.
  private func controlsChanged(_ visible: Bool) {
    controlsVisible = visible
    hoverRecheck?.invalidate()
    hoverRecheck = nil
    setTitlebar(visible: visible || pointerOnTitlebar, animated: true)
    if !visible, pointerOnTitlebar { scheduleHoverRecheck() }
  }

  private func scheduleHoverRecheck() {
    // The timer is ended through `hoverRecheck`, never captured: `controlsChanged` also
    // ends it when the controls come back.
    let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self, !self.controlsVisible, !self.pointerOnTitlebar else { return }
        self.hoverRecheck?.invalidate()
        self.hoverRecheck = nil
        self.setTitlebar(visible: false, animated: true)
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    hoverRecheck = timer
  }

  /// `NSTitlebarContainerView`: the strip with the traffic lights, the title and the
  /// toolbar. Its alpha is what fades; the window keeps its frame and its drag area.
  private var titlebarContainer: NSView? {
    window?.standardWindowButton(.closeButton)?.superview?.superview
  }

  private var pointerOnTitlebar: Bool {
    guard let window, window.isVisible, let container = titlebarContainer else { return false }
    let frame = window.convertToScreen(container.convert(container.bounds, to: nil))
    return frame.contains(NSEvent.mouseLocation)
  }

  private func setTitlebar(visible: Bool, animated: Bool) {
    guard let window, let container = titlebarContainer else { return }
    // Full screen has the system's own title bar, revealed from the top edge.
    let alpha: CGFloat = (visible || window.styleMask.contains(.fullScreen)) ? 1 : 0
    guard container.alphaValue != alpha else { return }
    if animated {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = alpha > 0 ? 0.15 : 0.35
        container.animator().alphaValue = alpha
      }
    } else {
      container.alphaValue = alpha
    }
  }

  // MARK: Window shaped like the video

  private func observeSize(of item: AVPlayerItem?) {
    sizeObservation = item?.observe(\.presentationSize, options: [.initial, .new]) { [weak self] item, _ in
      MainActor.assumeIsolated { self?.shapeWindow(force: false) }
    }
  }

  /// IINA's window takes the video's shape and keeps it while resized
  /// (`contentAspectRatio`), so there are no black bars around the picture. The width stays
  /// where the viewer put it; the height follows, centred on where the window was.
  private func shapeWindow(force: Bool) {
    guard let window, !window.styleMask.contains(.fullScreen),
          let size = manager?.player.currentItem?.presentationSize,
          size.width > 0, size.height > 0 else { return }
    if !force, let shapedFor, shapedFor == size { return }
    shapedFor = size
    window.contentAspectRatio = size
    let content = window.contentRect(forFrameRect: window.frame)
    var height = (content.width * size.height / size.width).rounded()
    var width = content.width
    if let visible = window.screen?.visibleFrame, height > visible.height {
      height = visible.height
      width = (height * size.width / size.height).rounded()
    }
    guard abs(height - content.height) > 1 || abs(width - content.width) > 1 else { return }
    var target = NSRect(x: content.midX - width / 2, y: content.midY - height / 2,
                        width: width, height: height)
    target = window.frameRect(forContentRect: target)
    if let visible = window.screen?.visibleFrame {
      target.origin.y = min(max(target.origin.y, visible.minY), visible.maxY - target.height)
      target.origin.x = min(max(target.origin.x, visible.minX), visible.maxX - target.width)
    }
    window.setFrame(target, display: true, animate: window.isVisible)
  }

  // MARK: Double-click

  /// A double-click on the picture toggles full screen, as in IINA and QuickTime. Not on
  /// AVKit's controls: a fast double-click on a button there is two presses of it.
  @objc private func doubleClicked(_ recognizer: NSClickGestureRecognizer) {
    guard recognizer.state == .ended else { return }
    window?.toggleFullScreen(nil)
  }

  func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                         shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
    guard let playerView else { return false }
    let point = playerView.convert(event.locationInWindow, from: nil)
    guard let hit = playerView.hitTest(point) else { return true }
    var view: NSView? = hit
    while let current = view, current !== playerView {
      if current is NSControl { return false }
      let name = String(describing: type(of: current))
      if name.contains("Button") || name.contains("Slider") || name.contains("Scrubber")
          || name.contains("Controls") && !name.contains("ContentView") {
        return false
      }
      view = current.superview
    }
    return true
  }
}
#endif

#if os(macOS)
import SwiftUI

/// Puts the hosting window in Window › and the Dock's window list, with the system's check
/// mark on the active one. `.commandsRemoved()` on a `Window` scene takes the window out of
/// that list along with its menu item; the player and Settings windows are windows of
/// their own and belong in it (Sasha, 2026-11-23).
private struct WindowMenuListing: NSViewRepresentable {
  final class Probe: NSView {
    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      list()
      // SwiftUI finishes setting the scene's window up after the first attach.
      DispatchQueue.main.async { [weak self] in self?.list() }
    }

    func list() {
      guard let window else { return }
      if window.isExcludedFromWindowsMenu { window.isExcludedFromWindowsMenu = false }
      // `Window` scenes open `.auxiliary`, which keeps a window out of the list and ⌘`.
      var behavior = window.collectionBehavior
      behavior.remove([.auxiliary, .transient])
      behavior.insert([.managed, .participatesInCycle])
      if behavior != window.collectionBehavior { window.collectionBehavior = behavior }
      // The library window's title lives in its toolbar, so the window's own is empty —
      // and a window with no title has no line in the list. The app's name stands in.
      let title = window.title.isEmpty
        ? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Kinopub")
        : window.title
      NSApp.changeWindowsItem(window, title: title, filename: false)
    }
  }

  func makeNSView(context: Context) -> Probe {
    let view = Probe()
    view.isHidden = true
    return view
  }

  func updateNSView(_ nsView: Probe, context: Context) {
    nsView.list()
  }
}

extension View {
  /// See `WindowMenuListing`.
  func listedInWindowMenu() -> some View {
    background(WindowMenuListing())
  }
}
#endif
