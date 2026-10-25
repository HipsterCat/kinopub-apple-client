#if os(tvOS)
import XCTest
import KinoPubMedia
@testable import KinoPubUI

final class TVPageIdentityTests: XCTestCase {

  private func card(_ id: Int, title: String = "T") -> MediaCard {
    MediaCard(id: id, posterURL: "", title: title)
  }

  /// Following and Continue share title ids. The cell class must travel with the
  /// item id, or reconfigure dequeues a still into a poster cell.
  func testAPosterAndAStillOfTheSameTitleAreDifferentIdentities() {
    let posters = TVPageSection.posters(id: "library", title: nil, flow: .grid, cards: [card(42)])
    let stills = TVPageSection.stills(id: "library", title: nil, flow: .grid, cards: [card(42)])
    XCTAssertNotEqual(posters.itemID(at: 0), stills.itemID(at: 0))
    XCTAssertEqual(posters.itemID(at: 0).registration, .poster)
    XCTAssertEqual(stills.itemID(at: 0).registration, .still)
  }

  /// Words can change under the same cover; the cell class cannot. Reconfigure is
  /// safe only while the registration stays put.
  func testAPostersRegistrationStaysPutWhenOnlyItsWordsChange() {
    let first = TVPageSection.posters(id: "library.watchlist", title: nil, flow: .grid,
                                      cards: [card(42, title: "A")])
    let next = TVPageSection.posters(id: "library.watchlist", title: nil, flow: .grid,
                                     cards: [card(42, title: "B")])
    XCTAssertEqual(first.itemID(at: 0), next.itemID(at: 0))
    XCTAssertEqual(first.itemID(at: 0).registration, .poster)
  }

  /// Cast & Crew is a strip of people in three columns: they are wide cards, not round
  /// person lockups grown to a third of the screen.
  func testAPersonInAStripIsAWideCard() {
    let person = TVUIKitPerson(id: "actor:Уиллем Дефо", name: "Уиллем Дефо",
                               nameComponents: TVUIKitPerson.nameComponents(from: "Уиллем Дефо"),
                               caption: nil, photoURL: nil)
    let section = TVPageSection.strip(id: "credits", groups: [
      TVPageGroup(id: "people", title: nil, columns: 3, items: [.person(person)])
    ])
    XCTAssertEqual(section.itemID(at: 0).registration, .card)
  }

  /// Search's top cards put people between titles. They are the same wide card as Cast &
  /// Crew (`testAPersonInAStripIsAWideCard`), never the round lockup at a third of the screen.
  func testAPersonAmongSearchCardsIsAWideCard() {
    let person = TVUIKitPerson(id: "actor:Уиллем Дефо", name: "Уиллем Дефо",
                               nameComponents: TVUIKitPerson.nameComponents(from: "Уиллем Дефо"),
                               caption: "Actor", photoURL: nil)
    let section = TVPageSection.cards(id: "top", title: nil, columns: 3, rows: 2,
                                      items: [.card(card(1)), .person(person)])
    XCTAssertEqual(section.itemID(at: 1).registration, .card)
    let people = TVPageSection.people(id: "people", title: nil, people: [person])
    XCTAssertEqual(people.itemID(at: 0).registration, .person)
  }

  func testUniquedItemsKeepsTheFirstOfADuplicatePerson() {
    let person = TVUIKitPerson(id: "actor:Валид Зуэйтер",
                               name: "Валид Зуэйтер",
                               nameComponents: TVUIKitPerson.nameComponents(from: "Валид Зуэйтер"),
                               caption: nil, photoURL: nil)
    let section = TVPageSection.strip(id: "credits", groups: [
      TVPageGroup(id: "people", title: nil, columns: 3,
                  items: [.person(person), .person(person)])
    ])
    XCTAssertEqual(section.items.count, 2)
    let unique = section.uniquedItems()
    XCTAssertEqual(unique.items.count, 1, "the snapshot cannot hold the same id twice")
    XCTAssertEqual(Set((0..<unique.items.count).map(unique.itemID(at:))).count, unique.items.count)
  }

  func testUniquedItemsKeepsTheFirstOfADuplicateCover() {
    let section = TVPageSection.posters(id: "library.watchlist", title: nil, flow: .grid,
                                        cards: [card(1), card(1), card(2)])
    let unique = section.uniquedItems()
    XCTAssertEqual(unique.items.compactMap(\.card?.id), [1, 2])
  }

  /// Poster lockups copy the id onto the inner view that takes focus. The wide card
  /// must too — otherwise XCUI sees an empty identifier on a focused person.
  @MainActor
  func testAPersonCardPutsItsAccessibilityIdOnTheCardThatTakesFocus() {
    let person = TVUIKitPerson(id: "director:Энтони Руссо",
                               name: "Энтони Руссо",
                               nameComponents: TVUIKitPerson.nameComponents(from: "Энтони Руссо"),
                               caption: "Режиссёр", photoURL: nil)
    let cell = TVPageWideCardCell(frame: CGRect(x: 0, y: 0, width: 500, height: 200))
    cell.configure(person: person)
    let id = "kinopub.card.person.director:Энтони Руссо"
    XCTAssertEqual(cell.accessibilityIdentifier, id)
    let inner = cell.contentView.subviews.compactMap(\.accessibilityIdentifier)
    XCTAssertTrue(inner.contains(id), "the TVCardView that takes focus must carry the id: \(inner)")
  }

  /// Cast & Crew dequeues `TVUIKitPersonCell`, not the wide card. Without an id XCUI
  /// reports the label and an empty identifier («Энтони Руссо, Режиссёр»).
  @MainActor
  func testTheCreditsPersonCellHasAnAccessibilityId() {
    let person = TVUIKitPerson(id: "director:Энтони Руссо",
                               name: "Энтони Руссо",
                               nameComponents: TVUIKitPerson.nameComponents(from: "Энтони Руссо"),
                               caption: "Режиссёр", photoURL: nil)
    let cell = TVUIKitPersonCell(frame: CGRect(x: 0, y: 0, width: 200, height: 280))
    cell.configure(person: person)
    XCTAssertEqual(cell.accessibilityIdentifier, "kinopub.card.person.director:Энтони Руссо")
  }

  @MainActor
  func testAFollowedCoverSaysHowManyEpisodesAreLeft() {
    let followed = MediaCard(id: 1, posterURL: "", title: "Дом Дракона",
                             unwatchedEpisodes: 5)
    XCTAssertEqual(TVPageLockupPosterCell.posterSubtitle(for: followed, caption: .always),
                   EpisodesLeftText(5)?.formatted())
  }
}
#endif
