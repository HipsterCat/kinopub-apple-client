#if os(tvOS)
//
//  TVPageBannerCell.swift
//  KinoPubUI
//
//  The Home banner: a `TVCardView` platter, like the wide card, so the lift, tilt and
//  focus motion are the system's. Everything drawn is inside the card's `contentView`:
//  the backdrop filling it, a scrim at the top behind the title logo (or the name when
//  there is no logo) and one at the bottom behind the words, the plot's first sentence
//  and the meta line, and the poster inset at the trailing edge.
//
//  The meta line is short on purpose (Sasha, 2026-10-01): the scores as
//  `MediaScoresView` draws them (logo at a fixed height, then the value), the season
//  count for a series (`MediaCard.seasonsLabel`) and one genre. No year, runtime,
//  country or dots. Plot and meta are both caption-sized; the plot goes primary while
//  focused, the meta stays secondary.
//

import TVUIKit
import UIKit

@MainActor
final class TVPageBannerCell: UICollectionViewCell {
  private let cardView = TVCardView()
  private let backdrop = UIImageView()
  private let topScrim = GradientView()
  private let bottomScrim = GradientView()
  private let poster = UIImageView()
  private let logo = UIImageView()
  private let titleLabel = UILabel()
  private let overviewLabel = UILabel()
  private let meta = UIStackView()
  private var logoWidth: NSLayoutConstraint!

  private var tasks: [Task<Void, Never>] = []
  private var feature: TVPageFeature?
  private var isFocusedLook = false

  private static let cornerRadius: CGFloat = 20
  private static let padding: CGFloat = 32
  private static let posterCornerRadius: CGFloat = 10
  /// The poster's share of the platter's height, and the logo's box.
  private static let posterHeightRatio: CGFloat = 0.42
  private static let logoHeightRatio: CGFloat = 0.2
  private static let logoMaxWidthRatio: CGFloat = 0.6
  /// How far each scrim reaches into the platter, as a share of its height.
  private static let topScrimReach: CGFloat = 0.45
  private static let bottomScrimReach: CGFloat = 0.65
  private static let resting = UIColor.white.withAlphaComponent(0.6)

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = false
    contentView.clipsToBounds = false

    cardView.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(cardView)

    let host = cardView.contentView
    host.backgroundColor = UIColor(white: 0.12, alpha: 1)
    host.layer.cornerRadius = Self.cornerRadius
    host.layer.cornerCurve = .continuous
    host.clipsToBounds = true

    backdrop.translatesAutoresizingMaskIntoConstraints = false
    backdrop.contentMode = .scaleAspectFill
    backdrop.clipsToBounds = true
    host.addSubview(backdrop)

    // Two scrims, not one: the title at the top and the words at the bottom each get
    // their own dark edge, and the middle, where the art's subject usually is, stays clear.
    // Views pinned with constraints, not layers sized in `layoutSubviews`: the platter
    // is sized by the card view after the cell lays out, so a reused cell kept a stale
    // (often zero) layer frame and drew white text on white art (2026-10-01).
    topScrim.colors = [UIColor.black.withAlphaComponent(0.65), UIColor.black.withAlphaComponent(0)]
    bottomScrim.colors = [UIColor.black.withAlphaComponent(0), UIColor.black.withAlphaComponent(0.65), UIColor.black.withAlphaComponent(0.9)]
    bottomScrim.locations = [0, 0.45, 1]
    for scrim in [topScrim, bottomScrim] {
      scrim.translatesAutoresizingMaskIntoConstraints = false
      scrim.isUserInteractionEnabled = false
      host.addSubview(scrim)
    }

    logo.translatesAutoresizingMaskIntoConstraints = false
    logo.contentMode = .scaleAspectFit
    host.addSubview(logo)

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = Self.font(.headline, weight: .bold)
    titleLabel.textColor = .white
    titleLabel.numberOfLines = 2
    host.addSubview(titleLabel)

    overviewLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
    overviewLabel.numberOfLines = 4
    overviewLabel.adjustsFontForContentSizeCategory = true
    meta.axis = .horizontal
    meta.alignment = .center
    meta.spacing = MediaScoresView.groupSpacing
    let text = UIStackView(arrangedSubviews: [overviewLabel, meta])
    text.axis = .vertical
    text.spacing = 8
    text.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(text)
    titleLabel.adjustsFontForContentSizeCategory = true

