//
//  TVSettingsCatalog.swift
//  KinoPubAppleClient
//
//  tvOS Settings content as TVSettingKit pages (`TVSettingKit.swift`): the categories,
//  their rows, and the bindings from each row to where the value already lives —
//  `@AppStorage` keys, `DeviceSettingsPaneModel`, `KinopoiskKeySettingsModel`,
//  `FeatureFlag`. Nothing here is stored twice.
//
//  Every row is a focus stop, read-only ones included: TVSettingKit makes them so, and
//  the left column shows the focused row's description.
//

#if os(tvOS)
import SwiftUI
import UIKit
import KinoPubBackend
import KinoPubKit
import KinoPubUI

@MainActor
final class TVSettingsCatalog {
  let host = TSKSplitHost()

  private let model: ProfileModel
  private let device = DeviceSettingsPaneModel()
  private let kinopoisk: KinopoiskKeySettingsModel
  private let deviceService: DeviceService
  private let errorHandler: ErrorHandler
  private let onLogout: () -> Void
  private let onLanguageChange: (String) -> Void
  /// Puts a SwiftUI page in a hosting controller with the environment it needs: hosted
  /// controllers do not inherit SwiftUI's.
  private let host_: (AnyView) -> UIViewController

  // MARK: - Banner Lab State
  private var bannerPreset: BannerLabPreset = .currentDefault
  private var bannerFocusState: BannerLabFocusState = .unfocused
  private var bannerSampleID: Int = TVPageBannerSamples.primaryID
  private var bannerHasLogo: Bool = true
  private var bannerHasBackdrop: Bool = true
  private var bannerHasPoster: Bool = false
  private var bannerLogoPlacement: TVPageBannerLogoPlacement = TVPageBannerChrome.current.logoPlacement
  private var bannerAlignment: TVPageBannerContentAlignment = TVPageBannerChrome.current.alignment
  private var bannerVerticalAlignment: TVPageBannerVerticalAlignment = TVPageBannerChrome.current.verticalAlignment
  private var bannerShowsPoster: Bool = TVPageBannerChrome.current.showsPoster
  private var bannerScrimChoice: BannerLabScrim = .defaultBottom
  private var bannerBlend: TVPageBannerBlend = TVPageBannerChrome.current.blend
  private var bannerVibrance: Double = Double(TVPageBannerChrome.current.textVibrance)
  private var bannerVibranceEnabled: Bool = TVPageBannerChrome.current.vibranceEnabled
  private var bannerShowsVotes: Bool = TVPageBannerChrome.current.showsRatingVotes
  private var bannerRatingLimit: Int = TVPageBannerChrome.current.ratingMaxCount
  private var bannerFilterNoise: Bool = TVPageBannerChrome.current.filterLowTurnout
  private var bannerFilterDominant: Bool = TVPageBannerChrome.current.filterDominantScore
  private var bannerShowsAggregate: Bool = TVPageBannerChrome.current.showsAggregateScore
  private var bannerAggregateOnly: Bool = TVPageBannerChrome.current.aggregateOnly
  private var bannerDedupAggregate: Bool = TVPageBannerChrome.current.deduplicateSingleSourceAggregate
  private var bannerCustomScores: MediaScores? = nil
  private weak var activeBannerHostView: TVPageBannerPreviewHost?
  private var cachedBannerPreviewController: UIViewController?

  init(model: ProfileModel,
       kinopoiskKeyProvider: KinopoiskKeyProvider,
       deviceService: DeviceService,
       errorHandler: ErrorHandler,
       onLogout: @escaping () -> Void,
       onLanguageChange: @escaping (String) -> Void,
       hosting: @escaping (AnyView) -> UIViewController) {
    self.model = model
    self.kinopoisk = KinopoiskKeySettingsModel(keyProvider: kinopoiskKeyProvider)
    self.deviceService = deviceService
    self.errorHandler = errorHandler
    self.onLogout = onLogout
    self.onLanguageChange = onLanguageChange
    self.host_ = hosting
    bindValues()
  }

  // MARK: - Root

  var rootPage: TSKPage {
    TSKPage(
      title: nil,
      idlePreview: { [unowned self] in self.appPreview() },
      sections: { [unowned self] in
        [TSKSection(rows: Category.allCases.map { category in
          TSKRow(title: category.title,
                 description: category.tip,
                 kind: .action(pushes: true) { [unowned self] in self.open(category) },
                 previewSymbol: category.symbol)
        })]
      }
    )
  }

  func open(_ category: Category) {
    if category.usesDeviceSettings {
      Task { [weak self] in
        guard let self, self.device.settings.streamingTypeOptions.isEmpty, !self.device.isLoading else { return }
        await self.device.load(deviceService: self.deviceService, errorHandler: self.errorHandler)
        self.host.reloadPages()
      }
    }
    host.push(page(for: category))
  }

  private func page(for category: Category) -> TSKPage {
    switch category {
    case .about:
      return TSKPage(
        title: category.title,
        customPreview: { [unowned self] _ in self.appPreview() },
        idlePreview: { [unowned self] in self.appPreview() },
        sections: { [unowned self] in self.aboutSections() }
      )
    default:
      return TSKPage(title: category.title, previewSymbol: category.symbol) { [unowned self] in
        self.sections(for: category)
      }
    }
  }

  private func sections(for category: Category) -> [TSKSection] {
    switch category {
    case .account: accountSections()
    case .server: serverSections()
    case .device: deviceSections()
    case .videoAudio: videoAudioSections()
    case .tabs: tabsSections()
    case .appearance: appearanceSections()
    case .dataSources: dataSourcesSections()
    case .advanced: advancedSections()
    case .experiments: experimentsSections()
    case .developer: developerSections()
    case .about: aboutSections()
    }
  }

  // MARK: - Pages

  private func accountSections() -> [TSKSection] {
    [TSKSection(rows: [
      info("User Name", model.userData.username),
      info("User Subscription", "\(model.userData.subscription.days) \("days".localized)"),
      info("Registration Date", model.userData.registrationDateFormatted),
      TSKRow(title: "Logout".localized,
             description: "Settings_Tip_Logout".localized,
             kind: .action(pushes: false) { [unowned self] in self.onLogout() }),
    ])]
  }

  private func serverSections() -> [TSKSection] {
    if let waiting = deviceReadySections() { return waiting }
    return [TSKSection(rows: [
        TSKRow(title: "Stream type".localized,
               description: serverTip,
               kind: .choice(key: "deviceStreamType",
                             values: device.settings.streamingTypeOptions.map { NSNumber(value: $0.id) },
                             label: { [unowned self] in self.optionLabel($0, self.device.settings.streamingTypeOptions) })),
        TSKRow(title: "Server location".localized,
               description: serverTip,
               kind: .choice(key: "deviceServerLocation",
                             values: device.settings.serverLocationOptions.map { NSNumber(value: $0.id) },
                             label: { [unowned self] in self.optionLabel($0, self.device.settings.serverLocationOptions) })),
    ])]
  }

  private var serverTip: String {
    "Settings_Tip_Server".localized + "\n\n" + saveHint
  }

  private func deviceSections() -> [TSKSection] {
    if let waiting = deviceReadySections() { return waiting }
    var rows: [TSKRow] = []
    if !device.deviceTitle.isEmpty {
      rows.append(info("This device", device.deviceTitle))
    }
    let tip = "Settings_Tip_DeviceCapabilities".localized + "\n\n" + saveHint
    rows += [
      TSKRow(title: "4K", description: tip, kind: .toggle(key: "device4K")),
      TSKRow(title: "HEVC", description: tip, kind: .toggle(key: "deviceHEVC")),
      TSKRow(title: "HDR", description: tip, kind: .toggle(key: "deviceHDR")),
      TSKRow(title: "Mixed playlists".localized, description: tip, kind: .toggle(key: "deviceMixedPlaylist")),
    ]
    return [TSKSection(rows: rows)]
  }

  /// Nil once kino.pub has answered; until then a loading row, or Retry after a failure.
  private func deviceReadySections() -> [TSKSection]? {
    guard device.settings.streamingTypeOptions.isEmpty else { return nil }
    if device.isLoading {
      return [TSKSection(rows: [info("Loading…", "")])]
    }
    return [TSKSection(rows: [
      TSKRow(title: "Retry".localized, kind: .action(pushes: false) { [weak self] in
        guard let self else { return }
        Task {
          await self.device.load(deviceService: self.deviceService, errorHandler: self.errorHandler)
          self.host.reloadPages()
        }
      }),
    ])]
  }

  private var saveHint: String {
    (device.didSave ? "Saved. Changes take effect within a minute." : "Changes take effect within a minute.").localized
  }

