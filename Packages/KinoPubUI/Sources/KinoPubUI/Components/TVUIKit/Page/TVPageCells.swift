#if os(tvOS)
//
//  TVPageCells.swift
//  KinoPubUI
//
//  The cells a `TVPageCollectionViewController` dequeues, and the section header.
//
//  Poster: `TVPosterView` as the cell's lockup, **without a footer**, and our overlays
//  inside its `contentView` — the container the header says clients add their subviews to
//  ("Views added directly to the lockup view have undefined behaviors"). Everything in
//  there scales, lifts and tilts with the system's focus motion. A captioned cover's two
//  lines are `TVPageCaptionView`, a sibling under the lockup that follows the cover down
//  on focus: the system footer came out one line or two depending on a first layout we do
//  not control (see that file). The earlier cell (`TVUIKitPosterCell`) put its overlay
//  *beside* the lockup and mirrored the focus scale by hand; that is the pile of
//  constraints this replaces.
//
//  Still and person cells are the existing system-configuration cells
//  (`TVUIKitMediaItemCell`, `TVUIKitPersonCell`) — nothing new to draw. The wide card
//  is a `TVCardView` with a thumbnail and text in its `contentView`.
//

import KinoPubMedia
import TVUIKit
import UIKit

// MARK: - Poster lockup

@MainActor
final class TVPageLockupPosterCell: UICollectionViewCell {
  /// Air between the art and the caption. `TVLockupView.contentViewInsets` takes negative
  /// values for positive spacing; the probe in `TVPageCellMetrics` applies the same, so the
  /// envelope it measures includes this.
  nonisolated static let footerGap: CGFloat = 12

  /// Non-focusable lockup (`isUserInteractionEnabled = false` on the whole subtree).
  /// The **cell** is the focused leaf — same shape as Continue Watching /
  /// `TVPageWideCardCell` — so the collection's context-menu delegate sees Play-Pause.
  /// `canBecomeFocused = false` alone left focus on `_TVPosterContentView`
  /// (7a8bd62): lift looked right, PCM never opened. Internal for `TVPosterArtFocusTests`.
  let posterView = TVUIKitNonFocusablePosterView(image: nil)
  /// Two lines under a captioned cover; hidden for a cover without one.
  let captionView = TVPageCaptionView()
  private var lockupHeight: NSLayoutConstraint!
  private let watchedGlyph = UIImageView()
  /// The title's score, top-trailing, for rows that set `showsRating`.
  private let ratingChip = TVPageRatingChip()

  private var currentURL: URL?
  private var recipe: TVPageCellRecipe?
  private var caption: TVPageCaption = .never
  /// What the recipe was measured for — a cover or a square — so a resize can measure again.
  var kind: TVPageCellKind = .poster

