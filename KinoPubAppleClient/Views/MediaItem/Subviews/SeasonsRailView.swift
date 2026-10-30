//
//  SeasonsRailView.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubUI
import KinoPubBackend
import KinoPubMetadata
import KinoPubMedia

/// Season tabs over one continuous horizontal rail of every episode in the series —
/// S1E1 through the finale — the way the Apple TV app presents a show. Tabs scroll the
/// rail to that season's first episode rather than swapping the content out. Opens
/// scrolled to the first unfinished episode.
///
/// The tabs are «Сезон» and a stop per season, numbers only. Past kino.pub's last season
/// the tabs carry what the rail's trailing cards carry — a clock for the announced season,
/// a lock for the run of seasons kino.pub lacks («4–7») — and selecting one scrolls the
/// rail to its card, as selecting a season scrolls to its first episode.
///
/// tvOS: tabs and rail are one TVUIKit controller, `TVSeasonRail` — the tabs are system
/// list cells, and where the remote lands between hero, tabs and episodes is decided
/// there (see its header). It opens on the episode the hero's main button plays.
/// iOS / macOS: `SeasonTabStrip` over a SwiftUI rail.
///
/// DESIGN: season-level "clear progress" → `UserActionsService.clearHistoryForSeason`
/// (`POST /v1/history/clear-for-season`). Episode hide/toggle-watched stay as they are.
struct SeasonsRailView: View {

  let seasons: [Season]
  let linkProvider: NavigationLinkProvider
  /// Filled into every episode handed to the player, so its transport bar can show the
  /// series name rather than just the episode's own title.
  let seriesTitle: String
  /// False while the hero/trailer is up — season tabs stay out of the way.
  var showsChrome: Bool = true
  /// The episode the hero's main button plays (`MediaItem.primaryEpisode`): where the rail
  /// opens and where Down from the hero lands. Read on tvOS.
  var openingEpisodeID: Int? = nil
  /// The next episode has a date. With everything watched the rail then stands on the
  /// last episode watched, not on the first one Replay would play (Sasha, 2026-10-11).
  /// Read on tvOS.
  var awaitsNextEpisode: Bool = false
  /// Pressing an episode there is nothing to play for — the page turns the message and
  /// its glyph (a clock for "not out yet", a lock for "not on kino.pub") into a toast.
  var onUnavailableSelected: ((_ message: String, _ systemImage: String) -> Void)? = nil
  var onHide: ((Episode, Season) -> Void)?
  var onToggleWatched: ((Episode, Season) -> Void)?
  /// Full TMDB season schedules keyed by season number — used to date kino episodes
  /// and to inject episodes that exist on TMDB but not yet on kino.pub.
  var seasonSchedules: [Int: [EpisodeSchedule]] = [:]
  /// Title-level metadata: drives the trailing missing/upcoming-season cards.
  var externalMetadata: TitleMetadata = TitleMetadata()
  /// The series' own backdrop: the picture of an episode that has no still of its own
  /// yet (announced, or not on kino.pub) instead of an empty plate (Sasha, 2026-10-30).
  var seriesBackdropURL: URL? = nil
  /// Ask the model to fetch schedule for a season number (kino.pub season.number).
  var onSeasonVisible: ((Int) -> Void)? = nil

  @Environment(ErrorHandler.self) private var errorHandler
  @Environment(NavigationState.self) private var navigationState
  @Environment(\.openURL) private var openURL
  @Environment(\.dynamicTypeSize) private var typeSize
#if os(tvOS)
  /// The UIKit rail can't host a `NavigationLink`, so playback is pushed through the
  /// same environment hook `MediaPosterShelf`'s TVUIKit rails use.
  @Environment(\.mediaNavigation) private var mediaNavigation
#endif
  @StateObject private var cardMenu = MediaCardMenuCoordinator()
  /// Measured rail width, so cards land on the same `ShelfMetrics` grid as every
  /// other landscape shelf (Continue Watching, History) rather than a fixed size.
  @State private var railWidth: CGFloat = SeasonsRailView.referenceWidth
  /// The selected `SeasonTab.id`: a `Season.id`, or the id of a trailing card.
  @State private var selectedTabID: Int?
  /// The episode `defaultFocus`/scroll should land on for the *currently selected*
  /// tab. Regressed in `38c6d07` ("Episodes and seasons rail"): the original
  /// `c1bd46f` scrolled straight to the first-unseen episode's own anchor; that commit
  /// routed the initial jump through the tab picker, which only ever knew "that
  /// season's first episode" — so resuming a show mid-season correctly picked the right
  /// *season* tab but always landed on its episode 1. Tracked separately from
  /// `selectedTabID` because manual tab clicks/switches still want "season's first
  /// episode" (unchanged), only the initial resume jump wants the specific episode.
  @State private var seasonEntryEpisodeID: Int?
  @State private var didScrollToUnseen = false
  /// True while a tab-driven scroll is in flight, so a stray episode focus update
  /// doesn't yank the selected tab back mid-jump.
  @State private var isScrollingFromTab = false

  private enum RailEntry: Identifiable {
    case playable(season: Season, episode: Episode, schedule: EpisodeSchedule?)
    /// On TMDB but not on kino.pub: announced, or aired and not uploaded — sometimes
    /// years ago. `MissingEpisodeAirState` says which.
    case unavailable(season: Season, schedule: EpisodeSchedule)
    /// Whole seasons between kino.pub's last and the next announced one — one dark
    /// info card instead of a row of untappable tabs.
    case missingSeasons(from: Int, to: Int, episodes: Int?, firstAir: Date?, lastAir: Date?)
    /// The next season with a known premiere date, ahead of everything kino.pub has.
    case upcomingSeason(number: Int, date: Date, poster: URL?)

    var id: Int {
      switch self {
      case .playable(_, let episode, _):
        return episode.id
      case .unavailable(let season, let schedule):
        // Negative synthetic id — outside kino.pub's positive media ids.
        return -(season.number * 1_000_000 + schedule.episodeNumber)
      case .missingSeasons(let from, let to, _, _, _):
        return -(2_000_000_000 + from * 1_000 + to)
      case .upcomingSeason(let number, _, _):
        return -(2_100_000_000 + number)
      }
    }

    var season: Season? {
      switch self {
      case .playable(let season, _, _), .unavailable(let season, _):
        return season
      case .missingSeasons, .upcomingSeason:
        return nil
      }
    }

    /// The `SeasonTab` the entry sits under: its season's. The trailing cards are seasons
    /// of their own, and stand for themselves.
    var tabID: Int { season?.id ?? id }

    var episodeNumber: Int {
      switch self {
      case .playable(_, let episode, _): return episode.number
      case .unavailable(_, let schedule): return schedule.episodeNumber
      case .missingSeasons, .upcomingSeason: return .max
      }
    }

    var schedule: EpisodeSchedule? {
      switch self {
      case .playable(_, _, let schedule): return schedule
      case .unavailable(_, let schedule): return schedule
      case .missingSeasons, .upcomingSeason: return nil
      }
    }

