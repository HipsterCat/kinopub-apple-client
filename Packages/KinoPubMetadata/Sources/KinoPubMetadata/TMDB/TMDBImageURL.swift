import Foundation

public enum TMDBImageSize: String, Sendable {
  case profileW185 = "w185"
  case profileW342 = "w342"
  case logoW500 = "w500"
  case stillW300 = "w300"
  case posterW780 = "w780"
  case backdropOriginal = "original"
}

public enum TMDBImageURL {
  public static let cdnBase = "https://image.tmdb.org/t/p/"

  /// Builds an image URL. When `proxyBase` is set (our Cloudflare Worker), paths go
  /// through `{proxy}/t/p/{size}{path}` so local DNS/proxy blocks on `image.tmdb.org`
  /// (Chrome → 127.0.0.1) don't break portraits and logos.
  public static func url(path: String?, size: TMDBImageSize, proxyBase: URL? = nil) -> URL? {
    guard let path, !path.isEmpty else { return nil }
    let normalized = path.hasPrefix("/") ? path : "/\(path)"
    let suffix = "\(size.rawValue)\(normalized)"
    if let proxyBase {
      let base = proxyBase.absoluteString.hasSuffix("/")
        ? String(proxyBase.absoluteString.dropLast())
        : proxyBase.absoluteString
      return URL(string: "\(base)/t/p/\(suffix)")
    }
    return URL(string: "\(cdnBase)\(suffix)")
  }

  /// A card already carries absolute image URLs. `image.tmdb.org` goes through the
  /// worker's `/t/p/…` forwarder — the same hop portraits use — so a DNS hijack of
  /// that host does not blank the page. Anything else (Kinopoisk, tvoe) stays as given.
  public static func proxied(_ absolute: String?, proxyBase: URL?) -> URL? {
    guard let absolute, !absolute.isEmpty, var url = URL(string: absolute) else { return nil }
    guard let proxyBase, url.host == "image.tmdb.org" else { return url }
    guard url.path.hasPrefix("/t/p/") else { return url }
    let base = proxyBase.absoluteString.hasSuffix("/")
      ? String(proxyBase.absoluteString.dropLast())
      : proxyBase.absoluteString
    url = URL(string: base + url.path + (url.query.map { "?\($0)" } ?? "")) ?? url
    return url
  }
}
