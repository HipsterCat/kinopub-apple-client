//
//  ScoreSummaryCard.swift
//  KinoPubUI
//
//  The two cards that lead Ratings and Reviews: «Зрители» and «Критики» (Sasha, 2026-11-09).
//  Each is a score out of 100 on an arc that is greener the higher it is, what it is and how
//  many stand behind it, and the sources it is made of, one per row — at most six rows, the
//  rest folded into one row of their marks. The critics' card adds how the reviews were meant.
//
//  One view on every platform: the pointer platforms put it in a `BlockCard`, tvOS hosts it
//  inside the page's `TVCardView` (`TVPageScoreSummaryCell`) and tells it when the platter
//  turned white. Its height is a function of its rows (`ScoreSummaryMetrics.contentHeight`), so
//  a rail or a collection layout can size it before it draws.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Model

/// What one summary card says. Built by the page from its sources; every string is already in
/// the reader's language.
public struct ScoreSummary: Hashable, Sendable {
  public enum Kind: String, Hashable, Sendable {
    case viewers, critics
  }

  /// One source — or, for the last row of a long list, several folded together.
  public struct Row: Hashable, Sendable, Identifiable {
    public let id: String
    /// One mark, or the folded sources' marks side by side.
    public let marks: [MediaScoreLogo.Source]
    /// The source's name. Nil for a folded row, which is its marks.
    public let name: String?
    /// As the source prints it: `7.5`, `74%`.
    public let value: String
    /// The scale after the number, quieter: `/ 10`, `/ 5`, `/ 100`. Nil for a percentage.
    public let scale: String?
    /// Five voters or fewer, or no published score.
    public let faint: Bool
    /// How many stand behind it, the bare number — what the row says under the pointer in
    /// place of the bar (Sasha, 2026-11-09: no «оценок»).
    public let detail: String?
    /// The row's turnout against the largest one, 0…1. Nil draws no bar: Rotten Tomatoes
    /// and Metacritic publish no count.
    public let share: Double?

    public init(id: String, marks: [MediaScoreLogo.Source], name: String?, value: String,
                scale: String? = nil, faint: Bool = false, detail: String? = nil, share: Double? = nil) {
      self.id = id
      self.marks = marks
      self.name = name
      self.value = value
      self.scale = scale
      self.faint = faint
      self.detail = detail
      self.share = share
    }
  }

  /// How the reviews were meant: «467 Положительные 63% ▬▬▬».
  public struct Tone: Hashable, Sendable, Identifiable {
    public enum Mood: String, Hashable, Sendable {
      case positive, neutral, negative
    }

    public var id: Mood { mood }
    public let mood: Mood
    public let title: String
    public let count: String
    public let percent: String
    /// Against the largest tone, 0…1.
    public let share: Double

    public init(mood: Mood, title: String, count: String, percent: String, share: Double) {
      self.mood = mood
      self.title = title
      self.count = count
      self.percent = percent
      self.share = share
    }
  }

  public let kind: Kind
  /// «Зрители», «Критики».
  public let title: String
  /// «2 224 оценки», «98 рецензий и отзывов».
  public let subtitle: String?
  /// 0…100. Nil when nothing can be averaged yet — the arc stays empty and says «—».
  public let score: Int?
  public let rows: [Row]
  public let tones: [Tone]

  /// The most rows a card draws in a rail. The sixth of more becomes one folded row (Sasha,
  /// 2026-11-09); on the page there is no limit.
  public static let rowLimit = 6

  public init(kind: Kind, title: String, subtitle: String?, score: Int?, rows: [Row], tones: [Tone] = []) {
    self.kind = kind
    self.title = title
    self.subtitle = subtitle
    self.score = score
    self.rows = rows
    self.tones = tones
  }

