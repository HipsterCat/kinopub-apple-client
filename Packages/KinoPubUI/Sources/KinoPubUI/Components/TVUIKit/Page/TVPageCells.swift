#if os(tvOS)
//
//  TVPageCells.swift
//  KinoPubUI
//
//  The cells a `TVPageCollectionViewController` dequeues, and the section header.
//
//  Poster: `TVPosterView` **as the whole cell**, with the caption in its own footer
//  and our overlays inside its `contentView` — the container the header says clients
//  add their subviews to ("Views added directly to the lockup view have undefined
//  behaviors"). Everything in there scales, lifts and tilts with the system's focus
//  motion, so the cell owns no transform, no coordinated animation and no stale-
//  appearance reset. The earlier cell (`TVUIKitPosterCell`) put its overlay *beside*
//  the lockup and mirrored the focus scale by hand; that is the pile of constraints
//  this replaces.
//
//  Still and person cells are the existing system-configuration cells
//  (`TVUIKitMediaItemCell`, `TVUIKitPersonCell`) — nothing new to draw. The wide card
//  is a `TVCardView` with a thumbnail and text in its `contentView`.
//

import TVUIKit
import UIKit

// MARK: - Poster lockup

@MainActor
final class TVPageLockupPosterCell: UICollectionViewCell {
  /// Air between the art and the footer caption. `TVLockupView.contentViewInsets`
  /// takes negative values for positive spacing; the probe in `TVPageCellMetrics`
  /// applies the same, so the envelope it measures includes this.
  static let footerGap: CGFloat = 12

  private let posterView = TVPosterView(image: nil)
  private let watchedGlyph = UIImageView()

  private var imageTask: Task<Void, Never>?
  private var currentURL: URL?
  private var recipe: TVPageCellRecipe?

  override init(frame: CGRect) {
    super.init(frame: frame)
    setUp()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private func setUp() {
    // The lockup's focus lift and shadow extend past the cell; the collection view is
    // unclipped for the same reason.
    clipsToBounds = false
    contentView.clipsToBounds = false

    posterView.translatesAutoresizingMaskIntoConstraints = false
    posterView.contentViewInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: -Self.footerGap, trailing: 0)
    contentView.addSubview(posterView)
    NSLayoutConstraint.activate([
      posterView.topAnchor.constraint(equalTo: contentView.topAnchor),
      posterView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      posterView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      posterView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
    ])

    // Overlays live in the lockup's contentView, pinned to its imageView, so they ride
    // the system focus transform instead of imitating it. No progress bar on a poster:
    // a poster is a title, not a playable item — the bar belongs to stills.
    let host = posterView.contentView
    let image = posterView.imageView

    watchedGlyph.translatesAutoresizingMaskIntoConstraints = false
    watchedGlyph.image = UIImage(systemName: "checkmark.circle.fill")
    watchedGlyph.tintColor = .white
    watchedGlyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
//    TVUIKitChromeSupport.applyLegibilityShadow(to: watchedGlyph.layer)
    watchedGlyph.isHidden = true
    host.addSubview(watchedGlyph)

    NSLayoutConstraint.activate([
      watchedGlyph.leadingAnchor.constraint(equalTo: image.leadingAnchor, constant: 16),
      watchedGlyph.bottomAnchor.constraint(equalTo: image.bottomAnchor, constant: -14)
    ])
  }

  func configure(card: MediaCard, recipe: TVPageCellRecipe, caption: TVPageCaption) {
    self.recipe = recipe
    posterView.contentSize = recipe.posterContentSize
    applyCaption(caption, title: card.title)

    let posterID = "kinopub.poster.\(card.id)"
    accessibilityIdentifier = posterID
    posterView.accessibilityIdentifier = posterID
    posterView.accessibilityLabel = card.title

    watchedGlyph.isHidden = !card.isWatched

    loadImage(URL(string: card.posterURL))
  }

  func configurePlaceholder(recipe: TVPageCellRecipe) {
    self.recipe = recipe
    posterView.contentSize = recipe.posterContentSize
    applyCaption(.never, title: nil)
    watchedGlyph.isHidden = true
    imageTask?.cancel()
    imageTask = nil
    currentURL = nil
    setImage(placeholder)
  }

