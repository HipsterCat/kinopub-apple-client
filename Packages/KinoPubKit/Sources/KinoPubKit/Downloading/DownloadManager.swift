//
//  DownloadManager.swift
//
//
//  Created by Kirill Kunst on 22.07.2023.
//

import Foundation
import Combine
import OSLog
import KinoPubLogging

public protocol DownloadManaging {
  associatedtype Meta: Codable & Equatable & Sendable

  var session: URLSession { get }
  func startDownload(url: URL, withMetadata metadata: Meta) -> Download<Meta>
  func removeDownload(for url: URL)
  func completeDownload(_ url: URL)
}

/// Lets a download's metadata supply a human-readable base filename (no extension), so saved files
/// read like "Бесстыжие S10E1 (480p).mp4" in the Files app instead of an opaque CDN hash.
public protocol DownloadFileNaming {
  var downloadFileBaseName: String? { get }
}

public final class DownloadManager<Meta: Codable & Equatable & Sendable>: NSObject, URLSessionDownloadDelegate, DownloadManaging, ObservableObject, @unchecked Sendable {
  @Published public var activeDownloads: [URL: Download<Meta>] = [:]
  private var fileSaver: FileSaving
  private var database: DownloadedFilesDatabase<Meta>
  private var controlDatabase: DownloadsControlDatabase<Meta>?

  /// Completion handler stored by the app delegate when the system relaunches the app to finish
  /// background URLSession events. Invoked once the session reports it finished delivering events.
  public var backgroundCompletionHandler: (() -> Void)?

  /// Invoked on the main thread when a download finishes successfully. The app uses this to post a
  /// local notification and to advance season-download groups. Kept generic so KinoPubKit stays
  /// UI- and platform-agnostic.
  public var onDownloadFinished: ((_ url: URL, _ metadata: Meta) -> Void)?

  /// Invoked on the main thread when a download fails with an error.
  public var onDownloadFailed: ((_ url: URL, _ metadata: Meta, _ error: Error) -> Void)?

  public init(fileSaver: FileSaving,
              database: DownloadedFilesDatabase<Meta>,
              controlDatabase: DownloadsControlDatabase<Meta>? = nil) {
    self.fileSaver = fileSaver
    self.database = database
    self.controlDatabase = controlDatabase
    super.init()
    restoreDownloads()
  }

  lazy public var session: URLSession = {
    let identifier = "com.kinopub.backgroundDownloadSession"
    let config = URLSessionConfiguration.background(withIdentifier: identifier)
    // Without this the system treats background transfers as discretionary and may defer them
    // indefinitely (downloads appear stuck / never start, especially in the simulator).
    config.isDiscretionary = false
    config.sessionSendsLaunchEvents = true
    config.allowsCellularAccess = true
    return URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }()

  public func startDownload(url: URL, withMetadata metadata: Meta) -> Download<Meta> {
    let download = Download(url: url, metadata: metadata, manager: self)
    observeStateChanges(of: download)
    download.resume()
    activeDownloads[url] = download
    persist(download)
    return download
  }

  /// Cancels the download for good. Not `pause()`: a pause's resume data arrives later and
  /// was written back to the control database, so a removed download came back on relaunch.
  public func removeDownload(for url: URL) {
    guard let download = activeDownloads[url] else {
      return
    }

    download.cancel()
    activeDownloads[url] = nil
    controlDatabase?.remove(url: url)
  }

  public func completeDownload(_ url: URL) {
    // Delegate callbacks arrive on a background queue; `activeDownloads` is @Published and drives
    // the UI, so its mutations must land on the main thread.
    onMain { self.activeDownloads[url] = nil }
    controlDatabase?.remove(url: url)
  }

  /// Runs `work` synchronously if already on the main thread (keeps unit-test assertions simple),
  /// otherwise hops to the main queue.
  private func onMain(_ work: @escaping @Sendable () -> Void) {
    if Thread.isMainThread {
      work()
    } else {
      DispatchQueue.main.async(execute: work)
    }
  }

