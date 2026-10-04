import Foundation

/// Who said it. A fragment's source is what `MediaPrecedence` ranks, and what an entity's
/// `provenance` records per field.
public enum MediaSource: String, Hashable, Sendable, Codable, CaseIterable {
  case kinopub, apple, tmdb, kinopoisk, imdb, omdb, tvoe, trakt
}

/// The fields precedence is declared for. One case per fact a source can state on its
/// own: a tagline is not a part of somebody's plot, so it is ranked — and kept — apart.
public enum MediaField: String, Hashable, Sendable, Codable, CaseIterable {
  case title, originalTitle, edition, seasonCount, genres, release, ended, runtime,
       contentRating, scores, poster, posterPreview, still, backdrop, logo, countries,
       setlist, formats
  /// `Synopsis.full` — the plot.
  case synopsis
  /// `Synopsis.short` — a line or two; Kinopoisk's `shortDescription`.
  case shortSynopsis
  /// `Synopsis.tagline` — TMDB's `tagline`, Kinopoisk's `slogan`.
  case tagline
}

/// **What one source says about one entity.** A source adapter builds these from its own
/// payload and decides nothing else: which source wins a field is `MediaPrecedence`'s
/// call, never the adapter's.
public struct MediaFragment: Hashable, Sendable, Codable {
  public let source: MediaSource
  /// The language the source's **text** is in — "ru" for kino.pub's plot and Kinopoisk's
  /// slogan, "en" for TMDB asked in English. Nil when the fragment carries no text or the
  /// source did not say. Kept so a policy can prefer the viewer's language over a fixed
  /// source order (see `MediaPrecedence`).
  public var language: String?
  public var entity: MediaEntity

  public init(source: MediaSource, language: String? = nil, entity: MediaEntity) {
    self.source = source
    self.language = language
    self.entity = entity
  }

  public init(_ source: MediaSource, _ kind: MediaKind, language: String? = nil,
              _ fill: (inout MediaEntity) -> Void) {
    var entity = MediaEntity(kind: kind)
    fill(&entity)
    self.init(source: source, language: language, entity: entity)
  }
}

/// **Which source wins which field**, declared once. A source missing from a field's list
/// ranks after every listed one, in `MediaSource` order — so the answer never depends on
/// which network call happened to finish first.
///
/// Precedence only decides the **default** answer. Nothing a lower-ranked source said is
/// thrown away: `MediaEntity.claims` keeps every fragment, so a surface that wants a
/// particular source's fact (Kinopoisk's slogan, TMDB's English plot) asks for it.
public struct MediaPrecedence: Sendable {
  public var order: [MediaField: [MediaSource]]

  public init(order: [MediaField: [MediaSource]]) {
    self.order = order
  }

  public func rank(_ source: MediaSource, for field: MediaField) -> Int {
    let listed = order[field] ?? []
    if let index = listed.firstIndex(of: source) { return index }
    return listed.count + (MediaSource.allCases.firstIndex(of: source) ?? MediaSource.allCases.count)
  }