  /// Accepted adapter (tvOS 27.2, measured 2026-09-21). `TVPosterView` computes its
  /// `focusSizeIncrease` — the inset the *unfocused* art sits at inside the envelope —
  /// only for an image assigned **outside a layout pass**. Assigned from a cell
  /// registration handler or `layoutSubviews` (both run inside the collection view's
  /// layout) the increase is 0 and stays 0 on every later layout, and the art fills the
  /// whole envelope: 286 wide instead of 260. Assigned from a later run-loop turn it is
  /// 13 / 20 on the next layout. Being in a window makes no difference — measured both.
  /// So the image is handed over on the next main-queue turn, one frame late, which is
  /// what the async artwork path does anyway.
  private var desiredImage: UIImage?

  private func setImage(_ image: UIImage) {
    desiredImage = image
    DispatchQueue.main.async { [weak self] in
      guard let self, self.desiredImage === image else { return }
      self.posterView.image = image
    }
  }

  /// Always an image of the content size, never nil: the lockup computes its focus
  /// envelope from the image, and a nil image means a different (zero) envelope until
  /// the real art lands.
  /// Rounded like the art the lockup will round itself, and resolved for this cell's
  /// appearance — the lockup rounds a real image but draws a bitmap placeholder as is.
  private var placeholder: UIImage {
    TVUIKitTileArtwork.placeholder(size: recipe?.posterContentSize ?? CGSize(width: 260, height: 390),
                                   cornerRadius: Self.placeholderCornerRadius,
                                   traits: traitCollection)
  }

  private static let placeholderCornerRadius: CGFloat = 14

  private func applyCaption(_ caption: TVPageCaption, title: String?) {
    switch caption {
    case .never:
      posterView.title = nil
    case .always, .onFocus:
      posterView.title = title
      // The footer is the system's: it hides and reveals itself, and a long title
      // marquees inside the lockup's width while focused (a screenshot mid-scroll
      // looks clipped on the left — it is not).
      posterView.footerView?.showsOnlyWhenAncestorFocused = caption == .onFocus
      posterView.footerView?.titleLabel?.textColor = isFocused ? .label : .secondaryLabel
    }
  }

  private func loadImage(_ url: URL?) {
    imageTask?.cancel()
    imageTask = nil
    currentURL = url
    guard let url else {
      setImage(placeholder)
      ArtworkLog.skipped(by: "poster", reason: "no artwork URL")
      return
    }
    // Decode at the focused size (the content size *is* the focused envelope of the
    // art), so the lifted lockup stays sharp. kino.pub's "big" poster is 250 × 375, so
    // in practice the source is the ceiling.
    let decodeSize = recipe?.posterContentSize ?? CGSize(width: 260, height: 390)
    if let hit = TVUIKitRemoteImage.cached(url: url, size: decodeSize) {
      setImage(hit)
      ArtworkLog.servedFromMemory(url, by: "poster")
      return
    }
    setImage(placeholder)
    ArtworkLog.requested(url, by: "poster")
    imageTask = Task { [weak self] in
      let image = await TVUIKitRemoteImage.load(url: url, size: decodeSize)
      guard let self, !Task.isCancelled, self.currentURL == url, let image else { return }
      self.setImage(image)
    }
  }

  /// Caption colour is the one focus response that is ours: secondary at rest, label
  /// when focused (the footer's own default is label always). Colour only — motion,
  /// lift and the footer's reveal stay the lockup's.
  override func didUpdateFocus(in context: UIFocusUpdateContext,
                               with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    let focused = context.nextFocusedView === self
      || context.nextFocusedView?.isDescendant(of: self) == true
    coordinator.addCoordinatedAnimations({ [weak self] in
      self?.posterView.footerView?.titleLabel?.textColor = focused ? .label : .secondaryLabel
    }, completion: { [weak self] in
      guard let self, !focused else { return }
      self.resetStaleFocusAppearance()
    })
  }

