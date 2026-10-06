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

/// The source's mark over its number, with how many people stand behind it underneath —
/// or, for kino.pub's own score, how many thumbs of each kind.
@MainActor
final class TVPageRatingContent: TVPageCardContent {
  private let logoView = UIImageView()
  private let nameLabel = UILabel()
  private let valueLabel = UILabel()
  private let captionLabel = UILabel()
  private let thumbsLabel = UILabel()
  private var thumbs: TVPageInfoCard.Rating.Thumbs?
  private var looksFocused = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    logoView.contentMode = .scaleAspectFit
    nameLabel.font = TVPageFonts.font(.callout, weight: .semibold)
    valueLabel.font = TVPageFonts.font(.title2, weight: .semibold, rounded: true)
    captionLabel.font = .preferredFont(forTextStyle: .caption1)
    thumbsLabel.font = .preferredFont(forTextStyle: .caption1)
    for label in [nameLabel, valueLabel, captionLabel, thumbsLabel] {
      label.adjustsFontForContentSizeCategory = true
      label.textAlignment = .center
      label.lineBreakMode = .byTruncatingTail
    }
    addSubview(logoView)
    for label in [nameLabel, valueLabel, captionLabel, thumbsLabel] { addSubview(label) }
    applyFocusLook(false)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ rating: TVPageInfoCard.Rating) {
    let mark = rating.source?.uiImage()
    logoView.image = mark
    logoView.isHidden = mark == nil
    nameLabel.text = rating.title
    nameLabel.isHidden = mark != nil && !rating.showsName
    valueLabel.text = rating.value
    captionLabel.text = rating.caption
    captionLabel.isHidden = rating.thumbs != nil || rating.caption == nil
    thumbs = rating.thumbs
    thumbsLabel.isHidden = rating.thumbs == nil
    renderThumbs()
    setNeedsLayout()
  }

  private func renderThumbs() {
    guard let thumbs else { thumbsLabel.attributedText = nil; return }
    let ink = Self.secondaryInk(focused: looksFocused)
    let configuration = UIImage.SymbolConfiguration(textStyle: .caption1)
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
    valueLabel.textColor = Self.ink(focused: focused)
    captionLabel.textColor = Self.secondaryInk(focused: focused)
    thumbsLabel.textColor = Self.secondaryInk(focused: focused)
    renderThumbs()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let pad = Self.padding
    let width = max(bounds.width - pad * 2, 1)
    let top: CGFloat = pad

    // Mark (or the source's name when we hold no mark): across the top. A glyph with no
    // lettering of its own shares the line with the name.
    let markHeight: CGFloat = 44
    let nameSize = nameLabel.isHidden
      ? CGSize.zero
      : nameLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    if !logoView.isHidden, let image = logoView.image, image.size.height > 0 {
      let ratio = image.size.width / image.size.height
      let gap: CGFloat = nameSize.width > 0 ? 10 : 0
      let markWidth = min(markHeight * ratio, max(width - nameSize.width - gap, 1))
      let name = min(nameSize.width, max(width - markWidth - gap, 0))
      let lineWidth = markWidth + gap + name
      let left = (bounds.width - lineWidth) / 2
      logoView.frame = CGRect(x: left, y: top, width: markWidth, height: markWidth / max(ratio, 0.01))
      nameLabel.frame = CGRect(x: left + markWidth + gap, y: top + (markHeight - nameSize.height) / 2,
                               width: name, height: nameSize.height)
    } else {
      nameLabel.frame = CGRect(x: pad, y: top + (markHeight - nameSize.height) / 2,
                               width: width, height: nameSize.height)
    }

    // Underneath: the voters, or the thumbs.
    let footer = thumbsLabel.isHidden ? captionLabel : thumbsLabel
    var footerHeight: CGFloat = 0
    if !footer.isHidden {
      footerHeight = footer.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
      footer.frame = CGRect(x: pad, y: bounds.height - pad - footerHeight, width: width, height: footerHeight)
    }

    // The number in the middle of what is left.
    let valueSize = valueLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
    let freeTop = top + markHeight
    let freeBottom = bounds.height - pad - footerHeight
    valueLabel.frame = CGRect(x: pad, y: freeTop + (freeBottom - freeTop - valueSize.height) / 2,
                              width: width, height: valueSize.height)
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

/// A fact fills the card and ellipsises on the last line that fits. A spoiler that is
/// still hidden says so, in a warning glyph, and offers to show itself.
@MainActor
final class TVPageFactContent: TVPageCardContent {
  private let textLabel = UILabel()
  private let warningIcon = UIImageView()
  private let warningLabel = UILabel()
  private let revealLabel = UILabel()
  private var showsWarning = false
  private var looksFocused = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    textLabel.font = .preferredFont(forTextStyle: .body)
    warningLabel.font = .preferredFont(forTextStyle: .body)
    warningLabel.numberOfLines = 3
    revealLabel.font = .preferredFont(forTextStyle: .body)
    warningIcon.contentMode = .scaleAspectFit
    warningIcon.image = UIImage(systemName: "exclamationmark.triangle.fill",
                                withConfiguration: UIImage.SymbolConfiguration(textStyle: .title2))
    for label in [textLabel, warningLabel, revealLabel] {
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
    revealLabel.text = fact.revealTitle
    textLabel.isHidden = fact.isHidden
    warningLabel.isHidden = !fact.isHidden
    revealLabel.isHidden = !fact.isHidden
    warningIcon.isHidden = !fact.isHidden
    setNeedsLayout()
  }

  override func applyFocusLook(_ focused: Bool) {
    self.looksFocused = focused
    textLabel.textColor = Self.ink(focused: focused)
    warningLabel.textColor = Self.secondaryInk(focused: focused)
    revealLabel.textColor = Self.secondaryInk(focused: focused)
    warningIcon.tintColor = Self.ink(focused: focused)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let pad = Self.padding
    let width = max(bounds.width - pad * 2, 1)
    let fit = CGSize(width: width, height: .greatestFiniteMagnitude)

    if showsWarning {
      let iconSize = warningIcon.image?.size ?? CGSize(width: 40, height: 40)
      warningIcon.frame = CGRect(x: pad, y: pad - 2, width: iconSize.width, height: iconSize.height)
      let revealHeight = revealLabel.sizeThatFits(fit).height
      revealLabel.frame = CGRect(x: pad, y: bounds.height - pad - revealHeight, width: width, height: revealHeight)
      let top = warningIcon.frame.maxY + 14
      let room = revealLabel.frame.minY - 10 - top
      let lineHeight = warningLabel.font.linePitch
      let lines = max(min(Int(floor(room / lineHeight)), 3), 1)
      if warningLabel.numberOfLines != lines { warningLabel.numberOfLines = lines }
      warningLabel.frame = CGRect(x: pad, y: top, width: width, height: CGFloat(lines) * lineHeight)
    } else {
      let room = bounds.height - pad * 2 + 4
      let lineHeight = textLabel.font.linePitch
      let lines = max(Int(floor(room / lineHeight)), 1)
      if textLabel.numberOfLines != lines { textLabel.numberOfLines = lines }
      textLabel.frame = CGRect(x: pad, y: pad - 2, width: width, height: CGFloat(lines) * lineHeight)
    }
  }
}
#endif
