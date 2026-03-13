# Kedro
## Cambio Card Game Score Tracker
### Product Requirements Document · v2.0 · March 2026

---

## 1. Product Overview

Kedro is a web-based score tracking application for the Cambio card game. It allows a friend group to log game results, maintain player profiles, track running totals and lifetime statistics, and watch live scores update across all devices in real time during an active game session.

| Field | Value |
|---|---|
| Product Name | Kedro |
| Platform | Web app — mobile portrait primary (personal phones) |
| Players | 3–8 per game session |
| Primary Users | Friend group playing Cambio together |
| Storage | Supabase (PostgreSQL + Realtime WebSockets) |
| Live Sync | Supabase Realtime subscriptions — instant push updates |
| Auth Model | Username only — no PIN, no email, no OAuth |
| Login Persistence | Stay logged in by default; switch player via Profile screen |

---

## 2. Game Rules Reference

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

### 2.5 Knocking (Round End)
- Any player may knock on their turn when they believe they have the lowest total
- After knocking, all other players get exactly one more turn to draw a card
- All cards are then revealed and totaled
- The player with the lowest total wins the round
- If the player who knocked does not have the lowest total, they receive a penalty (affects their round score — tracked manually by players, not enforced by the app)

### 2.6 Game End
- A game consists of multiple rounds (number varies — 3, 5, or as many as the group decides)
- The game ends when a player presses the Kedro button in the app
- There is no fixed end condition — the group decides when to end (e.g., first to 100 points, set number of rounds)
- The player with the lowest cumulative total at game end wins

---

## 3. User Stories

### 3.1 Player Registration & Login
- As a new user, I can register a profile with a unique username and an emoji avatar
- As a returning user, I tap my username and I'm immediately logged in (no PIN)
- As a logged-in user, I remain logged in across sessions on my personal phone
- As a user, I can switch to a different player from the Profile screen (for shared devices)
- As a user, I can log out from the Profile screen

### 3.2 Home Dashboard
- As a logged-in user, I can see my lifetime stats summary
- As a logged-in user, I can see a banner if there is an active game in progress, and tap to open it
- As a logged-in user, I can see recent game history
- As a logged-in user, I can navigate to: New Game, History, Profile
- As a logged-in user, I can see a live sync indicator confirming real-time connection is active

### 3.3 New Game
- As a host, I can start a new game by selecting 2–8 registered players from the full player list
- The game session is created in Supabase and immediately visible to all devices via real-time push
- Players who open the app see the active game banner on their dashboard and tap to join the live view
- As a host, I can tap "Rematch" from the post-game screen or dashboard to instantly start a new game with the same players

### 3.4 Active Game
- As a player in an active game, I can see a live scoreboard sorted by lowest cumulative score (leader first)
- The current leader displays a 👑 crown indicator at all times
- Each player shows their rank badge: 🥇 🥈 🥉 (and position numbers beyond 3rd)
- As a player, I can submit round scores by entering each player's score for that round
  - Scores are entered as round deltas (what each player scored that round, not running total)
  - Negative scores are supported (e.g., –1 for a Red King round)
  - The app computes and displays the running cumulative total for each player
- As part of round score entry, I can mark which player knocked for that round
  - The app automatically determines if the knocker had the lowest round score
  - This feeds into each player's Kedro effectiveness stat
- After a round is submitted, each player's row briefly shows their score delta (+7, –1, etc.) before settling to the new cumulative total
- As a player, I can tap any player's score to see their full round-by-round breakdown mid-game
- As a player, I can edit scores from any previous round if an entry was incorrect
- The screen stays awake during an active game (Wake Lock API)
- As a player, I can press the Kedro button to end the entire game
  - Pressing Kedro triggers a full-screen celebration animation
  - Game transitions to the Post-Game Summary screen
- As a host, I can abandon a game (marks it as abandoned, excludes from all stats)

### 3.5 Post-Game Summary
- After pressing Kedro, a summary screen appears before returning to the dashboard
- Summary shows:
  - Winner with celebration treatment
  - Final standings (all players, final cumulative scores)
  - Game highlights: best single round, most effective Kedro caller, lowest scoring player
- A "Rematch 🐴" button starts a new game with the same players instantly
- A "Home" button returns to the dashboard

### 3.6 History
- As a user, I can view a log of all completed games
- Each entry shows: date, players, final scores, winner
- Tapping a game shows the full round-by-round breakdown
- Abandoned games appear in history but are visually marked as abandoned

### 3.7 Profile
- As a user, I can view my profile: username, emoji, and full lifetime stats
- As a user, I can switch to a different player (for shared device use)
- As a user, I can log out

---

## 4. Stats Model

### 4.1 Per-Player Lifetime Stats

| Stat | Description |
|---|---|
| Games Played | Total completed games |
| Wins | Total games won |
| Win Rate | Wins / Games Played % |
| Best Game | Lowest cumulative score in a completed game |
| Worst Game | Highest cumulative score in a completed game |
| Average Score (per game) | Lifetime cumulative score / games played |
| Average Score (per round) | Lifetime round scores / rounds played |
| Current Win Streak | Consecutive wins currently |
| Longest Win Streak | Best consecutive win streak ever |
| Knock Rate | Rounds knocked / total rounds played % |
| Kedro Win % | Rounds won (had lowest score) when knocking / total knocks % |
| Nemesis | Player who has beaten this player most often head-to-head |