  // Each line is a product decision, not a technicality. Lines marked TODO(decision) are
  // provisional: what the code does today, written down so it can be changed in one place.
  //
  // TODO(decision): language before source. Every text line below ranks *sources*; none
  // asks which language the viewer reads. kino.pub and Kinopoisk speak Russian, TMDB
  // speaks whatever it was asked in. Proposal: for text fields (title, synopsis,
  // shortSynopsis, tagline) the viewer's language wins first, this order breaks ties.
  // Needs `MediaFragment.language` filled by every adapter (kino.pub and Kinopoisk: "ru";
  // TMDB: its request language) — done for Kinopoisk and TMDB, kino.pub is "ru".
  public static let standard = MediaPrecedence(order: [
    // The copy's own name, as the viewer's catalogue lists it.
    .title: [.kinopub, .apple, .tmdb, .kinopoisk],
    .originalTitle: [.tmdb, .apple, .imdb, .kinopub, .kinopoisk],
    .edition: [.kinopub],
    // What the viewer can play is kino.pub's seasons, not every season that aired.
    .seasonCount: [.kinopub, .tmdb],
    // kino.pub's plot describes the copy that plays. TODO(decision): Kinopoisk's
    // `description` is usually the fuller Russian text — rank it above kino.pub's?
    .synopsis: [.kinopub, .kinopoisk, .apple, .tmdb],
    // Only Kinopoisk has a short description today.
    .shortSynopsis: [.kinopoisk, .apple, .tmdb, .kinopub],
    // TODO(decision): Kinopoisk's Russian slogan vs TMDB's English tagline — today the
    // Russian one wins; with the language rule above this line stops mattering.
    .tagline: [.kinopoisk, .tmdb, .apple],
    // TODO(decision): `.apple` leads several lines but no Apple source exists yet; the
    // order is where it would go, not something that runs. Keep or drop until one lands.
    // kino.pub's genre set is narrow and deliberate (its own catalogue sections); TMDB's
    // is broader. Today kino.pub wins whenever it has any.
    .genres: [.apple, .kinopub, .tmdb, .kinopoisk],
    // A day beats a year; kino.pub only ever knows the year.
    .release: [.tmdb, .apple, .kinopoisk, .kinopub],
    .ended: [.tmdb, .apple, .kinopoisk],
    // The runtime of the file that plays.
    .runtime: [.kinopub, .tmdb, .apple],
    // TODO(decision): one age rating per title, Russian first. Kinopoisk also knows the
    // MPAA rating and TMDB has per-country certifications; `ContentRating.region` can
    // hold either. Should the viewer's region pick, and should the panel ever show two?
    // TODO: kino.pub's own age rating — in the API (the official Apple TV app shows it), field
    // not found yet (docs/providers/kinopub/video.md). Once decoded it is the rating kino.pub
    // itself shows; rank it first?
    .contentRating: [.kinopoisk, .tmdb, .apple, .kinopub],
    // A score is best reported by whoever gave it: IMDb's own dataset beats kino.pub's
    // copy of the same IMDb number.
    .scores: [.imdb, .kinopoisk, .tmdb, .omdb, .kinopub],
    // TODO(decision): TMDB's artwork is textless and high-resolution, Kinopoisk's poster
    // is the Russian one-sheet. A Russian-speaking viewer may want the Russian poster.
    .poster: [.apple, .tmdb, .kinopoisk, .kinopub],
    // An episode's frame: kino.pub's is full-size and from the very file that plays;
    // TMDB's arrives at 300 px. The episode rail has always preferred kino.pub's.
    .still: [.kinopub, .tmdb, .apple],
    .backdrop: [.apple, .tmdb, .kinopoisk, .kinopub],
    .logo: [.apple, .tmdb, .kinopoisk],
    .countries: [.kinopub, .tmdb, .kinopoisk],
    // The setlist of the recording that plays.
    .setlist: [.kinopub],
    // The stream's own formats: only the platform that serves it knows.
    .formats: [.kinopub],
    // A grid's poster comes from the same catalogue as the card it sits in.
    .posterPreview: [.kinopub, .tmdb, .kinopoisk],
  ])
}

/// The fragments for one playback, level by level: the thing itself, the season it is
/// in, and the show or film it belongs to. Every source adds what it knows at whichever
/// level it knows it.
public struct MediaContextDraft: Sendable, Codable {
  public var item: [MediaFragment]
  public var season: [MediaFragment]
  public var parent: [MediaFragment]

  public init(item: [MediaFragment] = [], season: [MediaFragment] = [],
              parent: [MediaFragment] = []) {
    self.item = item
    self.season = season
    self.parent = parent
  }

  public mutating func add(_ other: MediaContextDraft) {
    item += other.item
    season += other.season
    parent += other.parent
  }
}

public enum MediaAggregator {

