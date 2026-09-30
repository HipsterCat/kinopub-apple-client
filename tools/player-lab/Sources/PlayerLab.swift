import UIKit
import AVKit
import TVUIKit

/// Owns one `AVPlayerViewController` and applies the current `LabConfig` to it for a scenario.
/// Everything the app does (or could do) to the controller is a numbered branch below, so
/// the code here reads as the answer to "what would this variant cost".
final class PlayerLab: NSObject, AVPlayerViewControllerDelegate {

  static let clipDuration = 120.0
  /// The lab's "credits" begin this long before the end.
  static let creditsWindow = 15.0

  let controller = AVPlayerViewController()
  let player = AVPlayer()
  private(set) var scenario: Scenario
  private weak var presenter: UIViewController?
  private var timeObserver: Any?
  private var contextualState = ""
  private var systemInfoActions: [UIAction]?
  private var config: LabConfig { .shared }

  init(scenario: Scenario) {
    self.scenario = scenario
    super.init()
  }

  func present(from presenter: UIViewController) {
    self.presenter = presenter
    controller.player = player
    controller.delegate = self
    LabConfig.shared.replace(with: scenario.recipe)
    play(scenario, initial: true)
    presenter.present(controller, animated: true)
  }

  // MARK: Loading

  func play(_ s: Scenario, initial: Bool = false) {
    scenario = s
    NSLog("LAB play %@ next=%@", s.id, Scenarios.next(after: s)?.id ?? "none")
    let item = AVPlayerItem(url: Bundle.main.url(forResource: "clip", withExtension: "mp4")!)
    item.externalMetadata = metadata(for: s)
    configure(item: item, for: s)
    player.replaceCurrentItem(with: item)
    configureController(for: s)
    if config.value("start") == 1 {
      player.seek(to: CMTime(seconds: Self.clipDuration - Self.creditsWindow - 8, preferredTimescale: 600))
    }
    installTimeObserver()
    player.play()
  }

  // MARK: externalMetadata  (ours: PlayerInfo)