  /// Rebuilds `activeDownloads` from persisted control info. Each comes back paused; the
  /// ones the viewer did not pause are picked up again by `reattachBackgroundTasks()`.
  public func restoreDownloads() {
    guard let stored = controlDatabase?.readData(), !stored.isEmpty else { return }
    for info in stored {
      let download = Download(url: info.originalURL,
                              metadata: info.metadata,
                              manager: self,
                              resumeData: info.resumeData,
                              progress: info.progress)
      download.state = .paused
      if info.isPaused != true { resumeOnReattach.insert(info.originalURL) }
      observeStateChanges(of: download)
      activeDownloads[info.originalURL] = download
      Logger.kit.debug("[DOWNLOAD] restored download for: \(info.originalURL) (paused by viewer: \(info.isPaused == true))")
    }
  }

  /// Restored downloads the viewer had not paused: running when the app went away.
  private var resumeOnReattach: Set<URL> = []

  /// After a launch: the background session may still be running (or have finished) the
  /// transfers of a previous run. Creating the session reconnects it — its events are then
  /// delivered — and each live task is adopted by its download instead of a second copy
  /// being started. A download that was running and has no live task (force quit, reboot)
  /// starts again from its resume data. Deferred by the caller: creating a background
  /// session is an XPC round trip.
  public func reattachBackgroundTasks() {
    session.getAllTasks { [weak self] tasks in
      let live = tasks.compactMap { $0 as? URLSessionDownloadTask }
      DispatchQueue.main.async {
        guard let self else { return }
        var adopted = Set<URL>()
        for task in live {
          guard let url = task.originalRequest?.url, let download = self.activeDownloads[url] else { continue }
          download.attach(task)
          adopted.insert(url)
          Logger.kit.debug("[DOWNLOAD] reattached live task for: \(url)")
        }
        let toResume = self.resumeOnReattach.subtracting(adopted)
        self.resumeOnReattach = []
        // A beat later: a task the system cancelled while the app was gone reports in with
        // its resume data once the session exists, and resuming from that beats starting over.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
          for url in toResume {
            guard let download = self.activeDownloads[url], !download.hasTask else { continue }
            download.resume()
          }
        }
      }
    }
  }

  /// Pauses every running download.
  public func pauseAll() {
    for download in activeDownloads.values where download.state == .inProgress {
      download.pause()
    }
  }

  // MARK: - Persistence helpers

  private func observeStateChanges(of download: Download<Meta>) {
    download.onStateChange = { [weak self] download in
      self?.persist(download)
    }
  }

  private func persist(_ download: Download<Meta>) {
    let info = DownloadControlInfo(originalURL: download.url,
                                   resumeData: download.resumeData,
                                   progress: download.progress,
                                   metadata: download.metadata,
                                   isPaused: download.state == .paused)
    controlDatabase?.save(controlInfo: info)
  }

  // MARK: URLSessionDownloadDelegate methods

  public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
    guard let sourceURL = downloadTask.originalRequest?.url, let download = activeDownloads[sourceURL] else { return }
    Logger.kit.debug("[DOWNLOAD] Download finished: \(location)")

    // URLSession reports an HTTP error (403 / expired signature / etc.) as a successful "finish" and
    // hands us the tiny error body. Saving it produced broken ~160-byte "videos", so reject anything
    // that isn't a 2xx response or is implausibly small for media.
    if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
      Logger.kit.error("[DOWNLOAD] HTTP \(http.statusCode) for \(sourceURL) — discarding error body")
      try? FileManager.default.removeItem(at: location)
      completeDownload(sourceURL)
      return
    }
    // Only reject when we can actually read a (small) size — a real video is many MB, so anything
    // under ~100 KB is an error page. If the file's attributes can't be read, fall through and let
    // the file saver handle it (keeps this mockable in tests).
    if let attrs = try? FileManager.default.attributesOfItem(atPath: location.path),
       let fileSize = attrs[.size] as? Int64, fileSize < 100_000 {
      Logger.kit.error("[DOWNLOAD] file too small (\(fileSize) bytes) for \(sourceURL) — likely an error page, discarding")
      try? FileManager.default.removeItem(at: location)
      completeDownload(sourceURL)
      return
    }

    // Prefer a human-readable filename (keeps the source extension); fall back to the URL's last path
    // component. This is what shows in the Files app.
    let filename: String = {
      let ext = sourceURL.pathExtension
      if let base = (download.metadata as? DownloadFileNaming)?.downloadFileBaseName, !base.isEmpty {
        return ext.isEmpty ? base : "\(base).\(ext)"
      }
      return sourceURL.lastPathComponent
    }()
    let destinationURL = fileSaver.getDocumentsDirectoryURL(forFilename: filename)

    do {
      try fileSaver.saveFile(from: location, to: destinationURL)
      Logger.kit.info("[DOWNLOAD] File: \(location) moved to documents folder as \(filename)")

      let fileInfo = DownloadedFileInfo(originalURL: sourceURL, localFilename: filename, downloadDate: Date(), metadata: download.metadata)
      database.save(fileInfo: fileInfo)
    } catch {
      Logger.kit.error("[DOWNLOAD] Error during moving file: \(error)")
    }

    let metadata = download.metadata
    onMain { self.onDownloadFinished?(sourceURL, metadata) }
    completeDownload(sourceURL)
  }

  public func urlSession(_ session: URLSession,
                         downloadTask: URLSessionDownloadTask,
                         didWriteData bytesWritten: Int64,
                         totalBytesWritten: Int64,
                         totalBytesExpectedToWrite: Int64) {
    if totalBytesExpectedToWrite > 0, let download = activeDownloads[downloadTask.originalRequest?.url ?? URL(fileURLWithPath: "")] {
      let progress = Float(totalBytesWritten) / Float(totalBytesExpectedToWrite)
      Logger.kit.debug("[DOWNLOAD] progress for download: \(download.url), value: \(progress)")
      // Persist a progress checkpoint (throttled to whole-percent steps) so a partially
      // completed download survives a relaunch without writing the plist on every callback.
      let shouldCheckpoint = Int(progress * 100) != Int(download.progress * 100)
      DispatchQueue.main.async {
        download.updateProgress(progress)
        download.updateTransfer(bytesWritten: totalBytesWritten, totalBytes: totalBytesExpectedToWrite)
        if shouldCheckpoint {
          self.persist(download)
        }
      }
    }
  }

  public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    guard let error = error, let url = task.originalRequest?.url else { return }
    Logger.kit.debug("[DOWNLOAD] Download error for \(url): \(error)")
    let nsError = error as NSError
    let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
    onMain {
      guard let download = self.activeDownloads[url] else { return }
      // The viewer's pause, or a download restored paused whose old task reports in after
      // a force quit: the row stays paused, and keeps the resume data the session handed over.
      if download.state == .paused, nsError.code == NSURLErrorCancelled {
        if let resumeData { download.interrupted(resumeData: resumeData) }
        return
      }
      // A stale callback for a task this download no longer runs (it was resumed since).
      if download.state == .inProgress, download.hasTask, nsError.code == NSURLErrorCancelled { return }
      // The session gave up but left resume data (lost network, the app was force quit):
      // keep the row, paused, so it continues from where it stopped instead of vanishing.
      if resumeData != nil {
        download.interrupted(resumeData: resumeData)
        if nsError.code != NSURLErrorCancelled {
          self.onDownloadFailed?(url, download.metadata, error)
        }
        return
      }
      if nsError.code != NSURLErrorCancelled {
        self.onDownloadFailed?(url, download.metadata, error)
      }
      self.activeDownloads[url] = nil
      self.controlDatabase?.remove(url: url)
    }
  }

  public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    Logger.kit.debug("[DOWNLOAD] background session finished events")
    DispatchQueue.main.async {
      let handler = self.backgroundCompletionHandler
      self.backgroundCompletionHandler = nil
      handler?()
    }
  }
}
