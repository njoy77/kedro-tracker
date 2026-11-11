# @kedro/api

Bun + Hono API for the Kedro iOS app. Request and response types live in
`packages/shared/src/api.ts` (the contract the Swift client in `apps/ios/Kedro/Core/Networking`
mirrors); game rules (scoring, the op-log fold, stats, Elo) live in `packages/shared` too.

```sh
bun run --filter '@kedro/api' dev        # watch mode on :8787
bun run --filter '@kedro/api' test       # bun test (in-memory store, no network)
bun run --filter '@kedro/api' typecheck
KEDRO_DEV_AUTH=1 bun run --filter '@kedro/api' dev   # no Supabase: memory store, "Bearer dev:<uuid>"
```

## Testing against real data (local)

```sh
bun run env:pull                                  # once: writes apps/api/.env.local
bun run --filter '@kedro/api' dev:seed            # :8787, seeded from the web app
```

`dev:seed` runs the in-memory store with dev auth and, at startup, reads the web app's
`kedro_kv` rows **read-only** (anon key), imports them with the legacy importer, and makes every
legacy username a signed-up test account that has claimed its history (`src/dev/seed.ts`).
Nothing is written to Supabase; a restart re-reads the latest web data. `GET /dev/accounts` lists
the accounts. In a Debug build of the iOS app, **Sign In as a Test Account** (Welcome screen or
Settings → Account) picks one, or launch with `-KedroAccount <handle>`:

```sh
xcrun simctl launch booted com.njoy77.kedro -KedroAccount njoy -KedroScreen board
```

Web games the importer can't reproduce exactly (rounds without a knock, or a −10 on someone who
didn't knock) are skipped; the startup log says how many.

## Configuration

`bun run env:pull` writes `apps/api/.env.local` from Vercel (see `.env.example` and `src/config.ts`):
`SUPABASE_URL` and `SUPABASE_ANON_KEY` from the web project. The API's own keys are
production-only secrets in the `kedro-api` project, which Vercel never hands back, so locally the
server runs on the in-memory store.

