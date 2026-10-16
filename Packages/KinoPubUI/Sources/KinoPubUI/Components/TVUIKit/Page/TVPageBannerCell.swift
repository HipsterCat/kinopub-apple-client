#if os(tvOS)
//
//  TVPageBannerCell.swift
//  KinoPubUI
//
//  The Home banner: a `TVCardView` platter, so the lift, tilt and focus motion are
//  the system's. Everything drawn is inside the card's `contentView`. What it draws
//  — alignment, logo, scrim, poster — is `TVPageBannerChrome`.
//
//  The plot's first sentence and the meta line are both caption-sized and the same
//  weight. Focus does not recolour the plot. The meta line is a source logo and its
//  number (IMDb, then Kinopoisk), then the season count and one genre — never the
//  aggregate. A rating with no logo is left out, so a bare number cannot stand in
//  for it.
//
//  The title logo and the name share one slot (`TitleLogoSession`, same as the
//  detail hero): empty while a lookup is in flight, cached logo on the first
//  frame, lettered name only after a confirmed miss (no URL, 404, or image-load
//  timeout). A pending metadata lookup does not time out into text.
//

import TVUIKit
import UIKit

@MainActor
final class TVPageBannerCell: UICollectionViewCell {
  private let cardView = TVCardView()
  private let backdrop = UIImageView()
  private let wash = UIView()
  private let topScrim = GradientView()
  private let bottomScrim = GradientView()
  private let poster = UIImageView()
  private let logo = UIImageView()
  private let titleLabel = UILabel()
  private let overviewLabel = UILabel()
  private let meta = UIStackView()
  private let column = UIStackView()
  private let band = UIStackView()

  private var logoWidth: NSLayoutConstraint!
  private var logoHeight: NSLayoutConstraint!
  private var topScrimHeight: NSLayoutConstraint!
  private var bottomScrimHeight: NSLayoutConstraint!
  private var chromeConstraints: [NSLayoutConstraint] = []

  private var tasks: [Task<Void, Never>] = []
  private var feature: TVPageFeature?
  private var chrome = TVPageBannerChrome.current
  /// Shared with the SwiftUI hero. Completions are request-scoped inside the session.
  private let logoSession = TitleLogoSession()
  /// The plot sentence, plain. The label draws it unhyphenated, and chrome edits
  /// (font, colour, alignment) rebuild that string.
  private var overviewText: String?
  #if DEBUG
  /// A naked cell has no collection view to run `TVCardView`'s platter pass, so the
  /// preview sizes the platter itself. Off in the app.
  var laysOutPlatterForPreview = false
  #endif

  private static let cornerRadius: CGFloat = 20
  private static let posterCornerRadius: CGFloat = 10

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = false
    contentView.clipsToBounds = false

    cardView.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(cardView)
    logoSession.onChange = { [weak self] in self?.paintLogoSession() }

    let host = cardView.contentView
    host.backgroundColor = UIColor(white: 0.12, alpha: 1)
    host.layer.cornerRadius = Self.cornerRadius
    host.layer.cornerCurve = .continuous
    host.clipsToBounds = true

    backdrop.translatesAutoresizingMaskIntoConstraints = false
    backdrop.contentMode = .scaleAspectFill
    backdrop.clipsToBounds = true
    host.addSubview(backdrop)

    wash.translatesAutoresizingMaskIntoConstraints = false
    wash.isUserInteractionEnabled = false
    host.addSubview(wash)

    for scrim in [topScrim, bottomScrim] {
      scrim.translatesAutoresizingMaskIntoConstraints = false
      scrim.isUserInteractionEnabled = false
      host.addSubview(scrim)
    }

