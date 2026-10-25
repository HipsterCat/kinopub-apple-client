//
//  SectionVisibilityStore.swift
//  KinoPubAppleClient
//
//  Persisted show/hide and ordering for top-level browse tabs and Watch Now sections —
//  plain `UserDefaults` so every platform, tvOS included, shares the same configuration.
//

import Foundation
import SwiftUI

extension Notification.Name {
  static let homeSectionsConfigurationDidChange = Notification.Name("homeSectionsConfigurationDidChange")
}

/// One optional section a user can hide from their tab bar / sidebar.
struct AppSection: Identifiable, Hashable {
  let id: String
  let titleKey: LocalizedStringKey

  static func == (lhs: AppSection, rhs: AppSection) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// A top-level browse tab that can be toggled on/off and reordered in Settings.
struct BrowseTabSpec: Identifiable, Hashable {
  let id: String
  let tab: NavigationTabs
  let titleKey: LocalizedStringKey
  let localizedTitle: String
  let systemImage: String
  let defaultVisible: Bool

  var symbol: String { systemImage }
  var canHide: Bool { id != "home" }

  static func == (lhs: BrowseTabSpec, rhs: BrowseTabSpec) -> Bool { lhs.id == rhs.id }
  func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Metadata for a configurable section on Watch Now (`HomeCatalog`).
struct HomeSectionMeta: Identifiable, Hashable {
  let id: String
  let title: String
  let subtitle: String
  let defaultVisible: Bool

  var sortingDescription: String { subtitle }
}

@MainActor
final class SectionVisibilityStore: ObservableObject {
  static let shared = SectionVisibilityStore()

  private let hiddenTabsKey = "hiddenSectionIDs"
  private let orderedTabsKey = "orderedBrowseTabIDs"
  private let hiddenHomeSectionsKey = "hiddenHomeSectionIDs"
  private let orderedHomeSectionsKey = "orderedHomeSectionIDs"
  private let hiddenMovieSectionsKey = "hiddenMovieSectionIDs"
  private let orderedMovieSectionsKey = "orderedMovieSectionIDs"
  private let hiddenSeriesSectionsKey = "hiddenSeriesSectionIDs"
  private let orderedSeriesSectionsKey = "orderedSeriesSectionIDs"
  private let excludeConcertsKey = "homeExcludeConcerts"

  @Published private(set) var hiddenIDs: Set<String>
  @Published private(set) var orderedTabIDs: [String]
  @Published private(set) var hiddenHomeSectionIDs: Set<String>
  @Published private(set) var orderedHomeSectionIDs: [String]
  @Published private(set) var hiddenMovieSectionIDs: Set<String>
  @Published private(set) var orderedMovieSectionIDs: [String]
  @Published private(set) var hiddenSeriesSectionIDs: Set<String>
  @Published private(set) var orderedSeriesSectionIDs: [String]
  @Published var excludeConcertsOnHome: Bool {
    didSet {
      UserDefaults.standard.set(excludeConcertsOnHome, forKey: excludeConcertsKey)
      NotificationCenter.default.post(name: .homeSectionsConfigurationDidChange, object: nil)
    }
  }

  /// Default catalog of browse tabs in bar order.
  static let allBrowseTabs: [BrowseTabSpec] = {
    var tabs: [BrowseTabSpec] = [
      BrowseTabSpec(id: "home", tab: .home, titleKey: "Home",
                    localizedTitle: "Home".localized, systemImage: "house.fill", defaultVisible: true),
      BrowseTabSpec(id: "library", tab: .library, titleKey: "TabLibrary",
                    localizedTitle: "TabLibrary".localized, systemImage: "rectangle.stack.badge.person.crop", defaultVisible: true),
      BrowseTabSpec(id: "series", tab: .series, titleKey: "Series",
                    localizedTitle: "Series".localized, systemImage: "rectangle.stack", defaultVisible: true),
      BrowseTabSpec(id: "movies", tab: .movies, titleKey: "Movies",
                    localizedTitle: "Movies".localized, systemImage: "movieclapper", defaultVisible: true),
      BrowseTabSpec(id: "collections", tab: .collections, titleKey: "Bundles",
                    localizedTitle: "Bundles".localized, systemImage: "rectangle.3.group", defaultVisible: false),
      BrowseTabSpec(id: "catalog", tab: .catalog, titleKey: "Catalog",
                    localizedTitle: "Catalog".localized, systemImage: "square.grid.2x2", defaultVisible: true),
    ]
#if os(tvOS)
    tabs.append(
      BrowseTabSpec(id: "tv", tab: .tv, titleKey: "TV",
                    localizedTitle: "TV".localized, systemImage: "tv", defaultVisible: true)
    )
#endif
    return tabs
  }()

