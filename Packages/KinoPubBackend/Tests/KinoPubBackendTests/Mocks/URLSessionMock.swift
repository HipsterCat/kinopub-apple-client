//
//  File.swift
//
//
//  Created by Kirill Kunst on 21.07.2023.
//

import Foundation
import Synchronization
@testable import KinoPubBackend

public final class URLSessionMock: URLSessionProtocol {
  private struct State {
    var data: Data?
    var response: URLResponse?
    var error: Error?
    var lastRequest: URLRequest?
    var results: [(Data?, URLResponse?, Error?)] = []
    var requestCount = 0
  }

  private let state = Mutex(State())

  var data: Data? {
    get { state.withLock { $0.data } }
    set { state.withLock { $0.data = newValue } }
  }
  var response: URLResponse? {
    get { state.withLock { $0.response } }
    set { state.withLock { $0.response = newValue } }
  }
  var error: Error? {
    get { state.withLock { $0.error } }
    set { state.withLock { $0.error = newValue } }
  }
  var lastRequest: URLRequest? { state.withLock { $0.lastRequest } }
  /// Sequenced results for retry tests. Consumed FIFO before the single-shot fields.
  var results: [(Data?, URLResponse?, Error?)] {
    get { state.withLock { $0.results } }
    set { state.withLock { $0.results = newValue } }
  }
  var requestCount: Int { state.withLock { $0.requestCount } }

  public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    let (data, response, error) = state.withLock { state in
      state.lastRequest = request
      state.requestCount += 1
      return state.results.isEmpty
        ? (state.data, state.response, state.error)
        : state.results.removeFirst()
    }
    if let error { throw error }
    return (data ?? Data(), response ?? URLResponse())
  }
}
