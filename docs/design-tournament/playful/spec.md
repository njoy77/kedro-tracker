# Kedro for iOS · "Horse Play" design spec

*Design tournament entry · playful track · October 2026 · companion file: `mockups.html` (19 frames + Dynamic Island sheet)*

---

## 0. The five bets

1. **One tap to sit down.** Phones at the same table find each other over the local network, so a returning player's whole joining step is a single **Join** tap. No codes, no typing, no internet needed.
2. **The app scores, the table plays.** Round entry is a keypad that moves to the next player on its own, with a live line that explains the knock outcome as you type. The app works out −10, the hand value, or +10 every time, and every score has a one-tap "Why?".
3. **Horses, not hierarchy.** Every player is a horse they designed. Standings show as a race toward a finish line where the lowest score leads. Leaderboard newcomers wait in **the Paddock** until their fifth game, and achievements are **Rosettes**. Brand words always come with plain words beside them, and gameplay words (knock, hand, round) are never renamed.
4. **Celebrate loudly, interrupt rarely.** A game ending gets a full **Winner's Circle**. The rest of the time Kedro stays on the Lock Screen and in the Dynamic Island and sends very few notifications.
5. **Teach by playing.** A five-minute course with a hands-on knock-gamble simulator. Coach tips inside the live game the first time something happens. A "Why?" on every score.

---

## 1. Design thesis

**Kedro should feel like the table's favorite horse: quick on its feet, generous with applause, and easy to approach for someone who has never played.** During a round the app is calm and quick: big numbers, a keypad that moves on its own, and one plain sentence explaining each knock. Between rounds and after the game it shows its personality: horses moving between race lanes, rosettes, a Winner's Circle, rivalries kept like racing form. Liquid Glass carries the controls (tab bar, toolbars, the Record button, the live-game accessory) so the game's content stays solid and readable underneath.

| PRD goal | How Horse Play serves it |
|---|---|
| **Fast table flow** | A keypad that moves to the next player after a clear digit (9 to 11 taps for a 5-player round). The knocker is one tap on a horse. A live outcome preview means no math and no second check screen. Self-report runs in parallel on every phone. The screen stays awake. |
| **Everyone joins** | Local-network discovery with Nearby Interaction ranking (the closest table comes first). People you have played with are let in automatically. Guests take about 2 host taps. New installs can join as a guest before making an account. |
| **People come back** | Paddock progress (0 to 5 horseshoes), Rating with weekly movement, rivalries ("Leo leads 8–6"), Rosettes with a "Next up" list, and widgets that show all of it on the Home Screen. |
| **Spreads to new tables** | A guest-first welcome when a nearby table is detected, a Learn course built for first-time players, Coach tips during the game, claim links over AirDrop, rosettes back-dated when a guest claims, and the Trainer rosette for bringing in new players. |

---

## 2. Vocabulary (brand words vs. game words)

Horse words name **places and rewards in the app**. They never replace game terms (PRD §8). The first time a brand word appears in any surface, its plain meaning goes with it.

| Brand word | Plain meaning shown with it | Never used for |
|---|---|---|
| **Your horse** | Your avatar | — |
| **Silks** | Your player color (ring around your horse) | — |
| **The Paddock** | "Players on their way to 5 games: not ranked yet" | — |
| **Kedro Rating** | Skill rating used for leaderboard rank | — |
| **Rosettes** | Achievements | — |
| **Winner's Circle** | Game-end screen | — |
| **Coach** | Teaching tips and the Learn course (mascot horse "Dash") | — |
| — | — | knock, knocker, round, hand, hand value, stick, peek, switch (always plain) |

Knock outcomes use plain labels with a horseshoe glyph (the glyph is a reinforcement, never the only signal):

| Outcome | Label | Glyph | Color token |
|---|---|---|---|
| Knocker strictly lowest | **Clean knock · −10** | horseshoe upright (luck held) | `outcomeClean` (green) |
| Knocker tied for lowest | **Tied knock · hand** | horseshoe on its side | `outcomeTie` (amber) |
| Someone lower than knocker | **Beaten knock · +10** | horseshoe upside down (luck ran out) | `outcomeBeaten` (rose) |

---

## 3. Information architecture and navigation

### 3.1 Root

```
RootView
├─ Onboarding (first launch, signed-out, or guest-on-device)
└─ MainTabView  (TabView + Tab API, iOS 26 floating Liquid Glass tab bar)
   ├─ Tab "Play"         house of the next game: nearby tables, start a table, recent games, paddock/rivalry cards
   ├─ Tab "Leaderboard"  Global | Played with, lenses, the Paddock
   ├─ Tab "Learn"        course, knock simulator, full rules, card values
   ├─ Tab "Me"           your horse, stats, rosettes, rivals, history, settings, claim a history
   └─ Tab(role: .search) players by name; recent opponents first
   + tabViewBottomAccessory: active-game capsule ("Noah's table · R5/8 · You 5th")
   + .tabBarMinimizeBehavior(.onScrollDown)
```

**Why Learn is a tab:** learnability is a top-level goal (PRD §1.1 "Spreads to new tables", §7 criterion 5). A new player should find the rules without knowing where to look. Rules are *also* one tap away inside every live game (book button in the toolbar).

**Why rivals are not a tab:** a rivalry lives between two people, so it belongs on profiles (Me → Rivals, any profile → "You vs …") and in surfaces you pass often (Play tab card, widget). That keeps the tab bar at four plus Search.

### 3.2 The live game ("the Table")

- The live game is a **`fullScreenCover`** called the Table. It is the only place the game is played. It hides the tab bar, keeps the screen awake, and shows one primary action at a time.
- Swiping down or tapping the chevron **minimizes** the Table into the `tabViewBottomAccessory` capsule, the way Music's mini player works. Tapping the capsule zooms it back (`navigationTransition(.zoom)`). You can look up a rule, check a rival, or answer a text and come back in one tap.
- Inside the Table: a `NavigationStack` with pushes for **Rounds & changes** (history + audit trail) and **Player in this game**; sheets for **Record round** (`.large`), **Edit round** (`.large`), **Rules** (`.medium`/`.large`), **Table code / invite** (`.medium`); and a toolbar `Menu` for **Add rounds**, **End game now**, **Abandon game**, **Take over scorekeeping**.
- Each tab owns its own `NavigationStack` with `navigationDestination(for:)` routes: `PlayerID`, `GameID`, `HeadToHead(a,b)`, `RosetteID`, `LessonID`. Any horse avatar anywhere opens that player's profile, and any profile shows "You vs them".

### 3.3 Deep links and entry points

| Entry | Lands on |
|---|---|
| `kedro.app/t/<table>` (universal link from a table QR or invite) | Join sheet for that table |
| `kedro.app/c/<claim>` (claim link) | Claim flow (§4.10) |
| Live Activity tap / Dynamic Island tap | Table, current state |
| Live Activity button "Record round" / "Report hand" (App Intent) | Table with the Record sheet open |
| Control Center control / widget button "Start a table" | Table lobby, hosting |
| "Added to a table" notification **Join** action | Joins directly, opens Table lobby |