  private func videoAudioSections() -> [TSKSection] {
    var subtitles: [TSKRow] = [
      TSKRow(title: "Default English subtitles".localized,
             description: "Settings_Tip_EnglishSubtitles".localized,
             kind: .toggle(key: "subtitlesEnglish")),
      TSKRow(title: "Prefer non-CC / non-SDH".localized,
             description: "Settings_Tip_PreferNonCC".localized,
             kind: .toggle(key: "subtitlesNonCC"),
             isEnabled: SubtitlePreferences.preferEnglishSubtitles),
    ]
    // The dual-subtitle stage's rows — parked with the sidecar machinery they feed.
    if FeatureFlags.tvOSSidecarSubtitles {
      subtitles += [
        TSKRow(title: "Dual subtitles".localized,
               description: "Settings_Tip_DualSubtitles".localized,
               kind: .toggle(key: "subtitlesDual")),
        TSKRow(title: "Second subtitle language".localized,
               description: "Settings_Tip_SecondLanguage".localized,
               kind: .choice(key: "subtitlesSecondLanguage",
                             values: SubtitlePreferences.secondLanguageOptions.map { $0 as NSString },
                             label: { ($0 as? String).map(LanguageNames.name(for:)) }),
               isEnabled: SubtitlePreferences.dualSubtitlesEnabled),
      ]
    }
    return [
      TSKSection(rows: [
        TSKRow(title: "Stream quality".localized,
               description: "Settings_Tip_StreamQuality".localized,
               kind: .choice(key: "streamQuality",
                             values: StreamQuality.allCases.map { $0.rawValue as NSString },
                             label: { ($0 as? String).flatMap(StreamQuality.init(rawValue:))?.title })),
        TSKRow(title: "Remembered tracks".localized,
               description: "Settings_Tip_RememberedTracks".localized,
               kind: .action(pushes: true) { [unowned self] in self.host.push(self.rememberedTracksPage()) }),
      ]),
      TSKSection(title: "Playback".localized, rows: [
        TSKRow(title: "Auto-Play Next Episode".localized,
               description: "Settings_Tip_AutoPlayNextEpisode".localized,
               kind: .toggle(key: "autoPlayNextEpisode")),
        TSKRow(title: "Continue to Next Season".localized,
               description: "Settings_Tip_ContinueToNextSeason".localized,
               kind: .toggle(key: "autoPlayNextSeason"),
               isEnabled: PlaybackPreferences.autoPlayNextEpisode),
      ]),
      TSKSection(title: "Subtitles".localized, rows: subtitles),
    ]
  }

  private func tabsSections() -> [TSKSection] {
    let store = SectionVisibilityStore.shared
    let tabs = store.orderedBrowseTabs
    let tabRows: [TSKRow] = tabs.enumerated().map { idx, spec in
      let isVisible = store.isTabVisible(spec.tab)
      let status = isVisible ? "Вкл" : "Выкл"
      return TSKRow(
        title: "\(idx + 1). \(spec.localizedTitle) — \(status)",
        description: "Вкладка «\(spec.localizedTitle)». Позиция: #\(idx + 1) из \(tabs.count). Нажмите Select, чтобы включить/выключить вкладку или изменить её порядок в верхнем меню.",
        kind: .action(pushes: true) { [unowned self] in
          self.host.push(self.tabDetailPage(specID: spec.id))
        },
        previewSymbol: spec.symbol
      )
    }

    let filterRows: [TSKRow] = [
      TSKRow(
        title: "Без концертов на Главной: \(store.excludeConcertsOnHome ? "Вкл" : "Выкл")",
        description: "Исключает концерты из общих подборок и рейтинговых секций на Главной (Watch Now). Нажмите Select для переключения.",
        kind: .action(pushes: false) { [unowned self] in
          SectionVisibilityStore.shared.excludeConcertsOnHome.toggle()
          self.host.reloadPages()
        },
        previewSymbol: "music.mic.slash"
      ),
    ]

    let sections = store.orderedHomeSections
    let sectionRows: [TSKRow] = sections.enumerated().map { idx, section in
      let isVisible = store.isHomeSectionVisible(section.id)
      let status = isVisible ? "Вкл" : "Выкл"
      return TSKRow(
        title: "\(idx + 1). \(section.title) — \(status)",
        description: "\(section.subtitle)\nСортировка: \(section.sortingDescription)\nНажмите Select, чтобы включить/выключить секцию или переместить её выше/ниже.",
        kind: .action(pushes: true) { [unowned self] in
          self.host.push(self.homeSectionDetailPage(sectionID: section.id))
        },
        previewSymbol: "rectangle.grid.1x2"
      )
    }

    let movieSections = store.orderedMovieSections
    let movieSectionRows: [TSKRow] = movieSections.enumerated().map { idx, section in
      let isVisible = store.isMovieSectionVisible(section.id)
      let status = isVisible ? "Вкл" : "Выкл"
      return TSKRow(
        title: "\(idx + 1). \(section.title) — \(status)",
        description: "\(section.subtitle)\nНажмите Select, чтобы включить/выключить секцию на вкладке Фильмы или изменить её порядок.",
        kind: .action(pushes: true) { [unowned self] in
          self.host.push(self.movieSectionDetailPage(sectionID: section.id))
        },
        previewSymbol: "movieclapper"
      )
    }

    let seriesSections = store.orderedSeriesSections
    let seriesSectionRows: [TSKRow] = seriesSections.enumerated().map { idx, section in
      let isVisible = store.isSeriesSectionVisible(section.id)
      let status = isVisible ? "Вкл" : "Выкл"
      return TSKRow(
        title: "\(idx + 1). \(section.title) — \(status)",
        description: "\(section.subtitle)\nНажмите Select, чтобы включить/выключить секцию на вкладке Сериалы или изменить её порядок.",
        kind: .action(pushes: true) { [unowned self] in
          self.host.push(self.seriesSectionDetailPage(sectionID: section.id))
        },
        previewSymbol: "rectangle.stack"
      )
    }

    let resetRows: [TSKRow] = [
      TSKRow(
        title: "Сбросить вкладки и секции по умолчанию",
        description: "Восстанавливает стандартный набор и порядок вкладок верхнего меню и секций Главной, Фильмов и Сериалов.",
        kind: .action(pushes: false) { [unowned self] in
          SectionVisibilityStore.shared.resetToDefaults()
          self.host.reloadPages()
        },
        previewSymbol: "arrow.counterclockwise"
      ),
    ]

    return [
      TSKSection(title: "Вкладки верхнего меню (Табы)", rows: tabRows),
      TSKSection(title: "Фильтры Главной", rows: filterRows),
      TSKSection(title: "Секции Главной (Watch Now)", rows: sectionRows),
      TSKSection(title: "Секции Фильмов (Movies)", rows: movieSectionRows),
      TSKSection(title: "Секции Сериалов и Шоу (Series)", rows: seriesSectionRows),
      TSKSection(title: "Сброс", rows: resetRows),
    ]
  }

  private func tabDetailPage(specID: String) -> TSKPage {
    let spec = SectionVisibilityStore.allBrowseTabs.first { $0.id == specID }
      ?? SectionVisibilityStore.allBrowseTabs[0]
    return TSKPage(title: spec.localizedTitle, previewSymbol: spec.symbol) { [unowned self] in
      let store = SectionVisibilityStore.shared
      let ordered = store.orderedBrowseTabs
      let idx = ordered.firstIndex(where: { $0.id == specID }) ?? 0
      let isVisible = store.isTabVisible(spec.tab)
      let canToggle = spec.canHide && (!isVisible || store.visibleBrowseTabs.count > 1)

      let actionRows: [TSKRow] = [
        TSKRow(
          title: "Показывать в меню: \(isVisible ? "Вкл" : "Выкл")",
          description: spec.canHide
            ? "Включает или скрывает вкладку «\(spec.localizedTitle)» в главном меню навигации."
            : "Вкладка «\(spec.localizedTitle)» является основной и всегда отображается в меню.",
          kind: .action(pushes: false) { [unowned self] in
            SectionVisibilityStore.shared.toggleTabVisibility(id: specID)
            self.host.reloadPages()
          },
          isEnabled: canToggle
        ),
        TSKRow(
          title: "Поднять выше (↑)",
          description: "Переместить вкладку ближе к началу меню (текущая позиция: #\(idx + 1) из \(ordered.count)).",
          kind: .action(pushes: false) { [unowned self] in
            SectionVisibilityStore.shared.moveTabUp(id: specID)
            self.host.reloadPages()
          },
          isEnabled: idx > 0
        ),
        TSKRow(
          title: "Опустить ниже (↓)",
          description: "Переместить вкладку ближе к концу меню (текущая позиция: #\(idx + 1) из \(ordered.count)).",
          kind: .action(pushes: false) { [unowned self] in
            SectionVisibilityStore.shared.moveTabDown(id: specID)
            self.host.reloadPages()
          },
          isEnabled: idx < ordered.count - 1
        ),
      ]

      let positionRows: [TSKRow] = ordered.indices.map { targetIdx in
        let isCurrent = (targetIdx == idx)
        return TSKRow(
          title: isCurrent ? "Позиция #\(targetIdx + 1) (текущая)" : "Переместить на позицию #\(targetIdx + 1)",
          description: "Поставить вкладку «\(spec.localizedTitle)» на место #\(targetIdx + 1) в верхнем меню.",
          kind: .action(pushes: false) { [unowned self] in
            SectionVisibilityStore.shared.moveTab(id: specID, toPosition: targetIdx + 1)
            self.host.reloadPages()
          },
          isEnabled: !isCurrent
        )
      }

      return [
        TSKSection(title: "Управление вкладкой", rows: actionRows),
        TSKSection(title: "Быстрый выбор позиции", rows: positionRows),
      ]
    }
  }

