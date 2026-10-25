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
//  The title is Callout medium, centred, secondary at rest and primary when focused. Wider than
//  the art, it fades at its trailing edge at rest. While this cell is focused it runs left in
//  one direction: a second copy follows, so the part that left on the left comes back in from
//  the right. The detail line (year, genre, tour) is Caption 1 regular and truncates with an
//  ellipsis — it does not scroll. A line within half a glyph of the art draws that far into
//  the gutter and stays centred; the marquee starts only once it is clearly longer. Both
//  sizes are fixed, so the grid's measured caption box does not move.
//  Like the footer, the caption rests under the art and drops by the focus room when the cover
//  grows.
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

  /// Callout, medium. The box under the art is still two of these lines tall.
  static func font(category: UIContentSizeCategory) -> UIFont {
    weighted(.callout, .medium, category: category)
  }

  /// The year / genre / tour line. Caption 1, regular, at every Dynamic Type size — never
  /// scaled per string. The box it sits in stays one Callout line, so the grid does not move.
  static func detailFont(category: UIContentSizeCategory) -> UIFont {
    weighted(.caption1, .regular, category: category)
  }

  private static func weighted(_ style: UIFont.TextStyle, _ weight: UIFont.Weight,
                               category: UIContentSizeCategory) -> UIFont {
    let base = UIFont.preferredFont(forTextStyle: style,
                                    compatibleWith: UITraitCollection(preferredContentSizeCategory: category))
    let descriptor = base.fontDescriptor.addingAttributes([
      .traits: [UIFontDescriptor.TraitKey.weight: weight]
    ])
    return UIFont(descriptor: descriptor, size: 0)
  }

  private let title = TVPageMarqueeLine()
  private let detail = TVPageMarqueeLine()

  var titleText: String? { title.text }
  var detailText: String? { detail.text }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    clipsToBounds = false

    title.translatesAutoresizingMaskIntoConstraints = false
    title.textColor = .secondaryLabel
    detail.translatesAutoresizingMaskIntoConstraints = false
    detail.textColor = .secondaryLabel
    detail.scrolls = false
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
    title.font = Self.font(category: category)
    detail.font = Self.detailFont(category: category)
    title.text = text
    detail.text = detailText
    // A new cover starts at rest, whatever the cell showed before.
    alpha = 1
    resetToRest()
  }

  /// Puts the caption in the state a focus update asks for, inside its animation coordinator:
  /// the title changes colour, the caption follows the cover down by `drop` (the room the
  /// cover grows into) or back up, and with `reveals` it fades in and out with the focus. A
  /// focused title wider than the line starts to scroll once the motion has settled. The
  /// detail line stays put and shows an ellipsis.
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
      if focused { self.startScrolling() } else { self.stopScrolling() }
    })
  }

  func startScrolling() {
    title.startScrolling()
  }

  func stopScrolling() {
    title.stopScrolling()
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
    stopScrolling()
    if reveals { alpha = 0 }
  }
}

/// One line of text, centred, at the font it was given.
///
/// `scrolls`: too wide for the line, at rest it shows its start and fades out at the trailing
/// edge. `startScrolling()` runs it left, and a second copy follows a gap behind, so the run
/// is a loop rather than a trip to the end and back. Not the system label
/// (`enablesMarqueeWhenAncestorFocused`): a lockup's caption must not scroll because some
/// *ancestor* holds focus (on the detail page that is the SwiftUI scroll view's container, an
/// ancestor of every cell — see `TVPosterArtFocus`), so the cell says when it is focused.
///
/// `scrolls == false`: the same line, truncated with an ellipsis. The year / genre / tour
/// under a cover.
@MainActor
final class TVPageMarqueeLine: UIView {
  private let label = UILabel()
  /// The same string again, one gap behind `label`, so the run can loop.
  private let echo = UILabel()

  var text: String? {
    get { label.text }
    set {
      label.text = newValue
      echo.text = newValue
      stopScrolling()
    }
  }

  var font: UIFont {
    get { label.font }
    set {
      label.font = newValue
      echo.font = newValue
      setNeedsLayout()
    }
  }

  var textColor: UIColor {
    get { label.textColor }
    set {
      label.textColor = newValue
      echo.textColor = newValue
    }
  }

