#if os(tvOS)
//
//  TVPageInfoCells.swift
//  KinoPubUI
//
//  The cells of `TVPageCellKind.infoCard` and the title over a strip's group.
//
//  Every info card is a `TVCardView` — the system's floating platter, the UIKit side of
//  SwiftUI's `.card` button style — holding one content view. The platter, its focus lift,
//  tilt and white fill are the card view's. The cell does only what `TVPageWideCardCell`
//  (search's person and title cards) does around it: a quiet resting fill on the floating
//  content view that steps aside on focus, and the text's colours following the platter
//  from light-on-dark to dark-on-white. Content is drawn by hand in `layoutSubviews` —
//  a few labels at known sizes, no constraint solving per scroll tick.
//

import TVUIKit
import UIKit

// MARK: - Fonts

enum TVPageFonts {
  /// A Dynamic Type text style with a weight (and optionally the rounded design the score
  /// digits wear): the style's own descriptor plus traits, so it keeps tracking the
  /// content size category. The bare text style renders regular on tvOS.
  static func font(_ style: UIFont.TextStyle, weight: UIFont.Weight, rounded: Bool = false) -> UIFont {
    var descriptor = UIFont.preferredFont(forTextStyle: style).fontDescriptor
    if rounded, let design = descriptor.withDesign(.rounded) { descriptor = design }
    descriptor = descriptor.addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
    return UIFont(descriptor: descriptor, size: 0)
  }
}

extension UIFont {
  /// How far apart UILabel sets two lines of this font. **Not `lineHeight`**: that is
  /// 35.0 for tvOS `.body` where the label's pitch is 36, so a frame of `lines ×
  /// lineHeight` was a point short of its last line and the label drew one line fewer —
  /// a two-line warning came out as one line truncated, centred in its own frame.
  var linePitch: CGFloat { ceil(ascender) + ceil(-descender) + ceil(leading) }
}

extension UILabel {
  /// Running text that breaks between words and never inside one. A narrow card of
  /// Russian prose is hyphenated by the typesetter on its own ("сотря-сение"), which reads
  /// as a typo in four short lines.
  ///
  /// **Probed on the tvOS 27.2 simulator (2026-10-06): no paragraph setting stops it.** A
  /// plain label, an attributed one with `hyphenationFactor = 0` and
  /// `usesDefaultHyphenation = false`, `lineBreakStrategy = []` and `.byWordWrapping` all
  /// hyphenate. What does is tagging the run with a language that has no hyphenation
  /// data for Cyrillic — `NSLanguage` ("en") — so it is typeset by whole words. The font
  /// and colour stay the label's own.
  func setUnhyphenated(_ text: String?) {
    guard let text else {
      attributedText = nil
      return
    }
    let paragraph = NSMutableParagraphStyle()
    paragraph.hyphenationFactor = 0
    paragraph.usesDefaultHyphenation = false
    paragraph.lineBreakMode = lineBreakMode
    paragraph.alignment = textAlignment
    attributedText = NSAttributedString(string: text, attributes: [
      .font: font as Any,
      .foregroundColor: textColor as Any,
      .paragraphStyle: paragraph,
      NSAttributedString.Key(rawValue: "NSLanguage"): "en"
    ])
  }
}

// MARK: - Group title

/// The title over one group of a strip, on the same leading edge as the group's first card.
/// Not a control. In the row's own header type — `.headline` semibold, secondary — or, for a
/// group that says it is a subheading (`TVPageGroup.isSubheading`), a smaller `.callout`:
/// "Director" and "Starring" under "Cast & Crew".
///
/// The cell is as wide as its group, and its label can stand to the right of the cell's
/// leading edge (`setStickyShift`): a group that has scrolled under the page's side inset
/// keeps its title on screen until its last card has gone, instead of the title sliding off
/// to the left with the first one.
@MainActor
final class TVPageGroupTitleCell: UICollectionViewCell {
  private let label = UILabel()

  /// The title of a row: what a `TVPageHeaderView` draws.
  static var titleFont: UIFont { TVPageHeaderView.titleFont }
  /// A heading under a heading.
  static var subheadingFont: UIFont { TVPageFonts.font(.callout, weight: .semibold) }

