# CURRENT — active product policy (Kinopub Apple)

**Authority for agents and engineers.** If this file conflicts with `ROADMAP.md`, `CHANGELOG.md`, `docs/archive/**`, old PR descriptions, or code comments about iOS/macOS chrome — **this file wins**, until Sasha changes it.

Last updated: 2026-09-16 · Owner: archi (architecture) · Implementer: max (Cursor) · HIG grid + appearance realign

---

## One-sentence goal

Ship a **daily-driver Kinopub on tvOS 26+** using **standard Apple tvOS UI Kit** (Sketch + HIG grid law), full basic product features, on the existing `kinopub-apple-client` pipes — not a research UI, not a multiplatform polish pass.

## Active platform

| Platform | Status |
| --- | --- |
| **tvOS 26+** (device floor includes Apple TV 4K 1st gen through **26.6**) | **Active — only** |
| iOS / iPadOS / macOS | **Postponed.** Do not expand surface area, do not chase parity tickets, do not “fix while here.” When resumed: **same layout grammar, adaptive** — not a second design system. |

Compiling for other destinations may still succeed; **do not spend MVP time** on their chrome, toolbars, or focus quirks unless Sasha explicitly unblocks.

### “Adaptive” on tvOS

HIG: tvOS layouts do **not** auto-adapt per TV size — same interface on every display. Here **adaptive** means frames come from the **fixed HIG grid table + safe area** (`UICollectionViewFlowLayout` / `containerRelativeFrame`), not iOS size-class fluidity or ad-hoc percentages.

## What we are building (MVP)

Full **basic** Kinopub, Sketch-simple **where Sketch matches HIG**; Sketch that invents chrome is non-binding:

- Watch Now (ship tab may still say Home — rename toward Sketch)
- Series / Movies — **identical shelf layout**, typed filter; **no Up Next** on those tabs
- Library, Search, categories/catalog, movie/show detail, playback, **context actions**
- **Posters first** in the UI reset; Up Next / Continue Watching landscape row **only on Watch Now**
- **No LIVE badge** (mock artifact — never ship)

## Grid & chrome contract (law — blocks M1 if violated)

TVMLKit is deprecated; do **not** wait for Apple to republish every TVML template. Replacement stack:

1. HIG layout grid + safe area (below)
2. System lockups only — TVUIKit / SwiftUI `.borderless` | `.card` (see `AGENTS.md`)
3. WWDC24 shelf/search recipes for “how”
4. Sketch that isn’t (1)–(3) is **non-binding art**

### Safe area

Inset primary content **60 pt** top/bottom, **80 pt** sides. Section titles and the **first** card of a row align to that leading inset — same vertical line.

**Peek is not “insets none.”** Trailing (and leading when scrolled) may show a **partial next card** past the content box so the rail reads as scrollable. The page is **not** flush to the screen edge; removing the leading margin is a **regression**. Do not ignore the safe area to fake edge-to-edge chrome.

### Unfocused grid table — horizontal spacing **always 40 pt**; min vertical spacing **100 pt**

| Columns | Unfocused width (pt) |
| --- | --- |
| 2 | 860 |
| 3 | 560 |
| 4 | 410 |
| 5 | 320 |
| 6 | 260 |
| 7 | 217 |
| 8 | 184 |
| 9 | 160 |

**Any card width that isn’t in this table is a HIG break.** Extra vertical clearance for **titled** rows. Spacing must be **consistent**. Offscreen peek **symmetrical** left/right.

UIKit: column count from item width + spacing. SwiftUI: `containerRelativeFrame(.horizontal, count: N, spacing: 40)` + matching stack spacing; `scrollClipDisabled()` so focus scale isn’t clipped.

### Surface → recipe (MVP defaults)

| Surface / row | Aspect | Columns | Unfocused width | Notes |
| --- | --- | --- | --- | --- |
| Poster rails (Watch Now, Series, Movies) | 2:3 | **6** | **260** | Same recipe all three tabs. Alt **5 @ 320** only if Sasha picks density. |
| Up Next / stills (Watch Now only) | 16:9 | **4** | **410** | Progress on still; no LIVE. Alt **3 @ 560** for larger featured. |
| Library grid | TBD at M5 | — | — | Mock 4-col fits **landscape @ 410**. **2:3 posters → 5 or 6 col**, not 4. Decide before M5 impl; don’t mix silently. |
| Search results | 16:9 default | **4** | **410** | System search chrome only (below). |

