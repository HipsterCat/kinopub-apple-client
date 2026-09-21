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
//  (`TVUIKitMediaItemCell`, `TVUIKitPersonCell`) — nothing new to draw.
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
/// code here.
@MainActor
final class TVPageChipCell: UICollectionViewCell {
  private let button = UIButton(configuration: .gray())
  var onSelect: (() -> Void)?

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
    var configuration = button.configuration ?? .gray()
    configuration.title = chip.title
    configuration.image = chip.systemImage.flatMap { UIImage(systemName: $0) }
    configuration.imagePadding = 12
    configuration.cornerStyle = .capsule
    button.configuration = configuration
  }

  override var canBecomeFocused: Bool { false }

  override func prepareForReuse() {
    super.prepareForReuse()
    onSelect = nil
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
    countLabel.font = Self.font(.title3, weight: .medium)
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