  /// Configurable sections on Watch Now (`HomeCatalog`).
  static let allHomeSections: [HomeSectionMeta] = [
    HomeSectionMeta(id: "new-arrivals",
                    title: "Новинки Кинопаба",
                    subtitle: "Свежие релизы по дате добавления (-created)",
                    defaultVisible: true),
    HomeSectionMeta(id: "recently-updated",
                    title: "Недавно обновлённые",
                    subtitle: "Новые серии, сезоны и обновления качества (-updated)",
                    defaultVisible: true),
    HomeSectionMeta(id: "weekly-top",
                    title: "Топ недели",
                    subtitle: "Лидеры просмотров за 7 дней (-views, period=week)",
                    defaultVisible: true),
    HomeSectionMeta(id: "must-see-hits",
                    title: "Главные хиты месяца",
                    subtitle: "Самые просматриваемые за месяц (-views, period=month)",
                    defaultVisible: true),
    HomeSectionMeta(id: "binge-worthy",
                    title: "Сериалы по подписчикам",
                    subtitle: "Самые отслеживаемые сериалы (-watchers)",
                    defaultVisible: true),
    HomeSectionMeta(id: "top-rated",
                    title: "Высокий рейтинг IMDb",
                    subtitle: "Лучшие релизы последних лет по IMDb (-imdb_rating)",
                    defaultVisible: true),
    HomeSectionMeta(id: "community-top",
                    title: "Выбор зрителей Кинопаба",
                    subtitle: "Топ по рейтингу аудитории Кинопаба (-rating)",
                    defaultVisible: true),
    HomeSectionMeta(id: "latest-4k",
                    title: "Последние 4K релизы",
                    subtitle: "Новые фильмы и сериалы в 4K UHD (quality=4, -created)",
                    defaultVisible: true),
    HomeSectionMeta(id: "top-bookmarks",
                    title: "Топовые закладки",
                    subtitle: "Лучшее непросмотренное из ваших закладок",
                    defaultVisible: true),
    HomeSectionMeta(id: "live-tv",
                    title: "Спортивные и ТВ-каналы",
                    subtitle: "Прямой эфир и спорт (/v1/tv)",
                    defaultVisible: true),
    HomeSectionMeta(id: "tv-shows",
                    title: "Передачи и Стендап",
                    subtitle: "Развлекательные шоу и стендап-концерты (-updated)",
                    defaultVisible: true),
    HomeSectionMeta(id: "anime-hits",
                    title: "Аниме: Популярное",
                    subtitle: "Главные хиты аниме по подписчикам (-watchers)",
                    defaultVisible: true),
    HomeSectionMeta(id: "docu-picks",
                    title: "Документальные",
                    subtitle: "Наука, биографии, тру-крайм (-views)",
                    defaultVisible: true),
    HomeSectionMeta(id: "collections",
                    title: "Подборки и Коллекции",
                    subtitle: "Кураторские подборки Кинопаба",
                    defaultVisible: true),
  ]