### Search chrome

**System searchable / UIKit search only.** Sketch custom keyboard + suggestion-pill row is **non-binding** — do not build. Results use the grid table (default 4-col landscape @ 40 pt).

### Materials

System TabView / `sidebarAdaptable` / list materials only. No custom frosted pill stacks under Search/Settings. Heroes / full-bleed gradient catalogs stay **parked** (post-MVP).

### Focus acceptance (fundamentals — not polish)

1. Layout is a **grid of focusables** — no diagonal / irregular hit geometry.
2. Shelves: disable scroll clip so focused lockup can scale + shadow.
3. Headers / sidebars / filter rows: `focusSection` (or UIKit focus guides) so focus doesn’t jump to the tab bar from mid-shelf.
4. Captions clear the **focused (scaled)** image — prefer system lockups.
5. Assets sharp at **focused** size.
6. Empty/error states keep a focusable escape (don’t wait for M7).


## Appearance & type

- **System light/dark** — follow user preference. Forced dark-only was a **hero** tradeoff; heroes are parked, so dark-only is **rescinded** for MVP.
- **Dynamic Type** — system text styles; no `.system(size:)` except where AGENTS already allows glyph/geometry exceptions.

## Sketch source of truth

“Sketch” means **Apple Design Resources — tvOS UI Kit** (official Sketch library): named components and styles as Apple labeled them. Not informal wireframes. Product mocks that diverge from that kit + HIG grid are non-binding.

## Craft baseline

Repo `.agents/skills` (tvOS fundamentals) are **required reading** for implementers — same tier as AGENTS focus/TVUIKit rules. Do not reinvent clipped Lazy stacks that hide horizontal scroll.

## Shelf clipping (law)

Horizontal rails keep the **80 pt leading content inset** (headers + first poster aligned). They also show a **trailing peek** of the next offscreen item. Clipping so there is no peek (looks like a crooked static stack) **or** flushing the first card to the screen edge (insets none) are both **defects**. Disable scroll clipping as needed so focus scale and peek remain visible — without deleting the content margin.

## What we are not building (now)

- Clone-the-Apple-TV-app research, custom focus/parallax/scroll-scrub, custom player chrome → see `AGENTS.md` banned table (still law for *how* UI is built)
- Heroes / banner shelf / Top Shelf / light theme / advanced subtitles as MVP scope
- Custom search keyboard / Sketch glass approximations
- Invented card widths outside the HIG table
- Treating unchecked `ROADMAP.md` boxes as the sprint backlog
- Promoting `docs/archive/**` or despair-era experiments into requirements
- Copying Plozz / Parallax / Rivulet / silo code into product (technique only)
- Using `kinopub-lab` / KinoBook as the product shell

## Doc map (read in this order)

1. **`CURRENT.md`** (this file) — what is active
2. **`PLAYBOOK.md`** — how to execute milestones + agent rules
3. **`AGENTS.md`** — durable engineering law (focus, TVUIKit, one component, adapters). Still binding for *craft*; scope overrides live here in CURRENT
4. **`docs/product/*`** — accepted product rules for continue-watching, presentation, tracks, related (prd) — still valid unless CURRENT says otherwise
5. **`ROADMAP.md` / `CHANGELOG.md`** — **historical / inventory**. Useful evidence. **Not** automatic acceptance. Open checkboxes are candidates, not commitments
6. **`docs/archive/**`** — evidence of failures. Never law

## Naming

| Sketch / product | Code today (may lag) |
| --- | --- |
| Watch Now | Home tab |
| Series | Shows tab |
| Up Next (Watch Now row) | Continue Watching row — evolve presentation; Stage 7 `AVContentProposal` is **player** Up Next, separate |

## Sync / actions (intent)

One state-driven menu policy for every card (`ItemActionState` + single performer). Optimistic local truth; no refetch storms. Evolve `MediaCardContextMenus` + `MediaCardMenuCoordinator` — do not fork a second menu stack.

## Change control

Sasha’s explicit decision in chat overrides this file. Archi updates CURRENT/PLAYBOOK when policy moves. Implementers do not silently expand scope past the active milestone in PLAYBOOK.