    poster.translatesAutoresizingMaskIntoConstraints = false
    poster.contentMode = .scaleAspectFill
    poster.clipsToBounds = true
    poster.layer.cornerRadius = Self.posterCornerRadius
    poster.layer.cornerCurve = .continuous
    host.addSubview(poster)

    let pad = Self.padding
    logoWidth = logo.widthAnchor.constraint(equalToConstant: 0)
    NSLayoutConstraint.activate([
      cardView.topAnchor.constraint(equalTo: contentView.topAnchor),
      cardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      cardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      cardView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

      backdrop.topAnchor.constraint(equalTo: host.topAnchor),
      backdrop.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      backdrop.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      backdrop.bottomAnchor.constraint(equalTo: host.bottomAnchor),

      topScrim.topAnchor.constraint(equalTo: host.topAnchor),
      topScrim.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      topScrim.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      topScrim.heightAnchor.constraint(equalTo: host.heightAnchor, multiplier: Self.topScrimReach),
      bottomScrim.bottomAnchor.constraint(equalTo: host.bottomAnchor),
      bottomScrim.leadingAnchor.constraint(equalTo: host.leadingAnchor),
      bottomScrim.trailingAnchor.constraint(equalTo: host.trailingAnchor),
      bottomScrim.heightAnchor.constraint(equalTo: host.heightAnchor, multiplier: Self.bottomScrimReach),

      logo.topAnchor.constraint(equalTo: host.topAnchor, constant: pad),
      logo.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: pad),
      logo.heightAnchor.constraint(equalTo: host.heightAnchor, multiplier: Self.logoHeightRatio),
      logoWidth,

      // The name, when there is no logo, takes the whole width.
      titleLabel.topAnchor.constraint(equalTo: host.topAnchor, constant: pad),
      titleLabel.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: pad),
      titleLabel.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -pad),

      poster.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -pad),
      poster.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -pad),
      poster.heightAnchor.constraint(equalTo: host.heightAnchor, multiplier: Self.posterHeightRatio),
      poster.widthAnchor.constraint(equalTo: poster.heightAnchor, multiplier: CardAspect.poster.ratio),

      text.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: pad),
      text.trailingAnchor.constraint(equalTo: poster.leadingAnchor, constant: -pad),
      text.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -pad)
    ])
    applyFocusColors(false)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    updateLogoWidth()
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
    overviewLabel.text = card.overview.flatMap { Self.firstSentence(of: $0) }
    overviewLabel.isHidden = overviewLabel.text?.isEmpty ?? true
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
      showLogo(nil)
    }
    let size = cardView.contentSize
    if !sameTitle || backdrop.image == nil {
      load([URL(string: card.backdropImageURL), URL(string: card.posterURL)], size: size) { [weak self] in
        self?.backdrop.image = $0
      }
    }
    if !sameTitle || poster.image == nil {
      let posterSize = CGSize(width: size.height * Self.posterHeightRatio * CardAspect.poster.ratio,
                              height: size.height * Self.posterHeightRatio)
      load([URL(string: card.posterURL)], size: posterSize) { [weak self] in
        self?.poster.image = $0
      }
    }
    if let logoURL = feature.logoURL, !sameTitle || logo.image == nil {
      load([logoURL], size: .zero) { [weak self] in
        self?.showLogo($0)
      }
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

  // MARK: - Meta

  /// The words after the scores: season count for a series, then one genre.
  private static func metaParts(for card: MediaCard) -> [String] {
    var parts: [String] = []
    if let seasons = card.seasonsLabel, !seasons.isEmpty { parts.append(seasons) }
    if let genre = card.genreLine?.components(separatedBy: ", ").first, !genre.isEmpty {
      parts.append(genre)
    }
    return parts
  }

  /// "[IMDb] 6.9   [КП] 7.2   3 сезона   Аниме": `MediaScoresView`'s scores (its order,
  /// logo heights and spacing; template logos in image views, which draw the vector
  /// assets reliably where text attachments did not), then the words, one gap apart.
  private func applyMeta(_ card: MediaCard, parts: [String]) {
    meta.arrangedSubviews.forEach { $0.removeFromSuperview() }
    let font = UIFont.preferredFont(forTextStyle: .caption1)
    let scores: [(MediaScoreLogo.Source, Double?, CGFloat)] = [
      (.imdb, card.scores.imdbScore, MediaScoresView.imdbHeight),
      (.kinopoisk, card.scores.kinopoiskScore, MediaScoresView.kinopoiskHeight)
    ]
    for (source, value, height) in scores {
      guard let value else { continue }
      let group = UIStackView()
      group.axis = .horizontal
      group.alignment = .center
      group.spacing = 7
      if let mark = Self.scoreLogo(source, height: height) { group.addArrangedSubview(mark) }
      let number = UILabel()
      number.font = UIFont(descriptor: font.fontDescriptor.withDesign(.rounded)?
        .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]])
        ?? font.fontDescriptor, size: 0)
      number.textColor = Self.resting
      number.text = String(format: "%.1f", value)
      group.addArrangedSubview(number)
      meta.addArrangedSubview(group)
    }
    for part in parts {
      let label = UILabel()
      label.font = font
      label.textColor = Self.resting
      label.text = part
      meta.addArrangedSubview(label)
    }
    meta.isHidden = meta.arrangedSubviews.isEmpty
  }

  /// The source's template mark at a fixed height, its width following the artwork —
  /// `MediaScoreLogo(.template)` in UIKit.
  private static func scoreLogo(_ source: MediaScoreLogo.Source, height: CGFloat) -> UIImageView? {
    guard let image = UIImage(named: source.rawValue, in: .module, compatibleWith: nil),
          image.size.height > 0 else { return nil }
    let view = UIImageView(image: image.withRenderingMode(.alwaysTemplate))
    view.tintColor = resting
    view.contentMode = .scaleAspectFit
    view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      view.heightAnchor.constraint(equalToConstant: height),
      view.widthAnchor.constraint(equalToConstant: (height * image.size.width / image.size.height).rounded())
    ])
    return view
  }

  // MARK: - Focus

  /// The cell holds focus and the card follows it as an ancestor, as in
  /// `TVPageWideCardCell`; the plot goes primary with the lift, the meta does not.
  override func didUpdateFocus(in context: UIFocusUpdateContext,
                               with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    let focused = context.nextFocusedView === self
      || context.nextFocusedView?.isDescendant(of: self) == true
    guard focused != isFocusedLook else { return }
    coordinator.addCoordinatedAnimations({ [weak self] in
      self?.applyFocusColors(focused)
    })
  }

  /// White on the art in both states (the scrims make it dark whatever the theme);
  /// secondary is the same white the system's secondary label is on dark.
  private func applyFocusColors(_ focused: Bool) {
    isFocusedLook = focused
    overviewLabel.textColor = focused ? .white : Self.resting
  }

  // MARK: - Logo

  /// The logo replaces the name; without one, the name is drawn instead.
  private func showLogo(_ image: UIImage?) {
    logo.image = image
    logo.isHidden = image == nil
    titleLabel.isHidden = image != nil
    updateLogoWidth()
  }

  /// Aspect-fit inside a box `logoHeightRatio` tall and at most `logoMaxWidthRatio`
  /// wide, pinned to the leading edge rather than centred in the box.
  private func updateLogoWidth() {
    let host = cardView.contentView.bounds.size
    guard let image = logo.image, image.size.height > 0, host.height > 0 else {
      logoWidth.constant = 0
      return
    }
    let height = host.height * Self.logoHeightRatio
    logoWidth.constant = min(height * image.size.width / image.size.height,
                             host.width * Self.logoMaxWidthRatio)
  }

  // MARK: - Images

  /// First URL that loads wins: a derived wide backdrop can 404 where the poster does not.
  private func load(_ urls: [URL?], size: CGSize, apply: @escaping @MainActor (UIImage?) -> Void) {
    let urls = urls.compactMap { $0 }
    if let hit = urls.lazy.compactMap({ TVUIKitRemoteImage.cached(url: $0, size: size) }).first {
      apply(hit)
      return
    }
    apply(nil)
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
    })
  }

  private func cancelLoads() {
    tasks.forEach { $0.cancel() }
    tasks = []
  }

  private static func font(_ style: UIFont.TextStyle, weight: UIFont.Weight) -> UIFont {
    let descriptor = UIFont.preferredFont(forTextStyle: style).fontDescriptor
      .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: weight]])
    return UIFont(descriptor: descriptor, size: 0)
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    cancelLoads()
    feature = nil
    backdrop.image = nil
    poster.image = nil
    showLogo(nil)
    titleLabel.text = nil
    overviewLabel.text = nil
    meta.arrangedSubviews.forEach { $0.removeFromSuperview() }
    accessibilityIdentifier = nil
    applyFocusColors(false)
  }
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
  var locations: [NSNumber]? {
    get { gradient.locations }
    set { gradient.locations = newValue }
  }
}
#endif
