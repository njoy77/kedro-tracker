# Kedro iOS: "Rivalry Engine" design spec

Design tournament entry · iOS 26 · SwiftUI · October 2026
Companion file: [`mockups.html`](./mockups.html) (20 frames). Source of requirements: `docs/kedro-ios-prd.md` only.

---

## 0. Design thesis

**Every game is a chapter in a rivalry.** People don't come back to a score tracker; they come back to find out whether they finally beat Maya, whether they cracked the top five among their friends, and how many games until they get a rank. Kedro's job at the table is to be invisible: fast, exact, trusted. Its job between games is to turn those exact numbers into stories worth returning for: head-to-head records, streaks, a leaderboard you can climb, and achievements earned in memorable moments. The design runs on one loop:

> **Stakes → Play → Payoff → Next stakes.** Before a game, Kedro shows what's on the line. During it, it gets out of the way. At the end, it pays off every storyline at once. Then it gives you the next reason to play.

The brand's horse spirit gives the loop its language: racing has the vocabulary rivalries need (the **Paddock** where new players warm up before they rank, the **Track** where ranked players compete, **silks** that tell riders apart at a glance, **rosettes** for honors, a **dead heat** for a shared win). The theme stays out of gameplay terms: knocking is always "knocking", and rounds, hands, and scores keep their plain names.

### How the thesis serves the four PRD goals

| PRD goal | How the Rivalry Engine delivers it |
|---|---|
| **Fast table flow** | Stakes and stories live *before* and *after* the game. During play the screen is one standings list and one button. Round entry is one sheet with a custom keypad (it has a minus key and auto-advances), about 13 taps for 5 players. No storyline ever sits between the table and the "Record round" button. |
| **Everyone joins** | A rivalry needs both people in the record, so joining is designed as a one-tap pull: nearby tables appear on their own on the Play tab, and Nearby Interaction distance tells the table apart from the one next to it. Returning players never type. Guests get a generated silks avatar, so they look like real competitors from round 1. |
| **People come back** | The Play tab opens on **Since you last looked** (rank moves, rivalry flips, a guest who claimed their history) and **Next-game stakes**. Rivals, Track, and You tabs, three widget families, and a carefully limited notification set give you a reason to open the app that is never just a nag. |
| **Spreads to new tables** | New players learn through the same scoring screen they play with (every knock explains itself), plus a 5-lesson Learn track. Guests convert because the claim card sells *their* story: "Your 3 games and your rivalry with Noah are waiting." Claiming earns the host an achievement (Breaking In), which gives hosts a reason to hand out codes. |

### Design principles for this entry

1. **Stories between games, silence during them.** No achievement toasts, rank pop-ups, or notifications mid-game. Everything waits until the game is sealed and pays off at the end.
2. **One number to climb.** Ranking uses a single rating, so "I'm #4" means one thing (see 7a).
3. **The rule explains itself.** Every derived score shows the reason: −10, hand, or +10.
4. **Every fix is public, every fix is reversible until sealed.**
5. **The Paddock is a welcome, not a waiting room.** Players under the threshold see their progress everywhere and are visibly part of the community.

---

## 1. Information architecture and navigation

### 1.1 Top-level structure

`TabView` with the iOS 26 `Tab` API and the Liquid Glass tab bar. There are four content tabs plus a system search tab:

| Tab | SF Symbol | Purpose | Primary content |
|---|---|---|---|
| **Play** | `suit.club.fill` | Get to a table, see what's at stake | Start a table, nearby tables, Run it back (recent tables), Since you last looked, Next-game stakes, Learn Cambio, claim code entry |
| **Rivals** | `figure.equestrian.sports` | Your people and your records against them | Rivalries ranked by heat, nemesis pinned at the top, full played-with list, head-to-head detail |
| **Track** | `flag.checkered` | Leaderboards | Played-with (default) and Global boards, Around me / Top, Paddock section, category Spotlights |
| **You** | silks avatar | Your profile as others see it | Stats, form, knock profile, achievements shelf, game history, silks editor, settings |
| **Search** (`Tab(role: .search)`) | `magnifyingglass` | Find any Kedro player | Search results lead to public profiles and head-to-head with you |

**Rules** are not a tab. They are always one tap away: a book button in the live-game toolbar, a Learn card on Play, a "Why?" link on every knock outcome, and a Rules row in You. A tab for reference material would cost a top-level slot that the return loop needs.

### 1.2 The live game is a mode, not a tab

- A game in progress is presented as a **`fullScreenCover`** with its own `NavigationStack`. While it's on screen it holds the device awake.
- Swipe down or tap the chevron and the game collapses into a **`tabViewBottomAccessory`** mini bar above the tab bar (like Now Playing in Music): `R7/10 · You T2 · 27 · Live`. Tap it to return. This lets a player check a rivalry or the rules mid-game without losing the table.
- Only one active game per player. Starting or joining another game while one is active asks you to end or abandon the first.

### 1.3 Navigation map

```
Root
├─ Splash → Onboarding (first launch) → Main
└─ Main: TabView
   ├─ Play (NavigationStack)
   │   ├─ Start a table → Lobby (host)          ─┐
   │   ├─ Nearby table card → Join sheet        ─┼─→ Live game (fullScreenCover)
   │   ├─ Run it back (crew) → Lobby prefilled  ─┘      ├─ Standings | Rounds | Log
   │   ├─ Since you last looked → H2H / Track / Achievement
   │   ├─ Learn Cambio → Lessons 1–5 → Practice
   │   └─ Got a claim code? → Claim flow
   ├─ Rivals (NavigationStack) → Head-to-head → Game detail
   ├─ Track (NavigationStack) → Profile → Head-to-head
   ├─ You (NavigationStack) → Stat detail · Achievements · Game history → Game detail · Silks editor · Settings
   └─ Search → Profile → Head-to-head
Live game sheets: Round entry · Round detail/edit · Rules · Game menu (extend / end early / abandon / scorekeeper / reporters)
Game end: Final check → Winner's Circle → Hand guests their history · Rematch → Lobby
```

### 1.4 Deep links and entry points

Universal links (domain to be decided) route to: a claim (`/claim/<code>`), a table invite (`/table/<id>`), a profile, or a finished game. App Intents expose **Start a table**, **Record round**, and **Open my standings** to Siri, Shortcuts, the Action button, and a Control Center control.

---

## 2. Key flows

Sample data throughout (spec and mockups) is one game: Noah (host, "you"), Maya, Jordan, Priya, and Sam (guest). 8 planned rounds, extended to 10. Every number follows Section 2.6 and was checked by script:

