//
//  TVChannelsFixture.swift
//  KinoPubAppleClient
//

#if DEBUG && os(tvOS)
import SwiftUI
import KinoPubUI
import KinoPubBackend

/// `-KINOPUBTVChannelsFixture YES`: the TV tab as a signed-in account has it — the real
/// page under a tab bar — on a stand-in API that lists the channels below, and the
/// stand-in player (`DetailFixturePlayer`) behind Select. No session, no stream.
///
/// Logos are drawn plates unless `-KINOPUBFixtureRealArt YES`, which takes each channel's
/// card from kino.pub's CDN, as `/v1/tv` sends it (240×180, the mark on its own colour).
enum TVChannelsFixture {
  static var isActive: Bool { DebugLaunch.tvChannelsFixture }

  static func context(replacingServicesOf base: AppContext) -> AppContext {
    var context = base
    context.contentService = VideoContentServiceMock(tvChannels: { channels })
    return context
  }

  /// A guide for every other channel: an hour-long programme on air now, so the grid shows
  /// tiles with a second line and tiles without, as the real guide leaves some channels out.
  static let guide = EPGServiceMock { channels in
    let now = Date()
    var schedules: [Int: [EPGProgram]] = [:]
    for (index, channel) in channels.enumerated() where index.isMultiple(of: 2) {
      let title = index == 4 ? "Футбол. Чемпионат Италии. Серия А. Интер – Ювентус. Прямая трансляция"
                             : "Программа на \(channel.title)"
      schedules[channel.id] = [EPGProgram(title: title, start: now.addingTimeInterval(-1_200),
                                          stop: now.addingTimeInterval(2_400))]
    }
    return schedules
  }

  /// Apple's public HLS sample, for `-KINOPUBFixtureRealPlayer`: a stream anyone can open.
  static let sampleStream =
    "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8"

  /// A slice of what `/v1/tv` answered on 2026-10-17: names in both scripts, one long
  /// enough to need two lines, logos with a gradient behind the mark (Окко) and flat ones.
  static var channels: [TVChannel] {
    let rows: [(id: Int, title: String, logo: String)] = [
      (1, "МАТЧ! ТВ", "match_new"), (2, "МАТЧ! Арена", "arena3"), (3, "МАТЧ! Игра", "igra"),
      (4, "Матч Премьер", "match_premier"), (5, "Матч! Футбол 1", "match_football_1"),
      (6, "Матч! Футбол 2", "match_football2"), (7, "Матч! Футбол 3", "match_football_3"),
      (12, "КХЛ Prime", "khl_prime"), (112, "КХЛ", "khl_new"), (157, "Окко Спорт", "okko_sport"),
      (160, "ОККО Футбол", "okko_football"), (172, "Окко Прайм", "okko_prime"),
      (175, "Окко Чемпионат", "okko_championat"), (139, "Старт", "start_tv"),
      (127, "Футбол ТВ", "football_channel"), (93, "Боец ТВ", "boets"), (94, "Бокс ТВ", "box_tv"),
      (129, "Беларусь 5", "belarus_5"), (80, "CBS Sports", "cbs_sports"),
      (145, "Eleven Sports 4K", "elevensports4k"), (27, "ESPN 1", "espn_1"), (95, "ESPN 2", "espn_2"),
      (10, "Eurosport 1", "eurosport1_new"), (68, "Eurosport 2", "eurosport2_new"),
      (121, "Fox Sports 1", "fs1_cut"), (123, "Fox Sports 2", "fs2_cut"), (163, "MMA-TV", "mma_tv"),
      (92, "NBA TV", "nba_tv"), (75, "NBC Sports", "NBCSN-logo"), (89, "NHL Network", "nhlnetwork"),
      (74, "Premier Sports 1", "premier_sports_1"), (25, "Premier Sports 2", "premier_sports_2"),
      (13, "Setanta 1", "setanta_1"), (14, "Setanta 2", "setanta_2"), (17, "Sky Football", "sky_football_"),
      (19, "Sky Golf", "sky_golf"), (15, "Sky Main Event", "sky_main"),
      (16, "Sky Premier League", "sky_pl"), (20, "Sky Sports F1", "sky_f1"),
      (166, "Sky Sports F1 4K Ultra HD Formula One", "sky_f1_uhd_"), (18, "Sky Sports Mix", "sky_mix"),
      (76, "TNT Sport 1", "tntsports1"), (77, "TNT Sport 2", "tntsports2"),
      (24, "UFC ТВ", "ufc_tv"), (11, "Viju Sport", "viju_sport")
    ]
    return rows.map { row in
      TVChannel(id: row.id, title: row.title, name: row.logo,
                logo: DebugLaunch.fixtureRealArt
                  ? "https://m.staticpop.net/channels/150x150/\(row.logo).png" : nil,
                stream: DebugLaunch.fixtureRealPlayer
                  ? sampleStream : "https://fixture.invalid/\(row.logo)/index.m3u8")
    }
  }
}

/// The real TV tab beside a Watch Now stand-in, in production's `.tabBarOnly` bar, so Up
/// from the grid reaches the bar and Left / Right there leave the tab and come back.
struct TVChannelsFixtureRoot: View {
  @Environment(NavigationState.self) private var navigationState
  @Environment(\.appContext) private var appContext

  var body: some View {
    @Bindable var navigationState = navigationState
    TabView(selection: $navigationState.selectedTab) {
      Tab(value: NavigationTabs.home) { Color.clear } label: { Text("Watch Now") }
      Tab(value: NavigationTabs.tv) {
        TVChannelsView(model: TVChannelsModel(contentService: appContext.contentService,
                                              epgService: TVChannelsFixture.guide))
      } label: { Text("TV") }
    }
    .tabViewStyle(.tabBarOnly)
    .onAppear { navigationState.selectedTab = .tv }
  }
}
#endif
