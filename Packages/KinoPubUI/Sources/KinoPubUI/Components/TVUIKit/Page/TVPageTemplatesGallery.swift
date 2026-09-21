#if os(tvOS)
//
//  TVPageTemplatesGallery.swift
//  KinoPubUI
//
//  Every section template on one page, with sample data, so the recipe can be looked at
//  and driven on a remote without signing in or waiting on kino.pub. Reached from
//  Settings → Diagnostics → TVUIKit Gallery (DEBUG). Also the `#Preview` for the page.
//

import SwiftUI

public struct TVPageTemplatesGallery: View {
  @State private var lastSelection = "—"

  public init() {}

  public var body: some View {
    TVPage(
      sections: Self.sections,
      onSelect: { section, item in
        switch item {
        case .card(let card): lastSelection = "\(section.id): \(card.title)"
        case .person(let person): lastSelection = "\(section.id): \(person.name)"
        case .chip(let chip): lastSelection = "\(section.id): \(chip.title)"
        case .placeholder: break
        }
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

  /// The tab's sections in mockup order: Up Next (stills), poster rows, people, chips,
  /// a still grid, a skeleton row.
  public static var sections: [TVPageSection] {
    [
      .stills(id: "up-next", title: "Up Next", columns: 5, cards: stills(progress: true)),
      .posters(id: "hot", title: "Hot Movies", count: "128", columns: 6, cards: posters(seed: 0)),
      .posters(id: "fresh", title: "Fresh Series · 5 across", columns: 5, cards: posters(seed: 8)),
      .stills(id: "featured", title: "Featured · 4 across", columns: 4, cards: stills(progress: false)),
      .people(id: "cast", title: "Cast", people: people),
      .chips(id: "tags", title: "Tags", chips: chips),
      .placeholder(id: "loading", title: "Loading row", kind: .poster, columns: 6),
      .stills(id: "grid", title: "Library grid · 4 across", columns: 4, flow: .grid,
              cards: stills(progress: true) + stills(progress: false))
    ]
  }

  static func posters(seed: Int) -> [MediaCard] {
    (1...14).map { n in
      let id = seed * 100 + n
      return MediaCard(
        id: id,
        posterURL: "https://m.staticpop.net/poster/item/big/\(10581 + id).jpg",
        title: "Title \(id)",
        progress: n % 5 == 0 ? 0.4 : nil,
        isWatched: n % 7 == 0
      )
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
