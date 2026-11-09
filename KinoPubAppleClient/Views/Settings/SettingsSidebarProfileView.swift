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
        Text(name)
#if os(iOS)
          .font(.title3.weight(.semibold))
#else
          .font(.body.weight(.semibold))
#endif
          .foregroundStyle(.primary)
          .lineLimit(1)
        Text(subtitle)
#if os(iOS)
          .font(.footnote)
#else
          .font(.caption)
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

  /// The picture, or the initials on a grey disc, at whatever size it is given: the
  /// sidebar row's and the account page's (Sasha, 2026-11-09).
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
        GeometryReader { proxy in
          let side = min(proxy.size.width, proxy.size.height)
          ZStack {
            Circle().fill(Color.secondary.opacity(0.35))
            if initials.isEmpty {
              Image(systemName: "person.fill")
                .font(.system(size: side * 0.42, weight: .semibold))
                .foregroundStyle(.primary)
            } else {
              Text(initials)
                .font(.system(size: side * 0.32, weight: .semibold))
                .foregroundStyle(.primary)
            }
          }
          .frame(width: proxy.size.width, height: proxy.size.height)
        }
      }
    }

    private var initials: String {
      let trimmed = name.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { return "" }
      let parts = trimmed.split(separator: " ").prefix(2)
      let letters = parts.compactMap { $0.first.map(String.init) }
      return letters.isEmpty ? String(trimmed.prefix(1)).uppercased() : letters.joined().uppercased()
    }
  }
}
#endif
