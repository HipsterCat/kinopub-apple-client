//
//  ScrollMemory.swift
//  KinoPubUI
//
//  Where a page was scrolled to, kept by the page's long-lived model so that coming back
//  to a section finds it where it was left (Sasha, 2026-10-31). Not observable on
//  purpose: the offset is written on every scroll frame and nothing redraws for it.
//

import SwiftUI

public final class ScrollMemory {
  /// The top of the visible area, in content points.
  public var y: CGFloat = 0
  public init() {}
}

public extension EnvironmentValues {
  /// The memory for the page's main vertical scroll. A section sets it on its root page;
  /// a page pushed over it gets its own, or none.
  @Entry var scrollMemory: ScrollMemory? = nil
  /// Bumped when the section's page is asked back to its top: the section chosen again
  /// while already at its root (Sasha, 2026-10-31).
  @Entry var scrollToTopRequest: Int = 0
}

public extension View {
  /// Remembers this scroll view's offset in `scrollMemory` and goes back to it when the
  /// page comes back, and goes to the top on `scrollToTopRequest`.
  func remembersScroll() -> some View {
    modifier(RememberedScroll())
  }
}

private struct RememberedScroll: ViewModifier {
  @Environment(\.scrollMemory) private var memory
  @Environment(\.scrollToTopRequest) private var scrollToTopRequest
  @State private var position = ScrollPosition(edge: .top)

  func body(content: Content) -> some View {
    content
      .scrollPosition($position)
      .onScrollGeometryChange(for: CGFloat.self) { geometry in
        geometry.contentOffset.y + geometry.contentInsets.top
      } action: { _, y in
        memory?.y = max(y, 0)
      }
      .task {
        // Once the lazy content has laid out down to where the page was.
        guard let memory, memory.y > 1 else { return }
        let y = memory.y
        for _ in 0..<3 {
          try? await Task.sleep(for: .milliseconds(80))
          position.scrollTo(y: y)
        }
      }
      .onChange(of: scrollToTopRequest) {
        withAnimation { position.scrollTo(edge: .top) }
      }
  }
}