  override init(frame: CGRect) {
    super.init(frame: frame)
    setUp()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var canBecomeFocused: Bool { true }

  private func setUp() {
    // The lockup's focus lift and shadow extend past the cell; the collection view is
    // unclipped for the same reason.
    clipsToBounds = false
    contentView.clipsToBounds = false

    posterView.translatesAutoresizingMaskIntoConstraints = false
    posterView.contentViewInsets = NSDirectionalEdgeInsets(top: 0, leading: 0, bottom: -Self.footerGap, trailing: 0)
    contentView.addSubview(posterView)
    contentView.addSubview(captionView)
    captionView.isHidden = true
    // The art follows this cell's focus and nothing else's — see `TVPosterArtFocus`.
    TVPosterArtFocus.bind(posterView.imageView, to: self)
    // The lockup is the item minus the caption: the whole item for a cover without one.
    lockupHeight = posterView.heightAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      posterView.topAnchor.constraint(equalTo: contentView.topAnchor),
      posterView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      posterView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      lockupHeight
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
    watchedGlyph.isUserInteractionEnabled = false
//    TVUIKitChromeSupport.applyLegibilityShadow(to: watchedGlyph.layer)
    watchedGlyph.isHidden = true
    host.addSubview(watchedGlyph)

    ratingChip.translatesAutoresizingMaskIntoConstraints = false
    ratingChip.isUserInteractionEnabled = false
    ratingChip.isHidden = true
    host.addSubview(ratingChip)

    NSLayoutConstraint.activate([
      watchedGlyph.leadingAnchor.constraint(equalTo: image.leadingAnchor, constant: 16),
      watchedGlyph.bottomAnchor.constraint(equalTo: image.bottomAnchor, constant: -14),
      ratingChip.topAnchor.constraint(equalTo: image.topAnchor, constant: 12),
      ratingChip.trailingAnchor.constraint(equalTo: image.trailingAnchor, constant: -12)
    ])
  }


  func configure(card: MediaCard, recipe: TVPageCellRecipe, caption: TVPageCaption,
                 showsRating: Bool = false, omittingGenreIDs: Set<String> = []) {
    place(recipe: recipe)
    applyCaption(caption, title: card.title,
                 detail: Self.posterSubtitle(for: card, caption: caption, omittingGenreIDs: omittingGenreIDs))

    let posterID = "kinopub.poster.\(card.id)"
    accessibilityIdentifier = posterID
    accessibilityLabel = card.title
    posterView.accessibilityIdentifier = posterID
    posterView.accessibilityLabel = card.title

    watchedGlyph.isHidden = !card.isWatched
    let rating = showsRating ? card.rating?.formatted : nil
    ratingChip.text = rating
    ratingChip.isHidden = rating == nil

    drawnTile = nil
    loadImage(URL(string: card.coverURL))
  }

  /// A drawn tile in the lockup: the tint and glyph are the artwork, the name is the
  /// caption like any poster's, with no detail line.
  func configure(tile: TVPageTile, recipe: TVPageCellRecipe, caption: TVPageCaption) {
    place(recipe: recipe)
    applyCaption(caption, title: tile.title, detail: nil)
    accessibilityIdentifier = "kinopub.tile.\(tile.id)"
    accessibilityLabel = tile.title
    posterView.accessibilityIdentifier = accessibilityIdentifier
    posterView.accessibilityLabel = tile.title
    watchedGlyph.isHidden = true
    ratingChip.isHidden = true
    currentURL = nil
    TVUIKitRemoteImage.cancel(into: posterView)
    drawnTile = tile
    drawTile(tile)
  }

  /// The tile this cell draws, to draw again at another size.
  private var drawnTile: TVPageTile?

  private func drawTile(_ tile: TVPageTile) {
    setImage(TVUIKitTileArtwork.image(tint: tile.resolvedTint,
                                      symbol: tile.symbol,
                                      size: recipe?.posterContentSize ?? CGSize(width: 260, height: 390),
                                      cornerRadius: Self.placeholderCornerRadius,
                                      style: tile.style,
                                      traits: traitCollection))
  }

  func configurePlaceholder(recipe: TVPageCellRecipe) {
    place(recipe: recipe)
    applyCaption(.never, title: nil, detail: nil)
    watchedGlyph.isHidden = true
    ratingChip.isHidden = true
    currentURL = nil
    drawnTile = nil
    TVUIKitRemoteImage.cancel(into: posterView)
    setImage(placeholder)
  }

  /// What a captioned cover says under its title: a followed series says how many of its
  /// episodes are still unwatched (the Library's *Following* — «2 серии»); everything else
  /// `Год Жанр` / `2019–2024 Жанр`, a concert's tour in place of the genre.
  /// `omittingGenreIDs` is the section's own genre. A title with neither says nothing —
  /// the line is still there, empty, so a grid never mixes one-line and two-line cells.
  /// Original title is reserved for search's wide cards (match highlighting).
  static func posterSubtitle(for card: MediaCard, caption: TVPageCaption,
                             omittingGenreIDs: Set<String> = []) -> String? {
    switch caption {
    case .never:
      return nil
    case .always, .onFocus:
      return EpisodesLeftText(card.unwatchedEpisodes)?.formatted()
        ?? card.catalogCaption(omittingGenreIDs: omittingGenreIDs)
    }
  }

  /// Accepted adapter (tvOS 27.2, measured 2026-09-21). Image assignment for
  /// `focusSizeIncrease` is deferred inside `TVUIKitDeferredPosterView` (and
  /// `setImage` for drawn tiles / placeholders that skip Nuke).
  private func setImage(_ image: UIImage) {
    TVUIKitRemoteImage.display(image, on: posterView)
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

  /// The layout gave this cell another size after it was configured: the page's width moved
  /// under visible cells — the Library's sidebar measures itself after the grid's first pass,
  /// and a grid of five columns becomes four. The lockup kept the old recipe, so its art was
  /// the old height in the new cell: taller than a narrower cell, over the caption (Sasha, on
  /// opening the Library, 2026-10-17), or short of a wider one. Measure for the new width.
  override func apply(_ layoutAttributes: UICollectionViewLayoutAttributes) {
    super.apply(layoutAttributes)
    guard let recipe, abs(layoutAttributes.size.width - recipe.itemSize.width) >= 1 else { return }
    place(recipe: TVPageCellMetrics.recipe(kind: kind, itemWidth: layoutAttributes.size.width, caption: caption))
    if isFocused { captionView.setFocusedLook(drop: focusDrop) }
    // The lockup takes its focus envelope from the image, so the image is the new size too.
    if let currentURL {
      loadImage(currentURL)
    } else if let drawnTile {
      drawTile(drawnTile)
    } else {
      setImage(placeholder)
    }
  }

  /// Sizes the lockup to the recipe: the item minus the caption's two lines.
  private func place(recipe: TVPageCellRecipe) {
    self.recipe = recipe
    posterView.contentSize = recipe.posterContentSize
    lockupHeight.constant = recipe.lockupHeight
    // Where the caption sits is the recipe's, not the cell's bounds: set here, at once, so it
    // never waits for a layout pass the cell might not get before it is on screen.
    // `bounds` + `center`, not `frame`: the caption carries a transform while focused.
    guard recipe.captionHeight > 0 else { return }
    let size = CGSize(width: recipe.artSize.width, height: recipe.captionHeight)
    captionView.bounds = CGRect(origin: .zero, size: size)
    captionView.center = CGPoint(
      x: recipe.artInsets.leading + size.width / 2,
      y: recipe.artInsets.top + recipe.artSize.height + Self.footerGap + size.height / 2)
  }

  /// The caption is ours — two lines in `TVPageCaptionView` — and the lockup never has a
  /// footer. `.onFocus` shows it only while the cover is focused.
  private func applyCaption(_ caption: TVPageCaption, title: String?, detail: String?) {
    self.caption = caption
    switch caption {
    case .never:
      captionView.isHidden = true
      captionView.configure(title: nil, detail: nil, category: TVPageCellMetrics.contentSizeCategory)
    case .always, .onFocus:
      captionView.configure(title: title, detail: detail, category: TVPageCellMetrics.contentSizeCategory)
      captionView.isHidden = false
      captionView.alpha = caption == .onFocus && !isFocused ? 0 : 1
      if isFocused {
        captionView.setFocusedLook(drop: focusDrop)
        captionView.startScrolling()
      }
    }
  }

  /// How far the cover's bottom edge moves out when it grows for focus: the caption follows.
  private var focusDrop: CGFloat {
    guard let recipe else { return 0 }
    return ((recipe.posterContentSize.height - recipe.artSize.height) / 2).rounded()
  }

  private func loadImage(_ url: URL?) {
    currentURL = url
    let decodeSize = recipe?.posterContentSize ?? CGSize(width: 260, height: 390)
    // Nuke's `TVPosterView` path — lockup owns aspect / focus scale. No extra
    // UIImageView crop/fill stack.
    _ = TVUIKitRemoteImage.load(into: posterView, url: url, size: decodeSize, placeholder: placeholder)
  }

  /// The caption's response to focus is ours: it follows the cover down by the focus room,
  /// its title turns primary, and under `.onFocus` it appears. The cover's own motion, lift
  /// and tilt stay the lockup's.
  override func didUpdateFocus(in context: UIFocusUpdateContext,
                               with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    let leafIsSelf = context.nextFocusedView === self
    let focused = leafIsSelf
      || context.nextFocusedView?.isDescendant(of: self) == true
    if focused {
      PosterContextMenuLog.log(
        "poster cell focus title=\(accessibilityLabel ?? "?") id=\(accessibilityIdentifier ?? "?") leafIsCell=\(leafIsSelf) posterUserInteraction=\(posterView.isUserInteractionEnabled) chain=\(PosterContextMenuLog.focusedChainDescription(startingFrom: context.nextFocusedView))"
      )
    }
    if !captionView.isHidden {
      captionView.setFocused(focused, drop: focusDrop, reveals: caption == .onFocus, in: coordinator)
    }
    coordinator.addCoordinatedAnimations(nil, completion: { [weak self] in
      guard let self, !focused else { return }
      self.resetStaleFocusAppearance()
    })
  }

  override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
    for press in presses {
      PosterContextMenuLog.log(
        "poster cell pressesBegan \(PosterContextMenuLog.pressTypeName(press.type)) id=\(accessibilityIdentifier ?? "?") isFocused=\(isFocused) leaf=\(PosterContextMenuLog.focusedChainDescription(startingFrom: PosterContextMenuLog.focusedView(in: self)))"
      )
    }
    super.pressesBegan(presses, with: event)
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
    captionView.resetToRest(reveals: caption == .onFocus)
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    TVUIKitRemoteImage.cancel(into: posterView)
    currentURL = nil
    posterView.image = nil
    caption = .never
    captionView.configure(title: nil, detail: nil, category: TVPageCellMetrics.contentSizeCategory)
    captionView.isHidden = true
    watchedGlyph.isHidden = true
    ratingChip.isHidden = true
    resetStaleFocusAppearance()
    accessibilityIdentifier = nil
    accessibilityLabel = nil
    posterView.accessibilityIdentifier = nil
    posterView.accessibilityLabel = nil
  }
}

// MARK: - Rating chip

/// The score in a poster's corner: a dark rounded plate with the number on it. Lives in
/// the lockup's `contentView`, so it rides the system focus motion with the art. No
/// shadow (tvOS cards and badges carry none); the plate is what keeps it legible on
/// light artwork.
@MainActor
final class TVPageRatingChip: UIView {
  private let label = UILabel()

