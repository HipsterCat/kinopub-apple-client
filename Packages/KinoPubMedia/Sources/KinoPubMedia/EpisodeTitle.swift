import Foundation

/// **Whether an episode's "title" is a name or just its number spelled out.**
///
/// Sources fill the title field when they have no name: kino.pub ships «Эпизод 1», TMDB's
/// Russian locale answers «Эпизод 1» or «Серия 1» for untranslated episodes, others print
/// "Episode 1" or "S01E01". Shown as a name that becomes «Season 1, Episode 1: Эпизод 1».
/// A placeholder is a source with nothing to say — the merge treats it like a blank, so a
/// real name from another source can win, and no surface prints the number twice.
public enum EpisodeTitle {

  /// Words that only ever *number* an episode, in the languages our sources answer in.
  private static let numberingWords: Set<String> = [
    "эпизод", "серия", "выпуск", "часть", "эп", "episode", "ep", "part", "chapter", "no",
  ]

  /// "Эпизод 1", "Серия №3", "1 серия", "Episode 12", "Ep. 4", "S01E01", "#5", "7" — true.
  /// "Pilot", "Эпизод с Ревеккой", "Part of the Plan" — false: any other word makes it a
  /// name. A bare number counts as a placeholder, which costs the rare episode really
  /// called "1984".
  public static func isPlaceholder(_ title: String) -> Bool {
    let folded = title.folding(options: [.caseInsensitive, .diacriticInsensitive,
                                         .widthInsensitive], locale: nil)
    let tokens = folded
      .replacingOccurrences(of: #"s\d+\s*e\d+"#, with: " ", options: .regularExpression)
      .split { !$0.isLetter && !$0.isNumber }
      .map(String.init)
    let words = tokens.filter { !$0.allSatisfy(\.isNumber) }
    return words.allSatisfy { numberingWords.contains($0) }
  }

  /// The name, or nil when there is none — blank, or only a number spelled out.
  public static func meaningful(_ title: String?) -> String? {
    guard let title = title.nonBlank, !isPlaceholder(title) else { return nil }
    return title
  }
}
