//
//  TVChannelCatalog.swift
//  Piratic
//
//  The whole channel grid, in the order `/v1/tv` paints it: title order, Latin names
//  first. Fifty-one channels — the list checked on 2026-10-17, which is still what the
//  tab shows. The previous bake was the sixteen at the bottom of this list (the Russian
//  block the viewport was on), so the real list arrived and shoved them down.
//
//  Most logos still come from kino.pub's `150x150` CDN path (240×180 card, letterboxed
//  onto 16:9). A handful ship in `PiraticUI` Media.xcassets/tv — either a full card or a
//  logo mark + focus background. `plate` is the average of the card's edge, so the tile
//  is already the logo's colour while a remote picture loads (and under a mark at rest).
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

  /// Bundled channel artwork in `Packages/PiraticUI/.../Media.xcassets/tv`.
  enum BundledLogo: Equatable, Sendable {
    /// Single imageset — mark and plate already one picture.
    case full(String)
    /// Logo mark always; focus background only while the tile is focused.
    case mark(logo: String, focusBackground: String)
  }

  /// The path `/v1/tv` has been serving. The file behind it is 240×180.
  static let logoBase = "https://m.staticpop.net/channels/150x150/"

  /// Channels that paint from the asset catalog instead of (or ahead of) the CDN URL.
  /// `.mark` stays supported for any channel later; none use it today.
  static let bundledLogos: [Int: BundledLogo] = [
    // Logo mark + focus BG (restored pair; full `cbs-sports` imageset also present).
    80: .full("cbs-sports"),
    145: .full("eleven-sports"),
    27: .full("espn"),
    95: .full("espn-2"),
    10: .full("eurosport-1"),
    68: .full("eurosport-2"),
    92: .full("nba"),
    121: .full("fox-sports-1"),
    123: .full("fox-sports-2"),
    163: .full("mma-tv"),
    75: .full("nbc-sports"),
    89: .full("nhl-network"),
    74: .full("premier-sports-1"),
    25: .full("premier-sports-2"),
    13: .full("setanta-sports-1"),
    14: .full("setanta-sports-2"),
       154: .full("setanta-sports-kz"),
       125: .full("setanta-sports-plus"),
       109: .full("setanta-sports-ua"),
       17: .full("sky-sports-football"),
       19: .full("sky-sports-golf"),
       15: .full("sky-sports-main-event"),
       181: .full("sky-sports-main-event-uhd"),
       16: .full("sky-sports-premier"),
       20: .full("sky-sports-f1"),
       166: .full("sky-sports-f1-uhd"),
       18: .full("sky-sports-mix"),
       76: .full("tnt-sports"),
       77: .full("tnt-sports-2"),
       78: .full("tnt-sports-3"),
       90: .full("tnt-sports-4"),
       24: .full("ufc"),
       11: .full("viju-sport"),
       129: .full("беларусь-5"),
       93: .full("боец"),
       94: .full("бокс-тв"),
       112: .full("khl"),
       12: .full("khl-prime"),
       4: .full("матч-премьер"),
       2: .full("матч-арена"),
       3: .full("матч-игра"),
       1: .full("матч"),
       5: .full("матч-футбол-1"),
       6: .full("матч-футбол-2"),
       7: .full("матч-футбол-3"),
       172: .full("okko-prime-спорт"),
       157: .full("okko-спорт"),
       160: .full("okko-футбол"),
       175: .full("okko-чемпионат"),
       139: .full("старт"),
       127: .full("футбол")
  ]

  static let entries: [Entry] = [
    Entry(id: 80, title: "CBS Sports", logoName: "cbs_sports", plate: 0x0049CC),
    Entry(id: 145, title: "Eleven Sports 4K", logoName: "elevensports4k", plate: 0x14283F),
    Entry(id: 27, title: "ESPN 1", logoName: "espn_1", plate: 0xCD232D),
    Entry(id: 95, title: "ESPN 2", logoName: "espn_2", plate: 0xCD232D),
    Entry(id: 10, title: "Eurosport 1", logoName: "eurosport1_new", plate: 0x152481),
    Entry(id: 68, title: "Eurosport 2", logoName: "eurosport2_new", plate: 0x152481),
    Entry(id: 121, title: "Fox Sports 1", logoName: "fs1_cut", plate: 0x011A38),
    Entry(id: 123, title: "Fox Sports 2", logoName: "fs2_cut", plate: 0x182D4C),
    Entry(id: 163, title: "MMA-TV", logoName: "mma_tv", plate: 0x000000),
    Entry(id: 92, title: "NBA TV", logoName: "nba_tv", plate: 0xC80F2E),
    Entry(id: 75, title: "NBC Sports", logoName: "NBCSN-logo", plate: 0x0580CB),
    Entry(id: 89, title: "NHL Network", logoName: "nhlnetwork", plate: 0x0B0B0C),
    Entry(id: 74, title: "Premier Sports 1", logoName: "premier_sports_1", plate: 0xFFFF00),
    Entry(id: 25, title: "Premier Sports 2", logoName: "premier_sports_2", plate: 0xFFFF00),
    Entry(id: 13, title: "Setanta Sports 1", logoName: "setanta_1", plate: 0xFFD207),
    Entry(id: 14, title: "Setanta Sports 2", logoName: "setanta_2", plate: 0xFFD207),
    Entry(id: 154, title: "Setanta Казахстан", logoName: "setanta_kz", plate: 0xFFD207),
    Entry(id: 125, title: "Setanta Plus", logoName: "setanta_plus", plate: 0xFFD207),
    Entry(id: 109, title: "Setanta Украина", logoName: "setanta_ua", plate: 0xFFD207),
    Entry(id: 17, title: "Sky Sports Football", logoName: "sky_football_", plate: 0x0148E3),
    Entry(id: 19, title: "Sky Sports Golf", logoName: "sky_golf", plate: 0x0148E3),
    Entry(id: 15, title: "Sky Sports Main Event", logoName: "sky_main", plate: 0x0148E3),
    Entry(id: 181, title: "Sky Sports Main Event 4K UHD", logoName: "sky_main_uhd", plate: 0x0148E3),
    Entry(id: 16, title: "Sky Sports Premier League", logoName: "sky_pl", plate: 0x0148E3),
    Entry(id: 20, title: "Sky Sports F1", logoName: "sky_f1", plate: 0x0148E3),
    Entry(id: 166, title: "Sky Sports F1 4K Ultra HD", logoName: "sky_f1_uhd_", plate: 0x0148E3),
    Entry(id: 18, title: "Sky Sports Mix", logoName: "sky_mix", plate: 0x0148E3),
    Entry(id: 76, title: "TNT Sports 1", logoName: "tntsports1", plate: 0x2B2340),
    Entry(id: 77, title: "TNT Sports 2", logoName: "tntsports2", plate: 0x2B2340),
    Entry(id: 78, title: "TNT Sports 3", logoName: "tntsports3", plate: 0x2B2340),
    Entry(id: 90, title: "TNT Sports 4", logoName: "tntsports4", plate: 0x2B2340),
    Entry(id: 24, title: "UFC ТВ", logoName: "ufc_tv", plate: 0xD20A0A),
    Entry(id: 11, title: "Viju Sport", logoName: "viju_sport", plate: 0x372FFF),
    Entry(id: 129, title: "Беларусь 5", logoName: "belarus_5", plate: 0x2E7B2C),
    Entry(id: 93, title: "Боец ТВ", logoName: "boets", plate: 0xAA0D01),
    Entry(id: 94, title: "Бокс ТВ", logoName: "box_tv", plate: 0xEB2B32),
    Entry(id: 112, title: "КХЛ", logoName: "khl_new", plate: 0x6F6F6F),
    Entry(id: 12, title: "КХЛ Prime", logoName: "khl_prime", plate: 0x4E4E4E),
    Entry(id: 4, title: "Матч! Премьер", logoName: "match_premier", plate: 0x282B2F),
    Entry(id: 2, title: "Матч! Арена", logoName: "arena3", plate: 0x9A1E30),
    Entry(id: 3, title: "Матч! Игра", logoName: "igra", plate: 0x993101),
    Entry(id: 1, title: "Матч! ТВ", logoName: "match_new", plate: 0x580000),
    Entry(id: 5, title: "Матч! Футбол 1", logoName: "match_football_1", plate: 0x1E1E1E),
    Entry(id: 6, title: "Матч! Футбол 2", logoName: "match_football2", plate: 0x1E1E1E),
    Entry(id: 7, title: "Матч! Футбол 3", logoName: "match_football_3", plate: 0x1E1E1E),
    Entry(id: 157, title: "Okko Спорт", logoName: "okko_sport", plate: 0x080733),
    Entry(id: 172, title: "Okko Прайм Спорт", logoName: "okko_prime", plate: 0x161E55),
    Entry(id: 160, title: "Okko Футбол", logoName: "okko_football", plate: 0x110C60),
    Entry(id: 175, title: "Okko Чемпионат", logoName: "okko_championat", plate: 0x012B94),
    Entry(id: 139, title: "Старт", logoName: "start_tv", plate: 0x421000),
    Entry(id: 127, title: "Футбол ТВ", logoName: "football_channel", plate: 0x040405)
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

  /// Bundled artwork for `id`, when the asset catalog has one.
  static func bundledLogo(for id: Int) -> BundledLogo? {
    bundledLogos[id]
  }
}