  var text: String? {
    get { label.text }
    set { label.text = newValue }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = UIColor.black.withAlphaComponent(0.6)
    layer.cornerCurve = .continuous
    label.translatesAutoresizingMaskIntoConstraints = false
    label.font = UIFont.preferredFont(forTextStyle: .caption1)
    label.adjustsFontForContentSizeCategory = true
    label.textColor = .white
    addSubview(label)
    NSLayoutConstraint.activate([
      label.topAnchor.constraint(equalTo: topAnchor, constant: 4),
      label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
      label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
      label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    layer.cornerRadius = bounds.height / 2
  }
}

// MARK: - Chip

/// A system button that says when its menu opens and closes — the two
/// `UIContextMenuInteractionDelegate` calls `UIControl` already implements for the menu
/// it presents (tvOS 17).
@MainActor
final class TVPageMenuButton: UIButton {
  var onMenuWillShow: (() -> Void)?
  var onMenuDidEnd: (() -> Void)?

  override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                       willDisplayMenuFor configuration: UIContextMenuConfiguration,
                                       animator: (any UIContextMenuInteractionAnimating)?) {
    super.contextMenuInteraction(interaction, willDisplayMenuFor: configuration, animator: animator)
    onMenuWillShow?()
  }

  override func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                       willEndFor configuration: UIContextMenuConfiguration,
                                       animator: (any UIContextMenuInteractionAnimating)?) {
    super.contextMenuInteraction(interaction, willEndFor: configuration, animator: animator)
    onMenuDidEnd?()
  }
}

/// A pill of text. The cell is not focusable; the system button inside it is, which is
/// what gives the pill the stock tvOS button focus (lift, white fill) with no focus
/// code here. A chip with a `menu` is the system pull-down: `UIButton.menu` shown as
/// the primary action, the current pick checked — the same control a SwiftUI `Menu`
/// becomes on tvOS, with no menu chrome of ours.
///
/// A multi-select menu keeps a draft while it is open: a pick flips checkmarks in the
/// visible menu (`updateVisibleMenu`) and nothing else happens until it closes, when the
/// whole selection goes out once. Rebuilding the menu per pick reloaded the results
/// under it and sent a long list (countries) back to the top.
@MainActor
final class TVPageChipCell: UICollectionViewCell {
  private let button = TVPageMenuButton(configuration: .bordered())
  var onSelect: (() -> Void)?
  var onOption: ((String) -> Void)?
  var onSelection: ((Set<String>) -> Void)?