  static func font(subheading: Bool) -> UIFont { subheading ? subheadingFont : titleFont }

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = false
    contentView.clipsToBounds = false
    label.font = Self.titleFont
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .secondaryLabel
    label.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(label)
    NSLayoutConstraint.activate([
      label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      label.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
      label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var canBecomeFocused: Bool { false }

  func configure(text: String, subheading: Bool) {
    label.font = Self.font(subheading: subheading)
    label.text = text
    accessibilityLabel = text
    accessibilityTraits = .header
  }

  /// How far the label stands right of where its group starts. A transform on the label,
  /// not the cell: the cell's own transform is the focus dodge, and the cell has to stay
  /// where its group is for the collection to keep it alive while the group is on screen.
  func setStickyShift(_ shift: CGFloat) {
    label.transform = shift == 0 ? .identity : CGAffineTransform(translationX: shift, y: 0)
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    transform = .identity
    label.transform = .identity
    label.text = nil
  }
}

// MARK: - Platter

/// What an info card draws inside its platter. `applyFocusLook` is the one focus response
/// that is ours: ink on the resting fill, ink on the white platter.
@MainActor
class TVPageCardContent: UIView {
  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// Padding between the platter's edge and its content.
  static let padding: CGFloat = 28

  func applyFocusLook(_ focused: Bool) {}

  /// Primary and secondary ink for the platter's current look. On the white focused
  /// platter the system's label colours would be light-on-light, so they are fixed dark.
  static func ink(focused: Bool) -> UIColor { focused ? .black : .label }
  static func secondaryInk(focused: Bool) -> UIColor {
    focused ? UIColor.black.withAlphaComponent(0.6) : .secondaryLabel
  }
}

/// A `TVCardView` holding one `TVPageCardContent`. Subclasses install their content once.
@MainActor
class TVPageInfoCardCell: UICollectionViewCell {
  let cardView = TVCardView()
  private(set) var content: TVPageCardContent?

  /// What this card wears at rest — search's cards' tint (`TVPagePlatter`). A column of
  /// specifications wears none: it reads as text on the page and only gets a platter once
  /// it has focus.
  var restingFill: UIColor { TVPagePlatter.restingFill }

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = false
    contentView.clipsToBounds = false

    cardView.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(cardView)
    NSLayoutConstraint.activate([
      cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
      cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
    ])
    let host = cardView.contentView
    host.layer.cornerRadius = TVPagePlatter.cornerRadius
    host.layer.cornerCurve = .continuous
    host.clipsToBounds = true
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func install(_ view: TVPageCardContent) {
    content = view
    view.translatesAutoresizingMaskIntoConstraints = false
    let host = cardView.contentView
    host.addSubview(view)
    NSLayoutConstraint.activate([
      view.topAnchor.constraint(equalTo: host.topAnchor),
      view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      view.bottomAnchor.constraint(equalTo: host.bottomAnchor)
    ])
    applyFocusLook(false)
  }

  /// The card view sizes its platter from `contentSize` (a system default otherwise, ~500
  /// wide whatever the frame). `TVPageCellMetrics.cardRecipe` measured which content size
  /// puts the resting platter on the HIG column; the cell's frame is the envelope.
  func apply(recipe: TVPageCellRecipe) {
    if cardView.contentSize != recipe.posterContentSize {
      cardView.contentSize = recipe.posterContentSize
    }
  }

  /// Colour only, like search's cards: the lift, the tilt and the white fill are the card
  /// view's. The lockup calls its component hook only for its *own* focus, and here the
  /// cell holds focus (so selection, focus memory and the context menu stay the
  /// collection view's) — so the cell follows it.
  override func didUpdateFocus(in context: UIFocusUpdateContext,
                               with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    let focused = context.nextFocusedView === self
      || context.nextFocusedView?.isDescendant(of: self) == true
    // Focus left for a view that holds the whole page — SwiftUI's own focusable things
    // are that — and TVUIKit takes it for this cell still being focused.
    if !focused, let next = context.nextFocusedView, cardView.isDescendant(of: next) {
      cardView.releaseFocusedLook(with: coordinator)
    }
    coordinator.addCoordinatedAnimations({ [weak self] in
      self?.applyFocusLook(focused)
    })
  }

  private func applyFocusLook(_ focused: Bool) {
    cardView.contentView.backgroundColor = focused ? .clear : restingFill
    content?.applyFocusLook(focused)
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    applyFocusLook(false)
    accessibilityIdentifier = nil
    accessibilityLabel = nil
  }
}

// MARK: - Score

@MainActor
final class TVPageRatingCell: TVPageInfoCardCell {
  private let body = TVPageRatingContent()

  override init(frame: CGRect) {
    super.init(frame: frame)
    install(body)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ rating: TVPageInfoCard.Rating) {
    body.configure(rating)
    accessibilityIdentifier = "kinopub.rating.\(rating.id)"
    accessibilityLabel = [rating.title, rating.value, rating.caption].compactMap { $0 }.joined(separator: ", ")
  }
}

/// The source's mark before its number, with how many people stand behind it underneath —
/// or, for kino.pub's own score, how many thumbs of each kind. A source that has voters but
/// no score yet has a dash in secondary ink where the number would be, and still says how
/// many voted.
///
/// The card is as tall as its two lines (`height`), not as tall as a review: a score has
/// nothing to say that needs the room.
@MainActor
final class TVPageRatingContent: TVPageCardContent {
  private let logoView = UIImageView()
  private let nameLabel = UILabel()
  private let valueLabel = UILabel()
  private let captionLabel = UILabel()
  private let thumbsLabel = UILabel()
  private var thumbs: TVPageInfoCard.Rating.Thumbs?
  private var hasValue = true
  private var looksFocused = false

  /// The number: title2, rounded, medium. (SF Compact is not on tvOS — probed 2026-10-11.)
  static var valueFont: UIFont { TVPageFonts.font(.title2, weight: .medium, rounded: true) }
  /// How many people stand behind it: caption2, regular.
  static var captionFont: UIFont { TVPageFonts.font(.caption2, weight: .regular) }
  /// What the number says when the source has none yet.
  static let noValue = "—"
  /// Between the mark and the number.
  static let markGap: CGFloat = 16
  /// Between the mark-and-number line and the line under it.
  static let lineGap: CGFloat = 14

  /// The mark's height at the default text size, scaled with Dynamic Type like the text.
  static var markHeight: CGFloat {
    let traits = UITraitCollection(preferredContentSizeCategory: TVPageCellMetrics.contentSizeCategory)
    return UIFontMetrics(forTextStyle: .title2).scaledValue(for: 44, compatibleWith: traits).rounded()
  }

  /// The mark-and-number line: the number's own, or the mark's if that is taller.
  static var lineHeight: CGFloat { max(ceil(valueFont.linePitch), markHeight) }

  /// How tall a score card is: the padding, the line of mark and number, and the line of
  /// voters under it. 168 at the default text size.
  static var height: CGFloat {
    padding * 2 + lineHeight + lineGap + ceil(captionFont.linePitch)
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    logoView.contentMode = .scaleAspectFit
    nameLabel.font = TVPageFonts.font(.callout, weight: .semibold)
    valueLabel.font = Self.valueFont
    captionLabel.font = Self.captionFont
    thumbsLabel.font = Self.captionFont
    for label in [nameLabel, valueLabel, captionLabel, thumbsLabel] {
      label.adjustsFontForContentSizeCategory = true
      label.textAlignment = .center
      label.lineBreakMode = .byTruncatingTail
    }
    // A full score (`100%`) is wider than the room beside a mark: it shrinks to fit rather
    // than lose its last digit.
    valueLabel.adjustsFontSizeToFitWidth = true
    valueLabel.minimumScaleFactor = 0.6
    addSubview(logoView)
    for label in [nameLabel, valueLabel, captionLabel, thumbsLabel] { addSubview(label) }
    applyFocusLook(false)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ rating: TVPageInfoCard.Rating) {
    let mark = rating.source?.uiImage()
    logoView.image = mark
    logoView.isHidden = mark == nil
    // A source we hold no mark for is told by its name, in the mark's place.
    nameLabel.text = rating.title
    nameLabel.isHidden = mark != nil
    hasValue = rating.value != nil
    valueLabel.text = rating.value ?? Self.noValue
    captionLabel.text = rating.caption
    captionLabel.isHidden = rating.thumbs != nil || rating.caption == nil
    thumbs = rating.thumbs
    thumbsLabel.isHidden = rating.thumbs == nil
    applyFocusLook(looksFocused)
    setNeedsLayout()
  }

  private func renderThumbs() {
    guard let thumbs else { thumbsLabel.attributedText = nil; return }
    let ink = Self.secondaryInk(focused: looksFocused)
    let configuration = UIImage.SymbolConfiguration(textStyle: .caption2)
    func symbol(_ name: String) -> NSAttributedString {
      let attachment = NSTextAttachment()
      attachment.image = UIImage(systemName: name, withConfiguration: configuration)?
        .withTintColor(ink, renderingMode: .alwaysOriginal)
      return NSAttributedString(attachment: attachment)
    }
    let line = NSMutableAttributedString()
    line.append(symbol("hand.thumbsup.fill"))
    line.append(NSAttributedString(string: " \(thumbs.up)"))
    line.append(NSAttributedString(string: "     "))
    line.append(symbol("hand.thumbsdown.fill"))
    line.append(NSAttributedString(string: " \(thumbs.down)"))
    line.addAttributes([.foregroundColor: ink, .font: thumbsLabel.font as Any],
                       range: NSRange(location: 0, length: line.length))
    thumbsLabel.attributedText = line
  }

  override func applyFocusLook(_ focused: Bool) {
    self.looksFocused = focused
    nameLabel.textColor = Self.ink(focused: focused)
    valueLabel.textColor = hasValue ? Self.ink(focused: focused) : Self.secondaryInk(focused: focused)
    captionLabel.textColor = Self.secondaryInk(focused: focused)
    thumbsLabel.textColor = Self.secondaryInk(focused: focused)
    renderThumbs()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let pad = Self.padding
    let width = max(bounds.width - pad * 2, 1)
    let unbounded = CGSize(width: width, height: .greatestFiniteMagnitude)

    // Underneath: the voters, or the thumbs.
    let footer = thumbsLabel.isHidden ? captionLabel : thumbsLabel
    let footerHeight = footer.isHidden ? 0 : ceil(footer.sizeThatFits(unbounded).height)
    let line = Self.lineHeight
    let block = line + (footerHeight > 0 ? Self.lineGap + footerHeight : 0)
    let top = max((bounds.height - block) / 2, 0)

    // The line: the mark, then the number, one group centred on the card.
    var leading = CGSize.zero
    if !logoView.isHidden, let image = logoView.image, image.size.height > 0 {
      let height = Self.markHeight
      leading = CGSize(width: min(height * image.size.width / image.size.height, width / 2), height: height)
    } else if !nameLabel.isHidden {
      let name = nameLabel.sizeThatFits(unbounded)
      leading = CGSize(width: min(name.width, width / 2), height: name.height)
    }
    let gap = leading.width > 0 ? Self.markGap : 0
    let valueWidth = min(valueLabel.sizeThatFits(unbounded).width, max(width - leading.width - gap, 1))
    let left = (bounds.width - (leading.width + gap + valueWidth)) / 2
    let leadingFrame = CGRect(x: left, y: top + (line - leading.height) / 2,
                              width: leading.width, height: leading.height)
    if logoView.isHidden { nameLabel.frame = leadingFrame } else { logoView.frame = leadingFrame }
    valueLabel.frame = CGRect(x: left + leading.width + gap, y: top, width: valueWidth, height: line)

    if footerHeight > 0 {
      footer.frame = CGRect(x: pad, y: top + line + Self.lineGap, width: width, height: footerHeight)
    }
  }
}

// MARK: - Reviews, counted

@MainActor
final class TVPageReviewsCell: TVPageInfoCardCell {
  private let body = TVPageReviewsContent()

  override init(frame: CGRect) {
    super.init(frame: frame)
    install(body)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ reviews: TVPageInfoCard.Reviews) {
    body.configure(reviews)
    accessibilityIdentifier = "kinopub.reviews.\(reviews.id)"
    accessibilityLabel = reviews.accessibilityLabel
  }
}

/// How the three tones of a review are drawn: a face in a ring, a smile, a frown, a straight mouth.
///
/// **Apple API limitation, probed on the tvOS 26.5 simulator (2026-10-11):** SF Symbols has
/// `face.smiling` and nothing for the other two — `UIImage(systemName: "face.frowning")` and
/// `"face.neutral"` are nil — so all three are drawn here, as one family. A template image, tinted
/// by the view. Re-probe on the next SDK, and replace this with the symbols if they land.
enum TVPageMoodGlyph {
  enum Mood { case positive, negative, neutral }

  static func image(_ mood: Mood, side: CGFloat) -> UIImage {
    let size = CGSize(width: side, height: side)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 0 // the screen's own
    let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
      UIColor.black.setStroke()
      UIColor.black.setFill()
      let line = side * 0.09
      let ring = UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: line / 2, dy: line / 2))
      ring.lineWidth = line
      ring.stroke()

      let eye = side * 0.06
      for x in [0.34, 0.66] {
        UIBezierPath(ovalIn: CGRect(x: side * CGFloat(x) - eye, y: side * 0.38 - eye,
                                    width: eye * 2, height: eye * 2)).fill()
      }

      let mouth: UIBezierPath
      switch mood {
      case .positive:
        mouth = UIBezierPath(arcCenter: CGPoint(x: side * 0.5, y: side * 0.50), radius: side * 0.21,
                             startAngle: .pi * 0.15, endAngle: .pi * 0.85, clockwise: true)
      case .negative:
        mouth = UIBezierPath(arcCenter: CGPoint(x: side * 0.5, y: side * 0.79), radius: side * 0.21,
                             startAngle: .pi * 1.15, endAngle: .pi * 1.85, clockwise: true)
      case .neutral:
        mouth = UIBezierPath()
        mouth.move(to: CGPoint(x: side * 0.34, y: side * 0.66))
        mouth.addLine(to: CGPoint(x: side * 0.66, y: side * 0.66))
      }
      mouth.lineWidth = line
      mouth.lineCapStyle = .round
      mouth.stroke()
    }
    return image.withRenderingMode(.alwaysTemplate)
  }
}

