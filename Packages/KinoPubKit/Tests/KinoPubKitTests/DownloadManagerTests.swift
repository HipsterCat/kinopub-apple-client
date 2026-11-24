//
//  DownloadManagerTests.swift
//
//
//  Created by Kirill Kunst on 22.07.2023.
//

import Foundation
import XCTest
@testable import KinoPubKit

@MainActor
final class DownloadManagerTests: XCTestCase {

  // MARK: - Test Variables

  var downloadManager: DownloadManager<TestMeta>!
  var database: DownloadedFilesDatabase<TestMeta>!
  var fileSaverMock: FileSaverMock!

  private let url = URL(string: "http://example.com/testfile.txt")!
  private let metadata = TestMeta(id: 1, title: "Test")

  // MARK: - Test Setup

  override func setUp() async throws {
    fileSaverMock = FileSaverMock()
    database = DownloadedFilesDatabase<TestMeta>(fileSaver: fileSaverMock)
    downloadManager = DownloadManager<TestMeta>(fileSaver: fileSaverMock, database: database)
  }

  override func tearDown() async throws {
    downloadManager = nil
    database = nil
    fileSaverMock = nil
  }

  // MARK: - Helpers

  /// Registers a download without going through `startDownload`, which would spin up
  /// the shared background `URLSession`. Only one test does that on purpose.
  @discardableResult
  private func registerDownload() -> Download<TestMeta> {
    let download = Download(url: url, metadata: metadata, manager: downloadManager)
    downloadManager.activeDownloads[url] = download
    return download
  }

  // MARK: - Test Methods

  func testStartDownloadRegistersAnActiveDownload() {
    let download = downloadManager.startDownload(url: url, withMetadata: metadata)

    XCTAssertEqual(download.url, url)
    XCTAssertEqual(download.metadata, metadata)
    XCTAssertEqual(download.state, .inProgress)
    XCTAssertNotNil(downloadManager.activeDownloads[url])

    download.pause()
    downloadManager.completeDownload(url)
  }

  func testCompleteDownloadRemovesTheActiveDownload() {
    registerDownload()

    downloadManager.completeDownload(url)

    XCTAssertNil(downloadManager.activeDownloads[url])
  }

  func testRemoveDownloadRemovesTheActiveDownload() {
    registerDownload()

    downloadManager.removeDownload(for: url)

    XCTAssertNil(downloadManager.activeDownloads[url])
  }

  func testRemoveDownloadIsANoOpForAnUnknownURL() {
    registerDownload()

    downloadManager.removeDownload(for: URL(string: "http://example.com/other.txt")!)

    XCTAssertNotNil(downloadManager.activeDownloads[url])
  }

  func testFinishingADownloadSavesTheFileAndRecordsIt() async {
    registerDownload()
    let location = URL(fileURLWithPath: "/path/to/temporary/location.txt")
    let task = URLSessionDownloadTaskMock(url: url)

    downloadManager.urlSession(.shared, downloadTask: task, didFinishDownloadingTo: location)

    XCTAssertTrue(fileSaverMock.didSaveFileCalled)
    XCTAssertEqual(fileSaverMock.savedFileSourceURL, location)
    XCTAssertEqual(fileSaverMock.savedFileDestinationURL,
                   fileSaverMock.getDocumentsDirectoryURL(forFilename: "testfile.txt"))
    XCTAssertEqual(database.readData()?.map(\.localFilename), ["testfile.txt"])
    await drainMainQueue()
    XCTAssertNil(downloadManager.activeDownloads[url], "the download should no longer be active")
  }

  func testFinishingADownloadRecordsNothingWhenSavingFails() async {
    registerDownload()
    fileSaverMock.shouldThrowError = true
    let task = URLSessionDownloadTaskMock(url: url)

    downloadManager.urlSession(.shared,
                               downloadTask: task,
                               didFinishDownloadingTo: URL(fileURLWithPath: "/tmp/location.txt"))

    await drainMainQueue()
    XCTAssertNil(database.readData())
    XCTAssertNil(downloadManager.activeDownloads[url])
  }

