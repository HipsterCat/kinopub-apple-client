import Foundation

/// The worker's image route by kino.pub id:
/// `GET {worker}/img/{kind}/by/kinopub/{id}?w=&s=&e=&imdb=&lang=` answers **`302`**
/// to a stamped URL, then bytes:
///
///     /img/logo/by/kinopub/{id}/ru/logo.png
///     /img/logo/by/kinopub/{id}/en/logo.png
///     /img/backdrop/by/kinopub/{id}/und/backdrop.jpg
///     /img/cover/by/kinopub/{id}/ru/cover.jpg
///
/// The `{ru|en|und}` segment is the file's language (`und` = textless / no language).
/// **`Content-Language`** on the response matches that tag (not `en-US`). Parse the
/// final URL or header with ``WorkerArtworkLanguageTag`` — the `?lang=` query only
/// states preference, not what was served. ``Kind/cover`` is the language-tagged
/// TMDB backdrop (`images.backdrops` with `iso_639_1`); ``Kind/backdrop`` stays
/// textless.
///
/// `w` is the pixel width the picture will be drawn at, snapped onto TMDB/worker
/// buckets (`bucketedWidth`) so the worker never falls through to `/original` (a 5K Mac
/// logo used to ask `w=2560` and get a 2000–4000 px PNG). Logos use 780 / 1280;
/// backdrops top out at 1920 (tvOS) / 2400 (MacBook, KP-68).
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

  /// Caption rules from the **served** worker stamp, not the `?lang=` query.
  public init(deliveredLanguage: WorkerArtworkLanguageTag) {
    switch deliveredLanguage {
    case .en: self = .english
    case .ru, .und: self = .russianPreferred
    }
  }

  /// Caption under a confirmed logo. kino.pub splits `title` only on **` / `**
  /// (spaced slash — not `9/11` inside a name). First segment → ``localized``,
  /// second → ``original`` (``KinoPubBilingualTitle`` in KinoPubBackend). When both exist:
  /// **EN wordmark** → Russian (`localized`); **RU wordmark** → original after the slash.
  /// No ` / ` in the catalog → no second line (``partner`` only fills a missing slash).
  public func supplementaryUnderLogo(
    localized: String,
    original: String,
    partner: String? = nil
  ) -> String? {
    let partner = partner?.trimmingCharacters(in: .whitespacesAndNewlines)
    let hasPair = localized != original && !original.isEmpty
    switch self {
    case .english:
      guard hasPair else { return nil }
      return localized.isEmpty ? nil : localized
    case .russianPreferred:
      if hasPair { return original }
      if let partner, !partner.isEmpty, partner != localized { return partner }
      return nil
    }
  }
}

public struct TitleImageRoute: Sendable, Hashable {
  public enum Kind: String, Sendable {
    /// `thumbnail` is an episode still and needs a season and an episode.
    /// `cover` is a language-tagged wide TMDB backdrop (not the textless `backdrop`).
    case logo, backdrop, cover, poster, thumbnail
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

  /// TMDB/worker size tokens the client asks for to avoid `/original`.
  /// Logos skip `w1920` — a wordmark slot is hundreds of points, not a 4K plate.
  public static let logoWidthBuckets = [780, 1280]
  public static let imageWidthBuckets = [45, 92, 154, 185, 227, 300, 320, 342, 454, 500, 780, 1280, 1920, 2400]

  /// Smallest ladder step that covers `pixels`. Caps logos at 1280 and other
  /// kinds at 2400 (MacBook cap) so the worker does not serve `/original`.
  public static func bucketedWidth(_ kind: Kind, pixels: Int) -> Int {
    let ladder = kind == .logo ? logoWidthBuckets : imageWidthBuckets
    let target = max(pixels, 1)
    return ladder.first { $0 >= target } ?? ladder[ladder.count - 1]
  }

