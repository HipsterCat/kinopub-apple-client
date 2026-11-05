#if os(tvOS)
//
//  TVNavigationZoom.swift
//  KinoPubUI
//
//  Adapter (docs/engineering/adapters.md): tvOS's own page transition for every push
//  and pop on the app's navigation stacks.
//
//  Apple limitation: on tvOS `UINavigationController` push/pop is a plain crossfade, and
//  `UIViewController.Transition.zoom` / SwiftUI `.navigationTransition(.zoom)` "have no
//  effect" (Apple's docs; probed 2026-11-05: push and present both crossfade). The
//  scale in/out TVML apps and the old kino.pub client have — the page you leave grows
//  toward you and fades, the next one fades in; back is the reverse — is TVMLKit's
//  private `_TVNavigationZoomAnimator`, a plain `UIViewControllerAnimatedTransitioning`
//  (found by listing TVMLKit's classes on the 27.2 runtime; recorded frame by frame).
//
//  How: SwiftUI's `NavigationStack` is a `UINavigationController` whose delegate is
//  SwiftUI's own. The delegate is wrapped, not replaced: every call goes on to SwiftUI's
//  object, and only "which animator for this push / pop" is answered here. If the class
//  is missing on some tvOS, the answer is SwiftUI's — the system crossfade.
//

import SwiftUI
import UIKit
import ObjectiveC

public extension View {
  /// tvOS's scale in/out transition for the navigation stack this view is in. Once per
  /// stack, on its root content (`appRouteDestinations`).
  func tvNavigationZoom() -> some View {
    background(TVNavigationZoomInstaller().frame(width: 0, height: 0))
  }
}

/// Whether TVMLKit's animator is there to use.
public enum TVNavigationZoom {
  static let animatorClass: NSObject.Type? = {
    _ = dlopen("/System/Library/Frameworks/TVMLKit.framework/TVMLKit", RTLD_NOW)
    guard let cls = NSClassFromString("_TVNavigationZoomAnimator") as? NSObject.Type,
          cls.instancesRespond(to: NSSelectorFromString("animateTransition:"))
    else { return nil }
    return cls
  }()

  /// `-KINOPUBSystemNavigationTransition YES` keeps the system's crossfade, to compare.
  public static var isAvailable: Bool {
    animatorClass != nil && !UserDefaults.standard.bool(forKey: "KINOPUBSystemNavigationTransition")
  }

  static func makeAnimator() -> UIViewControllerAnimatedTransitioning? {
    animatorClass?.init() as? UIViewControllerAnimatedTransitioning
  }
}

private struct TVNavigationZoomInstaller: UIViewControllerRepresentable {
  func makeUIViewController(context: Context) -> Probe { Probe() }
  func updateUIViewController(_ controller: Probe, context: Context) { controller.install() }

  final class Probe: UIViewController {
    override func loadView() {
      view = UIView()
      view.isUserInteractionEnabled = false
    }

    override func didMove(toParent parent: UIViewController?) {
      super.didMove(toParent: parent)
      install()
    }

    override func viewWillAppear(_ animated: Bool) {
      super.viewWillAppear(animated)
      install()
    }

    override func viewDidAppear(_ animated: Bool) {
      super.viewDidAppear(animated)
      install()
    }

    func install() {
      guard TVNavigationZoom.isAvailable, let navigation = navigationController else { return }
      ZoomingNavigationDelegate.wrap(navigation)
    }
  }
}

/// Stands in front of SwiftUI's navigation delegate. Answers the animator question,
/// forwards everything else.
private final class ZoomingNavigationDelegate: NSObject, UINavigationControllerDelegate {
  private static var key: UInt8 = 0

  /// SwiftUI's own delegate. Weak, as `UINavigationController.delegate` is; SwiftUI keeps it.
  weak var wrapped: NSObject?

