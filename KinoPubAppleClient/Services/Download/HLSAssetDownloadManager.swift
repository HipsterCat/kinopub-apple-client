//
//  HLSAssetDownloadManager.swift
//  KinoPubAppleClient
//
//  Downloads HLS streams (master .m3u8) for offline playback using
//  AVAssetDownloadURLSession + AVAggregateAssetDownloadTask so that ALL audio
//  tracks (озвучки) and subtitles are downloaded alongside the video and remain
//  switchable during offline playback.
//
//  IMPORTANT: AVAssetDownloadURLSession / AVAggregateAssetDownloadTask are
//  iOS/tvOS only — NOT available on macOS. All AVAssetDownload* usage is gated
//  behind `#if os(iOS)`. On macOS this type exists as a no-op so shared code
//  (AppContext, DownloadsCatalog, MediaItemModel) compiles unchanged; the macOS
//  download path continues to use the mp4 `DownloadManager`.
//

import Foundation
import Combine
import KinoPubBackend
import KinoPubLogging
import OSLog
import AVFoundation

/// Lightweight, UI-facing description of an in-flight HLS download.
public struct HLSActiveDownload: Identifiable, Equatable {
  public let id: String        // taskDescription key (meta id + video + season)
  public let meta: DownloadMeta
  public var progress: Float
  /// Current transfer rate in bytes/sec (from the .movpkg growing on disk).
  public var speed: Double
  /// Estimated time remaining, derived from the progress rate.
  public var remaining: TimeInterval?
  /// The viewer paused it (its task is suspended).
  public var isPaused: Bool
  /// kino.pub answered 429; the next attempt is scheduled (`earliestBeginDate`).
  public var isWaitingToRetry: Bool

  public init(id: String, meta: DownloadMeta, progress: Float, speed: Double = 0, remaining: TimeInterval? = nil,
              isPaused: Bool = false, isWaitingToRetry: Bool = false) {
    self.id = id
    self.meta = meta
    self.progress = progress
    self.speed = speed
    self.remaining = remaining
    self.isPaused = isPaused
    self.isWaitingToRetry = isWaitingToRetry
  }
}

/// A download that was interrupted by the app being force-quit (its background task didn't survive),
/// so it can't be resumed — surfaced in the UI so the user can re-download it.
public struct HLSInterruptedDownload: Identifiable, Equatable {
  public let id: String   // HLSDownloadKey
  public let meta: DownloadMeta

  public init(id: String, meta: DownloadMeta) {
    self.id = id
    self.meta = meta
  }
}

/// Outcome of trying to start an HLS download, so the UI can tell the user exactly what happened.
public enum HLSDownloadStartResult: Equatable {
  case started
  case alreadyDownloading
  case alreadyDownloaded
  case failed(String)
}

/// Stable key used as the task description so we can re-associate background
/// tasks with their metadata after an app relaunch.
enum HLSDownloadKey {
  static func make(for meta: DownloadMeta) -> String {
    "\(meta.id)|\(meta.metadata.video.map(String.init) ?? "-")|\(meta.metadata.season.map(String.init) ?? "-")"
  }
}

#if os(iOS)
import UIKit

/// A few seconds of background execution for work that must finish before the system
/// suspends the app again (`beginBackgroundTask`). `end()` gives them back.
@MainActor
final class BackgroundWork {
  private var identifier = UIBackgroundTaskIdentifier.invalid

  init(_ name: String) {
    identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
      MainActor.assumeIsolated { self?.end() }
    }
  }

  func end() {
    guard identifier != .invalid else { return }
    UIApplication.shared.endBackgroundTask(identifier)
    identifier = .invalid
  }
}

public final class HLSAssetDownloadManager: NSObject, ObservableObject, AVAssetDownloadDelegate {

