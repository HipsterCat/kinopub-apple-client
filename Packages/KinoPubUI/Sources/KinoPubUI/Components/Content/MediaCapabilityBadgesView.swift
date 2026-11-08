//
//  MediaCapabilityBadgesView.swift
//  KinoPubUI
//

import SwiftUI
import KinoPubBackend

/// Renders `MediaCapabilityBadges` as compact system-looking capsules.
public struct MediaCapabilityBadgesView: View {
  public enum Mode {
    case poster
    case detail
  }

  private let badges: MediaCapabilityBadges
  private let mode: Mode

  public init(badges: MediaCapabilityBadges, mode: Mode = .detail) {
    self.badges = badges
    self.mode = mode
  }

  public var body: some View {
    switch mode {
    case .poster:
      typedChips(badges.posterChips)
    case .detail:
      // The drawn marks of `Media.xcassets/badges` (Sasha, 2026-11-08); a certification
      // has no drawing, so it stays a typed capsule after them.
      let assets = badges.detailBadgeAssets
      let rating = badges.ageRating.flatMap { $0.isEmpty ? nil : $0 }
      if !assets.isEmpty || rating != nil {
        HStack(spacing: Self.spacing) {
          if !assets.isEmpty {
            MediaBadgeImages(assets)
          }
          if let rating {
            typedChips([rating])
          }
        }
      }
    }
  }

  @ViewBuilder
  private func typedChips(_ chips: [String]) -> some View {
    if !chips.isEmpty {
      HStack(spacing: 6) {
        ForEach(chips, id: \.self) { chip in
          Text(chip)
            .font(Self.font)
            .foregroundStyle(.primary)
            .padding(.horizontal, Self.horizontalPadding)
            .padding(.vertical, Self.verticalPadding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .accessibilityLabel(Text(chip))
        }
      }
    }
  }

  static let spacing: CGFloat = 8

#if os(tvOS)
  static let font: Font = .caption.weight(.semibold)
  static let horizontalPadding: CGFloat = 8
  static let verticalPadding: CGFloat = 4
#else
  static let font: Font = .caption2.weight(.semibold)
  static let horizontalPadding: CGFloat = 6
  static let verticalPadding: CGFloat = 2
#endif
}

/// Badges drawn in `Media.xcassets/badges` (4K, HD, SD, 3D, CC, AD…), as tall as the
/// surrounding text's capitals and as wide as each drawing is. Template-rendered, so they
/// take the line's foreground — the files are white shapes with the letters knocked out.
/// No point size: the height comes from the font in the environment, so Dynamic Type and
/// every platform's type scale size them.
public struct MediaBadgeImages: View {
  private let names: [String]

  public init(_ names: [String]) {
    self.names = names
  }

  public var body: some View {
    BadgeImagesFitText(spacing: MediaCapabilityBadgesView.spacing) {
      // The yardstick: one capital in the line's font, never drawn.
      Text(verbatim: "H").hidden().accessibilityHidden(true)
      ForEach(names, id: \.self) { name in
        Image(name, bundle: .module)
          .renderingMode(.template)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .accessibilityLabel(Text(verbatim: name))
      }
    }
  }
}

/// First subview measures the line; every other one is drawn at that line's height
/// times `capRatio`, as wide as its own aspect ratio allows. The first takes no room.
private struct BadgeImagesFitText: Layout {
  var spacing: CGFloat
  /// The drawings are 15 pt tall boxes around 9 pt capitals: at 0.82 of the line height
  /// their box sits just inside the line, as Apple's badges do beside text.
  var capRatio: CGFloat = 0.82

  private func sizes(_ subviews: Subviews) -> (line: CGFloat, items: [CGSize]) {
    guard let ruler = subviews.first else { return (0, []) }
    let line = ruler.sizeThatFits(.unspecified).height
    let height = (line * capRatio).rounded()
    let items = subviews.dropFirst().map { subview -> CGSize in
      let natural = subview.sizeThatFits(.unspecified)
      let width = natural.height > 0 ? natural.width * height / natural.height : height
      return CGSize(width: width.rounded(), height: height)
    }
    return (line, items)
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let (line, items) = sizes(subviews)
    let width = items.map(\.width).reduce(0, +) + spacing * CGFloat(max(items.count - 1, 0))
    return CGSize(width: width, height: line)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let (_, items) = sizes(subviews)
    subviews.first?.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: 0, height: 0))
    var x = bounds.minX
    for (subview, size) in zip(subviews.dropFirst(), items) {
      subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
      x += size.width + spacing
    }
  }
}

#Preview("Capability badges") {
  VStack(alignment: .leading, spacing: 20) {
    MediaCapabilityBadgesView(
      badges: MediaCapabilityBadges(is4K: true, isHDR: true),
      mode: .poster
    )
    MediaCapabilityBadgesView(
      badges: MediaCapabilityBadges(
        is4K: true,
//        isHDR: true,
        is3D: true,
        ageRating: "18+",
        hasClosedCaptions: true,
//        languages: ["RU"],
//        audioChannelHint: "DD"
      ),
      mode: .detail
    )
  }
  .padding()
  // .background(Color.black)
  // .preferredColorScheme(.dark)
}