/// The count of reviews beside how they were meant: the speech bubbles before the total (a score's
/// mark before its number), the title under them, and — on the right — a face and a count for each
/// tone, in the tone's colour. As tall as a score card and its two lines, as wide as that needs and
/// never narrower than a score (`TVPageInfoCard.width(inColumn:)`).
@MainActor
final class TVPageReviewsContent: TVPageCardContent {
  private let iconView = UIImageView()
  private let countLabel = UILabel()
  private let titleLabel = UILabel()
  private let tones: [(mood: TVPageMoodGlyph.Mood, glyph: UIImageView, count: UILabel)]
  private var showsTones = false
  private var looksFocused = false

  private static var countFont: UIFont { TVPageRatingContent.valueFont }
  private static var toneFont: UIFont { TVPageFonts.font(.caption1, weight: .regular, rounded: true) }
  private static let toneGap: CGFloat = 6
  /// Between the bubbles and the total, as between a score's mark and its number.
  private static var markGap: CGFloat { TVPageRatingContent.markGap }
  /// Between what is counted and how it was meant.
  private static let columnGap: CGFloat = 28
  private static let glyphGap: CGFloat = 10

  private static var iconImage: UIImage? {
    UIImage(systemName: "bubble.left.and.text.bubble.right.fill",
            withConfiguration: UIImage.SymbolConfiguration(font: countFont, scale: .medium))
  }