  public var accessibilityLabel: String {
    var parts = [title]
    if let score { parts.append("\(score) / 100") }
    if let subtitle { parts.append(subtitle) }
    for row in rows {
      parts.append([row.name, row.value, row.scale, row.detail].compactMap { $0 }.joined(separator: " "))
    }
    for tone in tones { parts.append("\(tone.title) \(tone.count), \(tone.percent)") }
    return parts.joined(separator: ". ")
  }
}

// MARK: - Colour

public enum ScoreSummaryTint {
  /// Red at the bottom of the scale, through orange and yellow, to green at the top: the lower
  /// the score, the less green the arc (Sasha, 2026-11-09). Hue only — the same saturation and
  /// brightness at every score, so no score reads louder than another.
  public static func color(for score: Int?) -> Color {
    guard let score else { return .secondary }
    let t = min(max((Double(score) - 10) / 80, 0), 1)
    return Color(hue: 0.34 * t, saturation: 0.72, brightness: 0.86)
  }
}

// MARK: - Metrics

/// The card's geometry, in one place. The card's frame is Sasha's (2026-11-09): 320 wide,
/// 18 inside, corners of 16, the number's column 66, the columns 10 apart. The heights are
/// derived from the running text's line, so they follow Dynamic Type, and a rail or a
/// collection layout can size the card before it draws.
public enum ScoreSummaryMetrics {
#if os(tvOS)
  /// tvOS takes the width its column gives it.
  public static let cardWidth: CGFloat = 560
  public static let padding: CGFloat = 32
  public static let cornerRadius: CGFloat = 28
  public static let valueColumn: CGFloat = 116
  public static let columnSpacing: CGFloat = 18
  public static let reviewWidth: CGFloat = 460
#else
  public static let cardWidth: CGFloat = 320
  public static let padding: CGFloat = 18
  public static let cornerRadius: CGFloat = 16
  public static let valueColumn: CGFloat = 66
  public static let columnSpacing: CGFloat = 10
  /// A review beside the cards: 260 wide, as tall as the row.
  public static let reviewWidth: CGFloat = 260
#endif

  /// The detail page's running text (`TypeScale.detailBody`) as a platform font, so the
  /// height the layout is told and the height the rows draw are one number.
  public static var bodyFont: ScoreFont {
#if os(tvOS)
    ScoreFont.preferredFont(forTextStyle: .caption2)
#elseif os(iOS)
    ScoreFont.preferredFont(forTextStyle: .callout)
#else
    ScoreFont.preferredFont(forTextStyle: .body)
#endif
  }

  /// One row's height: the running text's line.
  public static var line: CGFloat {
#if canImport(UIKit)
    ceil(bodyFont.lineHeight)
#else
    ceil(bodyFont.ascender - bodyFont.descender + bodyFont.leading)
#endif
  }

  public static var rowSpacing: CGFloat { (line * 0.6).rounded() }
  /// The arc's box: about four and a half lines, the size of the title and the subtitle twice.
  public static var gauge: CGFloat { (line * 4.6).rounded() }
  /// Between the arc and the first row.
  public static var headerGap: CGFloat { (line * 1.1).rounded() }
  /// Above and below the rule between the sources and the tones.
  public static var dividerGap: CGFloat { (line * 0.8).rounded() }
  /// The source marks: the hero's own (`MediaScoreLogo.Style.line`) at the row's height.
  public static var markHeight: CGFloat { (line * 0.95).rounded() }

  /// How tall the card's content is with `rows` sources and `tones` tones — the padding not
  /// included.
  public static func contentHeight(rows: Int, tones: Int) -> CGFloat {
    var height = gauge + headerGap + stack(rows)
    if tones > 0 { height += dividerGap * 2 + 1 + stack(tones) }
    return ceil(height)
  }

  public static func contentHeight(for summary: ScoreSummary) -> CGFloat {
    contentHeight(rows: summary.rows.count, tones: summary.tones.count)
  }

  /// The whole card, padding included.
  public static func cardHeight(for summary: ScoreSummary) -> CGFloat {
    ceil(contentHeight(for: summary) + padding * 2)
  }

