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
cp apps/web/.env.example apps/web/.env   # add Supabase credentials
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

## iOS

Requires Xcode 26+. The app targets iOS 26 and uses Swift 6 with modern SwiftUI
(`@Observable`, `Tab`, `NavigationStack`, Swift Testing). The project uses
folder-synchronized groups, so files added under `apps/ios/Kedro/` are picked up
automatically. The API base URL comes from the `KEDRO_API_BASE_URL` build setting, which
`Config/Info.plist` exposes to the app as `KedroAPIBaseURL`.