    var isPlayable: Bool {
      if case .playable = self { return true }
      return false
    }
  }

  private var entries: [RailEntry] {
    let episodeEntries = seasons.flatMap { season -> [RailEntry] in
      let tmdb = seasonSchedules[season.number] ?? []
      let byNumber = Dictionary(uniqueKeysWithValues: tmdb.map { ($0.episodeNumber, $0) })
      let kinoNumbers = Set(season.episodes.map(\.number))

      var result: [RailEntry] = season.episodes.map { episode in
        .playable(season: season, episode: episode, schedule: byNumber[episode.number])
      }

      // Episodes TMDB knows about that kino.pub hasn't uploaded yet.
      let extras = tmdb
        .filter { !kinoNumbers.contains($0.episodeNumber) }
        .sorted { $0.episodeNumber < $1.episodeNumber }
        .map { RailEntry.unavailable(season: season, schedule: $0) }

      result.append(contentsOf: extras)
      result.sort { $0.episodeNumber < $1.episodeNumber }
      return result
    }
    return episodeEntries + trailingCards
  }

  /// What sits past kino.pub's last season: skipped seasons as one dark card, then
  /// the announced season with its premiere date — never as dead season tabs.
  private var trailingCards: [RailEntry] {
    guard let lastKino = seasons.last,
          let next = externalMetadata.nextEpisode,
          let date = next.airDate, date > Date(),
          next.seasonNumber > (lastKino.titleSeasonNumber ?? lastKino.number)
    else { return [] }

    let lastKinoNumber = lastKino.titleSeasonNumber ?? lastKino.number
    var cards: [RailEntry] = []

    let gap = externalMetadata.seasonSummaries
      .filter { $0.seasonNumber > lastKinoNumber && $0.seasonNumber < next.seasonNumber }
    if let first = gap.first, let last = gap.last {
      let episodes = gap.reduce(0) { $0 + ($1.episodeCount ?? 0) }
      cards.append(.missingSeasons(from: first.seasonNumber,
                                   to: last.seasonNumber,
                                   episodes: episodes > 0 ? episodes : nil,
                                   firstAir: first.airDate,
                                   lastAir: last.airDate))
    }

    let poster = externalMetadata.seasonSummaries
      .first { $0.seasonNumber == next.seasonNumber }?.poster
    cards.append(.upcomingSeason(number: next.seasonNumber, date: date, poster: poster))
    return cards
  }

  /// Every season kino.pub has, then what the rail's trailing cards stand for: the run of
  /// seasons it lacks («4–7», one tab however many) and the announced one. The strip and
  /// the rail read the same `trailingCards`, so a tab always has a card to scroll to.
  private var tabs: [SeasonTab] {
    // The number, never the name: kino.pub's titles («Сезон 14», or none) are not drawn here,
    // and its re-numbering from 1 must not sit beside TMDB's numbers on the trailing tabs.
    let kino = seasons.map { season -> SeasonTab in
      let number = KinoPubMediaMapping.seasonNumber(season)
      return SeasonTab(id: season.id, first: number, last: number, status: .available)
    }
    let beyond = trailingCards.compactMap { entry -> SeasonTab? in
      switch entry {
      case .missingSeasons(let from, let to, _, _, _):
        return SeasonTab(id: entry.id, first: from, last: to, status: .unavailable)
      case .upcomingSeason(let number, _, _):
        return SeasonTab(id: entry.id, first: number, last: number, status: .soon)
      case .playable, .unavailable:
        return nil
      }
    }
    return kino + beyond
  }

  private var selectedTab: SeasonTab? {
    tabs.first { $0.id == selectedTabID } ?? tabs.first
  }

  // MARK: - Metrics (shared with every other landscape shelf)

  private var metrics: ShelfMetrics {
    .landscape(width: railWidth, typeSize: typeSize)
  }

  private var cardWidth: CGFloat {
    metrics.cardWidth(in: railWidth)
  }

  /// The title page's side margin, the one the hero and every section under it start at.
  /// The shelf grid's own (40 pt on a Mac) put the seasons and episodes further right
  /// than everything else on the page (Sasha, 2026-10-30).
  private var pageInset: CGFloat { MediaItemLayout.horizontalInset }

  private var stillHeight: CGFloat {
    cardWidth / CardAspect.landscape.ratio
  }

  /// First unfinished playable episode walking seasons in order, else the very first rail item.
  /// First unfinished episode that is actually **watchable** — an unaired one is
  /// skipped. Landing the opening scroll on a future episode put the rail somewhere
  /// with nothing playable to the left of it and no visible context, which reads as
  /// the rail being broken rather than as "you're up to date".
  private var firstUnseen: RailEntry? {
    entries.first {
      guard case .playable(_, let episode, let schedule) = $0 else { return false }
      // Unwatched is `-1` on the payload, not `0`. Matching only zero sent a series
      // nobody had started to its last episode.
      return !episode.isWatched && schedule?.isUpcoming != true
    }
    ?? entries.first { $0.isPlayable }
    ?? entries.first
  }

  /// Rail item to land on when Down crosses from the season tabs into the rail — the
  /// tracked resume/entry episode when there is one, else the selected tab's first (its
  /// season's first episode, or its trailing card).
  private var entryItemForSelectedTab: Int? {
    if let seasonEntryEpisodeID, entries.contains(where: { $0.id == seasonEntryEpisodeID }) {
      return seasonEntryEpisodeID
    }
    if let selectedTabID,
       let first = entries.first(where: { $0.tabID == selectedTabID }) {
      return first.id
    }
    return entries.first?.id
  }

  var body: some View {
#if os(tvOS)
    // Tabs and episodes are one UIKit controller on tvOS: where the remote lands between
    // the hero, the tabs and the rail is the focus engine's call (`TVSeasonRail`).
    seasonRail
      .task {
        cardMenu.bind(errorHandler: errorHandler)
        await cardMenu.refreshFolders()
      }
      .mediaCardNewFolderAlert(cardMenu)
#else
    ScrollViewReader { proxy in
      VStack(alignment: .leading, spacing: showsChrome ? Self.stripToRailSpacing : 0) {
        // The line is there for one season too — «Сезон 1», nothing to press and exactly
        // as tall as with pills, so the rail does not jump between titles. A lone *pill*
        // would be an empty focus stop on the way up out of the rail; the strip draws
        // none for one season.
        if showsChrome {
          SeasonTabStrip(tabs: tabs,
                         selectedID: selectedTab?.id,
                         inset: pageInset,
                         onSelect: { tab in pick(tab, proxy: proxy) })
            .transition(.opacity)
        }

        episodeRail
      }
      .animation(.easeOut(duration: 0.25), value: showsChrome)
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.size.width
      } action: { width in
        if width > 0 { railWidth = width }
      }
      .onAppear {
        if selectedTabID == nil {
          selectedTabID = firstUnseen?.tabID ?? tabs.first?.id
        }
      }
      // Keyed on the rail's contents, not fired once on appear: the detail payload and
      // the TMDB schedules land *after* this view first renders, so a plain `.task` ran
      // against an empty `entries`, bailed, and never came back — leaving the opening
      // position to whatever the collection view happened to do.
      .task(id: entries.map(\.id)) {
        await scrollToFirstUnseen(proxy: proxy)
      }
      .task {
        cardMenu.bind(errorHandler: errorHandler)
        await cardMenu.refreshFolders()
      }
      .mediaCardNewFolderAlert(cardMenu)
    }
#endif
  }

  // MARK: - Season tabs

  /// A pill was pressed. The selected one too: it takes the rail back to the start of its
  /// season (Sasha, 2026-10-30).
  private func pick(_ tab: SeasonTab, proxy: ScrollViewProxy) {
    selectTab(tab.id, proxy: proxy, animated: true)
  }

  // MARK: - Episode rail

