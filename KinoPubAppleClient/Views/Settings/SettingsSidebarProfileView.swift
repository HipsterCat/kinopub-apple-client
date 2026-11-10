//
//  SettingsSidebarProfileView.swift
//  KinoPubAppleClient
//

import SwiftUI
import KinoPubBackend

#if !os(tvOS)
/// Identity row — compact in the macOS sidebar, Apple Account–sized on iOS.
struct SettingsSidebarProfileView: View {
  let name: String
  let subtitle: String
  let avatarImage: Image?

#if os(iOS)
  private let avatarSize: CGFloat = 60
#else
  private let avatarSize: CGFloat = 36
#endif

  var body: some View {
    HStack(spacing: 12) {
      avatar
        .frame(width: avatarSize, height: avatarSize)

      VStack(alignment: .leading, spacing: 2) {
        // Regular weight, as TestFlight's and System Settings' account rows set the name
        // (Sasha, 2026-11-10).
        Text(name)
#if os(iOS)
          .font(.title3)
#else
          .font(.body)
#endif
          .foregroundStyle(.primary)
          .lineLimit(1)
        Text(subtitle)
#if os(iOS)
          .font(.subheadline)
#else
          .font(.callout)
#endif
          .foregroundStyle(.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, 4)
  }

  private var avatar: some View {
    Avatar(name: name, image: avatarImage)
  }

  /// The picture, or the person glyph on a grey disc at whatever size it is given: the
  /// sidebar row's and the account page's. A glyph, not initials or a service's
  /// generated placeholder, as Apple's account rows do (Sasha, 2026-11-10).
  struct Avatar: View {
    let name: String
    let image: Image?

    var body: some View {
      if let image {
        image
          .resizable()
          .scaledToFill()
          .clipShape(Circle())
      } else {
        Image(systemName: "person.crop.circle.fill")
          .resizable()
          .scaledToFit()
          .symbolRenderingMode(.hierarchical)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
    }
  }
}
#endif
