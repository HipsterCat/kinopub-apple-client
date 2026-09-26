//
//  CatalogPopularity.swift
//  KinoPubBackend
//
//  Orders kino.pub has no endpoint for, measured once and written down (2026-09-26):
//  countries as kino.pub's own web filter lists them, genres by how many titles each
//  holds within its set (`/v1/items?type=…&genre=…` total_items). Code, not a bundled
//  JSON — a resource that failed to load quietly fell back to A–Z.
//

import Foundation

public enum CountryPopularity {
  public static let order: [String] = [
    "США",
    "Россия",
    "СССР",
    "Великобритания",
    "Япония",
    "Германия",
    "Китай",
    "Франция",
    "Испания",
    "Австралия",
    "Нидерланды",
    "Норвегия",
    "Польша",
    "Канада",
    "Новая Зеландия",
    "Австрия",
    "Гонконг",
    "Мексика",
    "Италия",
    "Ирландия",
    "Дания",
    "Швеция",
    "Украина",
    "Израиль",
    "Люксембург",
    "Швейцария",
    "Бельгия",
    "ЮАР",
    "Сингапур",
    "Турция",
    "Словения",
    "Венгрия",
    "Румыния",
    "Южная Корея",
    "Хорватия",
    "Таиланд",
    "Финляндия",
    "Индия",
    "Иран",
    "Исландия",
    "Аргентина",
    "Болгария",
    "Куба",
    "Латвия",
    "Литва",
    "Эстония",
    "Беларусь",
    "Малайзия",
    "Индонезия",
    "Бразилия",
    "Сербия",
    "Черногория",
    "Македония",
    "Чехословакия",
    "Армения",
    "Грузия",
    "Филиппины",
    "Чили",
    "Тунис",
    "Уругвай",
    "Югославия",
    "Чехия",
    "ОАЭ",
    "Казахстан",
    "Греция",
    "Вьетнам",
    "Венесуэла",
    "Тайвань",
    "Афганистан",
    "Багамы",
    "Ботсвана",
    "Египет",
    "Молдова",
    "Перу",
    "Саудовская Аравия",
    "Словакия",
    "Мадагаскар",
    "Боливия",
    "Азербайджан",
    "Северная Корея",
    "Босния-Герцеговина",
    "Албания",
    "Буркина-Фасо",
    "Пакистан",
    "Португалия",
    "Марокко",
    "Кипр",
    "Гана",
    "Алжир",
    "Мальта",
    "Шотландия",
    "Ливия",
    "Ливан",
    "Кувейт",
    "Мавритания",
    "Панама",
    "Коста-Рика",
    "Колумбия",
    "Монголия",
    "Непал",
    "Узбекистан",
    "Нигерия",
  ]

  private static let rank: [String: Int] = Dictionary(order.enumerated().map { ($1, $0) },
                                                      uniquingKeysWith: { first, _ in first })

  /// kino.pub's order; countries it does not list follow, A–Z.
  public static func sorted(_ countries: [Country]) -> [Country] {
    countries.sorted { a, b in
      switch (rank[a.title], rank[b.title]) {
      case let (x?, y?): return x < y
      case (_?, nil): return true
      case (nil, _?): return false
      default: return a.title.localizedStandardCompare(b.title) == .orderedAscending
      }
    }
  }
}

public enum GenrePopularity {
  /// Genre ids per set, most titles first.
  public static let order: [GenreKind: [Int]] = [
    .movie: [9, 1, 7, 10, 2, 17, 8, 5, 23, 13, 4, 6, 12, 128, 18, 25, 3, 19, 15, 26, 20, 14, 101, 21, 24, 27, 107, 105, 11, 116],
    .docu: [51, 133, 78, 73, 58, 83, 70, 77, 71, 63, 56, 82, 54, 57, 55, 52, 68, 59, 60, 61, 85, 66, 53, 93, 87, 64, 72, 79, 65, 74, 69, 81, 62, 122, 90, 88, 84, 80, 98, 104, 86, 91, 75, 76, 92, 67],
    .tvshow: [110, 114, 111, 112, 113, 123, 124],
    .music: [47, 44, 30, 50, 36, 39, 120, 45, 34, 40, 31, 119, 118, 99, 37, 32, 48, 100, 121, 49, 33, 43, 38, 103, 46, 109, 102, 42, 41, 35, 117],
  ]

  private static let rank: [Int: Int] = Dictionary(order.values.flatMap { $0.enumerated().map { ($1, $0) } },
                                                   uniquingKeysWith: { first, _ in first })

  /// Largest first within a set; unknown genres last, A–Z.
  public static func sorted(_ genres: [MediaGenre]) -> [MediaGenre] {
    genres.sorted { a, b in
      switch (rank[a.id], rank[b.id]) {
      case let (x?, y?): return x < y
      case (_?, nil): return true
      case (nil, _?): return false
      default: return a.title.localizedStandardCompare(b.title) == .orderedAscending
      }
    }
  }
}