#if os(tvOS)
  /// The season tabs and the episodes, as one TVUIKit controller (`TVSeasonRail`). The
  /// episodes are the **same component** as Continue Watching — the system's wide
  /// media-item cell on Home's still row — because it is literally the same tile in the
  /// product ("keep watching this episode" and "here are the episodes").
  ///
  /// Everything the SwiftUI strip drew by hand is a property on the configuration or a
  /// case of `TVUIKitMediaItemStatus` — progress, watched, unaired, announced-with-a-date
  /// — which is why the five states were modelled there in the first place.
  private var seasonRail: some View {
    let entries = entries
    let tabs = tabs
    return TVSeasonRail(
      title: seasonTitle(tabs: tabs),
      tabs: tabs.map { tab in
        TVSeasonTab(id: tab.id, label: tab.label, symbol: tab.status.symbol,
                    isAvailable: tab.status == .available, accessibilityLabel: tab.spokenLabel)
      },
      items: entries.map(railItem(for:)),
      tabOfItem: Dictionary(entries.map { ($0.id, $0.tabID) }, uniquingKeysWith: { first, _ in first }),
      entryByTab: Self.entryByTab(entries),
      openingItemID: openingEntry(in: entries)?.id,
      contentInset: TVHIGGrid.sideInset,
      // Home's still row, size and all (Sasha, 2026-10-04).
      columns: MainView.stillColumns,
      onSelect: { id in select(entryID: id) },
      onTabSelected: { id in
        // Only a season kino.pub has can be asked about: there is no schedule to fetch
        // for a number it does not carry.
        if let season = seasons.first(where: { $0.id == id }) {
          onSeasonVisible?(season.number)
        }
      },
      contextMenuProvider: { id in
        guard case .playable(let season, let episode, _)? = entries.first(where: { $0.id == id })
        else { return [] }
        return contextEntries(for: episode, season: season)
      }
    )
  }

  /// «Сезон» before the tabs; one season is not a choice, so its line says which.
  private func seasonTitle(tabs: [SeasonTab]) -> String {
    guard tabs.count == 1, let only = tabs.first else { return "Season".localized }
    return String(format: "MediaItem_SeasonSingle".localized, only.first)
  }

  /// Where picking a tab takes the rail: the season's first unfinished aired episode, else
  /// its first entry — a trailing card stands for itself.
  private static func entryByTab(_ entries: [RailEntry]) -> [Int: Int] {
    var result: [Int: Int] = [:]
    for entry in entries where result[entry.tabID] == nil {
      let inTab = entries.filter { $0.tabID == entry.tabID }
      let unseen = inTab.first {
        guard case .playable(_, let episode, let schedule) = $0 else { return false }
        return !episode.isWatched && schedule?.isUpcoming != true
      }
      result[entry.tabID] = (unseen ?? entry).id
    }
    return result
  }

  /// One rail entry in media-item terms. The status carries what used to be an opacity
  /// and a bespoke card: an unaired episode is `.upcoming` with its date in the badge,
  /// not a dimmed copy of a playable one.
  ///
  /// The caption is `7. "Episode Name"` — the season is already named by the tab above,
  /// so repeating it here is noise, and the air date lives in the badge rather than
  /// under the artwork.
  private func railItem(for entry: RailEntry) -> TVUIKitMediaItem {
    switch entry {
    case .playable(let season, let episode, let schedule):
      let card = Self.card(for: episode, in: season, schedule: schedule)
      let base = TVUIKitMediaItem(card: card)
      let caption = EpisodeText(season: nil, number: episode.number,
                                name: Self.displayTitle(episode: episode, schedule: schedule))
        .text(for: .episodeTile)
      let status: TVUIKitMediaItemStatus = (schedule?.isUpcoming == true)
        ? (schedule?.airDate.map { .upcoming(Self.airDateLabel($0, context: .beginningOfSentence)) } ?? .unavailable)
        : base.status
      return TVUIKitMediaItem(id: entry.id,
                              imageURL: base.imageURL ?? seriesBackdropURL,
                              caption: caption,
                              status: status,
                              timeLabel: base.timeLabel,
                              badgeText: base.badgeText)

    case .unavailable(_, let schedule):
      // An episode kino.pub has not uploaded must not read differently from one it has —
      // only the corner says so: its date while it is still ahead («Позже» with none),
      // the lock once it has aired. Never both (Sasha, 2026-10-04).
      let status: TVUIKitMediaItemStatus = MissingEpisodeAirState(airDate: schedule.airDate)
        .badgeText.map { .upcoming($0) } ?? .locked
      return TVUIKitMediaItem(id: entry.id,
                              imageURL: schedule.still ?? seriesBackdropURL,
                              // EpisodeText drops a name that is only the number («Серия 3»),
                              // the same rule as a kino.pub episode.
                              caption: EpisodeText(season: nil, number: schedule.episodeNumber,
                                                   name: schedule.name)
                                .text(for: .episodeTile),
                              status: status)

    case .missingSeasons(let from, let to, let episodes, _, _):
      // Same strings `MissingSeasonsCard` prints on the other platforms — the tile
      // changed, the words must not.
      var caption = String(format: "MediaItem_SeasonsRange".localized, from, to)
      if let episodes {
        caption += " · \(episodes) \("MediaItem_EpisodesShort".localized)"
      }
      return TVUIKitMediaItem(id: entry.id,
                              tint: TVUIKitTileArtwork.tint(for: "seasons-\(from)"),
                              symbol: "rectangle.stack",
                              caption: caption,
                              status: .unavailable)

    case .upcomingSeason(let number, let date, let poster):
      return TVUIKitMediaItem(id: entry.id,
                              imageURL: poster,
                              tint: TVUIKitTileArtwork.tint(for: "season-\(number)"),
                              symbol: "calendar",
                              caption: String(format: "MediaItem_SeasonSingle".localized, number),
                              status: .upcoming(Self.airDateLabel(date, context: .beginningOfSentence)))
    }
  }

  /// Enter on a rail entry. Only a playable, aired episode opens the player; everything
  /// else says why it cannot be watched, which is the same contract the dimmed-but-
  /// focusable SwiftUI card had — a non-focusable tile would wall off the rail's tail.
  private func select(entryID: Int) {
    guard let entry = entries.first(where: { $0.id == entryID }) else { return }
    switch entry {
    case .playable(let season, let episode, let schedule) where schedule?.isUpcoming != true:
      // `PlayerLink` is a plain `NavigationLink(value:)` off macOS, and a UIKit cell
      // cannot host one — the same environment hook the other TVUIKit rails push
      // through carries the identical route.
      mediaNavigation?(linkProvider.player(for: filled(episode, in: season)))
    case .playable(_, _, let schedule):
      onUnavailableSelected?(Self.unavailableMessage(date: schedule?.airDate), "clock")
    case .unavailable(_, let schedule):
      let message = MissingEpisodeAirState(airDate: schedule.airDate).message
      onUnavailableSelected?(message.text, message.systemImage)
    case .upcomingSeason(_, let date, _):
      onUnavailableSelected?(Self.unavailableMessage(date: date), "clock")
    case .missingSeasons:
      break
    }
  }