  private static var glyphSide: CGFloat { ceil(toneFont.lineHeight) }

  override init(frame: CGRect) {
    tones = [.positive, .negative, .neutral].map { ($0, UIImageView(), UILabel()) }
    super.init(frame: frame)
    iconView.contentMode = .scaleAspectFit
    iconView.image = Self.iconImage
    countLabel.font = Self.countFont
    titleLabel.font = TVPageRatingContent.captionFont
    for label in [countLabel, titleLabel] {
      label.adjustsFontForContentSizeCategory = true
      label.lineBreakMode = .byTruncatingTail
    }
    titleLabel.textAlignment = .center
    addSubview(iconView)
    addSubview(countLabel)
    addSubview(titleLabel)
    for tone in tones {
      tone.glyph.contentMode = .scaleAspectFit
      tone.glyph.image = TVPageMoodGlyph.image(tone.mood, side: Self.glyphSide)
      tone.count.font = Self.toneFont
      tone.count.adjustsFontForContentSizeCategory = true
      addSubview(tone.glyph)
      addSubview(tone.count)
    }
    applyFocusLook(false)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ reviews: TVPageInfoCard.Reviews) {
    countLabel.text = reviews.count
    titleLabel.text = reviews.title
    showsTones = reviews.tones != nil
    if let counts = reviews.tones {
      for (tone, text) in zip(tones, [counts.positive, counts.negative, counts.neutral]) { tone.count.text = text }
    }
    for tone in tones {
      tone.glyph.isHidden = !showsTones
      tone.count.isHidden = !showsTones
    }
    setNeedsLayout()
  }

