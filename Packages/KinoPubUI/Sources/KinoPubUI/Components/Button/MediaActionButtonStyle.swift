//
//  MediaActionButtonStyle.swift
//  KinoPubUI
//
//  Hero action controls. These are the **system** button styles with a border shape,
//  and nothing else.
//
//  They used to be three hand-written `ButtonStyle`s: capsule and circle plates painted
//  by hand, a hairline stroke, `Color.white.opacity(0.22)` fills, black-on-white
//  inversion, `.onHover` state, drop shadows, and a `scaleEffect` focus lift with its
//  own spring. That is a reimplementation of `.borderedProminent` / `.bordered` that
//  drifts from the platform every release — and on tvOS it also meant the focus lift,
//  the specular highlight and the press feedback were ours to keep in step with a
//  system that already does all three. `AGENTS.md`:
//  custom chrome needs a named missing API, and there was none.
//
//  What is left here is the vocabulary (which control is the primary, which is a
//  secondary, which is a circle), the icon/label metrics, and the resume bar — the one
//  piece the system genuinely does not ship.
//

import SwiftUI

// MARK: - Metrics

public enum MediaActionMetrics {
#if os(tvOS)
  /// Floor for the Play label so the primary control keeps its weight next to a
  /// labelled Trailer button. Applied to the *label*: the button itself is system-drawn
  /// and hugs whatever it is given.
  public static let playPillMinWidth: CGFloat = 200
//  public static let buttonHeight: CGFloat = 66
//  public static let iconPointSize: CGFloat = 26
//  public static let circleIconPointSize: CGFloat = 24
  public static let labelFont = TypeScale.actionLabel
  public static let progressWidth: CGFloat = 96
  public static let progressHeight: CGFloat = 8
  public static let contentSpacing: CGFloat = 14
  public static let rowSpacing: CGFloat = 16
#else
  public static let playPillMinWidth: CGFloat = 60
//  public static let buttonHeight: CGFloat = 44
//  public static let iconPointSize: CGFloat = 15
//  public static let circleIconPointSize: CGFloat = 16
  public static let labelFont = TypeScale.actionLabel
  public static let progressWidth: CGFloat = 40
  public static let progressHeight: CGFloat = 3
  public static let contentSpacing: CGFloat = 6
  public static let rowSpacing: CGFloat = 12
#endif
}

// MARK: - Scaled icon glyphs

/// `.system(size:weight:)` for an SF Symbol glyph, but the size still tracks Dynamic
/// Type. Icons here are sized off the button's own geometry, not a text baseline, so a
/// text style would fit the wrong thing — this scales the exact point size instead, the
/// same way a semantic style would.
private struct ScaledIconFont: ViewModifier {
  @ScaledMetric private var size: CGFloat
  private let weight: Font.Weight

  init(size: CGFloat, weight: Font.Weight) {
    self._size = ScaledMetric(wrappedValue: size)
    self.weight = weight
  }

  func body(content: Content) -> some View {
    content.font(.system(size: size, weight: weight))
  }
}

public extension View {
  /// Apply to an `Image(systemName:)` glyph in place of `.font(.system(size:weight:))`.
  func mediaActionIconFont(size: CGFloat, weight: Font.Weight) -> some View {
    modifier(ScaledIconFont(size: size, weight: weight))
  }
}

// MARK: - System styles

public extension View {
  /// Play / Resume — the primary call to action.
  func mediaActionPlayPillStyle() -> some View {
      buttonStyle(.glassProminent)
            .tint(.primary)
//          .foregroundStyle(.primary).colorScheme(.dark)
//          .kinoGlass(in: .buttonBorder, interactive: true)
      .buttonBorderShape(.capsule)
#if !os(tvOS)
      .controlSize(.large)
#endif
  }

  /// A labelled secondary control (Trailer, Watchlist) — same capsule, quieter weight.
  func mediaActionPillStyle() -> some View {
      
       buttonStyle(.borderedProminent)
//          .tint(Color.KinoPub.secondary)
//          .kinoGlass(in: .buttonBorder, interactive: true)
      .buttonBorderShape(.capsule)
#if !os(tvOS)
      .controlSize(.large)
#endif
  }

