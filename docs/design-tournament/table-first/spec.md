# Kedro for iOS: "Table First"

### Design tournament entry · spec v1 · October 2026

> Companion file: [`mockups.html`](./mockups.html) has 20 iPhone frames (393 × 852 pt), including the live game in light and dark.
> Requirements source: `docs/kedro-ios-prd.md` (v3.0). Section references such as "PRD 4.5" point there.

---

## 0. Design thesis

**At the table, Kedro is a scoreboard you glance at and a keypad you use for fifteen seconds. Everything else waits until the cards are put away.**

Cambio is a game of faces, bluffs and knocks. A phone that wants attention breaks that. So Table First has two speeds:

- **Table speed** (while a game is live). There is one screen, the **Table**: standings, last-round deltas and round progress, readable from arm's length. It has one primary action, **Record Round N**. No feeds, badges or prompts appear. Achievements, rating changes and progress messages are held back until the game ends.
- **Between-games speed** (everything else). Here Kedro becomes a rich, quiet record: your stats, your rivals, the leaderboard and your achievements. This is where "people come back" happens, and it can be as deep as it wants because nobody at a table is waiting on it.

The visual language reads Apple's HIG strictly. It uses stock `List`, `Form`, `TabView`, sheets, toolbars and Liquid Glass, with SF Pro and SF Symbols. The brand's red is used **only for the one action that matters** on each screen. The horse spirit appears in identity (every player is a horse, see 9.4) and in rare moments (the game-end gallop), never as decoration in the way of a score.

### How the thesis serves the four PRD goals

| PRD goal | How Table First delivers it |
|---|---|
| **Fast table flow** | One live screen and one primary button. Round entry is a single sheet: pick the knocker, then type hand values on a purpose-built keypad that auto-advances after two digits. The app applies −10 / hand / +10 itself and shows why. **12 taps and about 15 s for 5 players** (§14). The screen never sleeps during a game, and nothing interrupts it. |
| **Everyone joins** | Multipeer discovery shows any nearby table at the top of **Play**. Returning players tap **Join** once. People the host has played with are admitted automatically, and strangers need one host tap. Guests can be added with no app at all, or can join from a fresh install **without making an account**. Five returning players take **6 taps in total** (§14). |
| **People come back** | Between games: a Rating and leaderboard placement, the "5 games to rank" goal, head-to-head rivalries with a named nemesis, 22 achievements, Home Screen widgets, and a game-end screen that turns a win or loss into a "next goal". |
| **Spreads to new tables** | "Learn Cambio in 2 minutes" sits on the first-launch screen. TipKit coaching runs in a first game, the scoring explains itself ("why −10?"), and a card-tap entry mode teaches card values while you score. Guest history is claimed through AirDrop/Messages links. If a guest joined from their own phone, the claim happens automatically when they sign in. |

---

## 1. Information architecture and navigation

### 1.1 The two modes

```
App
├── TabView (between games)
│   ├── Play            ← start / join / rematch / recent games / learn
│   ├── Leaderboard     ← Global | Played With
│   ├── You             ← profile, stats, rivals, achievements, history, settings
│   └── Search (role: .search) ← find any Kedro player → public profile
│
└── Table (while a game is live)   ← fullScreenCover over the TabView
    ├── Standings (the only "page")
    ├── Record Round sheet           (scorekeeper or self-report)
    ├── History sheet                (round grid + Changes log)
    │   └── Round detail → Edit Round sheet
    ├── Rules sheet (medium detent, game stays visible behind it)
    └── ⋯ Menu: Invite · Hand off scorekeeping · Extend · End early · Abandon
```

**Why a full-screen cover instead of a tab?** A live game is a *mode*, not a place you browse to. Covering the tab bar removes every competing destination from the screen during play. When you minimize it (chevron at top left, or swipe down), the game stays in the iOS 26 **`tabViewBottomAccessory`** as a compact strip ("Round 5 of 8 · You 3rd · 36"), the way Music shows Now Playing. Tapping the strip brings the Table back. You can check your head-to-head with Ana mid-game, and you are always one tap away from the scoreboard.

**Why only three content tabs?** Each one answers a single question:
- **Play**: "Let's play." (start, join, rematch, learn)
- **Leaderboard**: "Where do I stand?"
- **You**: "How am I doing?" (stats, rivals, achievements, history)

Search uses the system `Tab(role: .search)`, so it appears as the separate Liquid Glass search button the system places in iOS 26, not as a fourth content tab.

### 1.2 Where things live

| Need | Location |
|---|---|
| Start a game | Play → **New Table** (the only prominent button on Play) |
| Join a nearby game | Play → **Nearby** section, which appears only when a table is discovered |
| Rematch | Game-end screen (primary button); Play → recent game row → swipe action **Rematch** |
| Played-with list | New Table → Add Player (first section); You → Rivals |
| Rules | Play → Learn Cambio; Table toolbar → book icon (any time, mid-game) |
| Any player's profile | Tap any avatar anywhere, or Search |
| Head-to-head | Any other player's profile → "You vs Ana" section; You → Rivals |
| Claim guest history | Universal link / AirDrop opens the claim sheet; You → Settings → Claim Guest History (enter code) |
| Settings | You → toolbar gear (pushes a `Form`) |

### 1.3 Navigation rules
1. One `NavigationStack` per tab, value-based `navigationDestination(for:)`. Routes are `PlayerID`, `GameID`, `HeadToHead(a,b)`, `AchievementID`.
2. **Sheets are for doing, pushes are for reading.** Recording, editing, setup, joining and claiming are sheets. Profiles, games and stats are pushes.
3. **Destructive and state-changing game actions** (extend, end early, abandon, edit) always pass through a `confirmationDialog` that states the consequence and says it will be logged for everyone.
4. Deep links (`kedro://` plus universal links `https://kedro.app/claim/…`, `/game/…`, `/player/…`) resolve to the same routes.

---

## 2. Getting a table into a game (PRD 4.1)

### 2.1 Proximity model

- **Discovery and offline sync use MultipeerConnectivity.** It works over Bluetooth and peer-to-peer Wi-Fi with no router and no internet, and its session cap of 8 peers matches the PRD's 3–8 table size exactly. When a host taps **New Table**, their device advertises; devices with Kedro in the foreground browse. No `MCBrowserViewController` (UIKit) is used. Discovered peers feed a SwiftUI list.
- **Nearby Interaction is a refinement, not a dependency.** On UWB iPhones, after a discovery token is exchanged over Multipeer, the table you are physically closest to sorts first and is labelled "Right here". "Bring your phone near Ana's" works as a gesture, but the design never *requires* it.
- **Online fallback.** With internet, a host can also add any Kedro user from Played With or Search. That user's device gets a "Noah added you to a table" push (the one joining notification, §8.3) and a Join card in Play.
- **Permissions are asked in context.** The Local Network prompt (needed for Multipeer) is preceded by a one-line explanation the first time someone taps **New Table** or **Join a table**, never at launch.