#else
  private var episodeRail: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      // Same lazy landscape strip as `MediaPosterShelf`: width from `ShelfMetrics`,
      // vertical room for the focus lift, nothing bespoke about the cards.
      LazyHStack(alignment: .top, spacing: metrics.gutter) {
        ForEach(entries) { entry in
          railCard(for: entry)
            .frame(width: cardWidth)
            .buttonStyle(MediaCardButtonStyle())
            .id(Self.episodeAnchor(entry.id))
        }
      }
      .scrollTargetLayout()
      .padding(.vertical, Metrics.landscapeFocusPadding)
      .environment(\.mediaCardTitleFont, TypeScale.episodeCardTitle)
    }
    // Content margins, not padding: `scrollTo(anchor: .leading)` would otherwise park
    // the first episode of a season under the page inset instead of beside it.
    .contentMargins(.horizontal, pageInset, for: .scrollContent)
    .onScrollTargetVisibilityChange(idType: String.self, threshold: 0.5) { ids in
      guard !isScrollingFromTab else { return }
      let visible = ids.compactMap { anchor -> RailEntry? in
        guard let entryID = Self.episodeID(from: anchor) else { return nil }
        return entries.first { $0.id == entryID }
      }
      guard let entry = visible.min(by: { lhs, rhs in
        let left = entries.firstIndex { $0.id == lhs.id } ?? 0
        let right = entries.firstIndex { $0.id == rhs.id } ?? 0
        return left < right
      }), entry.tabID != selectedTabID else { return }
      selectedTabID = entry.tabID
      if let season = seasons.first(where: { $0.id == entry.tabID }) {
        onSeasonVisible?(season.number)
      }
    }
  }