  /// Configurable sections on the Movies tab (`contentType == .movie`).
  static let allMovieSections: [HomeSectionMeta] = [
    HomeSectionMeta(id: "movies-new",
                    title: "Новинки кино",
                    subtitle: "Свежие фильмы на Кинопабе (-created)",
                    defaultVisible: true),
    HomeSectionMeta(id: "movies-weekly-top",
                    title: "Топ фильмов недели",
                    subtitle: "Лидеры просмотров за 7 дней (-views, period=week)",
                    defaultVisible: true),
    HomeSectionMeta(id: "movies-monthly-hits",
                    title: "Главные хиты месяца",
                    subtitle: "Самые просматриваемые фильмы за месяц (-views, period=month)",
                    defaultVisible: true),
    HomeSectionMeta(id: "movies-4k",
                    title: "Новые релизы в 4K UHD",
                    subtitle: "Фильмы в максимальном качестве (quality=4, -created)",
                    defaultVisible: true),
    HomeSectionMeta(id: "movies-top-imdb",
                    title: "Высокий рейтинг IMDb",
                    subtitle: "Лучшие современные фильмы по IMDb (-imdb_rating, 2020+)",
                    defaultVisible: true),
    HomeSectionMeta(id: "movies-community",
                    title: "Выбор зрителей Кинопаба",
                    subtitle: "Топ фильмов по рейтингу Кинопаба (-rating, period=year)",
                    defaultVisible: true),
    HomeSectionMeta(id: "movies-scifi",
                    title: "Фантастика и Фэнтези",
                    subtitle: "Миры будущего, космос и магия (genre=4,5, -views)",
                    defaultVisible: true),
    HomeSectionMeta(id: "movies-thriller",
                    title: "Остросюжетные триллеры и детективы",
                    subtitle: "Напряжённые триллеры, криминал и тайны (genre=7,13,17, -views)",
                    defaultVisible: true),
    HomeSectionMeta(id: "movies-action",
                    title: "Экшен и Приключения",
                    subtitle: "Масштабные боевики и блокбастеры (genre=2,8, -views)",
                    defaultVisible: true),
    HomeSectionMeta(id: "movies-comedy",
                    title: "Комедии для хорошего вечера",
                    subtitle: "Популярные комедии за год (genre=1, -views, period=year)",
                    defaultVisible: true),
    HomeSectionMeta(id: "movies-drama",
                    title: "Сильные драмы и биографии",
                    subtitle: "Драматическое кино с высоким рейтингом (genre=9,3, -imdb_rating)",
                    defaultVisible: true),
    HomeSectionMeta(id: "movies-horror",
                    title: "Хорроры и Мистика",
                    subtitle: "Ужасы и сверхъестественное (genre=12,11, -views, period=year)",
                    defaultVisible: true),
    HomeSectionMeta(id: "movies-family",
                    title: "Мультфильмы и Семейное кино",
                    subtitle: "Анимация и фильмы для всей семьи (genre=23,6, -views)",
                    defaultVisible: true),
    HomeSectionMeta(id: "movies-docu",
                    title: "Документальные фильмы",
                    subtitle: "Полнометражная документалистика (type=documovie, -views)",
                    defaultVisible: true),
    HomeSectionMeta(id: "movies-standup",
                    title: "Стендап-спешлы",
                    subtitle: "Сольные стендап-концерты (genre=101, -created)",
                    defaultVisible: true),
  ]

  /// Configurable sections on the Series & Shows tab (`contentType == .serial`).
  static let allSeriesSections: [HomeSectionMeta] = [
    HomeSectionMeta(id: "series-updated",
                    title: "Новые серии на этой неделе",
                    subtitle: "Свежие эпизоды и обновления сериалов (-updated)",
                    defaultVisible: true),
    HomeSectionMeta(id: "series-new",
                    title: "Новые сериалы и премьеры",
                    subtitle: "Недавно стартовавшие сериалы (-created)",
                    defaultVisible: true),
    HomeSectionMeta(id: "series-watchers",
                    title: "Главные сериалы по подписчикам",
                    subtitle: "Самые отслеживаемые сериалы Кинопаба (-watchers)",
                    defaultVisible: true),
    HomeSectionMeta(id: "series-weekly-top",
                    title: "Топ сериалов недели",
                    subtitle: "Лидеры просмотров за 7 дней (-views, period=week)",
                    defaultVisible: true),
    HomeSectionMeta(id: "series-finished",
                    title: "Завершённые сериалы целиком",
                    subtitle: "Полностью вышедшие сериалы для марафона (finished=1, -watchers)",
                    defaultVisible: true),
    HomeSectionMeta(id: "series-top-imdb",
                    title: "Золотой фонд IMDb",
                    subtitle: "Высший рейтинг IMDb среди сериалов (-imdb_rating)",
                    defaultVisible: true),
    HomeSectionMeta(id: "series-4k",
                    title: "Сериалы в 4K UHD",
                    subtitle: "Релизы сериалов в 4K UHD (quality=4, -updated)",
                    defaultVisible: true),
    HomeSectionMeta(id: "series-crime",
                    title: "Детективы, Триллеры и Криминал",
                    subtitle: "Расследования, нуар и триллеры (genre=13,7,17, -watchers)",
                    defaultVisible: true),
    HomeSectionMeta(id: "series-scifi",
                    title: "Фантастика и Фэнтези",
                    subtitle: "Научная фантастика и эпическое фэнтези (genre=4,5, -watchers)",
                    defaultVisible: true),
    HomeSectionMeta(id: "series-drama",
                    title: "Престижные драмы",
                    subtitle: "Лучшие драматические сериалы (genre=9, -watchers)",
                    defaultVisible: true),
    HomeSectionMeta(id: "series-comedy",
                    title: "Комедийные сериалы и ситкомы",
                    subtitle: "Лёгкие и смешные сериалы (genre=1, -watchers)",
                    defaultVisible: true),
    HomeSectionMeta(id: "series-anime",
                    title: "Аниме-сериалы",
                    subtitle: "Популярные аниме-сериалы по подписчикам (genre=25, -watchers)",
                    defaultVisible: true),
    HomeSectionMeta(id: "series-dorama",
                    title: "Дорамы",
                    subtitle: "Корейские и азиатские сериалы (genre=107, -watchers)",
                    defaultVisible: true),
    HomeSectionMeta(id: "series-docu",
                    title: "Документальные сериалы",
                    subtitle: "Тру-крайм, история и наука (type=docuserial, -views)",
                    defaultVisible: true),
    HomeSectionMeta(id: "series-tvshows",
                    title: "Телешоу и Передачи",
                    subtitle: "Развлекательные шоу и проекты (type=tvshow, -updated)",
                    defaultVisible: true),
  ]

