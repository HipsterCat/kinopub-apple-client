# What's New

What the viewer sees after an update, and where the history lives.

## Sheet after an update

**prd** — After the app updates to a **new marketing version** that has bullets in
`whats-new.json`, show a What's New sheet once. Track the last-seen version. First
install of a version records it and does not prompt.

**prd** — Dismiss (Continue, or Menu on tvOS) records the running version so the sheet
does not return on the next launch.

**prd** — The sheet is the current version's bullets only. Skipped versions are not
played back here; the full list is Settings › About.

## Settings › About

**prd** — About shows the marketing version and the build number, then the full
history (newest first). tvOS: a What's New page of focusable rows, one bullet per
row. iOS / macOS: the same entries on the About screen.

## Copy

**prd** — Bullets are user-facing, short, and localized **ru first, then en**. No
implementation notes, no ticket numbers, no "fixed a crash in X".

The implementation log stays in [CHANGELOG.md](../../CHANGELOG.md). TestFlight
"What to Test" is the Russian bullets for the current marketing version.

## Source

`KinoPubAppleClient/Resources/whats-new.json` — one object per marketing version.
Agents add an entry (or bullets on the current version) when the change is visible
to a viewer. See AGENTS.md › Working agreement.