    logo.isHidden = true
    titleLabel.isHidden = true
    logo.translatesAutoresizingMaskIntoConstraints = false
    logo.contentMode = .scaleAspectFit
    logo.setContentHuggingPriority(.required, for: .horizontal)
    logo.setContentHuggingPriority(.required, for: .vertical)
    logo.setContentCompressionResistancePriority(.required, for: .horizontal)
    logo.setContentCompressionResistancePriority(.required, for: .vertical)

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = Self.weightedFont(.headline, .semibold)
    titleLabel.textColor = .white
    titleLabel.numberOfLines = 2
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    overviewLabel.numberOfLines = 4
    overviewLabel.lineBreakMode = .byTruncatingTail
    overviewLabel.adjustsFontForContentSizeCategory = true
    // A multiline label's intrinsic width collapses to a few characters. The column
    // pins set the real width; these priorities let that pin win.
    overviewLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
    overviewLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    column.setContentHuggingPriority(.defaultLow, for: .horizontal)
    column.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    meta.axis = .horizontal
    meta.alignment = .center
    meta.spacing = MediaScoresView.groupSpacing
    meta.setContentHuggingPriority(.required, for: .horizontal)
    column.axis = .vertical
    column.translatesAutoresizingMaskIntoConstraints = false
    column.addArrangedSubview(overviewLabel)
    column.addArrangedSubview(meta)

    poster.translatesAutoresizingMaskIntoConstraints = false
    poster.contentMode = .scaleAspectFill
    poster.clipsToBounds = true
    poster.layer.cornerRadius = Self.posterCornerRadius
    poster.layer.cornerCurve = .continuous

    band.axis = .horizontal
    band.alignment = .bottom
    band.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(poster)

    logoWidth = logo.widthAnchor.constraint(equalToConstant: 0)
    logoHeight = logo.heightAnchor.constraint(equalToConstant: 0)
    topScrimHeight = topScrim.heightAnchor.constraint(equalToConstant: 0)
    bottomScrimHeight = bottomScrim.heightAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
      cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

      backdrop.topAnchor.constraint(equalTo: host.topAnchor),
      backdrop.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      backdrop.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      backdrop.bottomAnchor.constraint(equalTo: host.bottomAnchor),

      wash.topAnchor.constraint(equalTo: host.topAnchor),
      wash.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      wash.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      wash.bottomAnchor.constraint(equalTo: host.bottomAnchor),

      topScrim.topAnchor.constraint(equalTo: host.topAnchor),
      topScrim.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      topScrim.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      topScrimHeight,
      bottomScrim.bottomAnchor.constraint(equalTo: host.bottomAnchor),
      bottomScrim.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      bottomScrim.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      bottomScrimHeight,

