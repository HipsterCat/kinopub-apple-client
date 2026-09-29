//
//  AudioRenditions.swift
//
//

import Foundation

/// One audio rendition as the player sees it, reduced to what matching needs.
///
/// A protocol rather than `AVMediaSelectionOption` on purpose: the matching rules below
/// are the part with the sharp edges — duplicate names, suffixes, missing metadata — and
/// they are worth testing without an asset, a network and a simulator. `AVFoundation`
/// conforms to this in the app.
public protocol AudioRendition {
  /// The rendition's `NAME=` from the master playlist, not the language `displayName`.
  var renditionName: String { get }
  var renditionLanguageCode: String { get }
  var describesVideoForAccessibility: Bool { get }
}

/// Bridging between what `TrackResolver` decides — an `AudioTrackInfo` from the API — and
/// what the player can actually select.
///
/// **Two kinds of master reach the player, and they are named differently.** The CDN's own
/// names each rendition after the API row it carries — `01. Многоголосый. Rezka (RUS)`,
/// the number being the row's `index` — and the relabelled one (`HLSAudioLabeler`, behind
/// `FeatureFlags.rewritesStreamTrackMenus`) replaces that with `AudioTracks.baseLabel`.
/// `Naming` says which one the caller handed the player; the pairing reads each the way
/// it was written, so one set of rules serves both, and the relabeller itself.
public enum AudioRenditions {

  /// How the renditions in front of the player were named.
  public enum Naming {
    /// The CDN's master, untouched: `NN. Kind. Studio (LANG)`, `NN` the API row's `index`.
    case asDelivered
    /// Rewritten by `HLSAudioLabeler`: every `NAME=` is the API row's `baseLabel`.
    case apiLabels
  }

  /// HLS forbids two identical `NAME=` in one group, so the master rewrite
  /// (`AudioTracks.uniquedHLSLabels`) uniques duplicates with this. Matching has to
  /// see past it.
  static let duplicateSuffix = " ∙ "

  /// The menu to reason about when the API gave no track metadata — a downloaded file, or
  /// a master we did not relabel. Reading kind and studio back out of the rendition's own
  /// name is worse than the API's fields, and much better than AVFoundation's default of
  /// "first rendition in the system language".
  ///
  /// `index` is the rendition's position, which is what `rendition(for:…)` matches on.
  public static func menu(from renditions: [any AudioRendition]) -> [AudioTrackInfo] {
    renditions.enumerated().map { index, rendition in
      let name = rendition.renditionName
      let language = rendition.renditionLanguageCode
      return AudioTrackInfo(lang: language,
                            typeTitle: kindText(in: name, language: language),
                            authorTitle: studio(in: name, language: language),
                            channels: AudioTracks.channelCount(fromLabel: name),
                            index: index,
                            isAudioDescription: rendition.describesVideoForAccessibility)
    }
  }

  // MARK: - Pairing

  /// The API row each rendition carries, by the rendition's position. `nil` where none can
  /// be named — the rendition is on the master but not in the API's list, or the names
  /// say nothing.
  ///
  /// - `apiLabels`: by label, exactly and then past a duplicate suffix. Nothing else — a
  ///   relabelled master that does not match was relabelled from a different list.
  /// - `asDelivered`: by the leading number first. It is the row's id, so every copy of a
  ///   rendition — the CDN repeats them once per video quality — pairs with the same row.
  ///   What is left goes by language, in the API's own listing order (`index`), each row
  ///   taken once: several same-language dubs with no numbers are listed in the same order
  ///   on both sides, and that is the only thing left to match on.
  public static func pairing<R: AudioRendition>(_ renditions: [R],
                                                apiTracks: [AudioTrackInfo],
                                                naming: Naming) -> [AudioTrackInfo?] {
    switch naming {
    case .apiLabels:
      return renditions.map { rendition in
        let name = rendition.renditionName
        return apiTracks.first(where: { AudioTracks.baseLabel($0) == name })
          ?? apiTracks.first(where: { name.hasPrefix(AudioTracks.baseLabel($0) + duplicateSuffix) })
      }
    case .asDelivered:
      var paired = renditions.map { rendition -> AudioTrackInfo? in
        guard let number = sourceIndex(in: rendition.renditionName) else { return nil }
        return apiTracks.first { $0.index == number }
      }
      var remaining = apiTracks.filter { track in !paired.contains { $0 == track } }
      for (position, rendition) in renditions.enumerated() where paired[position] == nil {
        let key = SubtitleTracks.languageKey(rendition.renditionLanguageCode)
        guard !key.isEmpty else { continue }
        let candidates = remaining.indices.filter { remaining[$0].languageKey == key }
        guard let next = candidates.min(by: { remaining[$0].index < remaining[$1].index }) else { continue }
        paired[position] = remaining.remove(at: next)
      }
      return paired
    }
  }

