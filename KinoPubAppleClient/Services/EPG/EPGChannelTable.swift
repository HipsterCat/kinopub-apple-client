//
//  EPGChannelTable.swift
//  KinoPubAppleClient
//
//  Which epg.pw channel carries each kino.pub channel's schedule, by kino.pub channel id —
//  the id `/v1/tv` sends, which does not change when a channel is renamed. Every entry was
//  checked against epg.pw on 2026-10-17 (a schedule came back). The guide has nothing for
//  Eleven Sports 4K (145), MMA-TV (163), NBC Sports (75) and UFC ТВ (24); the 4K copies of
//  Sky channels show their HD channel's schedule.
//

enum EPGChannelTable {
  static let epgPW: [Int: String] = [
    1: "5755",      // МАТЧ! ТВ — «Матч! HD»
    2: "6273",      // МАТЧ! Арена
    3: "6779",      // МАТЧ! Игра
    4: "6208",      // Матч Премьер
    5: "6152",      // Матч! Футбол 1
    6: "6150",      // Матч! Футбол 2
    7: "6151",      // Матч! Футбол 3
    10: "6819",     // Eurosport 1
    11: "6517",     // Viju Sport — «Viju+ Sport»
    12: "7112",     // КХЛ Prime — «КХЛ HD»
    13: "62227",    // Setanta 1 — «Setanta Sports 1 KZ»
    14: "62234",    // Setanta 2 — «Setanta Sports 2 KZ»
    15: "7673",     // Sky Main Event
    16: "6958",     // Sky Premier League
    17: "450289",   // Sky Football
    18: "6553",     // Sky Sports Mix
    19: "538884",   // Sky Golf
    20: "6317",     // Sky Sports F1
    25: "219104",   // Premier Sports 2
    27: "465198",   // ESPN 1 — «ESPN HD»
    68: "44879",    // Eurosport 2
    74: "219100",   // Premier Sports 1
    76: "400477",   // TNT Sport 1
    77: "400480",   // TNT Sport 2
    78: "400479",   // TNT Sport 3
    80: "464937",   // CBS Sports — «CBS Sports Network HD»
    89: "465348",   // NHL Network
    90: "400478",   // TNT Sport 4
    92: "464912",   // NBA TV
    93: "6577",     // Боец ТВ — «Матч! Боец»
    94: "7749",     // Бокс ТВ
    95: "465373",   // ESPN 2
    109: "392163",  // Setanta UA — «Setanta Украина»
    112: "6543",    // КХЛ — «КХЛ ТВ»
    121: "465248",  // Fox Sports 1 — «FS1 HD»
    123: "465280",  // Fox Sports 2 — «FS2 HD»
    125: "325011",  // Setanta Plus — «Setanta Sports+»
    127: "7573",    // Футбол ТВ — «Футбол»
    129: "7836",    // Беларусь 5
    139: "368872",  // Старт
    154: "6159",    // Setanta KZ — «Setanta Казахстан»
    157: "6698",    // Окко Спорт
    160: "387776",  // ОККО Футбол
    166: "6317",    // Sky Sports F1 4K — the HD channel's schedule
    172: "428603",  // Окко Прайм — «Окко.Прайм Спорт»
    175: "480375",  // Окко Чемпионат
    181: "7673"     // Sky Main Event 4K — the HD channel's schedule
  ]
}
