# MyAnimeList (official API v2)

**Status: integrated for public anime ratings.** Account OAuth (list sync) is prepared via
`piratic://myanimelist` but not wired for sign-in yet.

**Auth (public reads):** `X-MAL-CLIENT-ID: <Client ID>` on every request. No user token.
**Auth (user lists / writes):** OAuth2 + PKCE; redirect URI `piratic://myanimelist`.
**Quota:** undocumented soft limits; treat politely. Cache answers **12–24h** (app uses **18h**).
**Coverage:** anime (and manga via separate endpoints — we do not call manga today).
**Ids accepted:** MAL anime id. Search by title when only kino.pub / IMDb identity is known.
**Integration kind:** system Client ID in the app (same class as Trakt’s public Client ID).
**Credential storage:** Info.plist key `MALClientID` = `$(MAL_CLIENT_ID)` and/or process env
`MAL_CLIENT_ID`. **Never commit the value.**

## Why it earns a slot

Trakt relays `mal.rating` / `mal.votes` on `/ratings?extended=all`, but those counts lag the
site (see research on Yani Neko). The official `mean` + `num_scoring_users` keep the title
page’s MyAnimeList chip fresh.

## Endpoints we call

| Request | Returns | We take | We skip |
| --- | --- | --- | --- |
| `GET /v2/anime?q=…&limit=8&fields=id,title,alternative_titles,start_date,start_season,media_type` | Search hits | Best year / title match → id | Everything else |
| `GET /v2/anime/{id}?fields=mean,rank,popularity,num_scoring_users,statistics,…` | One anime | `mean`, `rank`, `popularity`, `num_scoring_users`, `statistics` | Pictures, related, studios, synopsis (other sources cover them) |

Id hints also come from Wikidata `P4086` and Trakt’s `mal.link` when the parallel search
missed.

## Models (fields we asked for)

| Field | Shape | Note |
| --- | --- | --- |
| `mean` | number | Average user score 0…10 |
| `rank` | integer / null | Score ranking position |
| `popularity` | integer / null | Popularity ranking position |
| `num_scoring_users` | integer | Vote count for the mean |
| `statistics.status.*` | int or string | `watching`, `completed`, `on_hold`, `dropped`, `plan_to_watch` |
| `statistics.num_list_users` | integer | List membership total |

Mapped into `ExternalRating(kind: .myAnimeList)` and `MyAnimeListStats` on `TitleMetadata`.
Merge prefers the MyAnimeList score with the higher vote count (official over Trakt-relayed).

## OAuth (later)

Authorization: `https://myanimelist.net/v1/oauth2/authorize`  
Token: `https://myanimelist.net/v1/oauth2/token`  
Redirect: `piratic://myanimelist`  
Client ID via the same `MAL_CLIENT_ID` name; never commit a Client Secret (MAL’s public
clients are often PKCE-only).

## Code

- `Packages/PiraticMetadata/.../MyAnimeList/MyAnimeListSource.swift`
- `MyAnimeListCredentials.swift` — name-only resolution
- Settings › Integrations › MyAnimeList — ratings toggle when a Client ID is present
