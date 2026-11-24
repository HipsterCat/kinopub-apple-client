//
//  APIClient.swift
//
//
//  Created by Kirill Kunst on 21.07.2023.
//

import Foundation

public final class APIClient: Sendable {
  private let session: URLSessionProtocol
  private let requestBuilder: RequestBuilder
  private let baseUrl: URL
  private let plugins: [APIClientPlugin]
  private let cache: ResponseCaching?
  /// kino.pub's API hosts. Nil: every request goes to `baseUrl`, as before.
  public let hosts: APIHostPool?

  public init(baseUrl: String,
              plugins: [APIClientPlugin] = [],
              session: URLSessionProtocol = URLSessionImpl(session: .shared),
              cache: ResponseCaching? = nil,
              hosts: APIHostPool? = nil) {
    self.baseUrl = URL(string: baseUrl)!
    self.plugins = plugins
    self.session = session
    self.cache = cache
    self.hosts = hosts
    self.requestBuilder = RequestBuilder(baseURL: self.baseUrl)
  }

  /// - Parameter forceRefresh: when true, skips any cached value and always hits the network
  ///   (the fresh result still updates the cache).
  public func performRequest<T: Decodable>(with requestData: Endpoint,
                                           decodingType: T.Type,
                                           forceRefresh: Bool = false) async throws -> T {
    let cacheable = requestData as? CacheableRequest
    let policy = cacheable?.cachePolicy ?? .noCache
    if !forceRefresh, let cacheable, policy.ttl != nil,
       let cachedData = cache?.data(for: cacheable.cacheKey),
       let cached = try? JSONDecoder().decode(T.self, from: cachedData) {
      return cached
    }

    let (data, response) = try await execute(requestData, allowUnauthorizedRetry: true)

    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
      // Keep structured kino.pub / OAuth envelopes as BackendError so auth
      // call sites (invalid_grant → logout) keep working.
      if let backendError = try? JSONDecoder().decode(BackendError.self, from: data) {
        throw APIClientError.networkError(backendError)
      }
      throw APIClientError.httpStatus(http.statusCode, data: data)
    }

    let result = try decode(T.self, from: data, throwDecodingErrorImmediately: false)
    if let cacheable, let ttl = policy.ttl {
      cache?.store(data, for: cacheable.cacheKey, ttl: ttl, persist: policy.persistsToDisk)
    }
    return result
  }

  /// Drops all cached responses. Not used on logout — we only cache immutable
  /// genres/countries lists that are shared across accounts.
  public func clearCache() {
    cache?.clear()
  }

  /// Runs one HTTP round-trip. On a content 401, awaits token recovery once and
  /// retries with a freshly prepared Authorization header — callers never see the
  /// first 401 when refresh succeeds.
  private func execute(_ requestData: Endpoint,
                       allowUnauthorizedRetry: Bool) async throws -> (Data, URLResponse) {
    let (data, response) = try await send(requestData)

    if allowUnauthorizedRetry,
       let http = response as? HTTPURLResponse,
       http.statusCode == 401,
       Self.isContentPath(http.url?.path) {
      let recovered = await UnauthorizedRequestRecovery.shared.recover()
      if recovered {
        return try await execute(requestData, allowUnauthorizedRetry: false)
      }
    }

    return (data, response)
  }

  /// One round-trip, walking the API hosts: the current one first, the next on a
  /// failure `APIHostPool` says another host may not have (no DNS, no connection, a
  /// gateway 502/503/504 on a repeatable request). The host that answers becomes the
  /// current one. Endpoints with their own base URL, and clients without a pool, send
  /// once.
  private func send(_ requestData: Endpoint) async throws -> (Data, URLResponse) {
    guard let hosts, requestData.baseURLOverride == nil else {
      return try await sendOnce(requestData, host: nil)
    }
    let order = hosts.attemptOrder
    for (attempt, host) in order.enumerated() {
      let isLast = attempt == order.count - 1
      do {
        let (data, response) = try await sendOnce(requestData, host: host.url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if APIHostPool.isGatewayFailure(status) {
          // Not "answered": a host whose front cannot reach its backend never becomes
          // the sticky one, even when every host says so.
          hosts.recordFailure(of: host, reason: "HTTP \(status)")
          if !isLast, requestData.isRepeatable { continue }
          return (data, response)
        }
        hosts.recordAnswer(from: host, status: status)
        return (data, response)
      } catch {
        let underlying = Self.transportError(error)
        if Task.isCancelled || (underlying as? URLError)?.code == .cancelled { throw error }
        if underlying is URLError {
          hosts.recordFailure(of: host, reason: APIHostPool.reason(for: underlying))
        }
        guard !isLast,
              APIHostPool.shouldMoveOn(after: underlying, repeatable: requestData.isRepeatable) else {
          throw error
        }
      }
    }
    // Unreachable: the last host either returns or throws.
    throw APIClientError.urlError
  }

  private func sendOnce(_ requestData: Endpoint, host: URL?) async throws -> (Data, URLResponse) {
    guard let request = requestBuilder.build(with: requestData, host: host) else {
      throw APIClientError.invalidUrlParams
    }

    let preparedRequest = plugins.reduce(request) { $1.prepare($0) }
    plugins.forEach { $0.willSend(preparedRequest) }

    let (data, response) = try await session.data(for: preparedRequest)
    plugins.forEach { $0.didReceive(response, data: data) }
    return (data, response)
  }

  /// `URLSessionImpl` wraps transport errors in `APIClientError.networkError`.
  private static func transportError(_ error: Error) -> Error {
    if case APIClientError.networkError(let underlying) = error { return underlying }
    return error
  }

  /// OAuth endpoints handle their own failures; retrying `/oauth2/token` on 401 would loop.
  private static func isContentPath(_ path: String?) -> Bool {
    guard let path else { return true }
    return !path.contains("oauth2")
  }

  private func decode<T: Decodable>(_ type: T.Type,
                                    from data: Data,
                                    throwDecodingErrorImmediately: Bool) throws -> T where T: Decodable {
    do {
      let result = try JSONDecoder().decode(T.self, from: data)
      return result
    } catch {
      if throwDecodingErrorImmediately {
        throw APIClientError.decodingError(error)
      }

      if let backendError = try? JSONDecoder().decode(BackendError.self, from: data) {
        throw APIClientError.networkError(backendError)
      }

      throw APIClientError.decodingError(error)
    }
  }
}