  private func homeSectionDetailPage(sectionID: String) -> TSKPage {
    let section = SectionVisibilityStore.allHomeSections.first { $0.id == sectionID }
      ?? SectionVisibilityStore.allHomeSections[0]
    return TSKPage(title: section.title, previewSymbol: "rectangle.grid.1x2") { [unowned self] in
      let store = SectionVisibilityStore.shared
      let ordered = store.orderedHomeSections
      let idx = ordered.firstIndex(where: { $0.id == sectionID }) ?? 0
      let isVisible = store.isHomeSectionVisible(sectionID)

      let actionRows: [TSKRow] = [
        TSKRow(
          title: "Показывать на Главной: \(isVisible ? "Вкл" : "Выкл")",
          description: "\(section.subtitle)\nСортировка: \(section.sortingDescription)",
          kind: .action(pushes: false) { [unowned self] in
            SectionVisibilityStore.shared.toggleHomeSectionVisibility(id: sectionID)
            self.host.reloadPages()
          }
        ),
        TSKRow(
          title: "Поднять выше (↑)",
          description: "Переместить секцию выше на Главной странице (текущая позиция: #\(idx + 1) из \(ordered.count)).",
          kind: .action(pushes: false) { [unowned self] in
            SectionVisibilityStore.shared.moveHomeSectionUp(id: sectionID)
            self.host.reloadPages()
          },
          isEnabled: idx > 0
        ),
        TSKRow(
          title: "Опустить ниже (↓)",
          description: "Переместить секцию ниже на Главной странице (текущая позиция: #\(idx + 1) из \(ordered.count)).",
          kind: .action(pushes: false) { [unowned self] in
            SectionVisibilityStore.shared.moveHomeSectionDown(id: sectionID)
            self.host.reloadPages()
          },
          isEnabled: idx < ordered.count - 1
        ),
      ]

      let positionRows: [TSKRow] = ordered.indices.map { targetIdx in
        let isCurrent = (targetIdx == idx)
        return TSKRow(
          title: isCurrent ? "Позиция #\(targetIdx + 1) (текущая)" : "Переместить на позицию #\(targetIdx + 1)",
          description: "Поставить секцию «\(section.title)» на место #\(targetIdx + 1) на Главной.",
          kind: .action(pushes: false) { [unowned self] in
            SectionVisibilityStore.shared.moveHomeSection(id: sectionID, toPosition: targetIdx + 1)
            self.host.reloadPages()
          },
          isEnabled: !isCurrent
        )
      }

      return [
        TSKSection(title: "Управление секцией", rows: actionRows),
        TSKSection(title: "Быстрый выбор позиции", rows: positionRows),
      ]
    }
  }

  private func movieSectionDetailPage(sectionID: String) -> TSKPage {
    let section = SectionVisibilityStore.allMovieSections.first { $0.id == sectionID }
      ?? SectionVisibilityStore.allMovieSections[0]
    return TSKPage(title: section.title, previewSymbol: "movieclapper") { [unowned self] in
      let store = SectionVisibilityStore.shared
      let ordered = store.orderedMovieSections
      let idx = ordered.firstIndex(where: { $0.id == sectionID }) ?? 0
      let isVisible = store.isMovieSectionVisible(sectionID)

      let actionRows: [TSKRow] = [
        TSKRow(
          title: "Показывать в Фильмах: \(isVisible ? "Вкл" : "Выкл")",
          description: section.subtitle,
          kind: .action(pushes: false) { [unowned self] in
            SectionVisibilityStore.shared.toggleMovieSectionVisibility(id: sectionID)
            self.host.reloadPages()
          }
        ),
        TSKRow(
          title: "Поднять выше (↑)",
          description: "Переместить секцию выше на вкладке Фильмы (текущая позиция: #\(idx + 1) из \(ordered.count)).",
          kind: .action(pushes: false) { [unowned self] in
            SectionVisibilityStore.shared.moveMovieSectionUp(id: sectionID)
            self.host.reloadPages()
          },
          isEnabled: idx > 0
        ),
        TSKRow(
          title: "Опустить ниже (↓)",
          description: "Переместить секцию ниже на вкладке Фильмы (текущая позиция: #\(idx + 1) из \(ordered.count)).",
          kind: .action(pushes: false) { [unowned self] in
            SectionVisibilityStore.shared.moveMovieSectionDown(id: sectionID)
            self.host.reloadPages()
          },
          isEnabled: idx < ordered.count - 1
        ),
      ]

      let positionRows: [TSKRow] = ordered.indices.map { targetIdx in
        let isCurrent = (targetIdx == idx)
        return TSKRow(
          title: isCurrent ? "Позиция #\(targetIdx + 1) (текущая)" : "Переместить на позицию #\(targetIdx + 1)",
          description: "Поставить секцию «\(section.title)» на место #\(targetIdx + 1) в Фильмах.",
          kind: .action(pushes: false) { [unowned self] in
            SectionVisibilityStore.shared.moveMovieSection(id: sectionID, toPosition: targetIdx + 1)
            self.host.reloadPages()
          },
          isEnabled: !isCurrent
        )
      }

      return [
        TSKSection(title: "Управление секцией", rows: actionRows),
        TSKSection(title: "Быстрый выбор позиции", rows: positionRows),
      ]
    }
  }

  private func seriesSectionDetailPage(sectionID: String) -> TSKPage {
    let section = SectionVisibilityStore.allSeriesSections.first { $0.id == sectionID }
      ?? SectionVisibilityStore.allSeriesSections[0]
    return TSKPage(title: section.title, previewSymbol: "rectangle.stack") { [unowned self] in
      let store = SectionVisibilityStore.shared
      let ordered = store.orderedSeriesSections
      let idx = ordered.firstIndex(where: { $0.id == sectionID }) ?? 0
      let isVisible = store.isSeriesSectionVisible(sectionID)

      let actionRows: [TSKRow] = [
        TSKRow(
          title: "Показывать в Сериалах: \(isVisible ? "Вкл" : "Выкл")",
          description: section.subtitle,
          kind: .action(pushes: false) { [unowned self] in
            SectionVisibilityStore.shared.toggleSeriesSectionVisibility(id: sectionID)
            self.host.reloadPages()
          }
        ),
        TSKRow(
          title: "Поднять выше (↑)",
          description: "Переместить секцию выше на вкладке Сериалы (текущая позиция: #\(idx + 1) из \(ordered.count)).",
          kind: .action(pushes: false) { [unowned self] in
            SectionVisibilityStore.shared.moveSeriesSectionUp(id: sectionID)
            self.host.reloadPages()
          },
          isEnabled: idx > 0
        ),
        TSKRow(
          title: "Опустить ниже (↓)",
          description: "Переместить секцию ниже на вкладке Сериалы (текущая позиция: #\(idx + 1) из \(ordered.count)).",
          kind: .action(pushes: false) { [unowned self] in
            SectionVisibilityStore.shared.moveSeriesSectionDown(id: sectionID)
            self.host.reloadPages()
          },
          isEnabled: idx < ordered.count - 1
        ),
      ]

      let positionRows: [TSKRow] = ordered.indices.map { targetIdx in
        let isCurrent = (targetIdx == idx)
        return TSKRow(
          title: isCurrent ? "Позиция #\(targetIdx + 1) (текущая)" : "Переместить на позицию #\(targetIdx + 1)",
          description: "Поставить секцию «\(section.title)» на место #\(targetIdx + 1) в Сериалах.",
          kind: .action(pushes: false) { [unowned self] in
            SectionVisibilityStore.shared.moveSeriesSection(id: sectionID, toPosition: targetIdx + 1)
            self.host.reloadPages()
          },
          isEnabled: !isCurrent
        )
      }

      return [
        TSKSection(title: "Управление секцией", rows: actionRows),
        TSKSection(title: "Быстрый выбор позиции", rows: positionRows),
      ]
    }
  }

  private func appearanceSections() -> [TSKSection] {
    [TSKSection(rows: [
      TSKRow(title: "Language".localized,
             description: "Settings_Tip_Language".localized,
             kind: .choice(key: "language",
                           values: model.availableLanguages.keys.sorted().map { $0 as NSString },
                           label: { [unowned self] in ($0 as? String).map { self.model.availableLanguages[$0] ?? $0 } })),
      info("Theme", "Dark".localized),
      TSKRow(title: "Вкладки и Главная",
             description: "Включение, отключение и сортировка вкладок верхнего меню и секций Главной страницы.",
             kind: .action(pushes: true) { [unowned self] in self.open(.tabs) },
             previewSymbol: "square.grid.2x2"),
    ])]
  }

