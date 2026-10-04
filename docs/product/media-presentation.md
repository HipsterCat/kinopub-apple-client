# Media presentation — what type and genre change on screen

Implemented by `MediaPresentationProfile` (KinoPubBackend). Views ask the profile; the profile is
the only place these rules exist.

## Kinds

| Kind | What lands in it |
| --- | --- |
| `fiction` | `movie`, `serial`, `3d` — the default |
| `documentary` | type `documovie` / `docuserial`, or a documentary genre on any type |
| `concert` | type `concert` |
| `standup` | **genre 101** |
| `animation` | anime and cartoons (**genre 23**), any type |
| `show` | type `tvshow` |

**prd — The primary genre** (the one word shown — player, cards): **anime leads**, then
**animation** (*Мультфильм*); a title filed under both is anime first, the cartoon is the lesser
fact (user's call, 2026-10-04). Documentary leads by its type. `GenreVocabulary.primaryFirst`,
applied by the merge.

Type decides first, genre second. Genres are read in our vocabulary (`GenreVocabulary`,
KinoPubMedia), which holds kino.pub's whole id list; a name only decides for an id that list lacks.
`tvshow` implies the *TV Show* genre, `documovie`/`docuserial` *Documentary*, `concert` *Concert*.

## Rules

**prd — People.** Directors are a name people know and a face they do not.

- The cast rail is **actors only, and `fiction` only**. Directors are never a portrait, on any kind:
  they led that rail before, which spent the opening slot of the one section that exists because of
  faces.
- `documentary` / `concert` / `standup` / `animation` / `show`: no rail at all, and no "Starring"
  line in the hero. Their people are text.
- Everyone not on the rail is a **Credits** card in the information table, beside the qualities and
  the languages: an author row always, plus the cast for the kinds that get no rail.

**prd — Author.** kino.pub files a series' creators in the same `director` field.

- `serial` / `docuserial` / `tvshow` / `documovie` credit **creators**; everything else a
  **director**. The Credits row and the "More by…" shelf both say which.

**prd — The author shelf.**

- It covers the credited directors — **two at most, one request each**: a comma on `director`
  matches nothing (see [related-sections.md](related-sections.md)), so two names is two merged
  requests, and more than two is a crawl.
- Titled by role and count, with no name in it — with several credited people there is none to
  print: *More by This Director* · *More from These Directors* · *More by This Creator* ·
  *More from These Creators*.
- A shelf standing for several people has **no header link** — there is no one person page to open.
- `concert` and `standup` get no author shelf: that director is a TV credit nobody follows.

**prd — Person shelves, generally.** One card per film — the 3D and the flat entry of one title are
one card (`MediaItem.filmIdentity`). Picked by Kinopoisk rating, shown **newest first**, ties by
views: a rating is only as good as the crowd behind it and kino.pub does not guarantee a vote count.

**prd — One label per idea.** Whatever the author is called on a title, everything says the same
word: the hero's credit line, the Credits row and the shelf header. The hero read "Director" over a
page whose shelf said "More by This Creator".

## Not decided

- **Poster (vertical) and playable object (horizontal card).** No kind-specific rule yet; both take
  the fiction default. When one is decided it goes in the profile, not in the cell.
- **idea — the actor shelf still names the person** ("More with Крис Пратт") while the author shelf
  names the role. One of the two should move.
- **idea — voice actors.** `animation` could get its rail (and its cast shelf) back if we ever carry
  voice credits as such; kino.pub's flat `cast` string is not that.

## Verification

Everything above is **prd**: it builds on tvOS and iOS and the rules are unit-tested
(`MediaPresentationTests`), but nothing here has been watched on a device.
