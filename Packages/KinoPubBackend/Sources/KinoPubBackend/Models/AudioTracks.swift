//
//  AudioTracks.swift
//
//

import Foundation

/// One audio rendition of an item, with everything the detail page and the player
/// default-picker need to order and label it.
public struct AudioTrackInfo: Hashable, Sendable {
  public let lang: String
  public let typeId: Int?
  public let typeTitle: String?
  public let typeShortTitle: String?
  public let authorTitle: String?
  public let channels: Int
  public let codec: String
  public let index: Int
  public let isAudioDescription: Bool

  public init(lang: String,
              typeId: Int? = nil,
              typeTitle: String? = nil,
              typeShortTitle: String? = nil,
              authorTitle: String? = nil,
              channels: Int = 2,
              codec: String = "",
              index: Int = 0,
              isAudioDescription: Bool = false) {
    self.lang = lang
    self.typeId = typeId
    self.typeTitle = typeTitle
    self.typeShortTitle = typeShortTitle
    self.authorTitle = authorTitle
    self.channels = channels
    self.codec = codec
    self.index = index
    self.isAudioDescription = isAudioDescription
  }

  public init(_ audio: VideoAudio) {
    self.init(lang: audio.lang,
              typeId: audio.type?.id,
              typeTitle: audio.type?.title,
              typeShortTitle: audio.type?.shortTitle,
              authorTitle: audio.author?.title,
              channels: audio.channels,
              codec: audio.codec,
              index: audio.index,
              isAudioDescription: AudioTracks.looksLikeAudioDescription(audio.type?.title))
  }

  public init(_ audio: EpisodeAudio) {
    self.init(lang: audio.lang,
              typeId: audio.type?.id,
              typeTitle: audio.type?.title,
              typeShortTitle: audio.type?.shortTitle,
              authorTitle: audio.author?.title,
              channels: audio.channels,
              codec: audio.codec,
              index: audio.index,
              isAudioDescription: AudioTracks.looksLikeAudioDescription(audio.type?.title))
  }
}

public extension AudioTrackInfo {
  /// The same rendition in another language — for a track kino.pub left without one.
  func withLanguage(_ code: String) -> AudioTrackInfo {
    AudioTrackInfo(lang: code, typeId: typeId, typeTitle: typeTitle, typeShortTitle: typeShortTitle,
                   authorTitle: authorTitle, channels: channels, codec: codec, index: index,
                   isAudioDescription: isAudioDescription)
  }
}

/// What a metadata source (TMDB) knows about a title's languages: the one it was made in and
/// every one spoken in it. kino.pub does not say, and sometimes ships the original sound with
/// no language at all.
public struct TitleLanguages: Hashable, Sendable {
  /// ISO 639-1 of the original production («tl», «ko»).
  public var original: String?
  /// Every language spoken in it, the original among them.
  public var spoken: [String]

  public init(original: String? = nil, spoken: [String] = []) {
    self.original = original
    self.spoken = spoken
  }

  public var originalKey: String? {
    guard let original else { return nil }
    let key = SubtitleTracks.languageKey(original)
    return key.isEmpty || AudioTracks.isUnnamedLanguage(key) ? nil : key
  }
}

/// Shared sort ladder for the detail-page Audio column and the player's default pick.
///
/// Preferred languages first (system order), then the rest A–Z; within a language
/// regular before AD; then kind (DUB → MVO → DVO → VO → AVO → Orig); then studio
/// A–Z (anonymous last); more channels before fewer; stable `index` last.
public enum AudioTracks {

  /// API type ids: 1 DUB, 2 MVO, 3 DVO, 4 VO, 5 AVO, 6 Orig. Lower rank sorts first.
  public static let kindRankUnknown = 6

  // MARK: - Catalog

  public static func catalog(_ audios: [VideoAudio]) -> [AudioTrackInfo] {
    audios.map(AudioTrackInfo.init)
  }

  public static func catalog(_ audios: [EpisodeAudio]) -> [AudioTrackInfo] {
    audios.map(AudioTrackInfo.init)
  }

  // MARK: - Sorting

  public static func sort(_ tracks: [AudioTrackInfo],
                          preferredLanguages: [String] = Locale.preferredLanguages) -> [AudioTrackInfo] {
    tracks.sorted {
      sortKey(for: $0, preferredLanguages: preferredLanguages)
        < sortKey(for: $1, preferredLanguages: preferredLanguages)
    }
  }

