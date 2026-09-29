import Foundation

/// Who said it. A fragment's source is what `MediaPrecedence` ranks, and what an entity's
/// `provenance` records per field.
public enum MediaSource: String, Hashable, Sendable, Codable, CaseIterable {
  case kinopub, apple, tmdb, kinopoisk, imdb, omdb, tvoe, trakt
}

/// The fields precedence is declared for.
public enum MediaField: String, Hashable, Sendable, Codable, CaseIterable {
  case title, originalTitle, edition, synopsis, genres, release, ended, runtime,
       contentRating, scores, poster, still, backdrop, logo, countries
}

/// **What one source says about one entity.** A source adapter builds these from its own
/// payload and decides nothing else: which source wins a field is `MediaPrecedence`'s
/// call, never the adapter's.
public struct MediaFragment: Hashable, Sendable {
  public let source: MediaSource
  public var entity: MediaEntity

  public init(source: MediaSource, entity: MediaEntity) {
    self.source = source
    self.entity = entity
  }

  public init(_ source: MediaSource, _ kind: MediaKind, _ fill: (inout MediaEntity) -> Void) {
    var entity = MediaEntity(kind: kind)
    fill(&entity)
    self.init(source: source, entity: entity)
  }
}

/// **Which source wins which field**, declared once. A source missing from a field's list
/// ranks after every listed one, in `MediaSource` order — so the answer never depends on
/// which network call happened to finish first.
///
/// The standard order follows the `metadata-service` skill's precedence table: artwork
/// from the catalogues that have the best of it, scores side by side, kino.pub for what
/// only kino.pub knows (the Russian title and plot of the copy the viewer is about to play,
/// and its real runtime).
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

  public static let standard = MediaPrecedence(order: [
    .title: [.kinopub, .apple, .tmdb, .kinopoisk],
    .originalTitle: [.tmdb, .apple, .imdb, .kinopub, .kinopoisk],
    .edition: [.kinopub],
    .synopsis: [.kinopub, .kinopoisk, .apple, .tmdb],
    .genres: [.apple, .kinopub, .tmdb, .kinopoisk],
    .release: [.tmdb, .apple, .kinopoisk, .kinopub],
    .ended: [.tmdb, .apple, .kinopoisk],
    .runtime: [.kinopub, .tmdb, .apple],
    .contentRating: [.kinopoisk, .tmdb, .apple, .kinopub],
    // A score is best reported by whoever gave it: IMDb's own dataset beats kino.pub's
    // copy of the same IMDb number.
    .scores: [.imdb, .kinopoisk, .tmdb, .omdb, .kinopub],
    .poster: [.apple, .tmdb, .kinopoisk, .kinopub],
    .still: [.tmdb, .apple, .kinopub],
    .backdrop: [.apple, .tmdb, .kinopoisk, .kinopub],
    .logo: [.apple, .tmdb],
    .countries: [.kinopub, .tmdb, .kinopoisk],
  ])
}

/// The fragments for one playback, level by level: the thing itself, the season it is
/// in, and the show or film it belongs to. Every source adds what it knows at whichever
/// level it knows it.
public struct MediaContextDraft: Sendable {
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
    entity.title = pick(.title) { $0.title.nonBlank }
    entity.originalTitle = pick(.originalTitle) { $0.originalTitle.nonBlank }
    entity.edition = pick(.edition) { $0.edition.nonBlank }
    let synopsis = mergeSynopsis(ranked(.synopsis))
    entity.synopsis = synopsis.value
    if let source = synopsis.source { provenance[.synopsis] = source }
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
      logo: pick(.logo) { $0.artwork.logo })
    entity.countries = pick(.countries) { $0.countries.isEmpty ? nil : $0.countries } ?? []

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

  /// Each part of a synopsis from the best source that has *that* part: kino.pub's plot
  /// and TMDB's tagline do not compete.
  private static func mergeSynopsis(_ ranked: [MediaFragment])
    -> (value: Synopsis, source: MediaSource?) {
    var synopsis = Synopsis()
    var source: MediaSource?
    for fragment in ranked {
      let part = fragment.entity.synopsis
      if synopsis.full == nil, let full = part.full.nonBlank {
        synopsis.full = full
      }
      if synopsis.short == nil, let short = part.short.nonBlank {
        synopsis.short = short
      }
      if synopsis.tagline == nil, let tagline = part.tagline.nonBlank {
        synopsis.tagline = tagline
      }
      if source == nil, part.best != nil {
        source = fragment.source
      }
    }
    return (synopsis, source)
  }

  private static func sourceIndex(_ source: MediaSource) -> Int {
    MediaSource.allCases.firstIndex(of: source) ?? MediaSource.allCases.count
  }
}
