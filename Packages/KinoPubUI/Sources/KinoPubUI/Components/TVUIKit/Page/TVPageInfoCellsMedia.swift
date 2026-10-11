#if os(tvOS)
//
//  TVPageInfoCellsMedia.swift
//  KinoPubUI
//
//  The two info cards that are not text in a box: a grid of stills that opens the whole
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

/// Up to six stills in a grid that **adapts to how many there are** (Sasha, 2026-10-11) and fills
/// the platter edge to edge — the platter's rounded corners clip it. One is the whole platter, two
/// stand side by side, three are two over one wide, four two by two, five three over two wide,
/// six three over three: whichever way gives a still the shape closest to a still's own 16:9, and a
/// short last row's tiles widen to fill it.
@MainActor
final class TVPageGalleryContent: TVPageCardContent {
  static let stillCount = TVPageInfoCard.Gallery.stillCount
  private static let gap: CGFloat = 2
  private static let stillAspect: CGFloat = 16.0 / 9.0

  private let tiles: [UIImageView] = (0..<TVPageGalleryContent.stillCount).map { _ in UIImageView() }
  private var urls: [URL] = []
  private var tasks: [Task<Void, Never>?] = Array(repeating: nil, count: TVPageGalleryContent.stillCount)

  override init(frame: CGRect) {
    super.init(frame: frame)
    for tile in tiles {
      tile.contentMode = .scaleAspectFill
      tile.clipsToBounds = true
      tile.backgroundColor = UIColor.label.withAlphaComponent(0.08)
      tile.isHidden = true
      addSubview(tile)
    }
    applyFocusLook(false)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// Where each of `count` stills goes in a platter `size` big: the column count that makes a
  /// full row's tiles closest to a still's own shape, rows filled from the top, a short last row's
  /// tiles widened to fill it.
  static func frames(count: Int, in size: CGSize) -> [CGRect] {
    let count = min(max(count, 0), stillCount)
    guard count > 0, size.width > 0, size.height > 0 else { return [] }
    let gap = Self.gap
    func tile(columns: Int) -> CGSize {
      let rows = Int(ceil(Double(count) / Double(columns)))
      return CGSize(width: (size.width - gap * CGFloat(columns - 1)) / CGFloat(columns),
                    height: (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows))
    }
    // How far a tile's shape is from a still's, as a ratio either way round; the wider split wins a tie.
    func misfit(_ tile: CGSize) -> CGFloat {
      let ratio = (tile.width / tile.height) / stillAspect
      return ratio >= 1 ? ratio : 1 / ratio
    }
    let columns = (1...count).min { lhs, rhs in
      let (left, right) = (misfit(tile(columns: lhs)), misfit(tile(columns: rhs)))
      return abs(left - right) < 0.0001 ? lhs > rhs : left < right
    } ?? 1

    let rows = Int(ceil(Double(count) / Double(columns)))
    let height = (size.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
    var frames: [CGRect] = []
    for row in 0..<rows {
      let inRow = min(columns, count - row * columns)
      let width = (size.width - gap * CGFloat(inRow - 1)) / CGFloat(inRow)
      for column in 0..<inRow {
        frames.append(CGRect(x: CGFloat(column) * (width + gap), y: CGFloat(row) * (height + gap),
                             width: width, height: height))
      }
    }
    return frames
  }

  func configure(_ gallery: TVPageInfoCard.Gallery, artSize: CGSize) {
    urls = Array(gallery.images.prefix(Self.stillCount))
    let frames = Self.frames(count: urls.count, in: artSize)
    for index in tiles.indices { load(index, size: frames.indices.contains(index) ? frames[index].size : .zero) }
    setNeedsLayout()
  }

  private func load(_ index: Int, size: CGSize) {
    tasks[index]?.cancel()
    tasks[index] = nil
    guard urls.indices.contains(index), size != .zero else {
      tiles[index].image = nil
      return
    }
    let url = urls[index]
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
      tiles[index].isHidden = true
    }
    urls = []
  }

  override func applyFocusLook(_ focused: Bool) {}

  override func layoutSubviews() {
    super.layoutSubviews()
    let frames = Self.frames(count: urls.count, in: bounds.size)
    for (index, tile) in tiles.enumerated() {
      tile.isHidden = !frames.indices.contains(index)
      if frames.indices.contains(index) { tile.frame = frames[index] }
    }
  }
}

// MARK: - Specifications

/// An item of the table: **borderless** (Sasha, 2026-10-11) — no platter, no white. At rest it is
/// text on the page; **only an item that does something on Select can take focus** (Audio, Subtitles,
/// *Show all*), and under focus a quiet translucent plate comes up behind its words and the
/// secondary ones go primary. No lift, no tilt: the words do not move.
@MainActor
final class TVPageSpecCell: UICollectionViewCell {
  private let highlight = UIView()
  private let body = TVPageSpecContent()
  private var isActionable = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    clipsToBounds = false
    contentView.clipsToBounds = false
    highlight.backgroundColor = UIColor.white.withAlphaComponent(0.16)
    highlight.layer.cornerRadius = TVPagePlatter.cornerRadius
    highlight.layer.cornerCurve = .continuous
    highlight.alpha = 0
    for view in [highlight, body] {
      view.translatesAutoresizingMaskIntoConstraints = false
      contentView.addSubview(view)
      NSLayoutConstraint.activate([
        view.topAnchor.constraint(equalTo: contentView.topAnchor),
        view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
        view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
      ])
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var canBecomeFocused: Bool { isActionable }

  func configure(_ spec: TVPageInfoCard.Spec) {
    isActionable = spec.opensInPopup
    body.configure(spec)
    accessibilityIdentifier = "kinopub.spec.\(spec.id)"
    accessibilityLabel = ((spec.showsHeader ? [spec.title] : []) + spec.rows.map(\.text)).joined(separator: ", ")
    accessibilityTraits = isActionable ? .button : .staticText
  }

  override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    let focused = context.nextFocusedView === self
    coordinator.addCoordinatedAnimations({ [weak self] in
      self?.highlight.alpha = focused ? 1 : 0
      self?.body.applyFocusLook(focused)
    })
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    highlight.alpha = 0
    body.applyFocusLook(false)
    accessibilityIdentifier = nil
    accessibilityLabel = nil
  }
}

/// One item of the table: a header when it has one (Audio, Subtitles) and its rows — the languages
/// and what dubs them, the resolution, a runtime, a list of genres. **Every label is body, regular**
/// (Sasha, 2026-10-11); the header and the captions are secondary. A row is one line and truncates —
/// except words (a list of genres, of names, a dub's studios), which wrap onto as many lines as
/// they need and are never cut. A card's height is therefore a function of its rows and its width
/// (`height(for:cardWidth:)`), and the layout can reserve it before a single cell exists.
@MainActor
final class TVPageSpecContent: UIView {
  private let iconView = UIImageView()
  private let titleLabel = UILabel()
  private var rowViews: [TVPageSpecRowView] = []
  private var rows: [TVPageInfoCard.Spec.Row] = []
  private var showsHeader = true
  private var verticalPad: CGFloat = TVPageSpecContent.blockPadding
  private var looksFocused = false

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    titleLabel.font = Self.titleFont
    titleLabel.adjustsFontForContentSizeCategory = true
    iconView.contentMode = .scaleAspectFit
    addSubview(iconView)
    addSubview(titleLabel)
    applyFocusLook(false)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  /// Every label of the table: body, regular.
  static var titleFont: UIFont { TVPageFonts.font(.body, weight: .regular) }

