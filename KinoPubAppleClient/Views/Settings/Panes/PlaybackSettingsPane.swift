//
//  PlaybackSettingsPane.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubBackend

#if !os(tvOS)
struct PlaybackSettingsPane: View {
  @Environment(\.appContext) private var appContext

  @AppStorage(PlaybackLanguagePreferences.subtitleModeKey)
  private var subtitleModeRaw = PlaybackLanguagePreferences.subtitleMode.rawValue
  @AppStorage(SubtitlePreferences.preferNonCCKey) private var preferNonCCSubtitles = true
  @AppStorage(SubtitlePreferences.dualSubtitlesKey) private var dualSubtitlesEnabled = false
  @AppStorage(SubtitlePreferences.secondSubtitleLanguageKey) private var secondSubtitleLanguage = "ru"
  @AppStorage(StreamQuality.userDefaultsKey) private var streamQualityRaw = StreamQuality.auto.rawValue
  @AppStorage(PlaybackLanguagePreferences.minimumDubKindKey)
  private var minimumDubKind = PlaybackLanguagePreferences.noDubFloor
  @AppStorage(PlaybackLanguagePreferences.animeOriginalAudioKey)
  private var animePrefersOriginalAudio = false
  @AppStorage(PlaybackPreferences.autoPlayNextEpisodeKey) private var autoPlayNextEpisode = true
  @AppStorage(PlaybackPreferences.autoPlayNextSeasonKey) private var autoPlayNextSeason = false
  @AppStorage(SkipChipPreferences.styleKey) private var skipStyleRaw = SkipAutoStyle.apple.rawValue
  @AppStorage(SkipChipPreferences.delayKey) private var skipDelay = SkipChipPreferences.defaultDelay
  @AppStorage(SkipChipPreferences.cancelKey) private var skipCancelRaw = SkipCancelStyle.dismiss.rawValue

  /// Rebuilt when a preference changes so the summary below never disagrees with the
  /// switches above it.
  private var settings: PlaybackLanguagePreferences { .current }

  var body: some View {
    Form {
      qualitySection
      endOfPlaybackSection
      skipSection
      audioSection
      subtitleSection
      TrackMemorySections(store: appContext.trackPreferences)
    }
    .formStyle(.grouped)
  }

  private var qualitySection: some View {
    Section {
      Picker("Stream quality", selection: $streamQualityRaw) {
        ForEach(StreamQuality.allCases) { quality in
          Text(quality.title).tag(quality.rawValue)
        }
      }
      .pickerStyle(.menu)
    }
  }

  private var endOfPlaybackSection: some View {
    Section {
      Toggle("Auto-Play Next Episode", isOn: $autoPlayNextEpisode)
      Toggle("Continue to Next Season", isOn: $autoPlayNextSeason)
        .disabled(!autoPlayNextEpisode)
    } header: {
      Text("Playback")
    } footer: {
      Text("Settings_Tip_AutoPlayNextEpisode")
        + Text("\n\n")
        + Text("Settings_Tip_ContinueToNextSeason")
    }
  }

  private var skipSection: some View {
    Section {
      Picker("Settings_SkipDelay", selection: $skipDelay) {
        ForEach(SkipChipPreferences.delays, id: \.self) { seconds in
          Text(String(format: "Settings_SkipSeconds".localized, Int64(seconds))).tag(seconds)
        }
      }
      .pickerStyle(.menu)

      Picker("Settings_SkipStyle", selection: $skipStyleRaw) {
        ForEach(SkipAutoStyle.allCases) { style in
          Text(style.title).tag(style.rawValue)
        }
      }
      .pickerStyle(.menu)

      Picker("Settings_SkipCancel", selection: $skipCancelRaw) {
        ForEach(SkipCancelStyle.allCases) { style in
          Text(style.title).tag(style.rawValue)
        }
      }
      .pickerStyle(.menu)
    } header: {
      Text("Settings_Skip")
    } footer: {
      Text("Settings_SkipFooter")
    }
  }

