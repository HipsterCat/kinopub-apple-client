#if os(tvOS)
//
//  TVSearchChrome.swift
//  KinoPubUI
//
//  Builds and pre-warms the system tvOS search stack (`UISearchController` in a
//  `UISearchContainerViewController`, hosted the way UIKit expects). Creating that
//  stack on first visit of a SwiftUI `Tab` is why the Search tab sat empty for
//  seconds: the keyboard, search field and suggestion row are all in that first
//  presentation. WWDC 2020 "Discover search suggestions for Apple TV" and Apple's
//  own guidance (forums thread 17819; Rivulet / Plozz keep the container as a real
//  tab VC from launch) is to stand the container up when the tab bar is created,
//  not lazily on first appearance.
//
//  The prepared stack lives in a hidden window of the current scene so the
//  search views are loaded before the tab is selected. A visible / off-screen
//  window leaked a second search UI into XCTest and the focus graph (results
//  over the keyboard, field overlapping the tab bar). After `takePrepared()`
//  later `prewarm()` calls must not build another stack. Catalog posters apply
//  afterwards.
//

import UIKit
import KinoPubLogging

@MainActor
public enum TVSearchChrome {
  /// One ready-to-embed search host, built at tab-bar / fixture creation.
  struct Stack {
    let results: TVPageCollectionViewController
    let search: UISearchController
    let container: UISearchContainerViewController
    let host: TVSearchPageHostViewController
  }

  /// Milliseconds from `prewarm()` start to the prepared host's first layout.
  /// `nil` until a prewarm has run in this process.
  public private(set) static var lastPrewarmMilliseconds: Double?
  /// Milliseconds from `takePrepared()` to the host's first on-screen layout.
  /// `nil` until Search has appeared once.
  public private(set) static var lastFirstFrameMilliseconds: Double?

  /// The grid keyboard (Settings › General › Keyboard) stays on the left while focus is
  /// in the results, and the tab bar and the search field stay put while they scroll.
  /// `false` is the system's own Search: the keyboard slides away and the page takes the
  /// screen's width, the bar and the field leave with the scroll. The app sets this from
  /// its feature flag before the first `prewarm()`; a change drops a waiting stack, and a
  /// stack already on screen keeps the behaviour it was built with.
  public static var keepsGridKeyboardVisible = true {
    didSet {
      guard keepsGridKeyboardVisible != oldValue, let prepared else { return }
      unpark(prepared)
      self.prepared = nil
    }
  }

  private static var prepared: Stack?
  private static var parkingWindow: UIWindow?
  private static var firstFrameOrigin: CFTimeInterval?
  /// The representable has taken the stack. Later `prewarm()` must not park a
  /// second search UI — XCTest queries every window.
  private static var taken = false

  /// Load the system search chrome now so opening the Search tab does not wait
  /// on view creation. Safe to call more than once; a stack already waiting is
  /// reused. After the tab has taken it, further calls are no-ops. `AppDelegate`
  /// may run before a scene exists — a later call (tab bar `onAppear`) attaches
  /// then. Parking is deferred a turn so Search as the selected tab can take the
  /// stack without moving the host between windows.
  public static func prewarm() {
    if taken { return }
    let started = CACurrentMediaTime()
    if prepared == nil {
      let stack = makeStack()
      prepared = stack
      stack.host.isParked = true
      stack.host.loadViewIfNeeded()
      stack.search.loadViewIfNeeded()
      stack.container.loadViewIfNeeded()
    }
    if parkingWindow == nil {
      DispatchQueue.main.async { parkIfStillWaiting() }
    }
    lastPrewarmMilliseconds = (CACurrentMediaTime() - started) * 1000
    NSLog("TVSEARCH prewarm %.0f ms", lastPrewarmMilliseconds ?? -1)
  }

  /// The pre-warmed host, or a fresh stack if none was waiting. The representable
  /// takes this once and SwiftUI parents it.
  static func takePrepared() -> Stack {
    taken = true
    firstFrameOrigin = CACurrentMediaTime()
    lastFirstFrameMilliseconds = nil
    PerfSignpost.beginSearchTab()
    if let prepared {
      self.prepared = nil
      unpark(prepared)
      prepared.host.isParked = false
      prepared.host.view.accessibilityElementsHidden = false
      return prepared
    }
    return makeStack()
  }

  static func makeStack() -> Stack {
    let results = TVPageCollectionViewController()
    results.claimsInitialFocus = false
    results.remembersFocus = false
    results.spansScreenWidth = true
    results.returnsToTopOnMenu = true
    results.clipsAboveContentBesideGridKeyboard = keepsGridKeyboardVisible
    let search = UISearchController(searchResultsController: results)
    search.obscuresBackgroundDuringPresentation = false
    if !keepsGridKeyboardVisible {
      search.hidesGridKeyboardWhenUnfocused()
    }
    let container = UISearchContainerViewController(searchController: search)
    let host = TVSearchPageHostViewController(searchController: search,
                                              searchContainer: container,
                                              results: results)
    host.onFirstAppearance = recordFirstFrame
    return Stack(results: results, search: search, container: container, host: host)
  }

  private static func recordFirstFrame() {
    guard lastFirstFrameMilliseconds == nil, let origin = firstFrameOrigin else { return }
    lastFirstFrameMilliseconds = (CACurrentMediaTime() - origin) * 1000
    PerfSignpost.endSearchTab("painted")
    NSLog("TVSEARCH first frame %.0f ms (prewarm %.0f ms)",
          lastFirstFrameMilliseconds ?? -1, lastPrewarmMilliseconds ?? -1)
  }

  private static func parkIfStillWaiting() {
    guard !taken, let stack = prepared, parkingWindow == nil else { return }
    park(stack)
  }

  /// Keep the stack in the scene so UIKit loads the search views, without
  /// showing a second window. A hidden window skips `viewDidAppear` — that is
  /// on purpose: presenting the keyboard here and moving it into the tab broke
  /// the grid layout. Bounds come from the scene, not `UIScreen`.
  private static func park(_ stack: Stack) {
    guard parkingWindow == nil else { return }
    guard let scene = activeWindowScene() else {
      stack.host.view.layoutIfNeeded()
      stack.search.searchBar.layoutIfNeeded()
      return
    }
    let window = UIWindow(windowScene: scene)
    window.frame = scene.coordinateSpace.bounds
    window.windowLevel = UIWindow.Level(rawValue: -1000)
    window.alpha = 0
    window.isUserInteractionEnabled = false
    window.accessibilityElementsHidden = true
    window.rootViewController = stack.host
    window.isHidden = true
    stack.host.view.accessibilityElementsHidden = true
    // Do not drive `viewDidAppear` here: presenting the keyboard unfocused in a
    // hidden window, then moving the host into the tab, left the grid keyboard
    // gone and the results full-width. Views are loaded; the real tab presents.
    stack.host.view.layoutIfNeeded()
    stack.search.searchBar.layoutIfNeeded()
    stack.container.view.layoutIfNeeded()
    parkingWindow = window
  }

  private static func unpark(_ stack: Stack) {
    if parkingWindow?.rootViewController === stack.host {
      parkingWindow?.rootViewController = nil
    }
    parkingWindow?.isHidden = true
    parkingWindow?.accessibilityElementsHidden = true
    parkingWindow = nil
    if stack.host.parent != nil {
      stack.host.willMove(toParent: nil)
      stack.host.view.removeFromSuperview()
      stack.host.removeFromParent()
    }
  }

  private static func activeWindowScene() -> UIWindowScene? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
  }
}
#endif