  private var chip: TVPageChip?
  private var menuOpen = false
  private var pending: TVPageChip?
  private var draft: Set<String> = []
  private var openedWith: Set<String> = []

  override init(frame: CGRect) {
    super.init(frame: frame)
    button.translatesAutoresizingMaskIntoConstraints = false
    button.addAction(UIAction { [weak self] _ in self?.onSelect?() }, for: .primaryActionTriggered)
    button.onMenuWillShow = { [weak self] in self?.menuWillShow() }
    button.onMenuDidEnd = { [weak self] in self?.menuDidEnd() }
    contentView.addSubview(button)
    NSLayoutConstraint.activate([
      button.topAnchor.constraint(equalTo: contentView.topAnchor),
      button.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      button.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      button.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
    ])
    registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (cell: TVPageChipCell, _) in
      guard let chip = cell.chip else { return }
      cell.button.configuration = Self.configuration(for: chip)
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(chip: TVPageChip) {
    // Never rebuild a menu that is on screen — the page may repaint under it (results
    // arriving); the newest chip is applied when it closes.
    guard !menuOpen else {
      pending = chip
      return
    }
    self.chip = chip
    button.configuration = Self.configuration(for: chip)
    button.isEnabled = chip.isEnabled
    button.accessibilityLabel = chip.showsTitle ? nil : chip.title
    if let menu = chip.menu {
      draft = menu.selectedIDs
      button.menu = Self.menu(for: menu) { [weak self] id in self?.picked(id) }
      button.showsMenuAsPrimaryAction = true
    } else {
      button.menu = nil
      button.showsMenuAsPrimaryAction = false
    }
    button.accessibilityIdentifier = "kinopub.chip.\(chip.id)"
  }

  private func picked(_ id: String) {
    guard let menu = chip?.menu else { return }
    guard menu.keepsPresented else {
      onOption?(id)
      return
    }
    draft = menu.toggling(id, in: draft)
    let selection = draft
    button.contextMenuInteraction?.updateVisibleMenu { visible in
      Self.applyingChecks(selection, to: visible)
    }
  }

  private func menuWillShow() {
    menuOpen = true
    openedWith = draft
  }

  private func menuDidEnd() {
    menuOpen = false
    if chip?.menu?.keepsPresented == true, draft != openedWith {
      onSelection?(draft)
    }
    if let pending {
      self.pending = nil
      configure(chip: pending)
    }
  }

  /// The visible menu with each action's checkmark set from `selection`, submenus
  /// included — actions carry their option id as `identifier`.
  private static func applyingChecks(_ selection: Set<String>, to menu: UIMenu) -> UIMenu {
    menu.replacingChildren(menu.children.map { element in
      if let action = element as? UIAction {
        action.state = selection.contains(action.identifier.rawValue) ? .on : .off
        return action
      }
      if let submenu = element as? UIMenu {
        return applyingChecks(selection, to: submenu)
      }
      return element
    })
  }

  override var canBecomeFocused: Bool { false }

  /// System tvOS buttons. `.gray()` is white on white in light mode on a real Apple TV.
  /// An active filter is the filled one (`.borderedProminent`); the rest are
  /// `.bordered`. Focus, fill and padding stay the system's — including in light mode.
  /// The title is `.body`, so the button's own height follows Dynamic Type. No fixed
  /// insets and no fixed symbol point size: both would pin the row.
  static func configuration(for chip: TVPageChip) -> UIButton.Configuration {
    var configuration = chip.isActive
      ? UIButton.Configuration.borderedProminent()
      : UIButton.Configuration.bordered()
    configuration.cornerStyle = .capsule
    // One line: the row measures each pill at its full title (`fittingWidth`).
    configuration.titleLineBreakMode = .byTruncatingTail
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var outgoing = incoming
      outgoing.font = UIFont.preferredFont(forTextStyle: .body)
      return outgoing
    }
    let symbol = UIImage.SymbolConfiguration(textStyle: .body)
    if chip.showsTitle {
      configuration.title = chip.title
      if let systemImage = chip.systemImage {
        configuration.image = UIImage(systemName: systemImage)
        configuration.imagePlacement = .leading
        configuration.preferredSymbolConfigurationForImage = symbol
      } else if chip.menu != nil {
        configuration.image = UIImage(systemName: "chevron.down")
        configuration.imagePlacement = .trailing
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .caption1, scale: .small)
      }
    } else {
      configuration.image = chip.systemImage.flatMap { UIImage(systemName: $0) }
      configuration.preferredSymbolConfigurationForImage = symbol
    }
    return configuration
  }