  public static func sortKey(for track: AudioTrackInfo,
                             preferredLanguages: [String] = Locale.preferredLanguages) -> SortKey {
    sortKey(lang: track.lang,
            typeId: track.typeId,
            typeTitle: track.typeTitle,
            typeShortTitle: track.typeShortTitle,
            author: track.authorTitle,
            channels: track.channels,
            isAudioDescription: track.isAudioDescription,
            index: track.index,
            preferredLanguages: preferredLanguages)
  }

  public static func sortKey(lang: String,
                             typeId: Int? = nil,
                             typeTitle: String? = nil,
                             typeShortTitle: String? = nil,
                             author: String? = nil,
                             channels: Int = 2,
                             isAudioDescription: Bool = false,
                             index: Int = 0,
                             preferredLanguages: [String] = Locale.preferredLanguages) -> SortKey {
    let (priority, alphaName) = languageSort(lang: lang, preferredLanguages: preferredLanguages)
    let studio = normalizedAuthor(author)
    return SortKey(languagePriority: priority,
                   languageName: alphaName,
                   isAudioDescription: isAudioDescription,
                   kindRank: kindRank(typeId: typeId, typeTitle: typeTitle, typeShortTitle: typeShortTitle),
                   hasAuthor: studio != nil,
                   authorName: studio?.lowercased() ?? "",
                   channels: channels,
                   index: index)
  }

  /// Ascending = preferred order for lists; the player's default is the first key.
  public struct SortKey: Comparable {
    public let languagePriority: Int
    public let languageName: String
    public let isAudioDescription: Bool
    public let kindRank: Int
    public let hasAuthor: Bool
    public let authorName: String
    public let channels: Int
    public let index: Int

    public static func < (l: SortKey, r: SortKey) -> Bool {
      if l.languagePriority != r.languagePriority { return l.languagePriority < r.languagePriority }
      if l.languageName != r.languageName { return l.languageName < r.languageName }
      if l.isAudioDescription != r.isAudioDescription { return !l.isAudioDescription && r.isAudioDescription }
      if l.kindRank != r.kindRank { return l.kindRank < r.kindRank }
      if l.hasAuthor != r.hasAuthor { return l.hasAuthor && !r.hasAuthor }
      if l.authorName != r.authorName { return l.authorName < r.authorName }
      if l.channels != r.channels { return l.channels > r.channels }
      return l.index < r.index
    }
  }

  // MARK: - Labels

  /// Sorted, human-facing labels. Same lang+type+author collapses to one row — the
  /// better rendition (more channels) is already first after `sort`.
  public static func descriptions(for tracks: [AudioTrackInfo],
                                  preferredLanguages: [String] = Locale.preferredLanguages) -> [String] {
    var seen = Set<String>()
    return sort(tracks, preferredLanguages: preferredLanguages).compactMap { track in
      let label = baseLabel(track)
      guard seen.insert(label).inserted else { return nil }
      return label
    }
  }

  /// Languages in sort order, each with kind lines like
  /// `Дубляж (2), Кубик в Кубе, Мосфильм`.
  ///
  /// A track kino.pub left without a language is named by `languages` when it is the original
  /// sound (`resolvingUnnamedLanguage`), and otherwise reads «На языке оригинала · Язык не
  /// указан» rather than «Неизвестный язык». The original language lists the others spoken in
  /// the title under it.
  public static func languageGroups(for tracks: [AudioTrackInfo],
                                    preferredLanguages: [String] = Locale.preferredLanguages,
                                    languages: TitleLanguages = TitleLanguages())
  -> [MediaLanguageGroup] {
    let resolved = resolvingUnnamedLanguage(tracks, languages: languages)
    let originalIsUnnamed = unnamedIsOriginal(resolved)
    let sorted = sort(resolved, preferredLanguages: preferredLanguages)
    var order: [String] = []
    var byLanguage: [String: [AudioTrackInfo]] = [:]
    for track in sorted {
      let key = SubtitleTracks.languageKey(track.lang)
      if byLanguage[key] == nil { order.append(key) }
      byLanguage[key, default: []].append(track)
    }
    return order.compactMap { key in
      guard let group = byLanguage[key], let first = group.first else { return nil }
      if originalIsUnnamed && isUnnamedLanguage(key) {
        // «Оригинал» under «На языке оригинала» says the same thing twice.
        let voiced = group.filter { kindRank(of: $0) != originalKindRank }
        return MediaLanguageGroup(key: key,
                                  name: originalLanguageName,
                                  detailLines: kindSummaryLines(for: voiced) + [languageNotSpecified])
      }
      var lines = kindSummaryLines(for: group)
      if key == languages.originalKey, let spoken = alsoSpokenLine(languages, besides: key) {
        lines.append(spoken)
      }
      return MediaLanguageGroup(key: key,
                                name: LanguageNames.name(for: first.lang),
                                detailLines: lines)
    }
  }