  /// The title scrolls. The detail line sets this false and truncates instead.
  var scrolls = true {
    didSet {
      label.lineBreakMode = scrolls ? .byClipping : .byTruncatingTail
      if !scrolls { stopScrolling() }
    }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = true
    label.textAlignment = .center
    label.lineBreakMode = .byClipping
    echo.textAlignment = .left
    echo.lineBreakMode = .byClipping
    echo.isHidden = true
    addSubview(label)
    addSubview(echo)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    // While it scrolls the two copies own their frames.
    if !isScrolling { layoutAtRest() }
    restFade.frame = bounds
  }

  /// Half a glyph past the art, each side. A title within that of the line stays centred
  /// there instead of a marquee that would shuttle it back and forth by the same half glyph.
  /// The gutter between covers is 44 pt, so the extra does not meet the next caption.
  private var sideBleed: CGFloat {
    (label.font.pointSize * 0.35).rounded(.up)
  }

  private var textWidth: CGFloat {
    ceil(label.intrinsicContentSize.width)
  }

  /// Wider than the art by more than `sideBleed` on each side.
  private var overflows: Bool {
    textWidth > bounds.width + sideBleed * 2 + 1
  }

  /// Fits: centred, and a title within half a glyph of the art draws into that slack.
  /// A truncating line that is genuinely too long ends in an ellipsis. A scrolling line
  /// that is too long shows its start, the trailing edge faded.
  private func layoutAtRest() {
    echo.isHidden = true
    if !overflows {
      clipsToBounds = false
      label.textAlignment = .center
      label.frame = CGRect(x: -sideBleed, y: 0, width: bounds.width + sideBleed * 2, height: bounds.height)
      layer.mask = nil
    } else if scrolls {
      clipsToBounds = true
      label.textAlignment = .natural
      let overflow = textWidth - bounds.width
      label.frame = CGRect(x: 0, y: 0, width: bounds.width + overflow, height: bounds.height)
      restFade.frame = bounds
      layer.mask = restFade
    } else {
      clipsToBounds = true
      label.textAlignment = .center
      label.frame = bounds
      layer.mask = nil
    }
  }

  /// At rest only the trailing edge fades: the text starts where it starts. While it runs,
  /// the line clips at the art — a fade on both sides made the glyphs look shorter than
  /// the box they had to travel.
  private let restFade: CAGradientLayer = {
    let layer = CAGradientLayer()
    layer.startPoint = CGPoint(x: 0, y: 0.5)
    layer.endPoint = CGPoint(x: 1, y: 0.5)
    layer.colors = [UIColor.black, .black, UIColor.clear].map(\.cgColor)
    layer.locations = [0, 0.88, 1]
    return layer
  }()

  private(set) var isScrolling = false
  private static let marqueeKey = "marquee"

  func startScrolling() {
    guard scrolls, !isScrolling, bounds.width > 1, !UIAccessibility.isReduceMotionEnabled else { return }
    let natural = ceil(label.intrinsicContentSize.width)
    guard overflows else { return }
    isScrolling = true
    clipsToBounds = true
    layer.mask = nil
    // A tenth of the art between the end of one copy and the start of the next.
    let distance = natural + max(bounds.width / 10, 10)
    label.textAlignment = .left
    echo.isHidden = false
    // The model stays where the run starts. Removing the animation on blur puts both
    // copies back there; it never writes the end position into the layer.
    UIView.performWithoutAnimation {
      label.frame = CGRect(x: 0, y: 0, width: natural, height: bounds.height)
      echo.frame = CGRect(x: distance, y: 0, width: natural, height: bounds.height)
    }
    loop(label.layer, distance: distance)
    loop(echo.layer, distance: distance)
  }

  /// One pass at about 40 pt a second, then again. After `distance` the echo sits where
  /// the first copy started, so the repeat is the same picture.
  private func loop(_ layer: CALayer, distance: CGFloat) {
    let animation = CABasicAnimation(keyPath: "position.x")
    let from = layer.position.x
    animation.fromValue = from
    animation.toValue = from - distance
    animation.duration = Double(distance) / 40
    animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + 0.8
    animation.timingFunction = CAMediaTimingFunction(name: .linear)
    animation.repeatCount = .infinity
    animation.isRemovedOnCompletion = false
    animation.fillMode = .both
    layer.add(animation, forKey: Self.marqueeKey)
  }

  func stopScrolling() {
    guard isScrolling else { setNeedsLayout(); return }
    isScrolling = false
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    label.layer.removeAnimation(forKey: Self.marqueeKey)
    echo.layer.removeAnimation(forKey: Self.marqueeKey)
    echo.isHidden = true
    layoutAtRest()
    CATransaction.commit()
  }
}
#endif
