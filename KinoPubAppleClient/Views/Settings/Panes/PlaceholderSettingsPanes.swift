//
//  PlaceholderSettingsPanes.swift
//  KinoPubAppleClient
//
//  Demo panes: interactive System Settings–style chrome, @State only (no persistence).
//

import SwiftUI
import KinoPubUI

#if !os(tvOS)

/// Downloads settings that do something: the switches here were a demo that saved nothing
/// (Wi‑Fi only, quality, delete after watching). Quality follows Playback › Quality —
/// the HLS download asks for that rung (`HLSAssetDownloadManager`).
struct DownloadsSettingsPane: View {
  @ObservedObject private var center = AppContext.shared.downloadsCenter

  var body: some View {
    Form {
      Section {
        Toggle("Simultaneous Downloads", isOn: $center.simultaneous)
      } footer: {
        Text("Off: one download at a time, the rest wait their turn.")
      }
    }
    .formStyle(.grouped)
  }
}

struct AppearanceSettingsPane: View {
  @AppStorage(AppearancePreference.storageKey)
  private var appearanceRaw = AppearancePreference.system.rawValue
  @AppStorage(MediaCardDisplayPreferences.ratingPlacementKey)
  private var ratingPlacement = MediaCardDisplayPreferences.defaultRatingPlacement.rawValue
  @AppStorage(MediaCardDisplayPreferences.ratingSourceKey)
  private var ratingSource = MediaCardDisplayPreferences.defaultRatingSource.rawValue
  @AppStorage(MediaCardDisplayPreferences.ratingVisibilityKey)
  private var ratingVisibility = MediaCardDisplayPreferences.defaultRatingVisibility.rawValue
  @AppStorage(MediaCardDisplayPreferences.showVoteCountKey)
  private var showVoteCount = MediaCardDisplayPreferences.defaultShowVoteCount
  @AppStorage(MediaCardDisplayPreferences.showIMDbRatingKey)
  private var showIMDbRating = MediaCardDisplayPreferences.defaultShowIMDbRating
  @AppStorage(MediaCardDisplayPreferences.showKinopoiskRatingKey)
  private var showKinopoiskRating = MediaCardDisplayPreferences.defaultShowKinopoiskRating
  @AppStorage(MediaCardDisplayPreferences.sortRatingsByVotesKey)
  private var sortRatingsByVotes = MediaCardDisplayPreferences.defaultSortRatingsByVotes
  @AppStorage(MediaCardDisplayPreferences.fadedRatingIconsKey)
  private var fadedRatingIcons = MediaCardDisplayPreferences.defaultFadedRatingIcons
  @AppStorage(MediaCardDisplayPreferences.capabilityPlacementKey)
  private var capabilityPlacement = MediaCardDisplayPreferences.defaultCapabilityPlacement.rawValue
  @AppStorage(MediaCardDisplayPreferences.show4KKey)
  private var show4K = MediaCardDisplayPreferences.defaultShow4K
  @AppStorage(MediaCardDisplayPreferences.showHDRKey)
  private var showHDR = MediaCardDisplayPreferences.defaultShowHDR
  @AppStorage(MediaCardDisplayPreferences.showHDKey)
  private var showHD = MediaCardDisplayPreferences.defaultShowHD
  @AppStorage(MediaCardDisplayPreferences.show3DKey)
  private var show3D = MediaCardDisplayPreferences.defaultShow3D
  @AppStorage(MediaCardDisplayPreferences.showCCKey)
  private var showCC = MediaCardDisplayPreferences.defaultShowCC
  @AppStorage(MediaCardDisplayPreferences.editorialPlacementKey)
  private var editorialPlacement = MediaCardDisplayPreferences.defaultEditorialPlacement.rawValue
  @AppStorage(MediaCardDisplayPreferences.showOriginalTitleKey)
  private var showOriginalTitle = MediaCardDisplayPreferences.defaultShowOriginalTitle
  @AppStorage(MediaCardDisplayPreferences.showYearKey)
  private var showYear = MediaCardDisplayPreferences.defaultShowYear
  @AppStorage(MediaCardDisplayPreferences.showDurationKey)
  private var showDuration = MediaCardDisplayPreferences.defaultShowDuration
  @AppStorage(MediaCardDisplayPreferences.showGenreKey)
  private var showGenre = MediaCardDisplayPreferences.defaultShowGenre
  @AppStorage(MediaCardDisplayPreferences.showCountryKey)
  private var showCountry = MediaCardDisplayPreferences.defaultShowCountry
  @AppStorage(MediaCardDisplayPreferences.showBookmarkSymbolKey)
  private var showBookmarkSymbol = MediaCardDisplayPreferences.defaultShowBookmarkSymbol
  @AppStorage(MediaCardDisplayPreferences.progressVisibilityKey)
  private var progressVisibility = MediaCardDisplayPreferences.defaultProgressVisibility.rawValue
  @AppStorage(MediaCardDisplayPreferences.watchedStyleKey)
  private var watchedStyle = MediaCardDisplayPreferences.defaultWatchedStyle.rawValue
  /// Read so the picker refreshes when the key is written. The selection itself
  /// goes through `coverLanguage`, which keeps an unset value following the app language.
  @AppStorage(CoverArtworkPreferences.languageKey) private var coverLanguageToken = ""

