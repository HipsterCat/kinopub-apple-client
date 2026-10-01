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

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = true
    automaticallyUpdatesBackgroundConfiguration = false
    backgroundConfiguration = .clear()
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
    bioLabel.numberOfLines = 8
    bioLabel.isHidden = true

    personText.axis = .vertical
    personText.alignment = .leading
    personText.spacing = 6
    for label in [nameLabel, subtitleLabel, detailLabel, bioLabel] {
      personText.addArrangedSubview(label)
    }
    personText.setCustomSpacing(12, after: detailLabel)

    personRow.axis = .horizontal
    personRow.alignment = .center
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
    }
  }

  /// Person: biography opens with focus. Collection: a light scale so the band reads
  /// as the focused stop; stats stay visible either way. Both scale slightly so Up
  /// from the grid into this band is visible.
  private func applyExpanded(_ expanded: Bool, invalidate: Bool) {
    let scale: CGFloat = expanded ? 1.03 : 1
    if isPerson {
      let text = expanded ? biography : nil
      let wasHidden = bioLabel.isHidden
      set(bioLabel, text)
      personRow.transform = CGAffineTransform(scaleX: scale, y: scale)
      if invalidate, wasHidden != bioLabel.isHidden {
        invalidateIntrinsicSize()
      }
    } else {
      collectionColumn.transform = CGAffineTransform(scaleX: scale, y: scale)
      statsRow.alpha = 1
    }
  }

  private func invalidateIntrinsicSize() {
    // Self-sizing estimated cells only remeasure when the layout is asked.
    if let view = superview as? UICollectionView {
      UIView.performWithoutAnimation {
        view.collectionViewLayout.invalidateLayout()
      }
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let diameter = avatar.bounds.width
    avatar.layer.cornerRadius = diameter / 2
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
    personRow.transform = .identity
    collectionColumn.transform = .identity
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