  /// Accepted adapter, carried over from `TVUIKitPosterCell`: `TVPosterView`'s
  /// coordinated *unfocus* animation sometimes never runs — a tab switched mid-motion
  /// leaves every lockup of the row lifted, tilting and captioned while nothing is
  /// focused. This undoes the system's stranded motion; it runs no motion of its own.
  func resetStaleFocusAppearance() {
    guard !isFocused else { return }
    func clear(_ view: UIView) {
      if !view.transform.isIdentity { view.transform = .identity }
      if !CATransform3DIsIdentity(view.layer.transform) { view.layer.transform = CATransform3DIdentity }
      view.motionEffects.forEach { view.removeMotionEffect($0) }
      view.subviews.forEach(clear)
    }
    clear(posterView)
    posterView.footerView?.updateAppearance(forLockupViewState: .normal)
    posterView.footerView?.titleLabel?.textColor = .secondaryLabel
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    imageTask?.cancel()
    imageTask = nil
    currentURL = nil
    desiredImage = nil
    posterView.image = nil
    posterView.title = nil
    watchedGlyph.isHidden = true
    resetStaleFocusAppearance()
    accessibilityIdentifier = nil
    posterView.accessibilityIdentifier = nil
    posterView.accessibilityLabel = nil
  }
}

// MARK: - Chip

/// A pill of text. The cell is not focusable; the system button inside it is, which is
/// what gives the pill the stock tvOS button focus (lift, white fill) with no focus
/// code here. A chip with a `menu` is the system pull-down: `UIButton.menu` shown as
/// the primary action, the current pick checked — the same control a SwiftUI `Menu`
/// becomes on tvOS, with no menu chrome of ours.
@MainActor
final class TVPageChipCell: UICollectionViewCell {
  private let button = UIButton(configuration: .gray())
  var onSelect: (() -> Void)?
  var onOption: ((String) -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.configuration?.cornerStyle = .capsule
    button.addAction(UIAction { [weak self] _ in self?.onSelect?() }, for: .primaryActionTriggered)
    contentView.addSubview(button)
    NSLayoutConstraint.activate([
      button.topAnchor.constraint(equalTo: contentView.topAnchor),
      button.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(chip: TVPageChip) {
    button.configuration = Self.configuration(for: chip)
    if let menu = chip.menu {
      let blocks: [UIMenuElement] = menu.groups.map { group in
        let actions = group.options.map { option in
          UIAction(title: option.title, state: option.id == group.selectedID ? .on : .off) { [weak self] _ in
            self?.onOption?(option.id)
          }
        }
        return UIMenu(title: group.title ?? "", options: .displayInline, children: actions)
      }
      button.menu = UIMenu(children: blocks.count == 1 ? (blocks[0] as? UIMenu)?.children ?? blocks : blocks)
      button.showsMenuAsPrimaryAction = true
    } else {
      button.menu = nil
      button.showsMenuAsPrimaryAction = false
    }
    button.accessibilityIdentifier = "kinopub.chip.\(chip.id)"
  }

  override var canBecomeFocused: Bool { false }

  /// Active filters take the system's tinted fill; the rest stay gray. Title in
  /// `.body`, the size the filter row is drawn at. Focus is the button's own either way.
  static func configuration(for chip: TVPageChip) -> UIButton.Configuration {
    var configuration = chip.isActive ? UIButton.Configuration.tinted() : .gray()
    configuration.title = chip.title
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var outgoing = incoming
      outgoing.font = UIFont.preferredFont(forTextStyle: .body)
      return outgoing
    }
    configuration.imagePadding = 12
    configuration.cornerStyle = .capsule
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 26, bottom: 12, trailing: 26)
    if let systemImage = chip.systemImage {
      configuration.image = UIImage(systemName: systemImage)
      configuration.imagePlacement = .leading
      configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .body)
    } else if chip.menu != nil {
      // A pull-down with no icon of its own says so with the system chevron.
      configuration.image = UIImage(systemName: "chevron.down")
      configuration.imagePlacement = .trailing
      configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .caption1, scale: .small)
    } else {
      configuration.image = nil
    }
    return configuration
  }

  private static var widthCache: [TVPageChip: CGFloat] = [:]
  private static let prototype = UIButton(configuration: .gray())

  /// The pill's own width, measured on a prototype system button with the same
  /// configuration — what a filter row needs to push its trailing pills to the edge
  /// exactly (a flexible edge over estimated widths lands short).
  static func fittingWidth(for chip: TVPageChip) -> CGFloat {
    if let cached = widthCache[chip] { return cached }
    prototype.configuration = configuration(for: chip)
    let size = prototype.systemLayoutSizeFitting(
      CGSize(width: UIView.layoutFittingCompressedSize.width, height: TVPageLayout.chipHeight),
      withHorizontalFittingPriority: .fittingSizeLevel,
      verticalFittingPriority: .required
    )
    let width = ceil(size.width)
    widthCache[chip] = width
    return width
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    onSelect = nil
    onOption = nil
  }
}

