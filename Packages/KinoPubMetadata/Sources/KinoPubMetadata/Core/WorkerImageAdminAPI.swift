import Foundation
import KinoPubLogging

public enum WorkerImageAdminKind: String, Sendable, CaseIterable {
  case logo
  case backdrop
  case poster
}

public struct WorkerImageAdminCandidate: Sendable, Codable, Identifiable, Hashable {
  public let url: String
  public let from: String?
  public let width: Int?
  public let height: Int?
  public let vote: Double?
  public let pick: Bool?

  public var id: String { url }

  public var sizeLabel: String {
    guard let width, let height else { return "—" }
    return "\(width)×\(height)"
  }
}

public struct WorkerImageAdminStoredAsset: Sendable, Codable, Identifiable, Hashable {
  public let url: String
  public let lang: String?
  public let pinned: Bool?
  public let width: Int?
  public let height: Int?

  public var id: String { url }
}

public struct WorkerImageAdminCatalog: Sendable, Codable {
  public let ok: Bool
  public let id: String
  public let kind: String
  public let tmdb: String?
  public let ru: [WorkerImageAdminCandidate]
  public let en: [WorkerImageAdminCandidate]
  public let und: [WorkerImageAdminCandidate]
  public let stored: [WorkerImageAdminStoredAsset]?

  public func bucket(_ tag: WorkerArtworkLanguageTag) -> [WorkerImageAdminCandidate] {
    switch tag {
    case .ru: return ru
    case .en: return en
    case .und: return und
    }
  }
}

public struct WorkerImageAdminActionResponse: Sendable, Codable {
  public let ok: Bool?
  public let id: String?
  public let kind: String?
  public let art_rev: Int?
  public let count: Int?
  public let picked: [String: String]?
  public let error: String?
  public let hint: String?
}

/// POST routes on the TMDB proxy (`/admin/…`). Without a valid `Authorization: Bearer`
/// token the worker answers 404 as if the route did not exist.
public struct WorkerImageAdminClient: Sendable {
  public let baseURL: URL
  private let token: String
  private let session: URLSession

  public init(baseURL: URL, token: String, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.token = token
    self.session = session
  }

  public var isConfigured: Bool {
    !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  public func forget(kinopubID: Int, kind: WorkerImageAdminKind) async throws -> WorkerImageAdminActionResponse {
    try await post(
      path: "admin/kinopub/\(kinopubID)/forget",
      query: [URLQueryItem(name: "kind", value: kind.rawValue)]
    )
  }

  public func refresh(
    kinopubID: Int,
    kind: WorkerImageAdminKind,
    imdb: String?,
    kinopoisk: Int?
  ) async throws -> WorkerImageAdminActionResponse {
    var query = [URLQueryItem(name: "kind", value: kind.rawValue)]
    if let imdb, !imdb.isEmpty { query.append(URLQueryItem(name: "imdb", value: imdb)) }
    if let kinopoisk, kinopoisk > 0 {
      query.append(URLQueryItem(name: "kinopoisk", value: String(kinopoisk)))
    }
    return try await post(path: "admin/kinopub/\(kinopubID)/refresh", query: query)
  }

  public func catalog(
    kinopubID: Int,
    kind: WorkerImageAdminKind,
    imdb: String?
  ) async throws -> WorkerImageAdminCatalog {
    var query = [URLQueryItem(name: "kind", value: kind.rawValue)]
    if let imdb, !imdb.isEmpty { query.append(URLQueryItem(name: "imdb", value: imdb)) }
    let data = try await postData(path: "admin/kinopub/\(kinopubID)/images", query: query)
    return try JSONDecoder().decode(WorkerImageAdminCatalog.self, from: data)
  }

  public func pickLogo(kinopubID: Int, url: String, language: WorkerArtworkLanguageTag?) async throws
    -> WorkerImageAdminActionResponse {
    var body: [String: String] = ["logo": url]
    if let language, language != .und { body["logo_lang"] = language.rawValue }
    return try await pick(kinopubID: kinopubID, body: body)
  }

  public func pickBackdrop(kinopubID: Int, url: String) async throws -> WorkerImageAdminActionResponse {
    try await pick(kinopubID: kinopubID, body: ["backdrop": url])
  }

  public func imageStats() async throws -> [String: Int] {
    let data = try await postData(path: "admin/stats")
    let envelope = try JSONDecoder().decode(WorkerImageAdminStatsEnvelope.self, from: data)
    var counts: [String: Int] = [:]
    if let timeout = envelope.timeout { counts["timeout"] = timeout }
    if let missing = envelope.missing { counts["missing"] = missing }
    if let waited = envelope.waited { counts["waited"] = waited }
    return counts
  }

  private func pick(kinopubID: Int, body: [String: String]) async throws -> WorkerImageAdminActionResponse {
    let data = try JSONEncoder().encode(body)
    return try await post(path: "admin/kinopub/\(kinopubID)/pick", body: data)
  }

  private func post(
    path: String,
    query: [URLQueryItem] = [],
    body: Data? = nil
  ) async throws -> WorkerImageAdminActionResponse {
    let data = try await postData(path: path, query: query, body: body)
    return try JSONDecoder().decode(WorkerImageAdminActionResponse.self, from: data)
  }

  private func postData(
    path: String,
    query: [URLQueryItem] = [],
    body: Data? = nil
  ) async throws -> Data {
    let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
    guard var components = URLComponents(
      url: baseURL.appendingPathComponent(trimmed),
      resolvingAgainstBaseURL: false
    ) else {
      throw WorkerImageAdminError.badURL
    }
    if !query.isEmpty { components.queryItems = query }
    guard let url = components.url else { throw WorkerImageAdminError.badURL }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      request.httpBody = body
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }

    let activity = NetworkActivity.begin(request)
    defer { NetworkActivity.end(activity) }
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw WorkerImageAdminError.transport }
    if http.statusCode == 404 {
      throw WorkerImageAdminError.unauthorizedOrMissing
    }
    guard (200...299).contains(http.statusCode) else {
      if let action = try? JSONDecoder().decode(WorkerImageAdminActionResponse.self, from: data),
         let hint = action.hint ?? action.error {
        throw WorkerImageAdminError.server(hint)
      }
      throw WorkerImageAdminError.http(http.statusCode)
    }
    return data
  }
}

private struct WorkerImageAdminStatsEnvelope: Decodable {
  let ok: Bool?
  let timeout: Int?
  let missing: Int?
  let waited: Int?
}

public enum WorkerImageAdminError: Error, LocalizedError {
  case badURL
  case transport
  case unauthorizedOrMissing
  case http(Int)
  case server(String)

  public var errorDescription: String? {
    switch self {
    case .badURL: return "Bad worker URL"
    case .transport: return "Network error"
    case .unauthorizedOrMissing: return "404 — wrong token or route"
    case .http(let code): return "HTTP \(code)"
    case .server(let hint): return hint
    }
  }
}
