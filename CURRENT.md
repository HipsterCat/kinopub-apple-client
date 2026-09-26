# CURRENT — active product policy (Kinopub Apple)

**Authority for agents and engineers.** If this file conflicts with `ROADMAP.md`, `CHANGELOG.md`, `docs/archive/**`, old PR descriptions, or code comments about iOS/macOS chrome — **this file wins**, until Sasha changes it.

Last updated: 2026-09-26 · Owner: archi (architecture) · Implementer: max (Cursor) · Adaptive layout + Dynamic Type (HIG table = density examples)

---

## One-sentence goal

Ship a **daily-driver Kinopub on tvOS 26+** using **standard Apple tvOS UI** (Sketch + HIG as orientation, not fixed-canvas religion), full basic product features, on the existing `kinopub-apple-client` pipes — not a research UI, not a multiplatform polish pass.

## Active platform

| Platform | Status |
| --- | --- |
| **tvOS 26+** (device floor includes Apple TV 4K 1st gen through **26.6**) | **Active — only** |
| iOS / iPadOS / macOS | **Postponed.** Do not expand surface area, do not chase parity tickets, do not “fix while here.” When resumed: **same layout grammar, adaptive** — not a second design system. |

Compiling for other destinations may still succeed; **do not spend MVP time** on their chrome, toolbars, or focus quirks unless Sasha explicitly unblocks.

### Adaptive layout (all devices)

Layout comes from **container bounds + `safeAreaInsets` (overscan; top / bottom / leading / trailing can vary) + Dynamic Type** — not from `UIScreen`, a hardcoded 1920 canvas, or fixed cell frames.

- Prefer **preferred item size** (aspect + density class) and let column count follow available width.
- Do **not** hardcode column counts or cell sizes as if every display were one Sketch artboard.
- HIG grid numbers (6 @ 260, 4 @ 410, 80 pt sides, ~40 pt gutters, …) are **density examples** from Apple’s tvOS layout tables — useful to check against, **not** acceptance law that every surface must pin forever.
- When iOS / macOS unfreeze: **same adaptive contract**, not a second design system.

tvOS does not get iOS size-class fluidity; “adaptive” here still means **measure the container you have**, not invent a second product language.

## What we are building (MVP)

Full **basic** Kinopub, Sketch-simple **where Sketch matches system / HIG**; Sketch that invents chrome is non-binding:

- Watch Now (ship tab may still say Home — rename toward Sketch)
- Series / Movies — **identical shelf layout**, typed filter; **no Up Next** on those tabs
- Library, Search, categories/catalog, movie/show detail, playback, **context actions**
- **Posters first** in the UI reset; Up Next / Continue Watching landscape row **only on Watch Now**
- **No LIVE badge** (mock artifact — never ship)

## Grid & chrome contract

TVMLKit is deprecated; do **not** wait for Apple to republish every TVML template. Replacement stack:

1. Adaptive layout + safe area + Dynamic Type (above)
2. System lockups only — TVUIKit / SwiftUI `.borderless` | `.card` (see `AGENTS.md`)
3. System apps as orientation: **TV, App Store, Podcasts, Music, TestFlight, Fitness** (technique from research forks only — no product clone)
4. Sketch that isn’t (1)–(3) is **non-binding art**

### Safe area

Inset primary content from the **safe area / overscan**, not a second magic canvas. HIG’s **~60 pt** top/bottom and **~80 pt** sides are **starting examples** — match the container’s insets; do not double-apply SwiftUI 80 on top of UIKit’s already-adjusted content inset.

**Peek is not “insets none.”** Trailing (and leading when scrolled) may show a **partial next card** past the content box so the rail reads as scrollable. The page is **not** flush to the screen edge; removing the leading margin is a **regression**. Do not ignore the safe area to fake edge-to-edge chrome.

### HIG density examples (not a frozen recipe)

Unfocused widths Apple lists for a full-width 1920 reference with ~40–44 pt gutters (examples):

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

Use these as **density references**. Prefer measuring preferred card size and deriving how many fit. Do **not** invent random widths without a preferred-size rationale. Do **not** treat “any width not in this table” as an automatic merge blocker when the layout still tracks container + Dynamic Type.

Vertical rhythm between titled rows: HIG mentions ~100; product currently uses **~80** (Sasha 2026-09) — keep consistent within a page; do not invent a third number per shelf.

### Surface → recipe (MVP defaults to measure against)

| Surface / row | Aspect | Density class (example) | Notes |
| --- | --- | --- | --- |
| Poster rails (Watch Now, Series, Movies) | 2:3 | ~6-col poster class on full width | Same recipe all three tabs. Columns follow container + preferred poster size. |
| Up Next / stills (Watch Now only) | 16:9 | ~4-col still class on full width | Progress on still; no LIVE. |
| Library grid | TBD at M5 | — | Prefer preferred aspect + adaptive columns; don’t mix poster and landscape recipes silently. |
| Search results | posters / stills as product chooses | adaptive grid | **System UIKit search chrome only** (below). |

### Search chrome (tvOS)

**System UIKit search only** (`UISearchContainerViewController` / `UISearchController` path). Sketch custom keyboard + suggestion-pill row is **non-binding** — do not build.