  // MARK: - Tracks with no language

  /// What kino.pub and the CDN write where they do not know the language. ISO 639-2 `und`
  /// (undetermined) is the usual one; Foundation names it «Неизвестный язык».
  private static let unnamedLanguageCodes: Set<String> = ["", "und", "unk", "mis", "zxx", "xx", "xxx"]

  public static func isUnnamedLanguage(_ code: String) -> Bool {
    unnamedLanguageCodes.contains(LanguageNames.canonicalCode(code))
  }

  private static var originalKindRank: Int { VoiceType.original.preferenceRank }

  private static func kindRank(of track: AudioTrackInfo) -> Int {
    kindRank(typeId: track.typeId, typeTitle: track.typeTitle, typeShortTitle: track.typeShortTitle)
  }

  /// Whether the tracks with no language are the title's original sound (Sasha, 2026-11-28):
  /// kino.pub marks one as the original, or it sits beside the dubs of a single language — a
  /// Russian voice-over and the original, or a concert's one track. Never when a named track
  /// already is the original.
  public static func unnamedIsOriginal(_ tracks: [AudioTrackInfo]) -> Bool {
    let regular = tracks.filter { !$0.isAudioDescription }
    let unnamed = regular.filter { isUnnamedLanguage($0.lang) }
    guard !unnamed.isEmpty else { return false }
    if unnamed.contains(where: { kindRank(of: $0) == originalKindRank }) { return true }
    let named = regular.filter { !isUnnamedLanguage($0.lang) }
    if named.contains(where: { kindRank(of: $0) == originalKindRank }) { return false }
    return Set(named.map { SubtitleTracks.languageKey($0.lang) }).count <= 1
  }

  /// The unnamed original sound in the language the title was made in, when a metadata source
  /// knows it and no track is in that language already. Everything else as it came.
  public static func resolvingUnnamedLanguage(_ tracks: [AudioTrackInfo],
                                              languages: TitleLanguages) -> [AudioTrackInfo] {
    guard let original = languages.originalKey,
          unnamedIsOriginal(tracks),
          !tracks.contains(where: { SubtitleTracks.languageKey($0.lang) == original })
    else { return tracks }
    return tracks.map { isUnnamedLanguage($0.lang) ? $0.withLanguage(original) : $0 }
  }

  /// «На языке оригинала» — the unnamed original sound's row.
  public static var originalLanguageName: String {
    String(localized: "Original language", bundle: .module)
  }

  /// «Ориг» — the same in the hero's three-letter language list.
  public static var originalLanguageShortName: String {
    String(localized: "Original language (short)", bundle: .module)
  }

  /// «Язык не указан», grey under `originalLanguageName`.
  public static var languageNotSpecified: String {
    String(localized: "Language not specified", bundle: .module)
  }

  /// «Также звучат: японский и английский» — the other languages spoken in the title.
  public static func alsoSpokenLine(_ languages: TitleLanguages, besides key: String) -> String? {
    var seen: Set<String> = [key]
    let others = languages.spoken
      .map(SubtitleTracks.languageKey)
      .filter { !$0.isEmpty && !isUnnamedLanguage($0) && seen.insert($0).inserted }
      .compactMap { Locale.current.localizedString(forLanguageCode: $0) }
    guard !others.isEmpty else { return nil }
    let list = others.formatted(.list(type: .and))
    return String(localized: "Also spoken: \(list)", bundle: .module)
  }