  private func dataSourcesSections() -> [TSKSection] {
    var sources = [
      // The TMDB attribution the API terms ask for rides on the TMDB row.
      TSKRow(title: "TMDB",
             description: "Settings_Tip_DataSources".localized + "\n\n"
               + "This product uses the TMDB API but is not endorsed or certified by TMDB.".localized,
             kind: .info(value: "themoviedb.org")),
      TSKRow(title: "Kinopoisk",
             description: "Facts, stills, reviews and some cast details come from a third-party Kinopoisk data proxy (kpapp.link), not an official Kinopoisk product.".localized,
             kind: .info(value: "kpapp.link")),
    ]
    if KinopoiskKeyValidation.isValidated {
      sources.append(TSKRow(
        title: "Kinopoisk Unofficial API".localized,
        description: "Awards and richer metadata also use your own Kinopoisk Unofficial API key (kinopoiskapiunofficial.tech).".localized,
        kind: .info(value: "kinopoiskapiunofficial.tech")
      ))
    }
    return [
      TSKSection(title: "Kinopoisk", rows: [
        TSKRow(title: "API key".localized,
               description: kinopoisk.statusText.localized,
               kind: .text(key: "kinopoiskKey")),
      ]),
      TSKSection(title: "Sources".localized, rows: sources),
    ]
  }

  private func advancedSections() -> [TSKSection] {
    [TSKSection(title: "Diagnostics".localized, rows: [
      TSKRow(title: "Network log".localized,
             description: "Settings_Tip_NetworkLog".localized,
             kind: .action(pushes: true) { [unowned self] in self.presentPulseConsole() }),
      TSKRow(title: "Stream to Pulse on Mac".localized,
             description: "Settings_Tip_StreamToPulse".localized,
             kind: .toggle(key: "streamToPulse")),
      TSKRow(title: "Show in-flight requests".localized,
             description: "Settings_Tip_ActivityOverlay".localized,
             kind: .toggle(key: "activityOverlay")),
    ])]
  }

  private func experimentsSections() -> [TSKSection] {
    let flags = FeatureFlag.allCases.filter(\.isRelevantHere)
    func rows(appliesAtLaunch: Bool) -> [TSKRow] {
      flags.filter { $0.appliesAtLaunch == appliesAtLaunch }.map { flag in
        let shipped = flag.defaultValue ? "on" : "off"
        return TSKRow(title: flag.title,
                      description: flag.summary + (flag.isOverridden ? " Ships \(shipped)." : ""),
                      kind: .toggle(key: Self.flagKey(flag)))
      }
    }
    var defaults: [TSKRow] = []
    if flags.contains(where: \.isPendingRelaunch) {
      defaults.append(TSKRow(title: "Quit to apply".localized,
                             description: "Launch-time switches take hold on the next launch. This quits the app.",
                             kind: .action(pushes: false) { FeatureFlag.quitToApply() }))
    }
    defaults.append(TSKRow(title: "Reset to defaults".localized,
                           description: "Stored on this device only. A build ships with the defaults.",
                           kind: .action(pushes: false) { [unowned self] in
                             FeatureFlag.resetAll()
                             self.host.store.refreshAll()
                             self.host.reloadPages()
                           }))
    return [
      TSKSection(title: "Applies on next launch".localized, rows: rows(appliesAtLaunch: true)),
      TSKSection(title: "Applies when next opened".localized, rows: rows(appliesAtLaunch: false)),
      TSKSection(title: "Defaults".localized, rows: defaults),
    ]
  }

  private func developerSections() -> [TSKSection] {
    [TSKSection(rows: Lab.allCases.map { lab in
      TSKRow(title: lab.title,
             description: lab.description,
             kind: .action(pushes: true) { [unowned self] in
               if lab == .bannerLab {
                 self.cachedBannerPreviewController = nil
                 self.host.push(self.bannerLabPage())
               } else {
                 self.present(lab.page)
               }
             })
    })]
  }

  // MARK: - Banner Lab

  private var currentBannerChrome: TVPageBannerChrome {
    var draft = TVPageBannerChrome.current
    draft.logoPlacement = bannerLogoPlacement
    draft.alignment = bannerAlignment
    draft.verticalAlignment = bannerVerticalAlignment
    draft.showsPoster = bannerShowsPoster
    draft.blend = bannerBlend
    draft.textVibrance = CGFloat(bannerVibrance)
    draft.vibranceEnabled = bannerVibranceEnabled
    draft.isFocusedState = (bannerFocusState == .focused)
    draft.showsRatingVotes = bannerShowsVotes
    draft.ratingMaxCount = bannerRatingLimit
    draft.filterLowTurnout = bannerFilterNoise
    draft.filterDominantScore = bannerFilterDominant
    draft.showsAggregateScore = bannerShowsAggregate
    draft.aggregateOnly = bannerAggregateOnly
    draft.deduplicateSingleSourceAggregate = bannerDedupAggregate
    if let scrim = bannerScrimChoice.value {
      draft.scrim = scrim
    }
    return draft
  }

  private var currentBannerFeature: TVPageFeature {
    TVPageBannerSamples.makeFeature(
      id: bannerSampleID,
      title: bannerSampleID == TVPageBannerSamples.primaryID ? "Паук-Нуар" : "Тайтл #\(bannerSampleID)",
      overview: bannerSampleID == TVPageBannerSamples.primaryID
        ? TVPageBannerSamples.primaryOverview
        : "Арт и постер загружаются напрямую из каталога staticpop по ID \(bannerSampleID).",
      hasLogo: bannerHasLogo && bannerSampleID == TVPageBannerSamples.primaryID,
      hasBackdrop: bannerHasBackdrop,
      hasPoster: bannerHasPoster,
      scores: bannerCustomScores
    )
  }

  private func updateBannerState() {
    activeBannerHostView?.isSimulatedFocused = (bannerFocusState == .focused)
    activeBannerHostView?.configure(feature: currentBannerFeature, chrome: currentBannerChrome)
  }

  private func applyBannerPreset(_ preset: BannerLabPreset) {
    bannerPreset = preset
    switch preset {
    case .currentDefault:
      bannerSampleID = TVPageBannerSamples.primaryID
      bannerHasLogo = true
      bannerHasBackdrop = true
      bannerHasPoster = false
      bannerShowsPoster = false
      bannerLogoPlacement = .top
      bannerAlignment = .leading
      bannerVerticalAlignment = .bottom
      bannerFocusState = .unfocused
      bannerVibranceEnabled = false
      bannerCustomScores = nil
      bannerShowsVotes = false
      bannerRatingLimit = 2
      bannerFilterNoise = true
      bannerFilterDominant = true
      bannerShowsAggregate = false
      bannerAggregateOnly = false
      bannerDedupAggregate = true
      bannerScrimChoice = .defaultBottom
      bannerBlend = .normal
    case .previousFull:
      bannerSampleID = TVPageBannerSamples.primaryID
      bannerHasLogo = true
      bannerHasBackdrop = true
      bannerHasPoster = true
      bannerShowsPoster = true
      bannerLogoPlacement = .top
      bannerAlignment = .leading
      bannerVerticalAlignment = .bottom
      bannerFocusState = .unfocused
      bannerVibranceEnabled = true
      bannerVibrance = 0.65
      bannerCustomScores = nil
      bannerShowsVotes = true
      bannerScrimChoice = .edgesBlack
      bannerBlend = .normal
    case .focusedState:
      bannerFocusState = .focused
    case .noisyScores:
      bannerSampleID = TVPageBannerSamples.primaryID
      bannerCustomScores = MediaScores(imdb: 8.5, imdbVotes: 6, kinopoisk: 8.1, kinopoiskVotes: 4200)
    case .unknownScore:
      bannerSampleID = TVPageBannerSamples.primaryID
      bannerCustomScores = MediaScores(imdb: 7.9, imdbVotes: 45, kinopoisk: nil, kinopoiskVotes: 2500)
    case .dominantScore:
      bannerSampleID = TVPageBannerSamples.primaryID
      bannerCustomScores = MediaScores(imdb: 8.0, imdbVotes: 1000, kinopoisk: 8.4, kinopoiskVotes: 50_000)
    case .fallbackSources:
      bannerSampleID = TVPageBannerSamples.primaryID
      bannerCustomScores = MediaScores(imdb: nil, kinopoisk: nil, tmdb: 7.5, tmdbVotes: 800, kinopubLikes: 135, kinopubDislikes: 15)
    case .kinopub100:
      bannerSampleID = TVPageBannerSamples.primaryID
      bannerCustomScores = MediaScores(imdb: 8.2, imdbVotes: 5000, kinopubLikes: 100, kinopubDislikes: 0)
    case .aggregateDedup:
      bannerSampleID = TVPageBannerSamples.primaryID
      bannerShowsAggregate = true
      bannerAggregateOnly = false
      bannerDedupAggregate = true
      bannerCustomScores = MediaScores(imdb: 8.5, imdbVotes: 38)
    case .typographyOnly:
      bannerSampleID = TVPageBannerSamples.primaryID
      bannerHasLogo = false
      bannerHasBackdrop = true
      bannerHasPoster = false
      bannerShowsPoster = false
    case .noPoster:
      bannerSampleID = TVPageBannerSamples.primaryID
      bannerHasLogo = true
      bannerHasBackdrop = true
      bannerHasPoster = false
      bannerShowsPoster = false
    case .noBackdrop:
      bannerSampleID = TVPageBannerSamples.primaryID
      bannerHasLogo = true
      bannerHasBackdrop = false
      bannerHasPoster = false
      bannerShowsPoster = false
    case .catalog125268:
      bannerSampleID = 125268
      bannerHasLogo = false
      bannerHasBackdrop = true
      bannerHasPoster = false
      bannerShowsPoster = false
      bannerCustomScores = nil
    case .catalog125260:
      bannerSampleID = 125260
      bannerHasLogo = false
      bannerHasBackdrop = true
      bannerHasPoster = false
      bannerShowsPoster = false
      bannerCustomScores = nil
    }
  }

