import Foundation

/// Cast/crew face URLs: Kinopoisk is preferred when the file is real and large enough;
/// a missing, placeholder, or clearly tiny Kinopoisk headshot yields to TMDB (or any
/// stronger candidate). TMDB / pushbr / other hosts are never treated as "tiny" by the
/// path heuristic — only Kinopoisk CDN patterns encode a reliable width.
public enum PersonPhoto: Sendable {
  /// Kinopoisk `iphone120_…` and similar are ~120px; anything at or below this
  /// width is an upgrade candidate when TMDB has a better face (Sasha, 2026-11-26).
  public static let kinopoiskLowResMaxWidth = 200

  /// True when there is no usable face, or only a clearly small Kinopoisk one.
  public static func needsUpgrade(_ url: URL?) -> Bool {
    guard let url else { return true }
    let raw = url.absoluteString
    if raw.isKinopoiskPlaceholderImage { return true }
    guard isKinopoiskHost(url) else { return false }
    if raw.contains("kp_small") || raw.contains("actor_posters/kp_small") {
      return true
    }
    if let width = inferredWidth(in: raw), width <= kinopoiskLowResMaxWidth {
      return true
    }
    return false
  }

  /// Pick a face for the rail. Strong Kinopoisk wins; otherwise any non-upgrade
  /// candidate; weak Kinopoisk only when nothing better exists. `existing` wins ties
  /// so a merge does not churn a good URL.
  public static func picking(existing: URL?, candidate: URL?) -> URL? {
    let left = usable(existing)
    let right = usable(candidate)
    switch (left, right) {
    case (nil, let only): return only
    case (let only, nil): return only
    case (let a?, let b?):
      let aWeak = needsUpgrade(a)
      let bWeak = needsUpgrade(b)
      let aKP = isKinopoiskHost(a)
      let bKP = isKinopoiskHost(b)
      if aKP, !aWeak { return a }
      if bKP, !bWeak { return b }
      if !aWeak { return a }
      if !bWeak { return b }
      return a
    }
  }

  /// Best face among `urls` under the same rules as `picking`.
  public static func best(in urls: [URL?]) -> URL? {
    urls.reduce(nil) { picking(existing: $0, candidate: $1) }
  }

  // MARK: - Internals

  private static func usable(_ url: URL?) -> URL? {
    guard let url else { return nil }
    return url.absoluteString.isKinopoiskPlaceholderImage ? nil : url
  }

  public static func isKinopoiskHost(_ url: URL) -> Bool {
    guard let host = url.host?.lowercased() else { return false }
    return host.contains("kinopoisk")
      || host == "st.kp.yandex.net"
      || host.hasSuffix(".kp.yandex.net")
      || (host.contains("yandex.") && url.path.contains("kinopoisk"))
  }

  /// Width hinted by the URL itself — `iphone360_…`, `/200x300/`, `…/120x`, `w=150`.
  public static func inferredWidth(in raw: String) -> Int? {
    if let match = raw.range(of: #"iphone(\d+)_"#, options: .regularExpression) {
      let digits = raw[match].filter(\.isNumber)
      if let value = Int(digits) { return value }
    }
    if let match = raw.range(of: #"/(\d{2,4})x(\d{2,4})(/|$)"#, options: .regularExpression) {
      let slice = String(raw[match])
      if let width = slice.split(separator: "x").first.flatMap({ Int($0.filter(\.isNumber)) }) {
        return width
      }
    }
    if let match = raw.range(of: #"/(\d{2,4})x(/|$)"#, options: .regularExpression) {
      let digits = raw[match].filter(\.isNumber)
      if let value = Int(digits) { return value }
    }
    if let match = raw.range(of: #"[?&]w(idth)?=(\d+)"#, options: .regularExpression) {
      let digits = raw[match].filter(\.isNumber)
      if let value = Int(digits) { return value }
    }
    return nil
  }
}