      logoWidth,
      logoHeight,
      poster.heightAnchor.constraint(equalTo: host.heightAnchor, multiplier: TVPageBannerChrome.current.posterHeightRatio),
      poster.widthAnchor.constraint(equalTo: poster.heightAnchor, multiplier: CardAspect.poster.ratio)
    ])
    installChrome()
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var canBecomeFocused: Bool { true }

  override func layoutSubviews() {
    super.layoutSubviews()
    #if DEBUG
    if laysOutPlatterForPreview {
      let platter = cardView.contentView
      if platter.bounds.width < 2, contentView.bounds.width > 2 {
        cardView.frame = contentView.bounds
        let size = cardView.contentSize.width > 2 ? cardView.contentSize : contentView.bounds.size
        platter.frame = CGRect(x: (cardView.bounds.width - size.width) / 2,
                               y: (cardView.bounds.height - size.height) / 2,
                               width: size.width,
                               height: size.height)
      }
    }
    #endif
    let host = cardView.contentView.bounds.size
    guard host.height > 0 else { return }
    switch chrome.scrim {
    case .edges(_, let topReach, _, let bottomReach, _):
      topScrimHeight.constant = host.height * topReach
      bottomScrimHeight.constant = host.height * bottomReach
    case .wash:
      topScrimHeight.constant = 0
      bottomScrimHeight.constant = 0
    case .radial:
      topScrimHeight.constant = host.height
      bottomScrimHeight.constant = 0
    }
    let copyWidth = copyWidth(in: host)
    if copyWidth > 0, overviewLabel.preferredMaxLayoutWidth != copyWidth {
      overviewLabel.preferredMaxLayoutWidth = copyWidth
      titleLabel.preferredMaxLayoutWidth = copyWidth
      setNeedsLayout()
    }
    updateLogoSize(in: host)
    #if DEBUG
    if laysOutPlatterForPreview {
      cardView.contentView.layoutIfNeeded()
    }
    #endif
  }

  /// The card view sizes its platter from `contentSize`; the recipe holds the content
  /// size whose resting platter lands on the banner's width (`TVPageCellMetrics`).
  func apply(recipe: TVPageCellRecipe) {
    if cardView.contentSize != recipe.posterContentSize {
      cardView.contentSize = recipe.posterContentSize
    }
  }

  func configure(feature: TVPageFeature) {
    let card = feature.card
    let previous = self.feature
    self.feature = feature
    titleLabel.text = card.title
    overviewText = card.overview.flatMap { Self.firstSentence(of: $0) }
    applyOverview()
    let metaParts = Self.metaParts(for: card)
    applyMeta(card, parts: metaParts)
    accessibilityIdentifier = "kinopub.banner.\(card.id)"
    cardView.accessibilityLabel = ([card.title, overviewLabel.text].compactMap { $0 } + metaParts)
      .joined(separator: ", ")

    // A reconfigure of the same title (its details or logo arrived) keeps what is
    // already on screen and only loads what is new.
    let sameTitle = previous?.card.id == card.id
    if !sameTitle {
      cancelLoads()
      logoSession.reset()
      backdrop.image = nil
      poster.image = nil
      showMark(nil, awaitingLogo: true)
    }
    let size = cardView.contentSize
    if !sameTitle || backdrop.image == nil {
      load([URL(string: card.backdropImageURL), URL(string: card.posterURL)], size: size) { [weak self] in
        self?.backdrop.image = $0
      }
    }
    if chrome.showsPoster, !sameTitle || poster.image == nil {
      let posterSize = CGSize(width: size.height * chrome.posterHeightRatio * CardAspect.poster.ratio,
                              height: size.height * chrome.posterHeightRatio)
      load([URL(string: card.posterURL)], size: posterSize) { [weak self] in
        self?.poster.image = $0
      }
    }
    let logoChanged = previous?.logo != feature.logo
    if !sameTitle || logoChanged || (feature.logo.url != nil && logo.image == nil) {
      applyLogo(feature.logo)
    }
  }

  /// The plot's first sentence and nothing else; a banner is not the place to read.
  private static func firstSentence(of text: String) -> String? {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    var first: String?
    text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, stop in
      first = sentence?.trimmingCharacters(in: .whitespacesAndNewlines)
      stop = true
    }
    return first ?? text
  }

  /// Width the sentence can use: the column's pins, read off the platter rather
  /// than `column.bounds`, which follows the label and collapses with it.
  private func copyWidth(in host: CGSize) -> CGFloat {
    let pad = chrome.padding
    switch chrome.alignment {
    case .leading:
      var width = host.width - pad * 2
      if chrome.showsPoster {
        let posterHeight = host.height * chrome.posterHeightRatio
        width -= posterHeight * CardAspect.poster.ratio + pad
      }
      return max(width, 0)
    case .center:
      let fraction: CGFloat = chrome.showsPoster ? 0.48 : 0.62
      return max(host.width * fraction, 0)
    }
  }

  private func applyOverview() {
    overviewLabel.setUnhyphenated(overviewText)
    overviewLabel.isHidden = overviewText?.isEmpty ?? true
  }

  // MARK: - Meta

  /// The words after the scores: season count for a series, then one genre.
  private static func metaParts(for card: MediaCard) -> [String] {
    var parts: [String] = []
    if let seasons = card.seasonCountText() { parts.append(seasons) }
    if let genre = card.primaryGenre(), !genre.isEmpty { parts.append(genre) }
    return parts
  }

  /// Logo, then the number, in the same font as the description. No logo, no number —
  /// a bare digit is what the aggregate looks like, and this row does not show it.
  private func applyMeta(_ card: MediaCard, parts: [String]) {
    meta.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let font = chrome.textFont
    let iconHeight = chrome.scoreIconHeight ?? max(font.capHeight.rounded(), 12)
    let scores: [(MediaScoreLogo.Source, Double?)] = [
      (.imdb, card.scores.imdbScore),
      (.kinopoisk, card.scores.kinopoiskScore)
    ]
    for (source, value) in scores {
      guard let value, let mark = Self.scoreLogo(source, height: iconHeight) else { continue }
      let group = UIStackView()
      group.axis = .horizontal
      group.alignment = .center
      group.spacing = 6
      group.addArrangedSubview(mark)
      let number = UILabel()
      number.font = font
      number.adjustsFontForContentSizeCategory = true
      number.textColor = chrome.resolvedTextColor
      number.text = String(format: "%.1f", value)
      group.addArrangedSubview(number)
      meta.addArrangedSubview(group)
    }
    for part in parts {
      let label = UILabel()
      label.font = font
      label.adjustsFontForContentSizeCategory = true
      label.textColor = chrome.resolvedTextColor
      label.text = part
      meta.addArrangedSubview(label)
    }
    meta.isHidden = meta.arrangedSubviews.isEmpty
  }

  /// The source's colour mark at a fixed height, width following the artwork.
  /// Colour, not the template wordmark: the template drew as a faint smear, or not
  /// at all, and the digit sat there on its own.
  private static func scoreLogo(_ source: MediaScoreLogo.Source, height: CGFloat) -> UIImageView? {
    guard let image = source.uiImage(style: .color), image.size.height > 0 else { return nil }
    let view = UIImageView(image: image.withRenderingMode(.alwaysOriginal))
    view.contentMode = .scaleAspectFit
    view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      view.heightAnchor.constraint(equalToConstant: height),
      view.widthAnchor.constraint(equalToConstant: (height * image.size.width / image.size.height).rounded())
    ])
    return view
  }

  // MARK: - Chrome

  /// Rebuilds the pins. Images stay. Pass a draft from the preview; the page uses `current`.
  func installChrome(_ chrome: TVPageBannerChrome = .current) {
    self.chrome = chrome
    NSLayoutConstraint.deactivate(chromeConstraints)
    chromeConstraints = []

    if column.arrangedSubviews.contains(where: { $0 === logo }) {
      column.removeArrangedSubview(logo)
      logo.removeFromSuperview()
    }
    if column.arrangedSubviews.contains(where: { $0 === titleLabel }) {
      column.removeArrangedSubview(titleLabel)
      titleLabel.removeFromSuperview()
    }
    band.arrangedSubviews.forEach {
      band.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    column.removeFromSuperview()
    poster.removeFromSuperview()
    band.removeFromSuperview()
    logo.removeFromSuperview()
    titleLabel.removeFromSuperview()

    let host = cardView.contentView
    let pad = chrome.padding
    let centered = chrome.alignment == .center
    column.alignment = centered ? .center : .leading
    column.spacing = chrome.copySpacing
    band.spacing = pad
    overviewLabel.font = chrome.textFont
    overviewLabel.textAlignment = centered ? .center : .natural
    titleLabel.textAlignment = centered ? .center : .natural
    applyOverview()
    poster.isHidden = !chrome.showsPoster
    applyScrim()
    applyCopyColor()
    if !chrome.showsPoster { host.addSubview(poster) }

    var pins: [NSLayoutConstraint] = []
    switch chrome.alignment {
    case .leading:
      host.addSubview(column)
      pins += [
        column.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: pad),
        column.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -pad)
      ]
      if chrome.showsPoster {
        host.addSubview(poster)
        pins += [
          poster.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -pad),
          poster.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -pad),
          column.trailingAnchor.constraint(equalTo: poster.leadingAnchor, constant: -pad)
        ]
      } else {
        pins += [column.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -pad)]
      }
    case .center:
      host.addSubview(band)
      band.addArrangedSubview(column)
      if chrome.showsPoster { band.addArrangedSubview(poster) }
      let fraction: CGFloat = chrome.showsPoster ? 0.48 : 0.62
      pins += [
        band.centerXAnchor.constraint(equalTo: host.centerXAnchor),
        band.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -pad),
        band.leadingAnchor.constraint(greaterThanOrEqualTo: host.leadingAnchor, constant: pad),
        band.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor, constant: -pad),
        column.widthAnchor.constraint(equalTo: host.widthAnchor, multiplier: fraction)
      ]
    }

    switch chrome.logoPlacement {
    case .top:
      host.addSubview(logo)
      host.addSubview(titleLabel)
      pins += [
        logo.topAnchor.constraint(equalTo: host.topAnchor, constant: pad),
        titleLabel.topAnchor.constraint(equalTo: host.topAnchor, constant: pad)
      ]
      if centered {
        pins += [
          logo.centerXAnchor.constraint(equalTo: host.centerXAnchor),
          titleLabel.centerXAnchor.constraint(equalTo: host.centerXAnchor),
          titleLabel.widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor, multiplier: chrome.logoMaxWidthRatio)
        ]
      } else {
        pins += [
          logo.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: pad),
          titleLabel.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: pad),
          titleLabel.trailingAnchor.constraint(equalTo: column.trailingAnchor)
        ]
      }
    case .aboveCopy:
      column.insertArrangedSubview(titleLabel, at: 0)
      column.insertArrangedSubview(logo, at: 1)
    }
    // The column is as wide as the pins (leading edge to the poster, or the
    // centred fraction). The sentence fills that width; without this it keeps
    // the multiline label's collapsed intrinsic width and wraps in the corner.
    pins += [overviewLabel.widthAnchor.constraint(equalTo: column.widthAnchor)]
    if chrome.logoPlacement == .aboveCopy {
      pins += [titleLabel.widthAnchor.constraint(equalTo: column.widthAnchor)]
    }

    chromeConstraints = pins
    NSLayoutConstraint.activate(pins)
    setNeedsLayout()
  }

  /// Description, digits and genres share one colour. The preview calls this again
  /// when it swaps chrome, so labels built earlier pick up the new value.
  private func applyCopyColor() {
    let color = chrome.resolvedTextColor
    overviewLabel.textColor = color
    applyOverview()
    for view in meta.arrangedSubviews {
      if let label = view as? UILabel { label.textColor = color }
      guard let group = view as? UIStackView else { continue }
      for subview in group.arrangedSubviews {
        if let label = subview as? UILabel { label.textColor = color }
      }
    }
  }

  private func applyScrim() {
    let filter = chrome.blend.filterName
    for view in [wash, topScrim, bottomScrim] {
      view.layer.compositingFilter = filter
    }
    wash.isHidden = true
    topScrim.isHidden = true
    bottomScrim.isHidden = true
    topScrim.gradientType = .axial
    topScrim.startPoint = CGPoint(x: 0.5, y: 0)
    topScrim.endPoint = CGPoint(x: 0.5, y: 1)
    bottomScrim.gradientType = .axial
    bottomScrim.startPoint = CGPoint(x: 0.5, y: 0)
    bottomScrim.endPoint = CGPoint(x: 0.5, y: 1)

    switch chrome.scrim {
    case .edges(let color, _, let topAlpha, _, let bottomAlpha):
      topScrim.isHidden = topAlpha <= 0
      bottomScrim.isHidden = bottomAlpha <= 0
      topScrim.colors = [color.withAlphaComponent(topAlpha), color.withAlphaComponent(0)]
      bottomScrim.colors = [color.withAlphaComponent(0), color.withAlphaComponent(bottomAlpha)]
    case .wash(let color):
      wash.isHidden = false
      wash.backgroundColor = color
    case .radial(let edge, let mid):
      topScrim.isHidden = false
      topScrim.gradientType = .radial
      topScrim.startPoint = CGPoint(x: 0.5, y: 0.5)
      topScrim.endPoint = CGPoint(x: 1, y: 1)
      topScrim.colors = [mid, edge]
    }
  }

  // MARK: - Logo

  /// Empty while a lookup is in flight; cached image immediately; lettered name
  /// only after a confirmed miss. ``TitleLogoSession`` is the same state the hero uses.
  private func applyLogo(_ resolution: TitleLogoResolution) {
    logoSession.setResolution(resolution)
  }

  private func paintLogoSession() {
    switch logoSession.mark {
    case .logo:
      showMark(logoSession.image, awaitingLogo: false)
    case .text:
      showMark(nil, awaitingLogo: false)
    case .empty:
      showMark(logoSession.image, awaitingLogo: logoSession.image == nil)
    }
  }

  /// The logo and the name are one slot. `awaitingLogo` keeps the name off until
  /// the image arrives or the load fails.
  private func showMark(_ image: UIImage?, awaitingLogo: Bool) {
    logo.image = image
    logo.isHidden = image == nil
    titleLabel.isHidden = image != nil || awaitingLogo
    updateLogoSize(in: cardView.contentView.bounds.size)
    setNeedsLayout()
  }

  /// The view's size is the image's, so its top is the artwork's top. A fixed-height
  /// box with aspect-fit letterboxed a wide logo and the inset jumped per title.
  private func updateLogoSize(in host: CGSize) {
    guard let image = logo.image, image.size.height > 0, host.height > 0, !logo.isHidden else {
      logoWidth.constant = 0
      logoHeight.constant = 0
      return
    }
    let maxHeight = host.height * chrome.logoMaxHeightRatio
    let maxWidth = host.width * chrome.logoMaxWidthRatio
    let aspect = image.size.width / image.size.height
    var height = maxHeight
    var width = height * aspect
    if width > maxWidth, aspect > 0 {
      width = maxWidth
      height = width / aspect
    }
    logoWidth.constant = width.rounded()
    logoHeight.constant = height.rounded()
  }

  // MARK: - Images

  /// First URL that loads wins: a derived wide backdrop can 404 where the poster does not.
  /// `ifNone` runs when every URL misses — the logo uses it to fall back to the name.
  private func load(_ urls: [URL?], size: CGSize,
                    apply: @escaping @MainActor (UIImage?) -> Void,
                    ifNone: (@MainActor () -> Void)? = nil) {
    let urls = urls.compactMap { $0 }
    if let hit = urls.lazy.compactMap({ TVUIKitRemoteImage.cached(url: $0, size: size) }).first {
      apply(hit)
      return
    }
    apply(nil)
    guard !urls.isEmpty else {
      ifNone?()
      return
    }
    let id = feature?.card.id
    tasks.append(Task { [weak self] in
      for url in urls {
        let image = await TVUIKitRemoteImage.load(url: url, size: size)
        guard let self, !Task.isCancelled, self.feature?.card.id == id else { return }
        if let image {
          apply(image)
          return
        }
      }
      guard !Task.isCancelled, self?.feature?.card.id == id else { return }
      ifNone?()
    })
  }

  private func cancelLoads() {
    tasks.forEach { $0.cancel() }
    tasks = []
  }

  private static func weightedFont(_ style: UIFont.TextStyle, _ weight: UIFont.Weight) -> UIFont {
    let descriptor = UIFont.preferredFont(forTextStyle: style).fontDescriptor
      .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
    return UIFont(descriptor: descriptor, size: 0)
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    cancelLoads()
    logoSession.reset()
    feature = nil
    backdrop.image = nil
    poster.image = nil
    showMark(nil, awaitingLogo: true)
    titleLabel.text = nil
    overviewText = nil
    applyOverview()
    meta.arrangedSubviews.forEach { $0.removeFromSuperview() }
    accessibilityIdentifier = nil
  }

  #if DEBUG
  /// Solid stand-ins so the preview can show the chrome without a network.
  func previewFill(backdrop: UIImage, poster: UIImage?, logo: UIImage?) {
    laysOutPlatterForPreview = true
    self.backdrop.image = backdrop
    self.poster.image = poster
    showMark(logo, awaitingLogo: false)
  }
  #endif
}
#endif

#if os(tvOS)
/// A gradient that follows its view's bounds — sized by Auto Layout like any view.
@MainActor
private final class GradientView: UIView {
  override class var layerClass: AnyClass { CAGradientLayer.self }
  private var gradient: CAGradientLayer { layer as! CAGradientLayer } // swiftlint:disable:this force_cast

  var colors: [UIColor] = [] {
    didSet { gradient.colors = colors.map(\.cgColor) }
  }
  var gradientType: CAGradientLayerType {
    get { gradient.type }
    set { gradient.type = newValue }
  }
  var startPoint: CGPoint {
    get { gradient.startPoint }
    set { gradient.startPoint = newValue }
  }
  var endPoint: CGPoint {
    get { gradient.endPoint }
    set { gradient.endPoint = newValue }
  }
}
#endif
