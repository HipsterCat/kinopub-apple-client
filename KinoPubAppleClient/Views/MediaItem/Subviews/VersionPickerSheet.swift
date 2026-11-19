//
//  VersionPickerSheet.swift
//  KinoPubAppleClient
//
//  Apple TV-style «Choose a Version» for a multi-version film (`subtype: multi`).
//  Concerts / parts keep hero version pills; this sheet is film editions only.
//

import SwiftUI
import KinoPubBackend
import KinoPubMedia
import KinoPubUI

/// One row in the version chooser: thumb + title + distinguishing subtitle.
struct VersionPickerRow: Identifiable, Hashable {
  let variant: PlaybackVariant
  let subtitle: String?

  var id: Int { variant.id }
  var title: String { variant.title }
}

/// Diffs that separate one film edition from its siblings when the names alone
/// are not enough — runtime, quality / projector format, audio, subtitles.
enum VersionPickerDiff {
  static func rows(for variants: [PlaybackVariant]) -> [VersionPickerRow] {
    variants.map { VersionPickerRow(variant: $0, subtitle: subtitle(for: $0, among: variants)) }
  }

  static func subtitle(for variant: PlaybackVariant, among variants: [PlaybackVariant]) -> String? {
#if os(tvOS)
    // The TV app's row is the edition and one line, «Audio: English» — not a
    // joined list of runtime, quality, dub kind and subtitles.
    return audioLine(for: variant)
#else
    guard variants.count > 1 else { return nil }
    var parts: [String] = []

    if durationsDiffer(in: variants),
       let runtime = RuntimeText(seconds: variant.duration).formatted(.medium) {
      parts.append(runtime)
    }

    if qualitiesDiffer(in: variants), let quality = bestQuality(for: variant) {
      parts.append(quality)
    }

    if audioFingerprintsDiffer(in: variants) {
      let audio = audioSummary(for: variant)
      parts.append(String(format: String(localized: "VersionPicker_Audio"), audio))
    }

    if subtitleFingerprintsDiffer(in: variants) {
      let subs = subtitleSummary(for: variant)
      parts.append(String(format: String(localized: "VersionPicker_Subtitles"), subs))
    }

    guard !parts.isEmpty else { return nil }
    return parts.joined(separator: " · ")
#endif
  }

#if os(tvOS)
  /// «Звук: Русский», or «Звук: Русский + 2» when the edition has more than one language.
  private static func audioLine(for variant: PlaybackVariant) -> String? {
    let groups = AudioTracks.languageGroups(for: AudioTracks.catalog(variant.video.audios))
    guard let first = groups.first else { return nil }
    let name = groups.count == 1 ? first.name : "\(first.name) + \(groups.count - 1)"
    return String(format: String(localized: "VersionPicker_Audio"), name)
  }
#endif

#if !os(tvOS)
  // MARK: - Diff gates

  private static func durationsDiffer(in variants: [PlaybackVariant]) -> Bool {
    Set(variants.map(\.duration)).count > 1
  }

  private static func qualitiesDiffer(in variants: [PlaybackVariant]) -> Bool {
    Set(variants.map { bestQuality(for: $0) ?? "" }).count > 1
  }

  private static func audioFingerprintsDiffer(in variants: [PlaybackVariant]) -> Bool {
    Set(variants.map(audioFingerprint)).count > 1
  }

  private static func subtitleFingerprintsDiffer(in variants: [PlaybackVariant]) -> Bool {
    Set(variants.map(subtitleFingerprint)).count > 1
  }

  // MARK: - Per-version facts

  private static func bestQuality(for variant: PlaybackVariant) -> String? {
    let files = variant.files
    guard !files.isEmpty else { return nil }
    let best = files.max { lhs, rhs in
      if lhs.qualityID != rhs.qualityID { return lhs.qualityID < rhs.qualityID }
      return lhs.resolution < rhs.resolution
    }
    let quality = best?.quality.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return quality.isEmpty ? nil : quality
  }

  private static func audioFingerprint(_ variant: PlaybackVariant) -> String {
    AudioTracks.catalog(variant.video.audios)
      .map { "\($0.lang)|\($0.typeId ?? -1)|\($0.typeShortTitle ?? "")" }
      .sorted()
      .joined(separator: ";")
  }

  private static func subtitleFingerprint(_ variant: PlaybackVariant) -> String {
    SubtitleTracks.catalog(variant.subtitles)
      .map { SubtitleTracks.languageKey($0.lang) }
      .sorted()
      .joined(separator: ";")
  }

  private static func audioSummary(for variant: PlaybackVariant) -> String {
    let tracks = AudioTracks.catalog(variant.video.audios)
    let labels = AudioTracks.descriptions(for: tracks)
    if labels.isEmpty { return String(localized: "VersionPicker_None") }
    if labels.count == 1 { return labels[0] }
    return "\(labels[0]) + \(labels.count - 1)"
  }

  private static func subtitleSummary(for variant: PlaybackVariant) -> String {
    let groups = SubtitleTracks.languageGroups(for: SubtitleTracks.catalog(variant.subtitles))
    if groups.isEmpty { return String(localized: "VersionPicker_None") }
    let names = groups.map(\.name)
    if names.count == 1 { return names[0] }
    return "\(names[0]) + \(names.count - 1)"
  }
#endif
}

/// «Choose a Version» — first row focused by default; Select plays that edition.
struct VersionPickerSheet: View {
  let variants: [PlaybackVariant]
  let fallbackStillURL: String?
  let linkProvider: NavigationLinkProvider

