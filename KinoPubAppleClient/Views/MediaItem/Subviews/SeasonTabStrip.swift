//
//  SeasonTabStrip.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubUI

/// One stop in the season strip above the episode rail: a season, or a run of seasons that
/// stand in the same place.
struct SeasonTab: Identifiable, Equatable {

  /// Where the season stands. It is all the strip says about a season besides its number.
  enum Status: Equatable {
    /// kino.pub has it.
    case available
    /// Announced, not out yet — a filled clock.
    case soon
    /// Out somewhere, but kino.pub does not have it — a lock.
    case unavailable

    /// The glyph after the number. None when there is something to watch.
    var symbol: String? {
      switch self {
      case .available: nil
      case .soon: "clock.fill"
      case .unavailable: "lock.fill"
      }
    }
  }

  /// `Season.id` for a season kino.pub has. For the rest, the id of the rail card that stands
  /// for them — negative and synthetic like every other id kino.pub did not issue, so the
  /// two never meet.
  let id: Int
  /// The real season numbers (the title-parsed ones, not kino.pub's re-numbering), `first`
  /// equal to `last` for a single season.
  let first: Int
  let last: Int
  let status: Status

  /// "4", or "19–20" for a run.
  var label: String {
    first == last ? "\(first)" : "\(first)–\(last)"
  }

  /// What VoiceOver says for the pill: the glyph alone means nothing spoken.
  var spokenLabel: String {
    let seasons = first == last
      ? String(format: "MediaItem_SeasonSingle".localized, first)
      : String(format: "MediaItem_SeasonsRange".localized, first, last)
    switch status {
    case .available: return seasons
    case .soon: return "\(seasons), \("MediaItem_NotAvailableYet".localized)"
    case .unavailable: return "\(seasons), \("MediaItem_NotOnKinoPub".localized)"
    }
  }
}

/// The line above the episode rail: the word «Сезон» (always secondary), 20 pt of air, and a
/// pill per stop with none between them.
///
/// The line is there whatever the show has. One season is not a choice, so it reads
/// «Сезон 1» with no pills — and is exactly as tall as the same line with them, so the rail
/// under it does not move between titles. Pills are as tall as the headline text plus 10 pt
/// above and below, 24 pt of padding each side of the text, and never narrower than tall
/// (a lone digit is about a circle, «10» and «4–7» are wider). Seasons that are not on
/// kino.pub take the secondary colour and a glyph after the number: a filled clock for those
/// still to come, a lock for those it lacks. The selected pill is the filled one.
///
/// Focus (tvOS) lives in here. The strip is a `.focusSection()` whose default focus, at
/// user-initiated priority (which is what a remote move is), is the selected pill: Down from
/// the hero and Up from an episode land on the season you are in, however far across a
/// neighbour is nearer. Measured 2026-10-11, tvOS 26.5 and 27.2: `.focusSection()` alone, or
/// with `prefersDefaultFocus` in a `focusScope`, took the pill nearest in x. Selection
/// follows focus, so where focus lands is what the rail scrolls to.
struct SeasonTabStrip: View {

  let tabs: [SeasonTab]
  let selectedID: Int?
  /// Leading and trailing margin: the rail's, so the word starts where the first card does.
  let inset: CGFloat
  /// A pill was pressed, or (tvOS) took focus. Told even when it is already selected; the
  /// owner decides whether that moves anything.
  let onSelect: (SeasonTab) -> Void
  /// Bumped by the page when it hands focus down to the strip (tvOS; no other platform has
  /// a remote to take it).
  var entryToken: Int = 0

#if os(tvOS)
  @FocusState private var focusedID: Int?
#endif

  /// Headline text plus this above and below is a pill's height — and the line's.
  static let verticalPadding: CGFloat = 10
  /// Each side of a pill's text, on top of the minimum width (as wide as tall): a lone digit
  /// stays about a circle, «10» and «4–7» are wider than one.
  static let horizontalPadding: CGFloat = 24
  /// Between the word and the first pill (Sasha, 2026-10-11).
  static let labelGap: CGFloat = 20
  static let font: Font = .headline.weight(.semibold)

  /// Whether focus is on one of the pills, which is what lights the unselected ones: with
  /// focus down in the episodes they step back to secondary. No other platform has a focus
  /// to be elsewhere.
  private var stripHasFocus: Bool {
#if os(tvOS)
    focusedID != nil
#else
    true
#endif
  }

  /// One season is not a choice: the word says which, and nothing is pressable.
  private var title: String {
    guard tabs.count == 1, let only = tabs.first else { return "Season".localized }
    return String(format: "MediaItem_SeasonSingle".localized, only.first)
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 0) {
        Text(title)
          .font(Self.font)
          .foregroundStyle(.secondary)
          .padding(.vertical, Self.verticalPadding)
          .padding(.trailing, tabs.count > 1 ? Self.labelGap : 0)

        if tabs.count > 1 {
          ForEach(tabs) { tab in
            button(for: tab)
          }
        }
      }
      .padding(.horizontal, inset)
    }
    // A focused pill grows past its own bounds; the scroll view would shave it.
    .scrollClipDisabled()
#if os(tvOS)
    .frame(maxWidth: .infinity)
    // The section makes the strip one stop for the engine, and the scope decides *which* pill
    // it lands on (`prefersDefaultFocus` below). Geometry alone picks the one physically
    // nearest, wrong as soon as the rail has scrolled away from the start of its season.
    .focusSection()
    .defaultFocus($focusedID, selectedID, priority: .userInitiated)
    .onChange(of: focusedID) { _, id in
      // Left/Right onto another pill selects it; re-focusing the selected one is not a move.
      guard let id, let tab = tabs.first(where: { $0.id == id }) else { return }
      onSelect(tab)
    }
    .onChange(of: entryToken) { _, _ in
      focusedID = selectedID ?? tabs.first?.id
    }
