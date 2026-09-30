import UIKit

/// A plain list of real titles. Each row says what is inside it: the AVKit API it exercises.
/// Select plays it in the system player.
final class RootViewController: UITableViewController {
  private var lab: PlayerLab?
  private let groups: [(String, [Scenario])] = {
    var order: [String] = []
    for s in Scenarios.all where !s.hidden && !order.contains(s.group) { order.append(s.group) }
    return order.map { g in (g, Scenarios.all.filter { $0.group == g && !$0.hidden }) }
  }()

  init() { super.init(style: .grouped); title = "Player Lab"; tableView.rowHeight = 150 }
  required init?(coder: NSCoder) { fatalError() }

  override func numberOfSections(in tableView: UITableView) -> Int { groups.count }
  override func tableView(_ t: UITableView, titleForHeaderInSection s: Int) -> String? { groups[s].0 }
  override func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { groups[s].1.count }

  private func scenario(_ ip: IndexPath) -> Scenario { groups[ip.section].1[ip.row] }

  override func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
    let s = scenario(ip)
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    var c = UIListContentConfiguration.subtitleCell()
    c.text = s.name
    c.secondaryText = s.subtitle + "\n" + s.tags.map { "[\($0)]" }.joined(separator: " ")
    c.secondaryTextProperties.numberOfLines = 0
    c.secondaryTextProperties.font = .preferredFont(forTextStyle: .caption1)
    c.imageProperties.maximumSize = CGSize(width: 220, height: 124)
    c.imageProperties.cornerRadius = 8
    c.image = Scenarios.cachedData(s.thumbURL).flatMap(UIImage.init(data:)) ?? UIImage(systemName: "film")
    cell.contentConfiguration = c
    if Scenarios.cachedData(s.thumbURL) == nil, let url = s.thumbURL {
      Task { [weak self] in
        _ = await Scenarios.data(url)
        self?.tableView.reloadRows(at: [ip], with: .none)
      }
    }
    return cell
  }

  override func tableView(_ t: UITableView, didSelectRowAt ip: IndexPath) {
    let s = scenario(ip)
    Task { await play(s) }
  }

  func play(_ s: Scenario) async {
    // Artwork first: the system panel wants the image itself, not a URL.
    _ = await Scenarios.data(s.artURL)
    for e in Scenarios.following(s) { _ = await Scenarios.data(e.artURL); _ = await Scenarios.data(e.posterURL) }
    lab = PlayerLab(scenario: s)
    lab?.present(from: self)
  }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    guard let ws = scene as? UIWindowScene else { return }
    window = UIWindow(windowScene: ws)
    let root = RootViewController()
    window?.rootViewController = UINavigationController(rootViewController: root)
    window?.makeKeyAndVisible()
    let args = ProcessInfo.processInfo.arguments
    func arg(_ name: String) -> String? { args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
    // -tab 1|2|3 -autoplay <episode>: show just the Up Next tab's content, for screenshots.
    if let t = arg("-tab").flatMap({ Int($0) }), let id = arg("-autoplay"), let s = Scenarios.scenario(id) {
      Task {
        for e in Scenarios.following(s) { _ = await Scenarios.data(e.artURL); _ = await Scenarios.data(e.posterURL) }
        let tab = UpNextTab(episodes: Scenarios.following(s), style: t) { _ in }
        let host = UIViewController(); host.view.backgroundColor = .black
        host.addChild(tab); tab.view.frame = CGRect(x: 0, y: 500, width: 1920, height: 400); host.view.addSubview(tab.view)
        tab.didMove(toParent: host)
        window?.rootViewController = host
      }
      return
    }
    if let id = arg("-autoplay"), let s = Scenarios.scenario(id) {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { Task { await root.play(s) } }
    }
  }
}

@main final class App: UIResponder, UIApplicationDelegate {}