  private init() {
    let defaultTabOrder = Self.allBrowseTabs.map(\.id)
    if let savedHidden = UserDefaults.standard.stringArray(forKey: hiddenTabsKey) {
      hiddenIDs = Set(savedHidden)
    } else {
      hiddenIDs = Set(Self.allBrowseTabs.filter { !$0.defaultVisible }.map(\.id))
    }

    if let savedOrder = UserDefaults.standard.stringArray(forKey: orderedTabsKey), !savedOrder.isEmpty {
      let known = Set(defaultTabOrder)
      var merged = savedOrder.filter { known.contains($0) }
      for id in defaultTabOrder where !merged.contains(id) {
        merged.append(id)
      }
      orderedTabIDs = merged
    } else {
      orderedTabIDs = defaultTabOrder
    }

    let defaultSectionOrder = Self.allHomeSections.map(\.id)
    if let savedHiddenSections = UserDefaults.standard.stringArray(forKey: hiddenHomeSectionsKey) {
      hiddenHomeSectionIDs = Set(savedHiddenSections)
    } else {
      hiddenHomeSectionIDs = Set(Self.allHomeSections.filter { !$0.defaultVisible }.map(\.id))
    }

    if let savedSectionOrder = UserDefaults.standard.stringArray(forKey: orderedHomeSectionsKey), !savedSectionOrder.isEmpty {
      let known = Set(defaultSectionOrder)
      var merged = savedSectionOrder.filter { known.contains($0) }
      for id in defaultSectionOrder where !merged.contains(id) {
        merged.append(id)
      }
      orderedHomeSectionIDs = merged
    } else {
      orderedHomeSectionIDs = defaultSectionOrder
    }

    let defaultMovieOrder = Self.allMovieSections.map(\.id)
    if let savedHiddenMovieSections = UserDefaults.standard.stringArray(forKey: hiddenMovieSectionsKey) {
      hiddenMovieSectionIDs = Set(savedHiddenMovieSections)
    } else {
      hiddenMovieSectionIDs = Set(Self.allMovieSections.filter { !$0.defaultVisible }.map(\.id))
    }

    if let savedMovieOrder = UserDefaults.standard.stringArray(forKey: orderedMovieSectionsKey), !savedMovieOrder.isEmpty {
      let known = Set(defaultMovieOrder)
      var merged = savedMovieOrder.filter { known.contains($0) }
      for id in defaultMovieOrder where !merged.contains(id) {
        merged.append(id)
      }
      orderedMovieSectionIDs = merged
    } else {
      orderedMovieSectionIDs = defaultMovieOrder
    }

    let defaultSeriesOrder = Self.allSeriesSections.map(\.id)
    if let savedHiddenSeriesSections = UserDefaults.standard.stringArray(forKey: hiddenSeriesSectionsKey) {
      hiddenSeriesSectionIDs = Set(savedHiddenSeriesSections)
    } else {
      hiddenSeriesSectionIDs = Set(Self.allSeriesSections.filter { !$0.defaultVisible }.map(\.id))
    }

    if let savedSeriesOrder = UserDefaults.standard.stringArray(forKey: orderedSeriesSectionsKey), !savedSeriesOrder.isEmpty {
      let known = Set(defaultSeriesOrder)
      var merged = savedSeriesOrder.filter { known.contains($0) }
      for id in defaultSeriesOrder where !merged.contains(id) {
        merged.append(id)
      }
      orderedSeriesSectionIDs = merged
    } else {
      orderedSeriesSectionIDs = defaultSeriesOrder
    }

    if UserDefaults.standard.object(forKey: excludeConcertsKey) != nil {
      excludeConcertsOnHome = UserDefaults.standard.bool(forKey: excludeConcertsKey)
    } else {
      excludeConcertsOnHome = true
    }
  }

