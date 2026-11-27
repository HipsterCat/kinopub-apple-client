//
//  DownloadedFilesDatabase.swift
//
//
//  Created by Kirill Kunst on 22.07.2023.
//

import Foundation
import PiraticLogging
import OSLog
import Synchronization

public protocol DownloadedFilesDataReading {
  associatedtype Meta: Codable & Equatable
  func readData() -> [DownloadedFileInfo<Meta>]?
}

public protocol DownloadedFilesDataWriting {
  associatedtype Meta: Codable & Equatable
  func writeData(_ files: [DownloadedFileInfo<Meta>])
  func save(fileInfo: DownloadedFileInfo<Meta>)
}

/// Safe from any thread: a finished file is recorded on the download session's delegate
/// queue while the screens read and remove records on the main one. Every access to the
/// plist holds `file`, and a change holds it across its read and its write, so two
/// changes cannot lose one another.
public final class DownloadedFilesDatabase<Meta: Codable & Equatable & Sendable>: DownloadedFilesDataReading, DownloadedFilesDataWriting, Sendable {
  private let fileSaver: FileSaving
  private let dataFileURL: URL
  private let file = Mutex(())

  public init(fileSaver: FileSaving) {
    self.fileSaver = fileSaver
    self.dataFileURL = fileSaver.getDocumentsDirectoryURL(forFilename: "downloadedFiles.plist")
  }

  public func save(fileInfo: DownloadedFileInfo<Meta>) {
    update { $0.append(fileInfo) }
    Logger.kit.debug("[DOWNLOAD] save file info for: \(fileInfo.originalURL)")
  }

  public func readData() -> [DownloadedFileInfo<Meta>]? {
    file.withLock { _ in read() }
  }

  public func writeData(_ files: [DownloadedFileInfo<Meta>]) {
    file.withLock { _ in write(files) }
  }

  private func update(_ change: (inout [DownloadedFileInfo<Meta>]) -> Void) {
    file.withLock { _ in
      var files = read() ?? []
      change(&files)
      write(files)
    }
  }

  /// Holding `file`.
  private func read() -> [DownloadedFileInfo<Meta>]? {
    guard let data = try? Data(contentsOf: dataFileURL),
          let decodedData = try? PropertyListDecoder().decode([DownloadedFileInfo<Meta>].self, from: data) else {
      return nil
    }
    return decodedData.sorted(by: { $0.downloadDate > $1.downloadDate })
  }

  /// Holding `file`.
  private func write(_ files: [DownloadedFileInfo<Meta>]) {
    if let data = try? PropertyListEncoder().encode(files) {
      try? data.write(to: dataFileURL)
    }
  }
  
  public func remove(fileInfo: DownloadedFileInfo<Meta>) {
    update { $0.removeAll(where: { $0.originalURL == fileInfo.originalURL }) }
    // Delete the actual file on disk (was previously deleting the remote URL — a no-op).
    try? fileSaver.removeFile(at: fileInfo.localFileURL)
    Logger.kit.debug("[DOWNLOAD] file data removed: \(fileInfo.originalURL)")
  }
}