### 2.2 Admission policy (opinionated)
| Who taps Join | Result |
|---|---|
| Someone the host has **played with before** | **Admitted automatically.** The host sees them appear with a soft haptic. |
| Someone the host **added in setup** | Admitted automatically (already invited). |
| Anyone else (a new Kedro user, or a guest on their own phone) | Host gets an inline row "Jo wants to join · **Admit**". One tap. |

This keeps the returning-player path at a single confirmation while preventing a stranger in a café from joining your table.

### 2.3 Flow: a full table of returning players (5 players)

1. **Host (Noah)** opens Kedro → Play → **New Table**. The setup sheet opens with the host's last settings (8 rounds, Scorekeeper).
2. The **Players** section already lists everyone discovered nearby whom Noah has played with: Ana, Ben, Cleo, Dev, each pre-checked with a "Nearby" caption. Noah reviews and taps **Start Table**.
3. On Ana's, Ben's, Cleo's and Dev's phones (Kedro open, Play tab): the **Nearby** section shows "Noah's table · 5 players · Join". If Kedro is backgrounded, they open it and the card is already at the top. Each taps **Join** (the sheet confirms the player list, rounds and mode).
4. All five phones flip to the Table at the same moment the first player joins; a player whose phone lags simply joins a game that is already showing.

*If someone is not discovered* (Kedro not open, or no Bluetooth): Noah taps **Add Player** → Played With (sorted by most recent co-players) → tap the name. With internet that player gets a push. Without internet they can join from Nearby as soon as they open the app, and their seat is waiting for them (§2.6).

### 2.4 Flow: a table with a guest
- **Guest with no phone or no app.** In setup, Noah taps **Add Player → Guest**, types "Sam", and taps **Add**. Sam gets an unclaimed guest identity with a dashed-ring avatar (§9.4). In scorekeeper mode nothing else changes. In self-report mode Sam's row shows **Report for Sam**, which anyone can tap.
- **Guest with a fresh install (first-time Kedro user).** Sam installs Kedro. The first-launch screen has three choices (§2.7): Sign in with Apple, **Join a Table as a Guest**, and Learn Cambio. Sam taps Join as a Guest, types a name, and sees "Noah's table". **Join** → Noah taps **Admit**. Sam's device now holds a *claim token* for that guest identity, so if Sam signs in later, the history claims itself with no code.

### 2.5 Flow: mid-game join
"Mid-game join" means two different situations. Table First treats them differently on purpose:

| Situation | Behaviour |
|---|---|
| **A seated player's device joins late.** Ben's phone was dead, or Sam (added as a guest) installs Kedro in round 3. | Ben sees "Noah's table · Round 3 of 8" in Nearby → **Join** → Kedro matches him to his existing seat (by account, or by the host's choice for a guest: "Is this Sam?" → **Yes**). His device receives the whole operation log over Multipeer and is current immediately. |
| **A new person wants to play after Round 1 is recorded.** | **New players cannot be added after the first round is recorded.** The canonical ruleset (PRD 2) has no rule for scoring missed rounds, and inventing a catch-up score would be a house rule (a PRD non-goal). Instead, the newcomer can **Watch** (a read-only Table on their own phone, so they can learn by watching the scoring) and is automatically queued: "Jo is in for the rematch." When the game ends, the rematch sheet already includes Jo. |

Before Round 1 is recorded, the table is still "open" and anyone can join normally.

### 2.6 Flow: game setup (New Table sheet)

A `Form` in a sheet (`.presentationDetents([.large])`):

| Section | Control | Default |
|---|---|---|
| **Players** (3–8) | Rows with avatar, name and caption (You · Host / Nearby / Guest / Added). Swipe to remove. **Add Player** pushes a picker with three sections: *Played With* (recent first), *Search Kedro*, *Add a Guest by name*. | Nearby played-with players pre-checked. |
| **Rounds** | `Stepper` "8 rounds" (1–30), with a footer showing the typical length: "About 40 minutes at this table." The estimate comes from the group's own pace. | Last used, else 8. |
| **Scoring** | Segmented `Picker`: **One Scorekeeper** / **Everyone Reports**, with a footer explaining the selected mode in one sentence. If a guest has no device, the Everyone Reports footer says "Someone will report for Sam." | Last used, else One Scorekeeper. |
| **Scorekeeper** (scorekeeper mode only) | Picker of players | Host |
| Toolbar | Cancel · **Start Table** (`.borderedProminent`, disabled below 3 players with the footer "Add at least 3 players") | — |

**Start Table** is enabled with 3–8 players. When an 8th player is added, the Add Player row reads "Table is full (8)".

### 2.7 First launch / onboarding
One screen, not a carousel. The brand wordmark and the galloping horse sit on the brand's near-black (`#0A0A0E`) for the splash, which then settles into:

1. **Sign in with Apple** (`SignInWithAppleButton`, the primary choice). *While Apple sign-in is disabled pending developer approval, debug builds show the test-user sign-in in its place. Release builds never include it (compile-time `#if DEBUG`).*
2. **Join a Table as a Guest**: name field → Nearby. No account needed.
3. **New to Cambio? Learn in 2 minutes** (§7).

No notification prompt and no Local Network prompt at launch. Notifications are requested once, on the game-end screen of the user's **first finished game**, with a one-line reason ("Get told when you make the leaderboard"). The value is clear at that point, so the opt-in rate is higher.

---

## 3. The Table: the live game screen (PRD 4.4)

### 3.1 Layout (top to bottom)
1. **Toolbar** (Liquid Glass): `chevron.down` (minimize) · title **Round 5 of 8** · `book` (rules) · `clock.arrow.circlepath` (history) · `ellipsis` (menu). A **sync pill** appears in the title area *only when not live-online* (§6).
2. **Round progress**: 8 segments, 4 filled, the current one outlined. This one control shows progress against planned rounds. It is a `Gauge`-equivalent built with a custom `ProgressViewStyle`, so it stays a stock `ProgressView` for accessibility ("4 of 8 rounds complete").
3. **Last round line**: one sentence that always explains the most recent knock. For example: *"Cleo knocked with 2. Sam had −1, so the knock failed: Cleo scores 2 + 10."* Tapping it opens that round's detail.
4. **Standings** (`List`, `.plain`, large rows):
   - Rank (1–5, `.title3` monospaced). Ties share a rank ("2=").
   - Avatar · name (`.headline`) · caption "Leading" (with the horse glyph in brand red) for the leader(s), or "You".
   - Right side: **cumulative score**, `.system(size: 34, weight: .semibold).monospacedDigit()`, scaled with `@ScaledMetric`. Under it, **last-round delta** "+12" with a knock badge when relevant: `hand.raised.fill` + "failed" / "tied" / "−10". Deltas use **sign and words, not red/green**: lower is better in Cambio, red is the brand color, and color alone fails colorblind users.
   - Rows re-sort with `.animation(.smooth)` and scores tick with `.contentTransition(.numericText(value:))` (crossfade under Reduce Motion).
5. **Bottom action** (safe-area inset, glass-prominent): **Record Round 5**. A caption under it says who is keeping score: "You're keeping score", or "Ben is keeping score · he's entering Round 5 now…" (presence over Multipeer and Realtime). In self-report mode the button becomes **Report Your Hand**, and the standings rows show ✓/waiting status during an open round.

### 3.2 Attention rules during play
- **The screen never sleeps** while the Table is on screen (`isIdleTimerDisabled`; see the UIKit flag in §12). It sleeps again the moment the Table is minimized or the game ends.
- No push notifications to anyone at the table. The Live Activity is the only system surface that updates.
- Achievements, rating deltas and leaderboard movement are **computed but held back** until game end.
- An edit by another player shows a single **non-modal banner** for 4 s ("Ben edited Round 4 · View"), and the round is permanently tagged "Edited" in History. No modal dialogs, no sounds.
- Haptics: `.sensoryFeedback(.success)` on the device that saved a round; `.impact(weight: .light)` on the other devices when standings change.

### 3.3 Why the score is trusted (PRD 4.7, judging criterion 3)
- Every delta is tappable and opens a popover with the rule in plain words, for example: "Noah knocked with 2, the strictly lowest hand. A successful knock scores −10 no matter the hand."
- The knock outcome is a word ("successful", "tied", "failed"), never just a number.
- Everyone sees every edit, with who, when and before → after (§5).

---

## 4. Recording a round (PRD 4.2, 4.3, 2.6)

### 4.1 Scorekeeper mode: the Round sheet
`.sheet` at `.large`, with the Table visible above it as a dimmed strip. **Interaction design:**

1. **Who knocked?** A row of player avatars at the top. One tap selects the knocker (red ring + `hand.raised.fill`). **Save is disabled until a knocker is chosen** (PRD 2.5), and the field is labelled "Required". To make this fast, the sheet opens with focus on the knocker row.
2. **Hand values.** A `List` of players in seat order. The active row is highlighted, and a **built-in keypad** fills the bottom third:
   ```
   [ 1 ][ 2 ][ 3 ]
   [ 4 ][ 5 ][ 6 ]
   [ 7 ][ 8 ][ 9 ]
   [ − ][ 0 ][ ⌫ ]
   [      Next: Ana  › ]   → on the last player: [ Save Round 5 ]
   ```
   - **Why a custom keypad?** The system number pad has no minus key, and red Kings make negative hand values legal (PRD 4.3). It is plain SwiftUI `Grid` + `Button`, not UIKit.
   - **Auto-advance after two digits.** Hand values of 100 or more are not realistic, so "1", "4" moves straight to the next player. A single-digit value needs **Next**. Typing the knocker's row first is unnecessary: rows stay in seat order and the knocker's row is badged.
   - **`−` is a sign toggle**, allowed anywhere in the entry. **Validation:** the deck has only two red Kings, so −2 is the lowest possible hand. A value below −2 is blocked with an inline reason. A value above 60 asks "That's unusually high. Keep 64?" once.
   - **Card mode** (segmented toggle in the sheet header: *Total | Cards*): the keypad is replaced by a card palette (A 2–10 J Q K♠/♣ K♥/♦ Joker) and taps build the hand ("K♥ + 3 + 7 = 9"). This exists for learners (§7) and for disputed hands. The setting is remembered per user.
3. **Live preview.** Each row shows its round score as values come in ("→ −10", "→ 16"). A footer sentence states the outcome, for example "Noah's 2 is the lowest so far → successful knock, −10." It updates as later values come in ("Sam's 1 is lower → knock fails, 2 + 10").
4. **Save Round 5.** The sheet dismisses, the Table animates, and every device updates (§6).

**Edge cases**
- *Knocker ties the lowest*: preview "Tied with Ben at 4 → Cleo scores her hand, 4."
- *Knocker beaten*: "Sam's −1 is lower than Cleo's 2 → failed knock, Cleo scores 2 + 10 = 12."
- *Negative values*: shown with a true minus sign (U+2212) in a monospaced font, so "−1" and "1" never look alike.
- *Missing value*: Save stays disabled, and the empty row pulses once when Save is tapped.
- *Scorekeeper leaves*: anyone can **Hand off scorekeeping** from the menu, or simply tap **Record Round** (scorekeeper mode limits *who is expected* to record, not who is *allowed* to; trust comes from the audit log). If two devices record the same round offline, the conflict rule in §6.3 applies.

### 4.2 Self-report mode: Report Your Hand
Each player gets a compact sheet (`.medium` detent, so the standings stay visible):

1. **"Did you knock?"** A `Toggle` labelled **I knocked**, off by default.
2. A big hand-value readout and the same keypad (with Card mode). **Submit**.
3. After submitting, the sheet shows "Waiting on Cleo and Sam…" with checkmarks. Values stay **hidden until everyone has reported**, then all phones reveal the round together with one animation. This avoids "wait, you put 9?" mid-entry and gives the table a shared reveal moment.

**The knocker rule in self-report (exactly one knocker is required):**
| State when the last hand comes in | What happens |
|---|---|
| Exactly one "I knocked" | Round completes automatically, and scores are derived. |
| **Nobody** said they knocked | The round does not complete. Every phone shows "Who knocked?" with avatars, and the first tap on any device sets it. The choice is logged as "Ana marked Cleo as the knocker". |
| **Two or more** said they knocked | Every phone shows "Ana and Cleo both said they knocked. Who did?" The first answer resolves it, and the answer is logged. |

**Guests and players without the app:** their row reads **Report for Sam**. Anyone can tap it and enter Sam's hand, and the log records "Noah reported for Sam".

**Stragglers:** nobody gets a push. The Live Activity for unreported players switches to "Your hand for Round 5" with a **Report** button (App Intent that opens the sheet directly). If a player has stepped away, anyone can **Report for Ben** after 30 s.

### 4.3 What the app computes (PRD 2.6, applied in one pure function)
```swift
nonisolated func roundScores(hands: [PlayerID: Int], knocker: PlayerID) -> [PlayerID: RoundScore]
// lowestOther = min(hands except knocker)
// knocker.hand <  lowestOther → knocker: −10 (outcome .successful)
// knocker.hand == lowestOther → knocker: hand (outcome .tied)
// knocker.hand >  lowestOther → knocker: hand + 10 (outcome .failed)
// everyone else: their hand
```
The same function runs on every device and on the server, and it is unit-tested against the PRD's three worked examples. It is the only place scoring lives.

---

## 5. History, audit trail and corrections (PRD 4.4, 4.5)

### 5.1 History sheet
Opened from the Table's `clock.arrow.circlepath`. It is **one scrolling page with two parts**: the score grid, then the full Changes log under it. Keeping them on one page is deliberate, because a correction is never hidden behind a tab.

- **Rounds** is a **score grid**: rounds as rows, players as columns (5 × 58 pt fits 393 pt; 6–8 players scroll horizontally *inside* the grid, with the round column pinned). Each cell holds the round score. The knocker's cell carries a small `hand.raised.fill` and an outcome mark (✓ successful, = tied, ✗ failed). A total row is pinned at the bottom. Edited rounds have a small "Edited" tag on the row label. Tapping a row pushes **Round Detail**.
- **Round Detail**: each player's *hand value → round score*, the knocker and the outcome sentence, followed by that round's change history. The toolbar has **Edit** (hidden once the game is finished).
- **Changes**: the full chronological audit log for this game, covering edits, extend, end early, abandon, knocker resolution, "reported for", conflict resolutions, and seat claims. Each entry reads: avatar · "**Ben** changed **Sam's** hand in Round 4" · "1 → −1" · "9:41 PM" · and any downstream effect ("Sam's score 1 → −1. Cleo's knock still failed.").

### 5.2 Editing a round
1. Round Detail → **Edit** → the same Round sheet as recording, prefilled.
2. Change values or the knocker. The preview shows **before → after for every affected score**, including knock-outcome flips ("Cleo's knock: failed → successful, 12 → −10").
3. **Save Changes** shows a `confirmationDialog`: "Everyone at the table will see this change." → **Save Change**.
4. All devices: standings re-sort, a non-modal banner appears, the History row gets "Edited", and the Changes log gets an entry. The scoring function re-runs automatically (PRD 4.5).

### 5.3 Extend, end early, abandon (all logged, any player)
All three are in the Table's `⋯` menu:
- **Extend Game…** A small sheet with a `Stepper` ("Add 2 rounds → 10 total") → **Extend**. Log: "Noah extended the game: 8 → 10 rounds."
- **End Game Now…** A confirmation dialog: "End after Round 6 of 8? The game counts in everyone's stats." → **End Game**. This leads to the normal game-end moment, labelled "Ended early after 6 of 8 rounds".
- **Abandon Game…** A destructive confirmation dialog: "Abandon this game? It stays in history marked Abandoned and won't count toward any stats, leaderboards or achievements." → **Abandon**. There is no celebration. Every device returns to Play, and the game appears in history with an `xmark.circle` "Abandoned" label and its full log.

### 5.4 Finishing and immutability
When the last planned round is saved, the Round sheet does not dismiss to the Table. It shows:

> **That was the last round.**
> [ **Finish Game** ] (primary) [ Play Another Round ] · "Fix a round first"

**Finish Game** (any device) locks the game on all devices and starts the celebration everywhere at once. This one tap is the gate that makes "finished = immutable" safe: a typo in the final round can still be fixed before locking. If nobody taps it, the game finishes automatically after 15 minutes without activity, which is logged.

Once a game is finished, Edit disappears everywhere and Round Detail shows "Final. This game can't be changed." The server rejects later edits, and any offline edit that arrives late is recorded in the log as "Arrived after the game finished · not applied".

---

## 6. Offline play and resync (PRD 6.2)

### 6.1 Model
Every game is an **append-only operation log** (`GameCreated`, `PlayerSeated`, `RoundRecorded`, `RoundEdited`, `KnockerResolved`, `RoundsChanged`, `GameFinished`, `GameAbandoned`). Each operation has a UUID and a hybrid logical clock (HLC) timestamp. Each device stores the log locally (SwiftData) and derives the game state by folding operations in `(HLC, deviceID)` order. All devices sharing the same operations show the same score. The backend ingests operations idempotently by UUID, so retries never duplicate data.

### 6.2 Visible states: one pill, shown only when something is unusual
| State | Pill (Table title area) | Meaning |
|---|---|---|
| **Live** | *(none)* | Online, Realtime connected. |
| **Table sync** | `antenna.radiowaves.left.and.right` "Offline · 5 phones in sync" | No internet; Multipeer mesh holds everyone together. Everything works. |
| **This phone only** | `iphone` "Offline · saved on this phone" | No internet and no peers. Recording still works, and the round syncs to others when they reconnect. Self-report rows for unreachable players show "not connected" with **Report for…**. |
| **Catching up** | `arrow.triangle.2.circlepath` "Syncing…" | Reconnected. After catching up, a 3 s banner says, for example, "Caught up · 2 rounds from Ana's phone". |

The pill is a `Button` that opens a small popover describing the state in plain words. The Live Activity shows the same state as a single glyph.

### 6.3 Deterministic conflict rules (all written to Changes)
- **Concurrent edits to the same value**: the later HLC wins, and both edits stay visible: "Ben's and Cleo's edits to Round 3 crossed. Cleo's (later) was kept."
- **Two devices record the same round number offline**: the earlier HLC becomes Round N. The other is kept in the log as "Duplicate entry for Round 5 from Ben's phone (not applied)", with a **Use this version** action that creates an ordinary logged edit.
- **Edit vs Finish**: an edit whose HLC is after `GameFinished` is not applied (§5.4).
- **Abandon vs anything**: abandon wins, because it is the most conservative outcome for stats.

---

## 7. Rules and learning (PRD 4.7)

**Three layers, from lightest to deepest:**

1. **Learn Cambio in 2 minutes**: available on first launch and from Play → Learn. It is five paged cards (`TabView` `.page` style), each with one idea and one tiny interaction:
   1. *The goal*: lowest score wins. Four cards, face down, 2 × 2.
   2. *Card values*: tap cards to flip them and see their values; the lesson ends with "Red King = −1. Yes, it helps you."
   3. *Powers*: 7/8 peek own, 9/10 peek opponent, J/Q blind switch, black K look and switch.
   4. *Sticking*: an animated discard and stick.
   5. *The knock gamble*: three hands and the question "What does Ana score?", once each for successful, tied and failed. You answer by tapping −10 / 4 / 16. This screen teaches the rule the app enforces.
2. **Rules reference**: a `List` with sections (Setup, Card values, Powers, Sticking, Knocking, Scoring, Game end), searchable (`.searchable`). Available from Play and from the Table's book icon as a `.medium`/`.large` sheet over the live game.
3. **In-game reinforcement**:
   - **TipKit** tips in a user's first two games only: "Tap a score to see why", "Card mode adds up hands for you".
   - The **last round line** and **delta popovers** explain each knock outcome in a sentence.
   - **Card mode** in round entry turns scoring into practice with card values.
   - The Watch mode for late arrivals (§2.5) lets a newcomer learn by watching real scoring.

---

## 8. System surfaces (PRD 6.3)

### 8.1 Live Activity (ActivityKit)
Started automatically when a player's device joins a game, and ended (with a final-state update kept for 15 minutes) at finish or abandon.

| Presentation | Content |
|---|---|
| **Lock Screen / banner** | "Round 5 of 8" + segmented progress · top-five standings (rank, name, score, last delta), with your row highlighted · last-round line ("Cleo's knock failed · +10") · button **Record Round** (scorekeeper) or **Report Hand** (self-report), both App Intents. |
| **Dynamic Island: compact** | Leading: `R5/8`. Trailing: your rank and score, `3rd · 36`. |
| **Dynamic Island: minimal** | Your rank, `3`. |
| **Dynamic Island: expanded** | Leading: round and progress. Trailing: your score and delta. Bottom: top three plus you, the last knock outcome, and the **Record Round** button. |
| **Self-report "needs you"** | Content switches to "Your hand for Round 5" with **Report**. This is the one Live Activity update that uses an `AlertConfiguration` (a light, silent banner), and only on devices that have not reported. |

Updates arrive via ActivityKit push tokens (online) or local updates from the Multipeer-connected app (offline).

### 8.2 Widgets (WidgetKit)
| Widget | Families | Content |
|---|---|---|
| **Standing** | small, `accessoryCircular`, `accessoryRectangular` | Global rank and rating, with movement since last week. Under 5 games it shows instead a **ring "3 of 5 games to rank"**, the primary play-more nudge. |
| **Rivalry** | medium, `accessoryRectangular` | "You vs Ana · 5–12", last shared game, and "You've won the last 1". The rival is configurable (`AppIntentConfiguration`, default = nemesis). |
| **Next Achievement** | small | The closest unearned achievement with its progress ("Stable · 8 of 10 tablemates"). |

Widgets refresh on game finish (`WidgetCenter.reloadTimelines`) and otherwise daily.

### 8.3 Notifications: the complete set
Table First sends **four** kinds of notification, and **none of them reach a player who is sitting at a live table.**

| # | Notification | When | Interruption level |
|---|---|---|---|
| 1 | **"Noah added you to a table"** (+ Join action) | The host added you from Played With / Search while online, and you are not already in the game. | `.active` (default) |
| 2 | **"You made the leaderboard: #212"** | Your 5th completed game finishes. Delivered after the game, never during one. | `.passive` |
| 3 | **"Achievement: Late Charge"** (grouped if several) | A game finishes **and you were not in the app for the game-end screen** (you left early, phone died). Otherwise the game-end screen already showed it. | `.passive` |
| 4 | **"Sam claimed their Kedro history"** | A guest you added claimed their identity. This closes the "spreads to new tables" loop for the host. | `.passive` |

**Deliberately *not* notified, and why**
- **Nearby game you can join.** You are physically at the table and someone will say "open Kedro". Background discovery would also need persistent Bluetooth scanning, which costs battery and feels like surveillance.
- **Round recorded / standings changed.** The Live Activity already covers this silently. A push every round would turn the phone into the center of the table.
- **Self-report "your score is needed".** Handled by the Live Activity alert (§8.1) instead of a push, so it does not stack in Notification Center.
- **Edits.** Shown in-app (banner + log) to everyone at the table. Pushing edits implies suspicion.
- **"You were passed on the leaderboard", streak-at-risk, "we miss you".** These are re-engagement nags. They might lift short-term opens but erode trust in the product. The widgets give this information to people who want it, quietly.
- **Game ended.** You were there. Only if you left early does #3 cover what you missed.

---

## 9. Stats, rivalries, leaderboards and achievements (PRD 5)

All of these are derived from the operation log and finished games (PRD 5 intro), computed server-side as views or queries and cached on the device. Nothing is a maintained counter. Abandoned games are excluded everywhere, while early-ended games count fully.

### 9.1 You (profile + stats)
A pushed-style `List` (inset grouped) under a large header. Other players' public profiles use the same layout.

1. **Header**: horse avatar (§10.4) at 88 pt, display name, "#13 Global · Rating 1,586", and "+18 tonight" after a game. Under 5 games, the header shows the **rank progress ring** ("3 of 5 games to rank") instead.
2. **At a glance** (2 × 2 `Grid` of numbers): Games 24 · Wins 10 · Win rate 42% · Avg / round 7.3.
3. **Streaks**: Current win streak 1 · Longest 4.
4. **Knocking**: Knock rate 22% · Success 57%, plus a segmented bar for outcomes: 24 successful / 7 tied / 11 failed (Swift Charts `BarMark`, horizontal, stacked; the colors are backed by labels).
5. **Games**: Best game −6 · Worst game 92 · Avg / game 58.4. Each is tappable and opens that game.
6. **Nemesis**: "Ana · finished ahead of you 12 times", tappable to the head-to-head.
7. **Rivals**: the top 5 most-shared players, each with a finished-ahead record such as "5–12", tappable.
8. **Achievements**: an 8-badge preview and "13 of 22 · See All".
9. **Game history**: recent games with your place, final score and an "Abandoned" or "Ended early" label where relevant.

Every stat label has an ⓘ explanation (a popover with the PRD definition), because trust also applies to stats.

### 9.2 Head-to-head
Reached from any profile ("You vs Ana") or Rivals. Header: two avatars facing each other, with the overall finished-ahead record "5–12" (and "1 level") in large type.

| Row | You | Ana |
|---|---|---|
| Games together | 18 | 18 |
| Finished ahead | 5 | 12 |
| Wins in shared games | 4 | 8 |
| Knocks · successful / tied / failed | 9 / 3 / 5 | 14 / 2 / 3 |
| Average final score together | 61.0 | 44.2 |

The page ends with the list of shared games and a line generated from the data: "Ana is your nemesis. Your last win over her: tonight." (The data drives this line; nothing is decided by hand.)

### 9.3 Leaderboards

**Two scopes**, chosen with a segmented `Picker` in the navigation bar: **Global** | **Played With**.

**Recommendation (PRD 7a): one ranking attribute, Kedro Rating, plus a fixed set of "Records" category boards. No user-sortable columns.**

*Ranking.* Rows are ordered by **Kedro Rating**, a multiplayer Elo. Each finished game is scored as a pairwise result for every pair of players at the table (finishing ahead = win, equal = draw), with K scaled by 1/(n−1) so table size does not inflate swings. Everyone starts at 1500. The rating is **recomputed deterministically from the ordered history of finished games**, so it is a derived stat, not a counter (PRD 5): a guest claim correctly rewrites the history and the rating.

*Why a single rating rather than sortable columns:*
1. **One rank = one story.** "You're #14" is something you can say at the next table. With multi-sort, the answer to "what's my rank?" becomes "depends which column", which weakens both bragging rights and the play-more goal.
2. **Win rate is the wrong primary.** It rewards small samples (3–2 beats 40–25), punishes people who play at strong tables, and ignores how close a game was. Elo adjusts for opponent strength and stabilizes with volume, so it rewards playing more, which is PRD 5.4.
3. **Average score is not comparable** across games with different planned rounds.
4. **Less UI at a glance.** A sort menu is a control nobody needs while the leaderboard is meant to be *read*.
5. **Transparency is preserved.** An ⓘ "How rating works" sheet explains it in four sentences, and every game in your history shows its rating change ("+18").

*Records (the multi-attribute itch, without multi-sort):* Below the ranked list, a **Records** section lists category leaders, each a push to a top-25 board: **Win rate** (min 10 games) · **Knock success** (min 15 knocks) · **Longest win streak** · **Most games played**. Players who are not strong overall can still be #1 at something, and the main board stays simple.

*Eligibility (5 completed, non-abandoned games):*
- **Global:** the ranked list shows the top of the board, then a pinned **"You" row** (`.safeAreaInset(edge: .bottom)`) and your neighborhood (#12–14). Below the ranked list is a **"Not Yet Ranked"** section: "1,214 players are in their first five games". It shows players you have played with first, each with a **"3 of 5" progress ring and no rank number**. They are visibly part of the community, without a placement.
- **Played With:** the same ordering, among the people you have shared a table with. Sub-threshold players appear in the same "Not Yet Ranked" section at the bottom ("Dev · 3 of 5 games"), never interleaved and never given a number.
- **You under 5 games:** your pinned row reads "2 more games to rank" with the ring, instead of a number.
- Unclaimed guests never appear on leaderboards (PRD 3.3). Once claimed, they appear immediately with their full history.

### 9.4 Play-more incentives across the app (PRD 7b)

The principle is that **every surface answers "what happens if I play one more game?"**, and does so *between* games, never during one.

| Surface | Incentive |
|---|---|
| **Play tab** | Under 5 games: a progress card "2 games until you're ranked". Ranked: "3 points behind Cleo (#13)". After a game: a **Rematch** swipe action on the last game. |
| **Game-end screen** | Rating change ("+18 → 1,586"), movement ("You passed Cleo → #13"), the next goal ("Win 2 more in a row for Triple Crown"), newly unlocked achievements, and one big **Rematch** button. This is the highest-intent moment, so it gets the strongest prompt. |
| **Leaderboard** | Pinned "You" row with a neighborhood view (people just above you are reachable targets). "Not Yet Ranked" rings make the 5-game goal concrete. |
| **Profile** | Rank ring (under 5) and a "Next up" achievement row with a progress bar. |
| **Head-to-head** | A rivalry record ("5–12") with the nemesis named. Rivalries are the strongest reason to play *the same people again*. |
| **Widgets** | "3 of 5 games to rank", rank movement, and the rivalry score on the Home Screen. Ambient, not pushy. |
| **Achievements** | "Next up" shows the 3 closest unearned achievements with progress, and several achievements reward breadth (new tablemates, bringing a guest who claims), not only skill. |
| **Notifications** | Only *earned* moments (leaderboard entry, achievement) and no nags (§8.3). |

### 9.5 Achievement catalog (PRD 7c): 22 achievements

Achievements are evaluated **when a game finishes** (never mid-game, so a correction can't revoke something already announced), again on a guest claim, and they are derived from finished, non-abandoned games. Each is a single unlock with a progress bar where one applies. Names use light horse vocabulary for brand spirit, and every description uses plain Cambio terms.

| # | Name | Unlock rule | Category |
|---|---|---|---|
| 1 | **Out of the Gate** | Finish your first game. | Milestone |
| 2 | **First Past the Post** | Win a game (shared wins count). | Milestone |
| 3 | **On the Board** | Complete 5 games and earn a leaderboard rank. | Milestone |
| 4 | **Seasoned** | Complete 25 games. | Milestone |
| 5 | **Century** | Play 100 rounds. | Milestone |
| 6 | **Clean Knock** | Your first successful knock (strictly lowest → −10). | Knocking |
| 7 | **Hat Trick** | Three successful knocks in one game. | Knocking |
| 8 | **Steady Hand** | 10 successful knocks in a row over your career, with no tied or failed knock in between. | Knocking |
| 9 | **Thrown** | A failed knock (+10). Everyone gets one; it teaches the gamble. | Knocking |
| 10 | **Dead Heat** | Knock and tie for the lowest hand. | Knocking |
| 11 | **Red King's Favor** | Finish a round with a negative hand value (only a red King can do it). | Cards |
| 12 | **Clean Slate** | Finish a round with a hand value of exactly 0. | Cards |
| 13 | **Triple Crown** | Win 3 games in a row. | Streaks |
| 14 | **Thoroughbred** | Win 5 games in a row. | Streaks |
| 15 | **Late Charge** | Win a game in which you were not in the lead at the halfway round. | Moments |
| 16 | **Wire to Wire** | Lead (or share the lead) after every round of a game of at least 6 rounds, and win. | Moments |
| 17 | **Photo Finish** | Share a win (tied lowest final score). | Moments |
| 18 | **Dark Horse** | Win a game where every opponent had a higher Kedro Rating than you. | Moments |
| 19 | **Nemesis Tamed** | Finish ahead of your current nemesis. | Rivalry |
| 20 | **Stable** | Play with 10 different people. | Social |
| 21 | **Full Field** | Play a full 8-player game. | Social |
| 22 | **Bring One In** | Someone you played with as a guest claims their history. | Social |

Display: earned badges are an SF Symbol inside a circle, filled with the earner's coat color (§10.4). Unearned badges are outlined and gray, with a progress bar. Each badge pushes to a detail view with the date, the game it was earned in (tappable), and "Earned by 18% of players". Badges are public on profiles (PRD 5.5).

---

## 10. Visual identity

### 10.1 Restraint as identity
Kedro looks like a first-party Apple app that happens to belong to people who love a card game. Brand expression is concentrated in three places: **the avatar system**, **the color of the one primary action**, and **the game-end moment**. Everything else is system material.

### 10.2 Color
| Token | Light | Dark | Use |
|---|---|---|---|
| `kedroRed` (asset `AccentColor`) | `#C8102E` | `#FF5A6A` | Tint for the primary action, selected tab, and leader glyph. Contrast: 5.9:1 on white; 6.9:1 on black and 5.6:1 on `#1C1C1E`. |
| `kedroRedFill` | `#C8102E` | `#E0243B` | Background of filled buttons (white label). White on `#E0243B` is 4.7:1; the lighter `#FF5A6A` is only for red *text and glyphs* on dark, where white-on-it would fail. |
| `brandBackground` | `#0A0A0E` | `#0A0A0E` | Splash and first-launch only (existing asset). |
| Everything else | System semantic colors (`.primary`, `.secondary`, `.background`, `.secondarySystemGroupedBackground` via `Color(.secondarySystemGroupedBackground)` equivalents in SwiftUI `ShapeStyle`s) | — | — |

**Red never means "bad" in Kedro.** Deltas and knock outcomes use signs, words and symbols, never red or green. With **Increase Contrast**, the accent switches to `#A50D26` / `#FF7A87`.

### 10.3 Type
- **SF Pro** everywhere through text styles (`.largeTitle` … `.caption2`), so Dynamic Type works for free.
- **Scores** use `.monospacedDigit()` so columns do not jitter as numbers tick.
- **One justified exception: SF Pro Expanded** (`.fontWidth(.expanded)`, heavy) for the winner's name on the game-end screen and the onboarding headline. It is a system face (no bundled font), it echoes the forward motion of the gallop, and it appears only where it marks a moment.
- The script **Kedro wordmark** (existing logo asset) appears only on the splash and first-launch screens, never in navigation chrome.

### 10.4 Avatars: every player is a horse
- **Coat** (background color) chosen from real horse coats: Bay `#8A4B2A`, Chestnut `#B5562B`, Palomino `#D9A93F`, Grey `#8E8E93`, Black `#2C2C2E`, Dun `#B89A6A`, Roan `#9C6E74`, Buckskin `#C39A55`, Cremello `#E7D9BF`, Blue Roan `#5E6E86`.
- **Marking** (white face pattern): Blaze, Star, Snip, Stripe or None.
- Large sizes (≥ 44 pt) show a horse-head silhouette in profile with the marking. Small sizes (≤ 32 pt, such as list rows and the Live Activity) show the **initial on the coat color**, for legibility.
- **Guests have a dashed outline ring**: "not yet claimed". Claiming turns the ring solid, a small visual reward that also makes guest status obvious at the table.
- New accounts get a random coat and marking, and can pick their own in Settings. Duplicate coats at the same table are fine, because names and initials disambiguate.

### 10.5 Iconography
SF Symbols only, plus **one custom symbol**: `kedro.horse` (a horse-head silhouette exported as an SF Symbol template with weight variants). It is used for the leader marker, the app icon glyph, and achievement badges in the Moments category. Key symbols: `hand.raised.fill` (knock), `checkmark` / `equal` / `xmark` (knock outcomes), `book` (rules), `clock.arrow.circlepath` (history), `antenna.radiowaves.left.and.right` (table sync), `person.crop.circle.dashed` (guest).

### 10.6 Motion
| Moment | Motion | Reduce Motion |
|---|---|---|
| Round saved | Rows re-sort (`.smooth`), scores tick (`numericText`) | Crossfade, no movement |
| Self-report reveal | All values flip in together (a 0.25 s stagger by seat) | Simultaneous fade |
| Game end | A single **gallop line**: the horse silhouette crosses the header once (1.2 s) and leaves a hairline "finish" rule; then the winner name settles | Static horse and fade-in |
| Achievement unlock (game end only) | `symbolEffect(.bounce)` once | No bounce |

Nothing loops, and nothing animates during a live game except score changes.

---

## 11. Accessibility

- **Dynamic Type through AX5.** Standings rows switch from horizontal to stacked when `dynamicTypeSize.isAccessibilitySize`: name on line 1, score + delta on line 2. The score grid in History becomes a per-round `List` at accessibility sizes. Round-entry keypad keys grow up to 72 pt, and the grid stays 3 columns.
- **VoiceOver**
  - Standings rows are one element: "Ana, first place, leading, 20 points. Last round plus 16."
  - Knock rows: "Cleo knocked with 2. Failed knock: Sam had minus 1, which is lower. Cleo scores 12."
  - Keypad keys: "minus sign", "delete", "next player, Ana". The entry field announces "Sam, hand value, minus 1".
  - **Custom rotors** in History: *Rounds*, *Edited rounds*, *Knocks*.
  - Score changes post an `AccessibilityNotification.Announcement` on other devices only when VoiceOver is running: "Round 5 recorded. You are now 2nd."
- **Reduce Motion**: see §10.6. All motion has a non-motion equivalent.
- **Color and contrast**: every color-coded thing (knock outcome, guest status, leader, sync state) also has a symbol **and** text. Brand red meets 4.5:1 in both appearances, and there is an Increase Contrast variant. Avatars put a text initial on coat colors with ≥ 4.5:1 (white on dark coats, black on Palomino, Cremello and Dun).
- **Light and dark**: semantic colors throughout. The live Table is mocked in both appearances. The only fixed-dark surface is first launch.
- **Motor**: every action target is ≥ 44 pt, round-entry keys are ≥ 60 pt, and nothing depends on a long press or a gesture alone (every swipe action is also in a context menu).
- **Voice Control**: visible labels match accessibility labels ("Record Round 5").

---

## 12. SwiftUI implementation map

| Screen / feature | Native components and APIs | UIKit? |
|---|---|---|
| App shell | `TabView` with `Tab(…)`, `Tab(role: .search)`, `.tabViewBottomAccessory` (minimized game), `.tabBarMinimizeBehavior(.onScrollDown)` | No |
| First launch | `SignInWithAppleButton`, `@AppStorage` for first-run flag, `#if DEBUG` test sign-in | No |
| Play | `NavigationStack`, `List` sections (Nearby, Your Game, Recent), `.swipeActions` (Rematch), `ContentUnavailableView` for empty state | No |
| Nearby discovery / sync | **MultipeerConnectivity** (`MCNearbyServiceAdvertiser`, `MCNearbyServiceBrowser`, `MCSession`) wrapped in an `@Observable` `TableLink` actor-isolated service exposing `AsyncStream`s; **NearbyInteraction** (`NISession`) for "Right here" ordering; Info.plist `NSLocalNetworkUsageDescription`, `NSBonjourServices`, `NSNearbyInteractionUsageDescription` | No (not using `MCBrowserViewController`) |
| New Table | `.sheet` + `Form`, `Stepper`, `Picker(.segmented)`, `LabeledContent`, `.searchable` in Add Player | No |
| Table (live) | `.fullScreenCover`, `List(.plain)`, `.contentTransition(.numericText(value:))`, `.animation(.smooth, value:)`, `.safeAreaInset(edge: .bottom)` with `.buttonStyle(.glassProminent)`, `ToolbarItem`s, `.popover` for "why", `.sensoryFeedback`, `ProgressView` with custom `ProgressViewStyle` | **Yes, one property:** `UIApplication.shared.isIdleTimerDisabled` while the Table is visible. SwiftUI has no API to keep the screen awake. It is wrapped in a 10-line `IdleTimer` helper toggled from `.onAppear`/`.onDisappear` and `scenePhase`, with the required comment. |
| Round entry | `.sheet` + `.presentationDetents`, `Grid`/`GridRow` keypad of `Button`s, `@FocusState`-free custom focus (the keypad drives a selected-row binding), `Picker(.segmented)` Total/Cards, `.accessibilityRepresentation` | No |
| Self-report | `.sheet(.medium)`, `Toggle`, keypad, Realtime/Multipeer presence | No |
| History / audit | `ScrollView([.horizontal])` + `Grid` with pinned first column (`.scrollTargetLayout`), `List` section for Changes, `NavigationLink(value:)` → Round Detail, `.accessibilityRotor` | No |
| Corrections / extend / end / abandon | Round sheet reuse, `Menu`, `.confirmationDialog(presenting:)`, `Stepper` | No |
| Game end | `.fullScreenCover` content swap, `PhaseAnimator`/`KeyframeAnimator` for the gallop, `.fontWidth(.expanded)`, `ShareLink` (claim link, results card via `ImageRenderer`), `.symbolEffect(.bounce)` | No |
| Guest claim | Universal links via `.onOpenURL`, `.sheet`, `SignInWithAppleButton`, code entry `TextField` with `.textInputAutocapitalization(.characters)` | No |
| You / profile / public profile | `List(.insetGrouped)`, `Grid`, **Swift Charts** (`BarMark` knock outcomes, `LineMark` rating history), `.popover` stat definitions | No |
| Head-to-head | `List`, `Grid`, `LabeledContent` | No |
| Leaderboard | `List`, `Picker(.segmented)` in `.principal` toolbar, `.safeAreaInset(edge: .bottom)` for pinned You row, `Gauge(.accessoryCircularCapacity)` for "3 of 5" rings, `.refreshable` | No |
| Achievements | `LazyVGrid`, `ProgressView`, `.symbolEffect` | No |
| Learn / rules | `TabView` + `.tabViewStyle(.page)`, `List` + `.searchable`, **TipKit** (`Tips.configure`, `TipView`, `.popoverTip`) | No |
| Live Activity | **ActivityKit** (`Activity.request`, push token updates, `AlertConfiguration`), **WidgetKit** `ActivityConfiguration` with `DynamicIsland { expanded / compactLeading / compactTrailing / minimal }`, interactive `Button(intent:)` with **App Intents** | No |
| Widgets | **WidgetKit** `AppIntentConfiguration`, families `.systemSmall/.systemMedium/.accessoryCircular/.accessoryRectangular`, `WidgetCenter.reloadTimelines` | No |
| Notifications | **UserNotifications** (`UNUserNotificationCenter`, `interruptionLevel`, categories with Join action) | No |
| Persistence / sync | **SwiftData** (`@Model` Operation, Game cache), Supabase Realtime over `URLSessionWebSocketTask`, `NWPathMonitor` (Network framework) for connectivity | No |
| Settings | `Form`, avatar coat/marking picker (`LazyVGrid`), `Toggle`s | No |

**Total UIKit surface: one property (idle timer).**

---

## 13. Remaining edge cases (one line each)

- **3-player minimum** is enforced on Start. If a player leaves mid-game, their seat stays and someone records for them (the game's player set is fixed once Round 1 is recorded).
- **Shared win**: game end shows "Ana and Noah share the win". Both get the win, a Photo Finish check, and rating draws (PRD 2.7).
- **Ties in standings mid-game**: shared rank "2=" with both rows captioned identically.
- **Legacy web players**: they appear as guest identities in migrated games. The claim code is issued through whatever channel the migration uses, and claimed migrated games show a small "Imported" tag in history. They are immutable like any finished game.
- **Already-claimed link**: "This history has already been claimed." There is no way to claim it twice (PRD 3.2).
- **Claiming into an account that played in the same game** (the same person was added twice): blocked with the explanation "You're already in this game as Noah."
- **Kedro killed mid-game**: on relaunch, the Table reopens directly from the local log.
- **Debug test sign-in**: `#if DEBUG` only. A CI check fails any release build that contains the symbol.

---

## 14. Tap and time estimates

Assumptions: Kedro is already installed; "tap" counts screen touches including keypad keys; times are for a practised user, then a first-timer in parentheses.

### 14.1 Recording one round, 5 players, scorekeeper mode
Example hands: Noah 2 (knocker), Ana 9, Ben 6, Cleo 11, Sam 4.

| Step | Taps |
|---|---|
| **Record Round 5** | 1 |
| Tap the knocker (Noah) | 1 |
| Noah `2` + Next | 2 |
| Ana `9` + Next | 2 |
| Ben `6` + Next | 2 |
| Cleo `1` `1` (auto-advances) | 2 |
| Sam `4` | 1 |
| **Save Round 5** | 1 |
| **Total** | **12 taps, about 12–15 s** (25 s first time) |

Typical range: 11–15 taps depending on how many values are one digit. Self-report mode costs each player **3–4 taps** on their own phone (Report · [I knocked] · digits · Submit) **in parallel**, so wall-clock time is about **6–8 s** for the whole table.

### 14.2 Getting 5 returning players into a game
| Who | Steps | Taps |
|---|---|---|
| Host | New Table → (nearby played-with players already checked) → Start Table | 2 |
| Each of 4 others | Open Kedro → **Join** (auto-admitted) | 1 each (+ app launch) |
| **Total** | | **6 taps, about 10 s wall-clock**; 0 typing |

If one player is not discovered, add **2 taps** on the host's phone (Add Player → tap name).

### 14.3 A first-time guest joining
| Scenario | Steps | Taps / time |
|---|---|---|
| **Guest without the app** (most common) | Host: Add Player → Guest → type "Sam" (3 letters) → Add | **6 taps on the host's phone, about 8 s**; 0 for the guest |
| **Guest with a fresh install, no account** | Guest: Join a Table as a Guest → type name (3–4 letters) → Continue → **Join** on the nearby table · Host: **Admit** | **about 8 taps, about 20 s** (after install) |
| **Later, guest claims history** | Opens AirDropped link → Sign in with Apple (system sheet) → **Claim 1 game** | **3 taps, about 10 s**. With the on-device claim token (fresh-install path), it is automatic: **1 tap** (Sign in) |

---

## 15. Requirements traceability (summary)

| PRD | Where in this spec |
|---|---|
| 2.5 knocker required · 2.6 auto scoring | §4.1, §4.2 knocker table, §4.3 function |
| 2.7 planned rounds, extend, end early, shared wins | §2.6, §5.3, §5.4, §13 |
| 3.1 Sign in with Apple, debug-only test user, avatars | §2.7, §10.4, §13 |
| 3.2 guests and claim · 3.3 visibility | §2.4, §13, §9.3 (unclaimed guests not ranked), game-end ShareLink (§12) |
| 4.1 joining, host-led, played-with, rematch, 3–8, setup | §2 |
| 4.2 modes · 4.3 entry incl. negatives | §4 |
| 4.4 standings, deltas, history, progress, no sleep | §3, §5.1 |
| 4.5 edits, logging, immutability | §5 |
| 4.6 game end, early end, abandon | §5.3, §5.4, mockup 10 |
| 4.7 rules always available, learning, scoring reinforces rules | §7, §3.3 |
| 5.1–5.5 stats, H2H, leaderboards, play-more, achievements | §9 |
| 6.1 iOS 26 SwiftUI, accessibility | §11, §12 |
| 6.2 offline + sync | §6 |
| 6.3 Live Activity, widgets, notifications | §8 |
| 7 recommendations | §9.3 (a), §9.4 (b), §9.5 (c) |
| 8 brand | §10 |

### Game-end moment (PRD 4.6), in detail
Full-screen on every device simultaneously, triggered by **Finish Game** (§5.4):
1. Gallop line animation, then the **winner name in SF Pro Expanded**: "Noah wins" (or "Ana & Noah share the win"), with the final score.
2. **Final standings** with final scores and each player's rating change.
3. **Highlights**, three to four cards picked from: *Won on the final knock* · *Biggest comeback (4th after Round 3 → 1st)* · *Best round (−10, ×4 at this table)* · *Knocks tonight: 4 successful, 2 tied, 2 failed* · *Lowest hand (Noah 0)*.
4. **You** section: rating change, rank movement, newly earned achievements, next goal.
5. **Guests**: "Sam played as a guest" with **Send Sam's claim link** (`ShareLink`: AirDrop, Messages) and an 8-character code shown for reading aloud.
6. Actions: **Rematch** (primary) · Done · Share Results.

**Rematch**: one tap creates a new game with the same players, rounds and mode (and anyone queued in Watch mode, §2.5). The other devices get the familiar Join card, already at the top of their still-open Table, so it is **1 tap each**. Previously admitted players are auto-admitted.
