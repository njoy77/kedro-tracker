# playkedro.com

A static site, no build step. It makes the links the iOS app creates (`KedroLink`, `TableInviteLink`) work outside the app.

| Path | What it is |
|---|---|
| `/.well-known/apple-app-site-association` | Universal links for `/t/*` and `/s/*` (opens Kedro), and the App Clip (`com.njoy77.kedro.Clip`). Served as `application/json` with no redirect, as Apple requires |
| `/t/{gameID}?k={token}` | Table invite (QR / AirDrop). With the app or App Clip available, iOS never shows this page |
| `/s/{gameID}?host=&word=` | "Saved you a seat": shows the table word for **Join with Code** |
| `/claim/{code}`, `/claim?code=` | Guest claim code with Copy and how to redeem it. Not a universal link: the app doesn't route `/claim` yet |

- Run it locally with `bun run dev:site` (http://localhost:3001). `dev.ts` applies `vercel.json`'s rewrites and headers.
- Deployed by the Vercel project `kedro-site` (root directory `apps/site`, output `public`), which owns `playkedro.com`; `www.playkedro.com` redirects to it. The API is on `api.playkedro.com` (project `kedro-api`).
- **Get Kedro** links: set `INSTALL_URL` in `public/assets/site.js` to the TestFlight public link or the App Store page. Until then the pages say Kedro is in a private beta.
- Changing the app's link paths, team ID or bundle IDs means changing the AASA too. Apple's CDN caches it: check `https://app-site-association.cdn-apple.com/a/v1/playkedro.com` after deploying.