  /// In-flight downloads keyed by `HLSDownloadKey`.
  @Published public private(set) var activeDownloads: [HLSActiveDownload] = []
  /// Downloads whose background task didn't survive a force-quit — shown so the user can re-download.
  @Published public private(set) var interrupted: [HLSInterruptedDownload] = []
  /// Last download failure reason, surfaced to the user so a failed download isn't silent.
  @Published public var lastError: String?

  private let store: HLSDownloadsStore
  /// Maximum desired resolution height (px) used to derive a bitrate cap, or nil
  /// for "best available" (adaptive). Injected from the app's StreamQuality
  /// setting where one exists.
  private let maxResolutionProvider: () -> Int?

  /// Notification hooks (mirrors the mp4 path). Optional so macOS / tests can omit.
  public var onDownloadFinished: ((DownloadMeta) -> Void)?
  public var onDownloadFailed: ((DownloadMeta) -> Void)?

  // Per-running-task state.
  private struct TaskContext {
    let meta: DownloadMeta
    let hlsURL: URL
    let retryCount: Int
    var downloadURL: URL?      // the .movpkg location handed to us by the delegate
    // Aggregate progress across every media selection (video + each audio track + subtitles): the
    // delegate reports progress PER selection (each restarts from 0), so we keep the latest fraction
    // of each and average over the total, instead of showing one selection's progress and resetting.
    var totalSelections: Int = 1
    var selectionFractions: [String: Double] = [:]
    /// Loaded once at launch so progress callbacks can key selections without deprecated sync APIs.
    var audibleGroup: AVMediaSelectionGroup?
    var legibleGroup: AVMediaSelectionGroup?
    // Speed (from the .movpkg growing on disk) + ETA (from the progress rate).
    var lastBytes: Int64 = 0
    var lastBytesTime: Date?
    var speed: Double = 0
    var lastProgress: Float = 0
    var lastProgressTime: Date?
    var remaining: TimeInterval?
  }
  private var contexts: [Int: TaskContext] = [:]   // keyed by task.taskIdentifier
  /// The live task of each download, by `HLSDownloadKey` — what pause / resume act on.
  private var tasks: [String: AVAggregateAssetDownloadTask] = [:]

  /// The background session's identifier, for the app delegate to route its wake-up here.
  public static let sessionIdentifier = "com.kinopub.hlsDownloadSession"

  /// Stored by the app delegate when the system wakes the app for this session's events
  /// (`application(_:handleEventsForBackgroundURLSession:completionHandler:)`); called once
  /// the session says it delivered them all.
  public var backgroundCompletionHandler: (() -> Void)?
  /// kino.pub rate-limits (HTTP 429) aggressive HLS downloads; we retry with backoff this many times.
  private let maxRetries = 5

  /// Persisted record of an in-flight download so it can be resumed (background task survived) or
  /// re-offered (force-quit) after a relaunch — the system keeps the task, but the meta lives only in
  /// memory, so without this the delegate can't recover it.
  private struct PendingHLSDownload: Codable, Equatable, Sendable {
    let key: String
    let meta: DownloadMeta
    let hlsURLString: String
    var retryCount: Int
    /// Relative path of the partial `.movpkg` (once the system hands us a location) so we can delete
    /// it on cleanup.
    var partialRelativePath: String?
    /// The viewer paused it. Optional so older entries decode.
    var isPaused: Bool?
  }

  private let pendingFileURL: URL = {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return documents.appendingPathComponent("hlsPendingDownloads.plist")
  }()

  private func readPending() -> [PendingHLSDownload] {
    guard let data = try? Data(contentsOf: pendingFileURL),
          let decoded = try? PropertyListDecoder().decode([PendingHLSDownload].self, from: data) else { return [] }
    return decoded
  }

  private func writePending(_ items: [PendingHLSDownload]) {
    if let data = try? PropertyListEncoder().encode(items) { try? data.write(to: pendingFileURL) }
  }

  private func savePending(_ entry: PendingHLSDownload) {
    var items = readPending()
    items.removeAll { $0.key == entry.key }
    items.append(entry)
    writePending(items)
  }

