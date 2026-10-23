#if os(tvOS)
//
//  TVPageHero.swift
//  KinoPubUI
//
//  The Home hero: one full-screen title at a time, Apple TV style. Three parts:
//
//  - `TVPageHeroCarousel` — which title is fronted, and the stage the page is in.
//    Owned by the page controller, so it outlives the cell (a cell scrolled away
//    and dequeued again comes back on the same title).
//  - `TVPageHeroBackdropView` — the picture, behind the whole collection, pinned to
//    the screen. It does not scroll: the words scroll with the page and the picture
//    stays, so going down to the rows is a parallax the focus engine drives.
//  - `TVPageHeroCell` — the words and the buttons, low on the left; the paging dots
//    under them. The cell itself never takes focus, its buttons do.
//
//  The look and the motion follow Plozz's Home hero (github.com/thatcube/Plozz,
//  FeatureHome/HomeHeroView, HeroCarouselFocus, HomeHeroBackdrop — GPL-3, Brandon
//  Moore), rebuilt on system parts: `UIPageControl` with `UIPageControlTimerProgress`
//  for the dots and the auto-advance, glass `UIButton.Configuration`s for the
//  buttons, `UIFocusSystem.movementDidFailNotification` for paging on Left / Right
//  at the row's ends.
//
//  Fixed states only. The picture has three (`Stage`): the hero has focus; the row
//  under it has focus (the picture glides up and dims); focus is further down (the
//  picture is gone). No scroll-driven choreography.
//

import TVUIKit
import UIKit

// MARK: - Model

@MainActor
final class TVPageHeroCarousel {
  enum Stage: Equatable {
    /// Focus is on the hero, or outside the page (the tab bar).
    case hero
    /// Focus is on the row right under the hero.
    case receded
    /// Focus is further down the page.
    case away
  }

  /// How long one title stays before the next.
  static let dwell: TimeInterval = 8

  private(set) var hero: TVPageHero?
  private(set) var index = 0
  private(set) var stage: Stage = .hero
  /// The page is on screen — not under a pushed page, another tab or the player.
  var isPageVisible = false {
    didSet {
      guard isPageVisible != oldValue else { return }
      // Back on screen, the title on it gets its whole dwell again.
      if isPageVisible { cell?.restartDwell() }
      cell?.updateTimer()
    }
  }

  weak var backdrop: TVPageHeroBackdropView?
  weak var cell: TVPageHeroCell? {
    didSet {
      cell?.render(direction: 0)
      cell?.apply(stage: stage, animated: false)
    }
  }

  var features: [TVPageFeature] { hero?.features ?? [] }

  var current: TVPageFeature? {
    features.indices.contains(index) ? features[index] : nil
  }

  var next: TVPageFeature? {
    guard features.count > 1 else { return nil }
    return features[(index + 1) % features.count]
  }

  /// Auto-advance runs only while someone is looking at the hero.
  var advances: Bool { isPageVisible && stage == .hero && features.count > 1 }

  /// New titles, or new facts about them (details, a logo, a backdrop). The title on
  /// screen stays on screen when it is still in the list.
  func update(_ hero: TVPageHero?) {
    let shownID = current?.card.id
    guard hero != self.hero else { return }
    self.hero = hero
    if let shownID, let kept = features.firstIndex(where: { $0.card.id == shownID }) {
      index = kept
    } else {
      index = 0
    }
    TVUIKitRemoteImage.prefetch(features.map { $0.backdropCandidates.first })
    backdrop?.show(current, direction: 0, next: next)
    cell?.render(direction: 0)
  }

  /// One title over: +1 forward, -1 back. Both wrap.
  func step(_ delta: Int) {
    guard features.count > 1 else { return }
    move(to: (index + delta + features.count) % features.count, direction: delta)
  }

  /// `direction` is where the new title comes from: +1 from the trailing edge.
  func move(to newIndex: Int, direction: Int) {
    guard features.indices.contains(newIndex), newIndex != index else { return }
    index = newIndex
    // The words turn with the picture, not before it: the backdrop says when its
    // page turn starts (at once when the picture is cached).
    guard let backdrop else {
      cell?.render(direction: direction)
      return
    }
    let turned = index
    backdrop.show(current, direction: direction, next: next) { [weak self] in
      guard let self, self.index == turned else { return }
      self.cell?.render(direction: direction)
    }
  }

