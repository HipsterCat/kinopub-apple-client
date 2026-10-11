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
| 1 | Ratings | one card per rating source, and a card that counts the reviews |
| 2 | Cast & Crew | one row of person cards, the ones search draws, the role under each name |
| 3 | Similar: same actors \| this director \| by genre | one heading over up to three groups of ten Home posters, under subheadings |
| 4 | Stills \| Facts | a mosaic that opens the gallery · trivia cards |
| 5 | Collections | one Home poster row per collection this title is in |
| 6 | Audio & Subtitles \| Video \| Information | three columns at most, filling the width |
| 7 | Creators \| Cast | a kind with no faces only (anime, cartoons, a concert…): text, no heading |

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

**prd — Ratings (Sasha, 2026-10-11).** One card per source that has something to say — IMDb,
Kinopoisk, TMDB, kino.pub — kept small: **the source's mark before the number**, 16 pt apart, on one
line, and how many people stand behind it under them. The number is title2, rounded, medium; the
count is caption2, regular. No source's name is written beside its mark. The card is as tall as
those two lines (168 pt at the default text size), not as tall as a review's card (276), and sits
at the top of the row beside it. kino.pub's score is thumbs, so under its percentage it shows how
many of each. A source with voters but no score yet (Kinopoisk's «недостаточно оценок») prints a
**dash in secondary ink in place of the number** and still writes how many voted — it does not say
"not enough ratings".

**prd — Reviews, counted (Sasha, 2026-10-11).** The reviews' own words are **not on the detail
page**. The last card of the scores' row — **the same height and style as a score**, a little wider
because it carries two things — says how many there are and how they were meant: the speech bubbles
before the total (a score's mark before its number), the title «Отзывы» under them, and on the right
a face and a count for each tone — **green smiling** (positive), **red frowning** (negative), **grey
straight-mouthed** (neutral). The total is the source's (the proxy pages its reviews, so it is more
than the page carries), the tones are from its summary or, with none, tallied from the reviews we
hold; nothing to count, no card. **Select opens a page of their own**: the review cards, three
across, under the same count in the header, and Select on one reads it whole in the shared info
popup. A card there is what the row used to hold: a headline (the author when there is none — about
half have no headline), as much of the text as fits, how it was meant, the date.

**prd — Cast & Crew (Sasha, 2026-10-06; one row since 2026-10-11).** One heading, *Cast & Crew*, over
**one row of people with no sections inside it**. Search's person card for everyone; **what each is to
the title is the card's own subtitle** — the character (and, in a series, how many episodes) for an
actor, when TMDB has one; «Режиссёр» for a director; «Создатель» for a show's creator. **Fiction
only** — see [media-presentation.md](media-presentation.md): every other kind has no faces on the
page and its people are a section of their own, as text (below).

- **A film's director opens the row, then the cast.** Several directors (at most three) are still in
  the one row — never a row of their own.
- **A show's creators close the row, behind the actors**, however many there are (Sasha,
  2026-10-11: «чересчур» as a row of their own).
- **The cast is ranked, and the insignificant are dropped.** A **series** ranks by how many of its
  episodes a person is in; a **film** by TMDB's billing order — the one measure of prominence its
  credits carry (the model has no popularity figure). kino.pub's own order breaks a tie and stands in
  for a title TMDB knows nothing about. In a series, anyone in fewer than a **fifth** of the episodes
  the most-seen person is in — and never fewer than two, once anyone has more than one — is a guest
  and is dropped. **No more than 12** in any case.
- **Except the first of kino.pub's own list, who is never dropped** (Sasha, 2026-10-11): that is the
  lead. A name TMDB could not match has no episode count and was sent away as a guest — the title's
  own lead among them. If ranking would leave them out they open the row.
- **A person without a photo is their initials**, as in search. A fixture page draws no
  network portraits (`-KINOPUBFixtureRealArt YES` brings them back), so the no-photo state is what a
  fixture shows.

**prd — Similar (Sasha, 2026-10-11).** One heading, *Similar*, over **up to three groups** of
posters in one row that scrolls as one, each under a subheading in a smaller type than the row's
title, **in this order**:

1. **«Эти же актёры»** — what else the lead is in. A concert or a stand-up set keeps its role-worded
   shelf title («Ещё от комика»): its people do not star.
2. **«От этого режиссёра»** — what else the director made («От этих режиссёров», and for a series
   «От этого создателя»). No name in either: the group says the role, the title page the person.
3. **By genre** — titled by the title's own genres in a sentence («Фантастика, боевики,
   приключения»). kino.pub's *similar* shelf; when there is none, the genre floor stands in
   ([related-sections.md](related-sections.md)).

**Ten covers at most in a group.** A title is shown once, under the first group that has it, and
each group takes its ten from what the groups before it left — a long shelf never starves the next.
A group whose shelf came back empty is absent, and so is the row when none is left; one whose query
is still in flight holds its place as six skeleton covers under its own words, so the row does not
jump.

The covers are Home's poster: the same lockup, six across, the HIG gutter (44 pt) between any two —
inside a group and from one group to the next, the subheadings do the telling-apart — **with no
title or year under a cover, not even on focus** (Sasha, 2026-10-06): Home's own caption, none, so
there is no footer in the lockup to give or take height from the art. **A group ends in its last
cover — there is no *See all* tile** (Sasha, 2026-10-06: it named itself on focus, and the footer
that allowed gave the covers beside it a height of their own). A group's subheading stays on the
page's side margin while any of its covers is on screen and leaves with the last (the strip rule
above).