  private func removePending(key: String) {
    var items = readPending()
    let before = items.count
    items.removeAll { $0.key == key }
    if items.count != before { writePending(items) }
  }

  private func updatePendingPaused(key: String, paused: Bool) {
    var items = readPending()
    guard let idx = items.firstIndex(where: { $0.key == key }) else { return }
    items[idx].isPaused = paused
    writePending(items)
  }

  private func updatePendingPartial(key: String, relativePath: String) {
    var items = readPending()
    guard let idx = items.firstIndex(where: { $0.key == key }) else { return }
    items[idx].partialRelativePath = relativePath
    writePending(items)
  }

  /// Deletes the partial `.movpkg` left behind by an interrupted download, if its location was recorded.
  private func deletePartial(_ entry: PendingHLSDownload) {
    guard let relativePath = entry.partialRelativePath else { return }
    let url = URL(fileURLWithPath: NSHomeDirectory() + "/" + relativePath)
    try? FileManager.default.removeItem(at: url)
  }

  public init(store: HLSDownloadsStore,
              maxResolutionProvider: @escaping () -> Int? = { nil }) {
    self.store = store
    self.maxResolutionProvider = maxResolutionProvider
    super.init()
    // `session` is left genuinely lazy: constructing an AVAssetDownloadURLSession with a
    // background identifier is an XPC round trip to nsurlsessiond (~20-25ms measured on the
    // simulator, likely more on device) on the main thread, since `AppContext.shared` — which
    // owns this instance — is resolved synchronously on the main thread before the first frame.
    // `restorePendingDownloads()` is what actually needs the session to reattach background
    // tasks, and it's deferred off that path (see its call site in `AppContext.shared`).
  }

  private lazy var session: AVAssetDownloadURLSession = {
    let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
    // Not discretionary: a download the viewer asked for runs now, not when the system
    // finds the phone on Wi‑Fi and power. Launch events: the app is woken (relaunched if
    // the system had ended it) to hear a download finished, so the asset is recorded and
    // the next queued one starts while the app stays in the background.
    config.isDiscretionary = false
    config.sessionSendsLaunchEvents = true
    config.allowsCellularAccess = true
    return AVAssetDownloadURLSession(configuration: config,
                                     assetDownloadDelegate: self,
                                     delegateQueue: .main)
  }()

  /// Reconnects to the background session so the system delivers its pending events —
  /// what Apple asks of an app woken by `handleEventsForBackgroundURLSession`.
  public func connect() {
    _ = session
  }

  // MARK: - Public API

  /// Starts (or no-ops if already running) an HLS download of `hlsURL` for `meta`, returning what
  /// happened so the caller can tell the user (including *why* it didn't start).
  @discardableResult
  public func startDownload(meta: DownloadMeta, hlsURL: URL, startPaused: Bool = false) async -> HLSDownloadStartResult {
    let key = HLSDownloadKey.make(for: meta)

    // Already downloading?
    if activeDownloads.contains(where: { $0.id == key }) {
      Logger.kit.debug("[HLS] download already active for key \(key)")
      return .alreadyDownloading
    }
    // Already downloaded?
    if store.asset(forId: meta.id, video: meta.metadata.video, season: meta.metadata.season) != nil {
      Logger.kit.debug("[HLS] asset already downloaded for key \(key)")
      return .alreadyDownloaded
    }
    return await launch(meta: meta, hlsURL: hlsURL, retryCount: 0, startPaused: startPaused)
      ? .started
      : .failed(lastError ?? "Couldn't start download".localized)
  }