  // MARK: - Browse Tabs Visibility & Ordering

  var orderedBrowseTabs: [BrowseTabSpec] {
    let byID = Dictionary(uniqueKeysWithValues: Self.allBrowseTabs.map { ($0.id, $0) })
    let ordered = orderedTabIDs.compactMap { byID[$0] }
    let missing = Self.allBrowseTabs.filter { !orderedTabIDs.contains($0.id) }
    return ordered + missing
  }

  var visibleBrowseTabs: [BrowseTabSpec] {
    let visible = orderedBrowseTabs.filter { isTabVisible($0.id) }
    if visible.isEmpty, let first = orderedBrowseTabs.first {
      return [first]
    }
    return visible
  }

  func isTabVisible(_ id: String) -> Bool {
    !hiddenIDs.contains(id)
  }

  func isTabVisible(_ tab: NavigationTabs) -> Bool {
    guard let spec = Self.allBrowseTabs.first(where: { $0.tab == tab }) else { return false }
    return isTabVisible(spec.id)
  }

  func canHideTab(_ id: String) -> Bool {
    if !isTabVisible(id) { return true }
    let visibleCount = orderedBrowseTabs.filter { isTabVisible($0.id) }.count
    return visibleCount > 1
  }

  func setTabVisible(_ visible: Bool, id: String) {
    if !visible && !canHideTab(id) { return }
    if visible {
      hiddenIDs.remove(id)
    } else {
      hiddenIDs.insert(id)
    }
    UserDefaults.standard.set(Array(hiddenIDs), forKey: hiddenTabsKey)
  }

  func toggleTabVisibility(id: String) {
    setTabVisible(!isTabVisible(id), id: id)
  }

  func tabIndex(of id: String) -> Int? {
    orderedTabIDs.firstIndex(of: id)
  }

  func canMoveTabUp(id: String) -> Bool {
    guard let idx = orderedTabIDs.firstIndex(of: id) else { return false }
    return idx > 0
  }

  func canMoveTabDown(id: String) -> Bool {
    guard let idx = orderedTabIDs.firstIndex(of: id) else { return false }
    return idx < orderedTabIDs.count - 1
  }

  func moveTabUp(id: String) {
    guard let idx = orderedTabIDs.firstIndex(of: id), idx > 0 else { return }
    orderedTabIDs.swapAt(idx, idx - 1)
    UserDefaults.standard.set(orderedTabIDs, forKey: orderedTabsKey)
  }

  func moveTabDown(id: String) {
    guard let idx = orderedTabIDs.firstIndex(of: id), idx < orderedTabIDs.count - 1 else { return }
    orderedTabIDs.swapAt(idx, idx + 1)
    UserDefaults.standard.set(orderedTabIDs, forKey: orderedTabsKey)
  }

  func moveTabs(fromOffsets source: IndexSet, toOffset destination: Int) {
    orderedTabIDs.move(fromOffsets: source, toOffset: destination)
    UserDefaults.standard.set(orderedTabIDs, forKey: orderedTabsKey)
  }

  func moveTab(id: String, toPosition oneBasedPosition: Int) {
    guard let currentIndex = orderedTabIDs.firstIndex(of: id) else { return }
    let targetIndex = max(0, min(orderedTabIDs.count - 1, oneBasedPosition - 1))
    guard currentIndex != targetIndex else { return }
    let item = orderedTabIDs.remove(at: currentIndex)
    orderedTabIDs.insert(item, at: targetIndex)
    UserDefaults.standard.set(orderedTabIDs, forKey: orderedTabsKey)
  }

