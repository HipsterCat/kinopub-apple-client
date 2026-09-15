# CURRENT — active product policy (Kinopub Apple)

**Authority for agents and engineers.** If this file conflicts with `ROADMAP.md`, `CHANGELOG.md`, `docs/archive/**`, old PR descriptions, or code comments about iOS/macOS chrome — **this file wins**, until Sasha changes it.

Last updated: 2026-09-15 · Owner: archi (architecture) · Implementer: max (Cursor)

---

## One-sentence goal

Ship a **daily-driver Kinopub on tvOS 26+** using **standard Apple tvOS UI Kit** (Sketch), full basic product features, on the existing `kinopub-apple-client` pipes — not a research UI, not a multiplatform polish pass.

## Active platform

| Platform | Status |
| --- | --- |
| **tvOS 26+** (device floor includes Apple TV 4K 1st gen through **26.6**) | **Active — only** |
| iOS / iPadOS / macOS | **Postponed.** Do not expand surface area, do not chase parity tickets, do not “fix while here.” When resumed: **same layout grammar, adaptive** — not a second design system. |

Compiling for other destinations may still succeed; **do not spend MVP time** on their chrome, toolbars, or focus quirks unless Sasha explicitly unblocks.

## What we are building (MVP)

Full **basic** Kinopub, Sketch-simple:

- Watch Now (ship tab may still say Home — rename toward Sketch)
- Series / Movies — **identical shelf layout**, typed filter; **no Up Next** on those tabs
- Library, Search, categories/catalog, movie/show detail, playback, **context actions**
- **Posters first** in the UI reset; Up Next / Continue Watching landscape row **only on Watch Now**
- **No LIVE badge** (mock artifact — never ship)

## What we are not building (now)

- Clone-the-Apple-TV-app research, custom focus/parallax/scroll-scrub, custom player chrome → see `AGENTS.md` banned table (still law for *how* UI is built)
- Heroes / banner shelf / Top Shelf / light theme / advanced subtitles as MVP scope
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