  /// One line per dub kind within a language: kind, optional count, studios.
  public static func kindSummaryLines(for tracks: [AudioTrackInfo]) -> [String] {
    var kindOrder: [Int] = []
    var byKind: [Int: [AudioTrackInfo]] = [:]
    for track in tracks {
      let rank = kindRank(typeId: track.typeId,
                          typeTitle: track.typeTitle,
                          typeShortTitle: track.typeShortTitle)
      if byKind[rank] == nil { kindOrder.append(rank) }
      byKind[rank, default: []].append(track)
    }
    return kindOrder.compactMap { rank in
      guard let group = byKind[rank] else { return nil }
      return kindSummaryLine(rank: rank, tracks: group)
    }
  }

  private static func kindSummaryLine(rank: Int, tracks: [AudioTrackInfo]) -> String? {
    var seenAuthors = Set<String>()
    var authors: [String?] = []
    for track in tracks {
      let author = normalizedAuthor(track.authorTitle)
      let bucket = author?.lowercased() ?? ""
      guard seenAuthors.insert(bucket).inserted else { continue }
      authors.append(author)
    }
    guard !authors.isEmpty else { return nil }

    let kind = localizedKindLabel(typeId: tracks.first?.typeId,
                                  typeTitle: tracks.first?.typeTitle,
                                  typeShortTitle: tracks.first?.typeShortTitle)
      ?? tracks.first?.typeTitle
      ?? tracks.first?.typeShortTitle
      ?? ""
    guard !kind.isEmpty else { return nil }

    var head = kind
    if authors.count > 1 {
      head += " (\(authors.count))"
    }

    let unknown = String(localized: "Unknown", bundle: .module)
    let named = authors.compactMap { $0 }
    let hasAnonymous = authors.contains { $0 == nil }
    // A lone anonymous original reads cleaner as just the kind — "Original", not
    // "Original, Unknown".
    if named.isEmpty && authors.count == 1 { return head }

    var studios = named
    if hasAnonymous { studios.append(unknown) }
    guard !studios.isEmpty else { return head }
    return "\(head), \(studios.joined(separator: ", "))"
  }

  public static func uniquedHLSLabels(_ labels: [String]) -> [String] {
    var totals: [String: Int] = [:]
    for label in labels { totals[label, default: 0] += 1 }
    var seen: [String: Int] = [:]
    return labels.map { label in
      guard totals[label, default: 0] > 1 else { return label }
      let n = seen[label, default: 0] + 1
      seen[label] = n
      return n == 1 ? label : "\(label) ∙ \(n)"
    }
  }

  /// "Russian ∙ Multi-voice, LostFilm" — language sentence-cased, kind localized,
  /// studio after a comma.
  public static func baseLabel(_ track: AudioTrackInfo) -> String {
    let language = LanguageNames.name(for: track.lang)
    let kind = localizedKindLabel(typeId: track.typeId,
                                  typeTitle: track.typeTitle,
                                  typeShortTitle: track.typeShortTitle)
    let author = normalizedAuthor(track.authorTitle)

    switch (kind, author) {
    case let (kind?, author?):
      return "\(language) ∙ \(kind), \(author)"
    case let (kind?, nil):
      return "\(language) ∙ \(kind)"
    case let (nil, author?):
      return "\(language) ∙ \(author)"
    case (nil, nil):
      return language
    }
  }

  /// Localized dub-kind word for the middle of an audio label. Falls back to the
  /// API title when the kind is unknown.
  public static func localizedKindLabel(typeId: Int?,
                                        typeTitle: String?,
                                        typeShortTitle: String?) -> String? {
    let rank = kindRank(typeId: typeId, typeTitle: typeTitle, typeShortTitle: typeShortTitle)
    if let key = kindLocalizationKey(rank) {
      return String(localized: key, bundle: .module)
    }
    if let typeTitle, !typeTitle.isEmpty { return typeTitle }
    if let typeShortTitle, !typeShortTitle.isEmpty { return typeShortTitle }
    return nil
  }

  /// The dub kind for a rank, when that is all you have — a remembered signature carries a
  /// rank, not the API row it came from.
  public static func localizedKindLabel(rank: Int) -> String? {
    guard let key = kindLocalizationKey(rank) else { return nil }
    return String(localized: key, bundle: .module)
  }

  private static func kindLocalizationKey(_ rank: Int) -> String.LocalizationValue? {
    switch rank {
    case 0: return "Dubbed"
    case 1: return "Multi-voice"
    case 2: return "Two-voice"
    case 3: return "Single-voice"
    case 4: return "Author's"
    case 5: return "Original"
    default: return nil
    }
  }

