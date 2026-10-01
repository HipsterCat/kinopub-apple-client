#if os(tvOS)
//
//  TVZoomPresentation.swift
//  KinoPubUI
//
//  A page that grows out of the card it was opened from and shrinks back into it on
//  Menu: a UIKit modal presentation with its own animator.
//
//  Why a presentation and not a push: a push's transition belongs to the navigation
//  controller, and the only zoom SwiftUI offers it cross-faded on device (see
//  `TVZoomSource`). A presented controller takes any `UIViewControllerAnimatedTransitioning`,
//  so the zoom is ours end to end and does not hang on what tvOS does with an API Apple
//  documents mostly for iOS. `-KINOPUBSystemZoom` (DEBUG) swaps in the system's
//  `preferredTransition = .zoom` instead, to compare the two on a device.
//
//  - `.overFullScreen`: the tabs stay mounted under the page. `.fullScreen` takes the
//    presenting view out of the window, which ends every SwiftUI view under it
//    (`onDisappear`, cancelled `.task`s), and Home would reload on the way back.
//  - The page is laid out at full size from the first frame and scaled: one transform
//    and one mask animate, and nothing is laid out again per frame.
//  - Menu at the root of the page's own stack dismisses it; deeper, the stack pops.
//    Focus returns to the card by itself (`restoresFocusAfterTransition`).
//

import UIKit

/// Hosts one page over the tabs.
@MainActor
public final class TVZoomPresentedController: UIViewController {

  public let content: UIViewController
  /// After the page has gone, however it went.
  public var onDismiss: (() -> Void)?
  /// Menu reached the page itself rather than its stack: pop the page's own stack if it
  /// has anything pushed and answer true; false at its root, and the page closes.
  public var popOnMenu: (() -> Bool)?

  private let transition: TVZoomTransition

  public init(content: UIViewController, source: TVZoomSource?) {
    self.content = content
    self.transition = TVZoomTransition(source: source)
    super.init(nibName: nil, bundle: nil)
    modalPresentationStyle = .overFullScreen
#if DEBUG
    if ProcessInfo.processInfo.arguments.contains("-KINOPUBSystemZoom") {
      preferredTransition = .zoom(options: nil) { [weak source] _ in source?.sourceView }
      return
    }
#endif
    transitioningDelegate = transition
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  public override func viewDidLoad() {
    super.viewDidLoad()
    // Opaque: the tabs are still drawn under this page. tvOS has no semantic background
    // colour (`systemBackground` is iOS-only), hence black and white by hand.
    view.backgroundColor = UIColor { $0.userInterfaceStyle == .light ? .white : .black }
    addChild(content)
    content.view.frame = view.bounds
    content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    content.view.backgroundColor = .clear
    view.addSubview(content.view)
    content.didMove(toParent: self)
  }

  public override var preferredFocusEnvironments: [UIFocusEnvironment] { [content] }

  public override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    guard isBeingDismissed else { return }
    onDismiss?()
    onDismiss = nil
  }

  /// Presents over whatever is on screen in `window`, once any transition already
  /// running there (a context menu closing on "Go to title") has finished.
  /// `unable` runs instead when nothing could be presented.
  public func present(in window: UIWindow?, unable: @escaping () -> Void) {
    guard let window else {
      unable()
      return
    }
    present(in: window, attempts: 3, unable: unable)
  }

  private func present(in window: UIWindow, attempts: Int, unable: @escaping () -> Void) {
    guard var top = window.rootViewController else {
      unable()
      return
    }
    while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
    if let coordinator = top.transitionCoordinator ?? top.presentedViewController?.transitionCoordinator {
      guard attempts > 0 else {
        unable()
        return
      }
      // Strong: nothing else holds this controller until it is presented.
      coordinator.animate(alongsideTransition: nil) { [weak window] _ in
        guard let window else { return unable() }
        self.present(in: window, attempts: attempts - 1, unable: unable)
      }
      return
    }
    top.present(self, animated: true)
    // UIKit refuses a second presentation with a log line and nothing else.
    if presentingViewController == nil { unable() }
  }

