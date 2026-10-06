# Detail sections — what is under the hero

The part of the detail page that comes **after the hero and its buttons — never instead of them.**
Built on tvOS first (`MediaItemTVSections`); iOS, iPadOS and macOS keep their SwiftUI sections until
they get a pass of their own. The playable rails (versions, seasons, episodes, trailers) stay
directly under the hero and are not part of this order.

## Order

**prd — Sasha, 2026-10-06.** Top to bottom. A `|` is two titled groups side by side in **one row
that scrolls as one**:

| # | Row | What is in it |
| --- | --- | --- |
| 1 | Ratings \| Reviews | one card per rating source · review previews |
| 2 | Cast & Crew: Director \| Starring | person cards, the ones search draws, under one heading |
| 3 | Similar | Home's poster row, as it is built there |
| 4 | Stills \| Facts | a mosaic that opens the gallery · trivia cards |
| 5 | Type · Year · Countries · Genres | one chip group per axis, each under its own small title |
| 6 | Collections / selections | the other shelves, each a Home poster row |
| 7 | Video \| Audio \| Subtitles | three specification columns |

**prd — A section with nothing to say is absent.** Its row collapses and the next one moves up; a
row of two with one side empty is a row of one. Nothing is drawn as an empty box.

**prd — Cards, not tiles.** Ratings, reviews, facts, stills and the specification columns are
content of the HIG's *Card* — "a header, footer, and content view to present ratings and reviews for
media items" — so they lift, tilt and turn white under focus like every other platter on the page.
People are search's cards; shelves are Home's posters.

**prd — Close together (Sasha, 2026-10-06).** The air between cards of a row — scores, reviews,
people, facts — is **half** the HIG gutter (22 pt, not 44), and the air between two groups of a row
— Ratings and Reviews, Director and Starring — is half the titled-row gap (40 pt, not 80). Rows of
pills keep their wider group gap: the spacing inside a row of pills is already near the half.

**prd — A group's title does not leave without its group (Sasha, 2026-10-06).** Scroll a row
sideways and the title of the group still on screen — "Ratings" over scores that have begun to slide
under the page's side margin — stays on that margin, and goes only with the group's last card, the
next group's title taking its place. It does not slide off to the left with the first card.

## Rows

**prd — Ratings.** One card per source that has something to say — IMDb, Kinopoisk, TMDB, kino.pub —
holding the source's own mark, the number as the source prints it, and how many people stand behind
it. kino.pub's score is thumbs, so it shows how many of each. A source with too few votes says so
rather than printing a number.

**prd — Reviews.** The first ten, as previews: a headline (the author when there is none — about
half have no headline), as much of the text as fits, how it was meant, the date. **Select reads the
whole review** in the shared info popup, so a clipped card is its own way in.

**prd — Cast & Crew (Sasha, 2026-10-06).** One heading, *Cast & Crew*, and under it the
professions as **subheadings** — *Director*, *Starring* — set smaller than a row's title. Search's
person card for everyone. **Fiction only** — see [media-presentation.md](media-presentation.md):
every other kind has no faces on the page and its people become the *Credits* column of the
specifications.

- **No profession on a card.** The subheading says it; "Director" under a director and "Actor"
  under an actor said nothing. A card keeps what *is* news: the character (and, in a series, how
  many episodes), when TMDB has one.
- **One director stands beside the cast.** Director | Starring is one row. **Several directors are
  a row of their own, and the cast is the row under it** (at most three directors) — side by side
  they would push the cast off the screen. One heading over both.
- **The cast is ranked, and the insignificant are dropped.** A **series** ranks by how many of its
  episodes a person is in; a **film** by TMDB's billing order — the one measure of prominence its
  credits carry (the model has no popularity figure). kino.pub's own order breaks a tie and stands in
  for a title TMDB knows nothing about. In a series, anyone in fewer than a **fifth** of the episodes
  the most-seen person is in — and never fewer than two, once anyone has more than one — is a guest
  and is dropped. **No more than 12** in any case.

**prd — Similar.** The Home poster row: the same lockup, six across — **with no title or year
under a cover, not even on focus** (Sasha, 2026-10-06): Home's own caption, none, so there is no
footer in the lockup to give or take height from the art. The same goes for every other shelf on the
page, and **a shelf ends in its last cover — there is no *See all* tile** (Sasha, 2026-10-06: it named
itself on focus, and the footer that allowed gave the covers beside it a height of their own).

