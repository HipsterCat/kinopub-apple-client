//
//  SearchAutocomplete.swift
//  KinoPubBackend
//
//  kino.pub's own type-ahead: `GET https://api.kinopub.link/v1.1/autocomplete?query=`.
//  Keyless, a bare JSON array (not `{items}`), 20 rows, prefix match on any word of the
//  title (verified live 2026-09-25 — docs/providers/kinopub/video.md). `api.service-kp.com`
//  answers 404 for the same path, so it is its own host.
//

import Foundation

public struct SearchAutocompleteEntry: Decodable, Hashable, Sendable, Identifiable {
  public let id: Int
  /// "Матрица / The Matrix (1999)" — local title, original title, year.
  public let value: String
  public let type: String?

  public init(id: Int, value: String, type: String?) {
    self.id = id
    self.value = value
    self.type = type
  }

  /// The local title alone — what goes into the field when the row is picked.
  public var title: String {
    var text = value
    if let open = text.range(of: " (", options: .backwards), text.hasSuffix(")") {
      text = String(text[..<open.lowerBound])
    }
    if let slash = text.range(of: " / ") {
      text = String(text[..<slash.lowerBound])
    }
    return text.trimmingCharacters(in: .whitespaces)
  }
}

public enum SearchAutocomplete {
  public static let endpoint = URL(string: "https://api.kinopub.link/v1.1/autocomplete")!

  public static func url(for query: String) -> URL? {
    var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "query", value: query)]
    return components?.url
  }

  public static func fetch(_ query: String, session: URLSession = .shared) async throws -> [SearchAutocompleteEntry] {
    guard let url = url(for: query) else { return [] }
    var request = URLRequest(url: url)
    request.timeoutInterval = 6
    let (data, response) = try await session.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
    return try JSONDecoder().decode([SearchAutocompleteEntry].self, from: data)
  }
}