  /// Between a card's text and the edge: the same on every side of a block (Audio, Subtitles —
  /// things that are pressed), where the air between two blocks is right as it is.
  static let blockPadding: CGFloat = TVPageCardContent.padding
  /// Above and below an item that is only read — a type, a year, a runtime — half what a block has
  /// between its words and the next (Sasha, 2026-10-11): the sides stay, so the words line up.
  static let itemVerticalPadding: CGFloat = 11

  private static func verticalPadding(for spec: TVPageInfoCard.Spec) -> CGFloat {
    spec.opensInPopup ? blockPadding : itemVerticalPadding
  }

  func configure(_ spec: TVPageInfoCard.Spec) {
    showsHeader = spec.showsHeader
    verticalPad = Self.verticalPadding(for: spec)
    iconView.image = UIImage(systemName: spec.symbol,
                             withConfiguration: UIImage.SymbolConfiguration(textStyle: .body, scale: .medium))
    titleLabel.text = spec.title
    iconView.isHidden = !spec.showsHeader
    titleLabel.isHidden = !spec.showsHeader
    rows = spec.rows
    while rowViews.count < rows.count {
      let view = TVPageSpecRowView()
      addSubview(view)
      rowViews.append(view)
    }
    while rowViews.count > rows.count { rowViews.removeLast().removeFromSuperview() }
    for (view, row) in zip(rowViews, rows) { view.configure(row) }
    applyFocusLook(looksFocused)
    setNeedsLayout()
  }

