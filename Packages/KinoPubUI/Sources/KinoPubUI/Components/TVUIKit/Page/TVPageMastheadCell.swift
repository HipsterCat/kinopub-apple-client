#if os(tvOS)
//
//  TVPageMastheadCell.swift
//  KinoPubUI
//
//  The header of a catalog page, as a cell in the same collection as the grid so the
//  two scroll together. The whole band is one focus stop: Up from the grid lands here
//  and shows the expanded detail (a person's biography, a collection's stats already
//  in the band). Entry focus still prefers the first poster — see
//  `prefersFirstPosterFocus`. The photo is an image, not a monogram lockup.
//
//  No fake focus chrome: the Focus Engine lights the cell; we do not scale or move
//  siblings to "show" focus. Biography opens under focus by growing the cell's
//  measured height — top-aligned so the bio is readable, never cropped into the
//  avatar band.
//

import TVUIKit
import UIKit

@MainActor
final class TVPageMastheadCell: UICollectionViewCell {
  static let reuseID = "TVPageMastheadCell"

  private let personRow = UIStackView()
  private let avatar = UIImageView()
  private let personText = UIStackView()
  private let nameLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let detailLabel = UILabel()
  private let bioLabel = UILabel()

  private let collectionColumn = UIStackView()
  private let symbolView = UIImageView()
  private let collectionTitle = UILabel()
  private let statsRow = UIStackView()

  private var personConstraints: [NSLayoutConstraint] = []
  private var collectionConstraints: [NSLayoutConstraint] = []

  private var imageTask: Task<Void, Never>?
  private var currentURL: URL?
  private var monogramName: String?
  private var monogramDiameter: CGFloat = 0
  private var biography: String?
  private var isPerson = true

  private static let avatarSide: CGFloat = 180

  /// The whole header is one focus stop so Up from the grid can reach person /
  /// collection detail. Select does nothing — there is no action.
  override var canBecomeFocused: Bool { true }

  override func updateConfiguration(using state: UICellConfigurationState) {
    var background = UIBackgroundConfiguration.clear()
    if state.isFocused {
      // System cell fill — the UIKit stand-in for `.buttonStyle(.card)` on a
      // header that is not a lockup. Without this, removing the 1.03 scale left
      // the collection masthead with no focus cue (plain cell, no ring).
      background.backgroundColor = .tertiarySystemFill
      background.cornerRadius = 24
      background.cornerCurve = .continuous
    }
    backgroundConfiguration = background
  }

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = true
    automaticallyUpdatesBackgroundConfiguration = true
    backgroundColor = .clear
    contentView.backgroundColor = .clear
    clipsToBounds = false
    contentView.clipsToBounds = false

    avatar.translatesAutoresizingMaskIntoConstraints = false
    avatar.contentMode = .scaleAspectFill
    avatar.clipsToBounds = true
    avatar.backgroundColor = .clear
    avatar.isUserInteractionEnabled = false
    // The floating image treatment is a focus effect. This photo is not a control.
    avatar.adjustsImageWhenAncestorFocused = false
    NSLayoutConstraint.activate([
      avatar.widthAnchor.constraint(equalToConstant: Self.avatarSide),
      avatar.heightAnchor.constraint(equalToConstant: Self.avatarSide)
    ])

    nameLabel.font = UIFont.preferredFont(forTextStyle: .title2)
    nameLabel.adjustsFontForContentSizeCategory = true
    nameLabel.textColor = .label
    nameLabel.numberOfLines = 2

    subtitleLabel.font = UIFont.preferredFont(forTextStyle: .title3)
    subtitleLabel.adjustsFontForContentSizeCategory = true
    subtitleLabel.textColor = .secondaryLabel
    subtitleLabel.numberOfLines = 2

    detailLabel.font = UIFont.preferredFont(forTextStyle: .headline)
    detailLabel.adjustsFontForContentSizeCategory = true
    detailLabel.textColor = .secondaryLabel
    detailLabel.numberOfLines = 2

    // Biography opens with focus. Empty or collapsed, it takes no space — so a late
    // metadata paint does not shove the grid under an unfocused header.
    bioLabel.font = UIFont.preferredFont(forTextStyle: .body)
    bioLabel.adjustsFontForContentSizeCategory = true
    bioLabel.textColor = .secondaryLabel
    bioLabel.numberOfLines = 0
    bioLabel.isHidden = true

    personText.axis = .vertical
    personText.alignment = .leading
    personText.spacing = 6
    for label in [nameLabel, subtitleLabel, detailLabel, bioLabel] {
      personText.addArrangedSubview(label)
    }
    personText.setCustomSpacing(12, after: detailLabel)

