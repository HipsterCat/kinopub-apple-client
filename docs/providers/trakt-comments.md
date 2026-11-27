# Trakt comments

`GET /movies/:id/comments/likes` and `GET /shows/:id/comments/likes` return liked-first
comments for a title. `TraktSource` supplies the IMDb ID and Trakt client ID and asks for 50
comments. It keeps up to 20 after filtering spoilers and short comments and ranking the app
language first.

## Comment fields

- `id` is the comment ID and resolves to `https://trakt.tv/comments/<id>`.
- `parent_id` identifies the parent comment for a reply.
- `created_at` and `updated_at` are ISO 8601 timestamps. The card uses the posting date.
- `comment` is the prose. Markdown links can tag people with URLs on `app.trakt.tv/people/`.
- `gif` is the optional attachment with a `url` and an optional `slug`. The card renders prose.
- `spoiler` and `review` are boolean flags. The app filters out flagged spoilers and comments
  containing a `[spoiler]` tag. Eligibility otherwise comes from the comment text.
- `replies` and `likes` are counts, shown in the footer when positive.
- `language` is the optional language code, used for ordering.
- `user_rating` is the author's optional score on a 1–10 scale. `user_stats.rating` is the fallback.
  The card displays the score on a five-star scale and uses it for the sentiment tint.
- `user_stats.play_count` and `user_stats.completed_count` count plays and completions.
- `user` is the profile. The app takes the display name, falling back to the username for
  attribution in the sheet. [Profile schema](https://github.com/trakt/trakt-api/blob/966ddfc9008519da717db79e1040a2c55c0db653/projects/api/src/contracts/_internal/response/profileResponseSchema.ts)

Trakt provides emoji totals and distribution through a separate
`GET /comments/:id/reactions/summary` request. The card's reply and like counters come from the
title's comment list response.

[Comment schema](https://github.com/trakt/trakt-api/blob/966ddfc9008519da717db79e1040a2c55c0db653/projects/api/src/contracts/_internal/response/commentResponseSchema.ts) ·
[Reaction summary schema](https://github.com/trakt/trakt-api/blob/966ddfc9008519da717db79e1040a2c55c0db653/projects/api/src/contracts/_internal/response/reactionsResponseSchema.ts)

## Replies

`GET /comments/:id/replies` returns direct replies as an array of the comment records above.
The app sends the Trakt client ID and API version 2. It reads `id`, `comment`, `created_at`,
`spoiler`, and the author's display name or username. The sheet follows
`X-Pagination-Page-Count` to read the pages in provider order. It starts the request when a
review showing replies is opened. A flagged spoiler is represented by a spoiler label.

[Replies contract](https://github.com/trakt/trakt-api/blob/966ddfc9008519da717db79e1040a2c55c0db653/projects/api/src/contracts/comments/index.ts#L183) ·
[Pagination](https://github.com/trakt/trakt-api/blob/966ddfc9008519da717db79e1040a2c55c0db653/projects/developer/src/lib/guides/pagination.md)