#endif

  /// A focusable card for something that has not aired. Not dimmed: the date or the lock
  /// on it says so, and a half-transparent card read as broken (Sasha, 2026-10-30). Uses
  /// the stock card style so the focus treatment is the platform's, not ours.
  private func unavailableCard<Content: View>(
    message: String,
    systemImage: String = "clock",
    @ViewBuilder content: () -> Content
  ) -> some View {
    Button {
      onUnavailableSelected?(message, systemImage)
    } label: {
      content()
    }
    .buttonStyle(DetailTileStyle.buttonStyle)
  }

  private static func unavailableMessage(date: Date?) -> String {
    guard let date else { return "MediaItem_NotAvailableYet".localized }
    return String(format: "MediaItem_AirsOn".localized, airDateLabel(date))
  }

  @ViewBuilder
  private func railCard(for entry: RailEntry) -> some View {
    switch entry {
    case .playable(let season, let episode, let schedule) where schedule?.isUpcoming != true:
      PlayerLink(route: linkProvider.player(for: filled(episode, in: season)),
                 item: filled(episode, in: season),
                 mode: .media) {
        MediaCardView(card: Self.card(for: episode, in: season, schedule: schedule),
                      caption: .always)
      }
      .modifier(MediaCardContextMenuModifier(
        entries: contextEntries(for: episode, season: season)
      ))

    case .playable(let season, let episode, let schedule):
      // Announced but not out yet. Still a real control: on tvOS a
      // non-focusable card is a wall — the remote cannot travel past it, so the whole
      // tail of the rail becomes unreachable. Pressing it says when it airs.
      unavailableCard(
        message: Self.unavailableMessage(date: schedule?.airDate)
      ) {
        MediaCardView(card: Self.card(for: episode,
                                      in: season,
                                      schedule: schedule,
                                      fallbackStill: seriesBackdropURL,
                                      primaryAction: .openDetail),
                      caption: .always)
      }

    case .unavailable(_, let schedule):
      let state = MissingEpisodeAirState(airDate: schedule.airDate)
      unavailableCard(
        message: state.message.text,
        systemImage: state.message.systemImage
      ) {
        MediaCardView(card: MediaCard(unavailableEpisodeID: entry.id,
                                      number: schedule.episodeNumber,
                                      title: schedule.name,
                                      episodeLabel: Self.episodeLabel(number: schedule.episodeNumber),
                                      dateLabel: state.badgeText,
                                      stillURL: (schedule.still ?? seriesBackdropURL)?.absoluteString),
                      caption: .always)
      }

    case .missingSeasons(let from, let to, let episodes, let firstAir, let lastAir):
      MissingSeasonsCard(from: from,
                         to: to,
                         episodes: episodes,
                         firstAir: firstAir,
                         lastAir: lastAir,
                         stillHeight: stillHeight)

    case .upcomingSeason(let number, let date, let poster):
      UpcomingSeasonCard(number: number, date: date, poster: poster, stillHeight: stillHeight)
    }
  }

  /// Selects a tab and scrolls the rail to its first item: a season's first episode, or
  /// the trailing card of an announced / missing season. Used by tab focus, tab
  /// activation, and the initial jump to the first unfinished episode. Not tvOS: there
  /// `TVSeasonRail` owns tabs, rail and where focus lands.
  /// - Parameter entryEpisodeID: the specific episode to land the rail on. Defaults to
  ///   that tab's first item — correct for a manual tab click/switch. Only the
  ///   initial resume jump (`scrollToFirstUnseen`) passes a specific target here.
  private func selectTab(_ tabID: Int, entryEpisodeID: Int? = nil, proxy: ScrollViewProxy, animated: Bool) {
    guard tabs.contains(where: { $0.id == tabID }),
          let first = entries.first(where: { $0.tabID == tabID }) else { return }
    let target = entryEpisodeID.flatMap { id in entries.first(where: { $0.id == id }) } ?? first
    selectedTabID = tabID
    seasonEntryEpisodeID = target.id
    // Only a season kino.pub has can be asked about: there is no schedule to fetch for a
    // number it does not carry. The trailing cards already hold what TMDB said of theirs.
    if let season = seasons.first(where: { $0.id == tabID }) {
      onSeasonVisible?(season.number)
    }
    let anchor = Self.episodeAnchor(target.id)
    isScrollingFromTab = true
    if animated {
      withAnimation(.easeOut(duration: 0.2)) {
        proxy.scrollTo(anchor, anchor: .leading)
      }
    } else {
      proxy.scrollTo(anchor, anchor: .leading)
    }
    Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(250))
      isScrollingFromTab = false
    }
  }

  /// Where the rail stands and Down from the hero lands: the episode the hero's main
  /// button plays. With everything kino.pub has watched and the next episode dated, the
  /// last one watched — Replay's episode 1 is not what someone following a show is
  /// after (Sasha, 2026-10-11).
  private func openingEntry(in entries: [RailEntry]) -> RailEntry? {
    let playable = entries.filter(\.isPlayable)
    let allWatched = !playable.isEmpty && playable.allSatisfy {
      if case .playable(_, let episode, _) = $0 { return episode.isWatched }
      return false
    }
    if allWatched, awaitsNextEpisode, let last = playable.last {
      return last
    }
    if let openingEpisodeID, let entry = entries.first(where: { $0.id == openingEpisodeID }) {
      return entry
    }
    return firstUnseen
  }

  private func scrollToFirstUnseen(proxy: ScrollViewProxy) async {
    guard !didScrollToUnseen, let target = openingEntry(in: entries) else { return }
    try? await Task.sleep(for: .milliseconds(120))
    guard !Task.isCancelled else { return }
    // Only now: bailing above must leave this false so a later payload gets its turn.
    didScrollToUnseen = true
    // The first episode is already where the rail opens. `scrollTo` would also drag
    // the page down onto the episodes, and there is nothing to reveal.
    guard target.id != entries.first?.id else {
      selectedTabID = target.tabID
      return
    }
    selectTab(target.tabID, entryEpisodeID: target.id, proxy: proxy, animated: false)
  }

  private static func episodeID(from anchor: String) -> Int? {
    guard anchor.hasPrefix("episode-") else { return nil }
    return Int(anchor.dropFirst("episode-".count))
  }

  private func contextEntries(for episode: Episode, season: Season) -> [MediaCardContextEntry] {
    let card = Self.card(for: episode, in: season, schedule: nil)
    let containing = cardMenu.containingFolders(for: card)
    let folders = cardMenu.folders.map {
      MediaCardContextMenus.BookmarkFolderOption(
        id: $0.id,
        title: $0.title,
        isContaining: containing.contains($0.id)
      )
    }
    return MediaCardContextMenus.entries(
      for: card,
      surface: .shelf,
      bookmarkFolders: folders,
      onPlay: nil,
      onGoToTitle: nil,
      onToggleWatchlist: { cardMenu.toggleWatchlist(card) },
      onToggleBookmarkFolder: { folderID in
        guard let folder = cardMenu.folders.first(where: { $0.id == folderID }) else { return }
        cardMenu.toggleBookmark(itemID: card.itemID,
                                folder: folder,
                                serverHint: card.viewerState.bookmarkFolderIDs ?? [])
      },
      onCreateBookmarkFolder: { cardMenu.promptNewFolder(for: card.itemID) },
      onToggleWatched: { onToggleWatched?(episode, season) },
      onHide: { onHide?(episode, season) },
      onOpenImageURL: { openURL($0) }
    )
  }

  /// Episodes arrive without their season/media context, which playback needs.
  private func filled(_ episode: Episode, in season: Season) -> Episode {
    episode.seasonNumber = season.number
    episode.mediaId = season.mediaId
    episode.seriesTitle = seriesTitle
    return episode
  }

  /// The rail's card — the same landscape `MediaCard` History and Continue Watching
  /// draw, captioned "EPISODE 9 · 5 Mar" where the poster shelves caption "S2, E5".
  private static func card(for episode: Episode,
                           in season: Season,
                           schedule: EpisodeSchedule?,
                           fallbackStill: URL? = nil,
                           primaryAction: MediaCardPrimaryAction = .play) -> MediaCard {
    MediaCard(episode: episode,
              in: season,
              title: displayTitle(episode: episode, schedule: schedule),
              episodeLabel: episodeLabel(number: episode.number),
              dateLabel: schedule?.airDate.map { airDateLabel($0) },
              stillURL: stillURL(episode: episode, schedule: schedule) ?? fallbackStill?.absoluteString,
              primaryAction: primaryAction)
  }

  /// kino.pub's name, else TMDB's — and neither when it is only the number spelled out
  /// («Эпизод 1»): the caption already says which episode it is (`EpisodeTitle`).
  private static func displayTitle(episode: Episode, schedule: EpisodeSchedule?) -> String {
    EpisodeTitle.meaningful(episode.title) ?? EpisodeTitle.meaningful(schedule?.name) ?? ""
  }

  private static func stillURL(episode: Episode, schedule: EpisodeSchedule?) -> String? {
    if !episode.thumbnail.isEmpty { return episode.thumbnail }
    return schedule?.still?.absoluteString
  }

  private static func episodeLabel(number: Int) -> String {
    EpisodeText(season: nil, number: number).listItem()
  }

  /// Inside a week either way the date is relative — "in 3 days", "7 days ago", and
  /// "tomorrow" / "yesterday" for the ends. Further out it is an absolute date, with the
  /// year only when it is not this year (Sasha, 2026-10-04).
  ///
  /// `context` is where the words land: `.beginningOfSentence` on a card's badge
  /// («Завтра»), mid-sentence in a toast («Выходит завтра»).
  static func airDateLabel(_ date: Date,
                           now: Date = Date(),
                           context: Formatter.Context = .middleOfSentence,
                           locale: Locale = .current) -> String {
    let days = calendarDays(from: now, to: date)
    guard abs(days) > 7 else {
      return relativeDays(days, context: context, locale: locale)
    }
    return absoluteAirDate(date, now: now, locale: locale)
  }

  /// "today", "yesterday", "the day before yesterday" (ru «позавчера»), "in 3 days" —
  /// the locale's own named days where it has them.
  static func relativeDays(_ days: Int,
                           context: Formatter.Context = .middleOfSentence,
                           locale: Locale = .current) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = locale
    formatter.dateTimeStyle = .named
    formatter.unitsStyle = .full
    formatter.formattingContext = context
    return formatter.localizedString(from: DateComponents(day: days))
  }

  /// "12 Mar" this year, "12 Mar 2023" any other — see `airDateLabel`.
  static func absoluteAirDate(_ date: Date,
                              now: Date = Date(),
                              locale: Locale = .current,
                              calendar: Calendar = .current) -> String {
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.setLocalizedDateFormatFromTemplate(sameYear ? "d MMM" : "d MMM yyyy")
    return formatter.string(from: date)
  }

  /// Whole local calendar days from `now` to `date`; negative in the past.
  static func calendarDays(from now: Date, to date: Date, calendar: Calendar = .current) -> Int {
    calendar.dateComponents([.day],
                            from: calendar.startOfDay(for: now),
                            to: calendar.startOfDay(for: date)).day ?? 0
  }

  private static func episodeAnchor(_ id: Int) -> String { "episode-\(id)" }

  /// Between the season line and the rail. The air there used to measure 11 pt on tvOS (2 here,
  /// the rest the rail's own top inset); Sasha asked for twice that (2026-10-11), so 22.
  private static let stripToRailSpacing: CGFloat = 13

#if os(tvOS)
  /// Width to lay out with until the rail has measured itself.
  static let referenceWidth: CGFloat = 1920