**prd — One nesting, one look (Sasha, 2026-10-11).** A heading, its subheading and the stack under
it are spaced the same in every strip that has them — Similar's posters, Ratings and Reviews, the
table — **at rest and under focus**. At rest the subheading's line and where the stack begins are one
geometry whatever the stack is made of; under focus every subheading lifts by one amount
(`TVPageLayout.stripTitleLift`, the wide card's), never by the focused card's own growth — a poster
grows more than a person's card, and titles that followed it moved 19 pt over a row of posters and
11 over a row of people, so two rows built alike read differently.

**prd — Stills (Sasha, 2026-10-11).** A grid of **up to six** stills that **adapts to how many there
are** rather than a fixed 3 × 2: one still is the whole card, two stand side by side, three are two
over one wide, four two by two, five three over two wide, six three over three — the split that gives
a still the shape closest to its own 16:9, a short last row widened to fill it, edge to edge under the
card's rounded corners. There is no chevron cell: Select opens a full-screen gallery. Left and Right
turn its pages; Menu closes it.

**prd — Facts (Sasha, 2026-10-11).** Trivia cards, **the words body, regular, from the top of the card** — not
centred in it — and **facts without a spoiler first, the spoilers after them**. A spoiler is a card
with a warning — a quiet warning glyph (secondary, caption size) over its words — and **no *Show*
label**: the card is the control, and turns into the fact when selected; it never shows itself on its
own. A fact keeps the id of its place in kino.pub's list, so a revealed one stays revealed wherever
it now stands.

**prd — The table (Sasha, 2026-10-11).** The strip of type, year, country and genre pills is gone;
its words are in the table's third column. **Three columns at most, always, a gutter (44 pt) apart —
twice the air two cards of a row have — and sharing the width equally**, so they fill the page edge
to edge. **Every column is a stack of cards, one to an item**, so the table is never one focus stop
taller than the screen. **Borderless**: no platter, no white — at rest it is text on the page, and
**only an item that does something on Select can take focus**: Audio, Subtitles and the cast's *Expand*. A
type, a year, a resolution, a runtime are text and are skipped by the remote. Under focus a quiet
translucent plate comes up behind the words, which do not move, and the secondary ones go primary.
(Audio and Subtitles stay focusable even when nothing is folded away — a page whose bottom holds
nothing focusable cannot be scrolled to.)

**Every label is body, regular**; captions and the Audio / Subtitles headers are secondary, values
primary. **Words wrap onto as many lines as they need and are never cut** — genres, countries, a
dub's studios, the cast; they break between one another and never inside one. **No emoji and no
flags**: not on a genre, a country or a language.

**The air:** between **blocks** (Audio, Subtitles) the air is the card's own padding plus 12 pt — 68
pt text to text; between **items** that are only read (type, year, runtime, resolution…) it is **half
that**, 34 pt.

1. **Audio and Subtitles** — two blocks with a quiet header each. **Audio:** the languages in the
   viewer's order, no flag; the ones the viewer reads stay open with their dubs under them, **the
   rest fold into «+ ещё 7» / "+ 7 more"** — two words and no chevron. A dub is a line of words, no
   icon: its kind, then **every studio** that voiced it («Дубляж: Мосфильм», «Многоголосый: Кубик в
   Кубе, Пифагор»); a language with only the original track says *Original*. **Subtitles are one
   line**, the languages **two spaces apart**, a track marked hard-of-hearing or forced saying so in
   brackets («English (CC)»), then «+ ещё N» when more are folded. Select reads every one in the info
   popup. **A title that reports no audio says «Нет данных», no subtitles «Нет субтитров».**
2. **Video** — no header. The best file's resolution with a 4K / HD / SD mark, then the runtime (a
   series' is one episode's, with the whole run's in a card of its own), **then, for a series, how
   many seasons and episodes it has — under the duration, in the same column** — then the two
   advisories kino.pub raises about a release.
3. **Information** — no header. Type (and subtype), year, genres, countries — **the label is
   singular for one and plural for several** («Жанр» / «Жанры», «Страна» / «Страны»). A **series**
   has a status, and **the years it aired in place of a year**: «с 2026» while it airs, «с 2019 по
   2026» once it has ended, the one year when it began and ended in it. A multi-version film does not
   say *multi* (the versions rail above already lists them).

**prd — Cast & Crew as text (Sasha, 2026-10-11).** A kind with no faces (anime, cartoons, a concert,
stand-up, documentary, a show) has its people as text **under the table with the audio and the
subtitles — the last thing on the page — and with no heading**: not near the top where the portraits
are. **Three columns — whoever made it first, the cast second, the third not used yet** (its width
stays empty), each a card. The cast card shows the first six names, every one whole. **Under it there
is always a link — «Развернуть» / "Expand" — a drill-in that opens everyone kino.pub lists**, in the
info popup, a row to a name; it is the one focus stop in the section, and it is there however short
the cast. The cards of words are only read: they take no focus.

## Select, everywhere on the page

| On | Select does |
| --- | --- |
| a poster | opens the title |
| a person | opens their page |
| the count of reviews | opens the page of reviews |
| a review (on that page), a fact, Audio, Subtitles, the cast's *Expand* | reads it whole in the info popup |
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

- **"Collections / Подборки" is every shelf that Similar did not take in** — the collections this
  title is in, in the model's own order ([related-sections.md](related-sections.md)). A shelf is
  covers only. Its page of its own — all of a collection's titles — is no longer reachable from the
  shelf on tvOS (the *See all* tile was cut); a person's page still opens from the person's card in
  Cast & Crew.
- **Similar's groups are not capped.** The first can hold a screenful and more, and Right through
  all of it is the way to the lead's and the director's. Whether each group wants a limit (six, a
  screen) is not decided.
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
