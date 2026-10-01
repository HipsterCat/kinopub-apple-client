import Foundation

/// **What is playing, inside what** — an episode inside its season inside its show, a
/// trailer inside its film, a film on its own.
///
/// The inheritance rules live here and nowhere else: which facts an episode borrows from
/// its season and show, which it must never borrow, and which picture stands for it. A
/// surface asks the context; it does not walk the chain itself, so the info panel, a card
/// and Top Shelf cannot come to three different answers.
public struct MediaContext: Hashable, Sendable {
  public var item: MediaEntity
  public var season: MediaEntity?
  /// The show an episode or season belongs to; the film or show an extra belongs to.
  public var parent: MediaEntity?

  public init(item: MediaEntity, season: MediaEntity? = nil, parent: MediaEntity? = nil) {
    self.item = item
    self.season = season
    self.parent = parent
  }

  /// Where a missing fact is looked for, nearest first.
  private var chain: [MediaEntity] {
    [item] + [season, parent].compactMap { $0 }
  }

  /// The name the viewer knows this by: the show for an episode, the film for its
  /// trailer, the thing itself otherwise.
  public var title: String? {
    switch item.kind {
    case .episode, .season, .extra: return parent?.title ?? item.title
    case .movie, .show: return item.title
    }
  }

  // MARK: - Inherited

  /// Nobody files an episode under a genre; its show's genres are its genres.
  public var genres: [Genre] {
    chain.first { !$0.genres.isEmpty }?.genres ?? []
  }

  /// The one genre to show where there is room for one.
  public var primaryGenre: Genre? { genres.first }

  public var contentRating: ContentRating? {
    chain.lazy.compactMap { $0.contentRating }.first
  }

  /// The episode's own description; the season's, then the show's, when it has none —
  /// a line about the show beats an empty panel.
  public var synopsis: String? {
    chain.lazy.compactMap { $0.synopsis.best }.first
  }

  /// The episode's air date; the season's, then the show's, when it has none.
  public var release: ReleaseDate? {
    chain.lazy.compactMap { $0.release }.first
  }

  // MARK: - Never inherited

  /// Only the item's own scores. A show's 8.8 printed on one of its episodes would be a
  /// number nobody gave that episode.
  public var scores: [Score] { item.scores }

  // MARK: - Artwork

  /// The picture that stands for what is playing, best first — the caller walks the list
  /// when one fails to load. **An episode is its own still**, then its season's poster,
  /// then its show's; a trailer is its own frame, then its film's poster.
  public var artworkCandidates: [URL] {
    let candidates: [URL?]
    switch item.kind {
    case .episode:
      candidates = [item.artwork.still, season?.artwork.poster, parent?.artwork.poster,
                    parent?.artwork.backdrop, item.artwork.poster]
    case .extra:
      candidates = [item.artwork.still, parent?.artwork.poster, parent?.artwork.backdrop,
                    item.artwork.poster]
    case .season:
      candidates = [item.artwork.poster, parent?.artwork.poster, parent?.artwork.backdrop]
    case .movie, .show:
      candidates = [item.artwork.poster, item.artwork.backdrop, item.artwork.still]
    }
    var seen = Set<URL>()
    return candidates.compactMap { $0 }.filter { seen.insert($0).inserted }
  }
}
