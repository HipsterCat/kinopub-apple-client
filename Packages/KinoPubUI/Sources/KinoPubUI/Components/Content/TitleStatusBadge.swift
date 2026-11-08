//
//  TitleStatusBadge.swift
//  KinoPubUI
//
//  The one written badge a title page leads its facts with — «Новый сезон», «Новые
//  серии», «Новая серия через 5 дней», «Премьера»… Apple's TV app puts the same capsule
//  («Дата выхода: 18 нояб.») above the title: a dark fill, a faint light outline, the
//  words in the line's own type, a step bolder (Sasha, 2026-11-08).
//

import SwiftUI

public struct TitleStatusBadge: View {
  private let text: String

  public init(_ text: String) {
    self.text = text
  }

  @Environment(\.colorSchemeContrast) private var contrast

  public var body: some View {
    Text(verbatim: text)
      .fontWeight(.semibold)
      .foregroundStyle(Color.KinoPub.text)
      .lineLimit(1)
      .padding(.horizontal, Self.horizontalPadding)
      .padding(.vertical, Self.verticalPadding)
      .background {
        Self.shape.fill(Color.black.opacity(0.35))
      }
      .overlay {
        // Increase Contrast: a solid line, not a hint of one.
        Self.shape.strokeBorder(Color.KinoPub.text.opacity(contrast == .increased ? 0.9 : 0.45),
                                lineWidth: Self.strokeWidth)
      }
      .fixedSize()
  }

  private static let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

#if os(tvOS)
  static let horizontalPadding: CGFloat = 12
  static let verticalPadding: CGFloat = 4
  static let cornerRadius: CGFloat = 10
  static let strokeWidth: CGFloat = 2
#else
  static let horizontalPadding: CGFloat = 7
  static let verticalPadding: CGFloat = 2
  static let cornerRadius: CGFloat = 6
  static let strokeWidth: CGFloat = 1
#endif
}

#Preview("Status badge") {
  HStack {
    TitleStatusBadge("Новый сезон")
    Text(verbatim: "2025–26 сериал")
  }
  .padding()
  .background(Color.brown)
  .environment(\.colorScheme, .dark)
}