  // MARK: - Kind / language helpers

  /// Lower sorts earlier. Prefer the API type id when present.
  public static func kindRank(typeId: Int?, typeTitle: String?, typeShortTitle: String?) -> Int {
    // The API's type id, through the one `VoiceType` table (DUB → … → Orig).
    if let typeId, let type = VoiceType(rawValue: typeId), type.preferenceRank != kindRankUnknown {
      return type.preferenceRank
    }
    let blob = [typeTitle, typeShortTitle].compactMap { $0 }.joined(separator: " ")
    if !blob.isEmpty { return kindRank(fromLabel: blob) }
    return kindRankUnknown
  }

  /// Parses kino.pub / HLS display names. AVO is checked before VO so "AVO" does not
  /// fall through as unknown.
  public static func kindRank(fromLabel label: String) -> Int {
    let name = label.lowercased()
    if name.contains("дубляж") || name.contains("дублир")
        || name.contains("dubbed") || containsToken(name, "dub") { return 0 }
    if name.contains("многоголос") || name.contains("multi")
        || containsToken(name, "mvo") { return 1 }
    if name.contains("двухголос") || name.contains("two")
        || containsToken(name, "dvo") { return 2 }
    if name.contains("авторск") || name.contains("author")
        || containsToken(name, "avo") { return 4 }
    if name.contains("одноголос") || name.contains("single")
        || containsToken(name, "ovo") || containsToken(name, "vo") { return 3 }
    if name.contains("оригинал") || name.contains("original")
        || containsToken(name, "orig") { return 5 }
    return kindRankUnknown
  }

  public static func looksLikeAudioDescription(_ title: String?) -> Bool {
    guard let title, !title.isEmpty else { return false }
    let name = title.lowercased()
    return name.contains("audio description")
      || name.contains("аудиоописание")
      || name.contains("описание")
      || containsToken(name, "ad")
  }

  /// Studio text from a display label — `∙ Kind, Studio`, trailing `(Studio)`, or
  /// legacy `∙ Kind ∙ Studio`.
  public static func authorFromDisplayName(_ name: String) -> String? {
    if let open = name.lastIndex(of: "("),
       let close = name[open...].firstIndex(of: ")"),
       open < close {
      let inner = String(name[name.index(after: open)..<close])
        .trimmingCharacters(in: .whitespacesAndNewlines)
      if !inner.isEmpty { return inner }
    }

    for separator in [" ∙ ", " · ", " — "] {
      let parts = name.components(separatedBy: separator)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
      guard parts.count >= 2 else { continue }

      // "Lang ∙ Kind, Studio" or "Lang ∙ Kind, Studio ∙ 2"
      let afterLanguage = parts[1]
      if let comma = afterLanguage.firstIndex(of: ",") {
        let studio = afterLanguage[afterLanguage.index(after: comma)...]
          .trimmingCharacters(in: .whitespacesAndNewlines)
        if !studio.isEmpty { return studio }
      }

      // Legacy "Lang ∙ Kind ∙ Studio ∙ 2"
      guard parts.count >= 3 else { continue }
      if parts.count >= 4, Int(parts.last!) != nil {
        return parts[parts.count - 2]
      }
      if Int(parts.last!) != nil { return nil }
      return parts.last
    }
    return nil
  }

  public static func channelCount(fromLabel label: String) -> Int {
    let name = label.lowercased()
    if name.contains("7.1") { return 8 }
    if name.contains("5.1") { return 6 }
    if name.contains("2.0") || name.contains("стерео") || name.contains("stereo") { return 2 }
    if name.contains("mono") || name.contains("моно") { return 1 }
    return 2
  }

  // MARK: - Private

  private static func languageSort(lang: String,
                                   preferredLanguages: [String]) -> (priority: Int, name: String) {
    let key = SubtitleTracks.languageKey(lang)
    if let idx = preferredLanguages.firstIndex(where: { SubtitleTracks.languageKey($0) == key }) {
      return (idx, "")
    }
    let display = LanguageNames.name(for: lang).lowercased()
    return (preferredLanguages.count, display.isEmpty ? key : display)
  }

  private static func normalizedAuthor(_ author: String?) -> String? {
    guard let author else { return nil }
    let trimmed = author.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func containsToken(_ text: String, _ token: String) -> Bool {
    text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
      .contains { $0 == token }
  }
}
