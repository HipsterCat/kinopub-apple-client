//
//  URLSessionProtocol.swift
//
//
//  Created by Kirill Kunst on 21.07.2023.
//

import Foundation
import KinoPubLogging

public protocol URLSessionProtocol {
  func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

public class URLSessionImpl: URLSessionProtocol {
  let session: URLSession

  public init(session: URLSession) {
    self.session = session
  }

  /// Every kino.pub request passes through here, so the catalog never has to remember
  /// to report. The other stacks register themselves: metadata (TMDB proxy, Kinopoisk
  /// direct, kpapp), worker image routes, autocomplete, the guide, config.
  public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
    let activity = NetworkActivity.begin(request)
    defer { NetworkActivity.end(activity) }
    do {
      return try await session.data(for: request)
    } catch {
      throw APIClientError.networkError(error)
    }
  }
}