// MARK: - Wide card

/// A `TVCardView` — the system's floating platter, the UIKit side of SwiftUI's `.card`
/// button style — holding a thumbnail and up to three lines of text. The platter, its
/// focus lift, tilt and white fill are the card view's; the cell fills the
/// `contentView`, the container `TVLockupView` says subviews belong in.
///
/// A title's poster fills the platter's leading edge top to bottom; a person gets the
/// system monogram circle (`TVUIKitPersonAvatarView`, the same face as the cast rail and
/// the person page) inset by the padding. Text: title in `.body` (two lines), then in
/// `.caption2` the original title when that is what matched, and year · genres.
@MainActor
final class TVPageWideCardCell: UICollectionViewCell {
  private let cardView = TVCardView()
  private let thumbnail = UIImageView()
  private let avatar = TVUIKitPersonAvatarView()
  private let titleLabel = UILabel()
  private let originalLabel = UILabel()
  private let detailLabel = UILabel()
  private let text = UIStackView()
  private var textLeading: NSLayoutConstraint!

  private var imageTask: Task<Void, Never>?
  private var currentURL: URL?

  private static let restingFill = UIColor.label.withAlphaComponent(0.1) // REPLACE WITH SYSTEM BACKGROUND COLORS
  private static let cornerRadius: CGFloat = 12
  private static let textGap: CGFloat = 24

  private static var thumbnailSize: CGSize {
    let height = TVPageLayout.cardHeight
    return CGSize(width: (height * CardAspect.poster.ratio).rounded(), height: height)
  }

  private static var avatarDiameter: CGFloat { TVPageLayout.cardHeight - TVPageLayout.cardPadding * 2 }

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = false
    contentView.clipsToBounds = false

    cardView.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(cardView)

    let host = cardView.contentView
    // The system platter (default `cardBackgroundColor`) is clear at rest in dark mode
    // and white under focus. The rest tint is ours, on the floating content view so it
    // moves with it, and it steps aside on focus to let the system's white through.
    // The content view clips to the platter's corners, which is what rounds the poster's
    // leading edge.
    host.backgroundColor = Self.restingFill
    host.layer.cornerRadius = Self.cornerRadius
    host.layer.cornerCurve = .continuous
    host.clipsToBounds = true

    thumbnail.translatesAutoresizingMaskIntoConstraints = false
    thumbnail.contentMode = .scaleAspectFill
    thumbnail.clipsToBounds = true
    host.addSubview(thumbnail)

    avatar.translatesAutoresizingMaskIntoConstraints = false
    avatar.isUserInteractionEnabled = false
    host.addSubview(avatar)

    titleLabel.font = Self.font(.body, weight: .medium)
    titleLabel.numberOfLines = 2
    originalLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
    originalLabel.numberOfLines = 1
    detailLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
    detailLabel.numberOfLines = 1
    for label in [titleLabel, originalLabel, detailLabel] {
      label.adjustsFontForContentSizeCategory = true
      text.addArrangedSubview(label)
    }
    text.axis = .vertical
    text.spacing = 4
    text.setCustomSpacing(10, after: originalLabel)
    text.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(text)
    applyFocusColors(false)