  private static func stack(_ count: Int) -> CGFloat {
    guard count > 0 else { return 0 }
    return line * CGFloat(count) + rowSpacing * CGFloat(count - 1)
  }
}

// MARK: - Arc

/// A gauge open at the bottom, as watchOS draws its circular one: the whole arc in the score's
/// colour, a dot in the text's colour where the score is — set in a hole cut out of the arc,
/// not ringed — the number in the middle and «/ 100» in the gap. SwiftUI's `Gauge` is not on
/// tvOS, so the arc is drawn here; on the pointer platforms it is the style of a real `Gauge`,
/// which is what VoiceOver reads.
public struct ScoreGauge: View {
  let score: Int?
  let diameter: CGFloat

  @State private var progress: Double
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// - Parameter animatesIn: the dot travels to the score and the number counts up once on
  ///   screen. Off draws it settled (a still render, tvOS).
  public init(score: Int?, diameter: CGFloat, animatesIn: Bool = true) {
    self.score = score
    self.diameter = diameter
    _progress = State(initialValue: animatesIn ? 0 : 1)
  }

  public var body: some View {
#if os(tvOS)
    face
#else
    Gauge(value: Double(score ?? 0), in: 0...100) {
      EmptyView()
    } currentValueLabel: {
      Text(score.map { "\($0)" } ?? "—")
    }
    .gaugeStyle(ScoreArcGaugeStyle(face: face))
#endif
  }

  private var tint: Color { ScoreSummaryTint.color(for: score) }
  private var lineWidth: CGFloat { (diameter * 0.075).rounded() }
  private var fraction: Double { Double(min(max(score ?? 0, 0), 100)) / 100 }

  private var face: some View {
    let radius = (diameter - lineWidth) / 2
    let angle = Angle.degrees(ScoreArc.start + ScoreArc.sweep * fraction * progress)
    let offset = CGSize(width: radius * CGFloat(cos(angle.radians)),
                        height: radius * CGFloat(sin(angle.radians)))
    let dot = lineWidth * 0.95
    return ZStack {
      // One colour all the way round; the dot says where the score is.
      ZStack {
        ScoreArc()
          .stroke(score == nil ? tint.opacity(0.3) : tint,
                  style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        if score != nil {
          // The hole the dot sits in: the page shows through it, whatever the page is.
          Circle()
            .frame(width: dot + lineWidth * 1.4, height: dot + lineWidth * 1.4)
            .offset(offset)
            .blendMode(.destinationOut)
        }
      }
      .compositingGroup()
      if score != nil {
        Circle()
          .fill(Color.primary)
          .frame(width: dot, height: dot)
          .offset(offset)
      }
      Text(verbatim: score.map { "\(Int((Double($0) * progress).rounded()))" } ?? "—")
        .font(.system(size: diameter * 0.38, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .contentTransition(.numericText(value: Double(score ?? 0) * progress))
        .foregroundStyle(Color.primary)
        .minimumScaleFactor(0.6)
        .lineLimit(1)
        .padding(.horizontal, lineWidth * 1.5)
      Text(verbatim: "/ 100")
        .font(.system(size: diameter * 0.13, weight: .medium))
        .foregroundStyle(Color.secondary)
        .offset(y: diameter * 0.39)
    }
    .padding(lineWidth / 2)
    .frame(width: diameter, height: diameter)
    .onAppear { reveal() }
    .onChange(of: score) { reveal() }
  }

  private func reveal() {
    guard progress < 1 else { return }
    if reduceMotion {
      progress = 1
    } else {
      withAnimation(.spring(duration: 0.9, bounce: 0.15).delay(0.1)) { progress = 1 }
    }
  }
}

#if !os(tvOS)
/// `Gauge` drawn as `ScoreGauge`'s arc: the gauge keeps the value and VoiceOver's reading of
/// it, the face is ours.
private struct ScoreArcGaugeStyle<Face: View>: GaugeStyle {
  let face: Face

  func makeBody(configuration: Configuration) -> some View {
    face
      .accessibilityElement(children: .ignore)
      .accessibilityValue(Text(verbatim: "\(Int((configuration.value * 100).rounded())) / 100"))
  }
}
#endif

/// 270° of a circle, open at the bottom, from bottom-left clockwise over the top to
/// bottom-right.
private struct ScoreArc: Shape {
  static let start: Double = 135
  static let sweep: Double = 270

  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                radius: min(rect.width, rect.height) / 2,
                startAngle: .degrees(Self.start),
                endAngle: .degrees(Self.start + Self.sweep),
                clockwise: false)
    return path
  }
}

// MARK: - Card

/// The card on the pointer platforms: borderless — the page's material at rest, a shade
/// lighter under the pointer, nothing inverted (Sasha, 2026-11-09) — and, when it leads
/// somewhere, a navigation link whose chevron shows only while the card is hovered.
public struct ScoreSummaryCard: View {
  let summary: ScoreSummary
  let destination: (any Hashable)?