  func setStage(_ newStage: Stage) {
    guard newStage != stage else { return }
    stage = newStage
    backdrop?.apply(stage: newStage, animated: true)
    cell?.apply(stage: newStage, animated: true)
    cell?.updateTimer()
  }
}

// MARK: - Backdrop

/// The fronted title's picture over the whole screen, with the legibility shading the
/// detail hero and the old banner use (`HeroLegibilityTexture`), fading out at the
/// bottom into whatever is behind the page.
@MainActor
final class TVPageHeroBackdropView: UIView {
  /// Everything that moves and fades together on a stage change.
  private let stageView = UIView()
  private var front = UIImageView()
  private var back = UIImageView()
  private let texture = UIImageView()
  private let dim = UIView()
  private let fade = CAGradientLayer()

  private var shownID: Int?
  private var pending: (feature: TVPageFeature?, direction: Int, next: TVPageFeature?, turned: (() -> Void)?)?
  /// Called when the fronted title's picture starts to show — or right away when it
  /// cannot (no picture, or it is slow: `turnPatience`).
  private var turned: (() -> Void)?
  private static let turnPatience: TimeInterval = 0.8
  private var loadTask: Task<Void, Never>?
  private var transitionID = 0
  private var stage: TVPageHeroCarousel.Stage = .hero

  /// How far the picture glides up when the row under the hero takes focus, as a share
  /// of the screen's height. Below what the focus engine scrolls the page by, so the
  /// picture lags the words: the parallax.
  private static let recedeRise: CGFloat = 0.22
  /// Black over the picture while the row under it has focus.
  private static let recededDim: CGFloat = 0.35
  /// Where the picture starts to fade out, and where it is gone, as shares of its height.
  /// Late and short: the words, the dots and the row under the hero stand on the shaded
  /// picture. A long fade showed a light band behind the dots in light appearance,
  /// where the page behind is light (2026-10-22).
  private static let fadeStart: CGFloat = 0.92
  private static let fadeEnd: CGFloat = 1

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    clipsToBounds = true
    backgroundColor = .clear
    overrideUserInterfaceStyle = .dark
    accessibilityElementsHidden = true

    addSubview(stageView)
    for view in [back, front] {
      view.contentMode = .scaleAspectFill
      view.clipsToBounds = true
      stageView.addSubview(view)
    }
    texture.contentMode = .scaleToFill
    texture.image = HeroLegibilityTexture.templateUIImage()
    texture.tintColor = .black
    stageView.addSubview(texture)
    dim.backgroundColor = .black
    dim.alpha = 0
    stageView.addSubview(dim)

    fade.colors = [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
    fade.locations = [0, NSNumber(value: Double(Self.fadeStart)), NSNumber(value: Double(Self.fadeEnd))]
    stageView.layer.mask = fade
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard bounds.width > 0, bounds.height > 0 else { return }
    let transform = stageView.transform
    stageView.transform = .identity
    stageView.frame = bounds
    stageView.transform = transform
    for view in [back, front, texture, dim] where view.layer.animationKeys()?.isEmpty ?? true {
      let viewTransform = view.transform
      view.transform = .identity
      view.frame = stageView.bounds
      view.transform = viewTransform
    }
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    fade.frame = stageView.bounds
    CATransaction.commit()
    if stage != .hero { apply(stage: stage, animated: false) }
    if let pending {
      self.pending = nil
      show(pending.feature, direction: pending.direction, next: pending.next, turned: pending.turned)
    }
  }

