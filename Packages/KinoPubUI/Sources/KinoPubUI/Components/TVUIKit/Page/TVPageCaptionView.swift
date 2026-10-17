#if os(tvOS)
//
//  TVPageCaptionView.swift
//  KinoPubUI
//
//  The two lines under a captioned cover: a title and a line of detail (a year, the episodes
//  left of a followed series, or nothing). Drawn here, not by the lockup's own footer.
//
//  **Why not the system footer (measured 2026-10-06, tvOS 27.2 and 26.5).** `TVPosterView`
//  decides on its first layout whether its footer is two lines (74 pt) or one (37 pt, the
//  subtitle label collapsed to height 0) and then gives the art the difference: 384 → 421 pt.
//  The decision is not ours to make — it depends on whether the cell was created or reused
//  inside a window, and on the width of the page's first, wrong pass — and nothing we set on
//  the footer, the labels, the lockup's size or the texts made it stable: in a 99-cell grid
//  scrolled 40 rows 28 cells came out one-line with tall art and a missing second line (a
//  Search grid on Sasha's screen: no year, taller covers). So a captioned cover is the lockup
//  *without* a footer — the same rigid geometry as a rail's cover — plus this view, which has
//  two lines because it says so.
//
//  It matches the footer it replaces: Callout (SF Medium 31 pt), centred, title secondary at
//  rest and primary when focused, the detail always secondary. Like the footer, it rests under
//  the art and drops by the focus room when the cover grows, in the focus update's animation.
//  A title wider than the art fades out at its trailing edge at rest, no ellipsis, and scrolls
//  to its end and back while focused (the system label's marquee).
//

import UIKit

@MainActor
final class TVPageCaptionView: UIView {
  /// One line's height at a Dynamic Type size. The caption is exactly two of them, the way the
  /// footer it replaces was (2 × 37 pt at the default size).
  static func lineHeight(category: UIContentSizeCategory) -> CGFloat {
    font(category: category).lineHeight.rounded(.up)
  }

  static func height(category: UIContentSizeCategory) -> CGFloat {
    2 * lineHeight(category: category)
  }