  override func applyFocusLook(_ focused: Bool) {
    self.looksFocused = focused
    iconView.tintColor = Self.secondaryInk(focused: focused)
    countLabel.textColor = Self.ink(focused: focused)
    titleLabel.textColor = Self.secondaryInk(focused: focused)
    for tone in tones {
      switch tone.mood {
      case .positive: tone.glyph.tintColor = .systemGreen
      case .negative: tone.glyph.tintColor = .systemRed
      case .neutral: tone.glyph.tintColor = Self.secondaryInk(focused: focused)
      }
      tone.count.textColor = Self.secondaryInk(focused: focused)
    }
  }

  // MARK: Geometry

  /// What the left of the card needs: the bubbles and the total, or the title under them if wider.
  private static func leftWidth(_ reviews: TVPageInfoCard.Reviews) -> CGFloat {
    let icon = iconImage?.size.width ?? 0
    let count = ceil((reviews.count as NSString).size(withAttributes: [.font: countFont]).width)
    let title = ceil((reviews.title as NSString).size(withAttributes: [.font: TVPageRatingContent.captionFont]).width)
    return max(icon + markGap + count, title)
  }

  /// What the right of the card needs: a face, then the widest of the three counts.
  private static func tonesWidth(_ tones: TVPageInfoCard.Reviews.Tones) -> CGFloat {
    let widest = [tones.positive, tones.negative, tones.neutral].map {
      ceil(($0 as NSString).size(withAttributes: [.font: toneFont]).width)
    }.max() ?? 0
    return glyphSide + glyphGap + widest
  }