  // MARK: - Home Sections Visibility & Ordering

  var orderedHomeSections: [HomeSectionMeta] {
    let byID = Dictionary(uniqueKeysWithValues: Self.allHomeSections.map { ($0.id, $0) })
    let ordered = orderedHomeSectionIDs.compactMap { byID[$0] }
    let missing = Self.allHomeSections.filter { !orderedHomeSectionIDs.contains($0.id) }
    return ordered + missing
  }

  var visibleHomeSections: [HomeSectionMeta] {
    orderedHomeSections.filter { isHomeSectionVisible($0.id) }
  }

  func isHomeSectionVisible(_ id: String) -> Bool {
    !hiddenHomeSectionIDs.contains(id)
  }

  func setHomeSectionVisible(_ visible: Bool, id: String) {
    if visible {
      hiddenHomeSectionIDs.remove(id)
    } else {
      hiddenHomeSectionIDs.insert(id)
    }
    UserDefaults.standard.set(Array(hiddenHomeSectionIDs), forKey: hiddenHomeSectionsKey)
    NotificationCenter.default.post(name: .homeSectionsConfigurationDidChange, object: nil)
  }

  func toggleHomeSectionVisibility(id: String) {
    setHomeSectionVisible(!isHomeSectionVisible(id), id: id)
  }

  func moveHomeSectionUp(id: String) {
    guard let idx = orderedHomeSectionIDs.firstIndex(of: id), idx > 0 else { return }
    orderedHomeSectionIDs.swapAt(idx, idx - 1)
    UserDefaults.standard.set(orderedHomeSectionIDs, forKey: orderedHomeSectionsKey)
    NotificationCenter.default.post(name: .homeSectionsConfigurationDidChange, object: nil)
  }

  func moveHomeSectionDown(id: String) {
    guard let idx = orderedHomeSectionIDs.firstIndex(of: id), idx < orderedHomeSectionIDs.count - 1 else { return }
    orderedHomeSectionIDs.swapAt(idx, idx + 1)
    UserDefaults.standard.set(orderedHomeSectionIDs, forKey: orderedHomeSectionsKey)
    NotificationCenter.default.post(name: .homeSectionsConfigurationDidChange, object: nil)
  }

  func moveHomeSections(fromOffsets source: IndexSet, toOffset destination: Int) {
    orderedHomeSectionIDs.move(fromOffsets: source, toOffset: destination)
    UserDefaults.standard.set(orderedHomeSectionIDs, forKey: orderedHomeSectionsKey)
    NotificationCenter.default.post(name: .homeSectionsConfigurationDidChange, object: nil)
  }

  func moveHomeSection(id: String, toPosition oneBasedPosition: Int) {
    guard let currentIndex = orderedHomeSectionIDs.firstIndex(of: id) else { return }
    let targetIndex = max(0, min(orderedHomeSectionIDs.count - 1, oneBasedPosition - 1))
    guard currentIndex != targetIndex else { return }
    let item = orderedHomeSectionIDs.remove(at: currentIndex)
    orderedHomeSectionIDs.insert(item, at: targetIndex)
    UserDefaults.standard.set(orderedHomeSectionIDs, forKey: orderedHomeSectionsKey)
    NotificationCenter.default.post(name: .homeSectionsConfigurationDidChange, object: nil)
  }

  // MARK: - Movies Sections Visibility & Ordering

  var orderedMovieSections: [HomeSectionMeta] {
    let byID = Dictionary(uniqueKeysWithValues: Self.allMovieSections.map { ($0.id, $0) })
    let ordered = orderedMovieSectionIDs.compactMap { byID[$0] }
    let missing = Self.allMovieSections.filter { !orderedMovieSectionIDs.contains($0.id) }
    return ordered + missing
  }

  var visibleMovieSections: [HomeSectionMeta] {
    orderedMovieSections.filter { isMovieSectionVisible($0.id) }
  }

  func isMovieSectionVisible(_ id: String) -> Bool {
    !hiddenMovieSectionIDs.contains(id)
  }

  func setMovieSectionVisible(_ visible: Bool, id: String) {
    if visible {
      hiddenMovieSectionIDs.remove(id)
    } else {
      hiddenMovieSectionIDs.insert(id)
    }
    UserDefaults.standard.set(Array(hiddenMovieSectionIDs), forKey: hiddenMovieSectionsKey)
    NotificationCenter.default.post(name: .homeSectionsConfigurationDidChange, object: nil)
  }