  static func font(category: UIContentSizeCategory) -> UIFont {
    UIFont.preferredFont(forTextStyle: .callout,
                         compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
  }

  private let title = TVPageMarqueeLine()
  private let detail = UILabel()

  var titleText: String? { title.text }
  var detailText: String? { detail.text }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    clipsToBounds = false

    title.translatesAutoresizingMaskIntoConstraints = false
    title.textColor = .secondaryLabel
    detail.translatesAutoresizingMaskIntoConstraints = false
    detail.textAlignment = .center
    detail.lineBreakMode = .byTruncatingTail
    detail.textColor = .secondaryLabel
    addSubview(title)
    addSubview(detail)
    NSLayoutConstraint.activate([
      title.topAnchor.constraint(equalTo: topAnchor),
      title.leadingAnchor.constraint(equalTo: leadingAnchor),
      title.trailingAnchor.constraint(equalTo: trailingAnchor),
      title.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.5),
      detail.topAnchor.constraint(equalTo: title.bottomAnchor),
      detail.leadingAnchor.constraint(equalTo: leadingAnchor),
      detail.trailingAnchor.constraint(equalTo: trailingAnchor),
      detail.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// Both lines, at the size the page is measured at.
  func configure(title text: String?, detail detailText: String?, category: UIContentSizeCategory) {
    let font = Self.font(category: category)
    title.font = font
    detail.font = font
    title.text = text
    detail.text = detailText
    // A new cover starts at rest, whatever the cell showed before.
    alpha = 1
    resetToRest()
  }

  /// Puts the caption in the state a focus update asks for, inside its animation coordinator:
  /// the title changes colour, the caption follows the cover down by `drop` (the room the
  /// cover grows into) or back up, and with `reveals` it fades in and out with the focus. A
  /// focused title wider than the line starts to scroll once the motion has settled.
  func setFocused(_ focused: Bool, drop: CGFloat, reveals: Bool, in coordinator: UIFocusAnimationCoordinator) {
    coordinator.addCoordinatedAnimations({ [weak self] in
      guard let self else { return }
      if focused {
        self.setFocusedLook(drop: drop)
      } else {
        self.resetToRest(reveals: reveals)
      }
      if reveals { self.alpha = focused ? 1 : 0 }
    }, completion: { [weak self] in
      guard let self else { return }
      if focused { self.title.startScrolling() } else { self.title.stopScrolling() }
    })
  }

  /// The focused look, immediately: a cell configured while it already holds focus.
  func setFocusedLook(drop: CGFloat) {
    title.textColor = .label
    transform = CGAffineTransform(translationX: 0, y: drop)
  }

  /// Back to rest without animation — a reused cell, or the system stranded a focus motion.
  /// `reveals`: the caption of an `.onFocus` cover is invisible at rest.
  func resetToRest(reveals: Bool = false) {
    transform = .identity
    title.textColor = .secondaryLabel
    title.stopScrolling()
    if reveals { alpha = 0 }
  }
}

/// One line of text, centred. Too wide for the line, it does what a system label with
/// `enablesMarqueeWhenAncestorFocused` does: at rest it shows its start and fades out at the
/// trailing edge — no ellipsis — and `startScrolling()` moves it to its end and back.
///
/// Not the system label itself: a lockup's caption must not scroll because some *ancestor*
/// holds focus (on the detail page that is the SwiftUI scroll view's container, an ancestor of
/// every cell — see `TVPosterArtFocus`), so the cell says when it is focused.
@MainActor
final class TVPageMarqueeLine: UIView {
  private let label = UILabel()

  var text: String? {
    get { label.text }
    set { label.text = newValue; stopScrolling() }
  }

  var font: UIFont {
    get { label.font }
    set { label.font = newValue; setNeedsLayout() }
  }

  var textColor: UIColor {
    get { label.textColor }
    set { label.textColor = newValue }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = true
    label.textAlignment = .center
    label.lineBreakMode = .byClipping
    addSubview(label)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    // While it scrolls the label owns its frame.
    if !isScrolling { layoutAtRest() }
    fade.frame = bounds
  }

  private var overflow: CGFloat {
    ceil(label.intrinsicContentSize.width) - bounds.width
  }

  /// Fits: centred in the line. Too wide: its start, the trailing edge faded.
  private func layoutAtRest() {
    let overflow = overflow
    if overflow > 1 {
      label.textAlignment = .natural
      label.frame = CGRect(x: 0, y: 0, width: bounds.width + overflow, height: bounds.height)
      restFade.frame = bounds
      layer.mask = restFade
    } else {
      label.textAlignment = .center
      label.frame = bounds
      layer.mask = nil
    }
  }

  /// Soft edges while the text runs under them, as the system's marquee has.
  private let fade: CAGradientLayer = {
    let layer = CAGradientLayer()
    layer.startPoint = CGPoint(x: 0, y: 0.5)
    layer.endPoint = CGPoint(x: 1, y: 0.5)
    layer.colors = [UIColor.clear, .black, .black, UIColor.clear].map(\.cgColor)
    layer.locations = [0, 0.06, 0.94, 1]
    return layer
  }()

  /// At rest only the trailing edge fades: the text starts where it starts.
  private let restFade: CAGradientLayer = {
    let layer = CAGradientLayer()
    layer.startPoint = CGPoint(x: 0, y: 0.5)
    layer.endPoint = CGPoint(x: 1, y: 0.5)
    layer.colors = [UIColor.black, .black, UIColor.clear].map(\.cgColor)
    layer.locations = [0, 0.88, 1]
    return layer
  }()

  private(set) var isScrolling = false

  func startScrolling() {
    guard !isScrolling, bounds.width > 1, !UIAccessibility.isReduceMotionEnabled else { return }
    let natural = ceil(label.intrinsicContentSize.width)
    let overflow = natural - bounds.width
    guard overflow > 1 else { return }
    isScrolling = true
    fade.frame = bounds
    layer.mask = fade
    label.textAlignment = .left
    label.frame = CGRect(x: 0, y: 0, width: natural, height: bounds.height)
    // About 40 pt a second, a beat at the start before it moves.
    UIView.animate(withDuration: Double(overflow) / 40, delay: 0.8,
                   options: [.repeat, .autoreverse, .curveLinear, .allowUserInteraction]) { [label] in
      label.frame.origin.x = -overflow
    }
  }

  func stopScrolling() {
    guard isScrolling else { setNeedsLayout(); return }
    isScrolling = false
    label.layer.removeAllAnimations()
    layoutAtRest()
  }
}
#endif
