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
    /// How many stand behind it, in words — what the row says under the pointer.
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

/// The card's geometry, in one place, derived from the running text's line so it follows
/// Dynamic Type and the platform — nothing here is a point size picked for one screen.
public enum ScoreSummaryMetrics {
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

  public static var rowSpacing: CGFloat { (line * 0.5).rounded() }
  /// The arc's box: about four and a half lines, the size of the title and the subtitle twice.
  public static var gauge: CGFloat { (line * 4.6).rounded() }
  /// Between the arc and the first row.
  public static var headerGap: CGFloat { (line * 1.1).rounded() }
  /// Above and below the rule between the sources and the tones.
  public static var dividerGap: CGFloat { (line * 0.8).rounded() }
  /// The number's column: wide enough for «8.3 / 10» and «100%».
  public static var valueColumn: CGFloat { (line * 3.7).rounded() }
  /// The bars' column, on the trailing side.
  public static var barColumn: CGFloat { (line * 4.5).rounded() }
  public static var markHeight: CGFloat { (line * 0.95).rounded() }

  /// How tall the card's content is with `rows` sources and `tones` tones — the platter's
  /// padding not included.
  public static func contentHeight(rows: Int, tones: Int) -> CGFloat {
    var height = gauge + headerGap + stack(rows)
    if tones > 0 { height += dividerGap * 2 + 1 + stack(tones) }
    return ceil(height)
  }

  public static func contentHeight(for summary: ScoreSummary) -> CGFloat {
    contentHeight(rows: summary.rows.count, tones: summary.tones.count)
  }

  private static func stack(_ count: Int) -> CGFloat {
    guard count > 0 else { return 0 }
    return line * CGFloat(count) + rowSpacing * CGFloat(count - 1)
  }
}

// MARK: - Arc

/// A gauge open at the bottom, as watchOS draws its circular one: the whole scale in the
/// score's colour, faint past the score, a dot where the score is, the number in the middle and
/// «/ 100» in the gap. SwiftUI's `Gauge` is not on tvOS, so the arc is drawn here; on the
/// pointer platforms it is the style of a real `Gauge`, which is what VoiceOver reads.
public struct ScoreGauge: View {
  let score: Int?
  let diameter: CGFloat
  var focused: Bool = false

