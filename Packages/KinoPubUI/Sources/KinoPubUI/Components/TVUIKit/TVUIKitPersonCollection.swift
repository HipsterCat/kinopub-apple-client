#if os(tvOS)
//
//  TVUIKitPersonCollection.swift
//  KinoPubUI
//
//  Circular person rail. The circle is a photo, or the same initials image search
//  uses when there is no photo — not `TVMonogramContentConfiguration`. That
//  configuration paints a filled disc and a focus plate, and it has no property
//  for either (image, text, name components only). The cell stays focusable; the
//  picture does not carry a background of its own.
//

import SwiftUI
import UIKit

/// One row entry for `TVUIKitPersonCollection` — cast/crew today, any person rail later.
public struct TVUIKitPerson: Identifiable, Hashable {
  public let id: String
  public let name: String
  public let nameComponents: PersonNameComponents
  /// Character or role, shown under the name.
  public let caption: String?
  public let photoURL: URL?

  public init(id: String,
              name: String,
              nameComponents: PersonNameComponents,
              caption: String?,
              photoURL: URL?) {
    self.id = id
    self.name = name
    self.nameComponents = nameComponents
    self.caption = caption
    self.photoURL = photoURL
  }

  /// kino.pub credits are one flat string, so the split is positional: first word is
  /// the given name, the rest the family name. `TVMonogramContentConfiguration` uses
  /// these only to compose the initials it draws when there is no photo — which is why
  /// the rail and the person page must parse a name the same way, or the same person
  /// gets different initials on two screens.
  public static func nameComponents(from name: String) -> PersonNameComponents {
    var components = PersonNameComponents()
    let parts = name.split(separator: " ", omittingEmptySubsequences: true)
    components.givenName = parts.first.map(String.init)
    if parts.count > 1 {
      components.familyName = parts.dropFirst().joined(separator: " ")
    }
    return components
  }
}

public struct TVUIKitPersonCollection: UIViewControllerRepresentable {
  public let people: [TVUIKitPerson]
  public let onSelect: (TVUIKitPerson) -> Void
  /// Fired when focus lands on any cell. SwiftUI's `@Environment(\.isFocused)` does
  /// not cross into UIKit cells, so a caller that needs "this section is current"
  /// (the detail page's backdrop wash) has to be told from the focus engine directly.
  public let onCellFocused: (() -> Void)?
  public let contextMenuProvider: ((TVUIKitPerson) -> [MediaCardContextEntry])?

  public init(people: [TVUIKitPerson],
              onSelect: @escaping (TVUIKitPerson) -> Void,
              onCellFocused: (() -> Void)? = nil,
              contextMenuProvider: ((TVUIKitPerson) -> [MediaCardContextEntry])? = nil) {
    self.people = people
    self.onSelect = onSelect
    self.onCellFocused = onCellFocused
    self.contextMenuProvider = contextMenuProvider
  }

  public func makeUIViewController(context: Context) -> TVUIKitPersonCollectionController {
    let vc = TVUIKitPersonCollectionController()
    vc.apply(people: people,
             onSelect: onSelect,
             onCellFocused: onCellFocused,
             contextMenuProvider: contextMenuProvider)
    return vc
  }

  public func updateUIViewController(_ vc: TVUIKitPersonCollectionController, context: Context) {
    vc.apply(people: people,
             onSelect: onSelect,
             onCellFocused: onCellFocused,
             contextMenuProvider: contextMenuProvider)
  }
}

@MainActor
public final class TVUIKitPersonCollectionController: UIViewController {
  private var people: [TVUIKitPerson] = []
  private var onSelect: ((TVUIKitPerson) -> Void)?
  private var onCellFocused: (() -> Void)?
  private var contextMenuProvider: ((TVUIKitPerson) -> [MediaCardContextEntry])?

  private lazy var collectionView: UICollectionView = {
    let layout = UICollectionViewFlowLayout()
    layout.scrollDirection = .horizontal
    layout.minimumLineSpacing = Self.spacing
    layout.minimumInteritemSpacing = Self.spacing
    layout.itemSize = Self.itemSize
    layout.sectionInset = UIEdgeInsets(top: Self.focusRoom,
                                       left: Self.inset,
                                       bottom: Self.focusRoom,
                                       right: Self.inset)
    let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
    view.backgroundColor = .clear
    view.showsHorizontalScrollIndicator = false
    view.remembersLastFocusedIndexPath = true
    view.clipsToBounds = false
    view.dataSource = self
    view.delegate = self
    view.prefetchDataSource = self
    view.register(TVUIKitPersonCell.self, forCellWithReuseIdentifier: TVUIKitPersonCell.reuseID)
    view.accessibilityIdentifier = "cast-rail"
    return view
  }()

