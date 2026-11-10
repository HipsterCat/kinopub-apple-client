//
//  MediaItemCastAndCrewPage.swift
//  KinoPubAppleClient
//
//  Full cast & crew for a title — what the cast rail's header opens on iOS / iPadOS /
//  macOS. Search + Featured / Regular / Guest / Crew, round avatars, no generic
//  «Актёр» labels. Nothing here fetches: the company travelled in the route.
//

import SwiftUI
import KinoPubUI
import KinoPubBackend
import KinoPubMetadata

#if !os(tvOS)
struct MediaItemCastAndCrewPage: View {
  let payload: CastAndCrew
  let linkProvider: NavigationLinkProvider

  @State private var tab: CastAndCrewTab
  @State private var query = ""

  init(payload: CastAndCrew, linkProvider: NavigationLinkProvider) {
    self.payload = payload
    self.linkProvider = linkProvider
    _tab = State(initialValue: payload.tab)
  }

  private var visibleTabs: [CastAndCrewTab] {
    CastAndCrewTab.allCases.filter { !$0.people(in: payload).isEmpty }
  }

  private var rows: [CastAndCrew.Entry] {
    let base = tab.people(in: payload)
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return base }
    return base.filter { $0.matches(needle) }
  }

  var body: some View {
    List {
      if visibleTabs.count > 1 {
        Section {
          Picker(selection: $tab) {
            ForEach(visibleTabs) { tab in
              Text(tab.title(count: tab.people(in: payload).count)).tag(tab)
            }
          } label: {
            EmptyView()
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .listRowInsets(EdgeInsets(top: 8, leading: MediaItemLayout.horizontalInset,
                                    bottom: 8, trailing: MediaItemLayout.horizontalInset))
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
        }
      }

      Section {
        ForEach(rows) { entry in
          NavigationLink(value: linkProvider.person(for: entry.person)) {
            CastAndCrewRow(entry: entry)
          }
        }
      }
    }
    .listStyle(.plain)
#if os(iOS)
    .listSectionSpacing(12)
#endif
    .searchable(text: $query, prompt: Text("MediaItem_CastAndCrewSearch"))
    .platformNavigationTitle(payload.item.localizedTitle)
#if os(iOS) || os(macOS)
    .navigationSubtitle("MediaItem_CastSection".localized)
#endif
    .background(Color.KinoPub.background.ignoresSafeArea())
    .onAppear {
      if !visibleTabs.contains(tab), let first = visibleTabs.first {
        tab = first
      }
    }
  }
}

private struct CastAndCrewRow: View {
  let entry: CastAndCrew.Entry

  var body: some View {
    HStack(spacing: 14) {
      CastAvatarView(name: entry.person.name, photoURL: entry.person.photoURL,
                     style: .circle, diameter: 56)

      VStack(alignment: .leading, spacing: 2) {
        Text(entry.person.name)
          .font(.body.weight(.semibold))
          .foregroundStyle(Color.KinoPub.text)
          .lineLimit(1)

        if let role = entry.roleLine, !role.isEmpty {
          Text(role)
            .font(.subheadline)
            .foregroundStyle(Color.KinoPub.subtitle)
            .lineLimit(2)
        }

        if let episodes = entry.episodeLine {
          Text(episodes)
            .font(.subheadline)
            .foregroundStyle(Color.KinoPub.subtitle)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, 4)
  }
}

#Preview {
  NavigationStack {
    MediaItemCastAndCrewPage(
      payload: CastAndCrew(item: MediaItem.mock(),
                           cast: [
                             CastMember(name: "Jason Sudeikis", character: "Ted Lasso",
                                        episodeCount: 34, order: 0),
                             CastMember(name: "Hannah Waddingham", character: "Rebecca Welton",
                                        episodeCount: 34, order: 1)
                           ],
                           crew: [
                             CastMember(name: "Bill Lawrence", character: "Creator",
                                        department: "Writing")
                           ]),
      linkProvider: AppRoutesLinkProvider()
    )
  }
}
#endif