  @Environment(\.dismiss) private var dismiss
  @Environment(\.mediaNavigation) private var mediaNavigation
#if os(tvOS)
  @FocusState private var focusedID: Int?
#endif

  private var rows: [VersionPickerRow] { VersionPickerDiff.rows(for: variants) }

  var body: some View {
#if os(tvOS)
    tvSheet
#else
    NavigationStack {
      list
        .navigationTitle(Text("Choose a Version"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .topBarTrailing) {
            Button { dismiss() } label: {
              Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
            }
            .accessibilityLabel(Text("Close"))
          }
        }
#endif
    }
#endif
  }

#if os(tvOS)
  /// Compact rows over the hero: a centred title, then poster + name + one audio line.
  /// No navigation bar — that bar was the green truncated header.
  private var tvSheet: some View {
    VStack(alignment: .leading, spacing: 18) {
      Text("Choose a Version")
        .font(InfoPopupMetrics.titleFont)
        .foregroundStyle(Color.KinoPub.text)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
      VStack(spacing: 12) {
        ForEach(rows) { row in
          Button {
            play(row.variant)
          } label: {
            rowLabel(row)
          }
          .buttonStyle(.card)
          // The card style paints the focused row white and recolors the label.
          // A vertical `fixedSize` keeps that row at the poster's height: without
          // it the button accepts the card's spare height and the sheet grows a
          // blank band under the last edition.
          .fixedSize(horizontal: false, vertical: true)
          .focused($focusedID, equals: row.id)
          .accessibilityIdentifier("kinopub.versionPicker.\(row.id)")
        }
      }
    }
    .padding(InfoPopupMetrics.padding)
    .tvHeroSheet()
    .defaultFocus($focusedID, rows.first?.id, priority: .userInitiated)
    .onAppear { focusedID = rows.first?.id }
    .onExitCommand { dismiss() }
  }
#endif

#if !os(tvOS)
  @ViewBuilder
  private var list: some View {
    List {
      ForEach(rows) { row in
        Button {
          play(row.variant)
        } label: {
          rowLabel(row)
        }
        .accessibilityIdentifier("kinopub.versionPicker.\(row.id)")
      }
    }
#if os(macOS)
    .listStyle(.inset)
#endif
  }
#endif

  private func rowLabel(_ row: VersionPickerRow) -> some View {
    HStack(alignment: .center, spacing: 16) {
      thumb(for: row.variant)
        .frame(width: thumbSize.width, height: thumbSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      VersionRowText(title: row.title, subtitle: row.subtitle)
      Spacer(minLength: 0)
    }
    .padding(.vertical, 6)
    .contentShape(Rectangle())
  }

  @ViewBuilder
  private func thumb(for variant: PlaybackVariant) -> some View {
    let raw = variant.thumbnail.isEmpty ? (fallbackStillURL ?? "") : variant.thumbnail
    let url = URL(string: raw)
    CachedRemoteImage(
      url: url,
      size: thumbSize,
      contentMode: .fill,
      placeholder: {
#if os(tvOS)
        Color.clear
#else
        Color.secondary.opacity(0.25)
#endif
      },
      failure: {
#if os(tvOS)
        Color.clear
#else
        Color.secondary.opacity(0.25)
#endif
      }
    )
  }

  private var thumbSize: CGSize {
#if os(tvOS)
    CGSize(width: 136, height: 76)
#else
    CGSize(width: 96, height: 54)
#endif
  }

  /// `.buttonStyle(.card)` paints the focused row white and does not recolor a
  /// custom label, so the title would be white on white. The style still owns
  /// the platter, the lift and the parallax.
  private struct VersionRowText: View {
    let title: String
    let subtitle: String?
    @Environment(\.isFocused) private var isFocused

    var body: some View {
      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.headline)
          .foregroundStyle(isFocused ? Color.black : Color.primary)
          .multilineTextAlignment(.leading)
          .lineLimit(2)
        if let subtitle {
          Text(subtitle)
            .font(.subheadline)
            .foregroundStyle(isFocused ? Color.black.opacity(0.6) : Color.secondary)
            .multilineTextAlignment(.leading)
            .lineLimit(1)
        }
      }
    }
  }

  private func play(_ variant: PlaybackVariant) {
    dismiss()
#if os(macOS)
    PlaybackWindowState.shared.show(item: variant, mode: .media)
#else
    mediaNavigation?(linkProvider.player(for: variant))
#endif
  }
}

#if DEBUG
#Preview("Choose a Version") {
  VersionPickerSheet(
    variants: [
      PlaybackVariant(
        video: PreviewVideo.make(id: 1, title: "Театральная версия", duration: 9_600),
        mediaId: 1,
        movieTitle: "Amadeus"
      ),
      PlaybackVariant(
        video: PreviewVideo.make(id: 2, title: "Режиссерская Версия", duration: 10_800),
        mediaId: 1,
        movieTitle: "Amadeus"
      )
    ],
    fallbackStillURL: nil,
    linkProvider: AppRoutesLinkProvider()
  )
}

private enum PreviewVideo {
  static func make(id: Int, title: String, duration: Int) -> Video {
    let json = """
    {"id":\(id),"title":"\(title)","thumbnail":"","duration":\(duration),"tracks":1,"number":\(id),\
    "ac3":0,"audios":[],"watched":0,"watching":{"status":-1,"time":0},"subtitles":[],"files":[]}
    """
    return try! JSONDecoder().decode(Video.self, from: Data(json.utf8))
  }
}
#endif
