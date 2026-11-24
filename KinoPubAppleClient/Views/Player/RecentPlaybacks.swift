//
//  RecentPlaybacks.swift
//  KinoPubAppleClient
//
//  macOS: what was played last, for File › Open Recent and the Dock menu — the two places
//  IINA (and every document app) lists it (Sasha, 2026-11-23). One line per title, the
//  newest first; choosing one plays that film or that episode again, from where it was
//  left (the player's own resume point).
//

#if os(macOS)
import AppKit
import SwiftUI
import KinoPubBackend
import KinoPubKit
import KinoPubMedia
import KinoPubLogging
import OSLog

@MainActor
final class RecentPlaybacks: ObservableObject {

  static let shared = RecentPlaybacks()
  /// The system's own default for Open Recent.
  static let limit = 10
  private static let storageKey = "RecentPlaybacks.v1"

  struct Entry: Codable, Hashable, Identifiable {
    /// The kino.pub item (the film, the series).
    let titleID: Int
    let title: String
    /// «S1, E2: Name», a concert part — nil for a film played as a whole.
    let detail: String?
    let season: Int?
    /// Episode number in `season`, or the video number of a title in several parts.
    let video: Int?

    var id: Int { titleID }
    var menuTitle: String {
      guard let detail, !detail.isEmpty, detail != title else { return title }
      return "\(title) — \(detail)"
    }
  }

  @Published private(set) var entries: [Entry]

  private init() {
    if let data = UserDefaults.standard.data(forKey: Self.storageKey),
       let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
      entries = decoded
    } else {
      entries = []
    }
  }

  /// A film or episode started in the player window. Trailers and TV channels are not
  /// recents: neither is something one goes back to.
  func record(_ item: any PlayableItem, mode: WatchMode) {
    guard mode == .media else { return }
    if let entry = Self.entry(for: item, fallbackTitle: nil) {
      insert(entry)
      return
    }
    // An episode handed over without its series name, and no snapshot of the series yet:
    // the name comes with the item, which the player fetches anyway (cached).
    let titleID = item.metadata.id
    Logger.app.info("Recents: no title for \(String(describing: type(of: item)), privacy: .public) of item \(titleID), fetching it")
    // Everything but the name, now; the Task carries only these values.
    guard let pending = Self.entry(for: item, fallbackTitle: "-") else { return }
    Task {
      do {
        let title = try await AppContext.shared.contentService.fetchDetails(for: "\(titleID)").item.localizedTitle
        guard !title.isEmpty else { return }
        insert(Entry(titleID: pending.titleID, title: title, detail: pending.detail,
                     season: pending.season, video: pending.video))
      } catch {
        Logger.app.error("Recents: item \(titleID) title fetch failed: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  private func insert(_ entry: Entry) {
    Logger.app.info("Recents: \(entry.titleID) «\(entry.menuTitle, privacy: .public)»")
    var next = entries.filter { $0.titleID != entry.titleID }
    next.insert(entry, at: 0)
    if next.count > Self.limit { next.removeLast(next.count - Self.limit) }
    guard next != entries else { return }
    entries = next
    save()
  }

  func clear() {
    entries = []
    save()
  }

  private func save() {
    if let data = try? JSONEncoder().encode(entries) {
      UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
  }

  private static func entry(for item: any PlayableItem, fallbackTitle: String?) -> Entry? {
    let titleID = item.metadata.id
    guard titleID > 0 else { return nil }
    let snapshotTitle = fallbackTitle
      ?? AppContext.shared.localProgressStore.snapshot(for: titleID)?.localizedTitle
    if let episode = item as? Episode {
      let title = [episode.seriesTitle, snapshotTitle].compactMap { $0 }.first { !$0.isEmpty }
      guard let title else { return nil }
      let detail = EpisodeText(season: episode.seasonNumber, number: episode.number,
                               name: EpisodeTitle.meaningful(episode.title))
        .formatted(.medium)
      return Entry(titleID: titleID, title: title, detail: detail,
                   season: episode.seasonNumber, video: episode.number)
    }
    if let variant = item as? PlaybackVariant {
      let show = variant.movieTitle.trimmingCharacters(in: .whitespacesAndNewlines)
      let title = show.isEmpty ? (snapshotTitle ?? variant.name ?? "") : show
      guard !title.isEmpty else { return nil }
      return Entry(titleID: titleID, title: title, detail: variant.name,
                   season: nil, video: variant.number)
    }
    if let media = item as? MediaItem {
      guard !media.localizedTitle.isEmpty else { return nil }
      return Entry(titleID: titleID, title: media.localizedTitle, detail: nil, season: nil, video: nil)
    }
    if let download = item as? DownloadMeta {
      guard !download.localizedTitle.isEmpty else { return nil }
      return Entry(titleID: titleID, title: download.localizedTitle, detail: nil,
                   season: item.metadata.season, video: item.metadata.video)
    }
    return nil
  }

  // MARK: Open

  /// Plays `entry` again: the title is fetched fresh (links expire), the same episode or
  /// part found in it, and the player window opened on it.
  func open(_ entry: Entry) {
    Task {
      do {
        var item = try await AppContext.shared.contentService.fetchDetails(for: "\(entry.titleID)").item
        item.stampSeasons()
        AppContext.shared.localProgressStore.cacheItem(item)
        PlaybackWindowState.shared.open(item: Self.playable(entry, in: item), mode: .media)
      } catch {
        Logger.app.error("Open Recent: \(entry.titleID) failed: \(error.localizedDescription, privacy: .public)")
        NSSound.beep()
      }
    }
  }

  private static func playable(_ entry: Entry, in item: MediaItem) -> any PlayableItem {
    if let seasonNumber = entry.season, let number = entry.video,
       let season = item.seasons?.first(where: { $0.number == seasonNumber }),
       let episode = season.episodes.first(where: { $0.number == number }) {
      return episode.stamped(season: season.number, mediaId: item.id, seriesTitle: item.localizedTitle)
    }
    if let number = entry.video,
       let variant = item.playbackVariants.first(where: { $0.number == number }) {
      return variant
    }
    return item
  }

  // MARK: Dock menu

  /// The Dock menu's recents, above the system's window list (IINA's order).
  func dockMenu() -> NSMenu? {
    guard !entries.isEmpty else { return nil }
    let menu = NSMenu()
    for entry in entries {
      let item = NSMenuItem(title: entry.menuTitle, action: #selector(DockTarget.open(_:)), keyEquivalent: "")
      item.target = DockTarget.shared
      item.representedObject = entry.titleID
      menu.addItem(item)
    }
    return menu
  }

  /// `NSMenuItem` needs an Objective-C target.
  @MainActor
  final class DockTarget: NSObject {
    static let shared = DockTarget()

    @objc func open(_ sender: NSMenuItem) {
      guard let id = sender.representedObject as? Int,
            let entry = RecentPlaybacks.shared.entries.first(where: { $0.titleID == id }) else { return }
      RecentPlaybacks.shared.open(entry)
    }
  }
}

/// File › Open Recent, with Clear Menu at the bottom as in every Mac app.
struct OpenRecentMenu: View {
  @ObservedObject private var recents = RecentPlaybacks.shared
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Menu("Open Recent") {
      ForEach(recents.entries) { entry in
        Button(entry.menuTitle) {
          PlaybackWindowState.shared.opener = openWindow
          recents.open(entry)
        }
      }
      Divider()
      Button("Clear Menu") { recents.clear() }
        .disabled(recents.entries.isEmpty)
    }
  }
}
#endif