  /// Quiet: the words never invert (there is no white plate to be dark on). Under focus the
  /// secondary ones come up to primary.
  func applyFocusLook(_ focused: Bool) {
    looksFocused = focused
    let primary = UIColor.label
    let secondary: UIColor = focused ? .label : .secondaryLabel
    titleLabel.textColor = secondary
    iconView.tintColor = secondary
    rowViews.forEach { $0.applyLook(primary: primary, secondary: secondary) }
  }

  // MARK: Geometry

  private static let headerGap: CGFloat = 18

  /// Where each row goes and how tall the card is, from the rows and the width they have.
  static func plan(for rows: [TVPageInfoCard.Spec.Row], width: CGFloat, showsHeader: Bool = true,
                   verticalPadding: CGFloat = blockPadding) -> (header: CGFloat, frames: [CGRect], height: CGFloat) {
    let header = ceil(titleFont.lineHeight)
    var y = verticalPadding + (showsHeader ? header + headerGap : 0)
    var previous: TVPageInfoCard.Spec.Row.Style?
    var frames: [CGRect] = []
    for row in rows {
      y += TVPageSpecRowView.gap(before: row.style, after: previous)
      let height = TVPageSpecRowView.height(for: row, width: width)
      frames.append(CGRect(x: 0, y: y, width: 0, height: height))
      y += height
      previous = row.style
    }
    return (header, frames, ceil(y + verticalPadding))
  }

  /// How tall a card with these rows is, `cardWidth` wide.
  static func height(for spec: TVPageInfoCard.Spec, cardWidth: CGFloat) -> CGFloat {
    plan(for: spec.rows, width: max(cardWidth - TVPageCardContent.padding * 2, 1), showsHeader: spec.showsHeader,
         verticalPadding: verticalPadding(for: spec)).height
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let side = TVPageCardContent.padding
    let width = max(bounds.width - side * 2, 1)
    let plan = Self.plan(for: rows, width: width, showsHeader: showsHeader, verticalPadding: verticalPad)
    let iconSide = ceil(Self.titleFont.lineHeight)
    iconView.frame = CGRect(x: side, y: verticalPad, width: iconSide, height: plan.header)
    titleLabel.frame = CGRect(x: side + iconSide + 12, y: verticalPad,
                              width: max(width - iconSide - 12, 0), height: plan.header)
    for (view, frame) in zip(rowViews, plan.frames) {
      view.frame = CGRect(x: side, y: frame.minY, width: width, height: frame.height)
    }
  }
}

/// One row of an item of the table.
@MainActor
final class TVPageSpecRowView: UIView {
  private let leadingSymbol = UIImageView()
  private let textLabel = UILabel()
  private let secondaryLabel = UILabel()
  private var badgeLabels: [UILabel] = []
  private var row: TVPageInfoCard.Spec.Row?
  private var primary = UIColor.label
  private var secondary = UIColor.secondaryLabel