  /// Front `feature`. The same title again only fills in a picture that has not
  /// loaded yet; another title slides in from `direction` (0 dissolves).
  func show(_ feature: TVPageFeature?, direction: Int, next: TVPageFeature?,
            turned: (() -> Void)? = nil) {
    fireTurned()
    guard bounds.width > 0, bounds.height > 0 else {
      pending = (feature, direction, next, turned)
      return
    }
    self.turned = turned
    guard let feature, feature.card.id > 0 else {
      shownID = nil
      loadTask?.cancel()
      finishTransition()
      front.image = nil
      fireTurned()
      return
    }
    let sameTitle = feature.card.id == shownID
    if sameTitle, front.image != nil {
      fireTurned()
      return
    }
    if turned != nil {
      DispatchQueue.main.asyncAfter(deadline: .now() + Self.turnPatience) { [weak self] in
        guard let self, self.shownID == feature.card.id else { return }
        self.fireTurned()
      }
    }
    shownID = feature.card.id
    loadTask?.cancel()
    let size = bounds.size
    let urls = feature.backdropCandidates
    if let next {
      TVUIKitRemoteImage.prefetch([next.backdropCandidates.first])
    }
    for url in urls {
      if let hit = TVUIKitRemoteImage.cached(url: url, size: size) {
        present(hit, direction: sameTitle ? 0 : direction)
        return
      }
    }
    // Nothing cached: the old picture stays until the new one is in, so a page turn
    // never flashes the empty page.
    let id = feature.card.id
    loadTask = Task { [weak self] in
      for (index, url) in urls.enumerated() {
        let loaded = await TVUIKitRemoteImage.loadWithSource(url: url, size: size)
        guard let self, !Task.isCancelled, self.shownID == id else { return }
        if let loaded {
          ArtworkLog.source("hero.backdrop", id: feature.card.itemID, asked: url,
                            answered: loaded.answered, tier: loaded.tier,
                            candidate: index, of: urls.count)
          self.present(loaded.image, direction: direction)
          return
        }
      }
      guard let self, !Task.isCancelled, self.shownID == id else { return }
      ArtworkLog.exhausted("hero.backdrop", id: feature.card.itemID, tried: urls)
      // Never the portrait poster (cropped it is the wrong picture): an empty
      // backdrop under the shading reads better than a wrong one.
      self.present(nil, direction: 0)
    }
  }

  private func fireTurned() {
    let call = turned
    turned = nil
    call?()
  }

  private func present(_ image: UIImage?, direction: Int) {
    finishTransition()
    defer { fireTurned() }
    guard front.image != nil, image != nil, direction != 0,
          !UIAccessibility.isReduceMotionEnabled else {
      UIView.transition(with: front, duration: 0.45, options: [.transitionCrossDissolve, .allowUserInteraction]) {
        self.front.image = image
      }
      return
    }
    // The Apple TV move: the new picture is wiped in from the side it comes from,
    // drifting in a little, while the old one drifts the other way under it.
    transitionID += 1
    let id = transitionID
    let width = stageView.bounds.width
    let drift = width * 0.08 * CGFloat(direction)
    let incoming = back
    incoming.image = image
    incoming.frame = stageView.bounds
    incoming.transform = CGAffineTransform(translationX: drift, y: 0)
    // A soft edge, not a seam: the mask is opaque with a feathered leading side, and
    // it starts wholly outside the picture on the side the title comes from.
    let height = stageView.bounds.height
    let feather = (width * 0.25).rounded()
    let wipe = TVPageHeroWipeMask(feather: feather, fromTrailing: direction > 0)
    wipe.frame = direction > 0
      ? CGRect(x: width, y: 0, width: width + feather, height: height)
      : CGRect(x: -width - feather, y: 0, width: width + feather, height: height)
    incoming.mask = wipe
    stageView.insertSubview(incoming, aboveSubview: front)
    UIView.animate(withDuration: 0.9, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
      wipe.frame.origin.x = direction > 0 ? -feather : 0
      incoming.transform = .identity
      self.front.transform = CGAffineTransform(translationX: -drift, y: 0)
    } completion: { [weak self] _ in
      guard let self, self.transitionID == id else { return }
      self.settle()
    }
  }

  /// The incoming picture becomes the front one.
  private func settle() {
    let incoming = back
    back = front
    front = incoming
    front.mask = nil
    front.transform = .identity
    back.transform = .identity
    back.image = nil
    stageView.insertSubview(back, belowSubview: front)
  }