  /// Closes the page. `zoomingBack: false` when what is under it is about to change —
  /// a genre opens Search — so it does not shrink into a card that is going away.
  public func dismissPage(zoomingBack: Bool = true) {
    guard presentingViewController != nil, !isBeingDismissed else { return }
    if !zoomingBack { transition.dropSource() }
    dismiss(animated: true)
  }

  // MARK: - Menu

  public override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    // Handled on the way up, in `pressesEnded`; passing the press on would let the
    // presenting side see a Menu as well.
    guard presses.contains(where: { $0.type == .menu }) else {
      return super.pressesBegan(presses, with: event)
    }
  }

  public override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    guard presses.contains(where: { $0.type == .menu }) else {
      return super.pressesEnded(presses, with: event)
    }
    guard !isBeingPresented, !isBeingDismissed, presentedViewController == nil else { return }
    if popOnMenu?() == true { return }
    dismiss(animated: true)
  }

  public override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    guard presses.contains(where: { $0.type == .menu }) else {
      return super.pressesCancelled(presses, with: event)
    }
  }
}

// MARK: - Transition

@MainActor
final class TVZoomTransition: NSObject, UIViewControllerTransitioningDelegate {
  private var source: TVZoomSource?

  init(source: TVZoomSource?) {
    self.source = source
  }

  func dropSource() {
    source = nil
  }

  func animationController(forPresented presented: UIViewController,
                           presenting: UIViewController,
                           source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
    TVZoomAnimator(presenting: true, source: self.source)
  }

  func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
    TVZoomAnimator(presenting: false, source: source)
  }
}

/// Grows the page out of the card, or shrinks it back in.
///
/// The page view is full size throughout. A transform scales it down onto the card,
/// and a mask cuts it to the card's shape: the part of the page that maps onto the card,
/// centred, at the card's corner radius. Both run to identity together. A snapshot of
/// the card sits on top at the card's own size and fades out early, so what grows is the
/// card turning into the page; on the way back the snapshot fades in late, and the page
/// is exactly the card when it is removed.
@MainActor
final class TVZoomAnimator: NSObject, UIViewControllerAnimatedTransitioning {
  private let presenting: Bool
  private let source: TVZoomSource?

  private static let duration: TimeInterval = 0.5
  /// How far the tabs dim under the page while it grows.
  private static let dimming: CGFloat = 0.5

  init(presenting: Bool, source: TVZoomSource?) {
    self.presenting = presenting
    self.source = source
  }