  /// Builds and resumes an aggregate download. Attempts 0…maxRetries-2 grab every audio (озвучка) +
  /// subtitle track; the final attempt narrows to the preferred selection (video + default audio) so
  /// a heavily rate-limited title can still complete rather than failing outright.
  @discardableResult
  private func launch(meta: DownloadMeta, hlsURL: URL, retryCount: Int,
                      after delay: TimeInterval = 0, startPaused: Bool = false) async -> Bool {
    let key = HLSDownloadKey.make(for: meta)
    let asset = AVURLAsset(url: hlsURL)
    let narrow = retryCount >= maxRetries - 1

    let preferred: AVMediaSelection
    do {
      preferred = try await asset.load(.preferredMediaSelection)
    } catch {
      Logger.kit.error("[HLS] failed to load preferredMediaSelection for key \(key): \(error)")
      activeDownloads.removeAll(where: { $0.id == key })
      lastError = String(format: "Couldn't start downloading “%@” (the server didn't return a valid HLS stream).".localized,
                         meta.notificationTitle)
      onDownloadFailed?(meta)
      return false
    }

    let audibleGroup = try? await asset.loadMediaSelectionGroup(for: .audible)
    let legibleGroup = try? await asset.loadMediaSelectionGroup(for: .legible)

    var mediaSelections: [AVMediaSelection] = []
    if !narrow, let baseSelection = preferred.mutableCopy() as? AVMutableMediaSelection {
      for group in [audibleGroup, legibleGroup].compactMap({ $0 }) {
        for option in group.options {
          guard let selection = baseSelection.mutableCopy() as? AVMutableMediaSelection else { continue }
          selection.select(option, in: group)
          mediaSelections.append(selection)
        }
      }
    }
    // Always include the preferred selection (video + default tracks).
    mediaSelections.append(preferred)

    var options: [String: Any] = [:]
    if let maxResolution = maxResolutionProvider() {
      let bitrate = max(800_000, (maxResolution / 360) * 2_000_000)
      options[AVAssetDownloadTaskMinimumRequiredMediaBitrateKey] = bitrate
    }

    guard let task = session.aggregateAssetDownloadTask(with: asset,
                                                        mediaSelections: mediaSelections,
                                                        assetTitle: meta.localizedTitle,
                                                        assetArtworkData: nil,
                                                        options: options.isEmpty ? nil : options) else {
      Logger.kit.error("[HLS] failed to create aggregate download task for key \(key)")
      activeDownloads.removeAll(where: { $0.id == key })
      lastError = String(format: "Couldn't start downloading “%@” (the server didn't return a valid HLS stream).".localized,
                         meta.notificationTitle)
      onDownloadFailed?(meta)
      return false
    }

    task.taskDescription = key
    // A retry after 429 waits in the session, not in the app: a `Task.sleep` here never
    // woke up once the app was suspended in the background, and the download stalled.
    if delay > 0 { task.earliestBeginDate = Date().addingTimeInterval(delay) }
    tasks[key] = task
    var context = TaskContext(meta: meta, hlsURL: hlsURL, retryCount: retryCount)
    context.totalSelections = max(1, mediaSelections.count)
    context.audibleGroup = audibleGroup
    context.legibleGroup = legibleGroup
    contexts[task.taskIdentifier] = context
    // Persist so a relaunch can resume (task survived) or re-offer (force-quit) this download.
    savePending(PendingHLSDownload(key: key, meta: meta, hlsURLString: hlsURL.absoluteString,
                                   retryCount: retryCount, partialRelativePath: nil,
                                   isPaused: startPaused))
    interrupted.removeAll { $0.id == key }
    if let idx = activeDownloads.firstIndex(where: { $0.id == key }) {
      activeDownloads[idx].progress = 0   // keep the row visible across retries
      activeDownloads[idx].isWaitingToRetry = delay > 0
      activeDownloads[idx].isPaused = startPaused
    } else {
      activeDownloads.append(HLSActiveDownload(id: key, meta: meta, progress: 0,
                                               isPaused: startPaused, isWaitingToRetry: delay > 0))
    }
    // A created task is suspended until resumed: a queued download (one at a time) waits so.
    if !startPaused { task.resume() }
    lastError = nil
    Logger.kit.debug("[HLS] started download for key \(key) (attempt \(retryCount + 1), narrow: \(narrow))")
    return true
  }

