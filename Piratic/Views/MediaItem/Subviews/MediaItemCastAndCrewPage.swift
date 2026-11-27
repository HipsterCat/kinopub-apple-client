//
//  MediaItemCastAndCrewPage.swift
//  Piratic
//
//  Full cast & crew for a title — what the cast rail's header opens on iOS / iPadOS /
//  macOS. Local filter + All / Cast / Crew, round avatars, no generic «Актёр» labels.
//  Nothing here fetches: the company travelled in the route.
//
//  macOS must not use `.searchable` — the split view already owns that field for app
//  Search (`macSidebarSearch`), and a nested one steals the prompt («Поиск по составу»)
//  while still routing typing into catalog Search.
//

import SwiftUI
import PiraticUI
import KinoPubBackend
import PiraticMetadata

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

  private var sections: [CastAndCrew.Section] {
    payload.sections(for: tab, matching: query)
  }

  private var rowInsets: EdgeInsets {
    EdgeInsets(top: 6, leading: MediaItemLayout.horizontalInset,
               bottom: 6, trailing: MediaItemLayout.horizontalInset)
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

#if os(macOS)
      Section {
        macFilterField
          .listRowInsets(EdgeInsets(top: 4, leading: MediaItemLayout.horizontalInset,
                                    bottom: 4, trailing: MediaItemLayout.horizontalInset))
          .listRowBackground(Color.clear)
          .listRowSeparator(.hidden)
      }
#endif

      ForEach(sections) { section in
        Section {
          ForEach(section.rows) { entry in
            NavigationLink(value: linkProvider.person(for: entry.person)) {
              CastAndCrewRow(entry: entry)
            }
            .listRowInsets(rowInsets)
          }
        } header: {
          Text(section.titleWithCount)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MediaItemLayout.horizontalInset)
            .textCase(nil)
        }
      }
    }
    .listStyle(.plain)
#if os(iOS)
    .listSectionSpacing(12)
    // iOS: page-local filter. The Search tab owns its own `.searchable`; this one
    // stays on the cast sheet and does not open catalog Search.
    .searchable(text: $query, prompt: Text("MediaItem_CastAndCrewSearch"))
#endif
    .platformNavigationTitle(payload.item.displayTitle)
#if os(iOS) || os(macOS)
    .navigationSubtitle("MediaItem_CastSection".localized)
#endif
    .background(Color.Piratic.background.ignoresSafeArea())
    .onAppear {
      if !visibleTabs.contains(tab), let first = visibleTabs.first {
        tab = first
      }
    }
  }

#if os(macOS)
  /// Explicit field — never `.searchable` on macOS (sidebar Search steals it).
  private var macFilterField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)
      TextField("MediaItem_CastAndCrewSearch".localized, text: $query)
        .textFieldStyle(.plain)
        .labelsHidden()
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
  }
#endif
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
          .foregroundStyle(Color.Piratic.text)
          .lineLimit(1)

        if let role = entry.roleLine, !role.isEmpty {
          Text(role)
            .font(.subheadline)
            .foregroundStyle(Color.Piratic.subtitle)
            .lineLimit(2)
        }

        if let episodes = entry.episodeLine {
          Text(episodes)
            .font(.subheadline)
            .foregroundStyle(Color.Piratic.subtitle)
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
                                        episodeCount: 34, order: 1),
                             CastMember(name: "Extra Player", character: "Bar Patron",
                                        episodeCount: 2, order: 40)
                           ],
                           crew: [
                             CastMember(name: "Bill Lawrence", character: "Creator",
                                        department: "Writing"),
                             CastMember(name: "Han Yan", character: "Director",
                                        department: "Directing"),
                             CastMember(name: "Han Yan", character: "Writer",
                                        department: "Writing")
                           ]),
      linkProvider: AppRoutesLinkProvider()
    )
  }
}
#endif