SwiftUI `.searchable` is fine for **iOS / macOS** (and as a temporary tvOS fallback behind a flag). It is **not** tvOS MVP law — that API is the Mac/phone-era path.

### Materials

System TabView / `sidebarAdaptable` / list materials only. No custom frosted pill stacks under Search/Settings. Heroes / full-bleed gradient catalogs stay **parked** (post-MVP).

### Focus acceptance (fundamentals — not polish)

1. Layout is a **grid of focusables** — no diagonal / irregular hit geometry.
2. Shelves: disable scroll clip so focused lockup can scale + shadow.
3. Headers / sidebars / filter rows: `focusSection` (or UIKit focus guides) so focus doesn’t jump to the tab bar from mid-shelf.
4. Captions clear the **focused (scaled)** image — prefer system lockups.
5. Assets sharp at **focused** size.
6. Empty/error states keep a focusable escape (don’t wait for M7).

### UIKit vs SwiftUI (performance — soft guidance)

- **Large / repeating media** (page of shelves, result grids, long collections): **UIKit preferred** (`UICollectionView` / TVUIKit lockups). Measure before expanding SwiftUI Lazy stacks.
- **Small chrome** (buttons, `Menu`, filter chips, alerts, one-off labels): **SwiftUI is fine**.
- Do **not** freeze a mandatory “section architecture” vocabulary in this file. Follow Apple’s system patterns; revisit shelf implementation with archi when perf says so — not as silent dogma.

## Appearance & type

- **System light/dark** — follow user preference. Forced dark-only was a **hero** tradeoff; heroes are parked, so dark-only is **rescinded** for MVP. Do not apply `.preferredColorScheme` on the tvOS shell (even `nil` pinned Dark). `simctl ui appearance` is unsupported on current tvOS runtimes; DEBUG `-KINOPUBForceColorScheme light|dark` is the shot harness. Tab labels: **Watch Now** / **Series**, never Home / Shows.
- **Dynamic Type** — system text styles everywhere practical; UIKit labels use `adjustsFontForContentSizeCategory = true`; cells / rows **self-size / fit content**. No `.system(size:)` except where AGENTS already allows glyph/geometry exceptions. Larger text must grow captions and headers without clipping into a hardcoded cell frame.

## Sketch source of truth

“Sketch” means **Apple Design Resources — tvOS UI Kit** (official Sketch library): named components and styles as Apple labeled them. Not informal wireframes. Product mocks that diverge from that kit + system patterns are non-binding.

## Craft baseline

Repo `.agents/skills` (tvOS fundamentals) are **required reading** for implementers — same tier as AGENTS focus/TVUIKit rules. Do not reinvent clipped Lazy stacks that hide horizontal scroll.


## Shelf chrome (current default — subject to perf revisit)

- Today many shelves still use SwiftUI `Section(title) { rail }`. That remains an acceptable **current** approach; it is **not** forever-law. Expanding SwiftUI rail surface without measuring cost on 4K 1st gen is discouraged. A UIKit page / collection model is a valid direction when max + archi agree after measurement.
- **Section titles are leading**, aligned to the **content inset / safe area** with the first card — same vertical line. Do **not** fake leading with a 1920-wide screen-coordinate canvas. Never ship the centered-by-default Section header on tvOS without pinning leading.
- **Row header type** on tvOS: Sketch `Headers/Section Header/Dark/Secondary/1 Line` → `TypeScale.rowHeader` = **`.headline.weight(.semibold)`** + `.foregroundStyle(.secondary)`. Sasha: semibold, not `.headline.bold()`. Not `.title2` (~57pt). Not Primary / Subtitle / Eyebrow / App Icon / Pill.
- **Caption under poster** must clear the **focused (scaled)** lockup. Focused caption colour is **`UIColor.label`** (primary); unfocused stays secondary / hidden.
- Poster **density** on full-width TVUIKit shelves starts from the ~6-col / ~260 class as a **preferred size**, then adapts with container width — do not divide a sidebar pane into six columns blindly.

## Shelf clipping (law)

Horizontal rails keep a **leading content inset** from the safe area (headers + first poster aligned). They also show a **trailing peek** of the next offscreen item. Clipping so there is no peek (looks like a crooked static stack) **or** flushing the first card to the screen edge (insets none) are both **defects**. Disable scroll clipping as needed so focus scale and peek remain visible — without deleting the content margin.

## What we are not building (now)

- Clone-the-Apple-TV-app research, custom focus/parallax/scroll-scrub, custom player chrome → see `AGENTS.md` banned table (still law for *how* UI is built)
- Heroes / banner shelf / Top Shelf / light theme / advanced subtitles as MVP scope
- Custom search keyboard / Sketch glass approximations
- Hardcoded canvas (1920) / fixed column counts that ignore container bounds and Dynamic Type
- Treating unchecked `ROADMAP.md` boxes as the sprint backlog
- Promoting `docs/archive/**` or despair-era experiments into requirements
- Copying Plozz / Parallax / Rivulet / silo code into product (technique only)
- Using `kinopub-lab` / KinoBook as the product shell
- Turning AX dumps / old notes into new mandatory vocabulary without Sasha sign-off

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

**Archi reviews at merge-ready only** — not every UI/design iterate. Mid-PR visual work is max ↔ hig (see PLAYBOOK).