  /// The rendition carrying `track`.
  ///
  /// `apiTracks` empty means the menu was synthesised from these renditions, so the
  /// track's `index` is the answer. Otherwise the first rendition paired with it — with
  /// per-quality copies on the menu, the first copy is as good as any.
  public static func rendition<R: AudioRendition>(for track: AudioTrackInfo,
                                                  in renditions: [R],
                                                  apiTracks: [AudioTrackInfo],
                                                  naming: Naming = .apiLabels) -> R? {
    guard !apiTracks.isEmpty else {
      return renditions.indices.contains(track.index) ? renditions[track.index] : nil
    }
    let paired = pairing(renditions, apiTracks: apiTracks, naming: naming)
    return paired.firstIndex(of: track).map { renditions[$0] }
  }

  /// How the dub playing right now is written down: the API row when the rendition maps
  /// back to one, otherwise read off the rendition's own name.
  public static func signature<R: AudioRendition>(forRenditionAt index: Int,
                                                  in renditions: [R],
                                                  apiTracks: [AudioTrackInfo],
                                                  naming: Naming = .apiLabels) -> AudioTrackSignature? {
    guard renditions.indices.contains(index) else { return nil }
    if let track = pairing(renditions, apiTracks: apiTracks, naming: naming)[index] {
      return track.signature
    }
    let name = renditions[index].renditionName
    let language = renditions[index].renditionLanguageCode
    return AudioTrackSignature(languageKey: language,
                               kindRank: AudioTracks.kindRank(fromLabel: kindText(in: name, language: language)),
                               studio: studio(in: name, language: language))
  }

  // MARK: - Reading a name

  /// The API row number the CDN writes into a name. Two shapes, both built from the row
  /// (captured 2026-09-28, docs/providers/kinopub/hls.md): `"01. Многоголосый. Rezka (RUS)"`
  /// when the row has a type, `"Track 3 (RUS) AC3"` when it has none.
  public static func sourceIndex(in name: String) -> Int? {
    if let untyped = name.firstMatch(of: #/^Track (\d+)\b/#) { return Int(untyped.1) }
    let digits = name.prefix(while: \.isNumber)
    guard !digits.isEmpty else { return nil }
    let rest = name.dropFirst(digits.count)
    guard let separator = rest.first, separator == "." || separator == ")" || separator == " " else { return nil }
    return Int(digits)
  }

  /// The CDN's `NN. Kind. Studio (LANG)` split into kind and studio. `nil` for a name in
  /// any other shape — our own labels are read by `AudioTracks.authorFromDisplayName`.
  private static func sourceParts(of name: String, language: String) -> (kind: String, studio: String?)? {
    guard sourceIndex(in: name) != nil else { return nil }
    // "Track N (LANG)": the row had no type and no studio, so the name has neither.
    if name.hasPrefix("Track ") { return ("", nil) }
    var body = String(name.drop(while: \.isNumber).drop(while: { ".) ".contains($0) }))
    // A trailing "(RUS)" is the rendition's language, not a studio.
    if let open = body.lastIndex(of: "("), body.hasSuffix(")") {
      let inner = body[body.index(after: open)..<body.index(before: body.endIndex)]
      if SubtitleTracks.languageKey(String(inner)) == SubtitleTracks.languageKey(language) {
        body = String(body[..<open])
      }
    }
    let parts = body.components(separatedBy: ". ")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))) }
      .filter { !$0.isEmpty }
    guard let kind = parts.first else { return nil }
    let studio = parts.dropFirst().joined(separator: ". ")
    return (kind, studio.isEmpty ? nil : studio)
  }

  private static func kindText(in name: String, language: String) -> String {
    sourceParts(of: name, language: language)?.kind ?? name
  }

  private static func studio(in name: String, language: String) -> String? {
    if let parts = sourceParts(of: name, language: language) { return parts.studio }
    return AudioTracks.authorFromDisplayName(name)
  }
}
