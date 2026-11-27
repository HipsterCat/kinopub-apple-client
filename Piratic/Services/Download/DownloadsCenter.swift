//
//  DownloadsCenter.swift
//  Piratic
//
//  One place every screen asks about downloads: what is in flight (HLS `.movpkg` on
//  iPhone and iPad, mp4 everywhere else and as their fallback), what is on disk, and the
//  controls the Apple TV app's Activity window has — pause and continue one, pause all,
//  and Simultaneous Downloads (off: one at a time, the rest wait their turn).
//
//  Before this the Downloads screen read only the mp4 manager, so a film downloaded as
//  HLS on an iPhone never showed up in it, and each caller picked an engine on its own.
//

import Foundation
import Combine
import KinoPubBackend
import PiraticKit
import PiraticLogging
import OSLog

/// A download that has not finished yet, whichever engine runs it.
struct DownloadActivity: Identifiable, Equatable {
  enum Engine: Equatable {
    /// `HLSAssetDownloadManager`, by its `HLSDownloadKey`.
    case stream(key: String)
    /// `DownloadManager` (mp4), by the file's URL.
    case file(URL)
  }

  enum Phase: Equatable {
    case downloading
    case paused
    /// Waiting for its turn (Simultaneous Downloads off).
    case queued
    /// kino.pub asked to slow down (429); the next attempt is scheduled.
    case retrying
    /// The app was force quit and the system dropped the transfer: it can only start over.
    case interrupted
  }

  let id: String
  let engine: Engine
  let meta: DownloadMeta
  var progress: Double
  var phase: Phase
  /// Bytes so far and expected; 0 when the engine does not know (HLS knows neither total).
  var bytesWritten: Int64 = 0
  var totalBytes: Int64 = 0
  var speed: Double = 0
  var remaining: TimeInterval?

  var isActive: Bool { phase == .downloading || phase == .retrying }
}

/// A download on disk, ready to play offline.
struct DownloadedTitle: Identifiable {
  enum Source {
    case stream(HLSDownloadedAsset)
    case file(DownloadedFileInfo<DownloadMeta>)
  }

  let id: String
  let meta: DownloadMeta
  let date: Date
  let source: Source

  var localURL: URL {
    switch source {
    case .stream(let asset): asset.localFileURL
    case .file(let info): info.localFileURL
    }
  }

  /// Bytes on disk: a `.movpkg` is a folder, an mp4 a file.
  nonisolated static func diskSize(at url: URL) -> Int64 {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
    if isDirectory.boolValue { return HLSDownloadsStore.directorySize(at: url) }
    let size = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize
    return Int64(size ?? 0)
  }
}

@MainActor
final class DownloadsCenter: ObservableObject {

  @Published private(set) var activities: [DownloadActivity] = []
  @Published private(set) var downloaded: [DownloadedTitle] = []

  /// The Activity window's checkbox, as the TV app has it; on by default, as there.
  @Published var simultaneous: Bool {
    didSet {
      guard simultaneous != oldValue else { return }
      UserDefaults.standard.set(simultaneous, forKey: Self.simultaneousKey)
      if simultaneous {
        let waiting = queued
        queued = []
        for id in waiting { activities.first(where: { $0.id == id }).map(resumeNow) }
      }
      rebalance()
    }
  }

  static let simultaneousKey = "downloads.simultaneous"
  private static let queuedKey = "downloads.queued"

  /// Downloads held back by Simultaneous Downloads being off, in the order they wait.
  private var queued: [String] {
    didSet { UserDefaults.standard.set(queued, forKey: Self.queuedKey) }
  }

  private let downloadManager: DownloadManager<DownloadMeta>
  private let hlsManager: HLSAssetDownloadManager
  private let hlsStore: HLSDownloadsStore
  private let filesDatabase: DownloadedFilesDatabase<DownloadMeta>
  private let library: MediaLibraryStore
  private var cancellables = Set<AnyCancellable>()
  private var downloadObservers: [URL: AnyCancellable] = [:]
  private let changes = PassthroughSubject<Void, Never>()

