import Foundation

/// The **shape** of a thing to watch, in Apple's vocabulary: the Apple TV app and the
/// iTunes store know a movie, a show made of seasons made of episodes, and extras that
/// belong to one of those.
///
/// Only shape. What *sort* of work it is — a documentary, a concert, a stand-up set, an
/// anime — is a **genre**, the way Apple files it: a concert is a movie whose genres are
/// music genres, a docuseries is a show filed under Documentary. And 3D is neither: it is
/// a format of one platform's copy of a movie, not a different movie.
public enum MediaKind: String, Codable, Hashable, Sendable, CaseIterable {
  /// One feature: a film, a documentary, a concert, a stand-up special.
  case movie
  /// The container of seasons: a series, a docuseries, a TV show.
  case show
  case season
  case episode
  /// Belongs to one of the above and is never the thing itself — a trailer, a clip.
  case extra
}

public enum ExtraKind: String, Codable, Hashable, Sendable, CaseIterable {
  case trailer
  case teaser
  case clip
  case featurette
  case behindTheScenes
}