  static func wrap(_ navigation: UINavigationController) {
    if navigation.delegate is ZoomingNavigationDelegate { return }
    let proxy = ZoomingNavigationDelegate()
    proxy.shownCount = navigation.viewControllers.count
    proxy.wrapped = navigation.delegate as? NSObject
    // `delegate` is weak: the navigation controller keeps its proxy alive.
    objc_setAssociatedObject(navigation, &key, proxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    navigation.delegate = proxy
  }

  func navigationController(_ navigationController: UINavigationController,
                            animationControllerFor operation: UINavigationController.Operation,
                            from fromVC: UIViewController,
                            to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
    // An animated move (SwiftUI animates its pops) swaps the pages at once and is then
    // drawn exactly as a push is, from a snapshot of the page left — one path both ways.
    if operation == .push || operation == .pop, TVNavigationZoom.isAvailable {
      return SwapAnimator { [weak self] snapshot in self?.pendingSnapshot = snapshot }
    }
    return (wrapped as? UINavigationControllerDelegate)?
      .navigationController?(navigationController, animationControllerFor: operation, from: fromVC, to: toVC)
  }

  // MARK: Push

  /// SwiftUI's tvOS stack pushes **without** animation (`willShow … animated: false`, no
  /// transition coordinator) — the page just appeared and the fade people saw was the
  /// page's own content. So the push asks no animator; the same animator is driven here
  /// instead, from a snapshot of the page being left, once the new page is in place.
  private var shownCount = 0
  private var pendingSnapshot: UIView?

  func navigationController(_ navigationController: UINavigationController,
                            willShow viewController: UIViewController, animated: Bool) {
    let count = navigationController.viewControllers.count
    if count > shownCount {
      TabBarSlide.willShow(in: navigationController, pushing: true)
    } else if count < shownCount {
      TabBarSlide.willPop(in: navigationController, toRoot: count == 1)
    }
    if !animated, shownCount > 0, count > shownCount,
       let leaving = navigationController.viewControllers.dropLast().last?.view,
       leaving.window != nil,
       let snapshot = leaving.snapshotView(afterScreenUpdates: false) {
      snapshot.frame = leaving.frame
      pendingSnapshot = snapshot
    }
    (wrapped as? UINavigationControllerDelegate)?
      .navigationController?(navigationController, willShow: viewController, animated: animated)
  }

  func navigationController(_ navigationController: UINavigationController,
                            didShow viewController: UIViewController, animated: Bool) {
    shownCount = navigationController.viewControllers.count
    (wrapped as? UINavigationControllerDelegate)?
      .navigationController?(navigationController, didShow: viewController, animated: animated)
    guard let snapshot = pendingSnapshot else { return }
    pendingSnapshot = nil
    guard let container = viewController.view.superview,
          let animator = TVNavigationZoom.makeAnimator() else { return }
    let leaving = UIViewController()
    leaving.view = snapshot
    container.addSubview(snapshot)
    let context = ZoomPushContext(container: container, from: leaving, to: viewController) {
      snapshot.removeFromSuperview()
    }
    animator.animateTransition(using: context)
  }

  /// SwiftUI answers the push  /// SwiftUI answers the push through UIKit's private `animatorForOperation:` question,
  /// which UIKit asks before the public one; hidden, so the public one above is asked.
  private static let hidden: Set<Selector> = [
    NSSelectorFromString("navigationController:animatorForOperation:fromViewController:toViewController:")
  ]

  override func responds(to selector: Selector!) -> Bool {
    if Self.hidden.contains(selector) { return false }
    return super.responds(to: selector) || (wrapped?.responds(to: selector) ?? false)
  }

  override func forwardingTarget(for selector: Selector!) -> Any? {
    if let wrapped, wrapped.responds(to: selector) { return wrapped }
    return super.forwardingTarget(for: selector)
  }
}

/// Swaps the pages without animating and hands back a snapshot of the page left, which
/// `didShow` then zooms away over the page shown.
private final class SwapAnimator: NSObject, UIViewControllerAnimatedTransitioning {
  private let snapshotTaken: (UIView) -> Void
  init(snapshotTaken: @escaping (UIView) -> Void) { self.snapshotTaken = snapshotTaken }

  func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval { 0 }