#elseif os(macOS)
  static let referenceWidth: CGFloat = 1100
#else
  static let referenceWidth: CGFloat = 390
#endif
}

// MARK: - Episodes kino.pub does not have

/// Where an episode TMDB lists and kino.pub does not have stands, by its air date in
/// local calendar days. One rule for the card's badge, its lock and what Select says,
/// on the TVUIKit rail and the SwiftUI cards alike. Product rules (Sasha, 2026-10-03,
/// corner rule 2026-10-04): the corner holds the date while the episode is ahead
/// («Позже» with no date) and the lock once it has aired — never both.
enum MissingEpisodeAirState: Equatable {
  /// Air date ahead: the badge says when.
  case upcoming(Date)
  /// Aired today or up to `recentDays` ago and not uploaded yet.
  case justAired(Date, daysAgo: Int)
  /// Aired before that — kino.pub simply does not have it. The lock alone.
  case aired(Date)
  /// TMDB lists the episode without a date.
  case undated

  /// How far back an aired episode still gets its day on the card.
  static let recentDays = 3

  // `@MainActor` like the rail's date helpers it words itself with (a `View`'s statics).
  @MainActor
  init(airDate: Date?, now: Date = Date(), calendar: Calendar = .current) {
    guard let airDate else {
      self = .undated
      return
    }
    let days = SeasonsRailView.calendarDays(from: now, to: airDate, calendar: calendar)
    if days > 0 {
      self = .upcoming(airDate)
    } else if -days <= Self.recentDays {
      self = .justAired(airDate, daysAgo: -days)
    } else {
      self = .aired(airDate)
    }
  }

  /// The corner's date, capitalised because it starts the chip. Nil once the episode has
  /// aired: the lock takes the corner instead.
  @MainActor var badgeText: String? { badge() }

  @MainActor
  func badge(now: Date = Date(), locale: Locale = .current) -> String? {
    switch self {
    case .upcoming(let date):
      return SeasonsRailView.airDateLabel(date, now: now, context: .beginningOfSentence, locale: locale)
    case .justAired, .aired:
      return nil
    case .undated:
      return "MediaItem_Later".localized
    }
  }

  /// What pressing the card says, and the toast's glyph.
  @MainActor var message: (text: String, systemImage: String) {
    switch self {
    case .upcoming(let date):
      return (String(format: "MediaItem_AirsOn".localized, SeasonsRailView.airDateLabel(date)), "clock")
    // The HUD is a square for a short title; when it aired is already on the card.
    case .justAired, .aired:
      return ("MediaItem_NotOnKinoPub".localized, "lock")
    case .undated:
      return ("MediaItem_NotAvailableYet".localized, "clock")
    }
  }
}

// MARK: - Trailing cards (missing / upcoming seasons)

/// One dark slot for whole seasons between kino.pub's last and the next announced
/// one — "Сезоны 6–13 · 2013–2021 · 120 эп." — instead of a strip of dead tabs.
private struct MissingSeasonsCard: View {
  let from: Int
  let to: Int
  let episodes: Int?
  let firstAir: Date?
  let lastAir: Date?
  /// Artwork height of the neighbouring episode cards, so the slot lines up with them.
  let stillHeight: CGFloat

  private var yearsText: String? {
    guard let firstAir else { return nil }
    let firstYear = Calendar.current.component(.year, from: firstAir)
    let lastYear = lastAir.map { Calendar.current.component(.year, from: $0) }
    return lastYear != nil && lastYear != firstYear ? "\(firstYear)–\(lastYear!)" : "\(firstYear)"
  }