  /// One entity from every fragment about it. Nil when there is nothing to merge.
  public static func merge(_ fragments: [MediaFragment],
                           precedence: MediaPrecedence = .standard) -> MediaEntity? {
    guard !fragments.isEmpty else { return nil }
    // Identity (kind, numbering) is the same fact whoever states it; a fixed order only
    // keeps the answer independent of arrival order.
    let byIdentity = fragments.sorted { sourceIndex($0.source) < sourceIndex($1.source) }
    let first = byIdentity[0].entity

    var provenance: [MediaField: MediaSource] = [:]

    func ranked(_ field: MediaField) -> [MediaFragment] {
      fragments.enumerated().sorted { lhs, rhs in
        let left = precedence.rank(lhs.element.source, for: field)
        let right = precedence.rank(rhs.element.source, for: field)
        return left != right ? left < right : lhs.offset < rhs.offset
      }.map { $0.element }
    }

    func pick<Value>(_ field: MediaField, _ read: (MediaEntity) -> Value?) -> Value? {
      for fragment in ranked(field) {
        if let value = read(fragment.entity) {
          provenance[field] = fragment.source
          return value
        }
      }
      return nil
    }

    var entity = MediaEntity(kind: first.kind)
    entity.extraKind = byIdentity.lazy.compactMap(\.entity.extraKind).first
    entity.seasonNumber = byIdentity.lazy.compactMap(\.entity.seasonNumber).first
    entity.episodeNumber = byIdentity.lazy.compactMap(\.entity.episodeNumber).first

    var ids: [ExternalID] = []
    for fragment in byIdentity {
      for id in fragment.entity.ids where !ids.contains(id) { ids.append(id) }
    }
    entity.ids = ids

    var labels: [MediaLabel] = []
    for fragment in byIdentity {
      for label in fragment.entity.labels where !labels.contains(label) { labels.append(label) }
    }
    entity.labels = labels

    // A blank string is a source with nothing to say, not a value that wins the field —
    // kino.pub ships `""` for every episode it never named.
    // An episode's "Эпизод 1" is its number, not its name (`EpisodeTitle`) — it loses to a
    // real name from any source, and is never shown as one.
    entity.title = first.kind == .episode
      ? pick(.title) { EpisodeTitle.meaningful($0.title) }
      : pick(.title) { $0.title.nonBlank }
    entity.originalTitle = pick(.originalTitle) { $0.originalTitle.nonBlank }
    entity.edition = pick(.edition) { $0.edition.nonBlank }
    entity.seasonCount = pick(.seasonCount) { $0.seasonCount }
    entity.synopsis = Synopsis(short: pick(.shortSynopsis) { $0.synopsis.short.nonBlank },
                               full: pick(.synopsis) { $0.synopsis.full.nonBlank },
                               tagline: pick(.tagline) { $0.synopsis.tagline.nonBlank })
    // Genres are one list from one source, not a union: the order *is* the claim (its
    // first is the primary genre), and splicing two sources' orders makes a primary
    // genre neither of them gave.
    entity.genres = pick(.genres) { $0.genres.isEmpty ? nil : $0.genres } ?? []
    entity.release = pick(.release) { $0.release }
    entity.ended = pick(.ended) { $0.ended }
    entity.runtime = pick(.runtime) { $0.runtime }
    entity.contentRating = pick(.contentRating) { $0.contentRating }
    entity.artwork = ArtworkSet(
      poster: pick(.poster) { $0.artwork.poster },
      still: pick(.still) { $0.artwork.still },
      backdrop: pick(.backdrop) { $0.artwork.backdrop },
      logo: pick(.logo) { $0.artwork.logo },
      posterPreview: pick(.posterPreview) { $0.artwork.posterPreview })
    entity.countries = pick(.countries) { $0.countries.isEmpty ? nil : $0.countries } ?? []
    entity.setlist = pick(.setlist) { $0.setlist.isEmpty ? nil : $0.setlist } ?? []
    entity.formats = pick(.formats) { $0.formats.isEmpty ? nil : $0.formats } ?? []

    // Scores are kept side by side: one per provider, reported by the best-ranked source.
    var scores: [Score] = []
    for fragment in ranked(.scores) {
      for score in fragment.entity.scores
      where !scores.contains(where: { $0.provider == score.provider }) {
        scores.append(score)
        if provenance[.scores] == nil { provenance[.scores] = fragment.source }
      }
    }
    entity.scores = scores
    entity.provenance = provenance
    // Every source's own statement, kept whole: the merge picks a default per field, it
    // does not decide what the app may know. Flattened, so a re-merge never nests.
    entity.claims = byIdentity.flatMap { fragment in
      fragment.entity.claims.isEmpty ? [fragment.stripped] : fragment.entity.claims
    }
    return entity
  }

  /// A whole playback: the thing, its season, its parent. Nil without the thing itself.
  public static func merge(_ draft: MediaContextDraft,
                           precedence: MediaPrecedence = .standard) -> MediaContext? {
    guard let item = merge(draft.item, precedence: precedence) else { return nil }
    return MediaContext(item: item,
                        season: merge(draft.season, precedence: precedence),
                        parent: merge(draft.parent, precedence: precedence))
  }

  private static func sourceIndex(_ source: MediaSource) -> Int {
    MediaSource.allCases.firstIndex(of: source) ?? MediaSource.allCases.count
  }
}

extension MediaFragment {
  /// The fragment without claims of its own — what a merged entity stores.
  var stripped: MediaFragment {
    var copy = self
    copy.entity.claims = []
    copy.entity.provenance = [:]
    return copy
  }
}