  func animateTransition(using context: UIViewControllerContextTransitioning) {
    if let from = context.view(forKey: .from),
       let snapshot = from.snapshotView(afterScreenUpdates: false) {
      snapshot.frame = from.frame
      snapshotTaken(snapshot)
    }
    if let to = context.view(forKey: .to), let toVC = context.viewController(forKey: .to) {
      to.frame = context.finalFrame(for: toVC)
      context.containerView.addSubview(to)
    }
    context.view(forKey: .from)?.removeFromSuperview()
    context.completeTransition(!context.transitionWasCancelled)
  }
}

/// The tab bar leaves a pushed page by sliding up out of the screen, and comes back down
/// into place on the way back, instead of blinking out and in. SwiftUI still decides
/// when the bar is hidden (`.toolbar(.hidden, for: .tabBar)` on pushed pages); this only
/// draws the move: a snapshot rising on the way out, an additive slide on the way in.
@MainActor
private enum TabBarSlide {
  static let duration: CFTimeInterval = 0.45

  private static func bar(of navigation: UINavigationController) -> (UITabBarController, UITabBar)? {
    guard let tabs = navigation.tabBarController else { return nil }
    return (tabs, tabs.tabBar)
  }

  private static func isShowing(_ tabs: UITabBarController, _ bar: UITabBar) -> Bool {
    !tabs.isTabBarHidden && !bar.isHidden && bar.alpha > 0.01 && bar.window != nil
  }

  static func willShow(in navigation: UINavigationController, pushing: Bool) {
    guard let (tabs, bar) = bar(of: navigation) else { return }
    guard pushing, isShowing(tabs, bar), !UIAccessibility.isReduceMotionEnabled,
          let window = bar.window,
          let snapshot = bar.snapshotView(afterScreenUpdates: false) else { return }
    snapshot.frame = bar.convert(bar.bounds, to: window)
    snapshot.isUserInteractionEnabled = false
    window.addSubview(snapshot)
    let rise = snapshot.frame.maxY + 24
    UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
      snapshot.transform = CGAffineTransform(translationX: 0, y: -rise).scaledBy(x: 0.94, y: 0.94)
    } completion: { _ in
      snapshot.removeFromSuperview()
    }
  }

  /// SwiftUI shows the bar again only once a pop has finished. Going back to the stack's
  /// root — the one page that has the bar — it is shown as the pop starts and slides in
  /// alongside it.
  static func willPop(in navigation: UINavigationController, toRoot: Bool) {
    guard toRoot, let (tabs, bar) = bar(of: navigation) else { return }
    guard tabs.isTabBarHidden else { return }
    tabs.setTabBarHidden(false, animated: false)
    guard !UIAccessibility.isReduceMotionEnabled else { return }
    let rise = bar.frame.maxY + 24
    let slide = CABasicAnimation(keyPath: "transform")
    slide.fromValue = CATransform3DConcat(CATransform3DMakeScale(0.94, 0.94, 1),
                                          CATransform3DMakeTranslation(0, -rise, 0))
    slide.toValue = CATransform3DIdentity
    slide.duration = duration
    slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    bar.layer.add(slide, forKey: "kinopub.tabBarSlide")
  }
}

/// The transition context UIKit would have built for an animated push: the container
/// both pages are in, the page left (its snapshot) and the page shown.
private final class ZoomPushContext: NSObject, UIViewControllerContextTransitioning {
  let containerView: UIView
  private let from: UIViewController
  private let to: UIViewController
  private let finished: () -> Void

  init(container: UIView, from: UIViewController, to: UIViewController, finished: @escaping () -> Void) {
    containerView = container
    self.from = from
    self.to = to
    self.finished = finished
  }

  var isAnimated: Bool { true }
  var isInteractive: Bool { false }
  var transitionWasCancelled: Bool { false }
  var presentationStyle: UIModalPresentationStyle { .none }
  var targetTransform: CGAffineTransform { .identity }

  func updateInteractiveTransition(_ percentComplete: CGFloat) {}
  func finishInteractiveTransition() {}
  func cancelInteractiveTransition() {}
  func pauseInteractiveTransition() {}
  func completeTransition(_ didComplete: Bool) { finished() }

  func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? {
    switch key {
    case .from: from
    case .to: to
    default: nil
    }
  }

  func view(forKey key: UITransitionContextViewKey) -> UIView? {
    switch key {
    case .from: from.view
    case .to: to.view
    default: nil
    }
  }

  func initialFrame(for vc: UIViewController) -> CGRect { vc === from ? from.view.frame : .zero }
  func finalFrame(for vc: UIViewController) -> CGRect { vc === to ? to.view.frame : .zero }
}
#endif