**prd — Stills.** A 3 × 2 mosaic — the first five stills and a chevron cell that says there is more —
that opens a full-screen gallery. Left and Right turn its pages; Menu closes it.

**prd — Facts.** Trivia cards. A spoiler is a card with a warning and a *Show* control, and turns
into the fact when selected; it never shows itself on its own.

**prd — Type · Year · Countries · Genres.** One chip group per axis under its own small title. A
chip opens search narrowed to it. A **type** wears an **SF Symbol** — a film strip for a film, a
television for a series — never an emoji (Sasha, 2026-10-06); a country keeps its flag and a genre
its emoji. An
unknown subtype still shows its raw word, and a multi-version film does not say *multi* (the
versions rail above already lists them).

**prd — Specifications.** Three columns, no platter at rest — they read as text on the page and take
the platter only under focus — and Select opens the whole column in the info popup.

- *Video:* runtime (a series' is one episode's), the best file's resolution with a 4K / HD / SD mark,
  and the two advisories kino.pub raises about a release.
- *Audio:* the languages in the viewer's order, a flag before each. The ones the viewer reads stay
  open with what dubs them; **the rest fold into "N more languages"**, which the popup lists in full.
  Dubs sit under their language: ✓ a studio dub (named), three heads a multi-voice, two a two-voice,
  one a single voice. A language with only the original track says *Original*.
- *Subtitles:* the same languages and flags; a boxed **CC** when the track's own name says so
  (kino.pub does not tell hard-of-hearing from translated, so nothing more is claimed) and *Forced*.
- *Credits:* only for a kind with no faces on the page; first, as text.

## Select, everywhere on the page

| On | Select does |
| --- | --- |
| a poster | opens the title |
| a person | opens their page |
| a chip | opens search narrowed to it |
| a review, a fact, a specification column | reads it whole in the info popup |
| a spoiler | shows it, in place |
| the stills | opens the gallery |
| the kino.pub rating | offers a vote (see below) |

## Not on the page, on tvOS

**prd — The *Debug* button.** The footer's dev tool (the metadata sources' raw log) is **not on
tvOS** (Sasha, 2026-10-06): a button on a remote is a focus stop under the last row for something
nobody on a sofa reads. Settings › Diagnostics has the network log. The footer is the line saying
where the title came from and when, and nothing a remote can select.

## Built as an interpretation — not decided

**idea — each of these is a reading of the list above, built so there was something to look at.
Sasha has not confirmed any of them.**

- **"Collections / Подборки" is every shelf that is not Similar:** the director's other work, the
  lead's, the collections this title is in, the genre floor — in the model's own order
  ([related-sections.md](related-sections.md)). A shelf is covers only. Its page of its own — all of a
  director's or a collection's titles — is no longer reachable from the shelf on tvOS (the *See all*
  tile was cut); a person's page still opens from the person's card in Cast & Crew.
- **The vote lives on the kino.pub rating card.** Select offers Like / Dislike, once — votes are
  one-shot. The legacy page had a separate control for it.
- **Awards follow the facts**, as more cards of the same kind in the Facts group — they only exist for
  a viewer with their own Kinopoisk key, and the page does not grow a row for them.
- **Chip order follows the written list** (Type, Year, Countries, Genres), not the mock's (Type,
  Genres, Year, Countries).
- **Person-less kinds get a Credits column** instead of faces, which also means a fourth column in
  the specifications row that scrolls in.
- **"Two rows when several directors" is read as two *rows*** — directors, then cast under them —
  not as the directors stacked in two lines inside their column.
- **"Popularity" is TMDB's billing order**, with 12 and a fifth of the episodes as the cut-offs; the
  numbers are mine.
- **The character stays** as a card's only line, since only the *profession* was to go.
- **The footer** (where the title came from and when) stays at the very bottom, as it was.

## Not built

- **A Trakt rating tile** — there is no source for it.
- **The darker band behind the specifications row** that the mock draws.
- **A series' own order.** Series take the same sections under their seasons rail; whether a series
  wants its own order (and where cast sits next to episodes) is not decided.

## Verification

Everything above is **prd** or **idea** as tagged and **seen only in the tvOS simulators** (27.2, and
26.5 — which showed a bug of its own in the poster shelves, see CHANGELOG) on a fixture title
(`-KINOPUBDetailFixture film`, full of every kind of row) — never on a device, never on a live
payload. Not looked at on a real Apple TV: how the strips feel under the remote, whether
the info cards are readable at couch distance.