  private var subtitle: String? {
    var parts: [String] = []
    if let yearsText { parts.append(yearsText) }
    if let episodes { parts.append("\(episodes) \("MediaItem_EpisodesShort".localized)") }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  var body: some View {
    VStack(spacing: 10) {
      Text(String(format: "MediaItem_SeasonsRange".localized, from, to))
        .font(TypeScale.cardTitle)
        .foregroundStyle(Color.KinoPub.text)
        .multilineTextAlignment(.center)

      if let subtitle {
        Text(subtitle)
          .font(TypeScale.cardMeta)
          .foregroundStyle(Color.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .padding(.horizontal, 0)
    .frame(maxWidth: .infinity)
    .frame(height: stillHeight)
    .background(
      RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous)
        .fill(Color.secondary.opacity(0.18))
    )
  }
}

/// The announced season ahead of everything kino.pub has: poster, "Сезон 19",
/// premiere date and countdown. Inert — there is nothing to play yet.
private struct UpcomingSeasonCard: View {
  let number: Int
  let date: Date
  let poster: URL?
  /// Artwork height of the neighbouring episode cards, so the poster lines up with them.
  let stillHeight: CGFloat

  /// "12 марта", or "12 марта 2027" when it is not this year (Sasha, 2026-10-04).
  private var premiereText: String {
    let calendar = Calendar.current
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate(sameYear ? "d MMMM" : "d MMMM yyyy")
    return formatter.string(from: date)
  }

  private var countdown: String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
  }

  var body: some View {
    VStack(alignment: .center, spacing: 6) {
      CachedRemoteImage(
        url: poster,
        contentMode: .fill,
        placeholder: { Color.KinoPub.placeholder },
        failure: { Color.KinoPub.placeholder }
      )
      .frame(maxWidth: .infinity)
      .frame(height: stillHeight)
      .clipped()
      .clipShape(RoundedRectangle(cornerRadius: Metrics.cardCornerRadius, style: .continuous))

      Text(String(format: "MediaItem_SeasonSingle".localized, number))
        .font(TypeScale.cardTitle)
        .foregroundStyle(Color.KinoPub.text)
        .lineLimit(1)

      Text(String(format: "MediaItem_PremiereOn".localized, premiereText))
        .font(TypeScale.cardMeta)
        .foregroundStyle(Color.secondary)
        .lineLimit(2)
        .multilineTextAlignment(.center)

      Text(countdown)
        .font(TypeScale.cardMeta)
        .foregroundStyle(Color.secondary.opacity(0.7))
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity, alignment: .top)
  }
}

/// The versions of one film — 24 / 48 fps, colour / black-and-white, director's cut —
/// as the same landscape rail the episodes use.
///
/// It lives beside `SeasonsRailView` because it *is* that rail with a simpler spine: no
/// season tabs, no schedules, no hide/watched actions. What it must never be is the
/// episodes rail itself — kino.pub ships these as `videos` on a `subtype: "multi"` movie,
/// and dropping them in among real episodes is exactly the confusion the playable graph
/// in ROADMAP.md exists to prevent.
///
/// Before this, `videos.first` was the only version the app could reach; the other one
/// existed in the payload and nowhere in the UI.
struct VersionsRailView: View {

  let variants: [PlaybackVariant]
  let linkProvider: NavigationLinkProvider
  /// The film's own artwork, for versions kino.pub gives no thumbnail of their own.
  var stillURL: String? = nil
  /// False while the hero owns the page — the header stays out from under the artwork,
  /// the same rule the season tabs follow.
  var showsChrome: Bool = true
  /// What the rail is called (`MediaPresentationProfile`). The count, when there is
  /// more than one, is part of that title — not a number beside it.
  var titleKey: String = "MediaItem_Versions"
  /// Where focus lands when it enters the rail, and where the rail parks — the hero's
  /// «+ ещё N» sets it to the first version that had no pill. Nil at rest, so the rail
  /// starts at the first version.
  var entryVariantID: Int? = nil

  @Environment(\.dynamicTypeSize) private var typeSize
#if os(tvOS)
  @Environment(\.mediaNavigation) private var mediaNavigation
#endif
  @State private var railWidth: CGFloat = SeasonsRailView.referenceWidth

  private var metrics: ShelfMetrics { .landscape(width: railWidth, typeSize: typeSize) }
  private var cardWidth: CGFloat { metrics.cardWidth(in: railWidth) }
  /// The title page's side margin, as for the episodes (`SeasonsRailView.pageInset`).
  private var pageInset: CGFloat {
#if os(tvOS)
    metrics.inset
#else
    MediaItemLayout.horizontalInset
#endif
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if showsChrome {
        SectionHeader(title: videosRailHeading(titleKey: titleKey, count: variants.count),
                      leadingInset: pageInset)
          .transition(.opacity)
      }
      rail
    }
    .animation(.easeOut(duration: 0.25), value: showsChrome)
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { width in
      if width > 0 { railWidth = width }
    }
  }

#if os(tvOS)
  /// The system wide media-item cell, like every other rail on this platform — a
  /// hand-assembled tile here would be the banned shape even if it looked right.
  private var rail: some View {
    TVUIKitMediaItemRail(
      items: variants.map(railItem(for:)),
      contentInset: metrics.inset,
      columns: MainView.stillColumns,
      entryItemID: entryVariantID,
      onSelect: { id in
        guard let variant = variants.first(where: { $0.id == id }) else { return }
        // A UIKit cell cannot host a `NavigationLink`; the same environment hook the
        // other TVUIKit rails push through carries the identical route.
        mediaNavigation?(linkProvider.player(for: variant))
      }
    )
//    .background(.red)
//    .focusSection()
  }

  private func railItem(for variant: PlaybackVariant) -> TVUIKitMediaItem {
    let progress = variant.watchProgress
    let status: TVUIKitMediaItemStatus = {
      if variant.isWatched { return .watched }
      // `fraction` is nil when the duration is unusable, and a progress bar drawn from a
      // guessed denominator is worse than none.
      if progress.hasStarted, let fraction = progress.fraction { return .inProgress(fraction) }
      return .ready
    }()
    return TVUIKitMediaItem(
      id: variant.id,
      imageURL: URL(string: variant.thumbnail.isEmpty ? (stillURL ?? "") : variant.thumbnail),
      caption: variant.title,
      status: status,
      timeLabel: variant.duration >= 60
        ? RuntimeText(seconds: variant.duration).text(for: .timeBadge)
        : nil
    )
  }
#else
  private var rail: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      LazyHStack(alignment: .top, spacing: metrics.gutter) {
        ForEach(variants) { variant in
          PlayerLink(route: linkProvider.player(for: variant),
                     item: variant,
                     mode: .media) {
            MediaCardView(card: MediaCard(variant: variant, stillURL: stillURL),
                          caption: .always)
          }
          .frame(width: cardWidth)
          .buttonStyle(MediaCardButtonStyle())
        }
      }
      .padding(.vertical, Metrics.landscapeFocusPadding)
    }
    .contentMargins(.horizontal, pageInset, for: .scrollContent)
  }
#endif
}

// MARK: - Previews

#if DEBUG
/// Fixtures for the previews below. Dates are relative to "now" so every air state
/// (ahead, just aired, long gone, undated) stays true whenever the preview is opened.
private enum RailPreviewFixtures {

  static func day(_ offset: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
  }

  /// `progress` is seconds watched; `watched` is the server's explicit flag.
  static func episode(_ number: Int, season: Int, title: String? = nil,
                      watched: Bool = false, progress: Int = 0) -> Episode {
    Episode(id: season * 100 + number,
            title: title ?? "Episode title \(number)",
            thumbnail: "",
            duration: 2_700,
            tracks: 1,
            number: number,
            ac3: 0,
            audios: [],
            watched: watched ? 1 : 0,
            watching: EpisodeWatching(status: watched ? 1 : (progress > 0 ? 0 : -1), time: progress),
            subtitles: [],
            files: [])
  }

  static func season(_ number: Int, episodes: [Episode]) -> Season {
    // `SeasonWatching` has no public initialiser; it only ever comes off the wire.
    // swiftlint:disable:next force_try
    let watching = try! JSONDecoder().decode(SeasonWatching.self, from: Data(#"{"status": 0}"#.utf8))
    let season = Season(id: number, title: "", number: number,
                        watching: watching, episodes: episodes)
    season.mediaId = 1
    return season
  }

  /// Season 1 fully watched, season 2 half-way through, season 3 untouched.
  static var threeSeasons: [Season] {
    [
      season(1, episodes: (1...6).map { episode($0, season: 1, watched: true) }),
      season(2, episodes: [
        episode(1, season: 2, watched: true),
        episode(2, season: 2, watched: true),
        episode(3, season: 2, progress: 1_200),
        episode(4, season: 2),
        episode(5, season: 2),
      ]),
      season(3, episodes: (1...4).map { episode($0, season: 3) }),
    ]
  }

  static var oneSeason: [Season] {
    [season(1, episodes: (1...5).map { episode($0, season: 1, watched: $0 < 3) })]
  }

  /// TMDB knows two episodes kino.pub lacks (one ahead, one aired long ago) plus a
  /// third just aired and one with no date at all.
  static var schedules: [Int: [EpisodeSchedule]] {
    [3: [
      EpisodeSchedule(episodeNumber: 3, seasonNumber: 3, name: "Aired, not uploaded", airDate: day(-60)),
      EpisodeSchedule(episodeNumber: 4, seasonNumber: 3, name: "Aired two days ago", airDate: day(-2)),
      EpisodeSchedule(episodeNumber: 5, seasonNumber: 3, name: "Tomorrow", airDate: day(1)),
      EpisodeSchedule(episodeNumber: 6, seasonNumber: 3, name: "Next month", airDate: day(30)),
      EpisodeSchedule(episodeNumber: 7, seasonNumber: 3, name: "No date yet"),
    ]]
  }

  /// Season 3 is kino.pub's last; `upcoming` is the announced one, with `gap` seasons
  /// skipped in between.
  static func metadata(upcoming: Int, gap: [Int] = []) -> TitleMetadata {
    var metadata = TitleMetadata()
    metadata.nextEpisode = EpisodeRef(seasonNumber: upcoming, episodeNumber: 1, airDate: day(45))
    metadata.seasonSummaries = gap.map {
      SeasonSummary(seasonNumber: $0, episodeCount: 10, airDate: day(-365 * (upcoming - $0)))
    } + [SeasonSummary(seasonNumber: upcoming, episodeCount: 8, airDate: day(45))]
    return metadata
  }

  static func variant(_ number: Int, title: String, watched: Bool = false,
                      progress: Int = 0, duration: Int = 7_200) -> PlaybackVariant {
    let json = """
    {"id": \(900 + number), "title": "\(title)", "thumbnail": "", "duration": \(duration),
     "tracks": 1, "number": \(number), "ac3": 0, "audios": [],
     "watched": \(watched ? 1 : 0),
     "watching": {"status": \(progress > 0 ? 0 : -1), "time": \(progress)},
     "subtitles": [], "files": []}
    """
    // A decode of a literal this file owns; a typo should fail loudly in the canvas.
    // swiftlint:disable:next force_try
    let video = try! JSONDecoder().decode(Video.self, from: Data(json.utf8))
    return PlaybackVariant(video: video, mediaId: 1, movieTitle: "Preview Movie")
  }
}

/// Environment the rails read, so a preview does not crash on a missing object.
private struct RailPreviewHost<Content: View>: View {
  @ViewBuilder var content: () -> Content

  var body: some View {
    content()
      .padding(.vertical)
      .environment(ErrorHandler())
      .environment(NavigationState())
  }
}

#Preview("Seasons rail · single season (reads «Season 1», no pills)") {
  RailPreviewHost {
    SeasonsRailView(seasons: RailPreviewFixtures.oneSeason,
                    linkProvider: AppRoutesLinkProvider(),
                    seriesTitle: "Preview Series")
  }
}

#Preview("Seasons rail · watched / in progress / new") {
  RailPreviewHost {
    SeasonsRailView(seasons: RailPreviewFixtures.threeSeasons,
                    linkProvider: AppRoutesLinkProvider(),
                    seriesTitle: "Preview Series")
  }
}

