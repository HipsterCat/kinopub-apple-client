import Foundation

/// Which YouTube videos still exist, judged by their still: a removed video or a closed
/// channel leaves TMDB's entry behind, and its `hqdefault` answers 404 — the grey tile on
/// the title page (Sasha, 2026-11-04: drop those). One HEAD per video, in parallel,
/// remembered for the session.
public enum YouTubeThumbnailProbe {
  private actor Memory {
    var known: [String: Bool] = [:]
    func value(_ key: String) -> Bool? { known[key] }
    func set(_ key: String, _ value: Bool) { known[key] = value }
  }

  private static let memory = Memory()

  /// `videos` without the ones whose still does not load, order kept. Anything but a 200
  /// counts as gone: a card with no picture is what is being removed.
  public static func available(_ videos: [TrailerRef],
                               session: URLSession = .shared) async -> [TrailerRef] {
    let verdicts = await withTaskGroup(of: (String, Bool).self) { group in
      for video in videos {
        group.addTask {
          if let known = await memory.value(video.key) { return (video.key, known) }
          guard let url = video.thumbnailURL else { return (video.key, false) }
          var request = URLRequest(url: url, timeoutInterval: 10)
          request.httpMethod = "HEAD"
          let ok: Bool
          do {
            let (_, response) = try await session.data(for: request)
            ok = (response as? HTTPURLResponse)?.statusCode == 200
          } catch {
            // Offline or cancelled: not a verdict on the video, so not remembered.
            return (video.key, false)
          }
          await memory.set(video.key, ok)
          return (video.key, ok)
        }
      }
      var result: [String: Bool] = [:]
      for await (key, ok) in group { result[key] = ok }
      return result
    }
    return videos.filter { verdicts[$0.key] == true }
  }
}
