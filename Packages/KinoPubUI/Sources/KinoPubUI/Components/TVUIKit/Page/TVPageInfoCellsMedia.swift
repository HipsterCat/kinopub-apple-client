#if os(tvOS)
//
//  TVPageInfoCellsMedia.swift
//  KinoPubUI
//
//  The two info cards that are not text in a box: a mosaic of stills that opens the whole
//  gallery, and a column of specifications. See `TVPageInfoCells.swift` for the platter
//  they sit on.
//

import TVUIKit
import UIKit

// MARK: - Stills

@MainActor
final class TVPageGalleryCell: TVPageInfoCardCell {
  private let body = TVPageGalleryContent()

  override init(frame: CGRect) {
    super.init(frame: frame)
    install(body)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ gallery: TVPageInfoCard.Gallery, artSize: CGSize) {
    body.configure(gallery, artSize: artSize)
    accessibilityIdentifier = "kinopub.gallery.\(gallery.id)"
    accessibilityLabel = gallery.accessibilityLabel
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    body.cancelLoads()
  }
}

/// Five stills and a chevron in a 3 × 2 grid that fills the platter edge to edge — the
/// platter's rounded corners clip it. The chevron is the one cell that is not a picture:
/// it says the row is a way into more of them.
@MainActor
final class TVPageGalleryContent: TVPageCardContent {
  static let columns = 3
  static let rows = 2
  static let stillCount = TVPageInfoCard.Gallery.stillCount
  private static let gap: CGFloat = 2

  private let tiles: [UIImageView] = (0..<TVPageGalleryContent.stillCount).map { _ in UIImageView() }
  private let moreTile = UIView()
  private let chevron = UIImageView()
  private var urls: [URL] = []
  private var tasks: [Task<Void, Never>?] = Array(repeating: nil, count: TVPageGalleryContent.stillCount)
  private var decodeSize: CGSize = .zero

