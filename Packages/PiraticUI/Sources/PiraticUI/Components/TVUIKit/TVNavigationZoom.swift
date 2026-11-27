#if os(tvOS)
//
//  TVNavigationZoom.swift
//  PiraticUI
//
//  Adapter (docs/engineering/adapters.md): tvOS's own page transition for every push
//  and pop on the app's navigation stacks.
//
//  Apple limitation: on tvOS `UINavigationController` push/pop is a plain crossfade, and
//  `UIViewController.Transition.zoom` / SwiftUI `.navigationTransition(.zoom)` "have no
//  effect" (Apple's docs; probed 2026-11-05: push and present both crossfade). The
//  scale in/out TVML apps and the old kino.pub client have — the page you leave grows
//  toward you and fades, the next one fades in; back is the reverse — was TVMLKit's
//  private `_TVNavigationZoomAnimator`. Driving that animator under SwiftUI's
//  `UIHostingController` made it add `_UIReplicantView` into the hosting view (runtime
//  fault, 2026-11-20). So the look is the same scale/fade, drawn by us with a plain
//  `UIImageView` on the navigation controller's view — a common superview above every
//  hosting controller — never through the private animator.
//
//  How: SwiftUI's `NavigationStack` is a `UINavigationController` whose delegate is
//  SwiftUI's own. The delegate is wrapped, not replaced: every call goes on to SwiftUI's
//  object, and only "which animator for this push / pop" is answered here (a no-op swap
//  that hands back a bitmap of the page left). `-PIRATICSystemNavigationTransition YES`
//  keeps the system's crossfade.
//

import SwiftUI
import UIKit
import ObjectiveC

public extension View {
  /// tvOS's scale in/out transition for the navigation stack this view is in. On the
  /// stack's root content (`appRouteDestinations`), and on every pushed page so a page
  /// that appears without a push still hides the tab bar. Installing twice is a no-op.
  func tvNavigationZoom() -> some View {
    background(TVNavigationZoomInstaller().frame(width: 0, height: 0))
  }
}

/// Whether the custom scale transition is on.
public enum TVNavigationZoom {
  /// `-PIRATICSystemNavigationTransition YES` keeps the system's crossfade, to compare.
  public static var isAvailable: Bool {
    !UserDefaults.standard.bool(forKey: "PIRATICSystemNavigationTransition")
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
      // A page above the root that was never pushed — routes set at launch, a Top Shelf
      // link — has no `willShow` to hide the bar; it is hidden when that page appears.
      if navigation.viewControllers.count > 1 { TabBarSlide.keepHidden(in: navigation) }
    }
  }
}

/// Stands in front of SwiftUI's navigation delegate. Answers the animator question,
/// forwards everything else.
private final class ZoomingNavigationDelegate: NSObject, UINavigationControllerDelegate {
  /// Address token for `objc_setAssociatedObject`. Nothing reads or writes the
  /// byte; the pointer is the identity. `nonisolated(unsafe)` is the stable
  /// address, not a shared value.
  nonisolated(unsafe) private static var key: UInt8 = 0

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
  /// page's own content. So the push asks no animator; the zoom is driven here
  /// instead, from a snapshot of the page being left, once the new page is in place.
  private var shownCount = 0
  private var pendingSnapshot: UIImageView?
  /// Direction of the transition that will finish in `didShow`. Depth alone is wrong:
  /// title → related → Menu leaves depth 2, so `shownCount > 1` would play a push zoom
  /// on a pop (review on #123).
  private var pendingGrowing: Bool?

  func navigationController(_ navigationController: UINavigationController,
                            willShow viewController: UIViewController, animated: Bool) {
    let count = navigationController.viewControllers.count
    if count > shownCount {
      pendingGrowing = true
      TabBarSlide.willPush(in: navigationController)
    } else if count < shownCount {
      pendingGrowing = false
      TabBarSlide.willPop(in: navigationController, toRoot: count == 1)
    } else {
      pendingGrowing = nil
    }
    if !animated, shownCount > 0, count > shownCount,
       let leaving = navigationController.viewControllers.dropLast().last?.view,
       leaving.window != nil,
       let snapshot = Snapshot.imageView(of: leaving) {
      // Frame in the navigation controller — the common superview above hosting views.
      snapshot.frame = leaving.convert(leaving.bounds, to: navigationController.view)
      pendingSnapshot = snapshot
    }
    (wrapped as? UINavigationControllerDelegate)?
      .navigationController?(navigationController, willShow: viewController, animated: animated)
  }

  func navigationController(_ navigationController: UINavigationController,
                            didShow viewController: UIViewController, animated: Bool) {
    let growing = pendingGrowing
    pendingGrowing = nil
    shownCount = navigationController.viewControllers.count
    (wrapped as? UINavigationControllerDelegate)?
      .navigationController?(navigationController, didShow: viewController, animated: animated)
    if shownCount > 1 { TabBarSlide.keepHidden(in: navigationController) }
    guard let snapshot = pendingSnapshot else { return }
    pendingSnapshot = nil
    // Prefer the direction recorded in `willShow`; fall back to depth only if missing.
    Zoom.play(snapshot: snapshot, over: navigationController.view,
              growing: growing ?? (shownCount > 1))
  }

  /// SwiftUI answers the push through UIKit's private `animatorForOperation:` question,
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

/// Swaps the pages without animating and hands back a bitmap of the page left, which
/// `didShow` then zooms away over the page shown.
private final class SwapAnimator: NSObject, UIViewControllerAnimatedTransitioning {
  private let snapshotTaken: (UIImageView) -> Void
  init(snapshotTaken: @escaping (UIImageView) -> Void) { self.snapshotTaken = snapshotTaken }

