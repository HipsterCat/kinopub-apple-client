import Foundation

public enum KinoPubArtworkCDN {
  private static let hosts = ["m.staticpop.net", "m.pushbr.com", "m.boramoraboom.ru"]

  private static func sourceComponents(_ url: URL) -> URLComponents? {
    guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          components.scheme?.lowercased() == "https",
          components.port == nil || components.port == 443,
          components.user == nil, components.password == nil,
          let host = components.host?.lowercased(), hosts.contains(host) else { return nil }
    return components
  }

  public static func isThumbnail(_ url: URL) -> Bool {
    guard let components = sourceComponents(url) else { return false }
    return isThumbnailPath(components.percentEncodedPath)
  }

  private static func isThumbnailPath(_ path: String) -> Bool {
    path.wholeMatch(of: /\/thumb\/.+\.jpg/) != nil
  }

  /// The requested file first, followed by the same path and query on each mirror.
  public static func origins(for url: URL) -> [URL]? {
    guard var components = sourceComponents(url), let host = components.host?.lowercased() else { return nil }
    let path = components.percentEncodedPath
    let isPoster = path.wholeMatch(of: /\/poster\/item\/(small|medium|big|wide)\/[0-9]+\.jpg/) != nil
    guard isPoster || isThumbnailPath(path) else { return nil }
    let mirrors = hosts.filter { $0 != host }.compactMap { mirror in
      components.host = mirror
      return components.url
    }
    return [url] + mirrors
  }
}
