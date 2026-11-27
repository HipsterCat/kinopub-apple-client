# What's New entries

Add **one JSON file per visible change**. Do not edit
`../../whats-new.json` — that file is a frozen legacy archive.

## Filename

`YYYY-MM-DD-short-slug.json` — date plus a unique slug so parallel PRs never
collide. Example: `2026-11-26-actor-search.json`.

## Schema

```json
{
  "version": "1.0",
  "date": "2026-11-26",
  "ru": ["Короткий пользовательский пункт."],
  "en": ["Short user-facing bullet."]
}
```

- `version` — marketing version (usually `1.0`).
- `date` — ISO date; used for sort (newest first).
- `ru` / `en` — arrays; one bullet is fine. Several related bullets may share one file.
- Optional `id` — defaults to the filename stem when omitted.

The `WhatsNew` folder is an Xcode **folder reference**: new files under `entries/`
are bundled automatically — no `project.pbxproj` edit.