  func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval { 0 }

  func animateTransition(using context: UIViewControllerContextTransitioning) {
    if let from = context.view(forKey: .from),
       let snapshot = Snapshot.imageView(of: from) {
      // Same space as the push path: navigation controller's view (container's superview).
      // `from.frame` is in the transition container; both snapshots are added to the nav view.
      if let navView = context.containerView.superview {
        snapshot.frame = from.convert(from.bounds, to: navView)
      } else {
        snapshot.frame = from.frame
      }
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

/// The scale/fade that `_TVNavigationZoomAnimator` drew — without inviting its
/// `_UIReplicantView` into a hosting controller.
@MainActor
private enum Zoom {
  static let duration: TimeInterval = 0.45

  /// `growing` is a push (old page scales up and out); a pop scales down into place.
  static func play(snapshot: UIImageView, over container: UIView?, growing: Bool) {
    guard let container else {
      snapshot.removeFromSuperview()
      return
    }
    if UIAccessibility.isReduceMotionEnabled {
      snapshot.removeFromSuperview()
      return
    }
    snapshot.isUserInteractionEnabled = false
    if snapshot.superview !== container {
      container.addSubview(snapshot)
    }
    let end: CGAffineTransform = growing
      ? CGAffineTransform(scaleX: 1.12, y: 1.12)
      : CGAffineTransform(scaleX: 0.92, y: 0.92)
    UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
      snapshot.transform = end
      snapshot.alpha = 0
    } completion: { _ in
      snapshot.removeFromSuperview()
    }
  }
}

/// The tab bar leaves a pushed page by sliding up out of the screen, and comes back down
/// into place on the way back, instead of blinking out and in.
///
/// **This owns the bar's visibility for the stack's pushes and pops**, not SwiftUI.
/// `.toolbar(.hidden, for: .tabBar)` on pushed pages (`RouteDestination`) hides the bar
/// once, on the first push; with our animator answering the pops SwiftUI never shows it
/// again, and it caches "hidden". Showing the bar here on the way back (the slide) left
/// that cache stale, so the next push changed nothing in SwiftUI's eyes and the bar
/// stayed over the title page and the player (Sasha, 2026-11-16: second entry from the
/// Home hero; measured on 27.2 — `TVMenuBackUITests.testTabBarStaysHiddenOnTitleAndPlayerOpenedTwiceFromTheHero`).
/// Rule, the same as the product's (2026-09-21): the stack's root has the bar, every
/// pushed page has none. The modifier stays for stacks this proxy is not installed on.
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

  /// A push hides the bar at once; a snapshot of it rises out of the screen.
  static func willPush(in navigation: UINavigationController) {
    guard let (tabs, bar) = bar(of: navigation) else { return }
    if isShowing(tabs, bar), !UIAccessibility.isReduceMotionEnabled,
       let window = bar.window,
       let snapshot = Snapshot.imageView(of: bar) {
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
    keepHidden(in: navigation)
  }

  /// A pushed page (the title, the player over it, …) has no bar, whatever SwiftUI did.
  static func keepHidden(in navigation: UINavigationController) {
    guard let (tabs, _) = bar(of: navigation), !tabs.isTabBarHidden else { return }
    tabs.setTabBarHidden(true, animated: false)
  }

  /// Back to the stack's root — the one page that has the bar — it is shown as the pop
  /// starts and slides in alongside it. A pop that stays above the root (player → title)
  /// keeps it hidden.
  static func willPop(in navigation: UINavigationController, toRoot: Bool) {
    guard toRoot else { keepHidden(in: navigation); return }
    guard let (tabs, bar) = bar(of: navigation), tabs.isTabBarHidden else { return }
    tabs.setTabBarHidden(false, animated: false)
    guard !UIAccessibility.isReduceMotionEnabled else { return }
    let rise = bar.frame.maxY + 24
    let slide = CABasicAnimation(keyPath: "transform")
    slide.fromValue = CATransform3DConcat(CATransform3DMakeScale(0.94, 0.94, 1),
                                          CATransform3DMakeTranslation(0, -rise, 0))
    slide.toValue = CATransform3DIdentity
    slide.duration = duration
    slide.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    bar.layer.add(slide, forKey: "piratic.tabBarSlide")
  }
}

/// A plain `UIImageView` of a view — not `snapshotView(afterScreenUpdates:)`.
///
/// **Apple API limitation / adapter:** `snapshotView` returns `_UIReplicantView`. Adding
/// that as a subview of a `UIHostingController`'s view (SwiftUI's `NavigationStack`
/// container) logs *"Adding '_UIReplicantView' as a subview of UIHostingController.view
/// is not supported"*. An image draw is a normal view; it lives on the navigation
/// controller's view, above every hosting controller.
private enum Snapshot {
  static func imageView(of view: UIView) -> UIImageView? {
    let bounds = view.bounds
    guard bounds.width > 1, bounds.height > 1 else { return nil }
    let format = UIGraphicsImageRendererFormat()
    format.scale = view.traitCollection.displayScale
    format.opaque = false
    // `afterScreenUpdates: false` keeps materials (blur/glass) and avoids the
    // "drawing with afterScreenUpdates:YES inside CoreAnimation commit" warning.
    // Taken from `willShow` / the zero-duration swap animator, not mid-commit.
    let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
      _ = view.drawHierarchy(in: bounds, afterScreenUpdates: false)
    }
    let imageView = UIImageView(image: image)
    imageView.bounds = bounds
    imageView.isUserInteractionEnabled = false
    return imageView
  }
}
#endif