  private var audioSection: some View {
    Section {
      NavigationLink(value: SettingsDetailRoute.languageList(.audio)) {
        LabeledContent("Prefer audio in", value: languageList(settings.resolvedAudioLanguages(system: Locale.preferredLanguages)))
      }

      Picker("Lowest acceptable dub", selection: $minimumDubKind) {
        Text("Any").tag(PlaybackLanguagePreferences.noDubFloor)
        ForEach(0...4, id: \.self) { rank in
          Text(AudioTracks.localizedKindLabel(rank: rank) ?? "").tag(rank)
        }
      }
      .pickerStyle(.menu)

      Toggle("Anime in the original", isOn: $animePrefersOriginalAudio)
    } header: {
      Text("Audio")
    } footer: {
      Text("Below the lowest acceptable dub, the original is played with subtitles instead. Languages follow the system until you change the list.")
    }
  }

  private var subtitleSection: some View {
    Section {
      Picker("Subtitle mode", selection: $subtitleModeRaw) {
        ForEach(SubtitleMode.allCases, id: \.self) { mode in
          Text(mode.title).tag(mode.rawValue)
        }
      }
      .pickerStyle(.menu)
      NavigationLink(value: SettingsDetailRoute.languageList(.subtitles)) {
        LabeledContent("Prefer subtitles in", value: languageList(settings.resolvedSubtitleLanguages(system: Locale.preferredLanguages)))
      }
      Toggle("Prefer non-CC / non-SDH", isOn: $preferNonCCSubtitles)
      // The dual-subtitle stage's rows — parked with the sidecar machinery they feed.
      if FeatureFlags.tvOSSidecarSubtitles {
        Toggle("Dual subtitles", isOn: $dualSubtitlesEnabled)
        Picker("Second subtitle language", selection: $secondSubtitleLanguage) {
          ForEach(SubtitlePreferences.secondLanguageOptions, id: \.self) { code in
            Text(LanguageNames.name(for: code)).tag(code)
          }
        }
        .pickerStyle(.menu)
        .disabled(!dualSubtitlesEnabled)
      }
    } header: {
      Text("Subtitles")
    } footer: {
      Text("Settings_Tip_SubtitleMode")
    }
  }

  private func languageList(_ codes: [String]) -> String {
    let names = codes.prefix(3).map { LanguageNames.name(for: $0) }
    return names.isEmpty ? "—" : names.joined(separator: ", ")
  }
}

/// One ordered language list — audio or subtitles. Drag to reorder, swipe or the context
/// menu to remove, *Add Language…* for the rest of kino.pub's languages.
struct PlaybackLanguageListEditor: View {
  let kind: PlaybackLanguageList.Kind
  @State private var codes: [String] = []
  @State private var isCustom = false

  var body: some View {
    Form {
      Section {
        ForEach(codes, id: \.self) { code in
          Text(LanguageNames.name(for: code))
            .contextMenu {
              Button("Move Up") { PlaybackLanguageList.move(code, in: kind, by: -1); reload() }
                .disabled(code == codes.first)
              Button("Move Down") { PlaybackLanguageList.move(code, in: kind, by: 1); reload() }
                .disabled(code == codes.last)
              Button("Remove", role: .destructive) { PlaybackLanguageList.remove(code, from: kind); reload() }
            }
        }
        .onMove { from, to in
          var list = codes
          list.move(fromOffsets: from, toOffset: to)
          PlaybackLanguageList.set(kind, list)
          reload()
        }
        .onDelete { offsets in
          PlaybackLanguageList.set(kind, codes.enumerated().filter { !offsets.contains($0.offset) }.map(\.element))
          reload()
        }
        Menu("Add Language…") {
          ForEach(PlaybackLanguageList.addable(to: kind), id: \.self) { code in
            Button(LanguageNames.name(for: code)) { PlaybackLanguageList.add(code, to: kind); reload() }
          }
        }
      } footer: {
        Text(isCustom ? "The first language on the list that a title offers wins."
                      : "Following the system's languages until you change the list.")
      }
    }
    .formStyle(.grouped)
#if os(iOS)
    .toolbar { EditButton() }
#endif
    .navigationTitle(kind == .audio ? "Prefer audio in" : "Prefer subtitles in")
    .onAppear(perform: reload)
  }

  private func reload() {
    codes = PlaybackLanguageList.languages(kind)
    isCustom = PlaybackLanguageList.isCustom(kind)
  }
}
#endif
