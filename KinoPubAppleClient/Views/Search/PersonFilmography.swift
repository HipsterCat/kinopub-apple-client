//
//  PersonFilmography.swift
//  KinoPubAppleClient
//
//  Merge Kinopub person listings with TMDB combined_credits into **one chronological
//  grid** — titles missing from the catalog keep a «Нет на Кинопабе» badge in the
//  same timeline (no second rail). Keyed by TMDB id for a later ID join.
//
//  Matching uses the **loaded Kinopub window only** — never prefetch every page.
//  On year sort, a TMDB credit is eligible as unavailable only when its year sits
//  inside the years already loaded (same timeline). Credits that may still appear
//  on later pages stay out until that window covers them or the listing is complete.
//  Future / unreleased titles keep no absence chip — art often exists nowhere yet,
//  so the chip would falsely imply Kinopub-only absence (Sasha, 2026-11-26).
//

import Foundation
import KinoPubBackend
import KinoPubMetadata
import KinoPubUI

enum PersonFilmography {
  /// Synthetic card ids stay outside kino.pub's positive item ids.
  private static let externalIDBase = -9_100_000

  /// How far the Kinopub listing has been read — shared timeline with TMDB credits.
  struct MatchWindow: Equatable, Sendable {
    /// Years present on already-loaded Kinopub pages (year sort). Nil when empty or
    /// the active sort is not year-based.
    var coveredYears: ClosedRange<Int>?
    /// True when no further Kinopub pages will arrive (`!hasMore && !loading`).
    var kinopubListingComplete: Bool

    /// Year-sorted person filmography: the loaded pages cover `min…max` year seen.
    static func yearSorted(items: [MediaItem],
                           complete: Bool,
                           descending: Bool = true) -> MatchWindow {
      let years = items.map(\.year).filter { $0 > 0 }
      guard let lo = years.min(), let hi = years.max() else {
        return MatchWindow(coveredYears: nil, kinopubListingComplete: complete)
      }
      // Descending loads newest→oldest; ascending oldest→newest. Either way the
      // closed range of loaded years is the safe match window.
      _ = descending
      return MatchWindow(coveredYears: lo...hi, kinopubListingComplete: complete)
    }

    /// Non-year sorts have no safe partial window without prefetch — wait for complete.
    static func completeOnly(_ complete: Bool) -> MatchWindow {
      MatchWindow(coveredYears: nil, kinopubListingComplete: complete)
    }

    /// Whether this TMDB credit may be shown as unavailable against the loaded set.
    func allowsUnavailable(year: Int?) -> Bool {
      if kinopubListingComplete { return true }
      guard let year, year > 0, let coveredYears else { return false }
      return coveredYears.contains(year)
    }
  }

  /// TMDB credits that do not already appear in the **loaded** Kinopub listing —
  /// matched by localized / original / full title; only credits inside `window`.
  static func externalCards(credits: [PersonCredit],
                            kinopubItems: [MediaItem],
                            role: MediaPerson.Role,
                            window: MatchWindow) -> [MediaCard] {
    let known = Set(kinopubItems.flatMap { item -> [String] in
      [item.title, item.localizedTitle, item.originalTitle]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .map(normalize)
    }.filter { !$0.isEmpty })

    let acting = role == .actor
    var out: [MediaCard] = []
    for (offset, credit) in credits.enumerated() {
      if acting, credit.character == nil, credit.job != nil { continue }
      if !acting, credit.job == nil, credit.character != nil { continue }
      let titles = [credit.title, credit.originalTitle].compactMap { $0 }.map(normalize)
      if titles.contains(where: { known.contains($0) }) { continue }
      // Still may land on a later Kinopub page — stay out of the unavailable set.
      guard window.allowsUnavailable(year: credit.year) else { continue }
      var card = MediaCard(
        id: externalIDBase - offset,
        posterURL: credit.posterURL?.absoluteString ?? "",
        title: credit.title,
        scores: MediaScores(tmdb: credit.voteAverage),
        isSeries: credit.mediaType == "tv",
        year: credit.year,
        primaryAction: .openDetail
      )
      // Future / unreleased (Avatar 5 · 2031): art often doesn't exist anywhere — a
      // «Not on Kinopub» chip would imply Kinopub alone is missing it (Sasha, 2026-11-26).
      if !isUnreleased(credit) {
        // Same chip copy as the episode rail (`MediaItem_NotOnKinoPubChip` → «Нет на Кинопабе»).
        card.unavailableNotice = "MediaItem_NotOnKinoPubChip".localized
      }
      out.append(card)
    }
    return out
  }

  /// Release date still ahead, or calendar year after this year when TMDB has no day.
  static func isUnreleased(_ credit: PersonCredit, now: Date = Date()) -> Bool {
    if let date = credit.releaseDate { return date > now }
    guard let year = credit.year, year > 0 else { return false }
    return year > Calendar.current.component(.year, from: now)
  }

  /// Poster pixel width for filmography tiles (weserv `w=` / worker preference).
  static let posterPixelWidth = 454

  /// One chronological grid: Kinopub titles and TMDB-only cards interleaved by year.
  /// No second «Not on Kinopub» rail (Sasha, 2026-11-26).
  ///
  /// Matched Kinopub titles prefer `/img/poster/by/kinopub/{id}` (language on the
  /// route) wrapped by `images.weserv.nl` — not bare TMDB size tokens.
  static func mergedTimeline(kinopubItems: [MediaItem],
                             externalCards: [MediaCard],
                             descending: Bool,
                             images: TitleImageRoute = TitleImageRoute(baseURL: nil)) -> [MediaCard] {
    let kinopub = kinopubItems.map { kinopubCard($0, images: images) }
    return (kinopub + externalCards).sorted { a, b in
      let ya = a.year ?? 0
      let yb = b.year ?? 0
      if ya != yb {
        return descending ? ya > yb : ya < yb
      }
      // Kinopub (positive ids) before TMDB-only synthetics at the same year.
      let aKinopub = a.id > 0
      let bKinopub = b.id > 0
      if aKinopub != bKinopub { return aKinopub && !bKinopub }
      return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
    }
  }

  /// Worker poster-by-id (with route language) → `images.weserv.nl`; falls back to
  /// the listing's staticpop URL when the worker is not configured.
  static func kinopubCard(_ item: MediaItem, images: TitleImageRoute) -> MediaCard {
    let base = MediaCard(item)
    guard images.isConfigured,
          let worker = images.url(
            .poster,
            kinopubID: item.id,
            imdb: item.imdb,
            width: nil
          )
    else { return base }
    let wrapped = WeservImageURL.wrapping(worker, width: posterPixelWidth)
    return base.withPosterURL(wrapped.absoluteString)
  }

  private static func normalize(_ title: String) -> String {
    title
      .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