  /// An icon-only secondary control. `.circle` is a real `ButtonBorderShape`, so the
  /// plate, its focus treatment and its press feedback are all the system's.
  func mediaActionCircleStyle() -> some View {
       buttonStyle(.bordered)
     .buttonBorderShape(.circle)
#if !os(tvOS)
      .controlSize(.large)
#endif
  }
}

// MARK: - Resume bar

/// Thin capsule track shown inside the Play control once playback has started. The one
/// piece with no system equivalent — and the only reason this file still draws anything.
///
/// Colours are **hierarchical styles, not literals**: inside a button label they resolve
/// against whatever foreground the current style and focus state established, so the bar
/// inverts with the button instead of guessing when the button turned white. The old
/// version hard-coded black-on-white and needed a `forceFocusedColors` flag to paper
/// over the cases where the guess was wrong.
public struct MediaActionProgressTrack: View {
  public var progress: Double

  public init(progress: Double) {
    self.progress = progress
  }

  public var body: some View {
    Capsule()
      .fill(.tertiary)
      .frame(width: MediaActionMetrics.progressWidth,
             height: MediaActionMetrics.progressHeight)
      .overlay(alignment: .leading) {
        Capsule()
          .fill(.primary)
          .frame(width: max(6, MediaActionMetrics.progressWidth * min(max(progress, 0), 1)),
                 height: MediaActionMetrics.progressHeight)
      }
  }
}

