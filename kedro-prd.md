# Kedro
## Cambio Card Game Score Tracker
### Product Requirements Document · v1.0 · March 2026

---

## 1. Product Overview

Kedro is a web-based score tracking application for the Cambio card game. It allows a friend group to log game results, maintain player profiles, track running totals and lifetime statistics, and watch live scores update across all devices in real time during an active game session.

| Field | Value |
|---|---|
| Product Name | Kedro |
| Platform | Web app (browser, any device) |
| Players | 2–6+ per game session |
| Primary Users | Friend group playing Cambio together |
| Storage | Shared cloud storage (window.storage API, shared: true) |
| Live Sync | Polling every 5 seconds — all players see same state |
| Auth Model | Username + 4-digit PIN (no email, no OAuth) |

---

## 2. Game Rules Reference

The app is built around the official Cambio card game rules. Below is the rule set used as the design foundation.

### 2.1 Setup
- Each player receives 4 cards dealt face-down, arranged in a 2×2 grid
- Players may not look at their own cards (unless a power card reveals them)
- Goal: end the game with the lowest total point value

### 2.2 Scoring

| Card | Points |
|---|---|
| Face cards (J, Q, K — non-special) | 10 points each |
| Number cards (2–10) | Face value |
| Ace | 1 point |
| Red King (♥K or ♦K) | –1 point (negative) |
| Joker | 0 points |

### 2.3 Special Card Powers
- **7 / 8 — Peek Own:** Look at one of your own face-down cards
- **9 / 10 — Peek Opponent:** Look at one of an opponent's face-down cards
- **Jack / Queen — Blind Switch:** Swap one of your cards with an opponent's without looking
- **Black King (♠K or ♣K) — Look & Switch:** Look at any card, then optionally swap it

### 2.4 Sticking Mechanic
- When a card is discarded, any player may immediately play a matching card from their hand to remove it from their grid
- This is a live mechanic — players must be alert and act quickly

### 2.5 Calling Kedro (Win Condition)
- Any player may call "Kedro" on their turn when they believe they have the lowest total
- After Kedro is called, all other players get exactly one more turn
- All cards are then revealed and totaled
- The player with the lowest total wins the round
- If the player who called Kedro does not have the lowest total, they receive a penalty

---

## 3. User Stories

### 3.1 Player Registration & Login
- As a new user, I can register a profile with a unique username, a 4-digit PIN, and an emoji avatar
- As a returning user, I can log in by entering my username and PIN
- As a user, I can log out from my profile screen
- PINs are not recoverable — users must remember their PIN

### 3.2 Home Dashboard
- As a logged-in user, I can see my lifetime stats (games played, wins, average score, best game)
- As a logged-in user, I can see a banner if there is an active game in progress
- As a logged-in user, I can see recent game history
- As a logged-in user, I can navigate to: New Game, History, Profile
- As a logged-in user, I can see a live sync indicator (green pulsing dot + LIVE label) confirming shared data is active

### 3.3 New Game
- As a user, I can start a new game by selecting 2–6+ registered players
- The game session is saved to shared storage and visible to all devices

### 3.4 Active Game
- As a player in an active game, I can see a live scoreboard with all players and their current totals
- As a player, I can enter the score for each player after each round
- As a player, I can press the Kedro button to signal the end of the game
- Pressing Kedro triggers a full-screen celebration animation
- Round score inputs are preserved locally and are not disrupted by live sync polls

### 3.5 History
- As a user, I can view a log of all completed games
- Each entry shows the date, players, scores, and winner

### 3.6 Profile
- As a user, I can view my profile including username, emoji, and lifetime stats
- As a user, I can log out from this screen

---

## 4. Design & Brand

### 4.1 Brand Identity

| Property | Value |
|---|---|
| App Name | Kedro |
| Logo | Bold red script "Kedro" over a silver/gray galloping horse on black background |
| Logo format | Base64-embedded PNG (no external dependency) |
| Logo — Login screen | 120px wide, centered |
| Logo — Splash screen | 160px wide, centered |
| Logo blend mode | screen (to blend with dark background) |

### 4.2 Color Tokens

