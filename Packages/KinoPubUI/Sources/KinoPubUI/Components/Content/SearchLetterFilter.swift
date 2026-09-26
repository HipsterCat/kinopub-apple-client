import Foundation

/// The first letters typed into search, before the server is asked: an index over
/// what is already there, not a search.
///
/// `loaded` is the listing on screen — the catalog as the filters narrowed it — and
/// its matches are the answer. `elsewhere` is what the device holds beyond it (the
/// shelves); its matches are never mixed into that answer — a "4K anime" listing must
/// not gain a comedy in HD — and come back apart, as other results, without repeats.
public enum SearchLetterFilter {
  public static func split(loaded: [MediaCard], elsewhere: [MediaCard],
                           letters: String) -> (matches: [MediaCard], others: [MediaCard]) {
    var seen = Set<Int>()
    let matches = loaded.filter { $0.hasWord(startingWith: letters) && seen.insert($0.itemID).inserted }
    let others = elsewhere.filter { $0.hasWord(startingWith: letters) && seen.insert($0.itemID).inserted }
    return (matches, others)
  }
}

public extension MediaCard {
  /// A word of the title or original title starts with `letters` ("та" → "Табу",
  /// not "Звезда не того масштаба"), ignoring case and diacritics ("е" finds "ё").
  func hasWord(startingWith letters: String) -> Bool {
    guard !letters.isEmpty else { return false }
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .anchored]
    return [title, subtitle ?? ""].contains { text in
      text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .contains { $0.range(of: letters, options: options) != nil }
    }
  }
}