  /// - Parameters:
  ///   - width: pixels the picture is drawn at; snapped onto ``bucketedWidth``.
  ///     `nil` omits `w` (the worker's original) — callers that know a slot must pass one.
  ///   - imdb: kino.pub's numeric IMDb id. It lets the worker resolve a title it has
  ///     never seen; without it a cold title only gets kino.pub's own art.
  ///   - season: with `.poster`, that season's poster; with `.thumbnail`, required.
  ///   - episode: with `.thumbnail`, the episode whose still is asked for.
  ///   - kinopubThumb: with `.thumbnail`, optional `https://…staticpop.net/…` URL the
  ///     worker may seed and resize via wsrv.nl when TMDB has no still yet. With a title
  ///     `.poster` (no season), kino.pub's own poster: one rung of the worker's chain.
  ///   - kinopoisk: Kinopoisk id, so a cold title still has its Kinopoisk poster rung.
  public func url(_ kind: Kind, kinopubID: Int, imdb: Int?, width: Int?,
                  season: Int? = nil, episode: Int? = nil,
                  kinopubThumb: String? = nil, kinopoisk: Int? = nil) -> URL? {
    guard let baseURL, kinopubID > 0 else { return nil }
    var components = URLComponents(
      url: baseURL.appendingPathComponent("img/\(kind.rawValue)/by/kinopub/\(kinopubID)"),
      resolvingAgainstBaseURL: false
    )
    var query: [URLQueryItem] = []
    if let width, width > 0 {
      let resolvedWidth = kind == .thumbnail ? min(width, 1280) : Self.bucketedWidth(kind, pixels: width)
      query.append(URLQueryItem(name: "w", value: String(resolvedWidth)))
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
    if let kinopoisk, kinopoisk > 0 {
      query.append(URLQueryItem(name: "kinopoisk", value: String(kinopoisk)))
    }
    if let language {
      query.append(URLQueryItem(name: "lang", value: language))
    }
    let takesSource = kind == .thumbnail || ((kind == .poster || kind == .cover) && season == nil)
    if takesSource, let kinopubThumb, Self.isStaticpopThumb(kinopubThumb) {
      query.append(URLQueryItem(name: "src", value: kinopubThumb))
    }
    components?.queryItems = query.isEmpty ? nil : query
    return components?.url
  }

  /// An episode's still — one rule for every place that shows one: the title page's
  /// season rail, and the episode Continue Watching and History bring up under the
  /// pointer. The worker answers with the best still it has (tvoe, TMDB, then kino.pub's
  /// own frame via `src=`, resized to WebP), so the same episode is the same picture
  /// everywhere. `season` is kino.pub's season number, never a year from the title.
  public func episodeStill(kinopubID: Int, imdb: Int?, season: Int, episode: Int,
                           pixelWidth: Int, kinopubThumb: String?) -> URL? {
    url(.thumbnail, kinopubID: kinopubID, imdb: imdb, width: pixelWidth,
        season: season, episode: episode, kinopubThumb: kinopubThumb)
  }

  /// Pixel width for `/img/thumbnail?w=`: the slot's own pixels, capped at the worker's
  /// practical top bucket and floored at 300 so a tiny slot does not ask for a
  /// postage-stamp face crop.
  public static func episodeStillPixelWidth(points: Double, scale: Double) -> Int {
    let raw = Int((points * scale).rounded(.up))
    return min(max(raw, 300), 1280)
  }

  /// Only kino.pub's own CDN may ride on `src=` — the worker rejects anything else.
  public static func isStaticpopThumb(_ raw: String) -> Bool {
    guard let host = URL(string: raw)?.host?.lowercased() else { return false }
    return host == "staticpop.net" || host.hasSuffix(".staticpop.net")
  }

  /// Title poster, drawn at `width` pixels: the worker's chain is TMDB in the asked
  /// language, then kino.pub's own file (`kinopubPoster`), then Kinopoisk, then another
  /// language; WebP through wsrv.nl. Every vertical cover in the app comes from here, so
  /// kino.pub's CDN being down no longer blanks the grid (Sasha, 2026-11-26).
  public func poster(kinopubID: Int, imdb: Int?, kinopoisk: Int?, width: Int?,
                     kinopubPoster: String?) -> URL? {
    url(.poster, kinopubID: kinopubID, imdb: imdb, width: width,
        kinopubThumb: kinopubPoster, kinopoisk: kinopoisk)
  }

  /// A wide title card, drawn at `width` pixels: with `kinopubWide` the worker walks the
  /// cover in the language → textless backdrop → kino.pub's wide, WebP through wsrv.nl
  /// (Sasha, 2026-11-26). Without it, a plain ``cover(kinopubID:imdb:width:)``.
  public func wideCard(kinopubID: Int, imdb: Int?, width: Int?, kinopubWide: String?) -> URL? {
    url(.cover, kinopubID: kinopubID, imdb: imdb, width: width, kinopubThumb: kinopubWide)
  }

  /// Title logo, drawn at `width` pixels.
  public func logo(kinopubID: Int, imdb: Int?, width: Int?) -> URL? {
    url(.logo, kinopubID: kinopubID, imdb: imdb, width: width)
  }

  /// Textless backdrop, drawn at `width` pixels.
  public func backdrop(kinopubID: Int, imdb: Int?, width: Int?) -> URL? {
    url(.backdrop, kinopubID: kinopubID, imdb: imdb, width: width)
  }

  /// Language-tagged TMDB backdrop (`images.backdrops` with `iso_639_1`), drawn at
  /// `width` pixels. Uses the route's ``language`` (Russian when `nil`).
  public func cover(kinopubID: Int, imdb: Int?, width: Int?) -> URL? {
    url(.cover, kinopubID: kinopubID, imdb: imdb, width: width)
  }

  /// The app's own localization (the per-app language setting included), not the
  /// device's first language. Reads `selectedLanguage` so a soft remount does not
  /// wait on `Bundle.main.preferredLocalizations` (still process-pinned).
  public static var appLanguage: String? {
    let raw = UserDefaults.standard.string(forKey: "selectedLanguage")
      ?? Bundle.main.preferredLocalizations.first
    guard let raw else { return nil }
    let code = Locale(identifier: raw).language.languageCode?.identifier ?? raw
    return code == "ru" ? nil : "en"
  }
}
