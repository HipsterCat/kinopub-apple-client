#if os(tvOS)
//
//  TVPageTemplatesGallery.swift
//  KinoPubUI
//
//  Every section template on one page, with sample data, so the recipe can be looked at
//  and driven on a remote without signing in or waiting on kino.pub. Reached from
//  Settings → Diagnostics → TVUIKit Gallery (DEBUG). Also the `#Preview` for the page.
//

import CryptoKit
import SwiftUI

public struct TVPageTemplatesGallery: View {
  @State private var lastSelection = "—"

  public init() {}

  public var body: some View {
    TVPage(
      sections: Self.sections,
      // So UITests can wait for the collection itself — section header labels are not
      // reliable in the AX tree on CI runners (supplementary views often stay off-tree).
      accessibilityID: "kinopub.page.templates",
      onSelect: { section, item in
        switch item {
        case .card(let card): lastSelection = "\(section.id): \(card.title)"
        case .person(let person): lastSelection = "\(section.id): \(person.name)"
        case .chip(let chip): lastSelection = "\(section.id): \(chip.title)"
        case .tile(let tile): lastSelection = "\(section.id): \(tile.title)"
        case .feature(let feature): lastSelection = "\(section.id): \(feature.card.title)"
        case .placeholder: break
        }
      },
      contextMenuProvider: { card in
        // Sample entries so Play-Pause / long-Select can be verified without auth.
        [
          .action(MediaCardContextAction(
            id: "gallery.play.\(card.id)",
            title: "Play",
            systemImage: "play.fill",
            handler: {}
          )),
          .action(MediaCardContextAction(
            id: "gallery.info.\(card.id)",
            title: "Go to Movie",
            systemImage: "info.circle",
            handler: {}
          ))
        ]
      }
    )
    .ignoresSafeArea()
    .overlay(alignment: .bottomTrailing) {
      Text(lastSelection)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.trailing, 80)
        .padding(.bottom, 16)
    }
  }

  // MARK: - Samples

  /// Every shape the tabs are built from, in the order of the 2026-09-27 mockups
  /// (`/mnt/project-files/home-sections/draft.md`, v2), then the older samples. The
  /// point is to compare shapes on a TV side by side, so each row says what it is.
  public static var sections: [TVPageSection] {
    [
      // First, so focus starts in its middle lap the way the Home page does.
      .banner(id: "banner", features: posters(seed: 3, rated: true).prefix(6).map { TVPageFeature(card: $0) }),
      .chips(id: "filters", title: nil, chips: filters),
      .chips(id: "collection-chips", title: "Collections · chips with a mark", chips: collectionChips),
      .stills(id: "up-next", title: "Watch Next · stills with progress, 4 across", columns: 4,
              cards: stills(progress: true)),
      .posters(id: "recent", title: "Recently Added · posters with a score", columns: 6,
               caption: .always, showsRating: true, cards: posters(seed: 1, rated: true)),
      .tiles(id: "categories", title: "Categories · gradient tiles, 3 across", columns: 3,
             tiles: categoryTiles),
      .people(id: "people", title: "People · photos by name", people: photographedPeople),
      .squares(id: "festivals", title: "Festivals · square tiles", items: festivalTiles.map(TVPageItem.tile)),
      .cards(id: "anthologies", title: "Anthologies · collection cards, two deep", rows: 2,
             items: collectionCards.map(TVPageItem.card)),
      TVPageSection(id: "fan-favorites", title: "Fan Favorites · stills, two deep", kind: .still,
                    columns: 5, rows: 2, items: stills(progress: false).map(TVPageItem.card)),
      TVPageSection(id: "history", title: "Watch History · See All first", kind: .still, columns: 5,
                    items: [.tile(seeAll)] + stills(progress: true).map(TVPageItem.card)),
      .tiles(id: "genres", title: "Genres · flat tiles, 5 across", columns: 5, tiles: genreTiles),
      .posters(id: "hot", title: "Hot Movies", count: "128", columns: 6, cards: posters(seed: 0)),
      .cards(id: "top", title: "Top Results · wide cards",
             items: posters(seed: 3).prefix(2).map(TVPageItem.card)
               + people.prefix(2).map(TVPageItem.person)
               + posters(seed: 3).dropFirst(2).prefix(4).map(TVPageItem.card)),
      .posters(id: "fresh", title: "Fresh Series · 5 across", columns: 5, cards: posters(seed: 8)),
      .stills(id: "featured", title: "Featured · 4 across", columns: 4, cards: stills(progress: false)),
      .people(id: "cast", title: "Cast · monograms", people: people),
      .chips(id: "tags", title: "Tags", chips: chips),
      .placeholder(id: "loading", title: "Loading row", kind: .poster, columns: 6),
      .stills(id: "grid", title: "Library grid · 4 across", columns: 4, flow: .grid,
              cards: stills(progress: true) + stills(progress: false))
    ]
  }

  static func posters(seed: Int, rated: Bool = false) -> [MediaCard] {
    (1...14).map { n in
      let id = seed * 100 + n
      return MediaCard(
        id: id,
        posterURL: "https://m.staticpop.net/poster/item/big/\(10581 + id).jpg",
        title: "Title \(id)",
        kinopoiskRating: rated ? 5.5 + Double(n % 9) * 0.45 : nil,
        kinopoiskVotes: rated ? 1000 : nil,
        progress: n % 5 == 0 ? 0.4 : nil,
        isWatched: n % 7 == 0
      )
    }
  }

  // MARK: Mockup shapes (2026-09-27)

  /// A collection's own mark rides in the title (a flag) or as a symbol.
  static var collectionChips: [TVPageChip] {
    [
      TVPageChip(id: "korean-dramas", title: "🇰🇷 Корейские дорамы"),
      TVPageChip(id: "kp-top-250", title: "Топ-250 Кинопоиска", systemImage: "trophy"),
      TVPageChip(id: "ussr", title: "🇷🇺 Советское кино"),
      TVPageChip(id: "christmas", title: "Новогодние фильмы", systemImage: "snowflake"),
      TVPageChip(id: "marvel", title: "Кинокомиксы", systemImage: "bolt")
    ]
  }

  /// Category tiles: drawn gradient, symbol trailing, name in the caption line.
  static var categoryTiles: [TVPageTile] {
    [
      TVPageTile(id: "myths", title: "Герои мифов и фольклора", symbol: "flame"),
      TVPageTile(id: "dates", title: "Даты и события", symbol: "calendar"),
      TVPageTile(id: "kids", title: "Детское", symbol: "teddybear"),
      TVPageTile(id: "animals", title: "Животные", symbol: "pawprint"),
      TVPageTile(id: "history", title: "История", symbol: "building.columns"),
      TVPageTile(id: "sport", title: "Спорт", symbol: "figure.run"),
      TVPageTile(id: "space", title: "Фантастика и мир будущего", symbol: "sparkles")
    ]
  }

  /// Square tiles. Real collection covers are square-ish art from kino.pub's
  /// `/selection/` path; until one is wired these are drawn.
  static var festivalTiles: [TVPageTile] {
    [
      TVPageTile(id: "emmy", title: "Эмми", symbol: "trophy", tint: .systemIndigo),
      TVPageTile(id: "sundance", title: "Фестиваль Sundance", symbol: "sun.max", tint: .systemGreen),
      TVPageTile(id: "venice", title: "Золотой лев", symbol: "crown", tint: .systemOrange),
      TVPageTile(id: "globes", title: "Золотой глобус", symbol: "globe", tint: .systemGray),
      TVPageTile(id: "bafta", title: "Премия BAFTA", symbol: "theatermasks", tint: .systemPurple),
      TVPageTile(id: "cannes", title: "Золотая пальмовая ветвь", symbol: "leaf", tint: .systemYellow),
      TVPageTile(id: "oscar", title: "Премия «Оскар»", symbol: "star", tint: .systemRed)
    ]
  }

  static var genreTiles: [TVPageTile] {
    [("Боевик", "flame"), ("Комедия", "face.smiling"), ("Драма", "theatermasks"),
     ("Ужасы", "moon"), ("Фантастика", "sparkles"), ("Дорама", "heart"),
     ("Семейный", "house"), ("Аниме", "wand.and.stars")].map {
      TVPageTile(id: $0.0, title: $0.0, symbol: $0.1, style: .flat)
    }
  }

  /// Collections as cards: cover thumbnail, name, counters on the detail line.
  static var collectionCards: [MediaCard] {
    ["Рождённые в СССР: докуфильмы", "Приключения великолепной семёрки", "Kozure Okami",
     "Банда Ольсена: коллекция 1968–2001", "Освобождение: киноэпопея", "Факеры"]
      .enumerated().map { index, title in
        MediaCard(id: 9000 + index,
                  posterURL: "https://m.staticpop.net/poster/item/big/\(10700 + index).jpg",
                  title: title,
                  opensCollection: true,
                  captionStats: [.init(systemImage: "square.stack", value: "\(3 + index) фильмов"),
                                 .init(systemImage: "eye", value: "\(786 + index * 97) просмотров")])
      }
  }

  static var seeAll: TVPageTile {
    TVPageTile(id: "see-all", title: "Показать все", symbol: "clock.arrow.circlepath",
               tint: .systemGray, style: .flat)
  }

  /// kino.pub's portrait scheme: `actors/<md5 of the name as kino.pub spells it>.jpg`
  /// (the app's `ActorImageProvider`; kpapp serves the same path from `m.staticpop.net`).
  /// A name with no portrait answers 403 and the cell keeps its monogram.
  static var photographedPeople: [TVUIKitPerson] {
    ["Роберт Дауни мл.", "Райан Рейнольдс", "Том Холланд", "Дуэйн Джонсон",
     "Адам Сэндлер", "Сидни Суини", "Киану Ривз", "Марго Робби"].map { name in
      let hex = Insecure.MD5.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
      return TVUIKitPerson(id: name, name: name,
                           nameComponents: TVUIKitPerson.nameComponents(from: name),
                           caption: "Актёр",
                           photoURL: URL(string: "https://m.pushbr.com/actors/\(hex).jpg"))
    }
  }

  static func stills(progress: Bool) -> [MediaCard] {
    (1...10).map { n in
      MediaCard(
        id: 5000 + n + (progress ? 0 : 50),
        posterURL: "https://m.staticpop.net/poster/item/big/\(10600 + n).jpg",
        title: "Episode Name \(n)",
        subtitle: "S1, E\(n)",
        progress: progress && n % 2 == 0 ? Double(n) / 12 : nil,
        landscapeImageURL: "https://m.staticpop.net/poster/item/wide/\(10600 + n).jpg",
        video: n,
        durationSeconds: 42 * 60 + n * 30
      )
    }
  }

  static var people: [TVUIKitPerson] {
    ["Robert Downey Jr.", "Scarlett Johansson", "Chris Evans", "Mark Ruffalo",
     "Chris Hemsworth", "Jeremy Renner", "Tom Holland", "Paul Rudd", "Brie Larson"].map { name in
      TVUIKitPerson(id: name, name: name,
                    nameComponents: TVUIKitPerson.nameComponents(from: name),
                    caption: "Actor", photoURL: nil)
    }
  }

  /// Pull-downs, as search's sort row uses them.
  static var filters: [TVPageChip] {
    let sorts = ["Relevance", "Name", "Release Year", "IMDb Rating"]
    return [
      TVPageChip(id: "sort", title: sorts[0], systemImage: "arrow.up.arrow.down",
                 menu: .init(options: sorts.map { .init(id: $0, title: $0) }, selectedID: sorts[0])),
      TVPageChip(id: "genre", title: "Genre",
                 menu: .init(nodes: [.option(.init(id: "any", title: "Any"), isSelected: true)]
                   + ["Drama", "Comedy"].map { .option(.init(id: $0, title: $0), isSelected: false) },
                   keepsPresented: true))
    ]
  }

  static var chips: [TVPageChip] {
    ["Drama", "Thriller", "Sci-Fi", "Comedy", "Animation", "Documentary", "Horror", "Kids"].map {
      TVPageChip(id: $0, title: $0)
    }
  }
}

#Preview("Section templates") {
  TVPageTemplatesGallery()
}
#endif