  /// The system menu for a chip's `Menu`: options become `UIAction`s (checked ones
  /// `.on`), sections inline `UIMenu`s, submenus nested `UIMenu`s with a subtitle.
  static func menu(for menu: TVPageChip.Menu, onOption: @escaping (String) -> Void) -> UIMenu {
    func element(_ node: TVPageChip.MenuNode) -> UIMenuElement {
      switch node {
      case let .option(option, isSelected):
        var attributes: UIMenuElement.Attributes = []
        if !option.isEnabled { attributes.insert(.disabled) }
        if option.isDestructive { attributes.insert(.destructive) }
        if menu.keepsPresented { attributes.insert(.keepsMenuPresented) }
        return UIAction(title: option.title, image: option.systemImage.flatMap { UIImage(systemName: $0) },
                        identifier: UIAction.Identifier(option.id),
                        attributes: attributes,
                        state: isSelected ? .on : .off) { _ in onOption(option.id) }
      case let .section(title, children):
        return UIMenu(title: title ?? "", options: .displayInline, children: children.map(element))
      case let .submenu(title, subtitle, children):
        let submenu = UIMenu(title: title, children: children.map(element))
        submenu.subtitle = subtitle
        return submenu
      }
    }
    return UIMenu(children: menu.nodes.map(element))
  }

  /// What the pill's width depends on — not its menu (a genre menu is 115 options).
  private struct WidthKey: Hashable {
    let title: String
    let systemImage: String?
    let isActive: Bool
    let hasMenu: Bool
    let showsTitle: Bool
    let category: UIContentSizeCategory
  }

  private static var widthCache: [WidthKey: CGFloat] = [:]
  private static var heightByCategory: [UIContentSizeCategory: CGFloat] = [:]
  private static let prototype = UIButton(configuration: .bordered())

  /// The row's height: a system button with a `.body` title at the current content
  /// size. Prominent and bordered can differ by a point; the row takes the taller.
  static var rowHeight: CGFloat {
    let category = TVPageCellMetrics.contentSizeCategory
    if let cached = heightByCategory[category] { return cached }
    let plain = measuredSize(for: TVPageChip(id: "row", title: "Ag")).height
    let active = measuredSize(for: TVPageChip(id: "row", title: "Ag", isActive: true)).height
    let height = ceil(max(plain, active))
    heightByCategory[category] = height
    return height
  }

