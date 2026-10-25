import Foundation

/// The worker's image route by kino.pub id:
/// `GET {worker}/img/{kind}/by/kinopub/{id}?w=&s=&e=&imdb=&lang=` answers `302` to the
/// picture (TMDB's smallest bucket that covers `w`, kino.pub's own art as the
/// poster/backdrop fallback) or `404` when there is none. The client puts the URL
/// straight into an image view — no details call, no TMDB lookup, no JSON.
///
/// `w` is the pixel width the picture will be drawn at, so the size is the screen's
/// decision, not a constant baked into the worker: a 4K banner gets TMDB's original,
/// a card gets a small bucket.
///
/// **One title, one URL.** The Home banner and the detail hero build it from the same
/// inputs (kino.pub id + IMDb id + the same width), so the hero gets the banner's bytes
/// from the artwork cache instead of downloading the same logo again.
/// Which logo the worker route asks for (`lang` query). Drives the line spelled under
/// a wordmark on the detail hero once we treat the fetched image as that request.
public enum TitleLogoRequestKind: Sendable, Equatable {
  /// No `lang` on the route — Russian first, then English (``TitleImageRoute`` default).
  case russianPreferred
  /// `lang=en` on the route.
  case english

  public init(routeLanguage: String?) {
    self = routeLanguage == "en" ? .english : .russianPreferred
  }

  /// Caption under a confirmed logo: English wordmark → localized name; Russian
  /// wordmark → original / international title when it differs.
  ///
  /// The route asks for Russian first, but the worker may still redirect to an English
  /// file when that is all TMDB has. A catalog title without `RU / EN` then has no
  /// separate ``original`` — spell the localized name under that wordmark.
  public func supplementaryUnderLogo(localized: String, original: String) -> String? {
    switch self {
    case .english:
      return localized.isEmpty ? nil : localized
    case .russianPreferred:
      if localized != original, !original.isEmpty { return original }
      guard Self.catalogTitleUsesCyrillic(localized) else { return nil }
      return localized.isEmpty ? nil : localized
    }
  }

  /// kino.pub's localized side of the title — not a guess about the PNG pixels.
  private static func catalogTitleUsesCyrillic(_ title: String) -> Bool {
    title.unicodeScalars.contains { (0x0400...0x04FF).contains($0.value) }
  }
}

public struct TitleImageRoute: Sendable, Hashable {
  public enum Kind: String, Sendable {
    /// `thumbnail` is an episode still and needs a season and an episode.
    case logo, backdrop, poster, thumbnail
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

  public var logoRequestKind: TitleLogoRequestKind {
    TitleLogoRequestKind(routeLanguage: language)
  }

  /// - Parameters:
  ///   - width: pixels the picture is drawn at; `nil` asks for the original.
  ///   - imdb: kino.pub's numeric IMDb id. It lets the worker resolve a title it has
  ///     never seen; without it a cold title only gets kino.pub's own art.
  ///   - season: with `.poster`, that season's poster; with `.thumbnail`, required.
  ///   - episode: with `.thumbnail`, the episode whose still is asked for.
  public func url(_ kind: Kind, kinopubID: Int, imdb: Int?, width: Int?,
                  season: Int? = nil, episode: Int? = nil) -> URL? {
    guard let baseURL, kinopubID > 0 else { return nil }
    var components = URLComponents(
      url: baseURL.appendingPathComponent("img/\(kind.rawValue)/by/kinopub/\(kinopubID)"),
      resolvingAgainstBaseURL: false
    )
    var query: [URLQueryItem] = []
    if let width, width > 0 {
      query.append(URLQueryItem(name: "w", value: String(width)))
    }
    if let season {
      query.append(URLQueryItem(name: "s", value: String(season)))
    }
    if let episode {
      query.append(URLQueryItem(name: "e", value: String(episode)))
    }
    if let imdb, imdb > 0 {
      query.append(URLQueryItem(name: "imdb", value: TMDBIDFormatter.imdbString(from: imdb)))
    }
    if let language {
      query.append(URLQueryItem(name: "lang", value: language))
    }
    components?.queryItems = query.isEmpty ? nil : query
    return components?.url
  }

  /// Title logo, drawn at `width` pixels.
  public func logo(kinopubID: Int, imdb: Int?, width: Int?) -> URL? {
    url(.logo, kinopubID: kinopubID, imdb: imdb, width: width)
  }

  /// Textless backdrop, drawn at `width` pixels.
  public func backdrop(kinopubID: Int, imdb: Int?, width: Int?) -> URL? {
    url(.backdrop, kinopubID: kinopubID, imdb: imdb, width: width)
  }

  /// The app's own localization (the per-app language setting included), not the
  /// device's first language.
  public static var appLanguage: String? {
    guard let first = Bundle.main.preferredLocalizations.first else { return nil }
    return Locale(identifier: first).language.languageCode?.identifier == "ru" ? nil : "en"
  }
}