    // Top-aligned: when the bio opens, growth is downward into a taller cell.
    // `.center` cropped the expanded bio against the rest-height frame (and shoved
    // the name upward out of view) — the "focused header shows bio but it's invisible"
    // report on person pages.
    personRow.axis = .horizontal
    personRow.alignment = .top
    personRow.spacing = 28
    personRow.translatesAutoresizingMaskIntoConstraints = false
    personRow.addArrangedSubview(avatar)
    personRow.addArrangedSubview(personText)
    contentView.addSubview(personRow)

    symbolView.translatesAutoresizingMaskIntoConstraints = false
    symbolView.contentMode = .scaleAspectFit
    symbolView.tintColor = .secondaryLabel
    symbolView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title2)
    symbolView.backgroundColor = .clear
    NSLayoutConstraint.activate([
      symbolView.heightAnchor.constraint(equalToConstant: 44),
      symbolView.widthAnchor.constraint(equalToConstant: 44)
    ])

    collectionTitle.font = UIFont.preferredFont(forTextStyle: .title1)
    collectionTitle.adjustsFontForContentSizeCategory = true
    collectionTitle.textColor = .label
    collectionTitle.textAlignment = .center
    collectionTitle.numberOfLines = 3

    statsRow.axis = .horizontal
    statsRow.alignment = .top
    statsRow.distribution = .fillEqually
    statsRow.spacing = 28

    collectionColumn.axis = .vertical
    collectionColumn.alignment = .center
    collectionColumn.spacing = 18
    collectionColumn.translatesAutoresizingMaskIntoConstraints = false
    collectionColumn.addArrangedSubview(symbolView)
    collectionColumn.addArrangedSubview(collectionTitle)
    collectionColumn.addArrangedSubview(statsRow)
    contentView.addSubview(collectionColumn)

    personConstraints = [
      personRow.topAnchor.constraint(equalTo: contentView.topAnchor),
      personRow.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      personRow.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      personRow.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
    ]
    collectionConstraints = [
      collectionColumn.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
      collectionColumn.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      collectionColumn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
      collectionColumn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
      collectionTitle.widthAnchor.constraint(lessThanOrEqualTo: collectionColumn.widthAnchor, multiplier: 0.8),
      statsRow.widthAnchor.constraint(lessThanOrEqualTo: collectionColumn.widthAnchor)
    ]
    accessibilityIdentifier = "kinopub.masthead"
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(_ header: TVPageMasthead) {
    isPerson = header.style == .person
    personRow.isHidden = !isPerson
    collectionColumn.isHidden = isPerson
    NSLayoutConstraint.deactivate(personConstraints + collectionConstraints)
    NSLayoutConstraint.activate(isPerson ? personConstraints : collectionConstraints)

    if isPerson {
      nameLabel.text = header.title
      set(subtitleLabel, header.subtitle)
      set(detailLabel, header.detail)
      biography = header.biography?.trimmingCharacters(in: .whitespacesAndNewlines)
      if biography?.isEmpty == true { biography = nil }
      applyExpanded(isFocused, invalidate: false)
      loadAvatar(name: header.title, url: header.photoURL)
    } else {
      collectionTitle.text = header.title
      if let symbolName = header.symbolName {
        symbolView.image = UIImage(systemName: symbolName)
        symbolView.isHidden = symbolView.image == nil
      } else {
        symbolView.isHidden = true
      }
      // Stats live in the focus band itself — always part of the header, not a
      // second row that appears later and jumps the grid.
      rebuildStats(header.stats)
      applyExpanded(isFocused, invalidate: false)
      cancelImage()
    }
    accessibilityLabel = header.title
    setNeedsLayout()
  }

  override func didUpdateFocus(in context: UIFocusUpdateContext,
                               with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    let focused = context.nextFocusedView === self
      || context.nextFocusedView?.isDescendant(of: self) == true
    coordinator.addCoordinatedAnimations { [weak self] in
      self?.applyExpanded(focused, invalidate: true)
    } completion: { [weak self] in
      guard let self, focused else { return }
      self.ensureExpandedBioVisible()
    }
  }

  /// Person: biography opens with focus by growing the cell — no scale / transform
  /// fake focus. Collection: stats stay visible either way; the Focus Engine's own
  /// focus ring on the cell is the affordance.
  private func applyExpanded(_ expanded: Bool, invalidate: Bool) {
    guard isPerson else { return }
    let text = expanded ? biography : nil
    let wasHidden = bioLabel.isHidden
    set(bioLabel, text)
    if let text, !text.isEmpty {
      bioLabel.preferredMaxLayoutWidth = max(contentView.bounds.width - Self.avatarSide - 28, 200)
    }
    if invalidate, wasHidden != bioLabel.isHidden {
      invalidateIntrinsicSize()
    }
  }

  private func invalidateIntrinsicSize() {
    // Self-sizing estimated cells only remeasure when the layout is asked.
    guard let view = superview as? UICollectionView else { return }
    UIView.performWithoutAnimation {
      view.collectionViewLayout.invalidateLayout()
      view.layoutIfNeeded()
    }
  }

  /// After the bio opens, keep the expanded band on screen without moving focus off
  /// the masthead (no `scrollToItem` that re-targets preferred focus).
  private func ensureExpandedBioVisible() {
    guard isPerson, isFocused, biography != nil, !bioLabel.isHidden,
          let view = superview as? UICollectionView,
          let path = view.indexPath(for: self),
          let attributes = view.layoutAttributesForItem(at: path)
    else { return }
    let target = attributes.frame.insetBy(dx: 0, dy: -16)
    let visible = view.bounds.inset(by: view.adjustedContentInset)
    guard !visible.contains(target) else { return }
    view.scrollRectToVisible(target, animated: false)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let diameter = avatar.bounds.width
    avatar.layer.cornerRadius = diameter / 2
    if !bioLabel.isHidden {
      bioLabel.preferredMaxLayoutWidth = max(contentView.bounds.width - Self.avatarSide - 28, 200)
    }
    guard let monogramName, diameter > 1, abs(diameter - monogramDiameter) > 0.5 else { return }
    monogramDiameter = diameter
    avatar.image = TVUIKitTileArtwork.monogram(name: monogramName, diameter: diameter, traits: traitCollection)
  }

  /// Rest height is fixed so a late detail / stats paint cannot shove the grid.
  /// Only a focused person biography is allowed to grow the cell.
  override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
    let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
    let width = layoutAttributes.size.width
    let rest: CGFloat = isPerson ? 220 : (statsRow.isHidden ? 160 : 260)
    if isPerson, isFocused, biography != nil, bioLabel.isHidden == false {
      bioLabel.preferredMaxLayoutWidth = max(width - Self.avatarSide - 28, 200)
      let fitting = contentView.systemLayoutSizeFitting(
        CGSize(width: width, height: UIView.layoutFittingCompressedSize.height),
        withHorizontalFittingPriority: .required,
        verticalFittingPriority: .fittingSizeLevel
      )
      attributes.size = CGSize(width: width, height: max(ceil(fitting.height), rest))
    } else {
      attributes.size = CGSize(width: width, height: rest)
    }
    return attributes
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    cancelImage()
    monogramName = nil
    monogramDiameter = 0
    avatar.image = nil
    biography = nil
    bioLabel.text = nil
    bioLabel.isHidden = true
  }

  private func set(_ label: UILabel, _ text: String?) {
    let value = text?.trimmingCharacters(in: .whitespacesAndNewlines)
    label.text = value
    label.isHidden = value?.isEmpty != false
  }

  private func rebuildStats(_ stats: [TVPageMasthead.Stat]) {
    statsRow.arrangedSubviews.forEach {
      statsRow.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    statsRow.isHidden = stats.isEmpty
    for stat in stats {
      let value = UILabel()
      value.font = UIFont.preferredFont(forTextStyle: .title3)
      value.adjustsFontForContentSizeCategory = true
      value.textColor = .label
      value.textAlignment = .center
      value.text = stat.value
      let caption = UILabel()
      caption.font = UIFont.preferredFont(forTextStyle: .caption1)
      caption.adjustsFontForContentSizeCategory = true
      caption.textColor = .secondaryLabel
      caption.textAlignment = .center
      caption.text = stat.caption
      let column = UIStackView(arrangedSubviews: [value, caption])
      column.axis = .vertical
      column.alignment = .center
      column.spacing = 2
      statsRow.addArrangedSubview(column)
    }
  }

  private func cancelImage() {
    imageTask?.cancel()
    imageTask = nil
    currentURL = nil
  }

  private func loadAvatar(name: String, url: URL?) {
    imageTask?.cancel()
    imageTask = nil
    currentURL = url
    let cached = TVUIKitRemoteImage.cached(url: url)
    if let photo = TVUIKitPersonPhoto.displayable(cached, url: url) {
      monogramName = nil
      avatar.image = photo
      return
    }
    monogramName = name
    monogramDiameter = 0
    avatar.image = TVUIKitTileArtwork.monogram(name: name, diameter: Self.avatarSide, traits: traitCollection)
    guard let url else { return }
    imageTask = Task { [weak self] in
      let image = await TVUIKitRemoteImage.load(url: url)
      await MainActor.run {
        guard let self, !Task.isCancelled, self.currentURL == url else { return }
        if let photo = TVUIKitPersonPhoto.displayable(image, url: url) {
          self.monogramName = nil
          self.avatar.image = photo
        }
      }
    }
  }
}
#endif