| Rnd | Knocker | Hands N/M/J/P/S | Outcome | Round scores N/M/J/P/S | Cumulative N/M/J/P/S |
|---|---|---|---|---|---|
| 1 | Maya | 9/3/12/7/15 | Clean | 9/−10/12/7/15 | 9/−10/12/7/15 |
| 2 | Jordan | 5/8/5/11/6 | Tied (Noah 5) | 5/8/5/11/6 | 14/−2/17/18/21 |
| 3 | Noah | 2/6/14/−1/9 | Caught (Priya −1) | 12/6/14/−1/9 | 26/4/31/17/30 |
| 4 | Priya | 10/4/8/3/13 | Clean | 10/4/8/−10/13 | 36/8/39/7/43 |
| 5 | Sam | 1/9/6/12/7 | Caught (Noah 1) | 1/9/6/12/17 | 37/17/45/19/60 |
| 6 | Noah | 3/7/11/8/5 | Clean | −10/7/11/8/5 | 27/24/56/27/65 |
| 7 | Jordan | 6/4/4/9/12 | Tied (Maya 4) | 6/4/4/9/12 | 33/28/60/36/77 |
| 8 | Maya | 4/5/10/2/8 | Caught (Priya 2) | 4/15/10/2/8 | 37/43/70/38/85 |
| 9 | Noah | 0/6/9/5/11 | Clean | −10/6/9/5/11 | 27/49/79/43/96 |
| 10 | Priya | 7/3/8/1/10 | Clean | 7/3/8/−10/10 | 34/52/87/**33**/106 |

Priya wins 33 to 34. She was 16 behind with one round left; it's her 5th game, so it also puts her on the Track.

Knock outcome language, used everywhere:

| Outcome | Badge | Plain explanation shown in app |
|---|---|---|
| **Clean knock** | `−10` turf green, horseshoe-up glyph | "Noah knocked with 3, strictly the lowest hand → **−10** (hand ignored)." |
| **Tied knock** | `=` neutral | "Jordan knocked with 4 and Maya also had 4. A tie, so Jordan scores his hand: **4**." |
| **Caught** | `+10` rosette red, broken-shoe glyph | "Maya knocked with 5 but Priya had 2, so Maya scores 5 + 10 = **15**." |

### 2.1 First launch and onboarding (Frame 1)

1. **Splash** (existing scaffold) → **Welcome**: one screen with a short silks animation, "Score Cambio at the table. Settle every rivalry."
2. Two equal paths:
   - **Sign in with Apple** (`SignInWithAppleButton`). *While Apple sign-in is disabled, debug builds show the test-user button under `#if DEBUG`; release builds never contain it.*
   - **Join a table first.** Play now as a guest on this device and sign in later. The device keeps the guest identity's claim token, so signing in later claims the history automatically. This is the claim-code mechanism from 3.2 with the code delivered straight to the device, so no typing.
3. **Silks**: Kedro generates silks (pattern + two colors + horse coat) from your name. Tap **Looks good** or shuffle. Customizing is optional and lives in You.
4. **Permissions primer** (one card, before the system prompts): "Kedro finds tables in the same room. Your location isn't stored or shared." Then the Local Network prompt. The Nearby Interaction prompt is deferred until the first join, and notifications until the first game ends (asked in context: "Want to know when you're added to a table?").
5. **New to Cambio?** toggle: "I'm new, teach me as I play" turns on Table Coach (see 4) and adds Learn to the top of Play.
6. Small link: **Have a claim code?** for legacy web players and guests holding a code.

Target: signed-in returning user in **3 taps** (Sign in, Looks good, Allow); guest path in **2 taps** plus their name.

### 2.2 Getting a table into a game

#### Proximity architecture
- **Discovery and sync:** Network framework peer-to-peer (Bonjour with `includePeerToPeer`, using the iOS 26 structured-concurrency `NetworkListener` / `NetworkBrowser` / `NetworkConnection` APIs). This works over AWDL with no Wi-Fi network and no internet. `MultipeerConnectivity` is the fallback; its 8-peer session cap matches the 8-player table maximum. Wi-Fi Aware can be evaluated later for supported devices.
- **Same-table filtering:** once a peer is found, devices exchange `NIDiscoveryToken`s over that channel and run a `NISession`. Peers within about 3 m are shown as **At your table**; farther ones go under **Other tables nearby**. This keeps a party with two Cambio tables from crossing wires. Devices without UWB fall back to signal strength and a 4-character table word ("Table **MANE**") the host can read out.
- **Advertising** happens only while a lobby or live game is open on the host's phone, and **browsing** only while Play or the Join sheet is visible. No background location, no ambient tracking.

#### A. All returning players (Frames 2, 3, 4)
1. **Host** taps **Start a table** on Play. The Lobby opens and begins advertising. The host's seat is filled, and the table word shows.
2. **Each other player** opens Kedro. Play shows a **Nearby table** card at the top ("Noah's table · 1 m · 3 seated", with avatars) and **Join**. One tap. The Join sheet shows the stakes ("Your 5th game. This one puts you on the Track"; "Maya leads you 11–7") while you wait.
3. Seats fill live on the host's lobby with a spring "gallop in" animation. Co-located joins are **auto-accepted**. The host can remove a seat with a swipe.
4. Rounds and mode **default to the last game you hosted** (e.g. 8 rounds · Scorekeeper). Host taps **Start**. Every phone flips into the live game at the same moment.

**Fallback without proximity** (a phone without permission, or the network is blocked): **Run it back** cards on Play ("Friday's table: Maya, Jordan, Priya, Sam") prefill the lobby in one tap. Each added Kedro user gets the "Added to Noah's table" notification and joins with one tap. A host can also add anyone from **Played with** (sorted by recency and frequency), **Search** any Kedro user, or **Add guest** by name.