  @State private var hovered = false

  public init(summary: ScoreSummary, destination: (any Hashable)? = nil) {
    self.summary = summary
    self.destination = destination
  }

  private typealias M = ScoreSummaryMetrics
  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: M.cornerRadius, style: .continuous)
  }

  public var body: some View {
    if let destination {
      NavigationLink(value: destination) { surface }
        .buttonStyle(.plain)
    } else {
      surface
    }
  }

  private var surface: some View {
    ScoreSummaryCardContent(summary: summary, highlighted: hovered, showsChevron: destination != nil)
      .padding(M.padding)
      .frame(width: M.cardWidth)
      .frame(maxHeight: .infinity, alignment: .top)
      .background {
        ZStack {
          shape.fill(.regularMaterial)
          shape.fill(Color.primary.opacity(hovered ? 0.06 : 0))
        }
      }
      .contentShape(shape)
#if !os(tvOS)
      .onHover { inside in
        withAnimation(.easeOut(duration: 0.15)) { hovered = inside }
      }
#endif
  }
}

// MARK: - Card content

/// The card's insides — no platter, no padding: `ScoreSummaryCard` on the pointer platforms,
/// a still of it in `TVPageScoreSummaryCell` on tvOS.
public struct ScoreSummaryCardContent: View {
  let summary: ScoreSummary
  /// Hovered or focused: the chevron shows.
  var highlighted: Bool
  /// The card leads somewhere.
  var showsChevron: Bool
  var animatesIn: Bool

  @State private var hoveredRow: String?
  @State private var barsShown: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(summary: ScoreSummary, highlighted: Bool = false, showsChevron: Bool = false,
              animatesIn: Bool = true) {
    self.summary = summary
    self.highlighted = highlighted
    self.showsChevron = showsChevron
    self.animatesIn = animatesIn
    _barsShown = State(initialValue: !animatesIn)
  }

