//
//  ContinueWatchingLocalOverlay.swift
//

import Foundation

/// How local resume points paint the Continue Watching row **without** touching
/// `ContentStore`'s TTL. The cached cards stay the last server-backed snapshot;
/// this plan is applied at read time so a progress bar (or a just-finished hide)
/// can move on the next assemble, not on the next 60s refresh.
///
/// The player writes `LocalWatchProgressStore` every ~10s. Home must not persist
/// those ticks back into `rows-v2.json` — that is what the cache is for, and
/// rewriting it from a playhead would be the opposite of trusting it.
public enum ContinueWatchingLocalOverlay {

  public struct Card: Equatable, Sendable {
    public var itemID: Int
    public var isSeries: Bool
    public var season: Int?
    public var video: Int?
    /// The newest qualifying activity in the saved ranking.
    public var activityDate: Date?
    /// Resume bar on the cached snapshot, so a stale local playhead cannot paint
    /// over further progress from another device.
    public var progress: Double?

    public init(itemID: Int, isSeries: Bool, season: Int?, video: Int?,
                activityDate: Date? = nil, progress: Double? = nil) {
      self.itemID = itemID
      self.isSeries = isSeries
      self.season = season
      self.video = video
      self.activityDate = activityDate
      self.progress = progress
    }
  }

  public struct Local: Equatable, Sendable {
    public var itemID: Int
    public var isSeries: Bool
    public var season: Int?
    public var episode: Int?
    public var isFinished: Bool
    public var isResumable: Bool
    public var progress: Double?
    public var updatedAt: TimeInterval
    /// Snapshot exists so a title the server has not listed yet can still draw a card.
    public var canInsert: Bool

    public init(itemID: Int,
                isSeries: Bool,
                season: Int?,
                episode: Int?,
                isFinished: Bool,
                isResumable: Bool,
                progress: Double?,
                updatedAt: TimeInterval,
                canInsert: Bool) {
      self.itemID = itemID
      self.isSeries = isSeries
      self.season = season
      self.episode = episode
      self.isFinished = isFinished
      self.isResumable = isResumable
      self.progress = progress
      self.updatedAt = updatedAt
      self.canInsert = canInsert
    }
  }

  public struct Mutation: Equatable, Sendable {
    public var progress: Double?
    public var season: Int?
    public var video: Int?
    public init(progress: Double?, season: Int?, video: Int?) {
      self.progress = progress
      self.season = season
      self.video = video
    }
  }

  public struct Plan: Equatable, Sendable {
    public var hiddenIDs: Set<Int>
    public var mutations: [Int: Mutation]
    /// New plays merged into the saved ranking, including local-only inserts.
    public var order: [Int]
    public var insertIDs: [Int]

    public init(hiddenIDs: Set<Int>,
                mutations: [Int: Mutation],
                order: [Int],
                insertIDs: [Int]) {
      self.hiddenIDs = hiddenIDs
      self.mutations = mutations
      self.order = order
      self.insertIDs = insertIDs
    }
  }

  /// - Parameters:
  ///   - snapshotTakenAt: when the cached row was fetched. Only a play after it moves a
  ///     ``Local`` to the front: lifting every title ever played on this device put
  ///     weeks-old samples above new episodes (Sasha, 2026-10-25). Nil lifts every local title.
  ///   - playedAt: this device's newest qualifying play per title, read from the resume
  ///     points themselves (no title payload needed) and already past the
  ///     ``ContinueWatchingOrder/qualifyingPlayDate(_:position:rules:now:)`` rules. A card
  ///     already on the row ranks by the later of its saved date and this, whatever the
  ///     snapshot's age: a refetch that lost the play date can never push a title just
  ///     watched below the ones it was ahead of. Titles not on the row are not touched.
  public static func plan(cards: [Card],
                          locals: [Local],
                          snapshotTakenAt: Date? = nil,
                          playedAt: [Int: Date] = [:]) -> Plan {
    let cardByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.itemID, $0) })
    let recents = locals.sorted { $0.updatedAt > $1.updatedAt }

    var hidden = Set<Int>()
    var mutations: [Int: Mutation] = [:]
    var insertIDs: [Int] = []

    for local in recents {
      let card = cardByID[local.itemID]
      let present = card != nil

      if local.isFinished, !local.isSeries {
        if present { hidden.insert(local.itemID) }
        continue
      }

      if local.isFinished, local.isSeries {
        let next = ContinueWatchingEpisode.forSeries(
          local: (local.season, local.episode, true),
          history: nil,
          finishedInSeason: local.episode.map { [$0] } ?? [],
          watchedCount: nil,
          total: nil
        )
        guard next.hasEpisode else {
          if present { hidden.insert(local.itemID) }
          continue
        }
        let season = next.season ?? local.season ?? card?.season
        let video = next.episode
        let mutation = Mutation(progress: nil, season: season, video: video)
        if present {
          if let nextEp = video, let cardEp = card?.video,
             (season ?? 0) < (card?.season ?? 0)
              || ((season ?? 0) == (card?.season ?? 0) && nextEp < cardEp) {
            continue
          }
          mutations[local.itemID] = mutation
        }
        // Do not insert a finished series the row already dropped — without a
        // season map we would invent E+1 forever after the title left watching.
        continue
      }

      guard local.isResumable else { continue }
      if present, Self.localIsBehind(local, card: card) { continue }
      let season = local.season ?? card?.season
      let video = local.episode ?? card?.video
      let mutation = Mutation(progress: local.progress, season: season, video: video)
      if present {
        mutations[local.itemID] = mutation
      } else if local.canInsert {
        insertIDs.append(local.itemID)
        mutations[local.itemID] = mutation
      }
    }

    var activityDates = cardByID.compactMapValues(\.activityDate)
    let liftedAfter = snapshotTakenAt?.timeIntervalSince1970 ?? -.infinity
    for local in recents where local.updatedAt > liftedAfter {
      let id = local.itemID
      let localPlay = Date(timeIntervalSince1970: local.updatedAt)
      activityDates[id] = max(activityDates[id] ?? .distantPast, localPlay)
    }
    for (id, date) in playedAt where cardByID[id] != nil {
      activityDates[id] = max(activityDates[id] ?? .distantPast, date)
    }
    let order = (cards.map(\.itemID) + insertIDs).filter { !hidden.contains($0) }.sorted {
      (activityDates[$0] ?? .distantPast) > (activityDates[$1] ?? .distantPast)
    }

    return Plan(hiddenIDs: hidden, mutations: mutations, order: order, insertIDs: insertIDs)
  }

  /// Stale local resume from this device, behind a snapshot that already moved on
  /// (progress written on another device, then Home refetched).
  static func localIsBehind(_ local: Local, card: Card?) -> Bool {
    guard let card else { return false }
    if local.isSeries {
      let localSeason = local.season ?? 0
      let cardSeason = card.season ?? 0
      if localSeason != cardSeason { return localSeason < cardSeason }
      if let le = local.episode, let cv = card.video { return le < cv }
      return false
    }
    if let lp = local.progress, let cp = card.progress { return lp + 0.001 < cp }
    return false
  }
}