#Preview("Seasons rail · hero up (chrome hidden)") {
  RailPreviewHost {
    SeasonsRailView(seasons: RailPreviewFixtures.threeSeasons,
                    linkProvider: AppRoutesLinkProvider(),
                    seriesTitle: "Preview Series",
                    showsChrome: false)
  }
}

#Preview("Seasons rail · TMDB schedule (every air state)") {
  RailPreviewHost {
    SeasonsRailView(seasons: RailPreviewFixtures.threeSeasons,
                    linkProvider: AppRoutesLinkProvider(),
                    seriesTitle: "Preview Series",
                    seasonSchedules: RailPreviewFixtures.schedules)
  }
}

#Preview("Seasons rail · upcoming season card") {
  RailPreviewHost {
    SeasonsRailView(seasons: RailPreviewFixtures.threeSeasons,
                    linkProvider: AppRoutesLinkProvider(),
                    seriesTitle: "Preview Series",
                    externalMetadata: RailPreviewFixtures.metadata(upcoming: 4))
  }
}

#Preview("Seasons rail · skipped seasons + upcoming") {
  RailPreviewHost {
    SeasonsRailView(seasons: RailPreviewFixtures.threeSeasons,
                    linkProvider: AppRoutesLinkProvider(),
                    seriesTitle: "Preview Series",
                    seasonSchedules: RailPreviewFixtures.schedules,
                    externalMetadata: RailPreviewFixtures.metadata(upcoming: 8, gap: [4, 5, 6, 7]))
  }
}

#Preview("Missing seasons card · every shape") {
  VStack(spacing: 16) {
    // Years and episode count, spanning years.
    MissingSeasonsCard(from: 6, to: 13, episodes: 120,
                       firstAir: RailPreviewFixtures.day(-365 * 8),
                       lastAir: RailPreviewFixtures.day(-365),
                       stillHeight: 120)
    // Both ends in the same year → one year, not a range.
    MissingSeasonsCard(from: 4, to: 4, episodes: 8,
                       firstAir: RailPreviewFixtures.day(-10),
                       lastAir: RailPreviewFixtures.day(-10),
                       stillHeight: 120)
    // Years only.
    MissingSeasonsCard(from: 4, to: 5, episodes: nil,
                       firstAir: RailPreviewFixtures.day(-800),
                       lastAir: RailPreviewFixtures.day(-300),
                       stillHeight: 120)
    // Episode count only.
    MissingSeasonsCard(from: 4, to: 5, episodes: 20, firstAir: nil, lastAir: nil, stillHeight: 120)
    // Nothing but the range.
    MissingSeasonsCard(from: 4, to: 5, episodes: nil, firstAir: nil, lastAir: nil, stillHeight: 120)
  }
  .padding()
}

#Preview("Upcoming season card · every shape") {
  HStack(alignment: .top, spacing: 16) {
    // This year, no poster (placeholder).
    UpcomingSeasonCard(number: 4, date: RailPreviewFixtures.day(14), poster: nil, stillHeight: 120)
    // Far enough out to carry the year.
    UpcomingSeasonCard(number: 5, date: RailPreviewFixtures.day(500), poster: nil, stillHeight: 120)
    // Tomorrow.
    UpcomingSeasonCard(number: 6, date: RailPreviewFixtures.day(1), poster: nil, stillHeight: 120)
  }
  .padding()
}

#Preview("Missing episode air state · badge and toast") {
  let cases: [(String, MissingEpisodeAirState)] = [
    ("Upcoming", .upcoming(RailPreviewFixtures.day(5))),
    ("Upcoming, far", .upcoming(RailPreviewFixtures.day(90))),
    ("Just aired", .justAired(RailPreviewFixtures.day(-1), daysAgo: 1)),
    ("Aired long ago", .aired(RailPreviewFixtures.day(-400))),
    ("Undated", .undated),
  ]
  return VStack(alignment: .leading, spacing: 12) {
    ForEach(cases, id: \.0) { name, state in
      VStack(alignment: .leading, spacing: 2) {
        Text(name).font(.headline)
        Text("badge: \(state.badgeText ?? "— (lock)")")
        Label(state.message.text, systemImage: state.message.systemImage)
      }
    }
  }
  .padding()
}

#Preview("Versions rail · mixed progress") {
  RailPreviewHost {
    VersionsRailView(variants: [
      RailPreviewFixtures.variant(1, title: "24 fps"),
      RailPreviewFixtures.variant(2, title: "48 fps", progress: 2_400),
      RailPreviewFixtures.variant(3, title: "Black & white", watched: true),
    ], linkProvider: AppRoutesLinkProvider())
  }
}

#Preview("Versions rail · two versions") {
  RailPreviewHost {
    VersionsRailView(variants: [
      RailPreviewFixtures.variant(1, title: "24 fps"),
      RailPreviewFixtures.variant(2, title: "48 fps"),
    ], linkProvider: AppRoutesLinkProvider())
  }
}

#Preview("Versions rail · unnamed and short (chrome hidden)") {
  RailPreviewHost {
    VersionsRailView(variants: [
      RailPreviewFixtures.variant(1, title: ""),
      RailPreviewFixtures.variant(2, title: "Teaser cut", duration: 45),
    ], linkProvider: AppRoutesLinkProvider(), showsChrome: false)
  }
}
#endif