  /// How wide the card has to be: its padding, the left and, when it has them, the tones.
  static func fittingWidth(for reviews: TVPageInfoCard.Reviews) -> CGFloat {
    var width = padding * 2 + leftWidth(reviews)
    if let tones = reviews.tones { width += columnGap + tonesWidth(tones) }
    return ceil(width)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let pad = Self.padding
    let line = TVPageRatingContent.lineHeight
    let titleHeight = ceil(TVPageRatingContent.captionFont.linePitch)
    let block = line + TVPageRatingContent.lineGap + titleHeight
    let top = max((bounds.height - block) / 2, 0)

    // The right: a face and a count for each tone, stacked, right-aligned, centred in the card.
    var rightEdge = bounds.width - pad
    if showsTones {
      let rowHeight = max(Self.glyphSide, ceil(Self.toneFont.linePitch))
      let stack = rowHeight * CGFloat(tones.count) + Self.toneGap * CGFloat(tones.count - 1)
      let widest = tones.map { ceil($0.count.sizeThatFits(CGSize(width: 1000, height: rowHeight)).width) }.max() ?? 0
      let width = Self.glyphSide + Self.glyphGap + widest
      let left = bounds.width - pad - width
      var y = (bounds.height - stack) / 2
      for tone in tones {
        tone.glyph.frame = CGRect(x: left, y: y + (rowHeight - Self.glyphSide) / 2,
                                  width: Self.glyphSide, height: Self.glyphSide)
        tone.count.frame = CGRect(x: left + Self.glyphSide + Self.glyphGap, y: y, width: widest, height: rowHeight)
        y += rowHeight + Self.toneGap
      }
      rightEdge = left - Self.columnGap
    }

    // The left: the bubbles and the total as one line, the title centred under them — the group
    // centred in what the tones left.
    let iconSize = iconView.image?.size ?? .zero
    let countWidth = ceil(countLabel.sizeThatFits(CGSize(width: 1000, height: line)).width)
    let lineWidth = iconSize.width + Self.markGap + countWidth
    let room = max(rightEdge - pad, 1)
    let left = pad + max((room - lineWidth) / 2, 0)
    iconView.frame = CGRect(x: left, y: top + (line - iconSize.height) / 2,
                            width: iconSize.width, height: iconSize.height)
    countLabel.frame = CGRect(x: left + iconSize.width + Self.markGap, y: top, width: countWidth, height: line)
    titleLabel.frame = CGRect(x: pad, y: top + line + TVPageRatingContent.lineGap, width: room, height: titleHeight)
  }
}