  private func metadata(for s: Scenario) -> [AVMetadataItem] {
    let info = s.info
    var items = info.metadataItems()
    let date = Axes.axis("date").options.firstIndex(of: config.label("date"))!
    if date != 0 { items.removeAll { $0.identifier == .commonIdentifierCreationDate } }
    if let year = s.context.release?.year {
      func str(_ v: String) -> AVMetadataItem { item(.commonIdentifierCreationDate, v as NSString) }
      func utc(_ h: Int) -> NSDate {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: year, month: 1, day: 1, hour: h))! as NSDate
      }
      switch date {
      case 1: items.append(str("\(year)"))
      case 2: items.append(str("\(year)-01-01"))
      case 3: items.append(str("\(year)-01-01T12:00:00Z"))
      case 4: items.append(item(.commonIdentifierCreationDate, utc(0)))
      default: break
      }
    }
    switch config.value("meta") {
    case 1: items.removeAll { $0.identifier == .quickTimeMetadataGenre }
    case 2: items.removeAll { $0.identifier == .commonIdentifierCreationDate }
    case 4: items.removeAll { $0.identifier != .commonIdentifierTitle }
    default: break
    }
    if config.value("meta") == 0 || config.value("meta") == 1 || config.value("meta") == 2 {
      if let art = Scenarios.cachedData(s.artURL) { items.append(PlayerInfo.artworkItem(art)) }
    }
    return items
  }

  private func item(_ id: AVMetadataIdentifier, _ value: NSCopying & NSObjectProtocol) -> AVMetadataItem {
    let m = AVMutableMetadataItem()
    m.identifier = id; m.value = value; m.extendedLanguageTag = "und"
    return m
  }

  // MARK: AVPlayerItem surfaces

  private func configure(item: AVPlayerItem, for s: Scenario) {
    // nextContentProposal — ours (PlayerManager.installNextEpisodeProposal)
    item.nextContentProposal = nil
    if config.value("proposal") != 2, let next = Scenarios.next(after: s) {
      let proposal = AVContentProposal(
        contentTimeForTransition: CMTime(seconds: Self.clipDuration - Self.creditsWindow, preferredTimescale: 600),
        title: "Сезон 1, серия \(next.context.item.episodeNumber ?? 0) — \(next.context.parent?.title ?? "")",
        previewImage: Scenarios.cachedData(next.artURL).flatMap(UIImage.init(data:)))
      // NaN = no auto-accept (the default); 0 would accept the moment playback ends.
      proposal.automaticAcceptanceInterval = config.value("proposal") == 0 ? 10 : .nan
      item.nextContentProposal = proposal
    }
    // navigationMarkerGroups — not used by the app
    if config.value("chapters") == 1 {
      let names = ["Cold open", "Main story", "Credits"]
      let markers = names.enumerated().map { i, name -> AVTimedMetadataGroup in
        let title = AVMutableMetadataItem()
        title.identifier = .commonIdentifierTitle; title.value = name as NSString; title.extendedLanguageTag = "und"
        return AVTimedMetadataGroup(items: [title],
                                    timeRange: CMTimeRange(start: CMTime(seconds: Double(i) * 40, preferredTimescale: 600),
                                                           duration: CMTime(seconds: 40, preferredTimescale: 600)))
      }
      item.navigationMarkerGroups = [AVNavigationMarkersGroup(title: nil, timedNavigationMarkers: markers)]
    } else {
      item.navigationMarkerGroups = []
    }
  }

  // MARK: AVPlayerViewController surfaces

  private func configureController(for s: Scenario) {
    let c = controller
    let next = Scenarios.next(after: s)
    let goTo = UIAction(title: s.isEpisode ? "Go to Show" : "Go to Movie") { [weak self] _ in self?.goTo() }
    let nextAction = UIAction(title: "Next Episode") { [weak self] _ in self?.goNext() }

    // infoViewActions — ours (PlayerManager.rebuildInfoViewActions)
    // The system's list is only readable before the first set (after `= nil` it reads empty).
    if systemInfoActions == nil { systemInfoActions = c.infoViewActions ?? [] }
    let system = systemInfoActions ?? []
    var actions: [UIAction]?
    switch config.value("infoActions") {
    case 0: actions = next != nil ? [nextAction, goTo] : system + [goTo]
    case 1: actions = nil
    case 2: actions = system + (next != nil ? [nextAction] : [])
    case 3: actions = system + [goTo]
    case 4: actions = next != nil ? [nextAction] : nil
    default: actions = system + (next != nil ? [nextAction] : []) + [goTo]
    }
    c.infoViewActions = actions

    // customInfoViewControllers — not used by the app
    c.customInfoViewControllers = config.value("infoTab") > 0 && next != nil
      ? [UpNextTab(episodes: Scenarios.following(s), style: config.value("infoTab")) { [weak self] e in self?.play(e) }] : []

    // transportBarCustomMenuItems — behind the sidecar flag in the app
    c.transportBarCustomMenuItems = config.value("menus") == 1 && s.isEpisode
      ? [UIMenu(title: "Episodes", image: UIImage(systemName: "list.bullet"),
                children: ([s] + Scenarios.following(s)).map { e in
                  UIAction(title: e.name, state: e.id == s.id ? .on : .off) { [weak self] _ in self?.play(e) }
                })] : []

    // customOverlayViewController — not used
    c.customOverlayViewController = config.value("overlay") == 1 ? OverlayBadge() : nil

    // speeds — ours (system default)
    switch config.value("speeds") {
    case 1: c.speeds = []
    case 2: c.speeds = [0.5, 1, 1.25, 1.5, 2].map { AVPlaybackSpeed(rate: Float($0), localizedName: "\($0)×") }
    default: c.speeds = AVPlaybackSpeed.systemDefaultSpeeds
    }
    c.allowsPictureInPicturePlayback = config.value("pip") == 0
    c.allowedSubtitleOptionLanguages = config.value("subLangs") == 1 ? [] : nil
    c.showsPlaybackControls = config.value("controls") == 0
    c.requiresLinearPlayback = config.value("linear") == 1
    c.playbackControlsIncludeTransportBar = config.value("bar") == 0
    c.playbackControlsIncludeInfoViews = config.value("infoViews") == 0
    c.transportBarIncludesTitleView = config.value("titleView") == 0
    c.skippingBehavior = config.value("skipping") == 1 ? .skipItem : .default
    c.requiresFullSubtitles = config.value("fullSubs") == 1
    c.appliesPreferredDisplayCriteriaAutomatically = config.value("criteria") == 0
  }

  // MARK: contextualActions — not used by the app

  private func installTimeObserver() {
    if let timeObserver { player.removeTimeObserver(timeObserver) }
    contextualState = "?"
    timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] t in
      self?.updateContextual(at: t.seconds)
    }
  }

  private func updateContextual(at seconds: Double) {
    let mode = config.value("contextual")
    var actions: [UIAction] = []
    var state = ""
    if [2, 3].contains(mode), seconds >= 5, seconds < 20 {
      state += "skip"
      actions.append(UIAction(title: "Skip Intro") { [weak self] _ in
        NSLog("LAB tapped Skip Intro")
        self?.player.seek(to: CMTime(seconds: 20, preferredTimescale: 600))
      })
    }
    if [1, 3].contains(mode), seconds >= Self.clipDuration - 60, Scenarios.next(after: scenario) != nil {
      state += "next"
      actions.append(UIAction(title: "Next Episode") { [weak self] _ in self?.goNext() })
    }
    guard state != contextualState else { return }
    contextualState = state
    controller.contextualActions = actions
  }

  // MARK: Answers

  func goNext() {
    NSLog("LAB tapped Next Episode")
    guard let next = Scenarios.next(after: scenario) else { return }
    play(next)
  }

  private func goTo() {
    NSLog("LAB tapped Go to")
    let title = scenario.isEpisode ? "show page" : "movie page"
    let name = scenario.context.parent?.title ?? scenario.context.title ?? ""
    let presenter = presenter
    controller.dismiss(animated: true) {
      let a = UIAlertController(title: "Would open the \(title)", message: name, preferredStyle: .alert)
      a.addAction(UIAlertAction(title: "OK", style: .default))
      presenter?.present(a, animated: true)
    }
  }

  // MARK: AVPlayerViewControllerDelegate

  func playerViewController(_ pvc: AVPlayerViewController, shouldPresent proposal: AVContentProposal) -> Bool { true }
  func playerViewController(_ pvc: AVPlayerViewController, didAccept proposal: AVContentProposal) { NSLog("LAB proposal accepted"); goNext() }
  func playerViewController(_ pvc: AVPlayerViewController, didReject proposal: AVContentProposal) {
    NSLog("LAB proposal rejected")
    pvc.dismiss(animated: true)
  }
  @objc(skipToNextItemForPlayerViewController:)
  func skipToNextItem(for pvc: AVPlayerViewController) { NSLog("LAB skip next"); goNext() }

  func playerViewControllerDidEndDismissalTransition(_ pvc: AVPlayerViewController) {
    if let timeObserver { player.removeTimeObserver(timeObserver); self.timeObserver = nil }
    player.pause()
  }
}