    let size = Self.thumbnailSize
    textLeading = text.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: size.width + Self.textGap)
    NSLayoutConstraint.activate([
      cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
      cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

      thumbnail.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      thumbnail.topAnchor.constraint(equalTo: host.topAnchor),
      thumbnail.bottomAnchor.constraint(equalTo: host.bottomAnchor),
      thumbnail.widthAnchor.constraint(equalTo: thumbnail.heightAnchor, multiplier: CardAspect.poster.ratio),

      avatar.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: TVPageLayout.cardPadding * 1.5),
      avatar.centerYAnchor.constraint(equalTo: host.centerYAnchor),
      avatar.heightAnchor.constraint(equalToConstant: Self.avatarDiameter),
      avatar.widthAnchor.constraint(equalToConstant: Self.avatarDiameter),

      textLeading,
      text.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor, constant: -Self.textGap),
      text.centerYAnchor.constraint(equalTo: host.centerYAnchor)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// Colour only, like the poster caption: the platter's lift, tilt and white fill are
  /// the card view's. `TVLockupViewComponent` would be the lockup's own hook for this,
  /// but the lockup only calls it for its *own* focus — here the cell holds focus (so
  /// selection, focus memory and the context menu stay the collection view's) and the
  /// card only follows it as an ancestor (measured 2026-09-25: never called).
  override func didUpdateFocus(in context: UIFocusUpdateContext,
                               with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    let focused = context.nextFocusedView === self
      || context.nextFocusedView?.isDescendant(of: self) == true
    coordinator.addCoordinatedAnimations({ [weak self] in
      self?.applyFocusColors(focused)
    })
  }

  private func applyFocusColors(_ focused: Bool) {
    cardView.contentView.backgroundColor = focused ? .clear : Self.restingFill
    titleLabel.textColor = focused ? .black : .label
    let secondary = focused ? UIColor.black.withAlphaComponent(0.6) : .secondaryLabel
    originalLabel.textColor = secondary
    detailLabel.textColor = secondary
  }

  /// The card view sizes its platter from `contentSize` (a system default otherwise,
  /// ~500 wide whatever the frame). `TVPageCellMetrics` measured which content size
  /// puts the resting platter on the HIG column; the cell's frame is the envelope.
  func apply(recipe: TVPageCellRecipe) {
    if cardView.contentSize != recipe.posterContentSize {
      cardView.contentSize = recipe.posterContentSize
    }
  }

  func configure(card: MediaCard, match: String?) {
    thumbnail.isHidden = false
    avatar.isHidden = true
    textLeading.constant = Self.thumbnailSize.width + Self.textGap
    titleLabel.text = card.title
    let original = Self.matchedOriginal(card, match: match)
    originalLabel.text = original
    originalLabel.isHidden = original == nil
    detailLabel.text = Self.detail(for: card)
    detailLabel.isHidden = detailLabel.text == nil
    accessibilityIdentifier = "kinopub.card.\(card.id)"
    cardView.accessibilityLabel = [card.title, original, detailLabel.text].compactMap { $0 }.joined(separator: ", ")
    loadThumbnail(URL(string: card.posterURL))
  }

  func configure(person: TVUIKitPerson) {
    thumbnail.isHidden = true
    avatar.isHidden = false
    textLeading.constant = TVPageLayout.cardPadding * 1.5 + Self.avatarDiameter + Self.textGap
    imageTask?.cancel()
    imageTask = nil
    avatar.configure(name: person.name, photoURL: person.photoURL)
    titleLabel.text = person.name
    originalLabel.text = nil
    originalLabel.isHidden = true
    detailLabel.text = person.caption
    detailLabel.isHidden = person.caption == nil
    accessibilityIdentifier = "kinopub.card.person.\(person.id)"
    cardView.accessibilityLabel = [person.name, person.caption].compactMap { $0 }.joined(separator: ", ")
  }

  func configurePlaceholder() {
    thumbnail.isHidden = false
    avatar.isHidden = true
    titleLabel.text = nil
    originalLabel.isHidden = true
    detailLabel.isHidden = true
    thumbnail.image = placeholder
  }

  /// The original title, when the search matched it and it says something the local
  /// title does not.
  private static func matchedOriginal(_ card: MediaCard, match: String?) -> String? {
    guard let match, !match.isEmpty,
          let original = card.subtitle?.trimmingCharacters(in: .whitespaces), !original.isEmpty,
          original.caseInsensitiveCompare(card.title) != .orderedSame,
          original.range(of: match, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    else { return nil }
    return original
  }

  /// "2021  Боевик, Фантастика" — year and genres. No running time: in a result list the
  /// year and genre are what tell two same-named titles apart.
  private static func detail(for card: MediaCard) -> String? {
    let parts = [card.year.map(String.init), card.genreLine].compactMap { $0 }.filter { !$0.isEmpty }
    return parts.isEmpty ? nil : parts.joined(separator: "\u{2003}")
  }

  private var placeholder: UIImage {
    TVUIKitTileArtwork.placeholder(size: Self.thumbnailSize, cornerRadius: 0, traits: traitCollection)
  }

  private func loadThumbnail(_ url: URL?) {
    imageTask?.cancel()
    imageTask = nil
    currentURL = url
    let size = Self.thumbnailSize
    guard let url else {
      thumbnail.image = placeholder
      return
    }
    if let hit = TVUIKitRemoteImage.cached(url: url, size: size) {
      thumbnail.image = hit
      return
    }
    thumbnail.image = placeholder
    imageTask = Task { [weak self] in
      let image = await TVUIKitRemoteImage.load(url: url, size: size)
      guard let self, !Task.isCancelled, self.currentURL == url, let image else { return }
      self.thumbnail.image = image
    }
  }

  private static func font(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
    let descriptor = UIFont.preferredFont(forTextStyle: style).fontDescriptor
      .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
    return UIFont(descriptor: descriptor, size: 0)
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    imageTask?.cancel()
    imageTask = nil
    currentURL = nil
    thumbnail.image = nil
    titleLabel.text = nil
    originalLabel.text = nil
    detailLabel.text = nil
    accessibilityIdentifier = nil
    applyFocusColors(false)
  }
}