// MARK: - Review

@MainActor
final class TVPageReviewCell: TVPageInfoCardCell {
  private let body = TVPageReviewContent()

  override init(frame: CGRect) {
    super.init(frame: frame)
    install(body)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ review: TVPageInfoCard.Review) {
    body.configure(review)
    accessibilityIdentifier = "kinopub.review.\(review.id)"
    accessibilityLabel = [review.headline, review.body].joined(separator: ". ")
  }
}

/// A review as a preview: the headline, as much of the text as the card has room for with
/// an ellipsis on the last line that fits, and how it was meant and when at the foot. The
/// whole review is where Select goes — this is never the place to read one.
@MainActor
final class TVPageReviewContent: TVPageCardContent {
  private let headlineLabel = UILabel()
  private let bodyLabel = UILabel()
  private let sentimentLabel = UILabel()
  private let dateLabel = UILabel()
  private var tone: TVPageInfoCard.Review.Tone = .neutral
  private var looksFocused = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    headlineLabel.font = TVPageFonts.font(.body, weight: .semibold)
    headlineLabel.numberOfLines = 2
    bodyLabel.font = .preferredFont(forTextStyle: .body)
    sentimentLabel.font = TVPageFonts.font(.caption1, weight: .semibold)
    dateLabel.font = .preferredFont(forTextStyle: .caption1)
    dateLabel.textAlignment = .right
    for label in [headlineLabel, bodyLabel, sentimentLabel, dateLabel] {
      label.adjustsFontForContentSizeCategory = true
      label.lineBreakMode = .byTruncatingTail
      addSubview(label)
    }
    applyFocusLook(false)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ review: TVPageInfoCard.Review) {
    headlineLabel.text = review.headline
    bodyLabel.setUnhyphenated(review.body
      .replacingOccurrences(of: "\\s*\\n+\\s*", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines))
    sentimentLabel.text = review.sentiment
    dateLabel.text = review.date
    tone = review.tone
    applyFocusLook(looksFocused)
    setNeedsLayout()
  }

  override func applyFocusLook(_ focused: Bool) {
    self.looksFocused = focused
    headlineLabel.textColor = Self.ink(focused: focused)
    bodyLabel.textColor = Self.ink(focused: focused)
    dateLabel.textColor = Self.secondaryInk(focused: focused)
    switch tone {
    case .positive: sentimentLabel.textColor = focused ? UIColor(red: 0.1, green: 0.5, blue: 0.2, alpha: 1) : .systemGreen
    case .negative: sentimentLabel.textColor = focused ? UIColor(red: 0.75, green: 0.1, blue: 0.1, alpha: 1) : .systemRed
    case .neutral: sentimentLabel.textColor = Self.secondaryInk(focused: focused)
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let pad = Self.padding
    let width = max(bounds.width - pad * 2, 1)
    let fit = CGSize(width: width, height: .greatestFiniteMagnitude)

    let footerHeight = max(sentimentLabel.sizeThatFits(fit).height, dateLabel.sizeThatFits(fit).height)
    let footerY = bounds.height - pad + 2 - footerHeight
    let dateWidth = min(dateLabel.sizeThatFits(fit).width, width * 0.5)
    dateLabel.frame = CGRect(x: bounds.width - pad - dateWidth, y: footerY, width: dateWidth, height: footerHeight)
    sentimentLabel.frame = CGRect(x: pad, y: footerY, width: max(width - dateWidth - 12, 0), height: footerHeight)

    let headlineHeight = headlineLabel.sizeThatFits(fit).height
    headlineLabel.frame = CGRect(x: pad, y: pad - 4, width: width, height: headlineHeight)

    // As many whole lines as fit between the headline and the foot.
    let bodyTop = headlineLabel.frame.maxY + 8
    let room = footerY - 10 - bodyTop
    let lineHeight = bodyLabel.font.linePitch
    let lines = max(Int(floor(room / lineHeight)), 1)
    if bodyLabel.numberOfLines != lines { bodyLabel.numberOfLines = lines }
    bodyLabel.frame = CGRect(x: pad, y: bodyTop, width: width, height: CGFloat(lines) * lineHeight)
  }
}