  /// Reported once per layout pass so the "edge cells are clipped / the next card only
  /// loads on focus" question has measurements behind it rather than screenshots.
  public override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    FocusLog.railGeometry(collectionView, section: "cast-rail")
  }

  public override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear
    view.clipsToBounds = false
    collectionView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(collectionView)
    NSLayoutConstraint.activate([
      collectionView.topAnchor.constraint(equalTo: view.topAnchor),
      collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
    ])
  }

  func apply(people: [TVUIKitPerson],
             onSelect: @escaping (TVUIKitPerson) -> Void,
             onCellFocused: (() -> Void)?,
             contextMenuProvider: ((TVUIKitPerson) -> [MediaCardContextEntry])?) {
    let changed = self.people.map(\.id) != people.map(\.id)
    self.people = people
    self.onSelect = onSelect
    self.onCellFocused = onCellFocused
    self.contextMenuProvider = contextMenuProvider
    if changed {
      collectionView.reloadData()
    }
  }

  /// Circle + two lines of text under it — sized generously (native TVUIKit monogram
  /// cells read small at portrait-poster scale); proportioned against the app's other
  /// tvOS landscape/poster rail metrics rather than the DEBUG gallery's own numbers.
  static let circleDiameter: CGFloat = 168
  static let itemSize = CGSize(width: circleDiameter + 32, height: circleDiameter + 96)
  /// Spacing and focus room from the same rule the poster rails use: a focused circle
  /// grows into its neighbour's half of the gap, so a constant that looks right at rest
  /// has the avatars overlapping the moment one of them lights up.
  static var spacing: CGFloat { ShelfMetrics.tvGutter(cardWidth: itemSize.width) }
  static var focusRoom: CGFloat {
    TVUIKitPosterMetrics.focusGrowthPadding(tileHeight: itemSize.height)
  }
  static let inset: CGFloat = 80
  /// Item plus the focus-lift room the section insets reserve above and below.
  public static var railHeight: CGFloat { itemSize.height + focusRoom * 2 }
}

extension TVUIKitPersonCollectionController: UICollectionViewDataSourcePrefetching {
  public func collectionView(_ collectionView: UICollectionView, prefetchItemsAt indexPaths: [IndexPath]) {
    TVUIKitRemoteImage.prefetch(photoURLs(at: indexPaths))
  }

  public func collectionView(_ collectionView: UICollectionView,
                             cancelPrefetchingForItemsAt indexPaths: [IndexPath]) {
    TVUIKitRemoteImage.cancelPrefetch(photoURLs(at: indexPaths))
  }

  private func photoURLs(at indexPaths: [IndexPath]) -> [URL?] {
    indexPaths.compactMap { path in
      people.indices.contains(path.item) ? people[path.item].photoURL : nil
    }
  }
}

extension TVUIKitPersonCollectionController: UICollectionViewDataSource, UICollectionViewDelegate {
  public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    people.count
  }

  public func collectionView(
    _ collectionView: UICollectionView,
    cellForItemAt indexPath: IndexPath
  ) -> UICollectionViewCell {
    let cell = collectionView.dequeueReusableCell(
      withReuseIdentifier: TVUIKitPersonCell.reuseID,
      for: indexPath
    ) as! TVUIKitPersonCell
    cell.configure(person: people[indexPath.item])
    return cell
  }

  public func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
    onSelect?(people[indexPath.item])
  }

  public func collectionView(_ collectionView: UICollectionView,
                             didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
                             with coordinator: UIFocusAnimationCoordinator) {
    let name: (IndexPath?) -> String? = { [weak self] path in
      guard let self, let path, self.people.indices.contains(path.item) else { return nil }
      return self.people[path.item].name
    }
    FocusLog.engine(section: "cast-rail",
                    from: name(context.previouslyFocusedIndexPath),
                    to: name(context.nextFocusedIndexPath))

    guard context.nextFocusedIndexPath != nil else { return }
    onCellFocused?()
  }

  // Same tvOS long-press-Select routing as `TVUIKitMediaCollectionController` — the
  // gesture goes to the collection view's delegate hook, not a per-cell interaction.
  public func collectionView(
    _ collectionView: UICollectionView,
    contextMenuConfigurationForItemsAt indexPaths: [IndexPath],
    point: CGPoint
  ) -> UIContextMenuConfiguration? {
    guard let indexPath = indexPaths.first,
          people.indices.contains(indexPath.item),
          let entries = contextMenuProvider?(people[indexPath.item]),
          !entries.isEmpty
    else { return nil }

    return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { _ in
      TVUIKitContextMenuBuilder.menu(from: entries)
    }
  }
}

/// A person circle and the two lines under it. The circle is an image: a photo, or
/// search's initials disc when there is no photo. No filled plate, and the image
/// view is not itself a focusable lockup — the cell is the control.
@MainActor
final class TVUIKitPersonCell: UICollectionViewCell {
  static let reuseID = "TVUIKitPersonCell"

