#if os(tvOS)
//
//  TVUIKitSeasonCardCell.swift
//  KinoPubUI
//
//  A season's portrait card in front of its episodes on the title page's rail
//  (`TVUIKitMediaItem.seasonCard`, Sasha 2026-11-09). The episodes are the system's wide
//  media-item cell; this one is the poster alone, as tall as the stills beside it, with no
//  words on or under it (Sasha, 2026-11-10: the card is a picture, the menu says the rest).
//
//  It takes focus so it has a context menu and Select folds its season
//  (`TVUIKitMediaItemRail`). The focus lift is the system's own image effect
//  (`adjustsImageWhenAncestorFocused`) on art that carries its own rounding: the effect
//  floats the bitmap, so a layer's corner radius would not follow it, and
//  `masksFocusEffectToContents` keeps the sheen inside the rounded corners. Every bitmap
//  goes through `TVUIKitTileArtwork.render` (32-bit BGRA), the format the effect reads.
//

import UIKit
import TVUIKit

@MainActor
final class TVUIKitSeasonCardCell: UICollectionViewCell {
  static let reuseID = "TVUIKitSeasonCardCell"

  private let posterView = UIImageView()
  private var card: TVUIKitMediaItem.SeasonCard?
  private var imageTask: Task<Void, Never>?
  /// The card whose poster is on screen or on its way, and the size it was drawn at.
  private var loadingFor: TVUIKitMediaItem.SeasonCard?
  private var drawnSize: CGSize = .zero

  var tileAlpha: CGFloat = 1 {
    didSet { contentView.alpha = tileAlpha }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = false
    contentView.clipsToBounds = false

    posterView.contentMode = .scaleToFill
    posterView.clipsToBounds = false
    posterView.adjustsImageWhenAncestorFocused = true
    posterView.masksFocusEffectToContents = true
    contentView.addSubview(posterView)

    isAccessibilityElement = true
    accessibilityTraits = [.header, .button]
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var canBecomeFocused: Bool { true }

  /// As round as a still would be at this width: the still's radius scaled down.
  private static var cornerRadius: CGFloat {
    TVUIKitMediaItemCell.stillCornerRadius * CardAspect.poster.ratio / CardAspect.landscape.ratio
  }

  func configure(_ card: TVUIKitMediaItem.SeasonCard, id: Int) {
    let reload = loadingFor?.posterURL != card.posterURL
      || loadingFor?.fallbackPosterURL != card.fallbackPosterURL
    self.card = card
    accessibilityIdentifier = "kinopub.rail.season.\(id)"
    accessibilityLabel = ([card.captions.first] + [card.chips.first]).compactMap { $0 }.joined(separator: ", ")
    if reload { drawnSize = .zero }
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    posterView.frame = contentView.bounds
    // The art is drawn at the card's size; a new size (or a new card) draws it again.
    let size = contentView.bounds.size
    guard let card, size.width > 0, size.height > 0, size != drawnSize else { return }
    drawnSize = size
    posterView.image = TVUIKitTileArtwork.placeholder(size: size, cornerRadius: Self.cornerRadius,
                                                      traits: traitCollection)
    loadPoster(card, size: size)
  }

  /// `image` filling `size` (centre crop), its corners cut, in the focus effect's format.
  private static func rounded(_ image: UIImage, size: CGSize) -> UIImage {
    let source = image.size
    guard source.width > 0, source.height > 0 else { return image }
    let scale = max(size.width / source.width, size.height / source.height)
    let drawn = CGSize(width: source.width * scale, height: source.height * scale)
    let frame = CGRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                       width: drawn.width, height: drawn.height)
    return TVUIKitTileArtwork.render(size: size) { _ in
      UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: cornerRadius).addClip()
      image.draw(in: frame)
    }
  }

  private func loadPoster(_ card: TVUIKitMediaItem.SeasonCard, size: CGSize) {
    imageTask?.cancel()
    loadingFor = card
    let urls = [card.posterURL, card.fallbackPosterURL].compactMap { $0 }
    if let first = urls.first, let hit = TVUIKitRemoteImage.cached(url: first, size: size) {
      posterView.image = Self.rounded(hit, size: size)
      return
    }
    imageTask = Task { [weak self] in
      // The worker's season poster, then TMDB's when the worker has none (it answers 404).
      for url in urls {
        let image = await TVUIKitRemoteImage.load(url: url, size: size)
        guard let self, !Task.isCancelled, self.loadingFor == card, self.drawnSize == size else { return }
        if let image {
          self.posterView.image = Self.rounded(image, size: size)
          return
        }
      }
    }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    imageTask?.cancel()
    imageTask = nil
    card = nil
    loadingFor = nil
    drawnSize = .zero
    posterView.image = nil
    tileAlpha = 1
  }
}
#endif