  override init(frame: CGRect) {
    super.init(frame: frame)
    leadingSymbol.contentMode = .scaleAspectFit
    for label in [textLabel, secondaryLabel] {
      label.adjustsFontForContentSizeCategory = true
      label.lineBreakMode = .byTruncatingTail
      addSubview(label)
    }
    addSubview(leadingSymbol)
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // MARK: Metrics

  /// Every label of the table is body, regular (Sasha, 2026-10-11) — captions and notes differ
  /// from values in colour, not in size.
  static func font(for style: TVPageInfoCard.Spec.Row.Style) -> UIFont {
    TVPageFonts.font(.body, weight: .regular)
  }

  static func height(for style: TVPageInfoCard.Spec.Row.Style) -> CGFloat {
    ceil(font(for: style).lineHeight) + (style == .value || style == .language ? 4 : 2)
  }

  /// Words — a value, a dub's studios — wrap onto as many lines as they need, and are never cut.
  /// A row with marks after it (`4K`) or a note beside it keeps to one line, which they share.
  static func wraps(_ row: TVPageInfoCard.Spec.Row) -> Bool {
    (row.style == .value || row.style == .detail) && row.badges.isEmpty && row.secondary == nil
  }

  /// What lays words out the way a row's own label does, so the height reserved for them is the
  /// height they take.
  private static let probe = UILabel()

  /// How tall a row is in a card `width` wide: its style's one line, or the lines its words need.
  static func height(for row: TVPageInfoCard.Spec.Row, width: CGFloat) -> CGFloat {
    let single = height(for: row.style)
    guard wraps(row) else { return single }
    probe.font = font(for: row.style)
    probe.numberOfLines = 0
    probe.lineBreakMode = .byWordWrapping
    probe.setUnhyphenated(row.text)
    let room = max(width - leadingWidth(of: row), 1)
    return max(single, ceil(probe.sizeThatFits(CGSize(width: room, height: .greatestFiniteMagnitude)).height) + 4)
  }

  /// What a row's symbol takes before its words, with the air after it.
  private static func leadingWidth(of row: TVPageInfoCard.Spec.Row) -> CGFloat {
    switch row.leading {
    case .symbol?: return ceil(font(for: row.style).lineHeight) + 12
    case nil: return 0
    }
  }

  /// Air above a row: a caption starting a new pair and a language starting a new block stand
  /// apart; a detail hugs the language above it.
  static func gap(before style: TVPageInfoCard.Spec.Row.Style, after previous: TVPageInfoCard.Spec.Row.Style?) -> CGFloat {
    guard previous != nil else { return 0 }
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
    if Self.wraps(row) {
      textLabel.numberOfLines = 0
      textLabel.lineBreakMode = .byWordWrapping
    } else {
      textLabel.numberOfLines = 1
      textLabel.lineBreakMode = .byTruncatingTail
      textLabel.attributedText = nil
      textLabel.text = row.text
    }
    secondaryLabel.font = font
    secondaryLabel.text = row.secondary
    secondaryLabel.isHidden = row.secondary == nil

    switch row.leading {
    case .symbol(let name)?:
      leadingSymbol.image = UIImage(systemName: name,
                                    withConfiguration: UIImage.SymbolConfiguration(font: font, scale: .small))
      leadingSymbol.isHidden = false
    case nil:
      leadingSymbol.isHidden = true
    }

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
    applyLook(primary: primary, secondary: secondary)
    setNeedsLayout()
  }

  func applyLook(primary: UIColor, secondary: UIColor) {
    self.primary = primary
    self.secondary = secondary
    switch row?.style {
    case .caption, .detail, .more:
      textLabel.textColor = secondary
    default:
      textLabel.textColor = primary
    }
    leadingSymbol.tintColor = secondary
    secondaryLabel.textColor = secondary
    // Words that wrap are attributed (no hyphen inside a Russian word), and the colour is
    // read from the label when they are set.
    if let row, Self.wraps(row) { textLabel.setUnhyphenated(row.text) }
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

    if !leadingSymbol.isHidden {
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
    let secondaryWidth = secondaryLabel.isHidden ? 0 : min(secondaryLabel.sizeThatFits(CGSize(width: 400, height: height)).width, bounds.width * 0.45) + 14
    let available = max(bounds.width - x - badgesWidth - secondaryWidth, 0)
    let textWidth = Self.wraps(row)
      ? available
      : min(ceil(textLabel.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: height)).width), available)
    textLabel.frame = CGRect(x: x, y: 0, width: textWidth, height: height)
    x = textLabel.frame.maxX

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