/// Apple's TV app lists what comes next in its own tab. AVKit only gives us the tab (`customInfoViewControllers`);
/// what is inside is ours — here built from the same TVUIKit pieces as the app's rails.
final class UpNextTab: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate {
  private let episodes: [Scenario]
  private let style: Int   // 1 wide · 2 poster · 3 wide + badge/progress
  private let pick: (Scenario) -> Void
  private lazy var collection: UICollectionView = {
    let l = UICollectionViewFlowLayout()
    l.scrollDirection = .horizontal
    l.itemSize = style == 2 ? CGSize(width: 260, height: 430) : CGSize(width: 400, height: 225)
    l.minimumLineSpacing = 40
    l.sectionInset = UIEdgeInsets(top: 20, left: 60, bottom: 20, right: 60)
    let c = UICollectionView(frame: .zero, collectionViewLayout: l)
    c.dataSource = self; c.delegate = self
    c.register(WideCard.self, forCellWithReuseIdentifier: "wide")
    c.register(PosterCard.self, forCellWithReuseIdentifier: "poster")
    c.remembersLastFocusedIndexPath = true
    c.clipsToBounds = false
    return c
  }()

  init(episodes: [Scenario], style: Int, pick: @escaping (Scenario) -> Void) {
    self.episodes = episodes; self.style = style; self.pick = pick
    super.init(nibName: nil, bundle: nil)
    title = "Up Next"
    preferredContentSize = CGSize(width: 0, height: style == 2 ? 490 : 330)
  }
  required init?(coder: NSCoder) { fatalError() }
  override func loadView() { view = collection }