  func toggleMovieSectionVisibility(id: String) {
    setMovieSectionVisible(!isMovieSectionVisible(id), id: id)
  }

  func moveMovieSectionUp(id: String) {
    guard let idx = orderedMovieSectionIDs.firstIndex(of: id), idx > 0 else { return }
    orderedMovieSectionIDs.swapAt(idx, idx - 1)
    UserDefaults.standard.set(orderedMovieSectionIDs, forKey: orderedMovieSectionsKey)
    NotificationCenter.default.post(name: .homeSectionsConfigurationDidChange, object: nil)
  }

  func moveMovieSectionDown(id: String) {
    guard let idx = orderedMovieSectionIDs.firstIndex(of: id), idx < orderedMovieSectionIDs.count - 1 else { return }
    orderedMovieSectionIDs.swapAt(idx, idx + 1)
    UserDefaults.standard.set(orderedMovieSectionIDs, forKey: orderedMovieSectionsKey)
    NotificationCenter.default.post(name: .homeSectionsConfigurationDidChange, object: nil)
  }

  func moveMovieSections(fromOffsets source: IndexSet, toOffset destination: Int) {
    orderedMovieSectionIDs.move(fromOffsets: source, toOffset: destination)
    UserDefaults.standard.set(orderedMovieSectionIDs, forKey: orderedMovieSectionsKey)
    NotificationCenter.default.post(name: .homeSectionsConfigurationDidChange, object: nil)
  }

  func moveMovieSection(id: String, toPosition oneBasedPosition: Int) {
    guard let currentIndex = orderedMovieSectionIDs.firstIndex(of: id) else { return }
    let targetIndex = max(0, min(orderedMovieSectionIDs.count - 1, oneBasedPosition - 1))
    guard currentIndex != targetIndex else { return }
    let item = orderedMovieSectionIDs.remove(at: currentIndex)
    orderedMovieSectionIDs.insert(item, at: targetIndex)
    UserDefaults.standard.set(orderedMovieSectionIDs, forKey: orderedMovieSectionsKey)
    NotificationCenter.default.post(name: .homeSectionsConfigurationDidChange, object: nil)
  }

  // MARK: - Series Sections Visibility & Ordering

  var orderedSeriesSections: [HomeSectionMeta] {
    let byID = Dictionary(uniqueKeysWithValues: Self.allSeriesSections.map { ($0.id, $0) })
    let ordered = orderedSeriesSectionIDs.compactMap { byID[$0] }
    let missing = Self.allSeriesSections.filter { !orderedSeriesSectionIDs.contains($0.id) }
    return ordered + missing
  }

  var visibleSeriesSections: [HomeSectionMeta] {
    orderedSeriesSections.filter { isSeriesSectionVisible($0.id) }
  }

  func isSeriesSectionVisible(_ id: String) -> Bool {
    !hiddenSeriesSectionIDs.contains(id)
  }

  func setSeriesSectionVisible(_ visible: Bool, id: String) {
    if visible {
      hiddenSeriesSectionIDs.remove(id)
    } else {
      hiddenSeriesSectionIDs.insert(id)
    }
    UserDefaults.standard.set(Array(hiddenSeriesSectionIDs), forKey: hiddenSeriesSectionsKey)
    NotificationCenter.default.post(name: .homeSectionsConfigurationDidChange, object: nil)
  }

  func toggleSeriesSectionVisibility(id: String) {
    setSeriesSectionVisible(!isSeriesSectionVisible(id), id: id)
  }

  func moveSeriesSectionUp(id: String) {
    guard let idx = orderedSeriesSectionIDs.firstIndex(of: id), idx > 0 else { return }
    orderedSeriesSectionIDs.swapAt(idx, idx - 1)
    UserDefaults.standard.set(orderedSeriesSectionIDs, forKey: orderedSeriesSectionsKey)
    NotificationCenter.default.post(name: .homeSectionsConfigurationDidChange, object: nil)
  }

