//
//  MainQueue.swift
//

import Foundation

/// Lets everything already queued on the main queue run: the download manager brings the
/// session's callbacks there, and the main queue is first in, first out.
func drainMainQueue() async {
  await withCheckedContinuation { continuation in
    DispatchQueue.main.async { continuation.resume() }
  }
}
