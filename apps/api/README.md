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

## Configuration

`bun run env:pull` writes `apps/api/.env.local` from Vercel (see `.env.example` and `src/config.ts`):
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (server only) and optionally
`SUPABASE_JWT_SECRET`. Without the service-role key the server falls back to the in-memory store.

The database schema is `supabase/migrations/0002_kedro_v3.sql` (the legacy web app's `kedro_kv`
table in `supabase/schema.sql` is untouched).

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
| `GET /v1/games/:gameId/live-activity` | → `{channelId}` | addition; the APNs broadcast channel (null until APNs is set up); seated players only |
| `POST /v1/clip/sessions` | `{gameId, tableToken, deviceId}` → `{accessToken, expiresAt}` | addition, no Authorization; a 6-hour token for one game and one phone (`KEDRO_CLIP_SECRET`) |
| `POST /v1/clip/claims` | `{gameId, seatId}` → `{claimToken}` | addition, clip token only; the guest seat linked to the clip's phone; 409 when it already has one |

An App Clip token works only on `POST /v1/ops`, `GET /v1/games/:gameId/ops` (its own game) and
`POST /v1/clip/claims`. Its uploads may only link the phone to an existing guest seat and act for
that seat (HandReported, ReactionAdded, a canned TauntSent); anything else is rejected `notAllowed`.
Taunts are limited to 3 per sender per round (1 custom) for every caller. A player seated in the
lobby without a phone gets N-01 "saved you a seat" (built by `push/notifications.ts`; not sent
until APNs is configured).

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
8. The Live Activity broadcaster is called with the new state (a stub until APNs is configured,
   see `src/push/liveActivity.ts`).
