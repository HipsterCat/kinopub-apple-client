//
//  PlayerCasesView.swift
//  KinoPubAppleClient
//
//  DEBUG-only. Settings → Diagnostics / Advanced → Player cases.
//

#if DEBUG
import SwiftUI
import KinoPubBackend
import KinoPubKit
import KinoPubMedia
import KinoPubMetadata

/// **Every case `docs/product/playback-info.md` names, on real titles, one press from the
/// real player.** Each row shows what we will send the system player — computed by the same
/// pipeline the player runs (`PlaybackMediaContext` → `MediaAggregator` → `PlayerInfo`),
/// TMDB included — next to what the product doc expects. Open it, press Down for Info, and
/// compare: a difference between the row and the panel is AVKit's; a difference between
/// the row and the expectation is ours.
///
/// Titles are picked live (the first popular one of each type), and each is cached and
/// stamped exactly as the detail page does before Play, so the player gets what it gets in
/// the app. Not a second player path — rows open `Route.player` / `.trailerPlayer`.
struct PlayerCasesView: View {

  @Environment(\.appContext) private var appContext
  @StateObject private var model = PlayerCasesModel()

  var body: some View {
    ZStack {
      Color.KinoPub.background.edgesIgnoringSafeArea(.all)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 24) {
          Button {
            Task { await model.load(context: appContext) }
          } label: {
            Text(model.isLoading ? "Loading…" : "Reload cases")
          }
          .disabled(model.isLoading)

          ForEach(model.cases) { playerCase in
            PlayerCaseRow(playerCase: playerCase)
              // For a UI test to drive the same list: `playerCase.episode-named`, …
              .accessibilityIdentifier("playerCase.\(playerCase.id)")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
      }
    }
    // The Settings stacks register no `Route` destinations of their own.
    .appRouteDestinations()
    .task {
      if model.cases.allSatisfy({ $0.playable == nil }) {
        await model.load(context: appContext)
      }
    }
#if os(iOS)
    .platformNavigationTitle("Player cases")
#endif
  }
}

private struct PlayerCaseRow: View {
  let playerCase: PlayerCase

  var body: some View {
    if let playable = playerCase.playable {
      PlayerLink(route: playerCase.mode == .trailer
                   ? Route.trailerPlayer(playable, token: UUID())
                   : Route.player(playable, token: UUID()),
                 item: playable,
                 mode: playerCase.mode) {
        content
      }
#if os(tvOS)
      .buttonStyle(.card)
#endif
    } else {
      // Focusable on tvOS too, so a missing case can still be read.
      Button {} label: { content }
#if os(tvOS)
        .buttonStyle(.card)
#endif
    }
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(playerCase.name)
        .font(.headline)
      if let source = playerCase.source {
        Text(source)
          .font(.subheadline)
          .foregroundStyle(Color.KinoPub.subtitle)
      }
      if let info = playerCase.info {
        Text("Sends: \(PlayerCase.titleLine(info))")
        Text("Info: \(PlayerCase.infoLine(info))")
        if let description = info.description {
          Text(description)
            .lineLimit(2)
            .foregroundStyle(Color.KinoPub.subtitle)
        }
      }
      if let note = playerCase.note {
        Text(note)
          .foregroundStyle(.orange)
      }
      Text("Expect: \(playerCase.expectation)")
        .foregroundStyle(Color.KinoPub.subtitle)
    }
    .font(.callout)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
  }
}

// MARK: - Model

struct PlayerCase: Identifiable {
  let id: String
  let name: String
  /// What `docs/product/playback-info.md` says the panel shows for this case.
  let expectation: String
  var mode: WatchMode = .media
  var playable: (any PlayableItem)?
  /// The title it was picked from, and its kino.pub id.
  var source: String?
  var info: PlayerInfo?
  var note: String?

  static func titleLine(_ info: PlayerInfo) -> String {
    [info.title, info.subtitle].compactMap { $0 }.joined(separator: " — ")
  }

  static func infoLine(_ info: PlayerInfo) -> String {
    let parts = [info.genre, info.creationDate, info.contentRating].map { $0 ?? "—" }
    let artwork = info.artworkCandidates.first.map { "art \($0.lastPathComponent)" } ?? "no art"
    return (parts + [artwork]).joined(separator: " · ")
  }
}

@MainActor
final class PlayerCasesModel: ObservableObject {

  @Published private(set) var cases: [PlayerCase] = PlayerCasesModel.blank
  @Published private(set) var isLoading = false

  private static let blank: [PlayerCase] = [
    PlayerCase(id: "film", name: "Film",
               expectation: "film name · no subtitle · plot · first genre · year · poster"),
    PlayerCase(id: "film-trailer", name: "Film trailer", expectation:
                "film name · «Trailer» · film's plot, genre and poster · Info: Go to Movie"),
    PlayerCase(id: "episode-named", name: "Episode with a name", expectation:
                "show name · «Season N, Episode M: Name» · episode's own description (TMDB) or the show's · show's genre · episode still · Info: Go to Show · Up Next tab"),
    PlayerCase(id: "episode-placeholder", name: "Episode named «Эпизод N» by kino.pub",
               expectation: "«Season N, Episode M» with no «: Эпизод N» — or TMDB's real name"),
    PlayerCase(id: "series-trailer", name: "Series trailer", expectation:
                "show name · «Trailer» · show's plot · Info: Go to Show"),
    PlayerCase(id: "concert", name: "Concert (126187)",
               expectation: "a music genre (Electronic), never «Concert»"),
    PlayerCase(id: "documovie", name: "Documentary film",
               expectation: "«Documentary» as the genre"),
    PlayerCase(id: "docuserial", name: "Docuseries episode",
               expectation: "show name · episode line · «Documentary» as the genre"),
    PlayerCase(id: "tvshow", name: "TV show episode",
               expectation: "a format genre (Reality, Talk…) or «TV Show»"),
    PlayerCase(id: "version", name: "Film version (124447, 48 fps)",
               expectation: "film name · «48 fps» as the subtitle"),
    PlayerCase(id: "download", name: "Downloaded episode or film",
               expectation: "saved name · «Season N, Episode M» for an episode · saved poster"),
  ]