  override init(frame: CGRect) {
    super.init(frame: frame)
    for tile in tiles {
      tile.contentMode = .scaleAspectFill
      tile.clipsToBounds = true
      tile.backgroundColor = UIColor.label.withAlphaComponent(0.08)
      addSubview(tile)
    }
    moreTile.backgroundColor = UIColor.label.withAlphaComponent(0.06)
    chevron.contentMode = .center
    chevron.image = UIImage(systemName: "chevron.right",
                            withConfiguration: UIImage.SymbolConfiguration(textStyle: .title3, scale: .medium))
    addSubview(moreTile)
    addSubview(chevron)
    applyFocusLook(false)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// The tile a still is decoded into, from the platter's own size.
  private static func tileSize(in art: CGSize) -> CGSize {
    CGSize(width: (art.width - gap * CGFloat(columns - 1)) / CGFloat(columns),
           height: (art.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
  }

  func configure(_ gallery: TVPageInfoCard.Gallery, artSize: CGSize) {
    urls = Array(gallery.images.prefix(Self.stillCount))
    decodeSize = Self.tileSize(in: artSize)
    for index in tiles.indices { load(index) }
    setNeedsLayout()
  }

  private func load(_ index: Int) {
    tasks[index]?.cancel()
    tasks[index] = nil
    guard urls.indices.contains(index) else {
      tiles[index].image = nil
      return
    }
    let url = urls[index]
    let size = decodeSize
    if let hit = TVUIKitRemoteImage.cached(url: url, size: size) {
      tiles[index].image = hit
      return
    }
    tiles[index].image = nil
    tasks[index] = Task { [weak self] in
      let image = await TVUIKitRemoteImage.load(url: url, size: size)
      guard let self, !Task.isCancelled, self.urls.indices.contains(index),
            self.urls[index] == url, let image else { return }
      self.tiles[index].image = image
    }
  }

  func cancelLoads() {
    for index in tasks.indices {
      tasks[index]?.cancel()
      tasks[index] = nil
      tiles[index].image = nil
    }
    urls = []
  }

  override func applyFocusLook(_ focused: Bool) {
    chevron.tintColor = Self.secondaryInk(focused: focused)
    moreTile.backgroundColor = focused ? UIColor.black.withAlphaComponent(0.06) : UIColor.label.withAlphaComponent(0.06)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let gap = Self.gap
    let tile = Self.tileSize(in: bounds.size)
    for index in 0..<(Self.columns * Self.rows) {
      let column = index % Self.columns
      let row = index / Self.columns
      let frame = CGRect(x: CGFloat(column) * (tile.width + gap),
                         y: CGFloat(row) * (tile.height + gap),
                         width: tile.width, height: tile.height)
      if index < tiles.count {
        tiles[index].frame = frame
      } else {
        moreTile.frame = frame
        chevron.frame = frame
      }
    }
  }
}

// MARK: - Specifications

@MainActor
final class TVPageSpecCell: TVPageInfoCardCell {
  private let body = TVPageSpecContent()

  override init(frame: CGRect) {
    super.init(frame: frame)
    install(body)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// A column of facts reads as text on the page and gets a platter when focused.
  override var restingFill: UIColor { .clear }

  func configure(_ spec: TVPageInfoCard.Spec) {
    body.configure(spec)
    accessibilityIdentifier = "kinopub.spec.\(spec.id)"
    accessibilityLabel = ([spec.title] + spec.rows.map(\.text)).joined(separator: ", ")
  }
}

/// A titled list of rows — duration and resolution, the languages and what dubs them, the
/// subtitle languages. Rows are one line each and truncate, never wrap, so a column's
/// height is a function of its rows alone (`height(for:)`) and the layout can reserve it
/// before a single cell exists.
@MainActor
final class TVPageSpecContent: TVPageCardContent {
  private let iconView = UIImageView()
  private let titleLabel = UILabel()
  private var rowViews: [TVPageSpecRowView] = []
  private var rows: [TVPageInfoCard.Spec.Row] = []
  private var looksFocused = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    titleLabel.font = Self.titleFont
    titleLabel.adjustsFontForContentSizeCategory = true
    iconView.contentMode = .scaleAspectFit
    addSubview(iconView)
    addSubview(titleLabel)
    applyFocusLook(false)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  static var titleFont: UIFont { TVPageFonts.font(.callout, weight: .semibold) }

  func configure(_ spec: TVPageInfoCard.Spec) {
    iconView.image = UIImage(systemName: spec.symbol,
                             withConfiguration: UIImage.SymbolConfiguration(textStyle: .callout, scale: .medium))
    titleLabel.text = spec.title
    rows = spec.rows
    while rowViews.count < rows.count {
      let view = TVPageSpecRowView()
      addSubview(view)
      rowViews.append(view)
    }
    while rowViews.count > rows.count { rowViews.removeLast().removeFromSuperview() }
    for (view, row) in zip(rowViews, rows) {
      view.configure(row)
      view.applyFocusLook(looksFocused)
    }
    setNeedsLayout()
  }

  override func applyFocusLook(_ focused: Bool) {
    self.looksFocused = focused
    titleLabel.textColor = Self.ink(focused: focused)
    iconView.tintColor = Self.ink(focused: focused)
    rowViews.forEach { $0.applyFocusLook(focused) }
  }

  // MARK: Geometry

  private static let headerGap: CGFloat = 18

  /// Where each row goes and how tall the column is, from the rows alone.
  static func plan(for rows: [TVPageInfoCard.Spec.Row]) -> (header: CGFloat, frames: [CGRect], height: CGFloat) {
    let pad = padding
    let header = ceil(titleFont.lineHeight)
    var y = pad + header + headerGap
    var previous: TVPageInfoCard.Spec.Row.Style?
    var frames: [CGRect] = []
    for row in rows {
      y += TVPageSpecRowView.gap(before: row.style, after: previous)
      let height = TVPageSpecRowView.height(for: row.style)
      frames.append(CGRect(x: 0, y: y, width: 0, height: height))
      y += height
      previous = row.style
    }
    return (header, frames, ceil(y + pad))
  }

  /// How tall a column with these rows is.
  static func height(for spec: TVPageInfoCard.Spec) -> CGFloat {
    plan(for: spec.rows).height
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let pad = Self.padding
    let width = max(bounds.width - pad * 2, 1)
    let plan = Self.plan(for: rows)
    let iconSide = ceil(Self.titleFont.lineHeight)
    iconView.frame = CGRect(x: pad, y: pad, width: iconSide, height: plan.header)
    titleLabel.frame = CGRect(x: pad + iconSide + 12, y: pad,
                              width: max(width - iconSide - 12, 0), height: plan.header)
    for (view, frame) in zip(rowViews, plan.frames) {
      view.frame = CGRect(x: pad, y: frame.minY, width: width, height: frame.height)
    }
  }
}

/// One line of a specification column.
@MainActor
final class TVPageSpecRowView: UIView {
  private let leadingEmoji = UILabel()
  private let leadingSymbol = UIImageView()
  private let textLabel = UILabel()
  private let secondaryLabel = UILabel()
  private var badgeLabels: [UILabel] = []
  private let moreChevron = UIImageView()
  private var row: TVPageInfoCard.Spec.Row?
  private var looksFocused = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    leadingSymbol.contentMode = .scaleAspectFit
    moreChevron.contentMode = .scaleAspectFit
    moreChevron.image = UIImage(systemName: "chevron.down",
                                withConfiguration: UIImage.SymbolConfiguration(textStyle: .caption1, scale: .small))
    for label in [leadingEmoji, textLabel, secondaryLabel] {
      label.adjustsFontForContentSizeCategory = true
      label.lineBreakMode = .byTruncatingTail
      addSubview(label)
    }
    addSubview(leadingSymbol)
    addSubview(moreChevron)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // MARK: Metrics

  static func font(for style: TVPageInfoCard.Spec.Row.Style) -> UIFont {
    switch style {
    case .caption: return .preferredFont(forTextStyle: .caption1)
    case .value: return .preferredFont(forTextStyle: .callout)
    case .language: return TVPageFonts.font(.callout, weight: .medium)
    case .detail: return .preferredFont(forTextStyle: .caption1)
    case .more: return .preferredFont(forTextStyle: .callout)
    }
  }

  static func height(for style: TVPageInfoCard.Spec.Row.Style) -> CGFloat {
    ceil(font(for: style).lineHeight) + (style == .value || style == .language ? 4 : 2)
  }

  /// Air above a row: a caption starting a new pair, a language starting a new block and
  /// the fold line stand apart; a detail hugs the language above it.
  static func gap(before style: TVPageInfoCard.Spec.Row.Style, after previous: TVPageInfoCard.Spec.Row.Style?) -> CGFloat {
    guard let previous else { return 0 }
    switch style {
    case .caption: return 16
    case .language: return 14
    case .more: return 14
    case .value: return previous == .caption ? 0 : 8
    case .detail: return 2
    }
  }

  // MARK: Content

  func configure(_ row: TVPageInfoCard.Spec.Row) {
    self.row = row
    let font = Self.font(for: row.style)
    textLabel.font = font
    textLabel.text = row.text
    secondaryLabel.font = .preferredFont(forTextStyle: .caption1)
    secondaryLabel.text = row.secondary
    secondaryLabel.isHidden = row.secondary == nil

    switch row.leading {
    case .emoji(let emoji)?:
      leadingEmoji.font = font
      leadingEmoji.text = emoji
      leadingEmoji.isHidden = false
      leadingSymbol.isHidden = true
    case .symbol(let name)?:
      leadingSymbol.image = UIImage(systemName: name,
                                    withConfiguration: UIImage.SymbolConfiguration(font: font, scale: .small))
      leadingSymbol.isHidden = false
      leadingEmoji.isHidden = true
    case nil:
      leadingEmoji.isHidden = true
      leadingSymbol.isHidden = true
    }

    moreChevron.isHidden = row.style != .more

    while badgeLabels.count < row.badges.count {
      let badge = UILabel()
      badge.font = TVPageFonts.font(.caption2, weight: .bold)
      badge.textAlignment = .center
      badge.layer.cornerRadius = 6
      badge.layer.cornerCurve = .continuous
      badge.layer.borderWidth = 2
      badge.clipsToBounds = true
      addSubview(badge)
      badgeLabels.append(badge)
    }
    while badgeLabels.count > row.badges.count { badgeLabels.removeLast().removeFromSuperview() }
    for (label, text) in zip(badgeLabels, row.badges) { label.text = text }
    applyFocusLook(looksFocused)
    setNeedsLayout()
  }

  func applyFocusLook(_ focused: Bool) {
    self.looksFocused = focused
    let primary = TVPageCardContent.ink(focused: focused)
    let secondary = TVPageCardContent.secondaryInk(focused: focused)
    switch row?.style {
    case .caption, .detail, .more:
      textLabel.textColor = secondary
      leadingSymbol.tintColor = secondary
    default:
      textLabel.textColor = primary
      leadingSymbol.tintColor = secondary
    }
    secondaryLabel.textColor = secondary
    moreChevron.tintColor = secondary
    for badge in badgeLabels {
      badge.textColor = primary
      badge.layer.borderColor = primary.cgColor
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let row else { return }
    let height = bounds.height
    var x: CGFloat = 0

    if !leadingEmoji.isHidden {
      let size = leadingEmoji.sizeThatFits(CGSize(width: 80, height: height))
      leadingEmoji.frame = CGRect(x: 0, y: (height - size.height) / 2, width: ceil(size.width), height: size.height)
      x = ceil(size.width) + 12
    } else if !leadingSymbol.isHidden {
      let side = ceil(Self.font(for: row.style).lineHeight)
      leadingSymbol.frame = CGRect(x: 0, y: (height - side) / 2, width: side, height: side)
      x = side + 12
    }

    // Badges sit after the words and keep their own width; the words give way.
    var badgesWidth: CGFloat = 0
    var badgeSizes: [CGSize] = []
    for badge in badgeLabels {
      let size = badge.sizeThatFits(CGSize(width: 200, height: height))
      let box = CGSize(width: ceil(size.width) + 16, height: ceil(size.height) + 4)
      badgeSizes.append(box)
      badgesWidth += box.width + 10
    }
    let chevronWidth: CGFloat = moreChevron.isHidden ? 0 : 28
    let secondaryWidth = secondaryLabel.isHidden ? 0 : min(secondaryLabel.sizeThatFits(CGSize(width: 400, height: height)).width, bounds.width * 0.45) + 14
    let available = max(bounds.width - x - badgesWidth - secondaryWidth - chevronWidth, 0)
    let textWidth = min(ceil(textLabel.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: height)).width), available)
    textLabel.frame = CGRect(x: x, y: 0, width: textWidth, height: height)
    x = textLabel.frame.maxX

    if !moreChevron.isHidden {
      moreChevron.frame = CGRect(x: x + 10, y: 0, width: 18, height: height)
      x = moreChevron.frame.maxX
    }
    if !secondaryLabel.isHidden {
      secondaryLabel.frame = CGRect(x: x + 14, y: 0, width: secondaryWidth - 14, height: height)
      x = secondaryLabel.frame.maxX
    }
    for (badge, box) in zip(badgeLabels, badgeSizes) {
      badge.frame = CGRect(x: x + 10, y: (height - box.height) / 2, width: box.width, height: box.height)
      x = badge.frame.maxX
    }
  }
}
#endif
