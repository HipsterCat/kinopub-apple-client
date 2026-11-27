//
//  FileSaverMock.swift
//
//
//  Created by Kirill Kunst on 22.07.2023.
//

import Foundation
import Synchronization
@testable import PiraticKit

/// Records what it was asked to do, and hands out paths inside a throwaway
/// directory so `DownloadedFilesDatabase` — which reads and writes the plist
/// itself rather than going through `FileSaving` — has somewhere real to work.
/// Locked: the download manager saves from its delegate queue.
final class FileSaverMock: FileSaving {

  private struct Calls {
    var shouldThrowError = false
    var savedFrom: URL?
    var savedTo: URL?
    var removed: URL?
  }

  private let calls = Mutex(Calls())

  var shouldThrowError: Bool {
    get { calls.withLock { $0.shouldThrowError } }
    set { calls.withLock { $0.shouldThrowError = newValue } }
  }
  var didSaveFileCalled: Bool { savedFileSourceURL != nil }
  var savedFileSourceURL: URL? { calls.withLock { $0.savedFrom } }
  var savedFileDestinationURL: URL? { calls.withLock { $0.savedTo } }
  var didRemoveFileCalled: Bool { removedFileURL != nil }
  var removedFileURL: URL? { calls.withLock { $0.removed } }

  let directoryURL: URL

  init() {
    directoryURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("PiraticKitTests-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
  }

  deinit {
    try? FileManager.default.removeItem(at: directoryURL)
  }

  func saveFile(from sourceURL: URL, to destinationURL: URL) throws {
    if shouldThrowError {
      throw NSError(domain: "FileSaverMockErrorDomain", code: 123, userInfo: nil)
    }

    calls.withLock {
      $0.savedFrom = sourceURL
      $0.savedTo = destinationURL
    }
  }

  func removeFile(at sourceURL: URL) throws {
    if shouldThrowError {
      throw NSError(domain: "FileSaverMockErrorDomain", code: 123, userInfo: nil)
    }

    calls.withLock { $0.removed = sourceURL }
  }

  func getDocumentsDirectoryURL(forFilename filename: String) -> URL {
    directoryURL.appendingPathComponent(filename)
  }
}

/// Stand-in for the app's `DownloadMeta`, which lives in the app target.
struct TestMeta: Codable, Equatable, Sendable {
  let id: Int
  let title: String
}