  private typealias M = ScoreSummaryMetrics
  private var bodyFont: Font { Font(M.bodyFont) }
  private var tint: Color { ScoreSummaryTint.color(for: summary.score) }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
        .padding(.bottom, M.headerGap)
      sourcesGrid
      if !summary.tones.isEmpty {
        Rectangle()
          .fill(Color.primary.opacity(0.12))
          .frame(height: 1)
          .padding(.vertical, M.dividerGap)
        Grid(alignment: .leading, horizontalSpacing: M.columnSpacing, verticalSpacing: M.rowSpacing) {
          ForEach(summary.tones) { tone in
            toneRow(tone)
          }
        }
      }
      Spacer(minLength: 0)
    }
    .font(bodyFont)
    .lineLimit(1)
    .onAppear {
      guard !barsShown else { return }
      if reduceMotion { barsShown = true } else {
        withAnimation(.easeOut(duration: 0.7).delay(0.25)) { barsShown = true }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: summary.accessibilityLabel))
  }

  // MARK: Header

  private var header: some View {
    HStack(alignment: .center, spacing: M.columnSpacing * 1.4) {
      ScoreGauge(score: summary.score, diameter: M.gauge, animatesIn: animatesIn)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: summary.title)
          .font(Self.titleFont)
          .foregroundStyle(Color.primary)
        if let subtitle = summary.subtitle {
          Text(verbatim: subtitle)
            .foregroundStyle(Color.secondary)
        }
      }
      Spacer(minLength: 0)
      if showsChevron {
        // The section header's own chevron, shown while the card is hovered or focused.
        Image(systemName: "chevron.forward")
          .font(Self.chevronFont)
          .foregroundStyle(.secondary)
          .opacity(highlighted ? 0.7 : 0)
          .frame(maxHeight: .infinity, alignment: .top)
      }
    }
    .frame(height: M.gauge)
  }

  /// The section header's chevron; on tvOS the header's is far too big for a card, so the
  /// card's running text, bold.
  private static var chevronFont: Font {
#if os(tvOS)
    .caption2.weight(.bold)
#else
    TypeScale.rowChevron
#endif
  }

  private static var titleFont: Font {
#if os(tvOS)
    .callout.weight(.semibold)
#elseif os(macOS)
    .title2.weight(.bold)
#else
    .title3.weight(.bold)
#endif
  }

  // MARK: Rows

  /// Three columns, 10 apart: the number (fixed), the marks and names (one width for the
  /// column — its widest label's, Sasha 2026-11-09), the bar (the rest) — or, under the
  /// pointer, the bare count in its place. A `Grid`, so the columns are columns.
  private var sourcesGrid: some View {
    let pitch = M.line + M.rowSpacing
    return ZStack(alignment: .topLeading) {
      if let index = summary.rows.firstIndex(where: { $0.id == hoveredRow }) {
        RoundedRectangle(cornerRadius: M.line * 0.45, style: .continuous)
          .fill(.fill.secondary)
          .frame(maxWidth: .infinity)
          .frame(height: pitch)
          .padding(.horizontal, -M.columnSpacing)
          .offset(y: CGFloat(index) * pitch - M.rowSpacing / 2)
      }
      Grid(alignment: .leading, horizontalSpacing: M.columnSpacing, verticalSpacing: M.rowSpacing) {
        ForEach(summary.rows) { row in
          sourceRow(row)
        }
      }
#if !os(tvOS)
      // The rows' hover areas, over the grid's gaps too, so the pointer never falls between
      // two cells of one row.
      VStack(spacing: 0) {
        ForEach(summary.rows) { row in
          Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: pitch)
            .contentShape(Rectangle())
            .onHover { inside in
              withAnimation(.easeOut(duration: 0.15)) {
                if inside { hoveredRow = row.id } else if hoveredRow == row.id { hoveredRow = nil }
              }
            }
        }
      }
      .offset(y: -M.rowSpacing / 2)
#endif
    }
  }

  private func sourceRow(_ row: ScoreSummary.Row) -> some View {
    let hovered = hoveredRow == row.id
    return GridRow {
      HStack(alignment: .firstTextBaseline, spacing: 0) {
        ScoreValueText(row.value, font: M.bodyFont)
          .foregroundStyle(hovered ? tint : (row.faint ? Color.secondary : Color.primary))
        if let scale = row.scale {
          Text(verbatim: " \(scale)")
            .foregroundStyle(.tertiary)
        }
      }
      .frame(width: M.valueColumn, height: M.line, alignment: .leading)

      HStack(spacing: M.columnSpacing * 0.6) {
        marks(row.marks)
        if let name = row.name {
          Text(verbatim: name)
            .foregroundStyle(hovered ? Color.primary : Color.secondary)
        }
      }
      .fixedSize()
      .frame(height: M.line)

      Group {
        if hovered, let detail = row.detail {
          Text(verbatim: detail)
            .foregroundStyle(Color.primary)
            .transition(.opacity)
        } else if let share = row.share {
          bar(share)
            .transition(.opacity)
        } else {
          Color.clear
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: M.line)
    }
  }

  /// One mark, or a folded row's marks side by side — at most four, then «+N». The hero's
  /// marks (`.line`), so a source looks the same in both places.
  @ViewBuilder
  private func marks(_ marks: [MediaScoreLogo.Source]) -> some View {
    let shown = marks.prefix(4)
    HStack(spacing: M.markHeight * 0.2) {
      ForEach(Array(shown.enumerated()), id: \.offset) { _, mark in
        MediaScoreLogo(mark, height: M.markHeight, style: .line)
#if !os(tvOS)
          .frame(height: M.markHeight)
#endif
      }
      if marks.count > shown.count {
        Text(verbatim: "+\(marks.count - shown.count)")
          .foregroundStyle(Color.secondary)
      }
    }
    .fixedSize()
  }

  private func bar(_ share: Double) -> some View {
    GeometryReader { proxy in
      Capsule()
        .fill(Color.primary.opacity(0.35))
        .frame(width: max(proxy.size.width * share * (barsShown ? 1 : 0), barsShown ? 6 : 0),
               height: max((M.line * 0.18).rounded(), 3))
        .frame(maxHeight: .infinity, alignment: .center)
    }
  }

  // MARK: Tones

  private func toneRow(_ tone: ScoreSummary.Tone) -> some View {
    GridRow {
      Text(verbatim: tone.count)
        .foregroundStyle(Color.primary)
        .frame(width: M.valueColumn, height: M.line, alignment: .leading)
      HStack(spacing: M.columnSpacing * 0.6) {
        Text(verbatim: tone.title)
          .foregroundStyle(Color.secondary)
        Text(verbatim: tone.percent)
          .foregroundStyle(Color.primary)
      }
      .fixedSize()
      .frame(height: M.line)
      bar(tone.share)
        .frame(maxWidth: .infinity)
        .frame(height: M.line)
    }
  }
}

