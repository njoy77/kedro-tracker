# AGENTS.md

Guidance for AI coding agents working in this repository.

## Repository

Kedro is a score tracker organized as a Bun workspace monorepo:

| Path | What it is |
|---|---|
| `apps/web` | React + Vite web app, deployed to Vercel (root directory `apps/web`) |
| `apps/api` | Bun + Hono API |
| `apps/ios` | Native SwiftUI iOS app. Read `apps/ios/AGENTS.md` before changing it |
| `packages/shared` | TypeScript types and constants shared by web and api |
| `supabase` | Database schema |
| `docs` | Product requirements and the legacy prototype |

## Tooling

- Use **Bun** for everything JavaScript: `bun install`, `bun run <script>`, `bun add`. Do not use npm, yarn, or pnpm, and do not commit `package-lock.json`.
- Run commands from the repo root with the root scripts (`bun run dev`, `bun run build`, `bun run typecheck`, `bun run ios:build`) or target a workspace with `bun run --filter '@kedro/<name>' <script>`.
- Node is not installed on the main dev machine. CLIs that need Node can run on Bun with `bun --bun <cli>`.
- The repo lives in an iCloud-synced folder. Keep build output (Xcode DerivedData, etc.) out of the repo, or code signing fails on iCloud's extended attributes.

## Environment variables and keys

- Vercel (project `kedro-tracker`) is the single source of truth for keys. Do not hard-code keys or commit secrets files.
- `bun run env:pull` generates `apps/web/.env.local` and `apps/ios/Config/Secrets.xcconfig` from Vercel. Never edit those files by hand.
- `bun run env:push KEY=value` adds or updates a key in Vercel (all environments by default), then pulls.
- The API's server-only keys live in a second Vercel project, `kedro-api` (production only): `bun run env:push KEY --project api --sensitive`. See `apps/api/README.md`.
- When an app needs a new key, push it to Vercel and add it to `TARGETS` in `scripts/env.ts`.

## iOS

All iOS work uses **modern SwiftUI**. Use UIKit **if and only if** something cannot be built with SwiftUI. See `apps/ios/AGENTS.md` for the full rules.