#### B. A table with a guest
- In the lobby, **Add guest** → type a name → **Add**. The guest gets generated silks and a dotted "Guest" ring, and is fully recorded.
- A **reporter** is assigned for each guest (default: the host; tap the guest's seat to change). In scorekeeper mode this is moot. In self-report mode the reporter enters the guest's hand on their own phone, as a second card under "Report for Sam".
- If the guest **has Kedro but no account**, they join from the nearby card like anyone else ("Join a table first" path) and play as a guest on their own phone.

#### C. Mid-game join (a phone arriving after round 1)
Three distinct cases, all logged:
1. **A seated player's phone joins late** (the host added Jordan from Played-with; Jordan opens Kedro at round 3). The Join sheet says "You're seated in Noah's game" and opens the game at its current state. One tap.
2. **A guest takes over their own seat** (Sam installs Kedro at round 4). The Join sheet asks "Are you one of these guests?" and Sam taps "Sam". Any seated player's phone shows "Sam's phone wants Sam's seat · **Allow**". From then on, Sam's phone holds the guest identity and its claim token.
3. **A brand-new person sits down mid-game.** The canonical ruleset has no catch-up rule for a late entrant, and inventing a starting score would be a house rule (a PRD non-goal). Kedro does **not** add new players after round 1 has been recorded. They join as **On deck**: they watch the live standings on their own phone and are seated automatically if the table rematches. Before round 1 is recorded, new players can be added freely.

### 2.3 Game setup (Frame 4)

The lobby *is* the setup screen; there's no separate wizard.

- **Seats** (3–8): live list in table order (join order, or drag to reorder). Table order sets the entry order in scorekeeper mode, so the scorekeeper can go around the table. **Start** is disabled under 3 seats; the 9th seat can't be added ("Cambio tables max out at 8").
- **Planned rounds:** a stepper with quick chips **5 · 8 · 10 · 12**, defaulting to the host's last value. A hint shows typical length ("≈ 4 min per round").
- **Scoring mode:** a segmented control. **Scorekeeper** ("one phone enters everyone; fastest for tables with guests") or **Self-report** ("everyone enters their own hand; best when everyone has Kedro"). Kedro recommends a mode from the table: Scorekeeper if any guest lacks a phone, otherwise the host's last choice.
- **Scorekeeper** (scorekeeper mode): defaults to the host. Anyone can tap **Take over scoring** later, which is logged.
- **Stakes** strip (read-only, collapsible): up to 3 storylines generated from history, e.g. "Priya's 5th game: she reaches the Track", "You vs Maya: 7–11", "Jordan is on a 2-game win streak". This is the only place the Rivalry Engine speaks before play, and it's skipped once the host taps Start.

### 2.4 The live game (Frames 5, 6)

One screen, three segments: **Standings · Rounds · Log**.

**Header** (always visible)
- "Round 7 of 10" with 10 small horseshoe pips (filled = recorded). This is progress against the plan.
- Sync pill (see 2.12): `● Live`, `⟷ Table link`, `Jordan out of reach`, `↑ Uploading 4`.
- Toolbar: chevron (collapse to accessory), book (Rules sheet), `…` menu (Extend, End early, Abandon, Scorekeeper, Reporters, Hand guests their history).

**Standings** (default)
- Rows sorted by cumulative score, lowest first. Each row: rank (shared ranks shown as `T2`), silks avatar, name, a thin silks stripe on the leading edge, **cumulative** (large, monospaced digits), **last-round delta chip** (`−10 ↓` turf, `+7 ↑` neutral, `+17` rosette when caught), and **gap to leader** ("+3 back"). The leader's row gets a brass rail and "Leading". Rank changes from the last round animate as rows sliding past each other, with a `▲1` marker for one round.
- **Last round card** under the list: "Round 6 · Noah knocked with 3, strictly lowest → −10 · Clean knock" with **Why?** (opens the Rules sheet at Scoring, with this round's numbers filled in).
- **Storyline line** (one line, updates only between rounds, never during entry, dismissible for the game): e.g. "Noah and Priya are level on 27. Maya leads by 3." Facts only, no predictions.
- **Primary button** (Liquid Glass prominent, bottom): **Record round 7** for the scorekeeper. In self-report mode it reads **Enter my hand** and shows a reported count ("3 of 5 in"). Non-scorekeepers in scorekeeper mode see **Record round 7** too (anyone can record; the first save wins and the second phone sees "Round 7 was just saved by Noah · View").

**Rounds** segment: see 2.8. **Log** segment: see 2.9.

The device stays awake while the live game is on screen (4.4).

### 2.5 Recording a round: scorekeeper mode (Frame 7)

A `.large` sheet titled **Round 7**, built for one thumb:

1. **Who knocked?** A row of silks avatars at the top. This comes first because it's the first thing the table says out loud ("Jordan knocked"). **Save is disabled until a knocker is chosen**, and the empty state says "Every round has exactly one knocker."
2. **Hands list**: one row per player in table order. The active row is highlighted, and a **custom keypad** is docked at the bottom:
   ```
   1  2  3
   4  5  6
   7  8  9
   −  0  ⌫        [ Next → ]
   ```
   - The **− key** toggles the sign (the system number pad has no minus key, which is why the keypad is custom).
   - **Auto-advance:** after 2 digits the cursor moves to the next player. For a single-digit hand, tap **Next**. Tapping any row jumps to it.
   - **Cards mode** (per-row `suit.spade` toggle): a card picker (A–10, J, Q, black K, red K, Joker) that sums as you tap, showing each card's value. Useful for disputed or new players, and it teaches values.
   - **Validation:** values below −2 are blocked with a reason ("Lowest possible hand is −2: both red Kings"). Values above 60 show a non-blocking "Double-check: 61?".
3. **Live scoring preview** on each row: `hand → round score`. The knocker's row shows the outcome badge and its math as soon as all hands are in ("Tied knock: Jordan 4 = Maya 4 → Jordan scores 4").
4. **Save round** (prominent). Haptic `.success`, the sheet dismisses, rows animate to new positions on every phone, and the last-round card updates.

Undo: a 5-second "Round 7 saved · **Undo**" glass banner (undoing is itself logged as an edit). After that, edit through Rounds.

### 2.6 Recording a round: self-report mode (Frame 8)

The round opens automatically on every phone when the previous round is saved.

1. Each player taps **Enter my hand** (or the Live Activity button). The sheet shows:
   - **Who knocked?**: the first phone to set it fills it in for everyone ("Jordan · set by Jordan"). **I knocked** is a big shortcut button for the knocker. Anyone can change it, and the change is logged.
   - A **large hand display** with the same keypad, or Cards mode. New players default to Cards mode with values printed on each card.
   - **Report for Sam** cards for any guests this phone reports for.
   - **Submit**. The submitted value can be changed until the round completes.
2. **Reported** chips show who's in (`✓ Noah ✓ Maya ✓ Jordan · Sam (Noah reports) · You`). **Values stay hidden until everyone has reported**, which keeps anyone from anchoring on others' numbers and gives the table a moment.
3. When the last report lands, all phones play the **Reveal** together: hands flip in, the knock badge resolves with its math, and standings re-sort.
4. **Edge cases**
   - *Knocker mismatch* (two phones set different knockers, e.g. while offline): the round can't complete. All phones show "Who knocked: Jordan or Maya?" and the first tap resolves it. Both claims and the resolution go in the log.
   - *Phone died / player away:* any player can **Report for Jordan** from the reported chips. This is logged ("Maya reported for Jordan").
   - *Guest's reporter left:* the guest's chip reads "Needs a reporter" and anyone can take it over.

### 2.7 Live standings and last-round deltas
Covered in 2.4. VoiceOver reads each row as one element: "Second, tied. Noah. 27 points. Last round minus 10, clean knock. 3 behind the leader."

### 2.8 Round history (Frame 9)

**Rounds** segment: a compact table, newest first.
- Each row: round number, knocker avatar + outcome badge (`−10` / `=` / `+10`), and a mini row of every player's round score in table order. An `Edited` tag appears if the round was ever changed.
- Tap a row → **Round detail**: every player's hand → round score, the knock math sentence, and this round's edit history, plus **Edit round**.
- A small **"Show cumulative"** toggle switches the mini scores between round scores and running totals.

### 2.9 Audit trail and corrections (Frame 10)

**Log** segment: a chronological feed of every change, visible to everyone in the game. Each entry shows who, when (relative time plus round context), and before → after:

- `Maya edited Round 3 · 9:38 PM` · Priya's hand **3 → −1** · *Re-scored:* Noah's knock **Clean (−10) → Caught (12)** · Standings after round 5: Noah 1st → 3rd
- `Jordan edited Round 2 · 9:35 PM` · Sam's hand **9 → 6** · knock unchanged (Jordan's tie with Noah on 5 stands)
- `Noah extended the game · 9:33 PM` · Planned rounds **8 → 10**
- `Jordan's phone rejoined · merged 2 offline changes · no conflicts`
- `Sync resolved a conflict on Round 5` · Jordan set Sam's hand 8, Maya set 7 (later) → **7 applied**; Jordan's edit kept as *superseded*

**Editing**
1. Round detail → **Edit round** opens the same entry sheet, prefilled.
2. On save, a **diff confirmation** shows exactly what changes, including re-scoring and standings: "Priya 3 → −1. Noah's knock: Clean → Caught (−10 → 12). Noah drops from 1st to 3rd." **Save change**.
3. Every phone shows a non-blocking glass banner, "Maya edited Round 3 · See change", and the Log segment shows a badge until viewed. No push notification.
4. Changing the knocker or any hand value re-runs the 2.6 scoring automatically. Players never type a bonus or penalty.
5. **Finished games are immutable**: Round detail in a sealed game has no Edit button, and its log reads "Sealed 10:12 PM".

### 2.10 Extending, ending early, abandoning

All three live in the `…` menu, are available to **any player**, and are logged.

| Action | Interaction | Result |
|---|---|---|
| **Extend** | Stepper sheet: +1 · +2 · +5, or set a total. | Planned rounds change at once; pips grow; log entry "8 → 10". |
| **End early** | `confirmationDialog`: "End after round 6 of 10? The game counts fully in stats." | Enters **Final check** (below), then seals as finished. |
| **Abandon** | Destructive `confirmationDialog`: "Abandon this game? It stays in history marked Abandoned and won't count toward stats, leaderboards, or achievements." | Enters a 15 s **Abandoning** window with "Keep playing" on every phone, then seals as *Abandoned*. No celebration. History shows it greyed with an "Abandoned by Jordan · after round 4 of 8" tag. |

**Final check, the sealing window.** Sealing is permanent, so every terminal transition (planned rounds complete, end early, abandon) gets a 15-second window visible on every phone. It shows a countdown ring, "Final round in. Check your scores.", and **Fix a round** · **Extend** · (for abandon) **Keep playing**. Any of these cancels the countdown, and the game stays in progress. When the ring closes, the game seals and becomes immutable. This window is how "any player can end it" and "finished is final" both hold without anyone being surprised.

### 2.11 Game end: the Winner's Circle (Frame 11)

When the seal lands, every phone plays the same moment:
1. **Winner reveal**: the winner's silks avatar with a brass rosette unfurling and a short horseshoe sparkle (Reduce Motion: a crossfade). "**Priya wins** by 1." Co-winners stand side by side: "**Dead heat**: Priya & Noah share the win."
2. **Final standings** with total scores and the place change since halfway.
3. **Highlights** (a horizontal carousel, generated from the rounds):
   - *Comeback:* "Priya was 16 back with one round left and won with a clean knock."
   - *Clean knocks:* "Noah 2 · Priya 2 · Maya 1"
   - *Lead changes:* "4: Maya → Priya → Maya → Noah → Priya"
   - *Best round:* "−10, five times"
   - *Ouch:* "Sam's round 5 knock got caught: 7 + 10 = 17"
4. **Your story** (personal, different on each phone; the Rivalry Engine payoff):
   - "You beat Maya: H2H **8–11**, closest it's been."
   - "Priya beat you by 1. In her 5 games she now leads you **3–2**."
   - "Track: you passed Jordan → **#4** among your people."
   - "**Priya is on the Track**: debuts **#6**." (shown on everyone's phone)
   - Achievements unlocked this game, as rosettes.
5. **Hand guests their history**: one card per guest (see 2.13).
6. **Rematch** (prominent) and **Done** (returns to Play; the accessory disappears). **Share** renders a results card image with `ImageRenderer` for `ShareLink`.

### 2.12 Rematch
- **Rematch** on any phone creates a new lobby with the **same seats, table order, rounds, and mode**. Guests carry their **same guest identity**, so their history keeps accumulating under one claimable identity. On-deck people are added.
- Other phones still on the Winner's Circle see **"Rematch? · Join"** (one tap). Phones that left get the in-app nearby card.
- The new lobby's Stakes strip leads with the game that just ended: "Priya won the last one by 1."
- Host taps **Start**. Rematch is **2 taps for the proposer, 1 per player**.

### 2.13 Guest claim by link or code (Frame 12)

**Issuing**
- Every guest identity has one active **claim code** (6 characters from an unambiguous alphabet, shown as `K7Q-4MD`) and a matching universal link. Kedro issues it when the guest's first game seals. One code covers *all* of that guest identity's games.
- At game end, **Hand Sam their history** shows a big code, a QR code (generated with Core Image), and **AirDrop / Message** via `ShareLink`. Any player in the game can reopen it later from game history until it's claimed.
- If a guest's own phone was in the game (2.2 C2), the token is already on that phone and claiming needs no code.
- Legacy web users are migrated guest identities with codes distributed the same way (out of band).

**Claiming**
1. Open the link (Camera, Messages, AirDrop) → Kedro (or the App Store, with the link deferred through first launch) → **Sign in with Apple**.
2. **Claim card**: "This is Sam's history · 3 games · 1 win · Rivalries with Noah, Maya, Jordan, Priya". The card sells the story first, then shows **Claim**.
3. Kedro recomputes everything derived (stats, rivalries, achievements, rating), and the claimer sees "Welcome back: 2 achievements unlocked · 3 of 5 games to the Track".
4. A claimed code is dead: "This history was already claimed." There's no merge or unclaim UI in v1 (support only).
5. People who played with the guest see "Sam claimed their history · your rivalry is live" in Since you last looked, and the host earns **Breaking In**.

### 2.14 Offline play and resync

**Model.** A game is an append-only log of events (round recorded, field edited, knocker set, extend, end, abandon, seat changes), each with a UUID, author, wall time, and Lamport timestamp. Every phone holds the full log and derives standings from it. Phones exchange events directly over the peer-to-peer channel, and any phone with internet uploads them. The server dedupes by event UUID (idempotent), so nothing duplicates. Conflicting edits to the same field resolve by **highest (Lamport, device ID)**, the same answer on every device and the server. The losing edit stays in the log as *superseded*. Fact conflicts that need a human (knocker mismatch in self-report) block completion until resolved (2.6).

**States the player sees** (sync pill in the header, details on tap):

| State | Pill | Meaning |
|---|---|---|
| Online, all peers connected | `● Live` (turf) | Real-time everywhere |
| No internet, peers connected | `⟷ Table link` (brass) | Fully playable. Everything is saved on every phone and uploads later. |
| A peer missing | `Jordan out of reach` (amber) | Jordan's entries queue on his phone. Others carry on. Merges on reconnect. |
| Uploading | `↑ Uploading 4` | Catching up with the backend |
| Uploaded after offline | `✓ Saved` for 3 s | Then back to Live |

**After an offline game:** the Winner's Circle works fully offline. Track and rating lines read "Rank updates when you're online", and achievements earned show a small "confirming" dot until the server agrees (they're derived from the same log, so they match). Live Activity updates locally while Kedro runs.

---

## 3. Stats, head-to-head, leaderboards, achievements

All numbers are **derived from rounds and games** (PRD 5). The client never shows a stored counter. Corrections and claims re-derive, and so does the rating, which is recomputed by deterministic chronological replay.

### 3.1 You / Profile (Frame 13)
- **Header**: silks avatar (large), name, Track chip (`#4 people · #212 global · 1579`), or Paddock progress (`●●●○○ 3 of 5 to the Track`) for sub-threshold players.
- **Form strip**: last 10 games as placement pills (`1st` brass, `2nd` silver ...), with current streak.
- **Stat grid** (2 columns, `Grid`): Games played · Wins · Win rate · Best game · Worst game · Avg per game · Avg per round · Current streak · Longest streak.
- **Knock profile**: knock rate, knock success rate, and a segmented bar of **Clean / Tied / Caught** counts (Swift Charts `BarMark`, stacked, with an accessibility chart descriptor).
- **Nemesis** card: "Maya has finished ahead of you 11 times" → head-to-head.
- **Achievements shelf**: latest rosettes plus "3 close to unlocking".
- **History**: games list with place, score, players, plus abandoned games greyed out and tagged.
- Public profiles of other players use the same screen, with **Head-to-head with you** at the top.

Sample (Noah): 23 games, 7 wins, 30%, best 18, worst 96, 41.2 per game, 4.1 per round, current streak 0, longest 3, knock rate 18% (41 of 230 rounds), success 61% (25 clean · 4 tied · 12 caught), nemesis Maya (11).

### 3.2 Head-to-head (Frame 14)
- Two silks avatars facing each other. The **rivalry status** headline is computed from the record: *Neck and neck* (within 1), *You lead*, *Maya leads*, *New rivalry* (< 3 games).
- **Finished ahead**: big split number `8 – 11` with a tug bar. **Games together: 19.**
- **Wins in shared games**: 5 – 6.
- **Knocks when facing each other**: per player, Clean / Tied / Caught counts.
- **Timeline**: the last 10 shared games as dots (who finished ahead), and each game opens its detail.
- **Next game stakes**: "Three more finishes ahead of Maya and it's level."
- **Rematch-able**: "Play again with Maya" starts a lobby with her pre-added.

### 3.3 Leaderboards (Frame 15)
- Two scopes in a segmented control: **Played with** (default, since your people are the story) and **Global**.
- Global opens on **Around me** (5 above, 5 below) with a **Top** jump. Played-with shows everyone.
- Rows: rank, silks, name, **rating**, games, win rate (secondary), and movement since your last visit (`▲2`).
- **Paddock section** below the ranked list: "**In the Paddock** · warming up". In Played-with, each member is listed with **progress pips (3 of 5)** and **no rank number**. In Global, it's a count ("6,112 players in the Paddock") with a face pile and a "Who's close" list of people at 4 of 5.
- **Unclaimed guests** are not listed (PRD 3.3: visible only in their games).
- **Spotlights** (horizontal cards above the board): category leaders among ranked players. Best knock success, longest streak, best average per round, most games. See 7a for why these aren't sort options.
- Your own row is pinned to the bottom edge when it's scrolled off screen.

### 3.4 Achievements (Frame 16)
- Displayed as **rosettes** in a grid, grouped as Milestones · Knocks · Moments · Social · The Track.
- Earned: full-color rosette, date, the game it came from (tap → game detail). Locked: an outline with a progress ring and the rule in plain words ("Play with 15 different people · 9/15").
- **Close to unlocking** sits at the top (sorted by % complete). This is a play-more lever.
- Achievements are awarded **only when a game seals**, from finished, non-abandoned games. They never pop mid-game. Claims award retroactively.
- Public profiles show earned rosettes (5.5).

---

## 4. Rules and learning (Frame 17)

**Rules sheet** (available everywhere, including mid-game from the book button): sections for Setup · Card values · Power cards · Sticking · Knocking · Round scoring · Game end, as a searchable `List`. The **Round scoring** section has an embedded **knock calculator**: pick the knocker's hand and the lowest other hand, and it shows the result with the rule highlighted. Opening "Why?" from a round prefills it with that round's numbers.

**Learn Cambio**: 5 lessons, about 90 seconds each, interactive rather than text-heavy:
1. **Card values**: flip cards to reveal values. The surprises (red King −1, black King 13, Joker 0) are highlighted. Quick 3-card quiz.
2. **Power cards**: 7/8 peek own, 9/10 peek opponent, J/Q blind switch, black K look and switch. Each one is animated on a 2×2 grid.
3. **Sticking**: tap the matching card before the timer bar empties. A wrong stick shows how it ends up in your hand value.
4. **The knock gamble**: a slider for your hand and the lowest other hand, showing the three outcomes live (−10 / your hand / hand + 10). "Knocking is a gamble, not a win."
5. **Score a round**: a practice round using the real entry sheet, scored by Kedro, with the explanation.
Finishing all five earns **Schooled**.

**Table Coach** (for players who said "I'm new", or whose profile has fewer than 3 games): on *their phone only*, between rounds, one short tip relevant to what just happened ("Priya's −1: that's the red King"). It's never shown during entry, and it turns off after 3 games or with one tap.

**In-game reinforcement for everyone**: every knock badge carries its math sentence, the last-round card has **Why?**, Cards mode shows values on every card, and validation explains the −2 floor.

---

## 5. System surfaces

### 5.1 Live Activity and Dynamic Island (Frames 18, 19)
Started when a game starts (on every participating phone), and ended at seal with a 1-hour results state.

| Presentation | Content |
|---|---|
| **Lock Screen / banner** | "Noah's table · Round 7 of 10" + pips · top 3 plus you with cumulative and last-round delta · sync glyph · in self-report mode an **Enter my hand** button (`Button(intent:)` → opens the entry sheet; Live Activities can't take text input) |
| **Compact** | Leading: silks dot + `R7/10`. Trailing: your rank and score `T2 · 27` |
| **Minimal** | Your rank `T2` on your silks color |
| **Expanded** | Top 4 standings, last round's knock sentence, **Enter my hand** / **Open** |
| **Ended** | "Priya wins by 1 · You 2nd · 34" for 1 hour, then dismissed |

Updates: ActivityKit push tokens (APNs `liveactivity`) when online; local `Activity.update` from the app when offline. An alert update ("Your hand for round 7") is the self-report prompt, so there's no separate notification while a Live Activity is running.

### 5.2 Widgets (Frames 18, 20)
WidgetKit, `AppIntentConfiguration` where configurable, data shared through an App Group cache, reloaded on game seal.

| Widget | Sizes | Content |
|---|---|---|
| **Rival** | Small, Medium | You vs a chosen rival (default: nemesis): `8 – 11`, status line, last result |
| **Track** | Small, Medium, Lock Screen rectangular | Your played-with rank, rating, movement. Sub-threshold: Paddock pips "3 of 5" and "2 games to rank" |
| **Since last game** | Medium, Large | Rank move, streak, newest rosette, closest achievement |
| **Lock Screen circular** | Accessory circular | Paddock progress ring, or rank number |
| **Control** (`ControlWidget`) | Control Center / Lock Screen / Action button | **Start a table**: opens straight into a lobby |

### 5.3 Notifications

The set is small on purpose. Rule: **nothing interrupts a table that's playing, and nothing nags you to come back.** While you're in an active game, every Kedro notification except your own self-report prompt is held until the game seals, then merged into the results notification.

| # | Notification | When | Level |
|---|---|---|---|
| 1 | **Added to a table**: "Noah added you to a table · Join" | A host adds you directly (not when you joined yourself) | Time Sensitive |
| 2 | **Your hand, round 7** | Self-report only, your phone isn't showing Kedro, and the round has been open 20 s. Once per round, delivered as a Live Activity alert when one is running | Time Sensitive |
| 3 | **Game results**: "Priya won by 1 · You 2nd · +2 rosettes" | Game sealed and you weren't looking at Kedro. Bundles the Track and achievement news from that game | Active |
| 4 | **Your history was claimed / Sam claimed theirs**: "Sam claimed their history: your rivalry is live" | Asynchronous claim events | Passive |
| 5 | **Track milestone**: "You're on the Track: #4 among your people" | Only when it happens outside a game (e.g. a claim pushes you to 5 games); otherwise it's part of #3 | Active |
| 6 | **Weekly Track report** (opt-in, off by default) | Sunday, only if something changed | Passive |

**What we deliberately don't notify, and why**

- **Every round recorded or edited.** Everyone in the game is already at the table looking at the same screen, and edits show in-app with a banner and a Log badge. Pushing them would turn every typo fix into a buzz around the table.
- **Being overtaken on a leaderboard.** It's the most tempting rivalry ping, but it's a negative, out-of-context interruption you can't act on. It appears in Since you last looked and on the Track widget, where it's good news to discover when you choose to look.
- **Streak at risk / "you haven't played in a while".** Guilt loops don't fit a game played in person with friends. Kedro can't make the table happen, so it shouldn't nag.
- **Ambient "a game is happening near you".** It would need background location or Bluetooth tracking. Nearby discovery happens in the app, when you open it at the table. The direct invite (#1) covers the useful case.
- **Other people's achievements and games you weren't in.** Not your story, and it's noise.

---

## 6. Required recommendations (PRD Section 7, numbered 7a–7c)

### 7a. Leaderboard presentation and ranking

**Recommendation: one rank, driven by a single skill rating, with read-only category Spotlights. No user-selectable sort.**

**The rating.** A multiplayer pairwise Elo, in the "Track rating" family:
- Every finished game is decomposed into pairwise results between each pair of players at the table: finished ahead (1), tied (0.5), behind (0). Final cumulative score decides it, and shared wins are ties.
- Each pair updates Elo with K scaled by 1/(n−1), so an 8-player game moves your rating as much as a 3-player game, not 3.5× more. Start at 1500. K is higher (×2) for a player's first 10 games, so new players converge fast.
- It's derived: rebuilt by chronological replay of finished, non-abandoned games. Corrections can't happen after sealing, but claims and migrations change history, and replay keeps the numbers correct. Guests carry a hidden rating that becomes visible on claim.
- The rating **exists from game 1 but is revealed at game 5**, when the player reaches the Track. The reveal moment ("You're on the Track: 1521, #6 among your people") is the payoff for the Paddock.

**Why one rank, not several sortable ones**
1. **Rivalries need one number.** "I passed Jordan" only means something if there's one board. With multi-sort, everyone sorts by whatever flatters them, and the board stops settling arguments, which is the whole point of the product (PRD 1, "no arguments").
2. **Win rate and average score are confounded by table size.** Winning 1 of 3 at an 8-player table is excellent; at a 3-player table it's average. Average score depends on round count. A pairwise rating corrects for table size and opponent strength. Win rate would reward people who only play small tables.
3. **It rewards playing more without rewarding only volume.** Every game is a chance to climb, the K schedule moves newcomers quickly, and a big win over strong players is worth more than a big win over beginners.
4. **It fits the 5-game rule naturally.** Below 5 games a rating is mostly noise. Hiding it until 5 makes the threshold a reveal instead of a wall.

**What other skills get instead: Spotlights.** Above the board, read-only cards show leaders among ranked players for Knock success, Longest streak, Avg per round, and Most games. They give the knock artist and the grinder recognition without fragmenting the meaning of "rank". Each card opens a short top-10 list, and your own position in that category is shown when you're in it.

**Eligibility rules on the board**
- Ranked: 5+ finished, non-abandoned games. Rank numbers only appear here.
- **Paddock** (1–4 games): shown on Played-with with progress pips and **no rank**. On Global, shown as a counted community with faces and a "Who's close (4 of 5)" list. On profiles: "In the Paddock · 3 of 5".
- Ties in rating share a rank (`T12`).
- Unclaimed guests aren't shown on boards.

### 7b. Play-more incentives (across the whole app)

| Where | Incentive | Mechanism |
|---|---|---|
| Everywhere a sub-threshold player appears | **Paddock pips** (●●●○○) on avatar badges, profile, Join sheet, Track widget | The first goal is always visible |
| Join sheet / Lobby | **Stakes strip** | "Your 5th game: this one puts you on the Track", "Maya leads you 11–7" |
| Winner's Circle | **Your story** pays off rivalries, Track moves, and streaks, then **Rematch** is the primary button | The best moment to play again is right after a close finish |
| Game 5 | **Track reveal** with your rating and debut rank, shown to the whole table | Public celebration for the newcomer, plus social proof for the next one |
| Play tab | **Since you last looked** + **Next-game stakes** ("Win your next game and you pass Ava for #3") | A concrete, near-term target. These are all reachable in one game |
| Head-to-head | **Gap to level** ("3 more finishes ahead of Maya and it's level") | Turns a record into a goal |
| Achievements | **Close to unlocking** sorted first; locked rosettes show their exact progress | Visible, achievable next steps |
| Profile | **Streak** with "next win ties your best" | Positive framing, never loss framing |
| Widgets | Rival and Track widgets on the Home Screen | A passive, opt-in reminder of the story |
| Guests | The claim card sells *their* rivalries; hosts earn **Breaking In** when guests claim | Converts guests and rewards spreading |
| Learn | Finishing lessons earns **Schooled**; Table Coach turns off after 3 games | Learning counts as progress too |

Guardrails: no loss-framed notifications, no countdown timers, no paid boosts, no "come back" pushes. Incentives appear where people already look.

### 7c. Achievement catalog (25 rosettes)

All rules evaluate only finished, non-abandoned games, at seal. "Hand value" = the hand entered for that player, before knock adjustment.

| # | Rosette | Group | Unlock rule |
|---|---|---|---|
| 1 | **First Gallop** | Milestones | Finish your first game |
| 2 | **Out of the Gate** | Milestones | Win a game (shared wins count) |
| 3 | **Stayer** | Milestones | Finish 25 games |
| 4 | **Workhorse** | Milestones | Finish 100 games |
| 5 | **Clean Knock** | Knocks | Your first knock with the strictly lowest hand (−10) |
| 6 | **Iron Nerve** | Knocks | 3 clean knocks in one game |
| 7 | **Matched Stride** | Knocks | A tied knock (you knocked and tied for lowest) |
| 8 | **Thrown Shoe** | Knocks | Get caught on a knock (a consolation rosette, because it happens to everyone) |
| 9 | **Sure-Footed** | Knocks | 10 knocks in a row without getting caught (clean or tied), across games |
| 10 | **Royal Blush** | Moments | Finish a round with a negative hand value (only a red King can do it) |
| 11 | **Both Crowns** | Moments | Finish a round with a hand value of −2 (both red Kings) |
| 12 | **Ghost Hand** | Moments | Finish a round with a hand value of 0 |
| 13 | **Dead Heat** | Moments | Share a win (tied for the lowest final score) |
| 14 | **Wire to Wire** | Moments | Lead (or share the lead) after every round and win |
| 15 | **Dark Horse** | Moments | Win a game you were last in at the halfway round |
| 16 | **Photo Finish** | Moments | Win by 1 point |
| 17 | **Triple Crown** | Streaks | Win 3 games in a row |
| 18 | **Thoroughbred** | Streaks | Win 5 games in a row |
| 19 | **Herd** | Social | Play with 5 different people |
| 20 | **Stampede** | Social | Play with 15 different people |
| 21 | **Full Stable** | Social | Finish an 8-player game |
| 22 | **Turned the Tables** | Social | Finish ahead of your nemesis |
| 23 | **Breaking In** | Social | A guest you played with claims their history |
| 24 | **On the Track** | The Track | Finish your 5th game and earn a leaderboard placement |
| 25 | **Front Runner** | The Track | Reach #1 on your played-with board (with at least 5 ranked players on it) |
| — | **Schooled** *(bonus, not stat-derived)* | Learning | Complete all 5 Learn lessons |

That's 25 game-derived rosettes. Schooled is a 26th, learning-only badge shown separately, so it doesn't count toward game stats. If the catalog must be capped at 25, drop **Workhorse** for v1.

---

## 7. Visual identity

### 7.1 The horse spirit
- **Silks** are the identity system. Every player, guest included, gets jockey silks: one of 8 patterns (solid, hoops, stripes, chevron, diamonds, quarters, star, cross-belts) × two colors from a 10-color silks palette. Pattern plus color means **8 players at one table are always distinguishable without relying on color**, which also covers color-vision deficiency. Silks show as the avatar background, as a 3 pt stripe on standings rows, and in Live Activity dots.
- **Avatar**: a silks circle with a stylized horse-head profile in one of 5 coats (bay, chestnut, grey, black, palomino) and a marking (blaze, star, snip, none). It's generated from a name hash, so guests look like real competitors instantly, and it's editable in You.
- **Paddock / Track** frame progression. **Rosettes** are honors. **Horseshoe pips** show round progress. A **brass rail** marks the leader.
- **Tone**: a dash of the racetrack in headlines and celebrations ("Priya wins by a nose... well, by 1"), never in gameplay terms or rules.

### 7.2 Color
Semantic tokens in the asset catalog, each with light, dark, and Increase Contrast variants:

| Token | Light | Dark | Use |
|---|---|---|---|
| `paper` (background) | `#F5F1EA` warm racing-form paper | `#0B0B10` (existing BrandBackground ink) | Screen backgrounds |
| `card` | `#FFFFFF` | `#17171F` | Grouped content |
| `ink` (primary text) | `#16151A` | `#F3F1EC` | Text |
| `brass` (accent) | `#8A5A0B` text / `#C8902E` fill | `#E7B04C` | Tint, leader rail, rosettes, primary buttons |
| `turf` (good: lower) | `#1D7A45` | `#45D08A` | Negative deltas, clean knocks, Live |
| `rosette` (bad: +10) | `#B8322A` | `#FF6F61` | Caught knocks, destructive |
| `muted` | `#6B6760` | `#9C99A3` | Secondary text |

Scoring semantics flip the usual finance colors: **lower is better**, so `−10` is green. Deltas always carry a sign and an arrow, so color is never the only signal. Brass is used as a fill under dark text, and as text only in the deeper variant (≥ 4.5:1 on paper).

### 7.3 Type
SF only. **SF Pro** for UI. **SF Pro Expanded** (`.fontWidth(.expanded)`) for big headlines and rank numbers, which gives a race-poster feel inside the system family. **SF Pro Rounded** for score chips. `.monospacedDigit()` on every score so standings don't jitter as numbers change. Text styles only (`.largeTitle`, `.title2`, `.headline` ...), so Dynamic Type scales everything.

### 7.4 Iconography
SF Symbols throughout (`figure.equestrian.sports`, `flag.checkered`, `suit.*.fill`, `book`, `arrow.triangle.2.circlepath`). A handful of custom SF Symbols built from the SF template, so they scale with weight and Dynamic Type: **knock** (knuckle tap), **horseshoe** (clean knock / pips), **thrown shoe** (caught), **rosette**, **silks**.

### 7.5 Motion
- **Gallop re-sort**: standings rows slide past each other with `.snappy` springs when a round lands. Rank change ▲ markers fade after one round.
- **Numeric roll** on cumulative scores via `.contentTransition(.numericText())`.
- **Reveal** (self-report): hand values flip in together with a 60 ms stagger.
- **Rosette unfurl + horseshoe sparkle** at the Winner's Circle (`KeyframeAnimator`, `Canvas` particles), plus `.sensoryFeedback(.success)`.
- **Reduce Motion**: all of these become crossfades. No particles, no stagger. Numbers update without rolling.

---

## 8. Accessibility

| Area | Approach |
|---|---|
| **Dynamic Type** | Text styles everywhere. Standings rows use `ViewThatFits` to switch from a single line (rank · name · score · delta) to a two-line stack at accessibility sizes. The keypad keeps 64 pt keys and reflows to a full-width layout. The pips row becomes "Round 7 of 10" text at AX sizes. Tested to AX5. |
| **VoiceOver** | Standings rows are combined elements with full sentences (2.7). The knock badge reads its math sentence. The keypad keys are labeled ("minus", "delete", "next player"). Round entry announces "Jordan, hand 4, tied knock, scores 4". Round rows have custom actions (**Edit round**, **Why?**). Edits post an announcement ("Maya edited round 3"). Charts carry `AXChartDescriptor`s. The Winner's Circle announces the winner first. |
| **Reduce Motion** | See 7.5. Also no auto-advancing highlight carousels. |
| **Color & contrast** | All text ≥ 4.5:1, large numbers ≥ 3:1. Silks use pattern plus color. Deltas use sign plus arrow plus color. Increase Contrast variants for every token. Differentiate Without Color adds glyphs on outcome badges (already present). |
| **Light & dark** | Every frame is designed for both (Frames 5–6 show the live game in each). Paper vs ink backgrounds. Liquid Glass materials adapt automatically. |
| **Motor** | 44 pt minimum targets, 64 pt keypad keys. No gestures without a button equivalent (swipe-to-remove has a menu equivalent). The Final check window can be extended by tapping, never just a timed trap. |
| **Cognitive** | One primary action per screen in the live game. Plain-language rule sentences. Table Coach for newcomers. |

---

## 9. SwiftUI implementation map

| Screen / feature | Native components and APIs | UIKit needed? |
|---|---|---|
| App shell | `TabView` + `Tab`, `Tab(role: .search)`, `tabViewBottomAccessory` (live-game mini bar), `.tabBarMinimizeBehavior(.onScrollDown)` | No |
| Onboarding | `SignInWithAppleButton` (AuthenticationServices), `TabView(.page)` for steps, `#if DEBUG` test sign-in | No |
| Play | `NavigationStack`, `ScrollView` + `LazyVStack`, `.task` for discovery, `ContentUnavailableView` for no nearby tables | No |
| Proximity / join | Network framework `NetworkBrowser` / `NetworkListener` / `NetworkConnection` with peer-to-peer (Bonjour, `NSBonjourServices`, `NSLocalNetworkUsageDescription`). Fallback `MultipeerConnectivity`. `NearbyInteraction` `NISession` for distance (`NSNearbyInteractionUsageDescription`). | No (all non-UI frameworks) |
| Lobby / setup | `List` with `.onMove`, `Stepper`, `Picker(.segmented)`, `.sheet(item:)` for Add player, `.searchable` | No |
| Live game | `.fullScreenCover`, `NavigationStack`, `Picker(.segmented)`, `List` with animated reorder, `.contentTransition(.numericText())`, `.buttonStyle(.glassProminent)`, `.glassEffect()` banners, `.toolbar` with `Menu`, `confirmationDialog` | **Yes, keep-awake:** `UIApplication.shared.isIdleTimerDisabled` has no SwiftUI equivalent. Isolated in a tiny `IdleTimer` helper toggled by the live view's `scenePhase`/appear lifecycle, with the required explanatory comment. |
| Round entry | `.sheet` with `.presentationDetents([.large])`, custom keypad in `Grid`, `@FocusState`-like cursor in the model, `.sensoryFeedback`, `.disabled` for Save | No (custom keypad because the system number pad lacks a minus key) |
| Rounds / round detail / log | `List`, `Section`, `.swipeActions`, `.accessibilityAction(named:)`, `NavigationLink(value:)` + `navigationDestination(for:)` | No |
| Final check / Winner's Circle | `TimelineView`, `KeyframeAnimator`, `PhaseAnimator`, `Canvas` (particles), `ImageRenderer` + `ShareLink` | No |
| Guest claim handoff | `ShareLink` (AirDrop/Messages), Core Image `CIFilter.qrCodeGenerator()` → `Image(decorative:scale:)` | No. An in-app QR *scanner* would need VisionKit `DataScannerViewController` (UIKit), so v1 relies on the system Camera and universal links plus manual code entry instead. |
| Profile / stats | `Grid`, Swift Charts (`BarMark`, `PointMark`), `AXChartDescriptorRepresentable` | No |
| Head-to-head | `Gauge`/custom tug bar, Swift Charts timeline, `NavigationLink(value:)` | No |
| Track | `Picker(.segmented)`, `List` with pinned own row (`.safeAreaInset(edge: .bottom)`), `ScrollViewReader` / `.scrollPosition` for Around me | No |
| Achievements | `LazyVGrid`, `Gauge(.accessoryCircular)` style rings, `.navigationTransition(.zoom)` into detail | No |
| Rules / Learn | `List` + `.searchable`, `Slider` (knock gamble), `rotation3DEffect` card flips, `TipKit` for Table Coach tips | No |
| Live Activity / Dynamic Island | ActivityKit `Activity`, `ActivityConfiguration`, `DynamicIsland` regions, `LiveActivityIntent` buttons, APNs push tokens | No |
| Widgets / Control | WidgetKit `AppIntentConfiguration`, accessory families, `ControlWidget`, App Group container, `WidgetCenter.reloadTimelines` | No |
| Notifications | `UserNotifications` with `interruptionLevel` (`.timeSensitive`, `.passive`), notification categories with actions | No |
| App Intents | `AppIntent`, `AppShortcutsProvider` (Start a table, Record round) | No |
| Sync engine | `@Observable` game store, Swift concurrency actors, SwiftData (or SQLite) local event log, `BGTaskScheduler`-free upload on foreground + `.task` | No |

Only **keep-awake** requires UIKit. The QR scanner is the one feature deliberately designed out to avoid it.

---

## 10. Tap and time estimates

Assumptions: phones are unlocked with Kedro installed (except where stated). Hand values are about half single-digit and half two-digit.

### 10.1 Recording one round, 5-player table, scorekeeper mode

| Step | Taps |
|---|---|
| Record round 7 | 1 |
| Choose knocker | 1 |
| 5 hands: about 1.5 digit taps + 0.5 Next taps each (2-digit values auto-advance) | ≈ 10 |
| Save round | 1 |
| **Total** | **≈ 13 taps · 10–15 s** |

A negative hand adds 1 tap (−). Cards mode is optional and slower (one tap per card). In **self-report**, each player does about 4 taps (Enter my hand, 1–2 digits, Submit) **in parallel**, so wall time is about 6–8 s, set by the slowest player. The knocker's "I knocked" is one of those taps.

### 10.2 Getting 5 returning players into a game

| Who | Steps | Taps |
|---|---|---|
| Host | Start a table → (seats fill) → Start (defaults from last game) | 2 |
| Each of 4 joiners | Open Kedro → Join on the nearby card | 1 each (4) |
| **Total** | | **6 taps · ≈ 15–20 s**, mostly people unlocking phones |

Rematch afterward: 2 taps for the proposer, 1 for each other player. Fallback without proximity: Run it back (1) + Start (1) for the host, plus 1 tap on the "Added to a table" notification for each player.

### 10.3 A first-time guest joining

| Scenario | Steps | Taps / time |
|---|---|---|
| Guest with **no app** (most common) | Host: Add player → Guest → type name (≈ 4 letters) → Add | ≈ 7 taps · ≈ 8 s. **Zero for the guest.** |
| Guest who **just installed** Kedro | Join a table first → Looks good (silks) → type name → Join on the nearby card | ≈ 9 taps · ≈ 25 s (excluding download), no account needed |
| Guest **claiming afterward** | Open link from AirDrop → Sign in with Apple (2) → Claim | ≈ 4 taps · ≈ 15 s |

---

## 11. Edge-case index

| Case | Where handled |
|---|---|
| No knocker chosen | Save disabled, explanation shown (2.5, 2.6) |
| Knocker mismatch in self-report | Blocking chooser, logged (2.6) |
| Negative hands / below −2 | − key; floor validation (2.5) |
| Two phones save the same round | First save wins; the other sees "already saved · View" (2.4) |
| Concurrent offline edits | Lamport + device ID resolution, superseded entry logged (2.14) |
| A phone leaves mid-game | "Out of reach" pill; others continue; merge on return (2.14) |
| Late phone / guest seat takeover / newcomer | Three mid-game join cases (2.2 C) |
| Table drops below 3 phones | Fine. Seats are people, not phones. Scorekeeper mode needs only one phone. |
| Planned rounds reached | Final check → seal (2.10) |
| Accidental End / Abandon | 15 s window with Keep playing (2.10) |
| Shared win | Dead heat presentation; every co-winner credited (2.11, 7c #13) |
| Claim code reused | "Already claimed" (2.13) |
| Abandoned game | Greyed in history, excluded everywhere (2.10, 3) |
| Release build | No test sign-in (`#if DEBUG`) (2.1) |
