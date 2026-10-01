//
//  File.swift
//
//
//  Created by Kirill Kunst on 21.07.2023.
//

import Foundation
@testable import KinoPubBackend

public class URLSessionMock: URLSessionProtocol {
  var data: Data?
  var response: URLResponse?
  var error: Error?
  var lastRequest: URLRequest?
  /// Sequenced results for retry tests. Consumed FIFO before the single-shot fields.
  var results: [(Data?, URLResponse?, Error?)] = []
  private(set) var requestCount = 0

  public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    lastRequest = request
    requestCount += 1

    if !results.isEmpty {
      let next = results.removeFirst()
      if let error = next.2 { throw error }
      return (next.0 ?? Data(), next.1 ?? URLResponse())
    }

    if let error = error {
      throw error
    }

    return (data ?? Data(), response ?? URLResponse())
  }
}