  /// The pill's own width, measured on a prototype system button with the same
  /// configuration — what a filter row needs to push its trailing pills to the edge
  /// exactly (a flexible edge over estimated widths lands short). An icon-only pill
  /// is a circle: as wide as the row is tall.
  static func fittingWidth(for chip: TVPageChip) -> CGFloat {
    if !chip.showsTitle { return rowHeight }
    let category = TVPageCellMetrics.contentSizeCategory
    let key = WidthKey(title: chip.title, systemImage: chip.systemImage, isActive: chip.isActive,
                       hasMenu: chip.menu != nil, showsTitle: chip.showsTitle, category: category)
    if let cached = widthCache[key] { return cached }
    let width = ceil(measuredSize(for: chip).width)
    widthCache[key] = width
    return width
  }

  private static func measuredSize(for chip: TVPageChip) -> CGSize {
    prototype.traitOverrides.preferredContentSizeCategory = TVPageCellMetrics.contentSizeCategory
    prototype.configuration = configuration(for: chip)
    return prototype.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    onSelect = nil
    onOption = nil
    onSelection = nil
    pending = nil
  }
}

// MARK: - Wide card

/// What search's wide cards and the detail page's info cards both wear on the system's
/// platter: a quiet tint at rest on the card view's floating content view (so it moves
/// with it), and nothing under focus, so the system's white shows through.
enum TVPagePlatter {
  static let restingFill = UIColor.label.withAlphaComponent(0.1) // REPLACE WITH SYSTEM BACKGROUND COLORS
  static let cornerRadius: CGFloat = 12
}

/// A `TVCardView` — the system's floating platter, the UIKit side of SwiftUI's `.card`
/// button style — holding a thumbnail and up to three lines of text. The platter, its
/// focus lift, tilt and white fill are the card view's; the cell fills the
/// `contentView`, the container `TVLockupView` says subviews belong in.
///
/// A title's poster fills the platter's leading edge top to bottom; a person gets a
/// circle — their photo, or initials on a quiet disc — inset by the padding. Text: title in `.body` (two lines), then in
/// `.caption2` the original title when that is what matched, and year · genres.
@MainActor
final class TVPageWideCardCell: UICollectionViewCell {
  private let cardView = TVCardView()
  private let thumbnail = UIImageView()
  /// A person's photo or initials in a circle — a still image, like the poster
  /// thumbnail. Not a monogram content view: that lockup is focusable and lifts
  /// itself, layer by layer, inside the focused card, and it kept stale initials
  /// across reuse ("KT" on Stephen Robert Morse, 2026-09-26).
  private let avatar = UIImageView()
  private let titleLabel = UILabel()
  private let originalLabel = UILabel()
  private let detailLabel = UILabel()
  private let text = UIStackView()
  private var textLeading: NSLayoutConstraint!

  private var imageTask: Task<Void, Never>?
  private var currentURL: URL?

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
    host.backgroundColor = TVPagePlatter.restingFill
    host.layer.cornerRadius = TVPagePlatter.cornerRadius
    host.layer.cornerCurve = .continuous
    host.clipsToBounds = true

    thumbnail.translatesAutoresizingMaskIntoConstraints = false
    thumbnail.contentMode = .scaleAspectFill
    thumbnail.clipsToBounds = true
    host.addSubview(thumbnail)