  private var coverLanguage: Binding<String> {
    Binding(
      get: { CoverArtworkPreferences.language.rawValue },
      set: { raw in
        guard let language = CoverArtworkLanguage(rawValue: raw) else { return }
        CoverArtworkPreferences.set(language)
      }
    )
  }

  var body: some View {
    let _ = coverLanguageToken
    Form {
      Section {
        Picker("Theme", selection: $appearanceRaw) {
          ForEach(AppearancePreference.allCases) { preference in
            Text(preference.titleKey).tag(preference.rawValue)
          }
        }
#if os(iOS)
        .pickerStyle(.navigationLink)
#else
        .pickerStyle(.menu)
#endif
      } footer: {
        Text("Settings_Tip_Theme")
      }

      Section {
        Picker("Covers and images", selection: coverLanguage) {
          ForEach(CoverArtworkLanguage.allCases) { language in
            Text(LocalizedStringKey(language.titleKey)).tag(language.rawValue)
          }
        }
      } footer: {
        Text("Settings_Tip_Covers")
      }

      Section {
        if FeatureFlags.combinedRatingEnabled {
          Picker("Rating", selection: $ratingPlacement) {
            ForEach(MediaCardChromePlacement.allCases) { placement in
              Text(LocalizedStringKey(placement.titleKey)).tag(placement.rawValue)
            }
          }
          Picker("Rating source", selection: $ratingSource) {
            ForEach(MediaCardRatingSource.allCases) { source in
              Text(LocalizedStringKey(source.titleKey)).tag(source.rawValue)
            }
          }
          .disabled(ratingPlacement == MediaCardChromePlacement.hidden.rawValue)
        }
        Picker("When to show", selection: $ratingVisibility) {
          ForEach(MediaCardRatingVisibility.allCases) { visibility in
            Text(LocalizedStringKey(visibility.titleKey)).tag(visibility.rawValue)
          }
        }
        .disabled(FeatureFlags.combinedRatingEnabled
          && ratingPlacement == MediaCardChromePlacement.hidden.rawValue)
        Toggle("Show vote count", isOn: $showVoteCount)
          .disabled(FeatureFlags.combinedRatingEnabled
            && ratingPlacement == MediaCardChromePlacement.hidden.rawValue)
        Toggle("Show IMDb", isOn: $showIMDbRating)
          .disabled(FeatureFlags.combinedRatingEnabled
            && ratingPlacement == MediaCardChromePlacement.hidden.rawValue)
        Toggle("Show Kinopoisk", isOn: $showKinopoiskRating)
          .disabled(FeatureFlags.combinedRatingEnabled
            && ratingPlacement == MediaCardChromePlacement.hidden.rawValue)
        Toggle("Sort by vote count", isOn: $sortRatingsByVotes)
          .disabled(FeatureFlags.combinedRatingEnabled
            && ratingPlacement == MediaCardChromePlacement.hidden.rawValue)
        Toggle("Faded rating icons", isOn: $fadedRatingIcons)
          .disabled(
            (FeatureFlags.combinedRatingEnabled
              && ratingPlacement == MediaCardChromePlacement.hidden.rawValue)
            || (FeatureFlags.combinedRatingEnabled
              && ratingPlacement == MediaCardChromePlacement.onArtwork.rawValue)
          )
      } header: {
        Text("Poster score")
      } footer: {
        Text("On poster uses the coloured plaque. Under title shows IMDb / Kinopoisk logos separately. High ratings are green or gold.")
      }

      Section {
        Picker("Quality badges", selection: $capabilityPlacement) {
          ForEach(MediaCardChromePlacement.allCases) { placement in
            Text(LocalizedStringKey(placement.titleKey)).tag(placement.rawValue)
          }
        }
        Toggle("4K", isOn: $show4K)
        Toggle("HDR", isOn: $showHDR)
        Toggle("HD", isOn: $showHD)
        Toggle("3D", isOn: $show3D)
        Toggle("CC", isOn: $showCC)
        Picker("Unwatched episode count", selection: $editorialPlacement) {
          ForEach(MediaCardChromePlacement.allCases) { placement in
            Text(LocalizedStringKey(placement.titleKey)).tag(placement.rawValue)
          }
        }
        Toggle("Bookmark on artwork", isOn: $showBookmarkSymbol)
      } header: {
        Text("Badges")
      } footer: {
        Text("Unwatched episode count is for subscribed series only — on the poster or under the title like on Apple TV. Bookmark sits top-trailing, right of the quality chips.")
      }

      Section {
        Toggle("Original title", isOn: $showOriginalTitle)
        Toggle("Year", isOn: $showYear)
        Toggle("Genre", isOn: $showGenre)
        Toggle("Country", isOn: $showCountry)
      } header: {
        Text("Vertical posters")
      } footer: {
        Text("Original title never appears under landscape Continue Watching cards.")
      }

      Section {
        Toggle("Duration chip", isOn: $showDuration)
        Picker("Progress bar", selection: $progressVisibility) {
          ForEach(MediaCardProgressVisibility.allCases) { visibility in
            Text(LocalizedStringKey(visibility.titleKey)).tag(visibility.rawValue)
          }
        }
        Picker("Watched", selection: $watchedStyle) {
          ForEach(MediaCardWatchedStyle.allCases) { style in
            Text(LocalizedStringKey(style.titleKey)).tag(style.rawValue)
          }
        }
      } header: {
        Text("Landscape cards")
      } footer: {
        Text("Duration chip pins bottom-leading. New-episode counts (+N) render as a caption label, not a title chip. Watched dim/checkmark is for vertical posters.")
      }

      Section {
        NavigationLink("Sections", value: SettingsDetailRoute.sections)
      } footer: {
        Text("Choose which tabs show up.")
      }
    }
    .formStyle(.grouped)
  }
}

