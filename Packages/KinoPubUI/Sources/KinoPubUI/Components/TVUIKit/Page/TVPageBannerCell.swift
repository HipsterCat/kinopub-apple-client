#if os(tvOS)
//
//  TVPageBannerCell.swift
//  KinoPubUI
//
//  The Home banner: a `TVCardView` platter, like the wide card, so the lift, tilt and
//  focus motion are the system's. Everything drawn is inside the card's `contentView`:
//  the backdrop filling it, a scrim under the words, the title logo (or the name when
//  there is no logo), the plot, one meta line and the poster inset at the trailing
//  edge. No focus code of ours: the words sit on the art, so they do not recolour.
//

import TVUIKit
import UIKit

@MainActor
final class TVPageBannerCell: UICollectionViewCell {
  private let cardView = TVCardView()
  private let backdrop = UIImageView()
  private let scrim = CAGradientLayer()
  private let poster = UIImageView()
  private let logo = UIImageView()
  private let titleLabel = UILabel()
  private let overviewLabel = UILabel()
  private let metaLabel = UILabel()
  private var logoWidth: NSLayoutConstraint!

  private var tasks: [Task<Void, Never>] = []
  private var feature: TVPageFeature?

  private static let cornerRadius: CGFloat = 20
  private static let padding: CGFloat = 32
  private static let posterCornerRadius: CGFloat = 10
  /// The poster's share of the platter's height, and the logo's box.
  private static let posterHeightRatio: CGFloat = 0.42
  private static let logoHeightRatio: CGFloat = 0.24
  private static let logoMaxWidthRatio: CGFloat = 0.5

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

    // Dark under the words at the bottom and behind the logo at the top; clear across
    // the middle, where the art's subject usually is.
    scrim.colors = [UIColor.black.withAlphaComponent(0.35).cgColor,
                    UIColor.clear.cgColor,
                    UIColor.clear.cgColor,
                    UIColor.black.withAlphaComponent(0.8).cgColor]
    scrim.locations = [0, 0.3, 0.45, 1]
    host.layer.addSublayer(scrim)

    logo.translatesAutoresizingMaskIntoConstraints = false
    logo.contentMode = .scaleAspectFit
    host.addSubview(logo)

    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = Self.font(.title2, weight: .bold)
    titleLabel.textColor = .white
    titleLabel.numberOfLines = 2
    host.addSubview(titleLabel)

    overviewLabel.font = UIFont.preferredFont(forTextStyle: .callout)
    overviewLabel.textColor = UIColor.white.withAlphaComponent(0.9)
    overviewLabel.numberOfLines = 3
    metaLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
    metaLabel.textColor = UIColor.white.withAlphaComponent(0.7)
    metaLabel.numberOfLines = 1
    let text = UIStackView(arrangedSubviews: [overviewLabel, metaLabel])
    text.axis = .vertical
    text.spacing = 12
    text.translatesAutoresizingMaskIntoConstraints = false
    host.addSubview(text)
    for label in [titleLabel, overviewLabel, metaLabel] {
      label.adjustsFontForContentSizeCategory = true
    }

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

      logo.topAnchor.constraint(equalTo: host.topAnchor, constant: pad),
      logo.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: pad),
      logo.heightAnchor.constraint(equalTo: host.heightAnchor, multiplier: Self.logoHeightRatio),
      logoWidth,

      titleLabel.topAnchor.constraint(equalTo: host.topAnchor, constant: pad),
      titleLabel.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: pad),
      titleLabel.widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor, multiplier: 0.6),

      poster.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -pad),
      poster.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -pad),
      poster.heightAnchor.constraint(equalTo: host.heightAnchor, multiplier: Self.posterHeightRatio),
      poster.widthAnchor.constraint(equalTo: poster.heightAnchor, multiplier: CardAspect.poster.ratio),

      text.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: pad),
      text.trailingAnchor.constraint(equalTo: poster.leadingAnchor, constant: -pad),
      text.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -pad)
    ])
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func layoutSubviews() {
    super.layoutSubviews()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    scrim.frame = cardView.contentView.bounds
    CATransaction.commit()
    updateLogoWidth()
  }

  /// The card view sizes its platter from `contentSize`; the recipe holds the content
  /// size whose resting platter lands on the HIG column (`TVPageCellMetrics`).
  func apply(recipe: TVPageCellRecipe) {
    if cardView.contentSize != recipe.posterContentSize {
      cardView.contentSize = recipe.posterContentSize
    }
  }

  func configure(feature: TVPageFeature) {
    let card = feature.card
    self.feature = feature
    titleLabel.text = card.title
    overviewLabel.text = card.overview?.trimmingCharacters(in: .whitespacesAndNewlines)
    overviewLabel.isHidden = overviewLabel.text?.isEmpty ?? true
    metaLabel.text = Self.meta(for: card)
    metaLabel.isHidden = metaLabel.text == nil
    accessibilityIdentifier = "kinopub.banner.\(card.id)"
    cardView.accessibilityLabel = [card.title, card.overview, metaLabel.text].compactMap { $0 }
      .joined(separator: ", ")

    cancelLoads()
    showLogo(nil)
    let size = cardView.contentSize
    load([URL(string: card.backdropImageURL), URL(string: card.posterURL)], size: size) { [weak self] in
      self?.backdrop.image = $0
    }
    let posterSize = CGSize(width: size.height * Self.posterHeightRatio * CardAspect.poster.ratio,
                            height: size.height * Self.posterHeightRatio)
    load([URL(string: card.posterURL)], size: posterSize) { [weak self] in
      self?.poster.image = $0
    }
    if let logoURL = feature.logoURL {
      load([logoURL], size: .zero) { [weak self] in
        self?.showLogo($0)
      }
    }
  }

  /// "IMDb 6.5  КП 6.3  Триллер  1 ч 40 мин" — the scores the title has, its first
  /// genre, and the running time (a series has none; its year stands in).
  private static func meta(for card: MediaCard) -> String? {
    var parts: [String] = []
    if let imdb = card.scores.imdb, imdb > 0 { parts.append("IMDb \(String(format: "%.1f", imdb))") }
    if let kp = card.scores.kinopoisk, kp > 0 { parts.append("КП \(String(format: "%.1f", kp))") }
    if let genre = card.genreLine?.split(separator: ",").first {
      parts.append(genre.trimmingCharacters(in: .whitespaces))
    }
    if let duration = card.durationLabel {
      parts.append(duration)
    } else if let year = card.year {
      parts.append(String(year))
    }
    return parts.isEmpty ? nil : parts.joined(separator: "\u{2003}")
  }

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
    metaLabel.text = nil
    accessibilityIdentifier = nil
  }
}
#endif
