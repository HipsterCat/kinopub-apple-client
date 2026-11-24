//
//  FileSaver.swift
//
//
//  Created by Kirill Kunst on 22.07.2023.
//

import Foundation
import Synchronization

/// `Sendable`: the download session's delegate saves a finished file on its own queue,
/// before the system deletes the temporary one.
public protocol FileSaving: Sendable {
  func saveFile(from sourceURL: URL, to destinationURL: URL) throws
  func removeFile(at sourceURL: URL) throws
  func getDocumentsDirectoryURL(forFilename filename: String) -> URL
}

public final class FileSaver: FileSaving {
  private let fileManager: Mutex<FileManager>

  public init(fileManager: sending FileManager = .default) {
    self.fileManager = Mutex(fileManager)
  }

  public func saveFile(from sourceURL: URL, to destinationURL: URL) throws {
    try fileManager.withLock {
      try? $0.removeItem(at: destinationURL)
      try $0.moveItem(at: sourceURL, to: destinationURL)
    }
  }

  public func removeFile(at sourceURL: URL) throws {
    try fileManager.withLock { try $0.removeItem(at: sourceURL) }
  }

  public func getDocumentsDirectoryURL(forFilename filename: String) -> URL {
    let documentsDirectoryURL = fileManager.withLock {
      $0.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    return documentsDirectoryURL.appendingPathComponent(filename)
  }
}