#endif
  }

  @ViewBuilder
  private func button(for tab: SeasonTab) -> some View {
    let isSelected = tab.id == selectedID
    Button {
      onSelect(tab)
    } label: {
      SeasonPill(tab: tab, isSelected: isSelected, stripHasFocus: stripHasFocus)
    }
#if os(tvOS)
    .focused($focusedID, equals: tab.id)
    // Borderless, so no focus code of ours. It draws no lift on a text label — what shows
    // where you are is the fill, which follows focus (selection does). **Not** `.glass`
    // with a capsule: that is the system pill, but it pads its label itself — measured
    // 2026-10-11, tvOS 26.5, 104 pt tall and 134 wide for one digit, where this strip is
    // headline + 20 (66) and as wide as tall. Re-probe next SDK; ROADMAP has the line.
    .buttonStyle(.borderless)
#else
    .buttonStyle(.plain)
#endif
    .accessibilityLabel(tab.spokenLabel)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

/// A season pill: the number (or run), then the glyph if the season is not on kino.pub.
/// Filled when selected; it has no chrome of its own at rest otherwise.
///
/// Its colour says where you are: a season kino.pub has is primary when it is the selected one,
/// or while focus is on the strip, and secondary once focus has gone down to the episodes.
/// One it does not have is secondary always — the glyph says the rest.
struct SeasonPill: View {

  let tab: SeasonTab
  let isSelected: Bool
  let stripHasFocus: Bool

  private var isBright: Bool {
    tab.status == .available && (isSelected || stripHasFocus)
  }

  /// The glyph is a character of the text, not an `Image` view: the system's focus effect
  /// lifts the first `Image` it finds in a label, which here would be the lock alone
  /// (measured 2026-10-11, tvOS 26.5 — a bright blob over the glyph, the digits still).
  private var label: Text {
    guard let symbol = tab.status.symbol else { return Text(verbatim: tab.label) }
    return Text("\(tab.label) \(Text(Image(systemName: symbol)).font(.footnote))")
  }

  var body: some View {
    PillWidth {
      label
        .font(SeasonTabStrip.font)
        .foregroundStyle(isBright ? .primary : .secondary)
        .padding(.vertical, SeasonTabStrip.verticalPadding)
        .padding(.horizontal, SeasonTabStrip.horizontalPadding)
    }
    .background {
      if isSelected {
        Capsule().fill(Color.KinoPub.selectionBackground)
      }
    }
    .contentShape(Capsule())
  }
}

/// Lays its one child out at its own size, but never narrower than it is tall — what turns
/// "a number with padding" into a pill whose one-digit form is a circle. A frame cannot say
/// it: `minWidth` wants the height as a number, and the height is the text's, which moves
/// with Dynamic Type.
private struct PillWidth: Layout {

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    guard let content = subviews.first else { return .zero }
    let size = content.sizeThatFits(proposal)
    return CGSize(width: max(size.width, size.height), height: size.height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    guard let content = subviews.first else { return }
    content.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: .unspecified)
  }
}

// MARK: - Previews

#if DEBUG
private enum SeasonTabPreviewFixtures {
  static func tab(_ id: Int, _ first: Int, _ last: Int? = nil, _ status: SeasonTab.Status = .available) -> SeasonTab {
    SeasonTab(id: id, first: first, last: last ?? first, status: status)
  }

  static let oneSeason = [tab(1, 1)]
  static let allAvailable = (1...6).map { tab($0, $0) }
  /// kino.pub has 1–3; 4–7 are out and not on it; 8 is announced.
  static let everyStatus = [tab(1, 1), tab(2, 2), tab(3, 3),
                            tab(-1, 4, 7, .unavailable), tab(-2, 8, 8, .soon)]
  /// Two runs of the same kind, side by side with a long one.
  static let runs = [tab(1, 1), tab(2, 2), tab(-1, 4, 35, .unavailable), tab(-2, 36, 37, .soon)]
  /// Enough to scroll, and two-digit numbers.
  static let long = (1...24).map { tab($0, $0) } + [tab(-1, 25, 26, .soon)]
}

private struct SeasonTabStripPreview: View {
  let tabs: [SeasonTab]
  @State private var selectedID: Int?

  init(_ tabs: [SeasonTab], selected: Int? = nil) {
    self.tabs = tabs
    _selectedID = State(initialValue: selected ?? tabs.first?.id)
  }

  var body: some View {
    SeasonTabStrip(tabs: tabs, selectedID: selectedID, inset: 24) { selectedID = $0.id }
  }
}

#Preview("Season strip · one season") {
  SeasonTabStripPreview(SeasonTabPreviewFixtures.oneSeason)
}

#Preview("Season strip · every status") {
  SeasonTabStripPreview(SeasonTabPreviewFixtures.everyStatus, selected: 2)
}

#Preview("Season strip · joined runs") {
  SeasonTabStripPreview(SeasonTabPreviewFixtures.runs, selected: -1)
}

#Preview("Season strip · long, scrolling") {
  SeasonTabStripPreview(SeasonTabPreviewFixtures.long, selected: 12)
}

#Preview("Season strip · Dynamic Type") {
  VStack(alignment: .leading, spacing: 16) {
    SeasonTabStripPreview(SeasonTabPreviewFixtures.oneSeason)
    SeasonTabStripPreview(SeasonTabPreviewFixtures.everyStatus, selected: -1)
  }
  .dynamicTypeSize(.accessibility2)
}
#endif