---

## 4. Key flows

Sample cast used throughout (consistent with the mockups): **Noah** (you, bay horse, blue silks), **Mia** (palomino, magenta), **Leo** (black, green), **Priya** (grey, gold), **Sam** (guest, chestnut, dashed ring). The main sample game is "Noah's table", set up for 6 rounds and later extended to 8, with Noah as scorekeeper.

### 4.1 Joining a co-located table

**How discovery works**

- When a host taps **Start a table**, their phone advertises a Bonjour service (`_kedro._tcp`) over Wi-Fi and peer-to-peer Wi-Fi (`NWListener`, `includePeerToPeer = true`). The advertisement carries the table name, host horse, and a short-lived table token. It needs no internet connection.
- Every phone with Kedro in the foreground browses (`NWBrowser`). When it finds a table, it opens a connection and swaps Nearby Interaction discovery tokens. On UWB iPhones (iPhone 11 and later) the **closest table is ranked first** and labeled "right here" when it is within about 2 m. Otherwise tables are sorted by signal and arrival time.
- On the Play tab, a nearby table shows as a glass card that slides in: **"Noah's table · right here · Mia, Leo, Priya joined"** with a **Join** button. If exactly one table is found and it's within 2 m, the Join sheet opens by itself the first time (only once per table).
- A **two-word table code** (e.g., *Copper Pony*) and a QR code are shown in the lobby as a backup when local discovery is blocked, for example on a hotel network or with Local Network permission denied. The QR code is a universal link, so the system Camera opens it; Kedro needs **no in-app scanner**. Typing the code is the last resort: two words, with autocomplete from the horse word list.

**Edge case A: a table of returning players**

1. Host opens Kedro → **Start a table** (1 tap). The lobby opens, already advertising. Defaults come from the host's last game: rounds = last used (6) and mode = last used.
2. The four others open Kedro. The Play tab shows Noah's table → **Join** (1 tap each). Anyone the host has played with is **admitted automatically**, and each horse trots into the lobby as they arrive.
3. Host checks the lobby → **Start game** (1 tap).
4. *Variant:* if the host adds someone from the played-with row before they open the app, that person gets an "Added to a table" notification with a **Join** action (1 tap from the Lock Screen). If they open Kedro later instead, they see "You're in Noah's game · take your seat".

**Edge case B: a table with a guest (no app, no account)**

1. In the lobby, the host taps **Add guest** → types a first name → **Done**. Kedro gives the guest a random horse and silks that don't match anyone else's.
2. **Reusing guest identities:** if the name matches a guest who has played with anyone at this table before, Kedro suggests "Sam · guest · 3 games with you". Picking that (1 tap) keeps Sam's history building on one identity, so a later claim brings everything over.
3. In self-report mode, the guest's row appears on every phone as **"Report for Sam"**. Anyone can fill it in, and the first answer wins. The audit trail records "Reported by Noah".

**Edge case C: a first-time person who just installed Kedro**

1. On first launch, a permission primer explains Local Network ("to find tables around you") before the system prompt.
2. If a table is found, the Welcome screen leads with it: **"Noah's table is right here. Join as a guest"**. Sign in with Apple stays one button away, but it is not required to play.
3. **Make your horse:** type a first name; a random horse is pre-filled (with optional shuffle and customization) → **Join Noah's table**.
4. The host sees "Sam wants to join · Admit" (1 tap). Strangers are **never auto-admitted**.
5. The device now holds a **guest identity**. When Sam signs in with Apple later, that identity is claimed without a code, because the history lives on this device.

**Edge case D: mid-game join**

| Situation | Behavior |
|---|---|
| A player who is already in the game opens Kedro late, or their phone rejoins (dead battery, wandered off) | Join shows "Round 5 of 8 · take your seat". The phone downloads the whole event log from any peer and is up to date in under a second. No permission is needed because the seat is already theirs. |
| A guest seat is claimed by someone's phone ("I'm Sam, I just installed it") | Sam taps their own name on the Join sheet ("That's me"). The host approves (1 tap). The device takes over the guest identity, history included. |
| A **new player** asks to join after Round 1 has been recorded | **Not allowed.** The canonical rules don't cover late entry, and any starting score would be a house rule (PRD §1.3). The Join sheet says: "Noah's table is in Round 3. New players can join from the next game," and offers **Save my seat for the next game**. That puts the person straight into the rematch lobby (§4.9). They can follow the game as a **spectator** in the meantime (read-only Table). |
| A new player asks to join **before** Round 1 is recorded | Allowed. The host admits them and they start at 0 like everyone else. Logged as "Ava joined before Round 1". |
| Table is at 8 players | Join shows "Table is full (8/8)", offers spectating and **Save my seat for the next game**. |

### 4.2 Game setup (the lobby)

The lobby is one scrolling screen that **advertises while you set it up**, so players join while the host makes choices.

| Section | Contents | Default |
|---|---|---|
| Table | Table name ("Noah's table"), table code *Copper Pony*, QR button | Host's name |
| At the table | Seat-ordered horses (drag to match real seating, so entry order follows the table), each with a status: *Joined nearby*, *Added*, *Guest*, *Waiting to admit* | Join order |
| Add players | Played-with row (most recent and most frequent first, one tap each), **Search** (any Kedro user), **Add guest** | — |
| Planned rounds | Chips 4 · 6 · 8 · 10 plus a stepper (1–30) | Last used, else 6 |
| Scoring | Segmented: **Scorekeeper** (one phone enters everyone) / **Everyone reports** (self-report) | Self-report if every seated player is on their own phone; otherwise Scorekeeper |
| Scorekeeper | Shown in scorekeeper mode: who keeps score | Host |
| Coach tips | Toggle "New player at the table". Turns on Coach tips (§7.4) for this game, on every phone | Turns on automatically if anyone has fewer than 3 games |

The **Start game** button stays disabled with a reason ("Need at least 3 players", "Up to 8 players") until the table is valid. Starting locks the seat order for the scorekeeper's entry order, which can still be reordered from the Table menu. The Live Activity starts on every phone.

### 4.3 Recording a round: scorekeeper mode

The **Record round** sheet (`.large` detent, keypad pinned at the bottom):

1. **Who knocked?** A row of the table's horses in seat order. Tap one (1 tap) and a small knock badge appears on that horse. **The Record button stays disabled until a knocker is chosen**, and the reason is spelled out: "Pick who knocked".
2. **Hand values.** Players are listed in seat order, and focus starts on the first seat. A focus ring shows whose value is being entered, and tapping any row moves focus to it. The custom keypad has 0–9, **±**, and ⌫.
   - **Auto-advance:** focus moves to the next player after a digit that can't be the start of a realistic hand (0, 6–9), after any two digits, or after ±digit (a hand can't go below −2). After 1–5 it waits a moment for a second digit, or you tap **Next**. A value above 59 (rare) is entered by tapping the row again, which adds another digit.
   - **±** works at any point (before or after the digit) and flips the sign. Negative values show a small red-king hint: "Below zero: Red Kings at work".
   - **Cards mode** (toggle above the keypad) replaces the keypad with card chips (A–10, J, Q, K♠/♣, K♥/♦, Joker) and adds them up as you tap. Good for learners and for disputed hands.