  func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
    Self.duration
  }

  func animateTransition(using context: UIViewControllerContextTransitioning) {
    let container = context.containerView
    guard let page = context.viewController(forKey: presenting ? .to : .from), let pageView = page.view else {
      context.completeTransition(false)
      return
    }
    if presenting {
      pageView.frame = context.finalFrame(for: page)
      container.addSubview(pageView)
      pageView.layoutIfNeeded()
    }

    let dim = UIView(frame: container.bounds)
    dim.backgroundColor = UIColor.black.withAlphaComponent(Self.dimming)
    dim.alpha = presenting ? 0 : 1
    dim.isUserInteractionEnabled = false
    container.insertSubview(dim, belowSubview: pageView)

    guard let geometry = Geometry(source: source, page: pageView, container: container) else {
      scaleAndFade(pageView, dim: dim, context: context)
      return
    }

    let mask = UIView(frame: presenting ? geometry.window : pageView.bounds)
    mask.backgroundColor = .black
    mask.layer.cornerCurve = .continuous
    mask.layer.cornerRadius = presenting ? geometry.cornerRadius : 0
    pageView.mask = mask
    pageView.transform = presenting ? geometry.transform : .identity

    let snapshot = source?.snapshot()
    if let snapshot {
      // The card's own size, scaled from there: a snapshot view draws at the size it
      // was taken and does not stretch with its bounds. The page's transform brings it
      // back to exactly the card on screen.
      snapshot.bounds = CGRect(origin: .zero, size: geometry.unscaledCard)
      snapshot.center = CGPoint(x: geometry.window.midX, y: geometry.window.midY)
      snapshot.transform = CGAffineTransform(
        scaleX: geometry.card.width / geometry.unscaledCard.width / geometry.scale,
        y: geometry.card.height / geometry.unscaledCard.height / geometry.scale
      )
      snapshot.alpha = presenting ? 1 : 0
      snapshot.isUserInteractionEnabled = false
      pageView.addSubview(snapshot)
    }

    let animator = UIViewPropertyAnimator(duration: Self.duration,
                                          timingParameters: UISpringTimingParameters(dampingRatio: 1))
    animator.addAnimations { [presenting] in
      pageView.transform = presenting ? .identity : geometry.transform
      mask.frame = presenting ? pageView.bounds : geometry.window
      mask.layer.cornerRadius = presenting ? 0 : geometry.cornerRadius
      dim.alpha = presenting ? 1 : 0
    }
    animator.addCompletion { [presenting] _ in
      snapshot?.removeFromSuperview()
      dim.removeFromSuperview()
      pageView.mask = nil
      pageView.transform = .identity
      if !presenting { pageView.removeFromSuperview() }
      context.completeTransition(!context.transitionWasCancelled)
    }

    // The card dissolves into the page early on the way in, and the page into the card
    // late on the way out — a separate, shorter animator, since the spring above has no
    // keyframes.
    if let snapshot {
      _ = UIViewPropertyAnimator.runningPropertyAnimator(withDuration: Self.duration * 0.4,
                                                         delay: Self.duration * (presenting ? 0.1 : 0.45),
                                                         options: [.curveEaseInOut]) { [presenting] in
        snapshot.alpha = presenting ? 0 : 1
      }
    }
    animator.startAnimation()
  }

  /// No card to zoom to: it scrolled away, its row reloaded, or the tabs under the page
  /// are changing. A short scale and fade, so the page still arrives and leaves.
  private func scaleAndFade(_ pageView: UIView, dim: UIView, context: UIViewControllerContextTransitioning) {
    let shrunk = CGAffineTransform(scaleX: 0.94, y: 0.94)
    if presenting {
      pageView.alpha = 0
      pageView.transform = shrunk
    }
    let animator = UIViewPropertyAnimator(duration: Self.duration * 0.7, curve: .easeInOut) { [presenting] in
      pageView.alpha = presenting ? 1 : 0
      pageView.transform = presenting ? .identity : shrunk
      dim.alpha = presenting ? 1 : 0
    }
    animator.addCompletion { [presenting] _ in
      dim.removeFromSuperview()
      pageView.transform = .identity
      pageView.alpha = 1
      if !presenting { pageView.removeFromSuperview() }
      context.completeTransition(!context.transitionWasCancelled)
    }
    animator.startAnimation()
  }

  /// Where the card is, and how the full-size page maps onto it.
  private struct Geometry {
    /// The card, in the container — focus lift included.
    let card: CGRect
    /// The card view's own size, before any transform above it.
    let unscaledCard: CGSize
    /// Page size to card size: covering, so the card is filled in both directions.
    let scale: CGFloat
    /// The part of the page that lands on the card, in the page's own coordinates.
    let window: CGRect
    /// The card's corner radius, in the page's coordinates.
    let cornerRadius: CGFloat
    /// Scales the page down by `scale` and moves its centre onto the card's.
    let transform: CGAffineTransform

    @MainActor
    init?(source: TVZoomSource?, page: UIView, container: UIView) {
      guard let source, let view = source.sourceView, view.window === container.window,
            !Self.isHidden(view) else { return nil }
      let card = view.convert(view.bounds, to: container)
      guard card.width > 1, card.height > 1, view.bounds.width > 1, view.bounds.height > 1,
            container.bounds.intersects(card) else { return nil }
      let size = page.bounds.size
      let scale = max(card.width / size.width, card.height / size.height)
      let window = CGRect(x: (size.width - card.width / scale) / 2,
                          y: (size.height - card.height / scale) / 2,
                          width: card.width / scale,
                          height: card.height / scale)
      self.card = card
      self.unscaledCard = view.bounds.size
      self.scale = scale
      self.window = window
      self.cornerRadius = source.cornerRadius / scale
      self.transform = CGAffineTransform(translationX: card.midX - page.center.x,
                                         y: card.midY - page.center.y)
        .scaledBy(x: scale, y: scale)
    }

    @MainActor
    private static func isHidden(_ view: UIView) -> Bool {
      var current: UIView? = view
      while let candidate = current {
        if candidate.isHidden || candidate.alpha < 0.01 { return true }
        current = candidate.superview
      }
      return false
    }
  }
}
#endif
