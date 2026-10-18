# The detail page — engineering notes

How the title page is built and why. The short rules are in [AGENTS.md](../../AGENTS.md#the-detail-page); what each row shows is [docs/product/detail-sections.md](../product/detail-sections.md); open work is the Asana task [Страница тайтла](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219606600371250).

- **tvOS backdrop: interim, to be redone — not a design** (Sasha, 2026-10-11: "это все
  переделывать надо… костыль на костыле без разбора в апишках", tolerable for now). Do not
  read the current shape as the desired one, do not defend it, and do not build on it before
  Sasha's pass with reference apps that did read the documentation. What is decided:
  - The picture is **not in the scroll** — one full-screen backdrop behind the content, the
    content changes over it (Sasha, overruling the 2026-09-27 "artwork is part of the hero").
    The hero and the sections stay one scroll and one focus graph.
  - Sasha will supply mean colours / gradients per title and wants them crossfaded, Apple-style.
  What is merely there now (`PageBackdrop` in KinoPubUI, `Route.backdrop`): a stage around the
  tab view showing the picture of the selected tab's top route; the title's page publishes it;
  the hero reports focus in the sections (`pageBackdropDetails`) and the picture fades out to
  the system background there. Rejected on the way, with Sasha's reasons: a lifecycle-claimed
  backdrop (wrong title a few levels deep, late fade on Back), an opaque dark panel in the
  scroll ("moving fixed background", black in the light appearance), `.regularMaterial` over
  the picture (dirty grey in light). Facts measured on the way, not rules: on a tvOS pop the
  page beneath appears ~0.1 s after Menu, the leaving page disappears ~0.5 s later, a stack's
  root never re-appears, `isPresented` drops when a page is covered and never fires back.
  iOS and macOS are untouched: the artwork is the hero's `.background` and scrolls away.
- **Prose in the hero has no chrome at rest.** On tvOS the synopsis is always a `.borderless`
  button, and Select on that button opens the info popup. Do not add `.focusable()` on it: the
  wrapper takes the focus and Select never presses the button, so the popup never opens (Sasha,
  2026-10-01). `.card` is for fact containers — it draws a platter at rest and read as a second
  focus next to Play.
- **Play is the entry focus, by name.** `defaultFocus(priority: .userInitiated)`, and the hero
  claims Play (or Follow-primary) in `onAppear` / `.task`. The synopsis stays out of the focus
  chain until that entry lands — otherwise it is the topmost focusable and steals open, blinking
  Play when focus is corrected. Down from the synopsis returns to Play via separate
  `.focusSection()`s on the plot column and the action row — **never** by `.disabled`-ing
  Trailer / Bookmark / More to steer the remote. That left those controls dim forever whenever
  `@FocusState` lagged the visual focus, and a disabled `Menu` cannot open bookmarks
  (Sasha, 2026-10-01). Coming back from the player the hero claims the same entry control
  again — Follow when it leads, else Play, Replay included — because the row usually changed
  under the control that had focus (Sasha, 2026-10-03).
- **Detail page UI tests run on fixtures.** `-KINOPUBDetailFixture <name>` (DEBUG, tvOS) makes
  the root a stack of local titles served by stand-ins for the API, TMDB and the player
  (`DetailFixture.swift`); `TVDetailPageUITests` walks them with the remote and CI prints the
  screenshots into the tvOS test job's log. `film` is the one with every row populated and local
  artwork, so a layout is looked at with no session and no network (`TVDetailLayoutUITests`).
  Companions: `-KINOPUBFixtureRealArt YES` (the shelves' posters come over the network and are
  cached, as a signed-in session's do), `-KINOPUBFixtureInTabs YES` (the stack sits under
  production's tab bar) and `-KINOPUBSlowShelves <s>` (the shelves arrive late, while the hero
  holds focus). `-KINOPUBLibraryFixture YES` is the same idea for the Library: the real page on a
  stand-in API listing twelve followed series (`LibraryFixture`, `TVDetailLayoutUITests`) — how the
  *Following* captions («2 серии») look, with no session. **Run it on both simulator runtimes, tvOS 27.2 and 26.5 — and once on an Apple TV 4K device that is not "(at 1080p)"** (scale 2; it is the first device CI picks, and a lockup computes its focus growth in whole points there: art 254 where 1080p reads 256) — they differ: on 26.5
  the poster art's focus bug above (and, before captions became ours, a system footer's height changed how tall art grew — see Troubleshooting).
- **On tvOS everything under the hero is one embedded TVUIKit page** (Sasha, 2026-10-06).
  `MediaItemTVSections.make` is the order and the content, as data — the one place. `TVEmbeddedPage`
  draws it: a non-scrolling `TVPageCollectionViewController` sized to its content (`isEmbedded`)
  *inside the hero's `ScrollView`*, so hero and sections stay one scroll and one focus graph — an
  independent scroll world is the thing banned above. It needs its own full-width `.focusSection()`,
  or Up from the right of a row can miss the hero. Two titled groups in one row are a `.strip`
  (`TVPageSection.groups`): one orthogonal section whose cell frames all come from
  `TVPageStripPlan`, group titles being non-focusable cells that dodge together and **stay on the
  page's side margin while any of their group is on screen** (`stickyShifts`: the *label* moves
  inside a group-wide cell — a cell that moved with it would be recycled once its frame left the
  screen, and the cell's own transform is the focus dodge). A strip can carry a heading of its own
  (`strip(id:title:groups:)`, *Similar*) with its groups' titles as subheadings
  (`TVPageGroup.isSubheading`); *Cast & Crew* is a heading over one untitled group of people. What each row says:
  [docs/product/detail-sections.md](../product/detail-sections.md). The SwiftUI sections it
  replaced are still there behind `FeatureFlags.tvDetailSections` (default on) until the page has
  been seen on a device — and are what iOS, iPadOS and macOS draw. **Being inside the hero's scroll view
  has a price:** to UIKit a SwiftUI button with focus *is* the scroll view's container
  (`HostingScrollView.PlatformGroupContainer`), an ancestor of every lockup on the page, and TVUIKit
  reads "the focused view is an ancestor" as "I am focused" — info cards need
  `TVCardView.releaseFocusedLook`, poster art `TVPosterArtFocus` (Troubleshooting). Home's page is
  the tab's root, with no such ancestor, which is why it never shows either.
- **Hero content is forced dark** (`.environment(\.colorScheme, .dark)` in `MediaItemHeroView`):
  tvOS follows the system appearance, and without the force light mode paints `Color.primary`
  black on dark artwork. Keep the scrim where the text is (bottom band, left edge); a stacked 0.92
  diagonal read as a black slab. What the hero does in light mode once the picture has faded is
  open — Asana: [Светлая тема на странице: текст hero](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219606561789181). (An older rule,
  "the scrim follows light/dark", contradicted this and was removed 2026-10-18.)
- **No page-wide hero state.** No fold flag, no wash, no chrome fade, no custom
  `ScrollTargetBehavior`. The focus engine scrolls the page. The one scroll the page asks for is
  back to the top when a hero control takes focus (`ScrollViewReader.scrollTo`), because the
  controls sit at the hero's bottom edge and the engine otherwise nudges the page to frame each
  one. The fold state it replaces changed one step after focus moved, so the snap worked from stale
  state, and every write re-ran the whole page body and every shelf under it.
- **The page body reads no focus.** Hero focus is observed inside `MediaItemHeroView`; the page
  passes the `@FocusState` binding down and reads nothing from it.
- **Lead with what can be played.** The cheapest path on a remote is `hero button → playable rail →
  everything else`. Episodes, parts and versions are a rail directly under the hero
  (trailers join it — not built yet, Asana: [Трейлеры как элементы playable rail](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219606504266557));
  the sections follow, in the order of [docs/product/detail-sections.md](../product/detail-sections.md).
  Ordering is by what the user can do now, not by entity type — a movie is not "the layout with the
  rail missing".
- **One playable rail *component*, not one section per content type.** Episode, trailer, part, version and extra
  share a shape (id, title, duration, image, source, progress, kind) and differ in one field, so
  they share a component. A trailer tile *is* an episode tile *is* a Continue Watching tile.
- Versions of one film (`subtype: multi`) are `PlaybackVariant`, never episodes — one rail each,
  never mixed. Why, and what the payload actually looks like: `PlaybackVariant.swift` and
  [docs/providers/kinopub/video.md](../providers/kinopub/video.md).
- Sections are data (kind + payload), empty ones simply absent, order defined in one place.
- "Related" renders through the same shelf component Home uses.
- 🔴 **A rule that depends on a title's type or genre lives in `MediaPresentationProfile`, never as
  an `if type == …` in a view** — written into one view it lands on the detail page and is missed on
  the poster, the card and the label beside it. *What* each kind shows is product, not architecture:
  [docs/product/media-presentation.md](../product/media-presentation.md).
