import Foundation

/// Language stamped on a worker image after redirect or on the durable URL:
/// `…/by/kinopub/{id}/{tag}/{kind}.ext`. The worker uses exactly **`ru`**, **`en`**, or
/// **`und`** — not BCP-47 (`en-US` is normalized to `en`). The same tag is returned in
/// **`Content-Language`** when the worker serves bytes from `/img/…/ru/logo.png` etc.
///
/// - **`und`**: no language on the picture (textless backdrops, language-neutral logos).
public enum WorkerArtworkLanguageTag: String, Sendable, Equatable, Hashable {
  case ru
  case en
  case und

  /// Whether the asset is textless / language-neutral (`und`).
  public var isTextless: Bool { self == .und }

  /// Worker tags only; strips a BCP-47 suffix (`en-US` → `en`).
  public static func normalize(_ raw: String) -> WorkerArtworkLanguageTag? {
    let token = raw
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
      .first
      .map(String.init) ?? ""
    return WorkerArtworkLanguageTag(rawValue: token)
  }

  /// Reads the `{lang}` segment from a stamped worker URL
  /// (`/img/logo/by/kinopub/100564/ru/logo.png`).
  public static func parseStampedURL(_ url: URL) -> WorkerArtworkLanguageTag? {
    let parts = url.path.split(separator: "/").map(String.init)
    // img / {kind} / by / kinopub / {id} / {lang} / {file}
    guard parts.count == 7,
          parts[0] == "img",
          parts[2] == "by",
          parts[3] == "kinopub" else { return nil }
    return normalize(parts[5])
  }

  /// Prefer the stamped path on the final URL; fall back to `Content-Language`.
  public static func resolved(answeredURL: URL?, contentLanguageHeader: String?) -> WorkerArtworkLanguageTag? {
    if let url = answeredURL, let fromPath = parseStampedURL(url) { return fromPath }
    if let header = contentLanguageHeader, let fromHeader = normalize(header) { return fromHeader }
    return nil
  }
}