// MARK: - Fact

@MainActor
final class TVPageFactCell: TVPageInfoCardCell {
  private let body = TVPageFactContent()

  override init(frame: CGRect) {
    super.init(frame: frame)
    install(body)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ fact: TVPageInfoCard.Fact) {
    body.configure(fact)
    accessibilityIdentifier = "kinopub.fact.\(fact.id)"
    accessibilityLabel = fact.isHidden ? fact.warning : fact.text
  }
}

/// A fact fills the card from the top and ellipsises on the last line that fits. A spoiler that
/// is still hidden says so — a warning glyph, quiet, at caption size, and its words; it needs no
/// label to be pressed (Sasha, 2026-10-11), the card is the control.
@MainActor
final class TVPageFactContent: TVPageCardContent {
  private let textLabel = UILabel()
  private let warningIcon = UIImageView()
  private let warningLabel = UILabel()
  private var showsWarning = false
  private var looksFocused = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    // Body, regular (Sasha, 2026-10-11): the bare text style renders medium on tvOS.
    textLabel.font = TVPageFonts.font(.body, weight: .regular)
    warningLabel.font = TVPageFonts.font(.body, weight: .regular)
    warningIcon.contentMode = .scaleAspectFit
    warningIcon.image = UIImage(systemName: "exclamationmark.triangle.fill",
                                withConfiguration: UIImage.SymbolConfiguration(textStyle: .caption1))
    for label in [textLabel, warningLabel] {
      label.adjustsFontForContentSizeCategory = true
      label.lineBreakMode = .byTruncatingTail
      addSubview(label)
    }
    addSubview(warningIcon)
    applyFocusLook(false)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ fact: TVPageInfoCard.Fact) {
    showsWarning = fact.isHidden
    textLabel.setUnhyphenated(fact.text)
    warningLabel.setUnhyphenated(fact.warning)
    textLabel.isHidden = fact.isHidden
    warningLabel.isHidden = !fact.isHidden
    warningIcon.isHidden = !fact.isHidden
    setNeedsLayout()
  }

  override func applyFocusLook(_ focused: Bool) {
    self.looksFocused = focused
    textLabel.textColor = Self.ink(focused: focused)
    warningLabel.textColor = Self.secondaryInk(focused: focused)
    warningIcon.tintColor = Self.secondaryInk(focused: focused)
  }

  /// The words, from `top`, as many lines as the room allows and no taller than they are: a
  /// label taller than its words centres them in it.
  private func fit(_ label: UILabel, top: CGFloat, width: CGFloat, room: CGFloat) {
    let pitch = label.font.linePitch
    let lines = max(Int(floor(room / pitch)), 1)
    if label.numberOfLines != lines { label.numberOfLines = lines }
    let words = ceil(label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
    label.frame = CGRect(x: Self.padding, y: top, width: width, height: min(words, CGFloat(lines) * pitch))
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let pad = Self.padding
    let width = max(bounds.width - pad * 2, 1)
    let start = pad - 2

    if showsWarning {
      let iconSize = warningIcon.image?.size ?? CGSize(width: 24, height: 24)
      warningIcon.frame = CGRect(x: pad, y: start, width: iconSize.width, height: iconSize.height)
      let top = warningIcon.frame.maxY + 12
      fit(warningLabel, top: top, width: width, room: bounds.height - pad + 4 - top)
    } else {
      fit(textLabel, top: start, width: width, room: bounds.height - pad * 2 + 4)
    }
  }
}
#endif