3. **Live outcome line** above the keypad, updated with every digit: "Leo knocked with 4, lowest so far. Clean knock (−10) if no one has under 4." Once all values are in, it settles to one of the three outcomes with its glyph and color. Each row shows the **round score** that will be recorded on the right: the knocker's row shows −10 / hand / hand+10.
4. **Record round 6** (1 tap). The sheet closes, totals count up (`.contentTransition(.numericText())`), horses trot to their new lanes, and the outcome banner shows the knock result. A clean knock plays a success haptic, and a beaten knock makes the knocker's horse do a small bucking wiggle.

**Validation (soft, never blocking):** a hand under −2 → "Only two Red Kings in a deck. Sure?"; a hand over 50 → "That's more than four cards' worth. Sure?". **Hard requirements:** exactly one knocker, and a whole-number value for every player.

**Scorekeeper continuity:** if the scorekeeper's phone dies, anyone can choose **Take over scorekeeping** from the Table menu (logged). Non-scorekeepers see "Noah is keeping score" where the Record button would be. They can still edit any recorded round (PRD §4.5).

### 4.4 Recording a round: self-report mode

1. When a round ends at the table, any phone can tap **Round 6: report hands**. Every phone also offers the report card on its own after the previous round is recorded, so in practice nobody taps to open it.
2. On **my phone**: a keypad (or Cards mode) for **my hand**, plus an **I knocked** toggle with the knock glyph → **Send my hand** (2 to 3 taps total).
3. **Starting gate:** a strip shows every player's horse "in the gate" with ✓ when reported. **Values stay hidden until everyone has reported**, then the gates open together. This stops anyone from adjusting to what others entered, and the reveal is a small moment of drama.
4. **Guests:** "Report for Sam" appears on every phone. Whoever taps first takes the guest's row, and the others see "Noah is reporting for Sam".
5. **Knocker rules (the round can't close without exactly one):**
   - Nobody toggled *I knocked* by the time all hands are in → every phone shows **"Who knocked?"** with the horses. The first tap closes the round (logged as "knocker set by Mia").
   - Two people toggled *I knocked* → the round stays open with a **"Two knockers: Mia or Leo?"** prompt on every phone. Any player resolves it (logged with both claims).
6. **Stragglers:** a player who hasn't reported after 20 s while the app isn't on screen gets a Live Activity update ("Your hand for Round 6"), not a separate notification (§10.3). Anyone at the table can tap the straggler's row → **Report for Jules** (logged as reported-by).
7. When the last hand arrives, the round closes and scores are applied on every phone at the same moment, the same as in scorekeeper mode.

### 4.5 Live standings and last-round deltas

The Table screen, top to bottom:

1. **Toolbar (glass):** minimize chevron · title "Noah's table" · Rules (book) · Menu (…).
2. **Round progress:** a row of horseshoes, one per planned round, with completed ones filled: "Round 5 of 8 · 3 to go". After the final round it reads "Final check".
3. **The race strip:** one track with each horse placed by cumulative score, **lowest score at the finish flag**, so gaps can be seen at a glance. Labeled "Lowest score leads".
4. **Last round banner:** "Round 5 · Sam knocked with 2, lowest at the table → Clean knock −10" with an upright horseshoe. Tapping **Why?** opens the explanation (§7.3).
5. **Standings card:** one row per player with rank, horse, name (+ *You* / *Guest* tags), rank movement (↑2 / ↓1), **last-round delta chip** (+9, +12, −10 with knock glyph), and the **cumulative score** in large rounded numerals. The leader's row gets a gold rosette and "Leads by 7". Ties show the same rank with "=".
6. **Primary action (glass prominent):** *Record round 6* (scorekeeper) / *Report your hand* (self-report) / "Noah is keeping score" (others). The secondary button is **Rounds & changes**.
7. **Sync chip** (only when something's unusual): see §4.11.

The screen never sleeps while it's on screen and the game is active (`isIdleTimerDisabled`, §12 flags this). The lock is released when the Table is minimized or the game ends.

### 4.6 Round history and the audit trail

**Rounds & changes** (pushed in the Table) has two parts that share one scroll:

- **The grid:** players as rows, rounds as columns, totals pinned on the right. Each cell shows the round score, and the knocker's cell has the knock glyph tinted by outcome. An edited cell has a small pencil dot. Tapping a column opens **Round N detail**: hand values, knocker, outcome sentence, who recorded it, and **Edit round**.
- **Changes:** a reverse-chronological log of *every* change to the game:
  - round edits: who, when, the field **before → after**, and the score effect ("Noah's score −10 → 14 · Noah's total 18 → 42 · 1st → 5th");
  - planned-round changes ("Priya added 2 rounds · 6 → 8"), ended early, abandoned, restored;
  - scorekeeper handovers and "reported for" entries;
  - **sync events** and **conflict resolutions** ("Two phones edited Round 2 while apart. Kept Leo's (made later); Mia's change is shown as replaced").
- A new change made by someone else shows a one-line banner on every phone: "Mia edited Round 3 · View". It stays up for 6 s and is posted as a VoiceOver announcement. Edits are never silent.

### 4.7 Corrections

- **Anyone in the game** can tap any round → **Edit round**. The sheet is the Record sheet filled with the current values, plus a **Before → After preview** at the bottom: each affected player's round score and total, and any change in rank.
- Changing the knocker or any hand value **re-runs the scoring rules** right away, and the outcome line explains the new result.
- **Save change** shows "Everyone at the table will see this change." There is no extra confirmation dialog, because the audit trail is the safety net and an undo toast stays for 8 s.
- An edit from a phone that's offline goes into the local log and merges when the phones reconnect (§4.11).
- **Finished games are read-only.** The edit buttons are gone and the grid shows a lock with "Final · Oct 24, 9:12 PM".

### 4.8 Extending, ending early, abandoning

All three are in the Table menu, are available to **any player**, and are logged.

| Action | Flow | Result |
|---|---|---|
| **Add rounds** | Menu → Add rounds → +1 / +2 / custom → Save | Planned rounds go up. The horseshoe row grows and the Live Activity updates. Logged "Priya added 2 rounds · 6 → 8". It can be undone by lowering the count back toward the original, but never below the number of rounds already played. |
| **End game now** | Menu → End game now → sheet showing current standings as the final result, "Counts fully in stats" → **End game** | The game goes to *Final check* (below). A partly reported self-report round is discarded (logged). |
| **Abandon game** | Menu → Abandon game → destructive confirmation: "Abandoned games stay in history marked *Abandoned* and don't count toward stats, leaderboards or rosettes." → **Abandon** | The game is marked Abandoned on every phone and the Live Activity ends. **Any player can tap "Restore game" for 15 minutes**, which is logged. This protects against a sore loser voiding a game. |

**Final check (recognizing the end).** When the last planned round is recorded, Kedro doesn't lock the game right away, because finished games are permanent. The Table changes to **Final check**: final standings, "Last chance to fix a round", and two actions: **Finish game** (anyone) and **Add rounds**. The game finishes when someone taps Finish, or after **3 minutes with no edits**, whichever comes first. A countdown ring on the Finish button makes the deadline visible. Then the Winner's Circle opens on every phone at the same time.

### 4.9 The game-end moment and rematch

**Winner's Circle** (full screen on every phone):

- The winner's horse rises into a gold rosette wreath while rosettes fall like confetti and a success haptic plays. **Co-winners** share the wreath ("Dead heat! Priya and Leo share the win"), and both get full win credit.
- **Final standings** with totals and medal positions.
- **Highlights** (worked out from the rounds and ranked, at most 4): Best round (lowest round score, e.g., "Priya −10 in R4 with a −1 hand: double Red King"), Clean knocks ("Priya 2 for 2"), Biggest comeback ("Leo 4th → 2nd in the last 3 rounds"), Ouch ("Mia's R7 knock beaten by Noah's 3: +10").
- **Your progress** (personal to each phone): rating change, rank movement, Paddock horseshoes (+1), rosettes earned in this game (each one flips in), streak.
- **Guests:** a card per guest, "Send Sam their history", which opens the share sheet (AirDrop first) with the claim link and code (§4.10).
- **Actions:** **Rematch** (glass prominent) · Share result (an image card made with `ImageRenderer`, the race strip plus the winner) · Done.

**Rematch:** one tap from anyone creates a new lobby with **the same players, seat order, planned rounds, and mode**, and the starting seat moves one place clockwise. Every phone still on the Winner's Circle **moves into the rematch lobby on its own**, with a 5-second **Sit this one out** button. Guests come along on the same guest identities. "Saved seats" from people who arrived mid-game (§4.1 D) are added automatically. The host taps **Start game**, so the full rematch costs **2 taps** across the whole table.

### 4.10 Guest claim (link or code)

- **Issuing:** each guest identity has one claim credential: a link `kedro.app/c/7H4Q-PXMA` and the same 8-character code (Crockford base32, which avoids look-alike characters). It is offered at game end and can be found again later in that game's detail ("Claim link for Sam"). It is shared with `ShareLink`, so AirDrop, Messages, or any app works. Re-issuing it (for a lost link) replaces the old one.
- **Offline:** the credential is created on the phone and registered when the game uploads. Until then the share card reads "Link works once this game syncs".
- **Claiming:** opening the link launches Kedro, or the App Store and then Kedro. After sign-in the **Claim** screen previews the history: "Sam · guest · 3 games · 1 win · played with Noah, Mia, Leo, Priya" and "You'll earn 3 rosettes · 2 games to the leaderboard". **Claim my history** merges it in, recomputes the derived stats, back-dates rosettes to the games they came from, and sends a "Welcome to the herd" moment.
- **Already claimed:** "This history has already been claimed" (no details, nothing to guess). **Wrong code:** "That code doesn't match a guest" (rate-limited).
- **Me → Settings → Claim a history** takes a code by hand. This is also how **legacy web players** claim their migrated histories (PRD §9).
- **Visibility:** an unclaimed guest has no profile page. Tapping a guest's horse shows only "Sam · guest · in this game" (PRD §3.3). Guests don't appear on leaderboards until claimed.

### 4.11 Offline play and resync

**Model:** each game is an **append-only event log** (GameCreated, PlayerSeated, RoundRecorded, HandReported, RoundEdited, RoundsChanged, GameEnded, GameAbandoned, GameRestored). Every event has a UUID and a hybrid logical clock stamp `(HLC, deviceID)`. Phones at the table connect directly to each other over the same peer-to-peer link used for discovery and gossip events to each other, so **the whole game works without internet**. When any phone has a connection, it uploads the log, and uploads with the same UUID are ignored, so nothing gets duplicated.

**Deterministic conflicts:** two edits to the same field → the later `(HLC, deviceID)` wins, and the other is kept in the audit trail as *replaced*. Two phones recording "Round 6" while apart → the earlier one becomes Round 6, and the later one is applied as an **edit** of Round 6 and flagged with a review banner ("Two phones recorded Round 6 while apart · Review"). Ending and abandoning stand over later round events, and a Restore event overrides an Abandon.

**States shown to players** (the chip sits under the progress row and appears only when something is unusual):

| State | Chip | Meaning |
|---|---|---|
| Online, in sync | *(no chip)* | Normal. Saying nothing is the reassurance. |
| No internet, table linked | **Offline · 5 phones linked** (link glyph) | Fully playable. Everyone is in sync with each other. |
| This phone separated from the table | **Only on this phone** (amber) + "Move closer to the table to sync" | Edits here are kept locally, and scores may be stale. |
| Reconnecting | **Syncing…** | Short-lived. |
| Back online after offline play | **Synced** ✓ (fades after 3 s) + audit entry "Synced · 2 rounds uploaded" | — |
| Game finished offline | Winner's Circle shows **"Final. Uploads when online"**; rating changes and leaderboard rosettes show as *pending* | The result is fixed. Only the derived global numbers wait. |

---

## 5. Stats, head-to-head, leaderboards, rosettes

All numbers are computed from finished, non-abandoned games and their rounds (PRD §5). The design never shows a stored counter, so corrections and claims always produce correct numbers.

### 5.1 Profile (Me, and any public profile)

1. **Header:** large horse portrait with silks ring, name, **Kedro Rating 1,108 · #142 global** (or the **Paddock** card "3 of 5 games" with horseshoes), and a streak pill when the current streak is at least 2.
2. **Rosette shelf:** three pinned rosettes plus "14 of 25".
3. **Stats grid** (2 columns, a single column at accessibility sizes): Games 23 · Wins 6 · Win rate 26% · Avg per game 41.3 · Avg per round 5.2 · Best game 18 · Worst game 71 · Current streak 0 · Longest streak 3 · Knock rate 18% · Knock success 55%.
4. **Knock outcomes bar:** a stacked bar 18 clean / 4 tied / 11 beaten, labeled with counts (not only color).
5. **Nemesis card:** "Leo: finished ahead of you 8 times". Opens head-to-head.
6. **Rivals:** most-played opponents with their head-to-head records.
7. **Game history:** a list (wins marked with a rosette, abandoned games marked *Abandoned* in grey and labeled "not counted").
8. On someone else's profile, a **"You vs Leo"** card is pinned at the top.

### 5.2 Head-to-head

"You vs Leo": two horses nose to nose over a split bar. Big record **Leo 8 · 6 You**, labeled *finished ahead*. Below that: games together 14 · wins in shared games Leo 4 · You 3 · knock outcomes when facing each other (You: 5 clean · 1 tied · 3 beaten; Leo: 4 clean · 2 tied · 1 beaten) · recent shared games, each with both finishing positions. Footer hook: **"2 games to level it"**, with **Start a table** pre-filled with Leo.

### 5.3 Leaderboards

- **Segmented:** **Global** | **Played with** (you ranked among everyone you've shared a table with).
- **Lens chips:** **Rating** (default, official rank) · Win rate · Avg round · Knock success · Longest streak.
- **Rows:** rank, horse, name, primary value, games played, weekly movement (↑6).
- **Your row** is pinned at the bottom of the screen when you're scrolled away from it.
- **The Paddock** section comes after the ranked list: "**The Paddock** · On their way to 5 games: not ranked yet". It shows horses with horseshoe progress ("Ava · 3 of 5"), **no rank number**, sorted by games played. On Global, the Paddock is collapsed to a count ("+2,341 players in the Paddock") with your played-with Paddock friends listed. On Played-with it shows every friend in the Paddock.
- **If you are in the Paddock:** the board shows a header card: "You're in the Paddock: 2 more games to take your place on the Track", with your projected starting rating band.

### 5.4 Rosettes (achievements)

The Rosettes grid groups by category (Wins, Knocks, Moments, Herd, Track, Learning). Earned rosettes are in full color with the date and game. Locked ones are outlines with a progress ring ("23/25"). **Next up** (the top 3 closest to unlocking) sits at the top. Rosettes are public on profiles. Tapping one shows its rule, the date earned, the game it came from, and the share of players who hold it. The full catalog is in §8(c).

---

## 6. Rules and learning

### 6.1 Learn tab

1. **"Cambio in 5 minutes"**, a course of six short lessons, each a swipeable card stack with a single interaction:
   1. *Card values*: flip cards to see points. Ends with a quiz: "♥K + Joker + 4 = ?" (answer 3).
   2. *Peeks & switches*: the four power-card types, each with a little animated grid.
   3. *Sticking*: drag a matching card onto the discard.
   4. *Knocking*: one more turn for everyone, then reveal.
   5. *The knock gamble*: the **knock simulator** (§6.2).
   6. *Your first game*: what Kedro will ask you and when. "Start a table with Coach tips" button.
2. **Knock simulator** (also standalone): two sliders, *your hand* and *lowest other hand*, with the outcome shown live as the horseshoe flips: clean −10 / tied hand / beaten hand+10, plus "Should you knock?" guidance ("Knocking at 4 or less wins most of the time at a 5-player table").
3. **Rules reference:** the full canonical ruleset from PRD §2, in sections, searchable (`.searchable`), with the card-value table and the knock scoring table. It works offline because it ships in the app bundle.
4. **Card values quick card**: a single image-like card, also used as the Rules sheet's first detent in-game.

### 6.2 In-game teaching

- **Rules sheet** (book button, always in the Table toolbar): it opens at a `.medium` detent showing the card values plus the knock table, and drags up to the full reference. The game keeps running behind it.
- **"Why?" on every score:** tap any delta chip, grid cell, or the last-round banner and a popover explains it in one sentence with the numbers:
  - Clean: "Leo knocked with 4. Everyone else was higher (next lowest: Sam, 6). Clean knock: −10, hand ignored."
  - Tied: "Leo knocked with 5 and Priya also had 5. A tie isn't a clean knock, so Leo scores his hand: 5."
  - Beaten: "Noah knocked with 4, but Mia had 2. Beaten knock: hand + 10 = 14."
- **Coach tips** (TipKit, on when the game's "New player at the table" toggle is on): shown **once each** at the first knock ("Knock outcomes explained"), the first beaten knock, the first negative hand ("Red Kings are −1"), and the final round. They show *between* rounds, never over the keypad during entry.
- **Rosette for learning:** *Pupil* (§8c) rewards finishing the course.

---

## 7. System surfaces

### 7.1 Live Activity (Lock Screen) and Dynamic Island

Started on **every phone** in the game at Start. Updated by ActivityKit push when online and by local updates from the app (including peer-to-peer events) when offline. The `staleDate` shows "Updated 2 min ago" if a phone loses contact. It ends 10 minutes after the Winner's Circle, showing the winner.

| Presentation | Content |
|---|---|
| **Lock Screen** | Title "Noah's table" + horseshoe progress "R5 of 8". Leader "Mia · 20". **You: 5th · 42 (+5)**. Last round "Sam knocked: clean −10". Button **Record round 6** (scorekeeper) / **Report your hand** (self-report), using an App Intent that opens the Record sheet. |
| **Compact** | Leading: progress ring with "5/8". Trailing: "5th · 42". |
| **Minimal** | Progress ring with your rank in the center. |
| **Expanded** | Leading: your horse + rank. Trailing: the leader. Center: the last-round sentence. Bottom: the primary button. |
| **Self-report waiting** | "Your hand for Round 6" + "3 of 5 in" (an alert update with sound off: a quiet nudge). |
| **Final** | Winner's horse in a rosette, "Priya wins · 32". |

### 7.2 Widgets (WidgetKit)

| Widget | Sizes | Content |
|---|---|---|
| **Rank** | small, Lock Screen circular | Rating rank "#142 ↑6", or Paddock horseshoes "3/5" |
| **Rivalry** | medium | Your top rival: "Leo leads 8–6", last shared game, **Start a table** button (App Intent) |
| **Next rosette** | small, Lock Screen rectangular | The closest rosette with a progress ring ("Workhorse 23/25") |
| **Played-with board** | large | Your five nearest neighbors on the played-with board, you highlighted |
| **Start a table** | Control Center control (`ControlWidget`) | One tap to host |

Widgets update when a game finishes or a rating is recomputed. They never refresh on a timer just to look busy.

### 7.3 Notification set

Kedro sends **five** kinds of notification. Each one passes the test: *does this help a person get to, or stay in, a game they're physically part of, or mark something they'd want to know at most once?*

| # | Notification | When | Interruption level | Why it earns a buzz |
|---|---|---|---|---|
| 1 | **Added to a table:** "Noah added you to his table · Join" | The host adds you from played-with while your app is closed | Time-sensitive | You're sitting at that table right now. One tap seats you. |
| 2 | **Your hand is needed:** "Round 6 · 3 of 5 in" | Self-report, you haven't reported 20 s after the round opened, and the app isn't on screen. **Delivered as a Live Activity alert update when an activity exists**, and as a notification only as a fallback | Active, sound off | Without it the round stalls. |
| 3 | **Game final:** "Priya wins Noah's table · 2 rosettes for you" | The game finishes and your phone wasn't on the Winner's Circle (pocketed, left early) | Passive | Closes the loop. It **bundles** that game's rosettes and rating change so there's one notification, not four. |
| 4 | **You're on the Track:** "5 games done. You're #212 on the leaderboard" | Once, when you leave the Paddock | Active | The biggest progress moment there is. Happens once. |
| 5 | **History claimed:** "Sam claimed their history · your rivalry now counts" | A guest you played with claims | Passive | Low-key good news that unlocks new rivalry stats. |

**Deliberately not notified (and why):**

- *Every round recorded / every edit:* the players are at the table looking at it. Edits show as an in-app banner plus the audit log.
- *"A game is happening near you":* Kedro can't reliably sense proximity in the background without draining the battery, and a stranger's table isn't an invitation. Nearby tables show when **you** open the app.
- *Rank drops, someone passed you, friends' wins:* negative or competitive noise that sends people away instead of back to the table.
- *Streak at risk, "we miss you", daily reminders:* guilt mechanics go against "the table comes first".
- *Individual rosettes:* bundled into the Game final notification or shown in the Winner's Circle.

All notifications support Focus filters and grouping by game (`threadIdentifier = gameID`).

---

## 8. Required recommendations

### (a) Leaderboard presentation and ranking

**Recommendation: one official rank, from a single skill rating (Kedro Rating), plus optional "lenses" that re-sort by other stats without replacing the rank.**

- **Kedro Rating.** A multiplayer Elo computed from finishing order. Each finished game counts as pairwise results between every pair of players (a finish ahead = win, the same final score = draw), with K = 32 ÷ (players − 1) so an 8-player game moves ratings about as much as a 3-player game. Everyone starts at 1,000. It is **replayed from the full game history in finish-time order** (deterministic), so it stays a derived stat: corrections, claims, and migrated games produce the right number on recompute.
- **Eligibility.** Rank is shown only after 5 completed, non-abandoned games. Before that, players are in **the Paddock** with no rank, and their provisional rating is never shown, so nobody's "first number" is a bad one.
- **Lenses** (Win rate, Avg round, Knock success, Longest streak) re-sort the same eligible players and show a lens position ("3rd · Win rate"). The official **#** next to a name is always the rating rank. Lenses with small samples have their own floors (Knock success needs at least 10 knocks), shown in a footnote.

**Why not win rate as the single rank:** at a 3-player table the baseline win rate is 33%, and at an 8-player table it's 12.5%, so win rate rewards small tables and lucky short careers. **Why not average score:** it depends on the planned number of rounds, and per-round averages ignore who you played against. **Why not fully multi-sort with no official rank:** five equal sorts means five #1s and no single number to climb, which weakens the play-more loop (§5.4). **Rating** accounts for table size and opponent strength, rewards playing more without punishing new players (the Paddock shields them), and gives one clear number to chase. Lenses keep the stats fans happy and give everyone something they can be best at.

### (b) Play-more incentives

Spread across the whole app, never guilt-driven:

| Surface | Incentive |
|---|---|
| **Paddock progress** (Play tab card, profile header, Leaderboard header, Rank widget, Winner's Circle) | Five horseshoes fill one per game: "2 more games to take your place on the Track". The most visible goal for anyone new. |
| **Winner's Circle → Your progress** | Rating change, rank movement, horseshoe +1, rosettes flipping in, streak. Every game, even a loss, ends with visible progress. |
| **Rematch** | 2 taps for the whole table, with automatic re-seating. The cheapest possible "one more". |
| **Rivalries** | Head-to-head records on profiles, the Rivalry widget, and "2 games to level it" with a pre-filled table. |
| **Played-with board** | Being close to friends motivates more than the global board: "12 rating points behind Mia". |
| **Rosettes: Next up** | The three closest rosettes with progress rings, on Me and in the widget ("Workhorse 23/25"). |
| **Streak pill** | Shown in the lobby and on profiles when the streak is at least 2. Celebrated, never mourned (no "streak lost"). |
| **Coach mode + Trainer rosette** | Gets experienced players to bring new people in. A new player's first game is made easy, which helps the table grow. |
| **Guest claim** | A claim brings back-dated rosettes plus "2 games to the leaderboard". A guest's first look at their account is already progress. |
| **Monthly ride report** (in-app card on Play, not a notification) | "October: 9 games, 3 wins, best round −10 ×4, new rival: Jules." |

### (c) Achievement catalog: 25 Rosettes

All are derived from finished, non-abandoned games, awarded when a game finishes (or when a claim is recomputed, back-dated), and kept permanently once earned.

| # | Rosette | Category | Unlock rule |
|---|---|---|---|
| 1 | **First Ride** | Milestone | Complete your first game. |
| 2 | **Winner's Circle** | Wins | Win a game (shared wins count). |
| 3 | **Dead Heat** | Wins | Share a win (tie for lowest final score). |
| 4 | **Photo Finish** | Wins | Win by exactly 1 point over second place. |
| 5 | **Wire to Wire** | Wins | Lead (alone or tied) after every round of a game of 4+ rounds, and win it. |
| 6 | **Dark Horse** | Wins | Win a game in which you were alone in last place after any round past the halfway point. |
| 7 | **Triple Crown** | Wins | Win 3 games in a row. |
| 8 | **Unbridled** | Wins | Win 5 games in a row. |
| 9 | **Clean Knock** | Knocks | Your first successful knock (−10). |
| 10 | **Iron Nerve** | Knocks | Three clean knocks in one game. |
| 11 | **Neck and Neck** | Knocks | Knock and tie for the lowest hand. |
| 12 | **Bucked Off** | Knocks | Your first beaten knock (+10). Everyone gets thrown once. |
| 13 | **Red Rider** | Moments | Record a negative hand value (only a Red King can do it). |
| 14 | **Ghost Hand** | Moments | Finish a round with a hand value of exactly 0. |
| 15 | **Marathon** | Moments | Complete a game of 12 or more rounds. |
| 16 | **Workhorse I / II / III** | Milestone | Complete 25 / 50 / 100 games. |
| 17 | **Out of the Gate** | Track | Complete 5 games and take your place on the leaderboard. |
| 18 | **Podium** | Track | Reach the top 3 of your played-with board (Rating) after a game. |
| 19 | **Grand National** | Track | Reach the global top 100 (Rating). |
| 20 | **Herd I / II** | Herd | Play with 10 / 25 different people (account holders or claimed guests). |
| 21 | **Full Stable** | Herd | Complete an 8-player game. |
| 22 | **Old Rivals** | Herd | Complete 10 games with the same player. |
| 23 | **Turned the Tables** | Herd | Finish ahead of your current nemesis. |
| 24 | **Trainer** | Herd | Play in 3 games that were someone else's first-ever Kedro game. |
| 25 | **Pupil** | Learning | Finish the "Cambio in 5 minutes" course. |

Anti-farming: Herd counts only accounts and claimed guests. Trainer counts only first games that ended normally and had at least 3 rounds.

---

## 9. Visual identity

### 9.1 How the horse spirit shows up

- **Your horse is your identity.** The avatar builder has 8 coats (bay, chestnut, black, grey, palomino, dun, roan, appaloosa), 4 manes, 5 face markings (none, star, blaze, snip, stripe), and 10 silks colors. It's drawn as layered vector `Shape`s, so it's sharp at any size, can be tinted, and needs no image assets. In a game, if two players share a silks color, the later one gets the next free color for that game only. **Guests** get a random horse with a **dashed** silks ring and a "Guest" tag. Their horse carries over when they claim.
- **The race.** Live standings as a race strip, rank changes as horses trotting between lanes, the finish flag on the lowest score.
- **Horseshoes** mark progress (rounds, Paddock) and knock luck (upright, sideways, upside down).
- **Rosettes and the Winner's Circle** for rewards.
- **Dash**, the Kedro mascot (a cheerful chestnut foal), appears only in Learn, empty states, and onboarding. Never during a round.
- **Tone:** warm, a little cheeky ("Everyone gets thrown once"), never in the way. Puns are allowed in celebrations and empty states. They are never allowed in buttons, errors, or scoring explanations.

### 9.2 Color

Warm "stable" neutrals and racing-silk accents. All text pairs meet WCAG AA (≥ 4.5:1 for body text, ≥ 3:1 for large numerals and glyphs). Outcome meaning always comes with a glyph and a word as well.

| Token | Light | Dark | Use |
|---|---|---|---|
| `bg` | #FBF7F1 (parchment) | #12100E (stable night) | screen background |
| `surface` | #FFFFFF | #221E1B | cards |
| `ink` | #1D1A17 | #F6F0E8 | primary text |
| `ink2` | #5E564E | #C2B8AC | secondary text |
| `accent` (Chestnut) | #B4531F | #F08A4B | brand, primary buttons, focus |
| `gold` (Rosette) | #E2A72E / text #7A5200 | #F2BE4E | leader, winners, rosettes |
| `outcomeClean` | #1F7A52 | #4CC38A | clean knock, −10 |
| `outcomeTie` | #8F6400 | #E8B341 | tied knock |
| `outcomeBeaten` | #C23A51 | #FF6F86 | beaten knock, +10 |

Implemented as an asset-catalog color set (light/dark/high-contrast variants) exposed through a `ShapeStyle` extension (`.kedroAccent`). The app's `tint` is Chestnut. Increase Contrast swaps in the darker variants.

### 9.3 Type

**SF Pro Rounded for numbers and display, SF Pro for text.** The rounded design (`.fontDesign(.rounded)`) is still the SF family. It gives scores a friendly, game-piece feel and stays very readable at large sizes. All scores use `.monospacedDigit()` so columns line up and numbers don't shift when they count up. Text styles only (`.largeTitle`, `.title2`, `.headline`, `.body`, `.caption`), so Dynamic Type works everywhere. The single exception is the Winner's Circle total, which uses `.system(size:76, weight:.heavy, design:.rounded)` scaled with `@ScaledMetric`.

### 9.4 Iconography

SF Symbols throughout (variable color and symbol effects), plus four **custom symbols** made from SF Symbol templates so they match the weight and Dynamic Type scaling: `kedro.horse`, `kedro.horseshoe`, `kedro.knock` (a knocking knuckle with motion arcs), and `kedro.rosette`. Knock outcomes are the horseshoe at three rotations. Tab icons: Play = `suit.spade.fill` with cards, Leaderboard = podium, Learn = `book.fill`, Me = `kedro.horse`, Search = `magnifyingglass`.

### 9.5 Motion

| Moment | Motion | Reduce Motion version |
|---|---|---|
| Totals update | `.contentTransition(.numericText(value:))` count-up | Instant change |
| Rank change | Horses trot between lanes (`matchedGeometryEffect`, `.spring(duration:0.45, bounce:0.25)`) | Crossfade |
| Clean knock | Horseshoe flips upright + `.symbolEffect(.bounce)` + `.sensoryFeedback(.success)` | Static glyph + haptic |
| Beaten knock | Knocker's horse wiggles (`.symbolEffect(.wiggle)`) + `.sensoryFeedback(.warning)` | Static + haptic |
| Player joins lobby | Horse trots in from the edge | Fade in |
| Self-report reveal | Starting gates open together | Fade |
| Winner's Circle | Rosette confetti (`Canvas` + `TimelineView`), wreath rises (`keyframeAnimator`) | Static wreath, no particles |
| Table ↔ accessory | `navigationTransition(.zoom)` | System crossfade |

### 9.6 Liquid Glass usage

Glass only on the **controls layer**: the tab bar, the bottom accessory, toolbars, the Record button (`.buttonStyle(.glassProminent)`), the nearby-table card on Play (it floats over content), and the Live Activity button. The standings card, grid, keypad keys, and stats are **solid surfaces**, so numbers never sit on blurred content. The outcome banner and delta chips share a `GlassEffectContainer` so the banner morphs into the knocker's chip after a round (`glassEffectID`). Reduce Transparency falls back to solid surfaces automatically.

---

## 10. Accessibility

- **Dynamic Type (to AX5):** standings rows switch to a two-line layout (name above, score and delta below) using `ViewThatFits`. The keypad keys grow and the Record sheet scrolls while the keypad stays pinned. The race strip turns into a ranked list at accessibility sizes (its meaning is already in the standings). Stats grid goes from 2 columns to 1.
- **VoiceOver:** each standings row is one element: "Mia, first place, 20 points, last round plus 9, leads by 7". Custom actions: *Why this score*, *View player*, *Edit round*. The race strip has a single summary ("Mia leads, Noah last, gap 22"). After a round is recorded: `AccessibilityNotification.Announcement("Round 5 recorded. Sam knocked: clean knock, minus 10. Mia still leads.")`. Edits by others are announced. The rounds grid exposes rows and columns (`accessibilityChildren` / grid semantics) and has an `AXChartDescriptor` (Swift Charts audio graph) for score over time. Keypad keys are labeled ("minus sign", "delete").
- **Reduce Motion:** see the §9.5 table. No confetti, no horses moving between lanes, no parallax.
- **Color and contrast:** outcome = color + glyph + word, everywhere. Guest is shown by the dashed ring **and** a "Guest" tag. Contrast tokens meet AA in both appearances, and Increase Contrast swaps in darker variants. Silks colors are checked against both backgrounds and paired with names, never used alone.
- **Light and dark:** every surface is designed in both (see mockups 05/06). The Winner's Circle uses a warm gradient that works in both.
- **Other:** 44×44 pt minimum touch targets (keypad keys 72×56), haptics are paired with visible changes, and the Table works one-handed (all primary actions in the bottom third).

---

## 11. Tap and time estimates

Assumptions: phones unlocked, Kedro already installed for returning players, typical values (one two-digit hand per round).

| Task | Taps | Typing | Wall-clock |
|---|---|---|---|
| **Record one round, 5 players, scorekeeper** (hands 7, 12, 4, 9, 6; Leo knocks) | **9**: knocker 1 · digits 6 (7, 1-2, 4, 9, 6; auto-advance after 7, 12, 9, 6) · Next 1 (after "4") · Record 1 | none | **~10–15 s**, limited by people calling out values |
| Same round, self-report | **2–3 per player in parallel** (value + Send; knocker +1 toggle) | none | **~6–8 s** to the last hand |
| **Get 5 returning players into a game** | **6 total**: host Start a table 1 + Start game 1; each of 4 joiners Join 1 (auto-admitted) | none | **~15–20 s** |
| …with one player added by host from the played-with row instead | +1 host tap; that player taps Join on the notification | none | same |
| **First-time guest, no app** | **2 host taps** (Add guest, Done) | a first name | **~8 s** |
| **First-time guest, just installed** | **4 guest taps** (open, allow Local Network, Join as guest, Join table) + **1 host tap** (Admit) | a first name | **~25–35 s** after install |
| Rematch for the whole table | **2** (Rematch + Start game) | none | **~5 s** |
| Claim a guest history | **4** (open link, Sign in with Apple, Face ID confirm, Claim) | none | **~20 s** |
| Correct one hand value | **4** (tap round, tap value, digit(s), Save) | none | **~6 s** |

---

## 12. SwiftUI implementation map

| Screen / surface | Native components and APIs | UIKit? |
|---|---|---|
| **App shell** | `TabView` + `Tab`, `Tab(role: .search)`, `tabViewBottomAccessory`, `tabBarMinimizeBehavior(.onScrollDown)`, `@Observable` `AppModel` / `GameStore`, `@Environment` | No |
| **Onboarding / Welcome** | `NavigationStack`, `SignInWithAppleButton` (AuthenticationServices), `TabView(.page)` card stack, `PhaseAnimator` for the galloping horse | No |
| **Make your horse** | Layered `Shape`/`Canvas` avatar, `Picker(.palette)` swatches, `TextField`, `sensoryFeedback(.selection)` | No |
| **Play tab** | `ScrollView` + `LazyVStack`, `.glassEffect()` nearby card, `ContentUnavailableView` for empty states, `.sheet(item:)` Join sheet with `.presentationDetents([.medium])` | No |
| **Discovery & sync** | Network framework `NWListener`/`NWBrowser` (Bonjour `_kedro._tcp`, `includePeerToPeer`), `NWConnection` with a framed protocol for event gossip, NearbyInteraction `NISession` for distance ranking; Info.plist `NSLocalNetworkUsageDescription`, `NSBonjourServices`, `NSNearbyInteractionUsageDescription`. *(Alternative: MultipeerConnectivity session for gossip; never `MCBrowserViewController`, which is UIKit.)* | No |
| **Lobby / setup** | `List` with `.onMove` (seat order), `ScrollView(.horizontal)` played-with chips, `Picker(.segmented)` mode, `Stepper`, `Toggle`, QR via CoreImage `CIFilter.qrCodeGenerator` rendered as `Image`, `ShareLink` | No |
| **Table (live game)** | `fullScreenCover`, `NavigationStack`, `toolbar` with `ToolbarItem` glass buttons + `Menu`, `GlassEffectContainer`/`glassEffectID`, `matchedGeometryEffect`, `.contentTransition(.numericText)`, `.popover` for "Why?", `TipKit` `TipView`/`.popoverTip`, `.sensoryFeedback` | **Yes, one line:** keeping the screen awake needs `UIApplication.shared.isIdleTimerDisabled` (there is no SwiftUI API). Wrapped in a tiny `IdleTimerLock` helper tied to `scenePhase` + Table visibility, with a comment saying why. |
| **Record / Edit round sheet** | `.sheet(item:)` `.presentationDetents([.large])`, custom keypad `Grid` of `Button`s (avoids the system keyboard), `@FocusState`-like custom focus model, `Toggle` for Cards mode, `.accessibilityAction` | No |
| **Self-report** | Same keypad, `Toggle("I knocked")`, live presence via the sync layer, `.alert(item:)` for "Two knockers" | No |
| **Rounds & changes** | `Grid`/`LazyVGrid` for the rounds table with sticky totals (`ScrollView` + `.safeAreaInset`), `List` of change events, Swift Charts `LineMark` for score over time with `accessibilityChartDescriptor` | No |
| **Winner's Circle** | `keyframeAnimator`, `Canvas` + `TimelineView` confetti, `ImageRenderer` for the share card, `ShareLink` (AirDrop) for claim links | No |
| **Claim** | Universal links (`onOpenURL`), `SignInWithAppleButton`, `TextField` for code with `.textContentType(.oneTimeCode)` | No |
| **Profile / H2H** | `NavigationStack` + `navigationDestination(for: PlayerID.self)`, `Grid` stats, Swift Charts `BarMark` (knock outcomes, stacked), `ScrollView(.horizontal)` rosette shelf | No |
| **Leaderboard** | `List` with `Section`s (ranked / Paddock), `Picker(.segmented)`, chip row of lenses, `.safeAreaInset(edge: .bottom)` for the pinned "You" row, `.searchable` | No |
| **Rosettes** | `LazyVGrid`, `Gauge(.accessoryCircular)`-style progress rings, `.sheet` detail | No |
| **Learn** | `TabView(.page)` lessons, `Slider` knock simulator, `.searchable` rules reference (bundled Markdown rendered with `AttributedString`), `TipKit` | No |
| **Live Activity / Dynamic Island** | ActivityKit `Activity<GameAttributes>`, push tokens (`pushTokenUpdates`), widget-extension `ActivityConfiguration` with `DynamicIsland { expanded / compactLeading / compactTrailing / minimal }`, App Intents `LiveActivityIntent` buttons, `staleDate` | No |
| **Widgets** | WidgetKit `StaticConfiguration` (Rank, Rivalry, Next rosette, Played-with board), `accessoryCircular`/`accessoryRectangular` families, interactive `Button(intent:)`, `ControlWidget` for Start a table | No |
| **Notifications** | UserNotifications with `interruptionLevel` (.timeSensitive / .active / .passive), `threadIdentifier`, `UNNotificationAction` "Join" backed by an App Intent | No |
| **Sharing** | `ShareLink` (result card, claim link, table invite) | No |
| **Not used** | No in-app QR scanner (the system Camera handles the universal link, which avoids VisionKit's UIKit `DataScannerViewController`). No `UIAlertController`, no `UIColor`. | — |

**Stretch (v1.1): App Clip** for guests. Scanning the table QR opens a small SwiftUI clip that joins as a guest and self-reports, then offers the full app with the history claimed automatically. Flagged because App Clips have framework limits (local-network peer-to-peer may not be available), so the clip would relay through the backend and need internet.

---

## 13. Risks and open questions

1. **Local Network permission denial** breaks automatic discovery. Mitigation: the primer before the system prompt, plus the table code and QR, plus host-added players with the notification Join.
2. **Kedro Rating trust.** Explain it on a "How Rating works" page that is linked from every leaderboard header.
3. **Final check window (3 min)** could annoy a table that wants to leave right away. Anyone can tap Finish to end it early.
4. **Auto-advance keypad** needs real-table testing for hands above 59. The fallback (tap the row to add a digit) is designed but rare.
5. **Restore window for abandon (15 min)** needs a server rule so a restore made offline doesn't conflict. The deterministic rule is that Restore beats Abandon by HLC order.