  /// A page turn while the last one is still moving: jump it to its end.
  private func finishTransition() {
    guard back.mask != nil else { return }
    transitionID += 1
    [back, front, back.mask].compactMap { $0 }.forEach { $0.layer.removeAllAnimations() }
    settle()
  }

  func apply(stage: TVPageHeroCarousel.Stage, animated: Bool) {
    self.stage = stage
    let height = bounds.height
    let changes = {
      switch stage {
      case .hero:
        self.stageView.transform = .identity
        self.stageView.alpha = 1
        self.dim.alpha = 0
      case .receded:
        self.stageView.transform = CGAffineTransform(translationX: 0, y: -height * Self.recedeRise)
        self.stageView.alpha = 1
        self.dim.alpha = Self.recededDim
      case .away:
        self.stageView.transform = CGAffineTransform(translationX: 0, y: -height * Self.recedeRise)
        self.stageView.alpha = 0
        self.dim.alpha = Self.recededDim
      }
    }
    guard animated, !UIAccessibility.isReduceMotionEnabled else {
      changes()
      return
    }
    // Slower than the focus scroll on purpose — the picture lags the words.
    UIView.animate(withDuration: 0.9, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0,
                   options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
  }
}

// MARK: - Cell

/// The hero's words and buttons. Bottom-anchored on the page's side inset: title logo
/// (or the name), the meta line, the plot's first sentence, then Play, Bookmark,
/// Details and Next; the paging dots centred under them.
@MainActor
final class TVPageHeroCell: UICollectionViewCell {
  var onPlay: ((TVPageFeature) -> Void)?
  var onDetails: ((TVPageFeature) -> Void)?
  /// The bookmark folders menu for a title, built when the button is pressed.
  var bookmarkMenu: ((TVPageFeature) -> [UIMenuElement])?

  private weak var carousel: TVPageHeroCarousel?
  private var sideInset: CGFloat = TVHIGGrid.sideInset

  private let words = UIStackView()
  private let mark = UIView()
  private let logo = UIImageView()
  private let titleLabel = UILabel()
  private let meta = UIStackView()
  private let overview = UILabel()
  private let buttons = UIStackView()
  private let playButton = UIButton(type: .system)
  private let bookmarkButton = UIButton(type: .system)
  private let detailsButton = UIButton(type: .system)
  private let nextButton = UIButton(type: .system)
  private let pageControl = UIPageControl()
  /// The hero as one focus section, Plozz's single focus target for the row: focus
  /// coming in from anywhere outside (Down from the tab bar, Up from any card of the
  /// row under it, however far that row is scrolled) lands on the button it last left,
  /// Next at first — not on whichever button happens to sit nearest. Off while a button
  /// has focus, so Left / Right move between the buttons.
  private let entryGuide = UIFocusGuide()
  private weak var lastButton: UIButton?
  private let timer = UIPageControlTimerProgress(preferredDuration: TVPageHeroCarousel.dwell)

  private var leading: NSLayoutConstraint!
  private var wordsWidth: NSLayoutConstraint!
  private var logoWidth: NSLayoutConstraint!
  private var logoHeight: NSLayoutConstraint!
  private var markHeight: NSLayoutConstraint!

  private let logoSession = TitleLogoSession()
  private var renderedID: Int?
  private var focusFailObserver: NSObjectProtocol?

  private static let metaChrome: TVPageBannerChrome = {
    var chrome = TVPageBannerChrome.current
    chrome.textStyle = .caption1
    // Over a bright picture `.secondaryLabel` went grey on white; the shadow under the
    // line carries it, as it does the plot.
    chrome.textColor = UIColor(white: 1, alpha: 0.88)
    chrome.vibranceEnabled = false
    return chrome
  }()