| Token | Value |
|---|---|
| bg | #0a0a0a — primary background |
| surface | #111111 — card surfaces |
| surface2 | #181818 — secondary surfaces |
| surface3 | #1f1f1f — tertiary surfaces |
| border | #2a2a2a — default borders |
| borderLight | #3a3a3a — lighter borders |
| red | #d42b2b — primary accent (buttons, highlights) |
| redHover | #e83535 — red hover state |
| redGlow | rgba(212,43,43,0.25) — glow shadows |
| silver | #c0c0c0 — secondary text / horse theme |
| silverDim | #888888 — dimmed secondary |
| cream | #f0f0f0 — primary body text |
| creamDim | #999999 — dimmed body text |
| green | #3dba6a — success, live indicator |
| blue | #4a9edd — informational |

### 4.3 Typography
- Primary display font: Bebas Neue (headings, labels)
- Body font: Barlow (body text, inputs)
- Fonts loaded via Google Fonts CDN

### 4.4 Avatar & Emoji Theme
- All avatars use horse-themed emojis
- Emoji set: 🐴 🏇 🦄 🐎 🎠 🏆 🌾 🍀 🔱 ⚜️ 🌿 🪄 🎯 🌙 ⭐
- Default emoji: 🐴
- UI button labels use horse emoji: "Create Profile 🐴", "Deal Cards 🐴", "🐴 Kedro — Add Round"

---

## 5. Screen Inventory

| Screen | Description |
|---|---|
| Splash Screen | Animated logo display for 1.8 seconds, then auto-redirects to Login |
| Login / Register | Username input → PIN entry (existing user) or emoji picker + PIN creation (new user) |
| Home Dashboard | Stats summary, active game banner, recent games list, nav to all sections, LIVE indicator |
| New Game | Multi-select player picker, start game button |
| Active Game | Live scoreboard, round score entry per player, Kedro button, full-screen Kedro celebration |
| History | List of all completed games with date, players, scores, winner |
| Profile | User info, lifetime stats, logout |

---

## 6. Data Model

### 6.1 Storage Layer
The app uses `window.storage` (Claude artifact persistent storage API) with `shared: true` on all operations. This means all data is shared across all users accessing the same artifact URL — no per-user isolation.

### 6.2 Storage Keys

| Key | Contents |
|---|---|
| kedro_players | Array of all registered player objects |
| kedro_games | Array of all game session objects (active + completed) |
| kedro_session | Current logged-in user's session (username + emoji) |

### 6.3 Player Object
- `username` — string, unique identifier
- `pin` — string, 4-digit PIN
- `emoji` — string, selected avatar emoji
- `gamesPlayed` — integer
- `wins` — integer
- `totalScore` — integer (lifetime sum)
- `bestGame` — integer (lowest single-game score)

### 6.4 Game Object
- `id` — string, unique game ID
- `players` — array of player usernames
- `scores` — object mapping username → array of round scores
- `status` — `'active'` or `'completed'`
- `createdAt` — ISO timestamp
- `completedAt` — ISO timestamp (if completed)
- `winner` — username of winning player (if completed)

---

## 7. Live Sync Behavior

- Polling interval: every 5 seconds via `useEffect` with `setInterval`
- On each poll: fetch `kedro_players`, `kedro_games`, `kedro_session` from shared storage
- Re-derive stats and session state from freshly fetched data
- Round score inputs are stored in separate local React state — never overwritten by sync
- `live` boolean state: turns `true` after the first successful poll
- LIVE indicator: pulsing green dot + "LIVE" label appears in the top-right of Home Dashboard once `live` is true
- All players opening the same artifact URL share the same data store

---

## 8. Technical Stack (v1)

| Property | Value |
|---|---|
| Framework | React (single JSX file, no build step) |
| Styling | Inline styles using design token constants |
| Storage | window.storage (Claude artifact persistent storage API) |
| Fonts | Google Fonts CDN — Bebas Neue, Barlow |
| Deployment | Claude artifact (shared URL) |
| File | cambio-tracker.jsx (~761 lines) |
| No dependencies | No npm packages, no bundler, no backend |

---

## 9. Future Considerations

The following features were discussed but not built in v1:

- Quick-add / guest player mode from the New Game screen
- Leaderboards across all players
- Head-to-head matchup stats view
- Track which player called Kedro in game stats
- Migrate to Vite + React (local app) with Supabase for proper real-time WebSocket sync
- Expo / React Native version for native iOS/Android app
- Penalty tracking for incorrect Kedro calls

---

*Kedro PRD v1.0 · Built March 2026*