  private let avatar = UIImageView()
  private let nameLabel = UILabel()
  private let captionLabel = UILabel()
  private var imageTask: Task<Void, Never>?
  private var currentURL: URL?
  private var monogramName: String?
  private var monogramDiameter: CGFloat = 0

  override init(frame: CGRect) {
    super.init(frame: frame)
    // The monogram configuration drew the white disc and the focus plate. A clear
    // cell background is not enough while that view is the content: it paints both
    // itself (2026-09-28, and still on device 2026-10-01).
    backgroundView = nil
    selectedBackgroundView = nil
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
    avatar.adjustsImageWhenAncestorFocused = false
    contentView.addSubview(avatar)

    nameLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
    nameLabel.adjustsFontForContentSizeCategory = true
    nameLabel.textAlignment = .center
    nameLabel.numberOfLines = 2
    nameLabel.textColor = .secondaryLabel

    captionLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
    captionLabel.adjustsFontForContentSizeCategory = true
    captionLabel.textAlignment = .center
    captionLabel.numberOfLines = 1
    captionLabel.textColor = .tertiaryLabel

    let text = UIStackView(arrangedSubviews: [nameLabel, captionLabel])
    text.axis = .vertical
    text.alignment = .fill
    text.spacing = 2
    text.translatesAutoresizingMaskIntoConstraints = false
    contentView.addSubview(text)

    NSLayoutConstraint.activate([
      avatar.topAnchor.constraint(equalTo: contentView.topAnchor),
      avatar.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
      avatar.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -32),
      avatar.heightAnchor.constraint(equalTo: avatar.widthAnchor),
      text.topAnchor.constraint(equalTo: avatar.bottomAnchor, constant: 10),
      text.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
      text.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
    ])
    registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: TVUIKitPersonCell, _) in
      cell.redrawMonogramIfNeeded()
    }
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func configure(person: TVUIKitPerson) {
    imageTask?.cancel()
    imageTask = nil
    currentURL = person.photoURL
    nameLabel.text = person.name
    captionLabel.text = person.caption
    captionLabel.isHidden = person.caption?.isEmpty != false
    accessibilityLabel = [person.name, person.caption].compactMap { $0 }.joined(separator: ", ")

    let cached = TVUIKitRemoteImage.cached(url: person.photoURL)
    if let photo = TVUIKitPersonPhoto.displayable(cached, url: person.photoURL) {
      showPhoto(photo)
    } else {
      showMonogram(person.name)
    }

    guard let url = person.photoURL else {
      ArtworkLog.skipped(by: "cast/\(person.name)", reason: "no photo URL")
      return
    }
    if cached != nil, monogramName == nil {
      ArtworkLog.servedFromMemory(url, by: "cast/\(person.name)")
      return
    }
    ArtworkLog.requested(url, by: "cast/\(person.name)")
    imageTask = Task { [weak self] in
      let image = await TVUIKitRemoteImage.load(url: url)
      await MainActor.run {
        guard let self, !Task.isCancelled, self.currentURL == url else { return }
        if let photo = TVUIKitPersonPhoto.displayable(image, url: url) {
          self.showPhoto(photo)
        }
      }
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    let diameter = avatar.bounds.width
    guard diameter > 1 else { return }
    avatar.layer.cornerRadius = diameter / 2
    guard let monogramName, abs(diameter - monogramDiameter) > 0.5 else { return }
    monogramDiameter = diameter
    avatar.image = TVUIKitTileArtwork.monogram(name: monogramName, diameter: diameter, traits: traitCollection)
  }

  override func didUpdateFocus(in context: UIFocusUpdateContext,
                               with coordinator: UIFocusAnimationCoordinator) {
    super.didUpdateFocus(in: context, with: coordinator)
    let focused = context.nextFocusedView == self
    coordinator.addCoordinatedAnimations { [weak self] in
      self?.nameLabel.textColor = focused ? .label : .secondaryLabel
    }
  }

  override func prepareForReuse() {
    super.prepareForReuse()
    imageTask?.cancel()
    imageTask = nil
    currentURL = nil
    monogramName = nil
    monogramDiameter = 0
    avatar.image = nil
  }

  private func showPhoto(_ image: UIImage) {
    monogramName = nil
    avatar.image = image
  }

  private func showMonogram(_ name: String) {
    monogramName = name
    monogramDiameter = 0
    let diameter = avatar.bounds.width > 1 ? avatar.bounds.width : 168
    avatar.image = TVUIKitTileArtwork.monogram(name: name, diameter: diameter, traits: traitCollection)
  }

  private func redrawMonogramIfNeeded() {
    guard monogramName != nil else { return }
    monogramDiameter = 0
    setNeedsLayout()
  }
}
#endif