  func collectionView(_ cv: UICollectionView, numberOfItemsInSection s: Int) -> Int { episodes.count }
  func collectionView(_ cv: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
    let e = episodes[ip.item]
    let episode = e.context.item
    let line = "Сезон \(episode.seasonNumber ?? 1), серия \(episode.episodeNumber ?? 0)"
    let name = EpisodeTitle.isPlaceholder(episode.title ?? "") ? nil : episode.title
    if style == 2 {
      let cell = cv.dequeueReusableCell(withReuseIdentifier: "poster", for: ip) as! PosterCard
      cell.show(image: Scenarios.cachedData(e.posterURL).flatMap(UIImage.init(data:)), title: e.context.parent?.title ?? "", subtitle: [line, name].compactMap { $0 }.joined(separator: " · "))
      return cell
    }
    let cell = cv.dequeueReusableCell(withReuseIdentifier: "wide", for: ip) as! WideCard
    cell.show(image: Scenarios.cachedData(e.artURL).flatMap(UIImage.init(data:)), title: name ?? line,
              secondary: name == nil ? nil : line, badge: style == 3 ? (ip.item == 0 ? "Следующая" : nil) : nil,
              progress: style == 3 ? (ip.item == 0 ? 0.35 : 0) : 0)
    return cell
  }
  func collectionView(_ cv: UICollectionView, didSelectItemAt ip: IndexPath) { pick(episodes[ip.item]) }
}

/// The app's Continue Watching tile: `TVMediaItemContentConfiguration.wideCell()`.
final class WideCard: UICollectionViewCell {
  private var image: UIImage?, title = "", secondary: String?, badge: String?, progress: Float = 0
  func show(image: UIImage?, title: String, secondary: String?, badge: String?, progress: Float) {
    self.image = image; self.title = title; self.secondary = secondary; self.badge = badge; self.progress = progress
    setNeedsUpdateConfiguration()
  }
  override func updateConfiguration(using state: UICellConfigurationState) {
    var c = TVMediaItemContentConfiguration.wideCell()
    c.image = image
    c.text = title
    c.secondaryText = secondary
    c.textProperties.color = state.isFocused ? .label : .secondaryLabel
    c.playbackProgress = progress
    if let badge { c.badgeText = badge }
    contentConfiguration = c
  }
}

/// The app's poster tile: `TVPosterView`.
final class PosterCard: UICollectionViewCell {
  private let poster = TVPosterView()
  override init(frame: CGRect) {
    super.init(frame: frame)
    contentView.addSubview(poster)
  }
  override func layoutSubviews() { super.layoutSubviews(); poster.frame = contentView.bounds }
  required init?(coder: NSCoder) { fatalError() }
  func show(image: UIImage?, title: String, subtitle: String) {
    poster.image = image; poster.title = title; poster.subtitle = subtitle
  }
  override var canBecomeFocused: Bool { true }
}

final class OverlayBadge: UIViewController {
  override func viewDidLoad() {
    super.viewDidLoad()
    let l = UILabel(); l.text = " customOverlayViewController "; l.font = .boldSystemFont(ofSize: 26)
    l.backgroundColor = .systemYellow; l.textColor = .black
    l.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(l)
    NSLayoutConstraint.activate([l.topAnchor.constraint(equalTo: view.topAnchor, constant: 60),
                                 l.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -60)])
  }
}
