//
//  FileManagerMock.swift
//
//
//  Created by Kirill Kunst on 22.07.2023.
//

import Foundation
import Synchronization

/// Records *attempts* in `Attempts`, which the test keeps: the mock itself is handed over
/// to the `FileSaver`.
final class FileManagerMock: FileManager {

  final class Attempts: Sendable {
    private let state = Mutex((remove: false, move: false))

    /// Set before the throw, so a true value means the call was made, not that it succeeded.
    var didAttemptRemoveItem: Bool { state.withLock { $0.remove } }
    var didAttemptMoveItem: Bool { state.withLock { $0.move } }

    fileprivate func noteRemove() { state.withLock { $0.remove = true } }
    fileprivate func noteMove() { state.withLock { $0.move = true } }
  }

  private let attempts: Attempts
  private let shouldThrowError: Bool

  init(attempts: Attempts, shouldThrowError: Bool = false) {
    self.attempts = attempts
    self.shouldThrowError = shouldThrowError
    super.init()
  }

  override func removeItem(at URL: URL) throws {
    attempts.noteRemove()
    if shouldThrowError {
      throw NSError(domain: "FileManagerMockErrorDomain", code: 123, userInfo: nil)
    }
  }

  override func moveItem(at srcURL: URL, to dstURL: URL) throws {
    attempts.noteMove()
    if shouldThrowError {
      throw NSError(domain: "FileManagerMockErrorDomain", code: 456, userInfo: nil)
    }
  }
}