The database schema is `supabase/migrations/0002_kedro_v3.sql` and `0003_security_and_sync.sql`
(the legacy web app's `kedro_kv` table in `supabase/schema.sql` is untouched).

## Production

Vercel project **kedro-api** (root directory `apps/api`), deployed from `main` at
`https://api.playkedro.com`. The iOS Release build points there (`apps/ios/Config/API.xcconfig`).

`vercel.json` runs `bun run build`, which bundles `src/index.ts` into `dist/index.js` (Hono left
external, so Vercel's Hono preset recognizes the entrypoint), and Vercel serves it on the Bun
runtime. Vercel's own TypeScript step would type-check without our tsconfig base and leave the
`.ts` import paths in place, so it gets JavaScript only. `bunx vercel build` (after
`vercel pull --project kedro-api`) reproduces a deploy's build locally.

Keys, production only (`--project api` defaults to production):

```sh
bun run env:push SUPABASE_URL=https://<ref>.supabase.co SUPABASE_ANON_KEY=<anon> --project api
bun run env:push SUPABASE_SERVICE_ROLE_KEY --project api --sensitive   # value on stdin
bun scripts/api-keys.ts                                               # KEDRO_CLIP_SECRET, KEDRO_LINK_SIGNING_KEY
bun run env:push KEDRO_PUBLIC_URL=https://api.playkedro.com --project api
bun run env:push APNS_KEY_ID=<key id> --project api                  # the APNs auth key (Apple Developer → Keys)
bun run env:push APNS_PRIVATE_KEY --project api --sensitive          # the .p8 contents on stdin
```

### Pushes

With `APNS_KEY_ID` and `APNS_PRIVATE_KEY` set, the API sends pushes itself over HTTP/2
(`src/push/apns.ts`, on `node:http2`: Bun's `fetch` has no HTTP/2): an ES256 provider token
signed every 50 minutes and one session per APNs host, reused while the instance is warm. Team
and bundle ID default to `2RXNMCM34K` / `com.njoy77.kedro`; `APNS_ENVIRONMENT` is `production`
(TestFlight and App Store builds, the default on Vercel) or `sandbox` (Debug builds, the default
locally). Without the key the senders are stubs that log what they would send.

- **Live Activities** (`push/liveActivity.ts`): one APNs broadcast channel per game, created when a
  phone first asks for it at Deal or the game first changes, kept in `games.live_activity_channel_id`,
  and deleted after the `end` event. Needs **Broadcast** push enabled for the App ID's Push
  Notifications capability.
- **Alerts** (`push/notifications.ts`): N-01 "saved you a seat" to each of the player's device
  tokens, sent after the response. A token APNs answers 410 for is deleted.

On Vercel production (or with `NODE_ENV=production` elsewhere) the server refuses to start
without Supabase, `KEDRO_CLIP_SECRET`, `KEDRO_LINK_SIGNING_KEY` and `KEDRO_PUBLIC_URL`, and every
deployment refuses `KEDRO_DEV_AUTH` / `KEDRO_DEV_SEED` (`deploymentProblems` in `src/config.ts`).
Previews get no keys: they run on memory and answer every `/v1` request 401.

Known limits on Vercel: the per-game ingest lock (`services/lock.ts`) is per instance, so two
uploads to one game landing on different instances at once can leave its projection a write
behind until the next upload (the op log is always right). Background work after a response goes
through `waitUntil` (`defer` in `createApp`).

## Routes

Every `/v1` route needs `Authorization: Bearer <Supabase access token>`. Errors are
`{"error": <ApiErrorCode>, "message": "…"}`. UUIDs in paths may be any case.

| Route | Body → response | Notes |
|---|---|---|
| `GET /health` | → `{status, version}` | public |
| `POST /v1/ops` | `{ops:[Operation]}` → `{accepted, duplicates, rejected}` | ≤ 500 ops; idempotent by `opId`; needs a profile |
| `GET /v1/games/:gameId/ops?after=&limit=` | → `{ops}` | fold order; seated players and the creator only |
| `GET /v1/players/me` | → `Player` | 404 `profileRequired` before the first PUT |
| `PUT /v1/players/me` | `{displayName, handle, avatar, titleId?}` → `Player` | 409 `handleTaken` |
| `GET /v1/players/search?q=` | → `{players:[PlayerSummary]}` | name contains / handle prefix; `@` = handles only; excludes blocks both ways |
| `GET /v1/players/:playerId` | → `PlayerSummary` | addition (`PlayerDirectory.player`) |
| `GET /v1/players/me/played-with` | → `{players:[{player, gamesTogether, lastPlayedAt}]}` | addition |
| `GET /v1/players/me/guests?name=` | → `{guests:[{guestId, name, gamesTogether}]}` | addition (guest suggestions) |
| `GET /v1/handles/:handle` | → `{handle, available}` | addition (onboarding) |
| `POST /v1/claims` | `{claimToken}` → `{guestId, gamesClaimed}` | 404 unknown, 409 `alreadyClaimed`; replays ratings |
| `POST /v1/taunts/check` | `{text}` → `{allowed, reason?}` | reasons `empty`, `tooLong`, `blockedTerm` |
| `POST /v1/reports` | `{targetType, targetId, reason, gameId?}` → `{ok}` | |
| `POST /v1/blocks` · `DELETE /v1/blocks/:playerId` | `{playerId}` → `{ok}` | |
| `POST /v1/receipts` | `{gameId, toPlayerId, receiptKey}` → `{ok}` | both must have been seated; one per rival per game |
| `POST /v1/push/tokens` | `{token, kind, gameId?}` → `{ok}` | hex token; a per-game token needs a seat |
| `GET /v1/leaderboard?scope=&sort=&limit=` | → `{scope, sort, rows, notYetRanked, notYetRankedCount, me?}` | |
| `GET /v1/games/:gameId/live-activity` | → `{channelId}` | addition; the APNs broadcast channel, created on first use for a live game (null without APNs or after the game ends); seated players only |
| `POST /v1/clip/sessions` | `{gameId, tableToken, deviceId}` → `{accessToken, expiresAt}` | addition, no Authorization; a 6-hour token for one game and one phone (`KEDRO_CLIP_SECRET`) |
| `POST /v1/clip/claims` | `{gameId, seatId}` → `{claimToken}` | addition, clip token only; the guest seat linked to the clip's phone; 409 when it already has one |

An App Clip token works only on `POST /v1/ops`, `GET /v1/games/:gameId/ops` (its own game) and
`POST /v1/clip/claims`. Its uploads may only link the phone to an existing guest seat and act for
that seat (HandReported, ReactionAdded, a canned TauntSent); anything else is rejected `notAllowed`.
Taunts are limited to 3 per sender per round (1 custom) for every caller. A player seated in the
lobby without a phone gets N-01 "saved you a seat" (`push/notifications.ts`).

### Op ingest

1. Each op is validated against the wire contract (all 22 types); malformed ops are `rejected: invalid`.
2. Ops already stored are `duplicates`.
3. A new game's first upload must include its `GameCreated`; the uploader becomes its creator.
   For an existing game the caller must be seated, or be seating themselves (a `PlayerSeated` for
   their own player that the fold accepts: lobby, or before Round 1).
4. `actorPlayerId` must be null, the caller, or a player seated in the game (phones relay each other's ops).
5. A finished game takes only reactions, receipts, speaker claims, retractions, duplicate finishes and
   an abandon within 15 minutes of the finish. An abandoned game takes only a restore within 15
   minutes. Everything else is `rejected: gameFinished | gameAbandoned`; clients treat rejected ops as settled.
6. After inserting, the server re-folds the whole log and rewrites `games`/`seats`, the finished-game
   projection and (when the set of finished games changed) every rating.
7. Custom taunts are re-checked with the server filter; a blocked one gets a server-written
   `TauntRetracted` (`deviceId` `00000000-0000-4000-8000-00000000c0de`, `reason: "filtered"`).
8. The Live Activity broadcaster sends the new state to the game's channel after the response
   (`src/push/liveActivity.ts`; a stub without APNs).
