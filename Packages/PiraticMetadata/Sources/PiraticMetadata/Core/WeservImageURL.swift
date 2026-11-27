import Foundation

/// Client-side resize / WebP via [images.weserv.nl](https://images.weserv.nl/).
/// Wrap the **real** source (metadata worker with language, else Kinopub / TMDB / KP) —
/// never invent bare TMDB `/t/p/{fakeSize}/` tokens (Sasha, 2026-11-26).
public enum WeservImageURL {
  public static let base = "https://images.weserv.nl/"

  /// - Parameters:
  ///   - source: Absolute URL weserv will fetch (worker `/img/…`, TMDB original, KP, …).
  ///   - width: Drawn pixel width. Nil omits `w` (weserv serves the source size as WebP).
  public static func wrapping(_ source: URL, width: Int? = nil) -> URL {
    var components = URLComponents(string: base)
    var query: [URLQueryItem] = [
      URLQueryItem(name: "url", value: source.absoluteString),
      URLQueryItem(name: "q", value: "80"),
      URLQueryItem(name: "output", value: "webp"),
    ]
    if let width, width > 0 {
      query.insert(URLQueryItem(name: "w", value: String(width)), at: 1)
    }
    components?.queryItems = query
    return components?.url ?? source
  }
}
