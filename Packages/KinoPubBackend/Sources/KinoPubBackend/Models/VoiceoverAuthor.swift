//
//  VoiceoverAuthor.swift
//  KinoPubBackend
//
//  Every studio and voice kino.pub credits for a track, bundled: `voiceover-authors.json`
//  is kino.watch's filter list in its own order (popular first — Лицензия, iTunes,
//  LostFilm, Кубик в Кубе…) followed by the rest of `GET /v1/references/voiceover-author`
//  (834 in all, 2026-09-26). The ids are the API's `audio.author.id`.
//
//  `voiceType` is empty for now and is the place to record what a studio does (most are
//  one kind: LostFilm multi-voice, Гоблин single-voice…) — along with any narrowing by
//  genre, language or years — so filters, a "preferred voiceover" setting and the track
//  picker read one catalog.
//
//  Note: the mobile API does not filter by author (`voiceAuthor=` ignored, 2026-09-26);
//  kino.watch does it on its own backend.
//

import Foundation

public struct VoiceoverAuthor: Codable, Hashable, Sendable, Identifiable {
  public let id: Int
  public let title: String
  public var voiceType: VoiceType?

  public init(id: Int, title: String, voiceType: VoiceType? = nil) {
    self.id = id
    self.title = title
    self.voiceType = voiceType
  }

  /// The whole catalog in kino.watch order. Loaded once from the bundle.
  public static let catalog: [VoiceoverAuthor] = {
    struct File: Decodable { let authors: [VoiceoverAuthor] }
    guard let url = Bundle.module.url(forResource: "voiceover-authors", withExtension: "json"),
          let data = try? Data(contentsOf: url),
          let file = try? JSONDecoder().decode(File.self, from: data)
    else { return [] }
    return file.authors
  }()

  public static func named(id: Int) -> VoiceoverAuthor? {
    byID[id]
  }

  private static let byID: [Int: VoiceoverAuthor] = Dictionary(catalog.map { ($0.id, $0) },
                                                               uniquingKeysWith: { first, _ in first })
}
