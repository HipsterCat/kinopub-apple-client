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
//  not lazily on first appearance. We keep a prepared stack in a hidden window of
//  the current scene so the first paint of Search is the field and keyboard;
//  catalog posters are applied afterwards.
//

import UIKit

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
  /// Milliseconds from `makeStack()` to the host's first `viewDidAppear` in the
  /// real tab. `nil` until Search has appeared once.
  public private(set) static var lastFirstFrameMilliseconds: Double?

  private static var prepared: Stack?
  private static var parkingWindow: UIWindow?
  private static var firstFrameOrigin: CFTimeInterval?

  /// Stand the system search chrome up now so opening the Search tab does not
  /// wait on keyboard presentation. Safe to call more than once; a stack already
  /// waiting is reused, a stack already taken is rebuilt.
  public static func prewarm() {
    if prepared != nil { return }
    let started = CACurrentMediaTime()
    let stack = makeStack()
    park(stack)
    lastPrewarmMilliseconds = (CACurrentMediaTime() - started) * 1000
    NSLog("TVSEARCH prewarm %.0f ms", lastPrewarmMilliseconds ?? -1)
  }

  /// The pre-warmed host, or a fresh stack if none was waiting. The representable
  /// takes this once and SwiftUI parents it.
  static func takePrepared() -> Stack {
    if let prepared {
      self.prepared = nil
      unpark(prepared)
      firstFrameOrigin = CACurrentMediaTime()
      return prepared
    }
    firstFrameOrigin = CACurrentMediaTime()
    return makeStack()
  }

  static func makeStack() -> Stack {
    let results = TVPageCollectionViewController()
    results.claimsInitialFocus = false
    results.remembersFocus = false
    results.spansScreenWidth = true
    results.returnsToTopOnMenu = true
    let search = UISearchController(searchResultsController: results)
    search.obscuresBackgroundDuringPresentation = false
    search.hidesGridKeyboardWhenUnfocused()
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
    NSLog("TVSEARCH first frame %.0f ms (prewarm %.0f ms)",
          lastFirstFrameMilliseconds ?? -1, lastPrewarmMilliseconds ?? -1)
  }

  /// Keep the stack in the scene so UIKit actually builds the keyboard, without
  /// showing a second window. Bounds come from the scene, not `UIScreen`.
  private static func park(_ stack: Stack) {
    prepared = stack
    stack.host.loadViewIfNeeded()
    stack.search.loadViewIfNeeded()
    stack.container.loadViewIfNeeded()
    guard let scene = activeWindowScene() else {
      stack.host.view.layoutIfNeeded()
      return
    }
    let window = UIWindow(windowScene: scene)
    window.frame = scene.coordinateSpace.bounds
    window.windowLevel = UIWindow.Level(rawValue: -1000)
    window.alpha = 0
    window.isUserInteractionEnabled = false
    window.isHidden = true
    window.rootViewController = stack.host
    stack.host.view.layoutIfNeeded()
    stack.search.searchBar.layoutIfNeeded()
    parkingWindow = window
  }

  private static func unpark(_ stack: Stack) {
    if parkingWindow?.rootViewController === stack.host {
      parkingWindow?.rootViewController = nil
    }
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
