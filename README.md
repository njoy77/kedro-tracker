# Kedro

Score tracker for Kedro, organized as a [Bun](https://bun.sh) workspace monorepo.

```
apps/
  web/      React + Vite web app (Supabase-backed)
  api/      Bun + Hono API
  ios/      Native SwiftUI iOS app (Xcode project)
packages/
  shared/   TypeScript types and constants shared by web and api
supabase/   Database schema
docs/       Product requirements and legacy prototype
assets/     Brand assets (logo)
```

An Android app can be added later as `apps/android`.

## Setup

```bash
bun install
bun --bun run vercel login                         # once per machine
bun --bun run vercel link --project kedro-tracker  # once per checkout
bun run env:pull
```

## Common commands

| Command | What it does |
|---|---|
| `bun run dev` | Run web and API together |
| `bun run dev:web` | Web app at http://localhost:5173 |
| `bun run dev:api` | API at http://localhost:8787 |
| `bun run build` | Production build of the web app |
| `bun run typecheck` | Typecheck all TypeScript packages |
| `bun run ios:open` | Open the iOS project in Xcode |
| `bun run ios:build` | Build the iOS app for the simulator |
| `bun run env:pull` | Write local secrets files from Vercel env vars |
| `bun run env:push KEY=value` | Add or update a Vercel env var, then pull |

## Environment variables

Vercel (project `kedro-tracker`) is the source of truth for keys. Never edit the generated files by hand.

`bun run env:pull` writes:

| File | Contents |
|---|---|
| `apps/web/.env.local` | Every `VITE_*` variable |
| `apps/ios/Config/Secrets.xcconfig` | `SUPABASE_HOST` and `SUPABASE_ANON_KEY`, derived from the `VITE_SUPABASE_*` variables |

To add or change a key:

```bash
bun run env:push VITE_SUPABASE_ANON_KEY=new-value
```

- Pushes go to development, preview, and production unless you pass `--environment`.
- `bun run env:push --file some.env` pushes every key in a dotenv file.
- `echo "value" | bun run env:push KEY` keeps the value out of shell history.
- `--sensitive` stores a write-only secret. Sensitive values can't be pulled, so use it only for server-side keys that no local file needs.
- `bun run env:pull --environment production` pulls a different environment (default: development).
- When an app needs a new key, add it to `TARGETS` in `scripts/env.ts`.

## iOS

Requires Xcode 26+. The app targets iOS 26 and uses Swift 6 with modern SwiftUI
(`@Observable`, `Tab`, `NavigationStack`, Swift Testing). The project uses
folder-synchronized groups, so files added under `apps/ios/Kedro/` are picked up
automatically. The API base URL comes from the `KEDRO_API_BASE_URL` build setting, which
`Config/Info.plist` exposes to the app as `KedroAPIBaseURL`.
