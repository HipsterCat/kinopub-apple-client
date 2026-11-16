import XCTest
@testable import KinoPubUI

#if os(tvOS)
import UIKit

/// The episode rail grows under the user while TMDB schedules and the awaited episode
/// land: Sasha's crash 2026-11-17 was the season rail going 7 → 11 items and UIKit
/// throwing "Invalid batch updates … before = [11]" from `syncItems`. Each test drives the
/// real controllers in a window; an inconsistent batch is an Objective-C exception,
/// which takes the test process down, so reaching the asserts is the check.
@MainActor
final class TVUIKitMediaItemRailSyncTests: XCTestCase {

  private var window: UIWindow!

  override func setUp() {
    super.setUp()
    window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
  }

  override func tearDown() {
    window.rootViewController = nil
    window = nil
    super.tearDown()
  }

  // MARK: - Fixtures

  private func episodes(_ ids: Range<Int>, caption: String = "Серия") -> [TVUIKitMediaItem] {
    ids.map { TVUIKitMediaItem(id: $0, caption: "\(caption) \($0)") }
  }

  private func seasonCard(id: Int) -> TVUIKitMediaItem {
    TVUIKitMediaItem(id: id,
                     seasonCard: .init(posterURL: nil, fallbackPosterURL: nil,
                                       captions: ["Сезон \(id)"], chips: ["10 серий"]))
  }

  private func host(_ controller: UIViewController) {
    window.rootViewController = controller
    window.makeKeyAndVisible()
    controller.view.frame = window.bounds
    controller.view.layoutIfNeeded()
  }

  private func railCollectionView(in view: UIView) -> UICollectionView? {
    // The season controller has two: the tab strip first, then the rail. The rail is
    // the one whose data source is the rail controller.
    var found: [UICollectionView] = []
    func walk(_ view: UIView) {
      if let collection = view as? UICollectionView { found.append(collection) }
      view.subviews.forEach(walk)
    }
    walk(view)
    return found.first { $0.dataSource is TVUIKitMediaItemRailController }
  }

