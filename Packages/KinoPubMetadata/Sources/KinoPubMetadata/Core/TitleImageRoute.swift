import Foundation

/// The worker's image route by kino.pub id: `GET {worker}/img/{kind}/{size}/kinopub/{id}`
/// answers `302` to the picture (TMDB at the asked size, kino.pub's own art as the
/// poster/backdrop fallback) or `404` when there is no logo. The client puts the URL
/// straight into an image view — no details call, no TMDB lookup, no JSON.
///
/// **One title, one URL.** The Home banner and the detail hero build it from the same
/// inputs (kino.pub id + IMDb id), so the hero gets the banner's bytes from the artwork
/// cache instead of downloading the same logo again. Keep anything screen-specific out
/// of it.
public struct TitleImageRoute: Sendable, Hashable {
  public enum Kind: String, Sendable {
    case logo, backdrop, poster
  }

  /// The worker's buckets (`workers/tmdb-proxy/src/title.js`, `TMDB_SIZE`).
  public enum Size: String, Sendable {
    case sm, md, lg, orig
  }

  public let baseURL: URL?
  /// `nil` asks for the worker's default (Russian, then English). The app is Russian
  /// first, so English goes on the URL only when the app runs in another language.
  public let language: String?

  public init(baseURL: URL?, language: String? = TitleImageRoute.appLanguage) {
    self.baseURL = baseURL
    self.language = language
  }

  public var isConfigured: Bool { baseURL != nil }

  /// - Parameter imdb: kino.pub's numeric IMDb id. It lets the worker resolve a title
  ///   it has never seen; without it a cold title only gets kino.pub's own art.
  public func url(_ kind: Kind, size: Size, kinopubID: Int, imdb: Int?) -> URL? {
    guard let baseURL, kinopubID > 0 else { return nil }
    var components = URLComponents(
      url: baseURL.appendingPathComponent("img/\(kind.rawValue)/\(size.rawValue)/kinopub/\(kinopubID)"),
      resolvingAgainstBaseURL: false
    )
    var query: [URLQueryItem] = []
    if let imdb, imdb > 0 {
      query.append(URLQueryItem(name: "imdb", value: TMDBIDFormatter.imdbString(from: imdb)))
    }
    if let language {
      query.append(URLQueryItem(name: "lang", value: language))
    }
    components?.queryItems = query.isEmpty ? nil : query
    return components?.url
  }

  /// Title logo at the size the banner and hero draw (≤ 680 pt wide).
  public func logo(kinopubID: Int, imdb: Int?) -> URL? {
    url(.logo, size: .lg, kinopubID: kinopubID, imdb: imdb)
  }

  /// Full-screen textless backdrop. Original: the banner and hero fill a 4K screen.
  public func backdrop(kinopubID: Int, imdb: Int?) -> URL? {
    url(.backdrop, size: .orig, kinopubID: kinopubID, imdb: imdb)
  }

  /// The app's own localization (the per-app language setting included), not the
  /// device's first language.
  public static var appLanguage: String? {
    guard let first = Bundle.main.preferredLocalizations.first else { return nil }
    return Locale(identifier: first).language.languageCode?.identifier == "ru" ? nil : "en"
  }
}