  /// Cancels an in-flight download for the given key and deletes what it fetched.
  public func cancelDownload(key: String) {
    tasks[key] = nil
    session.getAllTasks { [weak self] tasks in
      for task in tasks where task.taskDescription == key {
        task.cancel()
      }
      DispatchQueue.main.async {
        guard let self else { return }
        self.activeDownloads.removeAll(where: { $0.id == key })
        if let entry = self.readPending().first(where: { $0.key == key }) { self.deletePartial(entry) }
        self.removePending(key: key)
      }
    }
  }

  /// Pauses a download: its task is suspended, keeping everything fetched so far.
  public func pauseDownload(key: String) {
    guard let idx = activeDownloads.firstIndex(where: { $0.id == key }) else { return }
    tasks[key]?.suspend()
    activeDownloads[idx].isPaused = true
    activeDownloads[idx].speed = 0
    activeDownloads[idx].remaining = nil
    updatePendingPaused(key: key, paused: true)
  }

  /// Continues a paused (or queued) download.
  public func resumeDownload(key: String) {
    guard let idx = activeDownloads.firstIndex(where: { $0.id == key }) else { return }
    if let task = tasks[key] {
      task.resume()
    } else if let entry = readPending().first(where: { $0.key == key }), let url = URL(string: entry.hlsURLString) {
      // No task to resume (it did not survive): fetch again.
      deletePartial(entry)
      Task { @MainActor [weak self] in
        _ = await self?.launch(meta: entry.meta, hlsURL: url, retryCount: 0)
      }
    }
    activeDownloads[idx].isPaused = false
    updatePendingPaused(key: key, paused: false)
  }

  /// Pauses every running download.
  public func pauseAll() {
    for download in activeDownloads where !download.isPaused {
      pauseDownload(key: download.id)
    }
  }

  /// After a relaunch: reattach any background task that survived (resume — rebuild its context so the
  /// delegate keeps reporting progress and persists on completion), and surface any whose task didn't
  /// survive a force-quit as `interrupted` so the user can re-download. Metadata comes from the
  /// persisted pending store (the system only gives us back the `taskDescription` key).
  public func restorePendingDownloads() {
    let pending = readPending()
    // Reclaim orphaned .movpkg bundles left by failed/cancelled/retried downloads — keeping anything
    // still tracked (saved downloads + in-flight/interrupted partials).
    let keepPartials = Set(pending.compactMap { $0.partialRelativePath })
    DispatchQueue.global(qos: .utility).async { [store] in
      store.sweepOrphans(keepRelativePaths: keepPartials)
    }
    guard !pending.isEmpty else { return }

    session.getAllTasks { [weak self] tasks in
      guard let self else { return }
      var liveTasksByKey: [String: AVAggregateAssetDownloadTask] = [:]
      for task in tasks {
        if let aggregate = task as? AVAggregateAssetDownloadTask, let key = aggregate.taskDescription {
          liveTasksByKey[key] = aggregate
        }
      }

      DispatchQueue.main.async {
        var interruptedNow: [HLSInterruptedDownload] = []
        for entry in pending {
          // Completed in the background while we were away → already in the store; drop the pending row.
          if self.store.asset(forId: entry.meta.id,
                              video: entry.meta.metadata.video,
                              season: entry.meta.metadata.season) != nil {
            self.removePending(key: entry.key)
            continue
          }
          if let task = liveTasksByKey[entry.key], let url = URL(string: entry.hlsURLString) {
            // Background task survived → rebuild context so progress + completion resume.
            if self.contexts[task.taskIdentifier] == nil {
              self.contexts[task.taskIdentifier] = Self.context(from: entry, url: url)
            }
            self.tasks[entry.key] = task
            let paused = entry.isPaused == true
            if !paused, task.state == .suspended { task.resume() }
            if !self.activeDownloads.contains(where: { $0.id == entry.key }) {
              self.activeDownloads.append(HLSActiveDownload(id: entry.key, meta: entry.meta, progress: 0,
                                                            isPaused: paused))
            }
          } else {
            // No live task (force-quit) → can't resume; offer a re-download.
            interruptedNow.append(HLSInterruptedDownload(id: entry.key, meta: entry.meta))
          }
        }
        self.interrupted = interruptedNow
      }
    }
  }

