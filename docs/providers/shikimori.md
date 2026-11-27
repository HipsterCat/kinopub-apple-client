# Shikimori

**Status: OAuth prepared, not live.** Piratic will use Shikimori for the viewer’s
`user_rates` (watch progress / scores on anime). Public catalogue reads should prefer
**GraphQL** over REST v1/v2 when we add them.

**Auth:** OAuth2. Application name **Piratic** must be sent as `User-Agent` on every
request (including token exchange). Mimicking a browser gets the IP banned.
**Redirect URI:** `piratic://shikimori`
**Scopes:** at least `user_rates` for create / update / delete.
**Rate limits:** 5 rps / 90 rpm.
**Integration kind:** user (viewer’s account). System Client ID + Client Secret.

## Credential names (values never in git)

| Name | Where the value lives |
| --- | --- |
| `SHIKIMORI_CLIENT_ID` | Info.plist `ShikimoriClientID` = `$(SHIKIMORI_CLIENT_ID)`, or process / CI env |
| `SHIKIMORI_CLIENT_SECRET` | CI env, Keychain, or worker secret only — **never Info.plist, never committed xcconfig** |

Code constants: `ShikimoriOAuth` in `PiraticMetadata`.

## OAuth flow (prepared)

1. `GET https://shikimori.one/oauth/authorize?client_id=…&redirect_uri=piratic://shikimori&response_type=code&scope=user_rates`
2. Exchange at `POST https://shikimori.one/oauth/token` with `User-Agent: Piratic`
3. Refresh with `grant_type=refresh_token` (access tokens expire in ~1 day)

## GraphQL (preferred for reads)

`POST https://shikimori.one/api/graphql`  
Headers: `User-Agent: Piratic`, `Authorization: Bearer …`, `Content-Type: application/json`

Starter query for the current user’s rates (see `ShikimoriOAuth.userRatesGraphQLQuery`):

```graphql
query UserRates($page: Int, $limit: Int) {
  userRates(page: $page, limit: $limit) {
    id score status episodes rewatches targetId targetType
  }
}
```

REST `GET/POST/PATCH/DELETE /api/v2/user_rates` remains available for writes when GraphQL
mutations are not enough; prefer GraphQL for catalogue and list reads.

## Endpoints (inventory — not all wired)

| Surface | Use |
| --- | --- |
| GraphQL `userRates` | Read the viewer’s rates |
| `POST /api/v2/user_rates` | Create a rate (`user_rates` scope) |
| `PATCH /api/v2/user_rates/:id` | Update |
| `DELETE /api/v2/user_rates/:id` | Destroy |
| `POST /api/v2/user_rates/:id/increment` | +1 episode |
| GraphQL anime/manga | Catalogue / posters (new poster fields are GraphQL-only) |

## Code

- `Packages/PiraticMetadata/.../Shikimori/ShikimoriOAuth.swift` — URLs, User-Agent, credential names, redirect, GraphQL starter
- Settings › Integrations › Shikimori — listed as coming soon
- App URL scheme `piratic` absorbs `piratic://shikimori` (token exchange TBD)