  override init(frame: CGRect) {
    super.init(frame: frame)
    overrideUserInterfaceStyle = .dark
    clipsToBounds = false
    contentView.clipsToBounds = false
    accessibilityIdentifier = "kinopub.hero"

    titleLabel.font = Self.weightedFont(.title2, .bold)
    titleLabel.textColor = .white
    titleLabel.numberOfLines = 2
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.isHidden = true
    titleLabel.accessibilityIdentifier = "kinopub.heroTitle"

    logo.contentMode = .scaleAspectFit
    logo.translatesAutoresizingMaskIntoConstraints = false
    logo.isHidden = true
    logoSession.onChange = { [weak self] in self?.paintLogo() }

    mark.translatesAutoresizingMaskIntoConstraints = false
    mark.addSubview(logo)
    mark.addSubview(titleLabel)

    meta.axis = .horizontal
    meta.alignment = .center
    meta.spacing = MediaScoresView.groupSpacing

    overview.font = UIFont.preferredFont(forTextStyle: .caption1)
    overview.adjustsFontForContentSizeCategory = true
    overview.textColor = UIColor(white: 1, alpha: 0.72)
    overview.numberOfLines = 2
    overview.lineBreakMode = .byTruncatingTail

    for label in [titleLabel, overview, meta] as [UIView] {
      label.layer.shadowColor = UIColor.black.cgColor
      label.layer.shadowOpacity = 0.32
      label.layer.shadowRadius = 7
      label.layer.shadowOffset = CGSize(width: 0, height: 2)
    }
    logo.layer.shadowColor = UIColor.black.cgColor
    logo.layer.shadowOpacity = 0.45
    logo.layer.shadowRadius = 14
    logo.layer.shadowOffset = CGSize(width: 0, height: 2)

    words.axis = .vertical
    words.alignment = .leading
    words.spacing = 14
    words.translatesAutoresizingMaskIntoConstraints = false
    words.addArrangedSubview(mark)
    words.setCustomSpacing(24, after: mark)
    words.addArrangedSubview(meta)
    words.addArrangedSubview(overview)
    contentView.addSubview(words)

    configureButtons()
    buttons.axis = .horizontal
    buttons.alignment = .center
    buttons.spacing = 24
    buttons.translatesAutoresizingMaskIntoConstraints = false
    [playButton, bookmarkButton, detailsButton, nextButton].forEach(buttons.addArrangedSubview)
    contentView.addSubview(buttons)

    pageControl.translatesAutoresizingMaskIntoConstraints = false
    pageControl.isUserInteractionEnabled = false
    pageControl.hidesForSinglePage = true
    pageControl.backgroundStyle = .minimal
    pageControl.progress = timer
    timer.delegate = self
    timer.resetsToInitialPageAfterEnd = true
    contentView.addSubview(pageControl)
    contentView.addLayoutGuide(entryGuide)

    leading = words.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: sideInset)
    wordsWidth = words.widthAnchor.constraint(equalToConstant: 600)
    logoWidth = logo.widthAnchor.constraint(equalToConstant: 0)
    logoHeight = logo.heightAnchor.constraint(equalToConstant: 0)
    markHeight = mark.heightAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      leading,
      wordsWidth,
      entryGuide.topAnchor.constraint(equalTo: contentView.topAnchor),
      entryGuide.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
      entryGuide.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      entryGuide.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      buttons.leadingAnchor.constraint(equalTo: words.leadingAnchor),
      buttons.topAnchor.constraint(equalTo: words.bottomAnchor, constant: 36),
      pageControl.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 36),
      pageControl.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      pageControl.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