  /// A task's context rebuilt from its persisted record — after the system relaunched the
  /// app for this session's events, the in-memory one is gone. Without the `.movpkg`
  /// location (handed over only once, when the download began) a finished download was
  /// reported as "no file produced" and never saved.
  private static func context(from entry: PendingHLSDownload, url: URL) -> TaskContext {
    var context = TaskContext(meta: entry.meta, hlsURL: url, retryCount: entry.retryCount)
    if let relative = entry.partialRelativePath {
      context.downloadURL = URL(fileURLWithPath: NSHomeDirectory() + "/" + relative)
    }
    return context
  }

  /// The task's context: in memory, or rebuilt from the pending record by its key.
  private func context(for task: URLSessionTask) -> TaskContext? {
    if let context = contexts[task.taskIdentifier] { return context }
    guard let key = task.taskDescription,
          let entry = readPending().first(where: { $0.key == key }),
          let url = URL(string: entry.hlsURLString) else { return nil }
    let context = Self.context(from: entry, url: url)
    contexts[task.taskIdentifier] = context
    if let aggregate = task as? AVAggregateAssetDownloadTask { tasks[key] = aggregate }
    if !activeDownloads.contains(where: { $0.id == key }) {
      activeDownloads.append(HLSActiveDownload(id: key, meta: entry.meta, progress: 0, isPaused: entry.isPaused == true))
    }
    return context
  }

  /// A stable identifier for a media selection (its chosen audio + subtitle options), so progress
  /// callbacks for the same selection update one bucket instead of creating a new one each time.
  private static func selectionKey(for selection: AVMediaSelection,
                                   audible: AVMediaSelectionGroup?,
                                   legible: AVMediaSelectionGroup?) -> String {
    let audio = audible.flatMap { selection.selectedMediaOption(in: $0)?.displayName } ?? "-"
    let subs = legible.flatMap { selection.selectedMediaOption(in: $0)?.displayName } ?? "-"
    return "\(audio)|\(subs)"
  }

  // MARK: - AVAssetDownloadDelegate

  /// Gives us the local `.movpkg` location. Apple: persist the RELATIVE path and
  /// do not move the bundle.
  public func urlSession(_ session: URLSession,
                         aggregateAssetDownloadTask: AVAggregateAssetDownloadTask,
                         willDownloadTo location: URL) {
    Logger.kit.debug("[HLS] willDownloadTo \(location.relativePath)")
    _ = context(for: aggregateAssetDownloadTask)
    contexts[aggregateAssetDownloadTask.taskIdentifier]?.downloadURL = location
    if let key = aggregateAssetDownloadTask.taskDescription {
      updatePendingPartial(key: key, relativePath: location.relativePath)
    }
  }