  private var context: AppContextProtocol = AppContext.shared

  func load(context: AppContextProtocol) async {
    guard !isLoading else { return }
    isLoading = true
    defer { isLoading = false }
    self.context = context
    cases = Self.blank

    let service = context.contentService
    let films = await popular(.movie, service)
    let film = await details(films.first?.id, service)
    await fill("film", playable: film, title: film)

    var trailerFilm: MediaItem?
    for candidate in films.prefix(8) {
      if let item = await details(candidate.id, service), item.trailerURL != nil {
        trailerFilm = item
        break
      }
    }
    await fill("film-trailer", playable: trailerFilm, title: trailerFilm, mode: .trailer)

    let series = await details(await popular(.serial, service).first?.id, service)
    let episodes = series.map(Self.stampedEpisodes) ?? []
    await fill("episode-named", playable: episodes.first { EpisodeTitle.meaningful($0.title) != nil },
               title: series,
               missing: "no episode of this series has a name of its own on kino.pub")
    await fill("episode-placeholder",
               playable: episodes.first { EpisodeTitle.meaningful($0.title) == nil },
               title: series,
               missing: "every episode of this series has a real name on kino.pub")
    await fill("series-trailer", playable: series?.trailerURL == nil ? nil : series,
               title: series, mode: .trailer, missing: "this series has no trailer")

    var concert = await details(126187, service)
    if concert == nil {
      concert = await details(await popular(.concert, service).first?.id, service)
    }
    await fill("concert", playable: concert, title: concert)

    let documovie = await details(await popular(.documovie, service).first?.id, service)
    await fill("documovie", playable: documovie, title: documovie)

    let docuserial = await details(await popular(.docuserial, service).first?.id, service)
    await fill("docuserial", playable: docuserial.flatMap { Self.stampedEpisodes($0).first },
               title: docuserial)

    let tvshow = await details(await popular(.tvshow, service).first?.id, service)
    await fill("tvshow", playable: tvshow.flatMap { Self.stampedEpisodes($0).first }, title: tvshow)

    let multi = await details(124447, service)
    await fill("version", playable: multi?.playbackVariants.last, title: multi,
               missing: "124447 no longer answers with two versions")

    let download = context.downloadedFilesDatabase.readData()?.first?.metadata
    await fill("download", playable: download,
               title: download.flatMap { context.localProgressStore.snapshot(for: $0.metadata.id) },
               missing: "nothing downloaded on this device")
  }

  // MARK: - Filling a case

  /// What the player would send, computed by the player's own pipeline — kino.pub's facts,
  /// then the enrichment sources', exactly as `PlayerManager` stamps them.
  private func fill(_ id: String, playable: (any PlayableItem)?, title: MediaItem?,
                    mode: WatchMode = .media, missing: String = "could not load a title") async {
    guard let index = cases.firstIndex(where: { $0.id == id }) else { return }
    guard let playable else {
      cases[index].note = missing
      return
    }
    let isTrailer = mode == .trailer
    var draft = PlaybackMediaContext.draft(playing: playable, title: title, isTrailer: isTrailer)
    if let enrichment = PlaybackMediaContext.enrichment(playing: playable, title: title,
                                                        isTrailer: isTrailer) {
      draft = await PlaybackMediaContext.enrich(draft, with: enrichment,
                                                service: context.metadataService)
    }
    cases[index].mode = mode
    cases[index].playable = playable
    cases[index].source = title.map { "\($0.title) · kino.pub \($0.id) · \($0.type)" }
    cases[index].info = MediaAggregator.merge(draft).map {
      PlayerInfo(context: $0, labels: PlaybackMediaContext.labels)
    }
    let unmapped = MediaAggregator.merge(draft)?.genres.filter { !$0.isMapped }.map(\.id) ?? []
    if !unmapped.isEmpty {
      cases[index].note = "unmapped genres: \(unmapped.joined(separator: ", "))"
    }
  }

  // MARK: - Titles

  private func popular(_ type: MediaType, _ service: VideoContentService) async -> [MediaItem] {
    (try? await service.fetch(shortcut: .popular, contentType: type, page: 1))?.items ?? []
  }

  /// Full details, links included, cached in the local store the way the detail page
  /// caches a title before Play — the player reads the series from there.
  private func details(_ id: Int?, _ service: VideoContentService) async -> MediaItem? {
    guard let id,
          let item = try? await service.fetchDetails(for: String(id), excludeLinks: false).item
    else { return nil }
    context.localProgressStore.cacheItem(item)
    return item
  }

  /// Episodes stamped the way every Play path stamps them: season number, the item's id
  /// for `/v1/watching`, the series' name.
  private static func stampedEpisodes(_ series: MediaItem) -> [Episode] {
    (series.seasons ?? []).flatMap { season in
      season.episodes.map { episode in
        episode.seasonNumber = season.number
        episode.mediaId = series.id
        episode.seriesTitle = series.localizedTitle
        return episode
      }
    }
  }
}

#Preview {
  PlayerCasesView()
}
#endif