  @State private var progress: Double = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(score: Int?, diameter: CGFloat, focused: Bool = false) {
    self.score = score
    self.diameter = diameter
    self.focused = focused
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
    let shown = fraction * progress
    let radius = (diameter - lineWidth) / 2
    let angle = Angle.degrees(ScoreArc.start + ScoreArc.sweep * shown)
    return ZStack {
      ScoreArc(fraction: 1)
        .stroke(tint.opacity(score == nil ? 0.25 : 0.3),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
      if score != nil {
        ScoreArc(fraction: shown)
          .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        Circle()
          .fill(focused ? Color.black.opacity(0.55) : Color.white.opacity(0.92))
          .frame(width: lineWidth * 0.9, height: lineWidth * 0.9)
          .offset(x: radius * CGFloat(cos(angle.radians)), y: radius * CGFloat(sin(angle.radians)))
      }
      Text(verbatim: score.map { "\(Int((Double($0) * progress).rounded()))" } ?? "—")
        .font(.system(size: diameter * 0.38, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .contentTransition(.numericText(value: Double(score ?? 0) * progress))
        .foregroundStyle(focused ? Color.black : Color.primary)
        .minimumScaleFactor(0.6)
        .lineLimit(1)
        .padding(.horizontal, lineWidth * 1.5)
      Text(verbatim: "/ 100")
        .font(.system(size: diameter * 0.13, weight: .medium))
        .foregroundStyle(focused ? Color.black.opacity(0.6) : Color.secondary)
        .offset(y: diameter * 0.39)
    }
    .padding(lineWidth / 2)
    .frame(width: diameter, height: diameter)
    .onAppear { reveal() }
    .onChange(of: score) { reveal() }
  }

  /// The arc fills to the score and the number counts up to it once the card is on screen.
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

/// 270° of a circle, open at the bottom, from bottom-left clockwise to bottom-right.
private struct ScoreArc: Shape {
  static let start: Double = 135
  static let sweep: Double = 270

  var fraction: Double

  var animatableData: Double {
    get { fraction }
    set { fraction = newValue }
  }

  func path(in rect: CGRect) -> Path {
    var path = Path()
    guard fraction > 0 else { return path }
    let radius = min(rect.width, rect.height) / 2
    path.addArc(center: CGPoint(x: rect.midX, y: rect.midY),
                radius: radius,
                startAngle: .degrees(Self.start),
                endAngle: .degrees(Self.start + Self.sweep * min(fraction, 1)),
                clockwise: false)
    return path
  }
}

// MARK: - Card content

/// The card's insides — no platter, no padding. `BlockCard` or `TVCardView` is the platter.
public struct ScoreSummaryCardContent: View {
  let summary: ScoreSummary
  /// tvOS: the platter turned white, so the ink turns dark.
  var focused: Bool
  /// A chevron in the corner says the card opens something (the pointer platforms).
  var showsChevron: Bool

  @State private var hoveredRow: String?
  @State private var barsShown = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(summary: ScoreSummary, focused: Bool = false, showsChevron: Bool = false) {
    self.summary = summary
    self.focused = focused
    self.showsChevron = showsChevron
  }

  private typealias M = ScoreSummaryMetrics
  private var bodyFont: Font { Font(M.bodyFont) }
  private var ink: Color { focused ? .black : Color.KinoPub.text }
  private var secondaryInk: Color { focused ? Color.black.opacity(0.6) : .secondary }
  private var tertiaryInk: Color { focused ? Color.black.opacity(0.4) : Color.secondary.opacity(0.7) }
  private var tint: Color { ScoreSummaryTint.color(for: summary.score) }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
        .padding(.bottom, M.headerGap)
      VStack(alignment: .leading, spacing: M.rowSpacing) {
        ForEach(summary.rows) { row in
          sourceRow(row)
        }
      }
      if !summary.tones.isEmpty {
        Rectangle()
          .fill(focused ? Color.black.opacity(0.12) : Color.primary.opacity(0.12))
          .frame(height: 1)
          .padding(.vertical, M.dividerGap)
        VStack(alignment: .leading, spacing: M.rowSpacing) {
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
      if reduceMotion { barsShown = true } else {
        withAnimation(.easeOut(duration: 0.7).delay(0.25)) { barsShown = true }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: summary.accessibilityLabel))
  }

  // MARK: Header

  private var header: some View {
    HStack(alignment: .center, spacing: M.line * 0.9) {
      ScoreGauge(score: summary.score, diameter: M.gauge, focused: focused)
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: summary.title)
          .font(Self.titleFont)
          .foregroundStyle(ink)
        if let subtitle = summary.subtitle {
          Text(verbatim: subtitle)
            .foregroundStyle(secondaryInk)
        }
      }
      Spacer(minLength: 0)
      if showsChevron {
        Image(systemName: "chevron.forward")
          .font(Self.titleFont)
          .foregroundStyle(secondaryInk)
          .frame(maxHeight: .infinity, alignment: .top)
      }
    }
    .frame(height: M.gauge)
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

  private func sourceRow(_ row: ScoreSummary.Row) -> some View {
    let hovered = hoveredRow == row.id && row.detail != nil
    return HStack(spacing: M.line * 0.5) {
      HStack(alignment: .firstTextBaseline, spacing: 0) {
        ScoreValueText(row.value, font: M.bodyFont)
          .foregroundStyle(hovered ? tint : (row.faint ? secondaryInk : ink))
        if let scale = row.scale {
          Text(verbatim: " \(scale)")
            .foregroundStyle(tertiaryInk)
        }
      }
      .frame(width: M.valueColumn, alignment: .leading)

      marks(row.marks)

      if let name = row.name {
        Text(verbatim: name)
          .foregroundStyle(secondaryInk)
          .layoutPriority(1)
      }

      Spacer(minLength: M.line * 0.5)

      Group {
        if hovered, let detail = row.detail {
          Text(verbatim: detail)
            .foregroundStyle(secondaryInk)
            .transition(.opacity)
        } else if let share = row.share {
          bar(share)
            .transition(.opacity)
        }
      }
      .frame(width: M.barColumn, alignment: .leading)
    }
    .frame(height: M.line)
    .background {
      if hovered {
        RoundedRectangle(cornerRadius: M.line * 0.5, style: .continuous)
          .fill(.fill.secondary)
          .padding(.horizontal, -M.line * 0.5)
          .padding(.vertical, -M.rowSpacing * 0.5)
      }
    }
#if !os(tvOS)
    .onHover { inside in
      withAnimation(.easeOut(duration: 0.15)) {
        if inside { hoveredRow = row.id } else if hoveredRow == row.id { hoveredRow = nil }
      }
    }
#endif
  }

  /// One mark, or a folded row's marks side by side — at most four, then «+N».
  @ViewBuilder
  private func marks(_ marks: [MediaScoreLogo.Source]) -> some View {
    let shown = marks.prefix(4)
    HStack(spacing: M.markHeight * 0.2) {
      ForEach(Array(shown.enumerated()), id: \.offset) { _, mark in
        MediaScoreLogo(mark, height: M.markHeight, style: .compact)
      }
      if marks.count > shown.count {
        Text(verbatim: "+\(marks.count - shown.count)")
          .foregroundStyle(secondaryInk)
      }
    }
    .fixedSize()
  }

  private func bar(_ share: Double) -> some View {
    GeometryReader { proxy in
      Capsule()
        .fill(focused ? Color.black.opacity(0.35) : Color.primary.opacity(0.35))
        .frame(width: max(proxy.size.width * share * (barsShown ? 1 : 0), barsShown ? 6 : 0),
               height: max((M.line * 0.18).rounded(), 3))
        .frame(maxHeight: .infinity, alignment: .center)
    }
  }

  // MARK: Tones

  private func toneRow(_ tone: ScoreSummary.Tone) -> some View {
    HStack(spacing: M.line * 0.5) {
      Text(verbatim: tone.count)
        .foregroundStyle(ink)
        .frame(width: M.valueColumn, alignment: .leading)
      Text(verbatim: tone.title)
        .foregroundStyle(secondaryInk)
      Text(verbatim: tone.percent)
        .foregroundStyle(ink)
      Spacer(minLength: M.line * 0.5)
      bar(tone.share)
        .frame(width: M.barColumn)
    }
    .frame(height: M.line)
  }
}

// MARK: - Preview

#Preview("Score summary") {
  let viewers = ScoreSummary(
    kind: .viewers, title: "Зрители", subtitle: "2 224 оценки", score: 77,
    rows: [
      .init(id: "kp", marks: [.kinopoisk], name: "Кинопоиск", value: "7.5", scale: "/ 10", detail: "1 024 оценки", share: 1),
      .init(id: "imdb", marks: [.imdb], name: "IMDb", value: "8.3", scale: "/ 10", detail: "640 оценок", share: 0.6),
      .init(id: "tmdb", marks: [.tmdb], name: "TMDB", value: "74%", detail: "846 оценок", share: 0.8),
      .init(id: "trakt", marks: [.trakt], name: "Trakt", value: "70%", detail: "300 оценок", share: 0.3),
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
      BlockCard(.interactive(action: {}), width: 360,
                height: ScoreSummaryMetrics.contentHeight(for: summary) + BlockMetrics.padding * 2) {
        ScoreSummaryCardContent(summary: summary, showsChevron: true)
      }
    }
  }
  .padding()
}
