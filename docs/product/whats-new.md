# What's New

What the viewer sees after an update, and where the history lives. Reference: Rivulet's
popup and About (Sasha, 2026-10-16: "все устраивает").

## Popup after an update

**prd** — The first launch of a build with notes this device has not shown yet presents
What's New once, signed in, over the app: title, «Версия 1.0 • Сборка 10», the new
bullets, and **Done**. The marketing version stays 1.0 across TestFlight builds, so the
gate is per bullet, not per version: any bullet in the catalog that this device has
not shown is new; a reworded one counts as new. A fresh install records everything as
seen and stays quiet.

**prd** — Done (Select) or Menu records every bullet as seen. On tvOS Done holds the
focus and is the only stop; Up / Down page the text.

**prd** — Drawn in the shared info popup (`InfoPopupView`): one panel over a dimmed
screen, hugging short text, scrolling long text with the edges faded — not a tvOS sheet,
which framed it in a second platter.

## Settings › About

**prd** — Rows: **Version** «1.0 (10)» — read-only, not a focus stop on tvOS — then
**What's New** (every version's bullets, newest first) and **Licenses** (the linked
open-source packages, their copyright lines and the MIT text), both in the same popup.
Menu closes it. iOS / macOS: the same three rows, with the data-source attribution
under them.

**prd** — The left panel on tvOS is the app plate, name and «Версия · Сборка», nothing
longer: TVSettingKit shrinks a long description to fit, and the notes under the plate
were unreadable (Sasha, 2026-10-16).

## Copy

**prd** — Bullets are user-facing, short, and localized **ru first, then en**. No
implementation notes, no ticket numbers, no "fixed a crash in X". A new bullet goes in a
**new file** under `entries/` (see Source); within that file, newest text first.

The implementation log stays in [CHANGELOG.md](../../CHANGELOG.md). TestFlight
"What to Test" is the Russian bullets for the current marketing version (fragments
first, then the legacy archive).

## Source

Hybrid catalog (Sasha, 2026-11-26):

| Path | Role |
| --- | --- |
| `KinoPubAppleClient/Resources/WhatsNew/entries/<id>.json` | **New bullets.** One file per PR / visible change. Filename `YYYY-MM-DD-short-slug.json`. |
| `KinoPubAppleClient/Resources/whats-new.json` | **Frozen legacy archive.** Do not add new bullets here. |

`AppChangelog.load` merges both: entry files sort by date (then id), newest first, and
prepend onto their marketing-version group. `WhatsNew` is an Xcode **folder reference**,
so new files under `entries/` need no `project.pbxproj` edit. Schema and an example live
in `entries/README.md`. Agents: see AGENTS.md › Working agreement. Licences:
`OpenSourceLicenses.swift` — a package added to `Package.resolved` gets a line there.