  init(downloadManager: DownloadManager<DownloadMeta>,
       hlsManager: HLSAssetDownloadManager,
       hlsStore: HLSDownloadsStore,
       filesDatabase: DownloadedFilesDatabase<DownloadMeta>,
       library: MediaLibraryStore) {
    self.downloadManager = downloadManager
    self.hlsManager = hlsManager
    self.hlsStore = hlsStore
    self.filesDatabase = filesDatabase
    self.library = library
    simultaneous = UserDefaults.standard.object(forKey: Self.simultaneousKey) as? Bool ?? true
    queued = UserDefaults.standard.stringArray(forKey: Self.queuedKey) ?? []

    downloadManager.$activeDownloads
      .receive(on: DispatchQueue.main)
      .sink { [weak self] downloads in
        MainActor.assumeIsolated { self?.observe(downloads) }
      }
      .store(in: &cancellables)
    hlsManager.objectWillChange
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        MainActor.assumeIsolated { self?.changes.send() }
      }
      .store(in: &cancellables)
    // Progress arrives many times a second per download; the lists redraw at most four.
    changes
      .throttle(for: .milliseconds(250), scheduler: DispatchQueue.main, latest: true)
      .sink { [weak self] in
        MainActor.assumeIsolated { self?.rebuild() }
      }
      .store(in: &cancellables)
    rebuild()
    reloadDownloaded()
  }

  // MARK: - Reading

  /// Downloads running or waiting — what the Mac's sidebar button and the Activity
  /// window show.
  var hasActivity: Bool { !activities.isEmpty }

  var isAnyActive: Bool { activities.contains(where: \.isActive) }

  /// One fraction for everything in flight, for a progress ring.
  var overallProgress: Double {
    let running = activities.filter { $0.phase != .interrupted }
    guard !running.isEmpty else { return 0 }
    return running.map(\.progress).reduce(0, +) / Double(running.count)
  }

  // MARK: - Starting

  /// Starts downloading `file` of a playable: offline HLS where the platform has it (all
  /// dubs and subtitles stay switchable), the mp4 otherwise or when HLS refuses. Waits its
  /// turn when Simultaneous Downloads is off and something is already downloading.
  /// Sidecar SRTs are fetched while online and rewritten onto `meta` before the transfer.
  func start(meta: DownloadMeta, file: FileInfo) {
    guard FeatureFlags.downloadsEnabled else { return }
    let waits = !simultaneous && isAnyActive
    Task { @MainActor in
      let ready = await SubtitleSidecarStore.localize(meta)
#if os(iOS)
      if let hls = URL(string: file.url.hls4), !file.url.hls4.isEmpty {
        let result = await hlsManager.startDownload(meta: ready, hlsURL: hls, startPaused: waits)
        switch result {
        case .started:
          if waits { enqueue(HLSDownloadKey.make(for: ready)) }
        case .alreadyDownloading, .alreadyDownloaded:
          return
        case .failed(let reason):
          Logger.app.error("[DOWNLOADS] HLS refused \(ready.notificationTitle): \(reason); trying the file")
          startFile(meta: ready, file: file, waits: waits)
        }
        return
      }
#endif
      startFile(meta: ready, file: file, waits: waits)
    }
  }

  private func startFile(meta: DownloadMeta, file: FileInfo, waits: Bool) {
    guard let url = URL(string: file.url.http), !file.url.http.isEmpty else {
      Logger.app.error("[DOWNLOADS] no link to download \(meta.notificationTitle)")
      return
    }
    guard downloadManager.activeDownloads[url] == nil else { return }
    let download = downloadManager.startDownload(url: url, withMetadata: meta)
    if waits {
      download.pause()
      enqueue(url.absoluteString)
    }
  }

  private func enqueue(_ id: String) {
    if !queued.contains(id) { queued.append(id) }
    changes.send()
  }

  // MARK: - Controls

  func pause(_ activity: DownloadActivity) {
    queued.removeAll { $0 == activity.id }
    switch activity.engine {
    case .stream(let key): hlsManager.pauseDownload(key: key)
    case .file(let url): downloadManager.activeDownloads[url]?.pause()
    }
    changes.send()
  }

  /// Continues a paused download — or lines it up next, when only one may run at a time.
  func resume(_ activity: DownloadActivity) {
    if activity.phase == .interrupted {
      retry(activity)
      return
    }
    if !simultaneous, activities.contains(where: { $0.isActive && $0.id != activity.id }) {
      queued.removeAll { $0 == activity.id }
      queued.insert(activity.id, at: 0)
      changes.send()
      return
    }
    queued.removeAll { $0 == activity.id }
    resumeNow(activity)
  }

  private func resumeNow(_ activity: DownloadActivity) {
    switch activity.engine {
    case .stream(let key): hlsManager.resumeDownload(key: key)
    case .file(let url): downloadManager.activeDownloads[url]?.resume()
    }
    changes.send()
  }

  /// Stops a download and throws away what it fetched.
  func cancel(_ activity: DownloadActivity) {
    queued.removeAll { $0 == activity.id }
    switch activity.engine {
    case .stream(let key):
      if activity.phase == .interrupted {
        hlsManager.dismissInterrupted(key)
      } else {
        hlsManager.cancelDownload(key: key)
      }
    case .file(let url):
      downloadManager.removeDownload(for: url)
    }
    changes.send()
  }

  func retry(_ activity: DownloadActivity) {
    guard case .stream(let key) = activity.engine else { return }
    hlsManager.retryInterrupted(key)
  }

  /// «Pause Downloads»: everything stops where it is.
  func pauseAll() {
    queued = []
    hlsManager.pauseAll()
    downloadManager.pauseAll()
    changes.send()
  }

  /// «Resume Downloads»: everything paused continues (one at a time when that is the rule).
  func resumeAll() {
    for activity in activities where activity.phase == .paused || activity.phase == .queued {
      if simultaneous {
        resumeNow(activity)
      } else if !queued.contains(activity.id) {
        queued.append(activity.id)
      }
    }
    changes.send()
  }

  // MARK: - On disk

  func reloadDownloaded() {
    var titles: [DownloadedTitle] = []
    for asset in hlsStore.readData() where asset.fileExists {
      titles.append(DownloadedTitle(id: "hls:" + asset.relativePath, meta: asset.meta,
                                    date: asset.downloadDate, source: .stream(asset)))
    }
    for info in filesDatabase.readData() ?? []
    where FileManager.default.fileExists(atPath: info.localFileURL.path) {
      titles.append(DownloadedTitle(id: "file:" + info.originalURL.absoluteString, meta: info.metadata,
                                    date: info.downloadDate, source: .file(info)))
    }
    downloaded = titles.sorted { $0.date > $1.date }
  }

  func delete(_ title: DownloadedTitle) {
    switch title.source {
    case .stream(let asset): hlsStore.remove(asset)
    case .file(let info): filesDatabase.remove(fileInfo: info)
    }
    library.deleteDownload(itemId: title.meta.id, video: title.meta.metadata.video,
                           season: title.meta.metadata.season)
    reloadDownloaded()
  }

  // MARK: - Building the list

  private func observe(_ downloads: [URL: Download<DownloadMeta>]) {
    downloadObservers = downloadObservers.filter { downloads[$0.key] != nil }
    for (url, download) in downloads where downloadObservers[url] == nil {
      downloadObservers[url] = download.objectWillChange
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
          MainActor.assumeIsolated { self?.changes.send() }
        }
    }
    changes.send()
  }

  private func rebuild() {
    var rows: [DownloadActivity] = []
    for hls in hlsManager.activeDownloads {
      let phase: DownloadActivity.Phase =
        hls.isWaitingToRetry ? .retrying
        : hls.isPaused ? (queued.contains(hls.id) ? .queued : .paused)
        : .downloading
      rows.append(DownloadActivity(id: hls.id, engine: .stream(key: hls.id), meta: hls.meta,
                                   progress: Double(hls.progress), phase: phase,
                                   speed: hls.speed, remaining: hls.remaining))
    }
    for lost in hlsManager.interrupted {
      rows.append(DownloadActivity(id: lost.id, engine: .stream(key: lost.id), meta: lost.meta,
                                   progress: 0, phase: .interrupted))
    }
    for download in downloadManager.activeDownloads.values.sorted(by: { $0.url.absoluteString < $1.url.absoluteString }) {
      let id = download.url.absoluteString
      let phase: DownloadActivity.Phase = switch download.state {
      case .inProgress: .downloading
      case .paused: queued.contains(id) ? .queued : .paused
      case .queued, .notStarted: .queued
      }
      rows.append(DownloadActivity(id: id, engine: .file(download.url), meta: download.metadata,
                                   progress: Double(download.progress), phase: phase,
                                   bytesWritten: download.bytesWritten, totalBytes: download.totalBytes,
                                   speed: download.speed, remaining: download.remainingTime))
    }
    // Waiting ones in the order they wait, after whatever runs.
    let order = Dictionary(queued.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    rows.sort { lhs, rhs in
      (order[lhs.id] ?? -1, lhs.meta.notificationTitle) < (order[rhs.id] ?? -1, rhs.meta.notificationTitle)
    }
    let finishedSomething = rows.count < activities.count
    if rows != activities { activities = rows }
    // Forget waiting ids whose download is gone (finished, cancelled elsewhere).
    let live = Set(rows.map(\.id))
    if queued.contains(where: { !live.contains($0) }) { queued.removeAll { !live.contains($0) } }
    if finishedSomething { reloadDownloaded() }
    rebalance()
  }

  /// Simultaneous Downloads off: one runs, the rest wait; when it ends the next starts —
  /// also in the background, where a finished task wakes the app.
  private func rebalance() {
    guard !simultaneous else { return }
    let running = activities.filter(\.isActive)
    if running.count > 1 {
      for extra in running.dropFirst() {
        switch extra.engine {
        case .stream(let key): hlsManager.pauseDownload(key: key)
        case .file(let url): downloadManager.activeDownloads[url]?.pause()
        }
        if !queued.contains(extra.id) { queued.insert(extra.id, at: 0) }
      }
      changes.send()
    } else if running.isEmpty, let next = queued.first,
              let activity = activities.first(where: { $0.id == next }) {
      queued.removeFirst()
      resumeNow(activity)
    }
  }
}