  private func resetBannerDefaults() {
    let defaults = TVPageBannerChrome.current
    bannerLogoPlacement = defaults.logoPlacement
    bannerAlignment = defaults.alignment
    bannerVerticalAlignment = defaults.verticalAlignment
    bannerShowsPoster = defaults.showsPoster
    bannerBlend = defaults.blend
    bannerVibrance = Double(defaults.textVibrance)
    bannerVibranceEnabled = defaults.vibranceEnabled
    bannerScrimChoice = .edgesBlack
    bannerPreset = .currentDefault
    bannerFocusState = .unfocused
    bannerSampleID = TVPageBannerSamples.primaryID
    bannerHasLogo = true
    bannerHasBackdrop = true
    bannerHasPoster = false
  }

  private func bannerPreviewController() -> UIViewController {
    if let cached = cachedBannerPreviewController {
      return cached
    }
    let container = makeBannerContainerView()
    let controller = TSKPreview.make(contentView: container, description: nil) ?? UIViewController()
    self.cachedBannerPreviewController = controller
    return controller
  }

  private func makeBannerContainerView() -> UIView {
    let container = UIView()
    container.translatesAutoresizingMaskIntoConstraints = false
    let host = TVPageBannerPreviewHost(frame: CGRect(x: 0, y: 0, width: 720, height: 450))
    host.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(host)
    NSLayoutConstraint.activate([
      container.widthAnchor.constraint(equalToConstant: 720),
      container.heightAnchor.constraint(equalToConstant: 450),
      host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      host.topAnchor.constraint(equalTo: container.topAnchor),
      host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
    host.isSimulatedFocused = (bannerFocusState == .focused)
    host.configure(feature: currentBannerFeature, chrome: currentBannerChrome)
    self.activeBannerHostView = host
    return container
  }

  private func bannerLabPage() -> TSKPage {
    TSKPage(
      title: "Home Banner Lab",
      customPreview: { [unowned self] _ in
        self.bannerPreviewController()
      },
      idlePreview: { [unowned self] in
        self.bannerPreviewController()
      },
      sections: { [unowned self] in
        self.bannerLabSections()
      }
    )
  }

  private func bannerLabSections() -> [TSKSection] {
    [
      TSKSection(
        title: "Состояние фокуса".localized,
        rows: [
          TSKRow(
            title: "Фокус карточки: \(bannerFocusState.label)".localized,
            description: "Симуляция фокуса на баннере: в фокусе описание приобретает primary белый оттенок, вне фокуса — вторичный (70%). Нажмите Select для переключения.",
            kind: .action(pushes: false) { [unowned self] in
              self.bannerFocusState = (self.bannerFocusState == .unfocused ? .focused : .unfocused)
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
        ]
      ),
      TSKSection(
        title: "Пресеты тайтла".localized,
        rows: [
          TSKRow(
            title: "Сценарий: \(bannerPreset.label)".localized,
            description: "Выбор готового сценария (нажмите Select для переключения): Новый дефолт, Пример 2, без логотипа, шум, доминанта и др.",
            kind: .action(pushes: false) { [unowned self] in
              let all = BannerLabPreset.allCases
              let nextIndex = (all.firstIndex(of: self.bannerPreset).map { $0 + 1 } ?? 0) % all.count
              self.applyBannerPreset(all[nextIndex])
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
        ]
      ),
      TSKSection(
        title: "Каталог staticpop".localized,
        rows: [
          TSKRow(
            title: "ID тайтла: #\(bannerSampleID)".localized,
            description: "Загрузка арта из каталога staticpop по ID. Нажмите Select для циклического выбора популярных тайтлов.",
            kind: .action(pushes: false) { [unowned self] in
              let samples = [125269, 125268, 125267, 125266, 125265, 125260]
              let nextIndex = (samples.firstIndex(of: self.bannerSampleID).map { $0 + 1 } ?? 0) % samples.count
              self.bannerSampleID = samples[nextIndex]
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
          TSKRow(
            title: "Следующий ID (+1)".localized,
            description: "Переключить на следующий тайтл каталога staticpop (#\(bannerSampleID + 1)).",
            kind: .action(pushes: false) { [unowned self] in
              self.bannerSampleID += 1
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
          TSKRow(
            title: "Предыдущий ID (−1)".localized,
            description: "Переключить на предыдущий тайтл каталога staticpop (#\(max(1, bannerSampleID - 1))).",
            kind: .action(pushes: false) { [unowned self] in
              self.bannerSampleID = max(1, self.bannerSampleID - 1)
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
          TSKRow(
            title: "Сброс к 125269 (Паук-Нуар)".localized,
            description: "Возврат к основному тестовому тайтлу 125269 с логотипом и высоким разрешением бэкдропа.",
            kind: .action(pushes: false) { [unowned self] in
              self.applyBannerPreset(.currentDefault)
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
        ]
      ),
      TSKSection(
        title: "Раскладка".localized,
        rows: [
          TSKRow(
            title: "Размещение логотипа: \(bannerLogoPlacement == .top ? "Top" : "Above copy")".localized,
            description: "Top — логотип закреплен в верхнем инсете карточки. Above copy — логотип находится в колонке контента над синопсисом. Нажмите Select для переключения.",
            kind: .action(pushes: false) { [unowned self] in
              self.bannerLogoPlacement = (self.bannerLogoPlacement == .top ? .aboveCopy : .top)
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
          TSKRow(
            title: "Выравнивание контента: \(bannerAlignment == .leading ? "Leading" : "Center")".localized,
            description: "Leading — текст слева, постер справа. Center — сгруппированный блок контента по центру карточки. Нажмите Select для переключения.",
            kind: .action(pushes: false) { [unowned self] in
              self.bannerAlignment = (self.bannerAlignment == .leading ? .center : .leading)
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
          TSKRow(
            title: "Вертикальное выравнивание: \(bannerVerticalAlignment.title)".localized,
            description: "Позиционирование блока контента по вертикали: Снизу (дефолт), По центру, Сверху. Нажмите Select для переключения.",
            kind: .action(pushes: false) { [unowned self] in
              let all = TVPageBannerVerticalAlignment.allCases
              let nextIndex = (all.firstIndex(of: self.bannerVerticalAlignment).map { $0 + 1 } ?? 0) % all.count
              self.bannerVerticalAlignment = all[nextIndex]
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
          TSKRow(
            title: "Показывать постер: \(bannerShowsPoster ? "Вкл" : "Выкл")".localized,
            description: "Включение или отключение вертикальной плашки постера справа от текста. Нажмите Select для переключения.",
            kind: .action(pushes: false) { [unowned self] in
              self.bannerShowsPoster.toggle()
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
        ]
      ),
      TSKSection(
        title: "Стилизация и наложение".localized,
        rows: [
          TSKRow(
            title: "Затемнение (Scrim): \(bannerScrimChoice.label)".localized,
            description: "Градиентные полосы по краям, сплошная заливка (wash) или радиальное затемнение черным цветом либо доминантным оттенком #C80202. Нажмите Select для переключения.",
            kind: .action(pushes: false) { [unowned self] in
              let all = BannerLabScrim.allCases
              let nextIndex = (all.firstIndex(of: self.bannerScrimChoice).map { $0 + 1 } ?? 0) % all.count
              self.bannerScrimChoice = all[nextIndex]
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
          TSKRow(
            title: "Режим наложения (Blend): \(bannerBlend.title)".localized,
            description: "Compositing-фильтр режима наложения (Normal, Multiply, Screen, Overlay, Soft light, Darken) поверх бэкдропа. Нажмите Select для переключения.",
            kind: .action(pushes: false) { [unowned self] in
              let all = TVPageBannerBlend.allSupportedCases
              let nextIndex = (all.firstIndex(of: self.bannerBlend).map { $0 + 1 } ?? 0) % all.count
              self.bannerBlend = all[nextIndex]
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
          TSKRow(
            title: "Высветление (Vibrance): \(bannerVibranceEnabled ? "Вкл" : "Выкл")".localized,
            description: "Включение программного высветления вторичного текста к белому. Нажмите Select для переключения.",
            kind: .action(pushes: false) { [unowned self] in
              self.bannerVibranceEnabled.toggle()
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
          TSKRow(
            title: "Яркость текста (Vibrance): \(String(format: "%.2f", bannerVibrance))".localized,
            description: "Смешивание цвета вторичного текста к чистому белому для читаемости на темном фоне. Нажмите Select для переключения.",
            kind: .action(pushes: false) { [unowned self] in
              let options: [Double] = [0.0, 0.25, 0.50, 0.65, 0.85, 1.0]
              let nextIndex = (options.firstIndex(where: { abs($0 - self.bannerVibrance) < 0.01 }).map { $0 + 1 } ?? 0) % options.count
              self.bannerVibrance = options[nextIndex]
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
        ]
      ),
      TSKSection(
        title: "Рейтинги и оценки".localized,
        rows: [
          TSKRow(
            title: "Голоса в скобках (12K): \(bannerShowsVotes ? "Вкл" : "Выкл")".localized,
            description: "Показывать количество проголосовавших в скобках после оценки. Нажмите Select для переключения.",
            kind: .action(pushes: false) { [unowned self] in
              self.bannerShowsVotes.toggle()
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
          TSKRow(
            title: "Лимит оценок: \(bannerRatingLimit)".localized,
            description: "Максимальное количество плашек оценок в строке метаданных баннера (1 или 2). Нажмите Select для переключения.",
            kind: .action(pushes: false) { [unowned self] in
              self.bannerRatingLimit = (self.bannerRatingLimit == 1 ? 2 : 1)
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
          TSKRow(
            title: "Фильтр шума (< 10 голосов): \(bannerFilterNoise ? "Вкл" : "Выкл")".localized,
            description: "Отбрасывать оценки с менее чем 10 голосами, если присутствуют более крупные источники. Нажмите Select для переключения.",
            kind: .action(pushes: false) { [unowned self] in
              self.bannerFilterNoise.toggle()
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
          TSKRow(
            title: "Фильтр доминанты (> 90%): \(bannerFilterDominant ? "Вкл" : "Выкл")".localized,
            description: "Оставлять только одну оценку, если один из источников дает более 90% всех голосов. Нажмите Select для переключения.",
            kind: .action(pushes: false) { [unowned self] in
              self.bannerFilterDominant.toggle()
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
          TSKRow(
            title: "Агрегированная оценка: \(bannerShowsAggregate ? "Вкл" : "Выкл")".localized,
            description: "Показывать объединенную взвешенную оценку (плашка с оценкой 0...10). Нажмите Select для переключения.",
            kind: .action(pushes: false) { [unowned self] in
              self.bannerShowsAggregate.toggle()
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
          TSKRow(
            title: "Только агрегат (без источников): \(bannerAggregateOnly ? "Вкл" : "Выкл")".localized,
            description: "Отображать только агрегированную оценку без разбивки по источникам. Нажмите Select для переключения.",
            kind: .action(pushes: false) { [unowned self] in
              self.bannerAggregateOnly.toggle()
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
          TSKRow(
            title: "Не дублировать цифру при 1 источнике: \(bannerDedupAggregate ? "Вкл" : "Выкл")".localized,
            description: "Если агрегат состоит из одного источника (например только IMDb 8.5), скрывать повторяющуюся цифру у источника. Нажмите Select для переключения.",
            kind: .action(pushes: false) { [unowned self] in
              self.bannerDedupAggregate.toggle()
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
        ]
      ),
      TSKSection(
        title: "Дефолты".localized,
        rows: [
          TSKRow(
            title: "Сбросить к новому дефолту".localized,
            description: "Сбросить все параметры баннера к новому базовому варианту (без постера, компактный нижний отступ 22pt, чистое описание).",
            kind: .action(pushes: false) { [unowned self] in
              self.applyBannerPreset(.currentDefault)
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
          TSKRow(
            title: "Восстановить пример 2 (Как было)".localized,
            description: "Восстановить параметры предыдущей версии (с постером 42%, нижний отступ 32pt, vibrance 0.65).",
            kind: .action(pushes: false) { [unowned self] in
              self.applyBannerPreset(.previousFull)
              self.updateBannerState()
              self.host.reloadPages()
            }
          ),
        ]
      ),
    ]
  }


  private func aboutSections() -> [TSKSection] {
    [TSKSection(rows: [
      TSKRow(title: "Version".localized,
             kind: .info(value: "\(Bundle.main.appVersionLong) (\(Bundle.main.appBuild))"),
             isFocusable: false),
      TSKRow(title: "What's new".localized,
             kind: .action(pushes: false) { [unowned self] in self.presentPopup(.history) }),
      TSKRow(title: "Licenses".localized,
             kind: .action(pushes: false) { [unowned self] in self.presentPopup(.licenses) }),
    ])]
  }

  enum AboutPopup: String {
    case history, licenses
  }

  func presentPopup(_ popup: AboutPopup) {
    let controller: UIViewController
    switch popup {
    case .history:
      let language = changelogLanguage
      controller = InfoPopupPresenter.controller(title: Text("What's new")) {
        ChangelogHistory(languageCode: language)
      }
    case .licenses:
      controller = InfoPopupPresenter.controller(title: Text("Licenses")) {
        OpenSourceLicensesView()
      }
    }
    host.presentPopup(controller)
  }

  private var changelogLanguage: String {
    UserDefaults.standard.string(forKey: "selectedLanguage")
      ?? Locale.current.language.languageCode?.identifier
      ?? "ru"
  }

  private func rememberedTracksPage() -> TSKPage {
    TSKPage(title: "Remembered tracks".localized, previewSymbol: "captions.bubble") { [unowned self] in
      let digest = TrackPreferenceDigest.sections(from: AppContext.shared.trackPreferences.storedScopes)
      let sections = digest.compactMap { section -> TSKSection? in
        let rows = section.groups.compactMap { group -> TSKRow? in
          guard let leader = group.audio.first ?? group.subtitles.first else { return nil }
          return TSKRow(title: self.scopeLabel(group.scope),
                        description: "Settings_Tip_RememberedTracks".localized,
                        kind: .info(value: "\(leader.label) · \(leader.weight)"))
        }
        return rows.isEmpty ? nil : TSKSection(title: self.trackTitle(section), rows: rows)
      }
      guard !sections.isEmpty else {
        return [TSKSection(rows: [
          TSKRow(title: "Nothing remembered yet. Pick a dub or a subtitle track in the player and it will show up here.".localized,
                 kind: .info(value: "")),
        ])]
      }
      return sections
    }
  }

  // MARK: - Previews

  /// The app plate, name, version and build. Nothing longer: TVSettingKit shrinks a long
  /// description to fit, and this build's notes under the plate came out unreadable —
  /// they are What's New's.
  private func appPreview() -> UIViewController {
    let text = NSMutableAttributedString(
      string: "KinoPub".localized + "\n",
      attributes: [.font: UIFont.preferredFont(forTextStyle: .title3).withWeight(.bold)]
    )
    let versionLine = String(format: "Version %@ • Build %@".localized,
                             Bundle.main.appVersionLong, Bundle.main.appBuild)
    text.append(NSAttributedString(
      string: versionLine,
      attributes: [.font: UIFont.preferredFont(forTextStyle: .caption1),
                   .foregroundColor: UIColor.secondaryLabel]
    ))
    return TSKPreview.make(contentView: Self.appPlate(), description: text) ?? UIViewController()
  }

  /// Brand, not chrome: the mark is drawn on a black disc, so the plate is black too.
  private static func appPlate() -> UIView {
    let plate = UIView()
    plate.backgroundColor = .black
    plate.layer.cornerRadius = 44
    plate.layer.cornerCurve = .continuous
    let mark = UIImageView(image: UIImage(named: "kinopub_icon"))
    mark.contentMode = .scaleAspectFit
    mark.translatesAutoresizingMaskIntoConstraints = false
    plate.addSubview(mark)
    plate.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      plate.widthAnchor.constraint(equalToConstant: 400),
      plate.heightAnchor.constraint(equalToConstant: 240),
      mark.centerXAnchor.constraint(equalTo: plate.centerXAnchor),
      mark.centerYAnchor.constraint(equalTo: plate.centerYAnchor),
      mark.widthAnchor.constraint(equalToConstant: 132),
      mark.heightAnchor.constraint(equalToConstant: 132),
    ])
    return plate
  }

  // MARK: - Helpers

  private func info(_ titleKey: String, _ value: String) -> TSKRow {
    TSKRow(title: titleKey.localized, kind: .info(value: value))
  }

  private func optionLabel(_ value: Any?, _ options: [DeviceSettingOption]) -> String? {
    guard let id = (value as? NSNumber)?.intValue else { return nil }
    return options.first { $0.id == id }?.label
  }

#if DEBUG
  func presentForDebugging(_ lab: Lab) {
    present(lab.page)
  }
#endif

  /// Full-screen tools get their own stack: some push routes (Player cases opens the real
  /// player routes), and a presented page is outside every other one.
  ///
  /// `inStack: false` is for pages that bring their own navigation container. Pulse's tvOS
  /// `ConsoleView` nests a `NavigationView` and injects its view models inside it; under an
  /// outer stack its links push onto ours, outside that injection, and `ConsoleFiltersView`
  /// traps on the missing `ConsoleFiltersViewModel`.
  private func present(_ view: some View, inStack: Bool = true) {
    host.present(host_(inStack ? AnyView(NavigationStack { view }) : AnyView(view)))
  }
  
  /// Present Pulse console directly without custom environment wrapping.
  /// Pulse's ConsoleView sets up its own environment internally, and wrapping it
  /// in our custom hosting closure prevents that initialization.
  private func presentPulseConsole() {
    let consoleView = NetworkConsoleView()
    // Create a plain UIHostingController without custom environment injection
    let controller = UIHostingController(rootView: consoleView)
    host.present(controller)
  }

  private func scopeLabel(_ scope: TrackMemoryScope) -> String {
    scope.displayLabel
  }

  private func trackTitle(_ section: TrackPreferenceDigest.Section) -> String {
    guard let titleID = section.titleID else { return "Anime".localized }
    return AppContext.shared.localProgressStore.snapshot(for: titleID)?.localizedTitle ?? "#\(titleID)"
  }

  private static func flagKey(_ flag: FeatureFlag) -> String { "flag_\(flag.rawValue)" }

  // MARK: - Bindings

  private func bindValues() {
    let store = host.store
    let defaults = UserDefaults.standard

    store.bind("language",
               get: { (defaults.string(forKey: "selectedLanguage")
                       ?? Locale.current.language.languageCode?.identifier ?? "en") as NSString },
               set: { [unowned self] value in
                 guard let code = value as? String else { return }
                 defaults.set(code, forKey: "selectedLanguage")
                 self.onLanguageChange(code)
               })
    store.bind("streamQuality",
               get: { (defaults.string(forKey: StreamQuality.userDefaultsKey) ?? StreamQuality.auto.rawValue) as NSString },
               set: { defaults.set($0 as? String, forKey: StreamQuality.userDefaultsKey) })
    store.bindBool("autoPlayNextEpisode",
                   get: { PlaybackPreferences.autoPlayNextEpisode },
                   set: { defaults.set($0, forKey: PlaybackPreferences.autoPlayNextEpisodeKey) })
    store.bindBool("autoPlayNextSeason",
                   get: { PlaybackPreferences.autoPlayNextSeason },
                   set: { defaults.set($0, forKey: PlaybackPreferences.autoPlayNextSeasonKey) })
    store.bindBool("subtitlesEnglish", get: { SubtitlePreferences.preferEnglishSubtitles },
                   set: { defaults.set($0, forKey: SubtitlePreferences.preferEnglishKey) })
    store.bindBool("subtitlesNonCC", get: { SubtitlePreferences.preferNonCCSubtitles },
                   set: { defaults.set($0, forKey: SubtitlePreferences.preferNonCCKey) })
    store.bindBool("subtitlesDual", get: { SubtitlePreferences.dualSubtitlesEnabled },
                   set: { defaults.set($0, forKey: SubtitlePreferences.dualSubtitlesKey) })
    store.bind("subtitlesSecondLanguage",
               get: { SubtitlePreferences.secondSubtitleLanguage as NSString },
               set: { defaults.set($0 as? String, forKey: SubtitlePreferences.secondSubtitleLanguageKey) })
    store.bindBool("streamToPulse", get: { defaults.bool(forKey: DiagnosticsSettings.remoteLoggingKey) },
                   set: { isOn in
                     defaults.set(isOn, forKey: DiagnosticsSettings.remoteLoggingKey)
                     NetworkDiagnostics.setRemoteLoggingEnabled(isOn)
                   })
    store.bindBool("activityOverlay", get: { defaults.bool(forKey: DiagnosticsSettings.activityOverlayKey) },
                   set: { defaults.set($0, forKey: DiagnosticsSettings.activityOverlayKey) })

    bindDevice("device4K", \.support4k)
    bindDevice("deviceHEVC", \.supportHevc)
    bindDevice("deviceHDR", \.supportHdr)
    bindDevice("deviceMixedPlaylist", \.mixedPlaylist)
    bindDeviceChoice("deviceStreamType", \.streamingType)
    bindDeviceChoice("deviceServerLocation", \.serverLocation)

    store.bind("kinopoiskKey",
               get: { [unowned self] in self.kinopoisk.keyText as NSString },
               set: { [unowned self] value in
                 self.kinopoisk.keyText = value as? String ?? ""
                 Task {
                   await self.kinopoisk.validate()
                   self.host.reloadPages()
                 }
               })

    for flag in FeatureFlag.allCases {
      store.bindBool(Self.flagKey(flag), get: { flag.storedValue }, set: { flag.set($0) })
    }

    // Banner Lab bindings
    store.bind("bannerFocusState",
               get: { [unowned self] in self.bannerFocusState.rawValue as NSString },
               set: { [unowned self] value in
                 guard let raw = value as? String, let state = BannerLabFocusState(rawValue: raw) else { return }
                 self.bannerFocusState = state
               })
    store.bind("bannerPreset",
               get: { [unowned self] in self.bannerPreset.rawValue as NSString },
               set: { [unowned self] value in
                 guard let raw = value as? String, let preset = BannerLabPreset(rawValue: raw) else { return }
                 self.applyBannerPreset(preset)
               })
    store.bind("bannerSampleID",
               get: { [unowned self] in NSNumber(value: self.bannerSampleID) },
               set: { [unowned self] value in
                 guard let id = (value as? NSNumber)?.intValue else { return }
                 self.bannerSampleID = id
               })
    store.bind("bannerLogoPlacement",
               get: { [unowned self] in self.bannerLogoPlacement.rawValue as NSString },
               set: { [unowned self] value in
                 guard let raw = value as? String, let placement = TVPageBannerLogoPlacement(rawValue: raw) else { return }
                 self.bannerLogoPlacement = placement
               })
    store.bind("bannerAlignment",
               get: { [unowned self] in self.bannerAlignment.rawValue as NSString },
               set: { [unowned self] value in
                 guard let raw = value as? String, let alignment = TVPageBannerContentAlignment(rawValue: raw) else { return }
                 self.bannerAlignment = alignment
               })
    store.bindBool("bannerShowsPoster",
                   get: { [unowned self] in self.bannerShowsPoster },
                   set: { [unowned self] in self.bannerShowsPoster = $0 })
    store.bind("bannerScrim",
               get: { [unowned self] in self.bannerScrimChoice.rawValue as NSString },
               set: { [unowned self] value in
                 guard let raw = value as? String, let scrim = BannerLabScrim(rawValue: raw) else { return }
                 self.bannerScrimChoice = scrim
               })
    store.bind("bannerBlend",
               get: { [unowned self] in self.bannerBlend.rawValue as NSString },
               set: { [unowned self] value in
                 guard let raw = value as? String, let blend = TVPageBannerBlend(rawValue: raw) else { return }
                 self.bannerBlend = blend
               })
    store.bindBool("bannerVibranceEnabled",
                   get: { [unowned self] in self.bannerVibranceEnabled },
                   set: { [unowned self] in self.bannerVibranceEnabled = $0 })
    store.bind("bannerVibrance",
               get: { [unowned self] in NSNumber(value: self.bannerVibrance) },
               set: { [unowned self] value in
                 guard let v = (value as? NSNumber)?.doubleValue else { return }
                 self.bannerVibrance = v
               })
    store.bindBool("bannerShowsVotes",
                   get: { [unowned self] in self.bannerShowsVotes },
                   set: { [unowned self] in self.bannerShowsVotes = $0 })
    store.bind("bannerRatingLimit",
               get: { [unowned self] in NSNumber(value: self.bannerRatingLimit) },
               set: { [unowned self] value in
                 guard let limit = (value as? NSNumber)?.intValue else { return }
                 self.bannerRatingLimit = limit
               })
    store.bindBool("bannerFilterNoise",
                   get: { [unowned self] in self.bannerFilterNoise },
                   set: { [unowned self] in self.bannerFilterNoise = $0 })
    store.bindBool("bannerFilterDominant",
                   get: { [unowned self] in self.bannerFilterDominant },
                   set: { [unowned self] in self.bannerFilterDominant = $0 })
    store.bindBool("bannerShowsAggregate",
                   get: { [unowned self] in self.bannerShowsAggregate },
                   set: { [unowned self] in self.bannerShowsAggregate = $0 })
    store.bindBool("bannerAggregateOnly",
                   get: { [unowned self] in self.bannerAggregateOnly },
                   set: { [unowned self] in self.bannerAggregateOnly = $0 })
    store.bindBool("bannerDedupAggregate",
                   get: { [unowned self] in self.bannerDedupAggregate },
                   set: { [unowned self] in self.bannerDedupAggregate = $0 })

    // Rows that depend on another row's value, and the experiments page's pending-quit row.
    store.didWrite = { [unowned self] key in
      if ["subtitlesEnglish", "subtitlesDual", "autoPlayNextEpisode"].contains(key)
          || key.hasPrefix("flag_") {
        self.host.reloadPages()
      } else if key.hasPrefix("banner") {
        self.updateBannerState()
      }
    }
  }

  /// There is no Save button on a remote: a change is sent as it is made.
  private func bindDevice(_ key: String, _ keyPath: WritableKeyPath<DeviceSettings, Bool>) {
    host.store.bindBool(key, get: { [unowned self] in self.device.settings[keyPath: keyPath] },
                        set: { [unowned self] in
                          self.device.settings[keyPath: keyPath] = $0
                          self.saveDevice()
                        })
  }

  private func bindDeviceChoice(_ key: String, _ keyPath: WritableKeyPath<DeviceSettings, Int>) {
    host.store.bind(key, get: { [unowned self] in NSNumber(value: self.device.settings[keyPath: keyPath]) },
                    set: { [unowned self] value in
                      guard let id = (value as? NSNumber)?.intValue else { return }
                      self.device.settings[keyPath: keyPath] = id
                      self.saveDevice()
                    })
  }

  private func saveDevice() {
    Task {
      await device.save(deviceService: deviceService, errorHandler: errorHandler)
      host.reloadPages()
    }
  }
}

// MARK: - Catalogue

extension TVSettingsCatalog {
  enum Category: String, CaseIterable {
    case account, server, device, videoAudio, tabs, appearance, dataSources, advanced, experiments, developer, about

    var title: String {
      switch self {
      case .account: "Kinopub account".localized
      case .server: "Server & connection".localized
      case .device: "Device".localized
      case .videoAudio: "Video & audio".localized
      case .tabs: "Вкладки и Главная"
      case .appearance: "Appearance".localized
      case .dataSources: "Data sources".localized
      case .advanced: "Advanced".localized
      case .experiments: "Feature flags".localized
      case .developer: "For developers".localized
      case .about: "About".localized
      }
    }

    var symbol: String {
      switch self {
      case .account: "person.crop.circle"
      case .server: "server.rack"
      case .device: "appletv"
      case .videoAudio: "play.rectangle"
      case .tabs: "square.grid.2x2"
      case .appearance: "paintbrush"
      case .dataSources: "square.stack.3d.up"
      case .advanced: "gearshape.2"
      case .experiments: "flask"
      case .developer: "hammer"
      case .about: "info.circle"
      }
    }

    var tip: String {
      switch self {
      case .account: "Settings_Tip_Account".localized
      case .server: "Settings_Tip_Server".localized
      case .device: "Settings_Tip_Device".localized
      case .videoAudio: "Settings_Tip_VideoAudio".localized
      case .tabs: "Настройка видимости и порядка вкладок верхнего меню (Каталог, Подборки, Фильмы, Сериалы, ТВ) и секций Главной страницы."
      case .appearance: "Settings_Tip_Appearance".localized
      case .dataSources: "Settings_Tip_DataSourcesCategory".localized
      case .advanced: "Settings_Tip_Advanced".localized
      case .experiments: "Settings_Tip_Experiments".localized
      case .developer: "Settings_Tip_Developer".localized
      case .about: "Settings_Tip_About".localized
      }
    }

    var usesDeviceSettings: Bool { self == .server || self == .device }
  }

  /// Developer tools — full-screen, so presented over Settings rather than pushed into
  /// its list column. Listed in every build.
  enum Lab: String, CaseIterable {
    case playerCases, tvUIKitGallery, bannerLab, navFocusLab, libraryLab, typeStyles, streamSurvey

    var title: String {
      switch self {
      case .playerCases: "Player cases"
      case .tvUIKitGallery: "TVUIKit Gallery"
      case .bannerLab: "Home Banner Lab"
      case .navFocusLab: "Navigation / Focus Lab"
      case .libraryLab: "Library Sidebar Lab"
      case .typeStyles: "Type Styles"
      case .streamSurvey: "Stream survey".localized
      }
    }

    var description: String? {
      switch self {
      case .streamSurvey: return "Settings_Tip_Diagnostics".localized
      case .bannerLab: return "Интерактивная настройка баннера главной: логотип, выравнивание, постер, scrim, blend и каталожные ID."
      default: return "Settings_Tip_Developer".localized
      }
    }

    @MainActor @ViewBuilder
    var page: some View {
      switch self {
      case .playerCases: PlayerCasesView()
      case .tvUIKitGallery: TVUIKitComponentGalleryView()
      case .bannerLab: TVPageBannerLabView()
      case .navFocusLab: NavigationFocusLabView()
      case .libraryLab: LibrarySidebarLabView()
      case .typeStyles: SystemTypeStylesCatalogView()
      case .streamSurvey: StreamSurveyView()
      }
    }
  }
}

private extension UIFont {
  func withWeight(_ weight: UIFont.Weight) -> UIFont {
    UIFont.systemFont(ofSize: pointSize, weight: weight)
  }
}

// MARK: - SwiftUI entry

/// tvOS Settings when TVSettingKit is present. `TVProfileSettingsView` is the fallback.
struct TVSettingKitSettingsView: View {
  let model: ProfileModel
  let kinopoiskKeyProvider: KinopoiskKeyProvider
  var onLogout: () -> Void
  var onLanguageChange: (String) -> Void

  @Environment(\.appContext) private var appContext
  @Environment(ErrorHandler.self) private var errorHandler
  // Forwarded to presented SwiftUI pages: UIKit-hosted pages do not inherit the environment.
  @Environment(NavigationState.self) private var navigationState
  @EnvironmentObject private var authState: AuthState
  @EnvironmentObject private var networkMonitor: NetworkMonitor

  @State private var catalog: TVSettingsCatalog?
  @State private var depth = 0

  var body: some View {
    Group {
      if let catalog {
        TSKSplitView(host: catalog.host, root: catalog.rootPage)
      } else {
        Color.clear
      }
    }
    // The split lays out its own title and columns from the full screen, like the
    // Settings app; it reads UIKit's safe area itself.
    .ignoresSafeArea()
    .toolbar(depth > 0 ? .hidden : .automatic, for: .tabBar)
    .onAppear {
      if catalog == nil {
        let catalog = TVSettingsCatalog(
          model: model,
          kinopoiskKeyProvider: kinopoiskKeyProvider,
          deviceService: appContext.deviceService,
          errorHandler: errorHandler,
          onLogout: onLogout,
          onLanguageChange: onLanguageChange,
          hosting: { [appContext, navigationState, errorHandler, authState, networkMonitor] view in
            UIHostingController(rootView: view
              .environment(\.appContext, appContext)
              .environment(navigationState)
              .environment(errorHandler)
              .environmentObject(authState)
              .environmentObject(networkMonitor))
          }
        )
        catalog.host.onDepthChange = { depth = $0 }
        self.catalog = catalog
      }
      if let raw = UserDefaults.standard.string(forKey: "KINOPUBOpenSettingsCategoryOnce"),
         let category = TVSettingsCatalog.Category(rawValue: raw) {
        UserDefaults.standard.removeObject(forKey: "KINOPUBOpenSettingsCategoryOnce")
        Task { @MainActor in
          try? await Task.sleep(for: .milliseconds(150))
          self.catalog?.open(category)
        }
      }
    }
#if DEBUG
    // `-KINOPUBSettingsPage <category>` opens a page and `-KINOPUBSettingsLab <lab>` a
    // developer tool directly — the simulator's remote is too unreliable to walk there.
    .task {
      let defaults = UserDefaults.standard
      try? await Task.sleep(for: .seconds(1))
      if let raw = defaults.string(forKey: "KINOPUBSettingsPage"),
         let category = TVSettingsCatalog.Category(rawValue: raw) {
        catalog?.open(category)
      }
      // `-KINOPUBSettingsPopup history|licenses` opens About's popup.
      if let raw = defaults.string(forKey: "KINOPUBSettingsPopup"),
         let popup = TVSettingsCatalog.AboutPopup(rawValue: raw) {
        catalog?.open(.about)
        try? await Task.sleep(for: .seconds(1))
        catalog?.presentPopup(popup)
      }
      if let raw = defaults.string(forKey: "KINOPUBSettingsLab"),
         let lab = TVSettingsCatalog.Lab(rawValue: raw) {
        try? await Task.sleep(for: .seconds(1))
        catalog?.presentForDebugging(lab)
      }
    }
#endif
  }
}
#endif
