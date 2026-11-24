//
//  Download.swift
//
//
//  Created by Kirill Kunst on 22.07.2023.
//

import Foundation
import KinoPubLogging
import OSLog

/// `Download` represents a downloadable resource. It provides methods for controlling the download,
/// such as pausing and resuming, and notifies about the progress through a progress handler.
/// Main actor: its state drives the screens, and `DownloadManager` brings the session's
/// callbacks there before they reach it.
@MainActor
public final class Download<Meta: Codable & Equatable & Sendable>: ObservableObject {
  /// The state of the download, such as not started, queued, in progress, or paused.
  public enum State: String {
    case notStarted
    case queued
    case inProgress
    case paused
  }
  
  /// URL for the download
  public let url: URL

  /// The current state of the download. Published so a pause / resume redraws its row.
  @Published public internal(set) var state: State = .notStarted

  /// Progress value
  @Published public private(set) var progress: Float = 0.0

  /// Bytes received so far and the expected total (for size / ETA display).
  @Published public private(set) var bytesWritten: Int64 = 0
  public private(set) var totalBytes: Int64 = 0

  /// Current transfer rate in bytes/sec (smoothed over ~0.5s samples).
  @Published public private(set) var speed: Double = 0

  private var lastSampleTime: Date?
  private var lastSampleBytes: Int64 = 0

  /// Estimated time remaining, or nil when it can't be computed yet.
  public var remainingTime: TimeInterval? {
    guard speed > 0, totalBytes > bytesWritten else { return nil }
    return Double(totalBytes - bytesWritten) / speed
  }

  /// Public metadata
  public let metadata: Meta

  // - Internal
  internal var task: URLSessionDownloadTask?

  /// Resume data produced when the download is paused. Exposed so the manager can persist it
  /// and restore paused downloads across app launches.
  internal var resumeData: Data?

  private let manager: any DownloadManaging

  /// Notifies the manager that this download's persistable state changed (paused / progress checkpoint).
  internal var onStateChange: ((Download<Meta>) -> Void)?

  /// Initializes a `Download` object.
  /// - Parameters:
  ///   - url: The URL of the resource to be downloaded.
  ///   - metadata: Metadata associated with the download.
  ///   - manager: An object that conforms to `DownloadManaging` to manage the download session.
  ///   - resumeData: Optional resume data used to restore a previously paused download.
  ///   - progress: Optional initial progress value used when restoring a download.
  public init(url: URL,
              metadata: Meta,
              manager: any DownloadManaging,
              resumeData: Data? = nil,
              progress: Float = 0.0) {
    self.url = url
    self.metadata = metadata
    self.manager = manager
    self.resumeData = resumeData
    self.progress = progress
    self.state = resumeData != nil ? .paused : .queued
    Logger.kit.debug("[DOWNLOAD] Download for url: \(url) is \(self.state.rawValue)")
  }

  /// Pauses the download, keeping resume data so `resume()` picks up where it stopped.
  /// The state flips at once: the session's "cancelled" completion that follows must find
  /// a paused download, not a failed one (it used to drop the row from the list).
  public func pause() {
    guard state != .paused else { return }
    state = .paused
    speed = 0
    let pausing = task
    task = nil
    // The session calls back on its delegate queue.
    pausing?.cancel(byProducingResumeData: { @Sendable [weak self] data in
      DispatchQueue.main.async {
        guard let self else { return }
        if let data { self.resumeData = data }
        Logger.kit.debug("[DOWNLOAD] Download for url: \(self.url.absoluteString) is paused (resume data: \(data != nil))")
        self.onStateChange?(self)
      }
    })
    onStateChange?(self)
  }

  /// Stops the download for good: no resume data, nothing persisted afterwards.
  public func cancel() {
    onStateChange = nil
    task?.cancel()
    task = nil
    resumeData = nil
    state = .notStarted
  }

  /// Resumes the download. If the download is already in progress, this method has no effect.
  public func resume() {
    if task != nil, state == .inProgress { return }
    if let resumeData = self.resumeData {
      task = manager.session.downloadTask(withResumeData: resumeData)
      self.resumeData = nil
    } else {
      task = manager.session.downloadTask(with: URLRequest(url: url))
    }
    state = .inProgress
    Logger.kit.debug("[DOWNLOAD] Download for url: \(self.url) is in progress")
    task?.resume()
    onStateChange?(self)
  }

  /// A task the background session kept running while the app was gone (or suspended):
  /// adopt it instead of starting a second copy of the same file.
  internal func attach(_ task: URLSessionDownloadTask) {
    self.task = task
    state = task.state == .running ? .inProgress : .paused
    if task.state == .suspended { task.resume(); state = .inProgress }
  }

  /// The session stopped the transfer (network, the system) and left resume data: the row
  /// stays, paused, so a tap continues it.
  internal func interrupted(resumeData: Data?) {
    task = nil
    if let resumeData { self.resumeData = resumeData }
    state = .paused
    speed = 0
    onStateChange?(self)
  }

  /// True while this download has a live session task.
  public var hasTask: Bool { task != nil }

  internal func updateProgress(_ progress: Float) {
    self.progress = progress
  }

  /// Updates byte counters and recomputes the transfer rate from ~0.5s samples.
  internal func updateTransfer(bytesWritten: Int64, totalBytes: Int64) {
    let now = Date()
    if let last = lastSampleTime {
      let dt = now.timeIntervalSince(last)
      if dt >= 0.5 {
        speed = max(0, Double(bytesWritten - lastSampleBytes) / dt)
        lastSampleTime = now
        lastSampleBytes = bytesWritten
      }
    } else {
      lastSampleTime = now
      lastSampleBytes = bytesWritten
    }
    self.bytesWritten = bytesWritten
    self.totalBytes = totalBytes
  }

}

extension Download: Identifiable {}
