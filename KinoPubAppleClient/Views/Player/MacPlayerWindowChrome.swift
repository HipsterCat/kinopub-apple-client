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
      recognizer.delaysPrimaryMouseButtonEvents = false
      recognizer.delegate = self
      playerView.addGestureRecognizer(recognizer)
      doubleClick = recognizer
    }
    follow(manager)
    adopt(playerView.window)
  }

  func detach() {
    controlsCancellable = nil
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
    // Always dark, as every video player is: the title over the picture followed the
    // system theme and went black on black in Light mode (Sasha, 2026-11-23).
    window.appearance = NSAppearance(named: .darkAqua)
    window.titlebarAppearsTransparent = true
    window.styleMask.insert(.fullSizeContentView)
    // The green button is full screen for this window — the scene made it a plain zoom («+»).
    window.collectionBehavior.remove([.fullScreenAuxiliary, .fullScreenNone])
    window.collectionBehavior.insert(.fullScreenPrimary)
    window.backgroundColor = .black
    // A window of its own in Window › and the Dock's window list, as IINA's player is.
    window.isExcludedFromWindowsMenu = false

    windowTokens.forEach(NotificationCenter.default.removeObserver)
    let center = NotificationCenter.default
    windowTokens = [
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
    let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
      MainActor.assumeIsolated {
        guard let self else { timer.invalidate(); return }
        guard !self.controlsVisible else { timer.invalidate(); return }
        if !self.pointerOnTitlebar {
          timer.invalidate()
          self.hoverRecheck = nil
          self.setTitlebar(visible: false, animated: true)
        }
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