    avatar.translatesAutoresizingMaskIntoConstraints = false
    avatar.contentMode = .scaleAspectFill
    avatar.clipsToBounds = true
    avatar.layer.cornerRadius = Self.avatarDiameter / 2
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
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: TVPageWideCardCell, _) in
      cell.redrawMonogramIfNeeded()
    }
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

  /// The name behind a monogram on screen (no photo): redrawn in the platter's colours.
  private var monogramName: String?
  private var isFocusedLook = false

  private func applyFocusColors(_ focused: Bool) {
    isFocusedLook = focused
    if let monogramName {
      // Light ink on the white focused platter, like the text beside it.
      let traits = focused ? UITraitCollection(userInterfaceStyle: .light) : traitCollection
      avatar.image = TVUIKitTileArtwork.monogram(name: monogramName, diameter: Self.avatarDiameter, traits: traits)
    }
    cardView.contentView.backgroundColor = focused ? .clear : TVPagePlatter.restingFill
    titleLabel.textColor = focused ? .black : .label
    let secondary = focused ? UIColor.black.withAlphaComponent(0.6) : .secondaryLabel
    originalLabel.textColor = secondary
    detailLabel.textColor = secondary
  }

  private func redrawMonogramIfNeeded() {
    applyFocusColors(isFocusedLook)
  }

  /// The card view sizes its platter from `contentSize` (a system default otherwise,
  /// ~500 wide whatever the frame). `TVPageCellMetrics` measured which content size
  /// puts the resting platter on the HIG column; the cell's frame is the envelope.
  func apply(recipe: TVPageCellRecipe) {
    if cardView.contentSize != recipe.posterContentSize {
      cardView.contentSize = recipe.posterContentSize
    }
  }

  func configure(card: MediaCard, match: String?, omittingGenreIDs: Set<String> = []) {
    monogramName = nil
    thumbnail.isHidden = false
    avatar.isHidden = true
    textLeading.constant = Self.thumbnailSize.width + Self.textGap
    titleLabel.text = card.title
    let original = Self.matchedOriginal(card, match: match)
    originalLabel.text = original
    originalLabel.isHidden = original == nil
    detailLabel.text = Self.detail(for: card, omittingGenreIDs: omittingGenreIDs)
    detailLabel.isHidden = detailLabel.text == nil
    // The card is what takes focus (and what XCUI reports); the cell id alone is empty there.
    let cardID = "kinopub.card.\(card.id)"
    accessibilityIdentifier = cardID
    cardView.accessibilityIdentifier = cardID
    let label = [card.title, original, detailLabel.text].compactMap { $0 }.joined(separator: ", ")
    accessibilityLabel = label
    cardView.accessibilityLabel = label
    loadThumbnail(URL(string: card.coverURL))
  }

  func configure(person: TVUIKitPerson) {
    thumbnail.isHidden = true
    avatar.isHidden = false
    textLeading.constant = TVPageLayout.cardPadding * 1.5 + Self.avatarDiameter + Self.textGap
    loadAvatar(name: person.name, url: person.photoURL)
    titleLabel.text = person.name
    originalLabel.text = nil
    originalLabel.isHidden = true
    detailLabel.text = person.caption
    detailLabel.isHidden = person.caption == nil
    let personID = "kinopub.card.person.\(person.id)"
    accessibilityIdentifier = personID
    cardView.accessibilityIdentifier = personID
    let label = [person.name, person.caption].compactMap { $0 }.joined(separator: ", ")
    accessibilityLabel = label
    cardView.accessibilityLabel = label
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

  /// "2021  Боевик" / "2019–2024  Драма" — year then genre, same words as a
  /// catalog cover (`catalogCaption`). No running time: in a result list those two
  /// are what tell two same-named titles apart. A collection has neither, so its
  /// counters (items, views) take the line instead.
  private static func detail(for card: MediaCard, omittingGenreIDs: Set<String> = []) -> String? {
    if let caption = card.catalogCaption(omittingGenreIDs: omittingGenreIDs) { return caption }
    let stats = card.captionStats.map(\.value).filter { !$0.isEmpty }
    return stats.isEmpty ? nil : stats.joined(separator: "\u{2003}")
  }

  private var placeholder: UIImage {
    TVUIKitTileArtwork.placeholder(size: Self.thumbnailSize, cornerRadius: 0, traits: traitCollection)
  }

  private func loadAvatar(name: String, url: URL?) {
    imageTask?.cancel()
    imageTask = nil
    currentURL = url
    let diameter = Self.avatarDiameter
    avatar.layer.cornerRadius = diameter / 2
    let traits = isFocusedLook ? UITraitCollection(userInterfaceStyle: .light) : traitCollection
    let monogram = TVUIKitTileArtwork.monogram(name: name, diameter: diameter, traits: traits)
    let size = CGSize(width: diameter, height: diameter)
    if let url, let hit = TVUIKitRemoteImage.cached(url: url, size: size) {
      monogramName = nil
      avatar.image = hit
      return
    }
    monogramName = name
    avatar.image = monogram
    guard let url else { return }
    imageTask = Task { [weak self] in
      let image = await TVUIKitRemoteImage.load(url: url, size: size)
      guard let self, !Task.isCancelled, self.currentURL == url, let image else { return }
      self.monogramName = nil
      self.avatar.image = image
    }
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
    avatar.image = nil
    monogramName = nil
    titleLabel.text = nil
    originalLabel.text = nil
    detailLabel.text = nil
    accessibilityIdentifier = nil
    cardView.accessibilityIdentifier = nil
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
/// Trailing actions are the same system pills Search uses (`TVPageChip`), at the
/// filter row's own size (`chipHeight` × `fittingWidth`) — not a scaled-down copy.
@MainActor
final class TVPageHeaderView: UICollectionReusableView {
  private let titleLabel = UILabel()
  private let countLabel = UILabel()
  private let actionsStack = UIStackView()
  private var actionCells: [TVPageChipCell] = []
  private var actionWidth: [NSLayoutConstraint] = []
  private var actionHeight: [NSLayoutConstraint] = []
  private var chips: [TVPageChip] = []
  var onChipOption: ((String, String) -> Void)?
  var onChipSelection: ((String, Set<String>) -> Void)?

  override init(frame: CGRect) {
    super.init(frame: frame)
    // `TypeScale.rowHeader` in UIKit terms: headline **semibold**, secondary. The
    // bare headline text style on tvOS renders regular, which is not the shelf title.
    titleLabel.font = Self.font(.headline, weight: .semibold)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.textColor = .secondaryLabel
    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    titleLabel.lineBreakMode = .byTruncatingTail
    countLabel.font = Self.font(.subheadline, weight: .medium)
    countLabel.adjustsFontForContentSizeCategory = true
    countLabel.textColor = .tertiaryLabel
    countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

    let titles = UIStackView(arrangedSubviews: [titleLabel, countLabel])
    titles.axis = .horizontal
    titles.alignment = .firstBaseline
    titles.spacing = 12
    titles.setContentHuggingPriority(.defaultLow, for: .horizontal)

    actionsStack.axis = .horizontal
    actionsStack.alignment = .center
    actionsStack.spacing = 12
    actionsStack.setContentHuggingPriority(.required, for: .horizontal)

    let stack = UIStackView(arrangedSubviews: [titles, actionsStack])
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 24
    stack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(stack)
    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: trailingAnchor),
      stack.topAnchor.constraint(equalTo: topAnchor),
      stack.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
    registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: TVPageHeaderView, _) in
      for (cell, chip) in zip(view.actionCells, view.chips) {
        cell.configure(chip: chip)
      }
      view.applyActionSizes()
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// A Dynamic Type text style with a weight — the style's descriptor plus the trait,
  /// so it keeps tracking the content size category.
  private static func font(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
    let descriptor = UIFont.preferredFont(forTextStyle: style).fontDescriptor
      .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
    return UIFont(descriptor: descriptor, size: 0)
  }

  /// The row title's face, for whatever else has to draw one in the same type — the
  /// titles over a strip's groups.
  static var titleFont: UIFont { font(.headline, weight: .semibold) }

  func configure(title: String, count: String?, actions: [TVPageChip] = []) {
    titleLabel.text = title
    countLabel.text = count
    countLabel.isHidden = count == nil
    accessibilityLabel = count.map { "\(title), \($0)" } ?? title
    rebuildActions(actions)
  }

  /// The Search filter pill's size: same cell, same measured width, same height.
  static func actionSize(for chip: TVPageChip) -> CGSize {
    CGSize(width: max(TVPageChipCell.fittingWidth(for: chip), TVPageLayout.chipHeight),
           height: TVPageLayout.chipHeight)
  }

  private func rebuildActions(_ actions: [TVPageChip]) {
    // Same pills, maybe a different `isActive` (Following's Unwatched/All): keep the
    // cells so Select on a segment does not rebuild the header and drop focus.
    if chips.map(\.id) == actions.map(\.id), actionCells.count == actions.count {
      chips = actions
      zip(actionCells, actions).forEach { $0.configure(chip: $1) }
      applyActionSizes()
      return
    }
    chips = actions
    actionCells.forEach { $0.removeFromSuperview() }
    actionCells.removeAll()
    actionWidth.removeAll()
    actionHeight.removeAll()
    actionsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
    for chip in actions {
      let cell = TVPageChipCell(frame: .zero)
      cell.translatesAutoresizingMaskIntoConstraints = false
      cell.configure(chip: chip)
      cell.onOption = { [weak self] option in self?.onChipOption?(chip.id, option) }
      cell.onSelection = { [weak self] selection in self?.onChipSelection?(chip.id, selection) }
      cell.onSelect = { [weak self] in self?.onChipOption?(chip.id, chip.id) }
      cell.setContentCompressionResistancePriority(.required, for: .horizontal)
      let size = Self.actionSize(for: chip)
      let width = cell.widthAnchor.constraint(equalToConstant: size.width)
      let height = cell.heightAnchor.constraint(equalToConstant: size.height)
      NSLayoutConstraint.activate([width, height])
      actionsStack.addArrangedSubview(cell)
      actionCells.append(cell)
      actionWidth.append(width)
      actionHeight.append(height)
    }
  }

  /// Header pills keep the measured system-button size. A content-size change does not
  /// rebuild the cells (that would drop focus), so the constants move with the font.
  private func applyActionSizes() {
    for (index, chip) in chips.enumerated() where actionWidth.indices.contains(index) {
      let size = Self.actionSize(for: chip)
      actionWidth[index].constant = size.width
      actionHeight[index].constant = size.height
    }
  }
}
#endif