// MARK: - Preview

#Preview("Score summary") {
  let viewers = ScoreSummary(
    kind: .viewers, title: "Зрители", subtitle: "2 224 оценки", score: 77,
    rows: [
      .init(id: "kp", marks: [.kinopoisk], name: "Кинопоиск", value: "7.5", scale: "/ 10", detail: "1 024", share: 1),
      .init(id: "imdb", marks: [.imdb], name: "IMDb", value: "8.3", scale: "/ 10", detail: "640", share: 0.6),
      .init(id: "tmdb", marks: [.tmdb], name: "TMDB", value: "74%", detail: "846", share: 0.8),
      .init(id: "trakt", marks: [.trakt], name: "Trakt", value: "70%", detail: "300", share: 0.3),
      .init(id: "pop", marks: [.rottenTomatoesAudienceUpright], name: "Popcornmeter", value: "78%"),
      .init(id: "more", marks: [.letterboxd, .myShows, .douban, .kinopub], name: nil, value: "7.4", scale: "/ 10", share: 0.1)
    ])
  let critics = ScoreSummary(
    kind: .critics, title: "Критики", subtitle: "98 рецензий и отзывов", score: 45,
    rows: [
      .init(id: "rt", marks: [.rottenTomatoesFresh], name: "Rotten Tomatoes", value: "75%"),
      .init(id: "mc", marks: [.metacriticFavorable], name: "Metacritic", value: "83", scale: "/ 100")
    ],
    tones: [
      .init(mood: .positive, title: "Положительные", count: "467", percent: "63%", share: 1),
      .init(mood: .neutral, title: "Нейтральные", count: "156", percent: "25%", share: 0.4),
      .init(mood: .negative, title: "Отрицательные", count: "45", percent: "14%", share: 0.2)
    ])
  return HStack(alignment: .top, spacing: 16) {
    ForEach([viewers, critics], id: \.kind) { summary in
      ScoreSummaryCard(summary: summary)
        .frame(height: ScoreSummaryMetrics.cardHeight(for: critics))
    }
  }
  .padding()
}