  /// Progress for the currently-downloading media selection.
  public func urlSession(_ session: URLSession,
                         aggregateAssetDownloadTask: AVAggregateAssetDownloadTask,
                         didLoad timeRange: CMTimeRange,
                         totalTimeRangesLoaded loadedTimeRanges: [NSValue],
                         timeRangeExpectedToLoad: CMTimeRange,
                         for mediaSelection: AVMediaSelection) {
    let id = aggregateAssetDownloadTask.taskIdentifier
    guard var ctx = context(for: aggregateAssetDownloadTask) else { return }

    var loadedSeconds = 0.0
    for value in loadedTimeRanges {
      loadedSeconds += CMTimeGetSeconds(value.timeRangeValue.duration)
    }
    let expected = CMTimeGetSeconds(timeRangeExpectedToLoad.duration)
    guard expected > 0 else { return }

    // Record THIS selection's fraction, then average across all selections so the bar climbs smoothly
    // 0→100 over the whole container instead of resetting each time a new track starts downloading.
    ctx.selectionFractions[Self.selectionKey(for: mediaSelection,
                                             audible: ctx.audibleGroup,
                                             legible: ctx.legibleGroup)] = min(1.0, loadedSeconds / expected)
    let denominator = Double(max(ctx.totalSelections, ctx.selectionFractions.count))
    let progress = Float(min(1.0, ctx.selectionFractions.values.reduce(0, +) / denominator))

    let now = Date()
    // ETA from the progress rate (cheap, no disk access).
    if let last = ctx.lastProgressTime {
      let dt = now.timeIntervalSince(last)
      if dt >= 1.0, progress > ctx.lastProgress {
        let rate = Double(progress - ctx.lastProgress) / dt   // fraction / sec
        if rate > 0 { ctx.remaining = Double(1 - progress) / rate }
        ctx.lastProgress = progress
        ctx.lastProgressTime = now
      }
    } else {
      ctx.lastProgress = progress
      ctx.lastProgressTime = now
    }
    // Speed from the .movpkg growing on disk, sampled every ~2s (enumerating the bundle isn't free).
    if let location = ctx.downloadURL,
       ctx.lastBytesTime == nil || now.timeIntervalSince(ctx.lastBytesTime ?? now) >= 2.0 {
      let bytes = HLSDownloadsStore.directorySize(at: location)
      if let lastTime = ctx.lastBytesTime {
        let dt = now.timeIntervalSince(lastTime)
        if dt > 0 { ctx.speed = max(0, Double(bytes - ctx.lastBytes) / dt) }
      }
      ctx.lastBytes = bytes
      ctx.lastBytesTime = now
    }
    contexts[id] = ctx

    if let key = aggregateAssetDownloadTask.taskDescription,
       let idx = activeDownloads.firstIndex(where: { $0.id == key }) {
      activeDownloads[idx].progress = progress
      activeDownloads[idx].speed = ctx.speed
      activeDownloads[idx].remaining = ctx.remaining
      activeDownloads[idx].isWaitingToRetry = false
    }
  }

  /// Completion. On success persist a record (relative path); on failure notify.
  public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    let id = task.taskIdentifier
    guard let ctx = context(for: task) else { return }
    let key = task.taskDescription ?? HLSDownloadKey.make(for: ctx.meta)
    contexts[id] = nil
    if tasks[key]?.taskIdentifier == id { tasks[key] = nil }

    if let error = error as NSError? {
      // Cancellation isn't a "failure" worth notifying about.
      if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled {
        Logger.kit.debug("[HLS] download cancelled for key \(key)")
        activeDownloads.removeAll(where: { $0.id == key })
        removePending(key: key)
        return
      }
      // kino.pub rate-limits aggressive HLS downloads (HTTP 429 → CoreMedia -16845). These are
      // transient: wait with exponential backoff and resume — AVFoundation keeps the partial
      // .movpkg, and the final retry narrows to the default track so it can finish.
      let rateLimited = error.code == -16845 || error.localizedDescription.contains("429")
      if rateLimited, ctx.retryCount < maxRetries {
        let delays: [UInt64] = [5, 15, 30, 60, 120]
        let seconds = delays[min(ctx.retryCount, delays.count - 1)]
        let next = ctx.retryCount + 1
        // The failed attempt's partial .movpkg won't be reused by the fresh task — delete it so
        // retries don't pile up abandoned bundles (the main cause of runaway disk usage).
        if let partial = ctx.downloadURL {
          try? FileManager.default.removeItem(at: partial)
        }
        Logger.kit.error("[HLS] rate-limited (429) for key \(key); retry \(next + 1) in \(seconds)s")
        // The next task is created now and told when to begin, so the session waits — not
        // the app, which the system suspends in the background. A short background task
        // covers loading the playlist the new task needs.
        Task { @MainActor [weak self] in
          let work = BackgroundWork("HLS retry")
          _ = await self?.launch(meta: ctx.meta, hlsURL: ctx.hlsURL, retryCount: next, after: TimeInterval(seconds))
          work.end()
        }
        return  // keep the active row visible while we wait
      }
      Logger.kit.error("[HLS] download failed for key \(key): \(error)")
      activeDownloads.removeAll(where: { $0.id == key })
      removePending(key: key)
      lastError = String(format: "“%@” failed to download: %@".localized,
                         ctx.meta.notificationTitle, error.localizedDescription)
      onDownloadFailed?(ctx.meta)
      return
    }