  func moveSeriesSectionDown(id: String) {
    guard let idx = orderedSeriesSectionIDs.firstIndex(of: id), idx < orderedSeriesSectionIDs.count - 1 else { return }
    orderedSeriesSectionIDs.swapAt(idx, idx + 1)
    UserDefaults.standard.set(orderedSeriesSectionIDs, forKey: orderedSeriesSectionsKey)
    NotificationCenter.default.post(name: .homeSectionsConfigurationDidChange, object: nil)
  }

  func moveSeriesSections(fromOffsets source: IndexSet, toOffset destination: Int) {
    orderedSeriesSectionIDs.move(fromOffsets: source, toOffset: destination)
    UserDefaults.standard.set(orderedSeriesSectionIDs, forKey: orderedSeriesSectionsKey)
    NotificationCenter.default.post(name: .homeSectionsConfigurationDidChange, object: nil)
  }

  func moveSeriesSection(id: String, toPosition oneBasedPosition: Int) {
    guard let currentIndex = orderedSeriesSectionIDs.firstIndex(of: id) else { return }
    let targetIndex = max(0, min(orderedSeriesSectionIDs.count - 1, oneBasedPosition - 1))
    guard currentIndex != targetIndex else { return }
    let item = orderedSeriesSectionIDs.remove(at: currentIndex)
    orderedSeriesSectionIDs.insert(item, at: targetIndex)
    UserDefaults.standard.set(orderedSeriesSectionIDs, forKey: orderedSeriesSectionsKey)
    NotificationCenter.default.post(name: .homeSectionsConfigurationDidChange, object: nil)
  }

  func resetToDefaults() {
    hiddenIDs = Set(Self.allBrowseTabs.filter { !$0.defaultVisible }.map(\.id))
    orderedTabIDs = Self.allBrowseTabs.map(\.id)
    hiddenHomeSectionIDs = Set(Self.allHomeSections.filter { !$0.defaultVisible }.map(\.id))
    orderedHomeSectionIDs = Self.allHomeSections.map(\.id)
    hiddenMovieSectionIDs = Set(Self.allMovieSections.filter { !$0.defaultVisible }.map(\.id))
    orderedMovieSectionIDs = Self.allMovieSections.map(\.id)
    hiddenSeriesSectionIDs = Set(Self.allSeriesSections.filter { !$0.defaultVisible }.map(\.id))
    orderedSeriesSectionIDs = Self.allSeriesSections.map(\.id)
    excludeConcertsOnHome = true

    UserDefaults.standard.removeObject(forKey: hiddenTabsKey)
    UserDefaults.standard.removeObject(forKey: orderedTabsKey)
    UserDefaults.standard.removeObject(forKey: hiddenHomeSectionsKey)
    UserDefaults.standard.removeObject(forKey: orderedHomeSectionsKey)
    UserDefaults.standard.removeObject(forKey: hiddenMovieSectionsKey)
    UserDefaults.standard.removeObject(forKey: orderedMovieSectionsKey)
    UserDefaults.standard.removeObject(forKey: hiddenSeriesSectionsKey)
    UserDefaults.standard.removeObject(forKey: orderedSeriesSectionsKey)
    UserDefaults.standard.removeObject(forKey: excludeConcertsKey)
    NotificationCenter.default.post(name: .homeSectionsConfigurationDidChange, object: nil)
  }

  // MARK: - Legacy AppSection compatibility

  static let forcedVisibleIDs: Set<String> = []

  static let librarySections: [AppSection] = {
    var items = SectionVisibilityStore.allBrowseTabs.map { AppSection(id: $0.id, titleKey: $0.titleKey) }
    items.append(AppSection(id: "watchlist", titleKey: "Watchlist"))
    items.append(AppSection(id: "history", titleKey: "History"))
    if FeatureFlags.allBookmarksEnabled {
      items.append(AppSection(id: "bookmarks", titleKey: "All Bookmarks"))
    }
    return items
  }()

  static let otherSections: [AppSection] = {
    guard FeatureFlags.downloadsEnabled else { return [] }
    return [AppSection(id: "downloads", titleKey: "Downloads")]
  }()

  func canHide(_ section: AppSection) -> Bool {
    if Self.allBrowseTabs.contains(where: { $0.id == section.id }) {
      return canHideTab(section.id)
    }
    return true
  }

  func isVisible(_ section: AppSection) -> Bool { !hiddenIDs.contains(section.id) }

  func setVisible(_ visible: Bool, for section: AppSection) {
    setTabVisible(visible, id: section.id)
  }
}