      logo.leadingAnchor.constraint(equalTo: mark.leadingAnchor),
      logo.bottomAnchor.constraint(equalTo: mark.bottomAnchor),
      logoWidth,
      logoHeight,
      titleLabel.leadingAnchor.constraint(equalTo: mark.leadingAnchor),
      titleLabel.trailingAnchor.constraint(equalTo: mark.trailingAnchor),
      titleLabel.bottomAnchor.constraint(equalTo: mark.bottomAnchor),
      mark.widthAnchor.constraint(equalTo: words.widthAnchor),
      markHeight
    ])
    updateEntryGuide(focusInButtons: false)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// The cell is a container: its buttons take focus, the cell never does.
  override var canBecomeFocused: Bool { false }

  /// Where focus enters the hero when the page asks for it — down from the tab bar the
  /// first time, Menu back to the top: Next, the Plozz / Apple TV entry Sasha picked
  /// (2026-10-22), so Right right away turns the page. Play when there is one title.
  override var preferredFocusEnvironments: [UIFocusEnvironment] {
    [entryButton]
  }

  /// The button the hero is entered on: the one focus last left, else Next.
  private var entryButton: UIButton {
    if let lastButton, !lastButton.isHidden { return lastButton }
    return nextButton.isHidden ? playButton : nextButton
  }

  private func updateEntryGuide(focusInButtons: Bool) {
    entryGuide.preferredFocusEnvironments = [entryButton]
    entryGuide.isEnabled = !focusInButtons
  }

  func configure(carousel: TVPageHeroCarousel, sideInset: CGFloat) {
    self.sideInset = sideInset
    leading.constant = sideInset
    self.carousel = carousel
    if carousel.cell !== self { carousel.cell = self } else { render(direction: 0) }
    updateTimer()
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    renderedID = nil
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let width = bounds.width
    guard width > 0 else { return }
    // A third of the screen for the words — Apple TV's column; the buttons may run
    // past it. Logo budget from the same width, never a fixed size.
    let column = (width * 0.34).rounded()
    if abs(wordsWidth.constant - column) > 0.5 {
      wordsWidth.constant = column
      overview.preferredMaxLayoutWidth = column
    }
    sizeLogo()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      if let focusFailObserver { NotificationCenter.default.removeObserver(focusFailObserver) }
      focusFailObserver = nil
    } else if focusFailObserver == nil {
      focusFailObserver = NotificationCenter.default.addObserver(
        forName: UIFocusSystem.movementDidFailNotification, object: nil, queue: .main
      ) { [weak self] note in
        let context = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext
        MainActor.assumeIsolated { self?.focusMovementFailed(context) }
      }
    }
    updateTimer()
  }

  override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    // Someone is choosing between the buttons: the title must not turn under them.
    let next = context.nextFocusedView
    if let next, next.isDescendant(of: buttons) {
      timer.currentProgress = 0
      lastButton = next as? UIButton
      updateEntryGuide(focusInButtons: true)
    } else {
      updateEntryGuide(focusInButtons: false)
    }
  }

  // MARK: Rendering

  /// Paint the carousel's current title. `direction` != 0 is a page turn.
  func render(direction: Int) {
    guard let carousel else { return }
    let features = carousel.features
    if pageControl.numberOfPages != features.count { pageControl.numberOfPages = features.count }
    if pageControl.currentPage != carousel.index { pageControl.currentPage = carousel.index }
    if let labels = carousel.hero?.labels { apply(labels) }
    guard let feature = carousel.current else {
      renderedID = nil
      words.isHidden = true
      buttons.isHidden = true
      return
    }
    words.isHidden = false
    buttons.isHidden = false
    let changesTitle = renderedID != feature.card.id
    renderedID = feature.card.id
    let fill = { self.fill(feature, newTitle: changesTitle) }
    // A new title gets its whole dwell, whoever turned the page.
    if changesTitle { timer.currentProgress = 0 }
    if changesTitle, direction != 0, !UIAccessibility.isReduceMotionEnabled {
      UIView.transition(with: words, duration: 0.45,
                        options: [.transitionCrossDissolve, .allowUserInteraction], animations: fill)
    } else {
      fill()
    }
  }

  private func fill(_ feature: TVPageFeature, newTitle: Bool) {
    let card = feature.card
    titleLabel.text = card.title
    if newTitle {
      logoSession.reset()
      paintLogo()
    }
    logoSession.setResolution(feature.logo)
    TVPageBannerCell.fillMeta(meta, card: card, parts: TVPageBannerCell.metaParts(for: card),
                              chrome: Self.metaChrome)
    meta.isHidden = meta.arrangedSubviews.isEmpty
    let synopsis = card.overview.flatMap { TVPageBannerCell.smartSynopsis(of: $0) }
    overview.setUnhyphenated(synopsis)
    overview.isHidden = synopsis?.isEmpty ?? true
    bookmarkButton.isHidden = bookmarkMenu == nil
    accessibilityLabel = card.title
    entryGuide.preferredFocusEnvironments = [entryButton]
  }

  private func paintLogo() {
    var isText = false
    if case .text = logoSession.mark { isText = true }
    let image = isText ? nil : logoSession.image
    logo.image = image
    logo.isHidden = image == nil
    titleLabel.isHidden = !isText
    sizeLogo()
  }

  /// The view takes the image's own shape inside the budget, so its bottom edge sits on
  /// the meta line whatever the logo's proportions.
  private func sizeLogo() {
    let width = bounds.width
    let maxWidth = (width * 0.28).rounded()
    let maxHeight = (width * 0.085).rounded()
    markHeight.constant = maxHeight
    guard let image = logo.image, image.size.height > 0, !logo.isHidden else {
      logoWidth.constant = 0
      logoHeight.constant = 0
      return
    }
    let aspect = image.size.width / image.size.height
    var height = maxHeight
    var logoW = height * aspect
    if logoW > maxWidth {
      logoW = maxWidth
      height = logoW / aspect
    }
    logoWidth.constant = logoW.rounded()
    logoHeight.constant = height.rounded()
  }

  // MARK: Buttons

  private func configureButtons() {
    // Plain glass like its neighbours: only focus turns a button white. Prominent glass
    // kept Play white at rest, which read as focus sitting on two buttons.
    var play = UIButton.Configuration.glass()
    play.image = UIImage(systemName: "play.fill")
    play.imagePadding = 12
    play.cornerStyle = .capsule
    playButton.configuration = play
    playButton.accessibilityIdentifier = "kinopub.hero.play"
    playButton.addAction(UIAction { [weak self] _ in
      guard let self, let feature = self.carousel?.current else { return }
      self.onPlay?(feature)
    }, for: .primaryActionTriggered)

    var bookmark = UIButton.Configuration.glass()
    bookmark.image = UIImage(systemName: "bookmark")
    bookmark.cornerStyle = .capsule
    bookmarkButton.configuration = bookmark
    bookmarkButton.accessibilityIdentifier = "kinopub.hero.bookmark"
    bookmarkButton.showsMenuAsPrimaryAction = true
    bookmarkButton.menu = UIMenu(children: [
      UIDeferredMenuElement.uncached { [weak self] completion in
        guard let self, let feature = self.carousel?.current else { return completion([]) }
        completion(self.bookmarkMenu?(feature) ?? [])
      }
    ])

    var details = UIButton.Configuration.glass()
    details.cornerStyle = .capsule
    detailsButton.configuration = details
    detailsButton.accessibilityIdentifier = "kinopub.hero.details"
    detailsButton.addAction(UIAction { [weak self] _ in
      guard let self, let feature = self.carousel?.current else { return }
      self.onDetails?(feature)
    }, for: .primaryActionTriggered)

    var next = UIButton.Configuration.glass()
    next.image = UIImage(systemName: "chevron.right")
    next.cornerStyle = .capsule
    nextButton.configuration = next
    nextButton.accessibilityIdentifier = "kinopub.hero.next"
    nextButton.addAction(UIAction { [weak self] _ in
      self?.carousel?.step(1)
    }, for: .primaryActionTriggered)
  }

  private var appliedLabels: TVPageHero.Labels?

  private func apply(_ labels: TVPageHero.Labels) {
    guard labels != appliedLabels else { return }
    appliedLabels = labels
    playButton.configuration?.title = labels.play
    detailsButton.configuration?.title = labels.details
    bookmarkButton.accessibilityLabel = labels.bookmark
    nextButton.accessibilityLabel = labels.next
    nextButton.isHidden = (carousel?.features.count ?? 0) < 2
  }

  /// Left / Right past the ends of the button row turns the page and keeps the button:
  /// Right on Next is the next title, Left on Play the previous one (Plozz's
  /// `HeroCarouselFocus`). Nothing else is there to move to, so the engine reports a
  /// failed move; that report is the whole mechanism — no focus routing of our own.
  private func focusMovementFailed(_ context: UIFocusUpdateContext?) {
    guard let context, let carousel,
          let view = context.previouslyFocusedItem as? UIView, view.isDescendant(of: buttons) else { return }
    let visible = buttons.arrangedSubviews.filter { !$0.isHidden }
    if context.focusHeading.contains(.right), view === visible.last {
      carousel.step(1)
    } else if context.focusHeading.contains(.left), view === visible.first {
      carousel.step(-1)
    }
  }

  /// How much further than the page the words and buttons rise when focus goes down
  /// (Plozz's `recedeContentLift`, 170 pt of 1080): the gap to the row opens as the
  /// page scrolls, so the hero leaves ahead of the row instead of riding on it.
  private static let recedeLift: CGFloat = 0.12

  /// On the row under the hero the words rise ahead of the page and stay, over the
  /// dimmed picture. Further down the picture is gone, and the words with it — they
  /// must not float over the page.
  func apply(stage: TVPageHeroCarousel.Stage, animated: Bool) {
    let alpha: CGFloat = stage == .away ? 0 : 1
    let lift = stage == .hero ? 0 : -((window?.bounds.height ?? bounds.height) * Self.recedeLift).rounded()
    let transform = CGAffineTransform(translationX: 0, y: lift)
    // On the views themselves, not the content view: the cell lays its content view
    // out by `frame`, which cancels a translation on it (the lift never showed).
    let lifted: [UIView] = [words, buttons, pageControl]
    guard contentView.alpha != alpha || lifted.contains(where: { $0.transform != transform }) else { return }
    let changes = {
      self.contentView.alpha = alpha
      lifted.forEach { $0.transform = transform }
    }
    guard animated, !UIAccessibility.isReduceMotionEnabled else {
      changes()
      return
    }
    // Quicker than the picture (0.9 s): the words lead, the picture lags behind them.
    UIView.animate(withDuration: 0.6, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0,
                   options: [.beginFromCurrentState, .allowUserInteraction], animations: changes)
  }

  // MARK: Timer

  func restartDwell() {
    timer.currentProgress = 0
  }

  func updateTimer() {
    guard let carousel else { return }
    if window != nil, carousel.advances {
      timer.resumeTimer()
    } else {
      timer.pauseTimer()
    }
  }

  private static func weightedFont(_ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> UIFont {
    let descriptor = UIFont.preferredFont(forTextStyle: style).fontDescriptor
      .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
    return UIFont(descriptor: descriptor, size: 0)
  }
}