#Preview("Action chrome") {
     VStack(alignment: .leading, spacing: 44) {
          LazyHStack(spacing: MediaActionMetrics.rowSpacing) {
               Button {} label: {
                    HStack(spacing: MediaActionMetrics.contentSpacing) {
                         Image(systemName: "play.fill")
                         Text("Смотреть фильм")
                              .font(MediaActionMetrics.labelFont)
                    }
               }
               .mediaActionPlayPillStyle() //
               
               
               

               
               
               
               //               Button {} label: {
               //                    Label("Просмотрено", systemImage: "checkmark")
               //                         .font(MediaActionMetrics.labelFont)
               //               }.mediaActionPillStyle() // Mark as Watched, only visible on in progress/unwatched items. Spinner until success, button disappears animated scale down when marked, updates play button state and shows toast on success
               
               
               
               //               Button {} label: {
               //                    Label("Random", systemImage: "shuffle")
               //                         .font(MediaActionMetrics.labelFont)
               //                    //                    .padding(.horizontal, 2)
               //               }.mediaActionPillStyle()
               
               
               //               Button {} label: {
               //                    Image(systemName: "arrow.trianglehead.counterclockwise")
               //               }.mediaActionCircleStyle()
               
               
               Button {} label: {
                    Label("Трейлер", systemImage: "play.fill")
                         .font(MediaActionMetrics.labelFont)
                    //                    .padding(.horizontal, 2)
               }
               //    .buttonStyle(.glass)
               .mediaActionPillStyle()
               
               
//               Button {} label: { Text("Инфо").font(MediaActionMetrics.labelFont)
//
//                    //                    .padding(.horizontal, 2)
//               }
//               //    .buttonStyle(.glass)
//               .mediaActionPillStyle()
               

//               Button {} label: {
//                    Image(systemName: "checkmark")
//               }.mediaActionCircleStyle() // Mark as Watched, only visible on in progress/unwatched items. Spinner until success, button disappears animated scale down when marked, updates play button state and shows toast on success
//               
//               // Long press for more options - "Серия 4", "2 сезон", "Все серии"
               
          
               
               //               Button {} label: {
               //                    Label("Трейлер", systemImage: "video.fill")
               //                         .font(MediaActionMetrics.labelFont)
               //                    //                    .padding(.horizontal, 2)
               //               }
               //               //    .buttonStyle(.glass)
               //               .mediaActionPillStyle()
               
               
               //               Button {} label: {
               //                    Label("Выбрать серию", systemImage: "rectangle.on.rectangle")
               //                         .font(MediaActionMetrics.labelFont)
               //               }.mediaActionPillStyle() // Выбрать сезон
               
               
               
               
               
               //               Button {} label: {
               //                    Image(systemName: "video.fill")
               //                         .font(MediaActionMetrics.labelFont)
               //                    //                    .padding(.horizontal, 2)
               //               }
               //               //    .buttonStyle(.glass)
               //               .mediaActionCircleStyle()
               
               
               //               Button {} label: {
               //                    Image(systemName: "info")
               //               }.mediaActionCircleStyle()
               
               
               
               //               Button {} label: {
               //                    Image(systemName: "checkmark")
               //               }.mediaActionCircleStyle() // Mark as Watched, only visible on in progress/unwatched items. Spinner until success, button disappears animated scale down when marked, updates play button state and shows toast on success
               
               //
               //               Button {} label: {
               //                    Label("Подписаться", systemImage: "plus")
               //                         .font(MediaActionMetrics.labelFont)
               //                    //                    .padding(.horizontal, 2)
               //               }
               //               //    .buttonStyle(.glass)
               //               .mediaActionPillStyle()
               
               
               

               
               //               Button {} label: {
               //                    Image(systemName: "plus")
               //               }.mediaActionCircleStyle() // // bookmark.fill when bookmarked
               
               
               Button {} label: {
                    Image(systemName: "bookmark")
               }.mediaActionCircleStyle() // // bookmark.fill when bookmarked
               
               Button {} label: {
                    Image(systemName: "checkmark")
               }.mediaActionCircleStyle() // Mark as Watched, only visible on in progress/unwatched items. Spinner until success, button disappears animated scale down when marked, updates play button state and shows toast on success
               
               
               Button {} label: {
                    Image(systemName: "arrow.down.to.line")
               }.mediaActionCircleStyle() // Download
               
               
               //               Button {} label: {
               //                    //      Image(systemName: "bookmark")
               //
               //                    //            .font(MediaActionMetrics.labelFont)
               //                    Label("Save", systemImage: "bookmark")
               //                         .font(MediaActionMetrics.labelFont)
               //                    //                    .padding(.horizontal, 2)
               //                    //        .mediaActionIconFont(size: MediaActionMetrics.circleIconPointSize, weight: .semibold)
               //                    // bookmark.fill when bookmarked, label = Name of folder or "2 Lists"
               //               }
               //               //    .buttonStyle(.glass)
               //               .mediaActionPillStyle()
               //               //    .mediaActionCircleStyle()
               
               
               
               
               Button {} label: {
                    Image(systemName: "ellipsis")
               }.mediaActionCircleStyle()
          }
          LazyHStack(spacing: MediaActionMetrics.rowSpacing) {
               Button {} label: {
                    HStack(spacing: MediaActionMetrics.contentSpacing) {
                         Image(systemName: "play.fill")
                         MediaActionProgressTrack(progress: 0.35)
                         Text("34 мин")
                              .font(MediaActionMetrics.labelFont)
                    }
               }
               .mediaActionPlayPillStyle()
               
               
               
               //               Button {} label: {
               //                    Image(systemName: "checkmark")
               //               }.mediaActionCircleStyle() // Mark as Watched, only visible on in progress/unwatched items. Spinner until success, button disappears animated scale down when marked, updates play button state and shows toast on success
               
               
               
               //               Button {} label: {
               //                    Label("Просмотрено", systemImage: "checkmark")
               //                         .font(MediaActionMetrics.labelFont)
               //               }.mediaActionPillStyle() // Mark as Watched, only visible on in progress/unwatched items. Spinner until success, button disappears animated scale down when marked, updates play button state and shows toast on success
               
               
               
               //               Button {} label: {
               //                    Label("Random", systemImage: "shuffle")
               //                         .font(MediaActionMetrics.labelFont)
               //                    //                    .padding(.horizontal, 2)
               //               }.mediaActionPillStyle()
               
               
               //               Button {} label: {
               //                    Image(systemName: "arrow.trianglehead.counterclockwise")
               //               }.mediaActionCircleStyle()

               
               Button {} label: {
                    Label("Просмотрено", systemImage: "checkmark")
                         .font(MediaActionMetrics.labelFont)
               }.mediaActionPillStyle() // Mark as Watched, only visible on in progress/unwatched items. Spinner until success, button disappears animated scale down when marked, updates play button state and shows toast on success
               // Long press for more options - "Серия 4", "2 сезон", "Все серии"
               
               
               Button {} label: {
                    Label("Трейлер", systemImage: "play.fill")
                         .font(MediaActionMetrics.labelFont)
                    //                    .padding(.horizontal, 2)
               }
               //    .buttonStyle(.glass)
               .mediaActionPillStyle()
               
//               Button {} label: {
//                    Label("Трейлер", systemImage: "video.fill")
//                         .font(MediaActionMetrics.labelFont)
//                    //                    .padding(.horizontal, 2)
//               }
//               //    .buttonStyle(.glass)
//               .mediaActionPillStyle()
               
               
//               Button {} label: {
//                    Label("Выбрать серию", systemImage: "rectangle.on.rectangle")
//                         .font(MediaActionMetrics.labelFont)
//               }.mediaActionPillStyle() // Выбрать сезон
               

               
               
               
               //               Button {} label: {
               //                    Image(systemName: "video.fill")
               //                         .font(MediaActionMetrics.labelFont)
               //                    //                    .padding(.horizontal, 2)
               //               }
               //               //    .buttonStyle(.glass)
               //               .mediaActionCircleStyle()
               
               
               //               Button {} label: {
               //                    Image(systemName: "info")
               //               }.mediaActionCircleStyle()
               
               
               
               //               Button {} label: {
               //                    Image(systemName: "checkmark")
               //               }.mediaActionCircleStyle() // Mark as Watched, only visible on in progress/unwatched items. Spinner until success, button disappears animated scale down when marked, updates play button state and shows toast on success
               
//
//               Button {} label: {
//                    Label("Подписаться", systemImage: "plus")
//                         .font(MediaActionMetrics.labelFont)
//                    //                    .padding(.horizontal, 2)
//               }
//               //    .buttonStyle(.glass)
//               .mediaActionPillStyle()
               
               
               
               Button {} label: {
                    Image(systemName: "bell")
               }.mediaActionCircleStyle() // Follow/subscribe/add to watchlist. Только для сериалов и шоу. "bell.fill" когда подписан. Клик spinner потом тост.
               
//               Button {} label: {
//                    Image(systemName: "plus")
//               }.mediaActionCircleStyle() // // bookmark.fill when bookmarked
               
               
               Button {} label: {
                    Image(systemName: "bookmark")
               }.mediaActionCircleStyle() // // bookmark.fill when bookmarked
               
   
               Button {} label: {
                    Image(systemName: "arrow.down.to.line")
               }.mediaActionCircleStyle() // Download
               
               
               //               Button {} label: {
               //                    //      Image(systemName: "bookmark")
               //
               //                    //            .font(MediaActionMetrics.labelFont)
               //                    Label("Save", systemImage: "bookmark")
               //                         .font(MediaActionMetrics.labelFont)
               //                    //                    .padding(.horizontal, 2)
               //                    //        .mediaActionIconFont(size: MediaActionMetrics.circleIconPointSize, weight: .semibold)
               //                    // bookmark.fill when bookmarked, label = Name of folder or "2 Lists"
               //               }
               //               //    .buttonStyle(.glass)
               //               .mediaActionPillStyle()
               //               //    .mediaActionCircleStyle()
               
               
               
               Button {} label: {
                    Image(systemName: "shuffle")
               }.mediaActionCircleStyle() // Play random unwatched episode, only for tv shows or shows with lots of episodes
               
               Button {} label: {
                    Image(systemName: "ellipsis")
               }.mediaActionCircleStyle()
          }
          LazyHStack(spacing: MediaActionMetrics.rowSpacing) {
               Button {} label: {
                    HStack(spacing: MediaActionMetrics.contentSpacing) {
                         Image(systemName: "play.fill")
                         Text("1 сезон, 1 серия")
                              .font(MediaActionMetrics.labelFont)
                    }
               }
               .mediaActionPlayPillStyle()
               
               
               
               //               Button {} label: {
               //                    Image(systemName: "checkmark")
               //               }.mediaActionCircleStyle() // Mark as Watched, only visible on in progress/unwatched items. Spinner until success, button disappears animated scale down when marked, updates play button state and shows toast on success
               
               
               
               //               Button {} label: {
               //                    Label("Просмотрено", systemImage: "checkmark")
               //                         .font(MediaActionMetrics.labelFont)
               //               }.mediaActionPillStyle() // Mark as Watched, only visible on in progress/unwatched items. Spinner until success, button disappears animated scale down when marked, updates play button state and shows toast on success
               
               
               
               //               Button {} label: {
               //                    Label("Random", systemImage: "shuffle")
               //                         .font(MediaActionMetrics.labelFont)
               //                    //                    .padding(.horizontal, 2)
               //               }.mediaActionPillStyle()
               
               
               //               Button {} label: {
               //                    Image(systemName: "arrow.trianglehead.counterclockwise")
               //               }.mediaActionCircleStyle()

     
               
               
               Button {} label: {
                    Label("Трейлер", systemImage: "play.fill")
                         .font(MediaActionMetrics.labelFont)
                    //                    .padding(.horizontal, 2)
               }
               //    .buttonStyle(.glass)
               .mediaActionPillStyle()
               
//               Button {} label: {
//                    Label("Трейлер", systemImage: "video.fill")
//                         .font(MediaActionMetrics.labelFont)
//                    //                    .padding(.horizontal, 2)
//               }
//               //    .buttonStyle(.glass)
//               .mediaActionPillStyle()
               
               
//               Button {} label: {
//                    Label("Выбрать серию", systemImage: "rectangle.on.rectangle")
//                         .font(MediaActionMetrics.labelFont)
//               }.mediaActionPillStyle() // Выбрать сезон
               

               
               
               
               //               Button {} label: {
               //                    Image(systemName: "video.fill")
               //                         .font(MediaActionMetrics.labelFont)
               //                    //                    .padding(.horizontal, 2)
               //               }
               //               //    .buttonStyle(.glass)
               //               .mediaActionCircleStyle()
               
               
               //               Button {} label: {
               //                    Image(systemName: "info")
               //               }.mediaActionCircleStyle()
               
               
               
               //               Button {} label: {
               //                    Image(systemName: "checkmark")
               //               }.mediaActionCircleStyle() // Mark as Watched, only visible on in progress/unwatched items. Spinner until success, button disappears animated scale down when marked, updates play button state and shows toast on success
               
//
//               Button {} label: {
//                    Label("Подписаться", systemImage: "plus")
//                         .font(MediaActionMetrics.labelFont)
//                    //                    .padding(.horizontal, 2)
//               }
//               //    .buttonStyle(.glass)
//               .mediaActionPillStyle()
               
               
//               Button {} label: {
//                    Label("Вы подписаны", systemImage: "bell.and.waves.left.and.right.fill")
//                         .font(MediaActionMetrics.labelFont)
//                    //                    .padding(.horizontal, 2)
//               }
//               //    .buttonStyle(.glass)
//               .mediaActionPillStyle()
////
               
//               Button {} label: {
//                    Label("Подписаться", systemImage: "bell")
//                         .font(MediaActionMetrics.labelFont)
//                    //                    .padding(.horizontal, 2)
//               }
//               //    .buttonStyle(.glass)
//               .mediaActionPillStyle()
//               
               
               Button {} label: {
                    Image(systemName: "bell.and.waves.left.and.right.fill")
               }.mediaActionCircleStyle()
//               Button {} label: {
//                    Image(systemName: "bell.badge.fill")
//               }.mediaActionCircleStyle() // Follow/subscribe/add to watchlist. Только для сериалов и шоу. "bell.fill" когда подписан. Клик spinner потом тост.
               
//               Button {} label: {
//                    Image(systemName: "plus")
//               }.mediaActionCircleStyle() // // bookmark.fill when bookmarked
               
//               Button {} label: {
//                    Label("Отложить", systemImage: "bookmark")
//                         .font(MediaActionMetrics.labelFont)
//                    //                    .padding(.horizontal, 2)
//               }
//               //    .buttonStyle(.glass)
//               .mediaActionPillStyle()
               
               Button {} label: {
                    Image(systemName: "bookmark.fill")
               }.mediaActionCircleStyle()
      
   

               
               
               //               Button {} label: {
               //                    //      Image(systemName: "bookmark")
               //
               //                    //            .font(MediaActionMetrics.labelFont)
               //                    Label("Save", systemImage: "bookmark")
               //                         .font(MediaActionMetrics.labelFont)
               //                    //                    .padding(.horizontal, 2)
               //                    //        .mediaActionIconFont(size: MediaActionMetrics.circleIconPointSize, weight: .semibold)
               //                    // bookmark.fill when bookmarked, label = Name of folder or "2 Lists"
               //               }
               //               //    .buttonStyle(.glass)
               //               .mediaActionPillStyle()
               //               //    .mediaActionCircleStyle()
               
               
               Button {} label: {
                    Image(systemName: "checkmark")
               }.mediaActionCircleStyle()

               
               Button {} label: {
                    Image(systemName: "ellipsis")
               }.mediaActionCircleStyle()
          }
          
          LazyHStack(spacing: MediaActionMetrics.rowSpacing) {
               //               Button {} label: {
               //                    Label("From Beggining", systemImage: "arrow.trianglehead.counterclockwise")
               //                         .font(MediaActionMetrics.labelFont)
               //                    //                    .padding(.horizontal, 2)
               //               }
               //               //    .buttonStyle(.glass)
               //               .mediaActionPillStyle()
               //               Button {} label: {
               //                    Image(systemName: "arrow.trianglehead.counterclockwise")
               //               }.mediaActionCircleStyle() // Mark as Watched, only visible on in progress/unwatched items
               Button {} label: {
                    HStack(spacing: MediaActionMetrics.contentSpacing) {
                         Image(systemName: "play.fill")
                         MediaActionProgressTrack(progress: 0.35)
                         Text("1 сезон, 2 серия")
                              .font(MediaActionMetrics.labelFont)
                    }
                    //                    .padding(.horizontal, 6)
                    //      HStack(spacing: MediaActionMetrics.contentSpacing) {
                    //        Image(systemName: "play.fill")
                    ////          .font(MediaActionMetrics.labelFont)
                    //        Text("Play")
                    //          .font(MediaActionMetrics.labelFont)
                    //          .padding(.horizontal, 4)
                    //      }
                    //      .frame(minWidth: MediaActionMetrics.playPillMinWidth)
               }
               .mediaActionPlayPillStyle()
               
               //               Button {} label: {
               //                    Label("Random", systemImage: "shuffle")
               //                         .font(MediaActionMetrics.labelFont)
               //                    //                    .padding(.horizontal, 2)
               //               }.mediaActionPillStyle()
               
               
               //               Button {} label: {
               //                    Image(systemName: "arrow.trianglehead.counterclockwise")
               //               }.mediaActionCircleStyle()
               
               
               Button {} label: {
                    Label("Просмотрено", systemImage: "checkmark")
                         .font(MediaActionMetrics.labelFont)
               }.mediaActionPillStyle() // Mark as Watched, only visible on in progress/unwatched items. Spinner until success, button disappears animated scale down when marked, updates play button state and shows toast on success
               // Long press for more options - "Серия 4", "2 сезон", "Все серии"
               
               Button {} label: {
                    Label("Трейлер", systemImage: "play.fill")
                         .font(MediaActionMetrics.labelFont)
                    //                    .padding(.horizontal, 2)
               }
               //    .buttonStyle(.glass)
               .mediaActionPillStyle()
               
               Button {} label: {
                    Image(systemName: "bell")
               }.mediaActionCircleStyle()
               
               Button {} label: {
                    Image(systemName: "bookmark")
               }.mediaActionCircleStyle() // // bookmark.fill when bookmarked
               
               
               //               Button {} label: {
               //                    //      Image(systemName: "bookmark")
               //
               //                    //            .font(MediaActionMetrics.labelFont)
               //                    Label("Save", systemImage: "bookmark")
               //                         .font(MediaActionMetrics.labelFont)
               //                    //                    .padding(.horizontal, 2)
               //                    //        .mediaActionIconFont(size: MediaActionMetrics.circleIconPointSize, weight: .semibold)
               //                    // bookmark.fill when bookmarked, label = Name of folder or "2 Lists"
               //               }
               //               //    .buttonStyle(.glass)
               //               .mediaActionPillStyle()
               //               //    .mediaActionCircleStyle()
               
               
               
               Button {} label: {
                    Image(systemName: "shuffle")
               }.mediaActionCircleStyle() // Play random unwatched episode, only for tv shows or shows with lots of episodes or when all episodes already watched
               Button {} label: {
                    Image(systemName: "ellipsis")
               }.mediaActionCircleStyle()
          }
          
          LazyHStack(spacing: MediaActionMetrics.rowSpacing) {
               //               Button {} label: {
               //                    Label("From Beggining", systemImage: "arrow.trianglehead.counterclockwise")
               //                         .font(MediaActionMetrics.labelFont)
               //                    //                    .padding(.horizontal, 2)
               //               }
               //               //    .buttonStyle(.glass)
               //               .mediaActionPillStyle()
               //               Button {} label: {
               //                    Image(systemName: "arrow.trianglehead.counterclockwise")
               //               }.mediaActionCircleStyle() // Mark as Watched, only visible on in progress/unwatched items
               Button {} label: {
                    HStack(spacing: MediaActionMetrics.contentSpacing) {
                         Image(systemName: "play.fill")
                         Text("1 сезон, 1 серия")
                              .font(MediaActionMetrics.labelFont)
                    }
                    //                    .padding(.horizontal, 6)
                    //      HStack(spacing: MediaActionMetrics.contentSpacing) {
                    //        Image(systemName: "play.fill")
                    ////          .font(MediaActionMetrics.labelFont)
                    //        Text("Play")
                    //          .font(MediaActionMetrics.labelFont)
                    //          .padding(.horizontal, 4)
                    //      }
                    //      .frame(minWidth: MediaActionMetrics.playPillMinWidth)
               }
               .mediaActionPlayPillStyle()
               
               //               Button {} label: {
               //                    Label("Random", systemImage: "shuffle")
               //                         .font(MediaActionMetrics.labelFont)
               //                    //                    .padding(.horizontal, 2)
               //               }.mediaActionPillStyle()
               
               
               //               Button {} label: {
               //                    Image(systemName: "arrow.trianglehead.counterclockwise")
               //               }.mediaActionCircleStyle()
               Button {} label: {
                    Label("Трейлер", systemImage: "video.fill")
                         .font(MediaActionMetrics.labelFont)
                    //                    .padding(.horizontal, 2)
               }
               //    .buttonStyle(.glass)
               .mediaActionPillStyle()
               
               Button {} label: {
                    Label("Случайно", systemImage: "shuffle")
                         .font(MediaActionMetrics.labelFont)
                    //                    .padding(.horizontal, 2)
               }
               //    .buttonStyle(.glass)
               .mediaActionPillStyle()
               
               Button {} label: {
                    Image(systemName: "bookmark")
               }.mediaActionCircleStyle() // // bookmark.fill when bookmarked
               
               
               //               Button {} label: {
               //                    //      Image(systemName: "bookmark")
               //
               //                    //            .font(MediaActionMetrics.labelFont)
               //                    Label("Save", systemImage: "bookmark")
               //                         .font(MediaActionMetrics.labelFont)
               //                    //                    .padding(.horizontal, 2)
               //                    //        .mediaActionIconFont(size: MediaActionMetrics.circleIconPointSize, weight: .semibold)
               //                    // bookmark.fill when bookmarked, label = Name of folder or "2 Lists"
               //               }
               //               //    .buttonStyle(.glass)
               //               .mediaActionPillStyle()
               //               //    .mediaActionCircleStyle()
               
               
               Button {} label: {
                    Image(systemName: "checkmark")
               }.mediaActionCircleStyle() // Mark as Watched, only visible on in progress/unwatched items. Spinner until success, button disappears animated scale down when marked, updates play button state and shows toast on success
               

               Button {} label: {
                    Image(systemName: "ellipsis")
               }.mediaActionCircleStyle()
          }
          HStack (spacing: 10) {
               Button {} label: {
                    Label("Play", systemImage: "play.fill")
                    .font(MediaActionMetrics.labelFont)}
               .padding(.horizontal, 6)
               .mediaActionPlayPillStyle()
               Button {} label: {
                    Label("Смотреть", systemImage: "play.fill")
                    .font(MediaActionMetrics.labelFont)}
               .padding(.horizontal, 6)
               .mediaActionPillStyle()
               Button {} label: {
                    Label("Play First Episode", systemImage: "play.fill")
                    .font(MediaActionMetrics.labelFont)}
               .padding(.horizontal, 6)
               .mediaActionPillStyle()
               Button {} label: {
                    Label("1 сезон, 1 серия", systemImage: "play.fill")
                    .font(MediaActionMetrics.labelFont)}
               .padding(.horizontal, 6)
               .mediaActionPillStyle()
               Button {} label: {
                    Label("Season 1, Episode 1", systemImage: "play.fill")
                    .font(MediaActionMetrics.labelFont)}
               .padding(.horizontal, 6)
               .mediaActionPillStyle()
               Button {} label: {
                    Label("Play S1, E1", systemImage: "play.fill")
                    .font(MediaActionMetrics.labelFont)}
               .padding(.horizontal, 6)
               .mediaActionPillStyle()
          }
          HStack (spacing: 10) {
               Button {} label: {
                    Label("Play Again", systemImage: "play.fill")
                    .font(MediaActionMetrics.labelFont)}
               .padding(.horizontal, 6)
               .mediaActionPlayPillStyle()
               Button {} label: {
                    Label("Смотреть ещё раз", systemImage: "play.fill")
                    .font(MediaActionMetrics.labelFont)}
               .padding(.horizontal, 6)
               .mediaActionPillStyle()
               Button {} label: {
                    Label("Пересмотреть", systemImage: "arrow.trianglehead.counterclockwise")
                    .font(MediaActionMetrics.labelFont)}
               .padding(.horizontal, 6)
               .mediaActionPillStyle()
          }
          HStack (spacing: 10) {
               Button {} label: {
                    Label("Resume S1, E2", systemImage: "play.fill")
                    .font(MediaActionMetrics.labelFont)}
               .padding(.horizontal, 6)
               .mediaActionPlayPillStyle()
               Button {} label: {
                    Label("Продолжить S1, E2", systemImage: "play.fill")
                    .font(MediaActionMetrics.labelFont)}
               .padding(.horizontal, 6)
               .mediaActionPillStyle()
               Button {} label: {
                    Label("1 сезон, 2 серия", systemImage: "play.fill")
                    .font(MediaActionMetrics.labelFont)}
               .padding(.horizontal, 6)
               .mediaActionPillStyle()
               Button {} label: {
                    Label("Далее 1 сезон, 2 серия", systemImage: "play.fill")
                    .font(MediaActionMetrics.labelFont)}
               .padding(.horizontal, 6)
               .mediaActionPillStyle()
          }
          HStack (spacing: 10) {

          Button {} label: {
               HStack(spacing: MediaActionMetrics.contentSpacing) {
                    Image(systemName: "play.fill")
                    MediaActionProgressTrack(progress: 0.35)
                    Text("S1, E2 ∙ 34m")
                         .font(MediaActionMetrics.labelFont)
               }
          }
          .mediaActionPlayPillStyle()

          Button {} label: {
               HStack(spacing: MediaActionMetrics.contentSpacing) {
                    Image(systemName: "play.fill")
                    MediaActionProgressTrack(progress: 0.35)
                    Text("1 сезон, 2 серия")
                         .font(MediaActionMetrics.labelFont)
               }
          }
          .mediaActionPillStyle()
               Button {} label: {
                    HStack(spacing: MediaActionMetrics.contentSpacing) {
                         Image(systemName: "play.fill")
                         MediaActionProgressTrack(progress: 0.35)
                         Text("2 серия")
                              .font(MediaActionMetrics.labelFont)
                    }
               }
               .mediaActionPillStyle()
     }
}
     .padding(.vertical, 18)
  .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  .background(Color.clear)
//  .preferredColorScheme(.dark)
}