  private func pump() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
  }

  private func makeRail() -> TVUIKitMediaItemRailController {
    TVUIKitMediaItemRailController(contentInset: 80, columns: 5, caption: .always,
                                   overlayOnFocus: true)
  }

  private func configure(_ rail: TVUIKitMediaItemRailController, _ items: [TVUIKitMediaItem]) {
    rail.configure(items: items, onSelect: { _ in }, onFocusedItem: nil, contextMenuProvider: nil)
  }

  // MARK: - Plain rail

  func testRailGrowsFromSevenToElevenItems() throws {
    let rail = makeRail()
    host(rail)
    configure(rail, episodes(0..<7))
    rail.view.layoutIfNeeded()
    configure(rail, episodes(0..<11))
    rail.view.layoutIfNeeded()
    let collection = try XCTUnwrap(railCollectionView(in: rail.view))
    XCTAssertEqual(collection.numberOfItems(inSection: 0), 11)
  }

  /// Growth with no layout pass between updates, the way several SwiftUI updates land in
  /// one transaction.
  func testRapidGrowthWithoutLayoutBetweenUpdates() throws {
    let rail = makeRail()
    host(rail)
    configure(rail, episodes(0..<7))
    for count in 8...11 { configure(rail, episodes(0..<count)) }
    configure(rail, episodes(0..<11, caption: "Эпизод"))
    for count in 12...20 { configure(rail, episodes(0..<count)) }
    rail.view.layoutIfNeeded()
    let collection = try XCTUnwrap(railCollectionView(in: rail.view))
    XCTAssertEqual(collection.numberOfItems(inSection: 0), 20)
  }

  /// A reload (identities changed) left pending — no layout yet — and then an append.
  /// UIKit flushes the pending reload when the batch starts and reads the data source;
  /// the append must still be counted from what the collection view had.
  func testAppendRightAfterAPendingReload() throws {
    let rail = makeRail()
    host(rail)
    configure(rail, episodes(0..<7))
    rail.view.layoutIfNeeded()
    configure(rail, episodes(100..<107))      // new identities → reload, not laid out
    configure(rail, episodes(100..<111))      // append on top of the pending reload
    rail.view.layoutIfNeeded()
    configure(rail, episodes(100..<104))      // shrink → reload
    configure(rail, episodes(100..<111))      // grow straight back
    rail.view.layoutIfNeeded()
    let collection = try XCTUnwrap(railCollectionView(in: rail.view))
    XCTAssertEqual(collection.numberOfItems(inSection: 0), 11)
  }

  /// Layout invalidated (a size or trait pass) between the updates.
  func testGrowthAcrossLayoutInvalidation() throws {
    let rail = makeRail()
    host(rail)
    configure(rail, episodes(0..<7))
    let collection = try XCTUnwrap(railCollectionView(in: rail.view))
    collection.collectionViewLayout.invalidateLayout()
    configure(rail, episodes(0..<11))
    rail.view.frame.size.width = 1800
    configure(rail, episodes(0..<14))
    rail.view.layoutIfNeeded()
    XCTAssertEqual(collection.numberOfItems(inSection: 0), 14)
  }

  /// Rail controlled before its view is in a window, then shown, then grown.
  func testGrowthBeforeAndAfterTheViewLoads() throws {
    let rail = makeRail()
    configure(rail, episodes(0..<3))
    configure(rail, episodes(0..<7))
    host(rail)
    configure(rail, episodes(0..<11))
    pump()
    let collection = try XCTUnwrap(railCollectionView(in: rail.view))
    XCTAssertEqual(collection.numberOfItems(inSection: 0), 11)
  }

  /// Random grow / edit / shrink / identity change, with and without layout and run-loop
  /// turns between, against a fixed seed.
  func testRandomUpdateSequencesStayConsistent() throws {
    var generator = SeededGenerator(seed: 20261117)
    let rail = makeRail()
    host(rail)
    var current = episodes(0..<7)
    configure(rail, current)
    let collection = try XCTUnwrap(railCollectionView(in: rail.view))
    for step in 0..<300 {
      switch Int.random(in: 0..<6, using: &generator) {
      case 0, 1:
        let start = (current.last?.id ?? 0) + 1
        current += episodes(start..<(start + Int.random(in: 1...4, using: &generator)))
      case 2:
        current = current.map { TVUIKitMediaItem(id: $0.id, caption: "Шаг \(step)") }
      case 3:
        current = Array(current.prefix(max(1, current.count - Int.random(in: 1...3, using: &generator))))
      case 4:
        let base = 1000 * (step + 1)
        current = episodes(base..<(base + Int.random(in: 3...12, using: &generator)))
      default:
        break
      }
      configure(rail, current)
      switch Int.random(in: 0..<3, using: &generator) {
      case 0: rail.view.layoutIfNeeded()
      case 1: collection.collectionViewLayout.invalidateLayout()
      default: break
      }
      if step % 25 == 0 { pump() }
    }
    rail.view.layoutIfNeeded()
    XCTAssertEqual(collection.numberOfItems(inSection: 0), current.count)
  }

  // MARK: - Counts invalidated between the read and the batch

  /// The device's crash: `numberOfItems` still answered the cached 7, then the layout
  /// pass `performBatchUpdates` forces first ran a full layout invalidation (which also
  /// drops the cached counts), so the batch read "before" from the data source. With the
  /// data source already at 11 that is "before = [11]" and UIKit throws. The host here
  /// invalidates the rail's layout from its own `layoutSubviews`, the way a pending
  /// parent layout did on the device.
  func testBatchThatReReadsCountsAfterAForcedLayoutPass() throws {
    let rail = makeRail()
    let host = InvalidatingHostController(rail: rail)
    self.host(host)
    configure(rail, episodes(0..<7))
    host.view.layoutIfNeeded()
    let collection = try XCTUnwrap(railCollectionView(in: rail.view))
    XCTAssertEqual(collection.numberOfItems(inSection: 0), 7)
    host.collection = collection
    for count in [11, 12, 15] {
      host.view.setNeedsLayout()
      rail.view.setNeedsLayout()
      collection.setNeedsLayout()
      configure(rail, episodes(0..<count))
      host.view.layoutIfNeeded()
      XCTAssertEqual(collection.numberOfItems(inSection: 0), count)
    }
  }

  func testSeasonRailBatchThatReReadsCountsAfterAForcedLayoutPass() throws {
    let controller = TVSeasonRailController(contentInset: 80, columns: 5)
    let host = InvalidatingHostController(rail: controller)
    self.host(host)
    applySeasons(controller, episodesPerSeason: [6])
    host.view.layoutIfNeeded()
    let collection = try XCTUnwrap(railCollectionView(in: controller.view))
    host.collection = collection
    host.view.setNeedsLayout()
    controller.view.setNeedsLayout()
    collection.setNeedsLayout()
    applySeasons(controller, episodesPerSeason: [10])
    host.view.layoutIfNeeded()
    XCTAssertEqual(collection.numberOfItems(inSection: 0), 11)
  }

  // MARK: - Season rail (the crashing path: TVSeasonRail.updateUIViewController)

  private func applySeasons(_ controller: TVSeasonRailController, episodesPerSeason: [Int]) {
    var items: [TVUIKitMediaItem] = []
    var tabOfItem: [Int: Int] = [:]
    var tabs: [TVSeasonTab] = []
    for (index, count) in episodesPerSeason.enumerated() {
      let season = index + 1
      tabs.append(TVSeasonTab(id: season, label: "\(season)", symbol: nil,
                              isAvailable: true, accessibilityLabel: "Сезон \(season)"))
      let card = seasonCard(id: -season)
      items.append(card)
      tabOfItem[card.id] = season
      for episode in 1...count {
        let item = TVUIKitMediaItem(id: season * 100 + episode, caption: "S\(season)E\(episode)")
        items.append(item)
        tabOfItem[item.id] = season
      }
    }
    controller.apply(title: "Сезоны", tabs: tabs, items: items, tabOfItem: tabOfItem,
                     entryByTab: [:], openingItemID: items.dropFirst().first?.id,
                     onSelect: { _ in }, onTabSelected: nil, contextMenuProvider: nil)
  }

  /// One season card plus 6 → 10 episodes: 7 → 11 items, the crash's numbers, with the
  /// mixed season-card layout that reads `items` from its section provider.
  func testSeasonRailGrowsFromSevenToElevenItems() throws {
    let controller = TVSeasonRailController(contentInset: 80, columns: 5)
    host(controller)
    applySeasons(controller, episodesPerSeason: [6])
    controller.view.layoutIfNeeded()
    applySeasons(controller, episodesPerSeason: [10])
    controller.view.layoutIfNeeded()
    let collection = try XCTUnwrap(railCollectionView(in: controller.view))
    XCTAssertEqual(collection.numberOfItems(inSection: 0), 11)
  }

  func testSeasonRailRapidUpdatesWithTwoSeasons() throws {
    let controller = TVSeasonRailController(contentInset: 80, columns: 5)
    host(controller)
    applySeasons(controller, episodesPerSeason: [6])
    for count in 7...10 { applySeasons(controller, episodesPerSeason: [count]) }
    applySeasons(controller, episodesPerSeason: [10, 2])   // a season appears: append
    pump()
    applySeasons(controller, episodesPerSeason: [10, 8])
    applySeasons(controller, episodesPerSeason: [4, 8])    // identities shift: reload
    applySeasons(controller, episodesPerSeason: [4, 12])
    controller.view.layoutIfNeeded()
    let collection = try XCTUnwrap(railCollectionView(in: controller.view))
    XCTAssertEqual(collection.numberOfItems(inSection: 0), 4 + 12 + 2)
  }
}

/// Hosts a rail and, on each of its own layout passes, fully invalidates the rail's
/// collection layout — which marks the collection view's cached item counts stale.
@MainActor
private final class InvalidatingHostController: UIViewController {
  let rail: UIViewController
  weak var collection: UICollectionView?

  init(rail: UIViewController) {
    self.rail = rail
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) { fatalError() }

  override func viewDidLoad() {
    super.viewDidLoad()
    addChild(rail)
    view.addSubview(rail.view)
    rail.didMove(toParent: self)
  }

  override func viewWillLayoutSubviews() {
    super.viewWillLayoutSubviews()
    collection?.collectionViewLayout.invalidateLayout()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    rail.view.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 400)
    collection?.collectionViewLayout.invalidateLayout()
  }
}

/// SplitMix64, so the random sequence is the same on every run.
private struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64
  init(seed: UInt64) { state = seed }
  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
#endif
