# Roadmap → Asana

**This file is no longer maintained.** Since 2026-10-18 every planned item, open question, finding
and follow-up lives in Asana, project
[Kinopub Engineering project plan](https://app.asana.com/1/1218266299921477/project/1219403693009374):
one task per feature or section, each item a subtask. Done work is a completed subtask with its PR
or commit; research findings and measured API facts go into the subtask's description.

**For agents (Claude, Cursor, Grok, anyone):** do not add checklists or "next" lists to any `.md`
file in this repo. New work, a defect you park, a decision you need — make it an Asana subtask
of the matching task below (Russian names, like the existing ones), or ask Sasha where it goes if
none fits. If you cannot reach Asana, say so in your reply and list the items there instead.

| Feature / section | Asana task |
| --- | --- |
| Title page (hero, sections, seasons, backdrop) | [Страница тайтла](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219606600371250) |
| Library | [Library](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219403704224202) |
| Search | [Search](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219403704224200) |
| Home rows | [Home page unlimited sections](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219403704224197) |
| Home banner | [Home page featured banners](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219403704224196) |
| Player | [Player](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219403704224201) |
| Player Up Next | [Player up next block](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219403704224199) |
| Skip intro / recap / credits, chapters | [Пропуск заставки, рекапа и титров](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219606490779079) |
| Live TV | [TV](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219604943618157) |
| kino.pub catalogue: collections, people, genres, filters | [Каталог kino.pub](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219606620916545) |
| Activation, Settings, app shell | [Вход, настройки и оболочка](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219606490759779) |
| External metadata, worker, `/v1/title`, recommendations | [Метаданные и обогащение](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219606561769807) |
| Caches, media model, `@Observable`, data-backbone | [Данные и архитектура](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219606600361125) |
| Atoms, TypeScale, accessibility, light theme | [Дизайн-система и доступность](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219606620915902) |
| Top Shelf | [Top Shelf](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219606504247784) |
| Tests and CI | [Тесты и CI](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219606490778977) |
| iOS / iPadOS / macOS | [iOS, iPadOS и macOS](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219606561782966) |
| Advanced subtitles | [Продвинутые субтитры](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219606620916480) |
| Skeletons | [Skeletons](https://app.asana.com/1/1218266299921477/project/1219403693009374/task/1219403704224198) |

**Decided behavior** stays in [docs/product/](docs/product/), durable engineering rules in
[AGENTS.md](AGENTS.md), what is active in [CURRENT.md](CURRENT.md), shipped facts in
[CHANGELOG.md](CHANGELOG.md).

The old staged roadmap (stages 1–8, with every ticked box) is in git history: `git show
08e1090e:ROADMAP.md`. Every open box in it was checked against the code on 2026-10-18 and moved to
the tasks above; the ones already done were filed as completed subtasks.
