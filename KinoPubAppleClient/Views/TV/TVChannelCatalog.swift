//
//  TVChannelCatalog.swift
//  KinoPubAppleClient
//
//  The whole channel grid, in the order `/v1/tv` paints it: title order, Latin names
//  first. Fifty-one channels — the list checked on 2026-10-17, which is still what the
//  tab shows. The previous bake was the sixteen at the bottom of this list (the Russian
//  block the viewport was on), so the real list arrived and shoved them down.
//
//  Logos are not in the bundle. `logo` is kino.pub's `150x150` path, which serves the
//  240×180 card; the cell letterboxes that onto 16:9. `plate` is the average of that
//  card's edge, so the tile is already the logo's background while the picture loads.
//

import Foundation
import KinoPubBackend

enum TVChannelCatalog {
  struct Entry {
    let id: Int
    let title: String
    let logoName: String
    /// Average of the logo card's edge, `RRGGBB`.
    let plate: UInt32
  }

  /// The path `/v1/tv` has been serving. The file behind it is 240×180.
  static let logoBase = "https://m.staticpop.net/channels/150x150/"

  static let entries: [Entry] = [
    Entry(id: 80, title: "CBS Sports", logoName: "cbs_sports", plate: 0x051221),
    Entry(id: 145, title: "Eleven Sports 4K", logoName: "elevensports4k", plate: 0x000000),
    Entry(id: 27, title: "ESPN 1", logoName: "espn_1", plate: 0x0D0D0D),
    Entry(id: 95, title: "ESPN 2", logoName: "espn_2", plate: 0x0E0E0E),
    Entry(id: 10, title: "Eurosport 1", logoName: "eurosport1_new", plate: 0x0E1725),
    Entry(id: 68, title: "Eurosport 2", logoName: "eurosport2_new", plate: 0x0F1624),
    Entry(id: 121, title: "Fox Sports 1", logoName: "fs1_cut", plate: 0x001230),
    Entry(id: 123, title: "Fox Sports 2", logoName: "fs2_cut", plate: 0x001534),
    Entry(id: 163, title: "MMA-TV", logoName: "mma_tv", plate: 0x070707),
    Entry(id: 92, title: "NBA TV", logoName: "nba_tv", plate: 0x060606),
    Entry(id: 75, title: "NBC Sports", logoName: "NBCSN-logo", plate: 0x000000),
    Entry(id: 89, title: "NHL Network", logoName: "nhlnetwork", plate: 0x0B0B0C),
    Entry(id: 74, title: "Premier Sports 1", logoName: "premier_sports_1", plate: 0x111111),
    Entry(id: 25, title: "Premier Sports 2", logoName: "premier_sports_2", plate: 0x101011),
    Entry(id: 13, title: "Setanta 1", logoName: "setanta_1", plate: 0x030303),
    Entry(id: 14, title: "Setanta 2", logoName: "setanta_2", plate: 0x040404),
    Entry(id: 154, title: "Setanta KZ", logoName: "setanta_kz", plate: 0x020202),
    Entry(id: 125, title: "Setanta Plus", logoName: "setanta_plus", plate: 0x020202),
    Entry(id: 109, title: "Setanta UA", logoName: "setanta_ua", plate: 0x010101),
    Entry(id: 17, title: "Sky Football", logoName: "sky_football_", plate: 0x060606),
    Entry(id: 19, title: "Sky Golf", logoName: "sky_golf", plate: 0x070707),
    Entry(id: 15, title: "Sky Main Event", logoName: "sky_main", plate: 0x0F0F0F),
    Entry(id: 181, title: "Sky Main Event 4K", logoName: "sky_main_uhd", plate: 0x0C0C0B),
    Entry(id: 16, title: "Sky Premier League", logoName: "sky_pl", plate: 0x101011),
    Entry(id: 20, title: "Sky Sports F1", logoName: "sky_f1", plate: 0x0D0D0D),
    Entry(id: 166, title: "Sky Sports F1 4K Ultra HD Formula One", logoName: "sky_f1_uhd_", plate: 0x0D0D0D),
    Entry(id: 18, title: "Sky Sports Mix", logoName: "sky_mix", plate: 0x070708),
    Entry(id: 76, title: "TNT Sport 1", logoName: "tntsports1", plate: 0x0E0E0E),
    Entry(id: 77, title: "TNT Sport 2", logoName: "tntsports2", plate: 0x0D0D0D),
    Entry(id: 78, title: "TNT Sport 3", logoName: "tntsports3", plate: 0x0D0D0D),
    Entry(id: 90, title: "TNT Sport 4", logoName: "tntsports4", plate: 0x0D0D0D),
    Entry(id: 24, title: "UFC ТВ", logoName: "ufc_tv", plate: 0x0D0F12),
    Entry(id: 11, title: "Viju Sport", logoName: "viju_sport", plate: 0x010101),
    Entry(id: 129, title: "Беларусь 5", logoName: "belarus_5", plate: 0x060A0F),
    Entry(id: 93, title: "Боец ТВ", logoName: "boets", plate: 0x05090C),
    Entry(id: 94, title: "Бокс ТВ", logoName: "box_tv", plate: 0x0C0F13),
    Entry(id: 112, title: "КХЛ", logoName: "khl_new", plate: 0x141414),
    Entry(id: 12, title: "КХЛ Prime", logoName: "khl_prime", plate: 0x181717),
    Entry(id: 4, title: "Матч Премьер", logoName: "match_premier", plate: 0x0C0C0D),
    Entry(id: 2, title: "МАТЧ! Арена", logoName: "arena3", plate: 0x070707),
    Entry(id: 3, title: "МАТЧ! Игра", logoName: "igra", plate: 0x000000),
    Entry(id: 1, title: "МАТЧ! ТВ", logoName: "match_new", plate: 0x030303),
    Entry(id: 5, title: "Матч! Футбол 1", logoName: "match_football_1", plate: 0x030103),
    Entry(id: 6, title: "Матч! Футбол 2", logoName: "match_football2", plate: 0x010201),
    Entry(id: 7, title: "Матч! Футбол 3", logoName: "match_football_3", plate: 0x000000),
    Entry(id: 172, title: "Окко Прайм", logoName: "okko_prime", plate: 0x17013D),
    Entry(id: 157, title: "Окко Спорт", logoName: "okko_sport", plate: 0x260155),
    Entry(id: 160, title: "ОККО Футбол", logoName: "okko_football", plate: 0x260154),
    Entry(id: 175, title: "Окко Чемпионат", logoName: "okko_championat", plate: 0x1E0149),
    Entry(id: 139, title: "Старт", logoName: "start_tv", plate: 0x080B0C),
    Entry(id: 127, title: "Футбол ТВ", logoName: "football_channel", plate: 0x010101)
  ]

  /// Display copies: a name, a plate and a logo URL, no stream yet. Select waits for
  /// `/v1/tv`, whose link carries the playback token.
  static var channels: [TVChannel] {
    entries.map { entry in
      TVChannel(id: entry.id, title: entry.title, name: entry.logoName,
                logo: logoBase + entry.logoName + ".png", stream: "")
    }
  }

  /// `channels` in this list's order when it is exactly this set — a server that lists
  /// the same channels differently does not reshuffle the grid. Any other set is the
  /// server's own order, returned by the caller.
  static func matching(_ channels: [TVChannel]) -> [TVChannel]? {
    let byID = Dictionary(channels.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    guard byID.count == entries.count, entries.allSatisfy({ byID[$0.id] != nil }) else { return nil }
    return entries.compactMap { byID[$0.id] }
  }

  /// `RRGGBB` of the logo's plate, or nil for a channel outside this list.
  static func plateHex(for id: Int) -> UInt32? {
    entries.first { $0.id == id }?.plate
  }
}
