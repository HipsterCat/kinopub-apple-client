#if os(tvOS)
//
//  TVUIKitSeasonCardCell.swift
//  KinoPubUI
//
//  A season's portrait card in front of its episodes on the title page's rail
//  (`TVUIKitMediaItem.seasonCard`, Sasha 2026-11-09). The episodes are the system's wide
//  media-item cell; this one is not focusable — a heading for the run after it, the way
//  the season tabs head the rail — so it draws itself: the poster as tall as the stills
//  beside it, the episode count in the stills' runtime pill, and the one line under the
//  art in the stills' own caption type and place.
//

import UIKit
import TVUIKit

@MainActor
final class TVUIKitSeasonCardCell: UICollectionViewCell {
  static let reuseID = "TVUIKitSeasonCardCell"

  private let posterView = UIImageView()
  private let chip = UIView()
  private let chipLabel = UILabel()
  private let captionLabel = UILabel()
  private var card: TVUIKitMediaItem.SeasonCard?
  private var imageTask: Task<Void, Never>?
  /// The card whose poster is on screen or on its way.
  private var loadingFor: TVUIKitMediaItem.SeasonCard?

  /// The stills' runtime pill (`TVUIKitMediaItemOverlayView`): height, inset, fill.
  private static let chipHeight: CGFloat = 32
  private static let chipInset: CGFloat = 8
  private static let chipPadding: CGFloat = 10
  private static let chipFill = UIColor.black.withAlphaComponent(0.36)
  /// Between the art and the line under it — the wide cell's, measured on tvOS 27.2
  /// (`TVPageCellMetrics.stillTextBlock`: 9 pt gap + 39 pt label).
  private static let captionGap: CGFloat = 9
  private static let captionHeight: CGFloat = 39

  /// The wide cell's caption: its type and alignment, read off the system configuration
  /// rather than restated.
  private static let captionText = TVMediaItemContentConfiguration.wideCell().textProperties

  var tileAlpha: CGFloat = 1 {
    didSet { contentView.alpha = tileAlpha }
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = false
    contentView.clipsToBounds = false

    posterView.contentMode = .scaleAspectFill
    posterView.clipsToBounds = true
    posterView.layer.cornerCurve = .continuous
    contentView.addSubview(posterView)

    chip.backgroundColor = Self.chipFill
    chip.layer.cornerCurve = .continuous
    chipLabel.font = .preferredFont(forTextStyle: .caption2)
    chipLabel.textColor = .white
    chip.addSubview(chipLabel)
    contentView.addSubview(chip)

    captionLabel.font = Self.captionText.font
    captionLabel.textColor = .secondaryLabel
    captionLabel.numberOfLines = 1
    captionLabel.lineBreakMode = .byTruncatingTail
    contentView.addSubview(captionLabel)

    isAccessibilityElement = true
    accessibilityTraits = .header
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var canBecomeFocused: Bool { false }

  func configure(_ card: TVUIKitMediaItem.SeasonCard, id: Int) {
    let reload = loadingFor?.posterURL != card.posterURL
      || loadingFor?.fallbackPosterURL != card.fallbackPosterURL
    self.card = card
    accessibilityIdentifier = "kinopub.rail.season.\(id)"
    accessibilityLabel = ([card.captions.first] + [card.chips.first]).compactMap { $0 }.joined(separator: ", ")
    if reload {
      posterView.image = TVUIKitTileArtwork.placeholder(traits: traitCollection)
      loadPoster(card)
    }
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let art = contentView.bounds
    posterView.frame = art
    // As round as a still would be at this width: the still's radius scaled down.
    posterView.layer.cornerRadius = TVUIKitMediaItemCell.stillCornerRadius
      * CardAspect.poster.ratio / CardAspect.landscape.ratio

    let room = art.width - Self.chipInset * 2
    let chipText = Self.firstFitting(card?.chips ?? [], font: chipLabel.font,
                                     width: room - Self.chipPadding * 2)
    chipLabel.text = chipText
    chip.isHidden = chipText == nil
    if let chipText {
      let textWidth = (chipText as NSString).size(withAttributes: [.font: chipLabel.font as Any]).width.rounded(.up)
      let width = min(textWidth + Self.chipPadding * 2, room)
      chip.frame = CGRect(x: art.maxX - Self.chipInset - width,
                          y: art.maxY - Self.chipInset - Self.chipHeight,
                          width: width, height: Self.chipHeight)
      chip.layer.cornerRadius = Self.chipHeight / 2
      chipLabel.frame = chip.bounds.insetBy(dx: Self.chipPadding, dy: 0)
    }

    captionLabel.textAlignment = Self.alignment
    captionLabel.text = Self.firstFitting(card?.captions ?? [], font: captionLabel.font, width: art.width)
      ?? card?.captions.last
    captionLabel.frame = CGRect(x: art.minX, y: art.maxY + Self.captionGap,
                                width: art.width, height: Self.captionHeight)
  }

  /// The first candidate that fits `width` on one line in `font`.
  private static func firstFitting(_ candidates: [String], font: UIFont, width: CGFloat) -> String? {
    candidates.first { ($0 as NSString).size(withAttributes: [.font: font]).width <= width }
  }

  private static var alignment: NSTextAlignment {
    switch captionText.alignment {
    case .center: .center
    case .justified: .justified
    default: .natural
    }
  }

  private func loadPoster(_ card: TVUIKitMediaItem.SeasonCard) {
    imageTask?.cancel()
    loadingFor = card
    let size = contentView.bounds.size
    let urls = [card.posterURL, card.fallbackPosterURL].compactMap { $0 }
    if let first = urls.first, let hit = TVUIKitRemoteImage.cached(url: first, size: size) {
      posterView.image = hit
      return
    }
    imageTask = Task { [weak self] in
      // The worker's season poster, then TMDB's when the worker has none (it answers 404).
      for url in urls {
        let image = await TVUIKitRemoteImage.load(url: url, size: size)
        guard let self, !Task.isCancelled, self.loadingFor == card else { return }
        if let image {
          self.posterView.image = image
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
    posterView.image = nil
    tileAlpha = 1
  }
}
#endif