struct SidebarSettingsPane: View {
  @State private var showFolders = true
  @State private var compactIcons = false

  var body: some View {
    Form {
      Section {
        Toggle("Show bookmark folders", isOn: $showFolders)
        Toggle("Compact sidebar icons", isOn: $compactIcons)
        Text("Customize tabs from the sidebar’s Edit menu when available.")
          .foregroundStyle(.secondary)
          .font(.callout)
      } footer: {
        Text("Demo controls — tab customization already uses system TabViewCustomization.")
      }
    }
    .formStyle(.grouped)
  }
}

struct NotificationsSettingsPane: View {
  @Environment(\.appContext) private var appContext
  @AppStorage(AppIconBadgePreferences.enabledKey) private var badgeEnabled = false
  @AppStorage(AppIconBadgePreferences.modeKey)
  private var badgeMode = AppIconBadgePreferences.Mode.unwatchedEpisodes.rawValue

  var body: some View {
    Form {
      Section {
        Toggle("App Icon Badge", isOn: $badgeEnabled)
          .onChange(of: badgeEnabled) { _, isOn in
            if isOn {
              AppIconBadgeController.requestAuthorizationIfNeeded()
            }
            Task { await refreshAppIconBadge() }
          }
        Picker("Display the number of", selection: $badgeMode) {
          ForEach(AppIconBadgePreferences.Mode.allCases) { mode in
            Text(LocalizedStringKey(mode.titleKey)).tag(mode.rawValue)
          }
        }
        .disabled(!badgeEnabled)
        .onChange(of: badgeMode) { _, _ in
          Task { await refreshAppIconBadge() }
        }
      } footer: {
        Text("Home Screen icon only. The Watchlist tab keeps its own count.")
      }
    }
    .formStyle(.grouped)
  }

  private func refreshAppIconBadge() async {
    if !badgeEnabled {
      AppIconBadgeController.refreshFromPreferences()
      return
    }
    do {
      let serials = try await WatchingListCache.shared.serials(
        subscribedOnly: true,
        using: appContext.contentService
      )
      AppIconBadgeController.apply(serials: serials)
    } catch {
      AppIconBadgeController.refreshFromPreferences()
    }
  }
}