// MARK: - Layout debug

/// `-KINOPUBLayoutDebug`: a translucent fill per section (the decoration background the
/// layout adds behind each), cycling colours by section index, so a section's content
/// insets show as the coloured margin around its cells.
final class TVPageDebugSectionBackground: UICollectionReusableView {
  static let palette: [UIColor] = [.systemBlue, .systemGreen, .systemRed, .systemYellow, .systemPurple, .systemOrange, .systemTeal]

  override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
    super.apply(layoutAttributes)
    let color = Self.palette[layoutAttributes.indexPath.section % Self.palette.count]
    backgroundColor = color.withAlphaComponent(0.22)
    layer.borderColor = color.cgColor
    layer.borderWidth = 2
  }
}

// MARK: - Header

/// Row title, leading on the same column as the first card: `.headline` in secondary.
/// Not focusable — "see all" belongs to a trailing card or a control inside the row.
@MainActor
final class TVPageHeaderView: UICollectionReusableView {
  private let titleLabel = UILabel()
  private let countLabel = UILabel()

  override init(frame: CGRect) {
    super.init(frame: frame)
    // `TypeScale.rowHeader` in UIKit terms: headline **semibold**, secondary. The
    // bare headline text style on tvOS renders regular, which is not the shelf title.
    titleLabel.font = Self.font(.headline, weight: .semibold)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textColor = .secondaryLabel
    countLabel.font = Self.font(.subheadline, weight: .medium)
    countLabel.adjustsFontForContentSizeCategory = true
    countLabel.textColor = .tertiaryLabel

    let stack = UIStackView(arrangedSubviews: [titleLabel, countLabel])
    stack.axis = .horizontal
    stack.alignment = .firstBaseline
    stack.spacing = 12
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// A Dynamic Type text style with a weight — the style's descriptor plus the trait,
  /// so it keeps tracking the content size category.
  private static func font(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
    let descriptor = UIFont.preferredFont(forTextStyle: style).fontDescriptor
      .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
    return UIFont(descriptor: descriptor, size: 0)
  }

  func configure(title: String, count: String?) {
    titleLabel.text = title
    countLabel.text = count
    countLabel.isHidden = count == nil
    accessibilityLabel = count.map { "\(title), \($0)" } ?? title
  }
}
#endif