  /// The session calls on its own queue, with the main thread busy: the file is moved and
  /// recorded before the callback returns, the rest follows on the main actor in order.
  func testCallbacksFromTheSessionsQueueReachTheMainActorInOrder() async {
    let download = registerDownload()
    let task = URLSessionDownloadTaskMock(url: url)
    let manager = downloadManager!
    let saver = fileSaverMock!
    let location = URL(fileURLWithPath: "/tmp/movie.mp4")
    var events: [String] = []
    let observation = download.$progress.dropFirst().sink { events.append("progress \($0)") }
    manager.onDownloadFinished = { [url] finished, meta in
      XCTAssertEqual(finished, url)
      XCTAssertEqual(meta, TestMeta(id: 1, title: "Test"))
      events.append("finished")
    }
    manager.backgroundCompletionHandler = { events.append("events delivered") }

    let savedBeforeReturning = DispatchQueue(label: "session").sync {
      manager.urlSession(.shared, downloadTask: task, didWriteData: 1,
                         totalBytesWritten: 1, totalBytesExpectedToWrite: 2)
      manager.urlSession(.shared, downloadTask: task, didFinishDownloadingTo: location)
      manager.urlSessionDidFinishEvents(forBackgroundURLSession: .shared)
      return saver.savedFileSourceURL
    }

    XCTAssertEqual(savedBeforeReturning, location)
    XCTAssertEqual(events, [])
    await drainMainQueue()
    XCTAssertEqual(events, ["progress 0.5", "finished", "events delivered"])
    XCTAssertNil(manager.activeDownloads[url])
    observation.cancel()
  }

  /// A download removed before its file arrives is not saved.
  func testAFileOfARemovedDownloadIsNotSaved() async {
    registerDownload()
    downloadManager.removeDownload(for: url)

    downloadManager.urlSession(.shared, downloadTask: URLSessionDownloadTaskMock(url: url),
                               didFinishDownloadingTo: URL(fileURLWithPath: "/tmp/movie.mp4"))

    XCTAssertFalse(fileSaverMock.didSaveFileCalled)
    XCTAssertNil(database.readData())
  }

  func testProgressIsPublishedWhileDownloading() async {
    let download = registerDownload()
    let task = URLSessionDownloadTaskMock(url: url)
    let progressUpdated = expectation(description: "progress updated")

    let observation = download.$progress
      .dropFirst()
      .sink { progress in
        XCTAssertEqual(progress, 0.5, accuracy: 0.001)
        progressUpdated.fulfill()
      }

    downloadManager.urlSession(.shared,
                               downloadTask: task,
                               didWriteData: 1024,
                               totalBytesWritten: 1024,
                               totalBytesExpectedToWrite: 2048)

    await fulfillment(of: [progressUpdated], timeout: 1.0)
    observation.cancel()
  }

  // MARK: - Pause, failure, removal

  /// Pausing cancels the task "by producing resume data"; the session then reports a
  /// cancellation. That used to drop the download from the list.
  func testCancellationOfAPausedDownloadKeepsIt() async {
    let download = registerDownload()
    download.state = .paused
    let cancelled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)

    downloadManager.urlSession(.shared, task: URLSessionDownloadTaskMock(url: url), didCompleteWithError: cancelled)
    await drainMainQueue()

    XCTAssertNotNil(downloadManager.activeDownloads[url])
    XCTAssertEqual(download.state, .paused)
  }

  /// The session gave up but left resume data (network, force quit): keep it, paused.
  func testFailureWithResumeDataPausesTheDownload() async {
    let download = registerDownload()
    download.state = .inProgress
    let lost = NSError(domain: NSURLErrorDomain, code: NSURLErrorNetworkConnectionLost,
                       userInfo: [NSURLSessionDownloadTaskResumeData: Data([1, 2, 3])])

    downloadManager.urlSession(.shared, task: URLSessionDownloadTaskMock(url: url), didCompleteWithError: lost)
    await drainMainQueue()

    XCTAssertNotNil(downloadManager.activeDownloads[url])
    XCTAssertEqual(download.state, .paused)
    XCTAssertEqual(download.resumeData, Data([1, 2, 3]))
  }

  func testFailureWithoutResumeDataDropsTheDownload() async {
    let download = registerDownload()
    download.state = .inProgress
    let failed = NSError(domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse)

    downloadManager.urlSession(.shared, task: URLSessionDownloadTaskMock(url: url), didCompleteWithError: failed)
    await drainMainQueue()

    XCTAssertNil(downloadManager.activeDownloads[url])
  }
}

// MARK: - Mock Classes

final class URLSessionDownloadTaskMock: URLSessionDownloadTask, @unchecked Sendable {
  private let url: URL?

  init(url: URL? = nil) {
    self.url = url
  }

  override var originalRequest: URLRequest? {
    guard let url else { return nil }
    return URLRequest(url: url)
  }

  override func resume() {}

  override func cancel() {}

  override func cancel(byProducingResumeData completionHandler: @escaping (Data?) -> Void) {
    completionHandler(nil)
  }
}