struct DetailsSettingsPane: View {
  @AppStorage(DetailsEnrichmentPreferences.metadataFetchingKey)
  private var metadataFetching = true
  @AppStorage(DetailsEnrichmentPreferences.paneKey)
  private var paneRaw = DetailsEnrichmentPreferences.Pane.items.rawValue
  @AppStorage(MediaItemDisplayPreferences.showAgeRatingBadgeKey)
  private var showAgeRatingBadge = false
  @AppStorage(DetailsEnrichmentPreferences.hideDescriptionsKey)
  private var hideDescriptions = false
  @AppStorage(DetailsEnrichmentPreferences.hideTitlesKey)
  private var hideTitles = false
  @AppStorage(DetailsEnrichmentPreferences.blurPreviewsKey)
  private var blurPreviews = false

  private var pane: Binding<DetailsEnrichmentPreferences.Pane> {
    Binding(
      get: { DetailsEnrichmentPreferences.Pane(rawValue: paneRaw) ?? .items },
      set: { paneRaw = $0.rawValue }
    )
  }

  var body: some View {
    Form {
      Section {
        Toggle("Metadata Fetching", isOn: $metadataFetching)
      } footer: {
        Text("Off stops outside metadata on title pages. kino.pub data still loads.")
      }

      Section {
        Picker("Details", selection: pane) {
          ForEach(DetailsEnrichmentPreferences.Pane.allCases) { value in
            Text(LocalizedStringKey(value.titleKey)).tag(value)
          }
        }
        .pickerStyle(.segmented)
        .disabled(!metadataFetching)
        .labelsHidden()
      }

      if pane.wrappedValue == .items {
        Section {
          ForEach(DetailsEnrichmentItem.imageItems) { item in
            NavigationLink(value: SettingsDetailRoute.detailsItem(item)) {
              Label(LocalizedStringKey(item.titleKey), systemImage: item.systemImage)
            }
            .disabled(!metadataFetching)
          }
        } header: {
          Text("Images")
        }

        Section {
          ForEach(DetailsEnrichmentItem.infoItems) { item in
            NavigationLink(value: SettingsDetailRoute.detailsItem(item)) {
              Label(LocalizedStringKey(item.titleKey), systemImage: item.systemImage)
            }
            .disabled(!metadataFetching)
          }
        } header: {
          Text("Info")
        }
      } else {
        Section {
          ForEach(DetailsEnrichmentSource.rows) { integration in
            NavigationLink(value: SettingsDetailRoute.integration(integration)) {
              HStack(spacing: 10) {
                IntegrationIconView(integration: integration)
                Text(verbatim: integration.name)
              }
            }
            .disabled(!metadataFetching)
          }
        } footer: {
          Text("Opens the same pages as Integrations — keys, proxy, data and playback.")
        }
      }

      Section {
        Toggle("Age rating badge", isOn: $showAgeRatingBadge)
          .disabled(!metadataFetching)
      } header: {
        Text("Display")
      } footer: {
        Text("Certification chip beside the year on the hero. Always listed in Facts.")
      }

      Section {
        Toggle("Hide descriptions", isOn: $hideDescriptions)
        Toggle("Hide titles", isOn: $hideTitles)
        Toggle("Blur previews", isOn: $blurPreviews)
      } header: {
        Text("Spoilers")
      } footer: {
        Text("Facts, stills and titles that can spoil — including when rewatching.")
      }
    }
    .formStyle(.grouped)
  }
}

struct BackupsSettingsPane: View {
  @State private var iCloudSync = false
  @State private var includeWatchHistory = true
  @State private var includeSettings = true

  var body: some View {
    Form {
      Section {
        Toggle("iCloud Sync", isOn: $iCloudSync)
        Toggle("Include watch history", isOn: $includeWatchHistory)
          .disabled(!iCloudSync)
        Toggle("Include settings", isOn: $includeSettings)
          .disabled(!iCloudSync)
      } footer: {
        Text("Aspirational — after local DB foundation. Demo controls are not saved.")
      }
    }
    .formStyle(.grouped)
  }
}

struct NetworkSettingsPane: View {
  @State private var useProxy = false
  @State private var preferIPv6 = false

  var body: some View {
    Form {
      Section {
        LabeledContent("Status", value: "Online")
        Toggle("Use proxy", isOn: $useProxy)
        Toggle("Prefer IPv6", isOn: $preferIPv6)
        Button("Run Speed Test") {}
          .disabled(true)
      } footer: {
        Text("Demo controls — not saved yet.")
      }
    }
    .formStyle(.grouped)
  }
}

#endif