### 4.2 Head-to-Head Records
- For any two players, show: games played together, wins each, win rate each

---

## 5. Design & Brand

### 5.1 Brand Identity

| Property | Value |
|---|---|
| App Name | Kedro |
| Logo | Bold red script "Kedro" over a silver/gray galloping horse on black background |
| Logo format | Base64-embedded PNG (no external dependency) |
| Logo — Login screen | 120px wide, centered |
| Logo — Splash screen | 160px wide, centered |
| Logo blend mode | screen (to blend with dark background) |

### 5.2 Color Tokens

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
| gold | #f5c842 — crown / leader indicator |

### 5.3 Typography
- Primary display font: Bebas Neue (headings, labels)
- Body font: Barlow (body text, inputs)
- Fonts loaded via Google Fonts CDN

### 5.4 Avatar & Emoji Theme
- All avatars use horse-themed emojis
- Emoji set: 🐴 🏇 🦄 🐎 🎠 🏆 🌾 🍀 🔱 ⚜️ 🌿 🪄 🎯 🌙 ⭐
- Default emoji: 🐴
- UI button labels use horse emoji: "Create Profile 🐴", "Start Game 🐴", "🐴 Kedro — End Game"

---

## 6. Screen Inventory

| Screen | Description |
|---|---|
| Splash Screen | Animated logo display for 1.8s, then auto-redirects to Login |
| Login / Register | Username input → existing user logs in immediately, new user picks emoji and creates profile |
| Home Dashboard | Stats summary, active game banner, recent games list, nav to all sections, LIVE indicator |
| New Game | Multi-select player picker from registered list, start game button |
| Active Game | Live scoreboard (sorted by score), rank badges, crown on leader, round score entry, knock tracker, score delta animation, round history tap, edit scores, Kedro end-game button, abandon option |
| Post-Game Summary | Winner celebration, final standings, game highlights, Rematch button, Home button |
| History | List of all completed games; tap to expand full round-by-round breakdown |
| Profile | User info, full lifetime stats, switch player, logout |

---

## 7. Data Model

### 7.1 Storage Layer
The app uses Supabase (PostgreSQL) with Realtime WebSocket subscriptions for instant cross-device sync. All data lives in a shared `kedro_kv` key-value table plus dedicated tables for structured queries.

### 7.2 Storage Keys (kedro_kv)

| Key | Contents |
|---|---|
| kedro_players | Array of all registered player objects |
| kedro_games | Array of all game session objects (active + completed + abandoned) |
| kedro_session_{deviceId} | Current logged-in user for this device |

### 7.3 Player Object
- `username` — string, unique identifier
- `emoji` — string, selected avatar emoji
- `gamesPlayed` — integer
- `wins` — integer
- `totalScore` — integer (lifetime sum of all round scores)
- `totalRounds` — integer (lifetime rounds played)
- `bestGame` — integer (lowest cumulative score in a completed game)
- `worstGame` — integer (highest cumulative score in a completed game)
- `currentStreak` — integer
- `longestStreak` — integer
- `totalKnocks` — integer (times knocked across all games)
- `kedroWins` — integer (times knocked and had the lowest round score)

### 7.4 Game Object
- `id` — string, unique game ID
- `players` — array of player usernames (ordered)
- `rounds` — array of round objects (see 7.5)
- `status` — `'active'` | `'completed'` | `'abandoned'`
- `createdAt` — ISO timestamp
- `completedAt` — ISO timestamp (if completed)
- `winner` — username of winning player (if completed)

### 7.5 Round Object
- `roundNumber` — integer
- `scores` — object mapping username → round score (delta, can be negative)
- `knockedBy` — username of player who knocked (nullable)
- `knockerWon` — boolean (was the knocker's round score the lowest?)

---

## 8. Real-Time Sync Behavior

- Sync method: Supabase Realtime WebSocket subscriptions on `kedro_kv` table
- On any data change: all subscribed clients receive instant push update
- No polling — updates are event-driven
- `live` boolean state: turns `true` after first successful subscription
- LIVE indicator: pulsing green dot + "LIVE" label in top-right of Home Dashboard
- Round score inputs are stored in separate local React state — never overwritten by sync
- Wake Lock API keeps screen active during an active game session

---

## 9. Technical Stack (v2)

| Property | Value |
|---|---|
| Framework | React 18 + Vite |
| Styling | Inline styles using design token constants |
| Database | Supabase (PostgreSQL) |
| Real-time | Supabase Realtime WebSocket subscriptions |
| Fonts | Google Fonts CDN — Bebas Neue, Barlow |
| Deployment | Vercel / Netlify (static site + env vars) or local |
| Auth | None — username-only, persisted to localStorage |

---

## 10. Future Considerations

- Expo / React Native version for native iOS/Android app
- Push notifications when it's your turn or scores are submitted
- Leaderboard screen across all players (all-time rankings)
- Tournament mode (bracket-style multi-game events)
- Penalty tracking for incorrect Kedro calls (auto-added to score)
- Guest/quick-add player mode for one-off players without profiles

---

*Kedro PRD v2.0 · Revised March 2026*