    activeDownloads.removeAll(where: { $0.id == key })
    guard let location = ctx.downloadURL else {
      Logger.kit.error("[HLS] download finished but no location for key \(key)")
      removePending(key: key)
      lastError = String(format: "“%@” failed to download (no file was produced).".localized,
                         ctx.meta.notificationTitle)
      onDownloadFailed?(ctx.meta)
      return
    }

    let asset = HLSDownloadedAsset(meta: ctx.meta,
                                   relativePath: location.relativePath,
                                   downloadDate: Date())
    store.save(asset)
    removePending(key: key)
    Logger.kit.info("[HLS] download finished for key \(key)")
    onDownloadFinished?(ctx.meta)
  }

  /// The session delivered every event it held for the app; the system may suspend it again.
  public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    Logger.kit.debug("[HLS] background session finished events")
    let handler = backgroundCompletionHandler
    backgroundCompletionHandler = nil
    handler?()
  }

  // MARK: - Resume / re-download after relaunch

  /// Re-download an interrupted item from scratch (deleting any stale partial first).
  public func retryInterrupted(_ key: String) {
    guard let entry = readPending().first(where: { $0.key == key }),
          let url = URL(string: entry.hlsURLString) else {
      interrupted.removeAll { $0.id == key }
      return
    }
    deletePartial(entry)
    interrupted.removeAll { $0.id == key }
    Task { @MainActor [weak self] in
      _ = await self?.launch(meta: entry.meta, hlsURL: url, retryCount: 0)
    }
  }

  /// Drop an interrupted item and clean up its partial `.movpkg`.
  public func dismissInterrupted(_ key: String) {
    if let entry = readPending().first(where: { $0.key == key }) {
      deletePartial(entry)
    }
    removePending(key: key)
    interrupted.removeAll { $0.id == key }
  }
}

#else

// macOS (and any non-iOS platform): no-op shim with the same public surface so
// shared code compiles. The mp4 DownloadManager handles downloads on macOS.
public final class HLSAssetDownloadManager: ObservableObject {

  @Published public private(set) var activeDownloads: [HLSActiveDownload] = []
  @Published public private(set) var interrupted: [HLSInterruptedDownload] = []
  @Published public var lastError: String?

  public var onDownloadFinished: ((DownloadMeta) -> Void)?
  public var onDownloadFailed: ((DownloadMeta) -> Void)?

  public init(store: HLSDownloadsStore,
              maxResolutionProvider: @escaping () -> Int? = { nil }) {}

  @discardableResult
  public func startDownload(meta: DownloadMeta, hlsURL: URL, startPaused: Bool = false) async -> HLSDownloadStartResult {
    Logger.kit.debug("[HLS] HLS downloads are not supported on this platform; ignoring.")
    return .failed("HLS downloads are not supported on this platform.")
  }

  public var backgroundCompletionHandler: (() -> Void)?
  public static let sessionIdentifier = "com.kinopub.hlsDownloadSession"

  public func connect() {}

  public func cancelDownload(key: String) {}

  public func pauseDownload(key: String) {}

  public func resumeDownload(key: String) {}

  public func pauseAll() {}

  public func restorePendingDownloads() {}

  public func retryInterrupted(_ key: String) {}

  public func dismissInterrupted(_ key: String) {}
}

#endif