extension TVPageHeroCell: UIPageControlTimerProgressDelegate {
  /// The dwell ran out: the carousel moves, the control draws the new page itself.
  func pageControlTimerProgress(_ progress: UIPageControlTimerProgress, shouldAdvanceToPage page: Int) -> Bool {
    guard let carousel, carousel.advances else { return false }
    carousel.move(to: page, direction: 1)
    return true
  }
}
#endif

#if os(tvOS)
/// The wipe's mask: opaque, with a gradient on the side that leads into the picture.
@MainActor
private final class TVPageHeroWipeMask: UIView {
  override class var layerClass: AnyClass { CAGradientLayer.self }

  init(feather: CGFloat, fromTrailing: Bool) {
    super.init(frame: .zero)
    let gradient = layer as! CAGradientLayer // swiftlint:disable:this force_cast
    gradient.startPoint = CGPoint(x: 0, y: 0.5)
    gradient.endPoint = CGPoint(x: 1, y: 0.5)
    featherWidth = feather
    leadsFromTrailing = fromTrailing
    gradient.colors = fromTrailing
      ? [UIColor.clear.cgColor, UIColor.black.cgColor, UIColor.black.cgColor]
      : [UIColor.black.cgColor, UIColor.black.cgColor, UIColor.clear.cgColor]
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  private var featherWidth: CGFloat = 0
  private var leadsFromTrailing = true

  override func layoutSubviews() {
    super.layoutSubviews()
    let gradient = layer as! CAGradientLayer // swiftlint:disable:this force_cast
    let share = bounds.width > 0 ? featherWidth / bounds.width : 0
    gradient.locations = leadsFromTrailing
      ? [0, NSNumber(value: Double(share)), 1]
      : [0, NSNumber(value: Double(1 - share)), 1]
  }
}
#endif
