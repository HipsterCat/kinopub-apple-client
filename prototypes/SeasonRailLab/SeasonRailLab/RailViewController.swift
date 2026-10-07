import UIKit

/// Standalone season rail. One collection. Each cell follows
/// `VideosUI.EpisodeLockup`: borderless still, title, a separately focusable
/// description, accessories on the image. Season chips are plain at rest and
/// filled when selected. The product's `TVUIKitMediaItemRail` is not involved.
final class RailViewController: UIViewController, UICollectionViewDelegate {
  private let backdrop = UIImageView()
  private let scrim = ScrimView()
  private let logo = UIImageView()
  private let seasonRow = UIStackView()
  private let footer = UILabel()
  private let statusLabel = UILabel()
  private let retryButton = UIButton(configuration: .borderedProminent())
  private var collectionView: UICollectionView!
  private var dataSource: UICollectionViewDiffableDataSource<Int, RailItem>!
  private var seasonButtons: [UIButton] = []
  private var show: Show?
  private var selectedSeason = 1
  private var items: [RailItem] = []
  private var didProbe = false
  private var cellHeight: CGFloat = 560

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    cellHeight = RailMetrics.cellHeight(traits: traitCollection)
    installChrome()
    installCollection()
    showSkeletons()
    load()
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    guard !didProbe else { return }
    didProbe = true
    _ = APIProbe.run(in: view)
  }

  override var preferredFocusEnvironments: [any UIFocusEnvironment] {
    if !retryButton.isHidden { return [retryButton] }
    return [collectionView]
  }

  func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
    if let index = items.firstIndex(where: { item in
      guard case .episode(let episode) = item else { return false }
      if case .inProgress = episode.availability { return true }
      return false
    }) {
      return IndexPath(item: index, section: 0)
    }
    return items.isEmpty ? nil : IndexPath(item: 0, section: 0)
  }

  private func installChrome() {
    backdrop.contentMode = .scaleAspectFill
    backdrop.clipsToBounds = true
    backdrop.alpha = 0
    backdrop.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(backdrop)

    scrim.translatesAutoresizingMaskIntoConstraints = false
    scrim.isUserInteractionEnabled = false
    view.addSubview(scrim)

    logo.contentMode = .scaleAspectFit
    logo.alpha = 0
    logo.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(logo)

    seasonRow.axis = .horizontal
    seasonRow.alignment = .center
    seasonRow.spacing = 18
    seasonRow.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(seasonRow)

    footer.font = UIFont.preferredFont(forTextStyle: .footnote)
    footer.textColor = .secondaryLabel
    footer.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(footer)

    statusLabel.font = UIFont.preferredFont(forTextStyle: .callout)
    statusLabel.textColor = .secondaryLabel
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 0
    statusLabel.text = "Не удалось загрузить сезоны"
    statusLabel.isHidden = true
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(statusLabel)

    var retry = UIButton.Configuration.borderedProminent()
    retry.title = "Повторить"
    retryButton.configuration = retry
    retryButton.isHidden = true
    retryButton.addAction(UIAction { [weak self] _ in self?.load() }, for: .primaryActionTriggered)
    retryButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(retryButton)

    let safe = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      backdrop.topAnchor.constraint(equalTo: view.topAnchor),
      backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      scrim.topAnchor.constraint(equalTo: view.topAnchor),
      scrim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      scrim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      logo.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
      logo.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      logo.widthAnchor.constraint(equalToConstant: 720),
      logo.heightAnchor.constraint(equalToConstant: 120),
      footer.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -12),
      footer.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      statusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 1200),
      statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -30),
      retryButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      retryButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
    ])
  }

  private func installCollection() {
    let height = cellHeight
    let layout = UICollectionViewCompositionalLayout { _, _ in
      let size = NSCollectionLayoutSize(
        widthDimension: .absolute(RailMetrics.imageWidth),
        heightDimension: .absolute(height)
      )
      let item = NSCollectionLayoutItem(layoutSize: size)
      let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [item])
      let section = NSCollectionLayoutSection(group: group)
      section.orthogonalScrollingBehavior = .continuous
      section.interGroupSpacing = RailMetrics.gutter
      section.contentInsets = NSDirectionalEdgeInsets(top: 20, leading: 80, bottom: 12, trailing: 80)
      return section
    }
    let collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
    collection.backgroundColor = .clear
    collection.clipsToBounds = false
    collection.remembersLastFocusedIndexPath = false
    collection.delegate = self
    collection.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(collection)
    collectionView = collection

    let registration = UICollectionView.CellRegistration<EpisodeCell, RailItem> { cell, _, item in
      cell.configure(item)
    }
    dataSource = UICollectionViewDiffableDataSource(collectionView: collection) { collectionView, indexPath, item in
      collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: item)
    }

    let safe = view.safeAreaLayoutGuide
    NSLayoutConstraint.activate([
      collection.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      collection.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      collection.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),
      collection.heightAnchor.constraint(equalToConstant: height + 36 + 28),
      seasonRow.bottomAnchor.constraint(equalTo: collection.topAnchor, constant: -8),
      seasonRow.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      seasonRow.topAnchor.constraint(greaterThanOrEqualTo: logo.bottomAnchor, constant: 16),
      footer.topAnchor.constraint(greaterThanOrEqualTo: safe.topAnchor),
    ])
  }

  private func showSkeletons() {
    items = (0..<6).map { .skeleton($0) }
    apply(items, animated: false)
    footer.text = nil
  }

  private func load() {
    statusLabel.isHidden = true
    retryButton.isHidden = true
    if show == nil { showSkeletons() }
    Task { [weak self] in
      guard let self else { return }
      async let backdropImage = ImageStore.load(
        Catalog.backdrop,
        pointSize: CGSize(width: 1920, height: 1080),
        scale: self.traitCollection.displayScale
      )
      async let logoImage = ImageStore.load(
        Catalog.logo,
        pointSize: CGSize(width: 720, height: 120),
        scale: self.traitCollection.displayScale
      )
      do {
        let show = try await Catalog.fetch()
        let backdrop = await backdropImage
        let logo = await logoImage
        self.applyChrome(backdrop: backdrop, logo: logo)
        self.show = show
        self.selectedSeason = show.seasons.first?.number ?? 1
        self.rebuildSeasons()
        self.showSeason(self.selectedSeason)
        self.setNeedsFocusUpdate()
      } catch {
        _ = await backdropImage
        _ = await logoImage
        self.items = []
        self.apply([], animated: false)
        self.statusLabel.text = "Не удалось загрузить сезоны\n\(error)"
        NSLog("RAIL_LOAD %@", String(describing: error))
        self.statusLabel.isHidden = false
        self.retryButton.isHidden = false
        self.setNeedsFocusUpdate()
      }
    }
  }

  private func applyChrome(backdrop image: UIImage?, logo logoImage: UIImage?) {
    if let image {
      backdrop.image = image
      if let color = ImageStore.averageColor(of: image) {
        EpisodeCell.placeholder = ImageStore.placeholder(
          color: color,
          size: CGSize(width: RailMetrics.imageWidth, height: RailMetrics.imageHeight),
          scale: traitCollection.displayScale
        )
        for case let cell as EpisodeCell in collectionView.visibleCells {
          cell.refreshPlaceholderIfNeeded()
        }
      }
    }
    if let logoImage { logo.image = logoImage }
    UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
      self.backdrop.alpha = image == nil ? 0 : 1
      self.logo.alpha = logoImage == nil ? 0 : 1
    }
  }

  private func rebuildSeasons() {
    for button in seasonButtons { button.removeFromSuperview() }
    seasonButtons = []
    let label = UILabel()
    label.font = UIFont.preferredFont(forTextStyle: .title2)
    label.textColor = .secondaryLabel
    label.text = "Сезон"
    seasonRow.addArrangedSubview(label)
    for season in show?.seasons ?? [] {
      let button = UIButton(configuration: seasonConfiguration(number: season.number, selected: season.number == selectedSeason))
      button.tag = season.number
      button.accessibilityLabel = "Сезон \(season.number)"
      button.addAction(UIAction { [weak self] action in
        guard let button = action.sender as? UIButton else { return }
        self?.selectSeason(button.tag)
      }, for: .primaryActionTriggered)
      button.translatesAutoresizingMaskIntoConstraints = false
      NSLayoutConstraint.activate([
        button.widthAnchor.constraint(equalToConstant: 66),
        button.heightAnchor.constraint(equalToConstant: 66),
      ])
      seasonRow.addArrangedSubview(button)
      seasonButtons.append(button)
    }
  }

  private func selectSeason(_ number: Int) {
    guard number != selectedSeason, show?.seasons.contains(where: { $0.number == number }) == true else { return }
    selectedSeason = number
    for button in seasonButtons {
      button.configuration = seasonConfiguration(number: button.tag, selected: button.tag == number)
    }
    showSeason(number)
  }

  private func seasonConfiguration(number: Int, selected: Bool) -> UIButton.Configuration {
    var config: UIButton.Configuration = selected ? .filled() : .plain()
    config.title = "\(number)"
    config.cornerStyle = .capsule
    config.contentInsets = .zero
    config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var outgoing = incoming
      outgoing.font = UIFont.preferredFont(forTextStyle: .title2)
      return outgoing
    }
    return config
  }

  private func showSeason(_ number: Int) {
    guard let season = show?.seasons.first(where: { $0.number == number }) else { return }
    items = season.episodes.map { .episode($0) }
    footer.text = RailCopy.summary(season: number, episodes: season.episodes)
    apply(items, animated: false)
    if let first = items.indices.first {
      collectionView.scrollToItem(at: IndexPath(item: first, section: 0), at: .left, animated: false)
    }
  }

  private func apply(_ items: [RailItem], animated: Bool) {
    var snapshot = NSDiffableDataSourceSnapshot<Int, RailItem>()
    snapshot.appendSections([0])
    snapshot.appendItems(items)
    dataSource.apply(snapshot, animatingDifferences: animated)
  }
}

final class ScrimView: UIView {
  override class var layerClass: AnyClass { CAGradientLayer.self }

  override init(frame: CGRect) {
    super.init(frame: frame)
    guard let gradient = layer as? CAGradientLayer else { return }
    gradient.colors = [
      UIColor.clear.cgColor,
      UIColor.black.withAlphaComponent(0.45).cgColor,
      UIColor.black.cgColor,
    ]
    gradient.locations = [0.30, 0.58, 0.78]
  }

  required init?(coder: NSCoder) { nil }
}
