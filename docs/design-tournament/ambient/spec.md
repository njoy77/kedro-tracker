# Kedro for iOS: "Ambient Table"
### Design tournament entry · spec v1 · October 2026

Companion file: [`mockups.html`](./mockups.html) has 20 iPhone frames, and the frame numbers (F1–F20) are cited throughout this spec.

---

## 0. Design thesis

**The game shouldn't live on one screen. It should live in the room.** A Cambio night happens on a table, between a handful of phones that are already within arm's reach of each other. Ambient Table treats those phones as one shared object, a *table*. A table forms the moment someone opens Kedro, other phones nearby find it without anyone typing, and it stays in sync over Bluetooth and peer‑to‑peer Wi‑Fi whether or not anyone has internet. Most of the time the game isn't even "in the app": it's in the Dynamic Island, on the Lock Screen of a phone lying face‑up next to the discard pile, and in one tap on a Live Activity. Between games it stays out of the way on the Home Screen as a rivalry, a rank, or a horseshoe that's three nails away from the leaderboard. Kedro takes over the screen for only two moments: entering a round, and the finish.

| PRD goal | How Ambient Table delivers it |
|---|---|
| **Fast table flow** | Marking the knocker takes one tap at the moment of the knock, so it's done before reveal. The scorekeeper enters hands on a purpose‑built keypad with live scoring previews (about 15 taps for 5 players). In self‑report mode everyone types their own hand in parallel, so the table's wait is the slowest single player (about 4 s). Phones can lock: the Live Activity is the scoreboard. |
| **Everyone joins** | Proximity discovery (Network framework peer‑to‑peer + Bonjour, ranked by Nearby Interaction distance) surfaces a **Table card** on every nearby phone. Returning players tap **Sit down** once. Guests need a typed name and nothing else, and they can follow along in an App Clip without installing anything. |
| **People come back** | Rank, rivalry, and progress widgets; a "first five" horseshoe that fills nail by nail; head‑to‑head records that update the moment a game ends; achievements with visible progress; a Rematch button that's always one tap away. |
| **Spreads to new tables** | An interactive four‑minute Learn path, a scoring screen that explains every knock in a sentence, App Clip join for people without the app, and a claim code handed over by AirDrop at the finish line, so a guest's first game becomes their first stat. |

**Principles I hold myself to**

1. **Glanceable over interactive.** If information can be shown on a system surface the user is already looking at, it goes there before it goes into a screen.
2. **One tap at the moment it happens.** Each fact gets captured when it becomes true: the knocker at the knock, the hands at the reveal.
3. **The table is the trust boundary.** Being physically together is the security model for joining. Transparency is the security model for edits.
4. **Horse spirit is the brand, never the vocabulary.** Knocking stays "knocking", rounds stay "rounds", and hands stay "hands". The horse lives in avatars, the leader mark, achievements, and motion.

---

## 1. Information architecture and navigation

### 1.1 Top level

A `TabView` using the iOS 26 `Tab` API with a Liquid Glass tab bar and four tabs plus a search tab:

| Tab | SF Symbol / custom | Purpose |
|---|---|---|
| **Table** | custom `kedro.table` (a ring of seats) | The "now" tab. With no game, it's the **Radar**: nearby tables, Start a table, rematch suggestions, recent games. With a game in progress, it's the **live game**. |
| **You** | `person.crop.circle` with your marking | Profile, lifetime stats, rivals (head‑to‑head), achievements, game history, claim a guest history, settings. |
| **Ranks** | custom horseshoe | Leaderboards: Played‑with (default) and Global, plus the Community section. |
| **Learn** | `book.pages` | Lessons, interactive drills, full rulebook. |
| **Search** (`Tab(role: .search)`) | `magnifyingglass` | Find any Kedro player and open their public profile. |

### 1.2 The game as "Now Playing"

An active game follows the Music app's Now Playing pattern, which iOS 26 makes native:

- On the Table tab, the live game *is* the tab content (F4/F5). While it's on screen, the tab bar hides (`.toolbarVisibility(.hidden, for: .tabBar)`) and the **knock dock** takes its place, so the scores get the whole screen. The chevron at the top left **minimizes** the game: the tab bar comes back and the game moves into the bottom accessory.
- On every other tab, the game rides in the tab bar's **bottom accessory** (`.tabViewBottomAccessory`). It's a glass capsule showing round progress, your rank, and the leader, and tapping it returns to the game. You can check a rival's record mid‑game without "leaving" the table.
- Round entry, round detail, the rulebook, and the game menu are **sheets** over the live game with detents, so the standings always stay partly visible.
- The game end moment is a `fullScreenCover`. It's the one place Kedro takes over the whole screen.

### 1.3 Navigation map

```
TabView
├─ Table ─ NavigationStack
│   ├─ Radar (no game)                 F2
│   │   ├─ Table card → Sit down       (sheet: confirm seat when not auto‑accepted)
│   │   ├─ Start a table → Lobby       F3
│   │   └─ Recent game → Game record (read‑only, immutable)
│   └─ Live game                        F4, F5
│       ├─ sheet: Enter round (scorekeeper)     F6
│       ├─ sheet: Report hand (self‑report)     F7
│       ├─ segment: Rounds → Round detail → Edit   F8
│       ├─ segment: Log (audit trail)           F9
│       ├─ sheet: Rules (mid‑game)              F16 content
│       ├─ menu: Add rounds · End early · Abandon · Hand off scoring · Show join code
│       └─ fullScreenCover: Finish          F10 → Hand‑off sheet (guest claim) F11 → Rematch
├─ You ─ NavigationStack
│   ├─ Profile + stats                  F12
│   ├─ Rival → Head‑to‑head             F13
│   ├─ Achievements                     F15
│   ├─ Game history → Game record
│   └─ Claim a guest history (code entry)
├─ Ranks ─ NavigationStack              F14
├─ Learn ─ NavigationStack              F16
└─ Search ─ NavigationStack → Profile (any player)
Outside the app: Live Activity (F17), Dynamic Island (F18/F19), widgets (F18), Control Center control, notifications, App Clip.
```

Deep links (`kedro://` and universal links `https://kedro.app/...`) are routed by an `@Observable Router` that owns the `NavigationPath` per tab: `/t/<tableToken>` (join), `/claim/<code>`, `/game/<id>`, `/game/<id>/report` (open the hand sheet), `/player/<id>`.

---

## 2. Joining a co‑located table

### 2.1 Mechanism: the "Table Link"

| Layer | Framework | Role |
|---|---|---|
| Discovery + transport | **Network framework** (iOS 26 Swift‑concurrency `NetworkListener` / `NetworkBrowser`, Bonjour service `_kedro-table._tcp`, peer‑to‑peer enabled) | Every seated phone advertises the table. Every phone with Kedro in the foreground browses. Peer‑to‑peer (AWDL) means it works with **no Wi‑Fi network and no internet**. The TXT record carries a table ID, host name, seat count, round state, and a rotating 30‑second table token. |
| "At *this* table" | **Nearby Interaction** (UWB on iPhone 11 and later) | After connecting, phones exchange `NIDiscoveryToken`s and measure distance. Tables within about 3 m are labeled **At your table**; farther ones are **Nearby**. Bringing two phones within 10 cm triggers **touch to sit** (an optional flourish, not a required path). |
| Background awareness | **Core Bluetooth** (service‑UUID advertising from seated foreground phones, background scanning with state restoration on others) | Lets a locked phone in a pocket learn that a table with someone you've played with is right here, which drives the single *Nearby table* notification (§9.3). Best‑effort only, never the sole path. |
| Background state link | Core Bluetooth (`bluetooth-central` background mode, small GATT characteristic carrying compact game state) | Keeps Live Activities updating offline while phones are locked (§9.1). |
| Online | Supabase Realtime + APNs | With internet, the backend is simply another peer: real‑time fan‑out, Live Activity push, and the durable record. |
| Fallback | Universal link + QR (Core Image `qrCodeGenerator`) | **Show join code** from the game menu. The Camera app opens Kedro (or the App Clip). This covers older phones, Local Network permission denied, or a crowded venue. |

**Trust model.** Proximity is the credential. A person you've **played with before** sits down instantly, and the host sees them arrive (with a 5‑second "Remove" affordance on the arrival toast). Someone you've **never played with** sees **Ask to sit**, and the host or any seated player taps **Let in**. The table token rotates, so a screenshot of the QR goes stale.

### 2.2 Flow A: a full table of returning players (5 players, nobody types anything)

1. **Maya** opens Kedro. The Table tab is the Radar. She taps **Start a table** (1 tap). The lobby appears with her seat filled, using last time's settings: 10 rounds, Scorekeeper (F3).
2. **Noah, Leo, Priya** open Kedro (or tap the *Maya's table is right here* notification). Each Radar shows a **Table card** rising from the bottom: *Maya's table · at your table · Maya, Leo +1* with their faces (F2). Each taps **Sit down** (1 tap each). Because they've played with Maya, they're seated immediately. On Maya's phone, the seat fills with a soft "canter" animation and a light haptic.
3. **Sam** (no app) is added by Maya as a guest (§2.3).
4. Maya taps **Deal** (1 tap). Every phone switches to the live game at the same time and starts its Live Activity.

*Total: host 2 taps, each returning player 1 tap. About 10–15 s of wall time, mostly people unlocking phones.*

### 2.3 Flow B: a table with a guest

- **Host‑added guest (no app):** in the lobby, **+ Guest** → type a name (first name is enough) → **Add**. The guest gets a seat with a generated *unbranded* marking (a dashed‑outline horse; see §12.2). A guest has no account, no app, and no permissions. In Scorekeeper mode the scorekeeper enters their hand. In Self‑report mode anyone can **Report for Sam** (logged as reported‑by).
- **Guest with a phone, no app (App Clip):** the host taps **Show join code** and the guest points their Camera at it. The **Kedro App Clip** opens without an install: *You're joining Maya's table. Which seat is yours?* → tap **Sam** (or **I'm new here** → type a name). The guest now sees live standings and can report their own hand. App Clips are online‑only in this design, so if the table is offline the guest simply watches the host's screen, and the PRD's "someone reports for them" rule applies.
- **Guest who installs the app later:** the claim flow at the game end (§7) turns the guest seat into their account.

### 2.4 Flow C: mid‑game joins

| Situation | Behavior |
|---|---|
| **Your seat already exists** (the host added you from Played‑with before you opened the app, or your phone died and restarted) | The Table card reads *Your seat at Maya's table · Round 5 of 10 · You're 3rd (35)*. Tap **Take your seat**. Your phone catches up by syncing the event log from any peer in under a second, then starts its Live Activity. |
| **A guest seat is taken over by a device** (Sam opens the App Clip at Round 6) | **That's me** on Sam's seat binds the device. It's logged: *Sam's seat linked to a phone*. |
| **A new person arrives mid‑game** | They can **Watch**: a read‑only live view that doesn't count as being in the game (spectators can't edit). They're also put **On deck**, which seats them automatically in the Rematch lobby. *Rationale:* the canonical ruleset doesn't define a mid‑game entry score, and inventing one (for example "start at the highest total") would be a house rule, which is a non‑goal. **Flagged as an open product question**: if the PRD later allows mid‑game entry, the seat model already supports adding a seat at round *n*. |
| **Table is full (8)** | The card shows *Table full · 8 seated* with **Watch**. |
| **Two tables in one room** | The Radar stacks cards, nearest first by UWB distance. Each card shows the seated faces so you pick yours by people, not by an ID. Without UWB, cards are ordered by played‑with overlap, then recency. |
| **Host's phone dies in the lobby** | Host duties (settings, Deal) pass to the earliest‑seated remaining phone. After Deal there is no host: every seat is equal (PRD 4.5). |
| **Local Network permission denied** | The Radar shows a `ContentUnavailableView`: *Kedro can't look for tables* · **Allow in Settings** · **Scan a join code instead**. |

### 2.5 Rematch

At the finish (F10), **Rematch** is the primary button for everyone. The first person to tap it opens a lobby with **the same seats, rounds, and scoring mode** pre‑filled, plus anyone who was On deck. Each other phone shows a Table card: *Rematch at Noah's table* → **I'm in** (1 tap). Players who don't respond within the lobby are listed as *Not sitting yet*, and the host can Deal once 3 or more are in. Guests carry over without retyping. *Rematch total: 1 tap for the initiator plus 1 per player, then Deal.*

---

## 3. Game setup (the Lobby, F3)

The lobby is a single screen, not a wizard. Every setting has a remembered default, so most games start with zero setup taps.

- **Seats:** an oval "table" with up to 8 seat positions. Seats fill as people Sit down. **+ Add** offers *Played with* (sorted by most recent, with frequent tablemates first), *Search Kedro*, and *+ Guest*. A player added from Played‑with who isn't nearby shows as *Seat saved, waiting for phone*, which is valid because they can be scored for. A long press on a seat offers Remove or Make scorekeeper.
- **Planned rounds:** chips for **5 · 8 · 10 · Custom** (a stepper from 1 to 30). The default is last game's value, or 8 the first time. A caption says *About 40 min at this table size*, based on your history.
- **Scoring:** a segmented control, **Scorekeeper** | **Everyone reports**, with a one‑line explanation under each. Kedro *recommends* one: Everyone reports when every seat has a linked phone, and Scorekeeper when there's an unlinked guest. The recommendation is just the default selection, and the host can change it.
- **Scorekeeper** (Scorekeeper mode only): the host by default. During the game anyone can **Take over scoring** (logged).
- **Validation:** **Deal** stays disabled until 3–8 seats are filled. The footnote says why: *Cambio needs at least 3 players*.

Planned rounds and scoring mode are written as the first two events in the game's log (F9).

---

## 4. Recording a round

### 4.1 The knock is captured when it happens

The live game's bottom dock is always a **"Who knocked?"** strip of seat avatars (F4). When someone knocks at the table, anyone (usually the scorekeeper, or the knocker themselves) taps that avatar: **1 tap**. Then:

- Every phone and every Live Activity shows *Maya knocked · last turns* (a silent alert update, with no sound at the table).
- The dock changes to **Enter hands** (Scorekeeper) or **Report your hand** (Self‑report).
- Knocker changes are allowed and logged. There's no "no knock" option anywhere: the round's data model requires a knocker, and the Record button stays disabled until one is set (PRD 2.5).

The knocker can also tap **I knocked** on their own Live Activity without unlocking (a `LiveActivityIntent`).

### 4.2 Scorekeeper mode (F6)

A large‑detent sheet over the game:

1. **Header:** *Round 5 · Noah knocked* (tap to change).
2. **Seat list:** one row per player, **starting with the knocker** and then clockwise around the table. Entering the knocker's hand first means the rule line can say straight away what beats the knock. The active row is highlighted. Each row shows the typed **hand** and, at the right, the **round score preview**.
3. **Keypad:** a purpose‑built pad with 0–9, **±**, ⌫, and a wide **Next ›**. It isn't the system keyboard, because ± is a first‑class key, the layout never shifts, and the targets are 64 pt.
4. **Live rule line** above the keypad, in plain language that updates as you type:
   *"Noah has 3, the lowest so far. If it holds, Noah scores −10 (knock succeeded)."*
   *"Sam has −1, lower than Noah's 3. Noah scores 3 + 10 = 13 (knock beaten)."*
5. **Cards helper** (the **Count cards** toggle on any row): a strip of card chips **A 2…10 J Q K♠ K♥ 🃏**. Tapping chips sums the hand (K♥ = −1, Joker = 0), which is ideal for learners and arguments. The typed value and the chip total are the same field.
6. On the last row, **Next** becomes **Record round**. Kedro applies §2.6 automatically, closes the sheet, and the standings re‑sort with deltas on every phone.

**Validation:** hand values run from **−2** (both red Kings, the lowest legal hand) to 99. Values above 52 ask *That's high, double‑check?*, which is non‑blocking because penalty cards can make hands large. Every row must have a value. A row can't be skipped, because every player has a hand.

**Negative values:** tap ± before or after the digits. The value shows with a true minus (−1) and is announced as "minus one" by VoiceOver.

### 4.3 Self‑report mode (F7)

1. After the knocker is set, every linked phone shows a glass card in the dock: **Report your hand**. The Live Activity shows the same button, which deep‑links straight into the sheet.
2. The sheet has a compact keypad, a Cards helper, and the live rule line, which is personal: *"Leo knocked with 5. Your −1 is lower, so if it holds Leo scores 15."*
3. **Report −1** → done (about 3–4 taps). The value is visible to the table immediately, because cards are face up at the table anyway, so there's nothing to hide.
4. **Round status** appears at the top of everyone's sheet and dock as seat chips with ✓ (reported) and … (waiting). Unlinked guests show **Report for Ava**, which anyone can tap. A linked player who's slow can be reported for too, after 20 seconds (*Report for Priya*), logged as *Noah reported for Priya*.
5. When the last seat reports, the round **completes automatically** on all phones: a one‑second reveal animates each score into place, then the standings re‑sort.
6. **Knocker conflict:** if two phones set different knockers concurrently, the round shows *Who knocked: Maya or Leo?* and won't complete until someone picks. It never guesses.
7. Players can change their own report until the round completes. After that, it's an edit (§6).

### 4.4 What the app computes (and always shows its working)

For each round: hand values plus the knocker → round scores per PRD §2.6, and a **knock outcome** that's one of:

| Outcome | Badge (shape + color + text, never color alone) | Explanation template |
|---|---|---|
| Strictly lowest | ✓ **−10** green | "Noah knocked with 3, lower than everyone. Flat −10, hand ignored." |
| Tied for lowest | **=** amber | "Leo knocked with 5 and tied Priya's 5. Leo scores his hand: 5." |
| Beaten | ✕ **+10** red | "Priya knocked with 1, but Sam had −1. Priya scores 1 + 10 = 11." |

The explanation appears in the round detail, in the round history, on the Live Activity's expanded view, and as the VoiceOver label of the outcome badge. This is how the live game teaches the rules (PRD 4.7).

---

## 5. During the game: live standings, deltas, history, progress (F4, F5, F8)

**Header:** the table name (*Thursday table*, editable), **Round 5 of 10** with a 10‑pip progress row (completed pips filled, the current one pulsing), the **sync pill** (§8), and toolbar buttons **?** (rules) and **⋯** (menu).

**Segments:** **Standings** | **Rounds** | **Log**.

**Standings (default):**
- Rows sorted by cumulative total, lowest first. Each row has the rank, marking avatar, name, a subtitle (*Leads by 15*, *Knocked R4 ✕*), a **last‑round delta chip** (+13, −10 ✓), and the **total** in large SF Pro Rounded monospaced digits.
- The leader wears the **horseshoe** (the leader mark). Tied totals share a rank (=2) and both wear it if tied for first.
- When a round records, totals roll with `.contentTransition(.numericText())`, rows re‑sort with a snappy spring, and delta chips pulse once. Under Reduce Motion, rows crossfade instead of moving.
- **You** are always marked with a ring and a "You" label, never with color alone.

**Rounds:** reverse‑chronological round cards. Each card shows the knocker, the outcome badge, every player's hand → score, and an *edited* dot if the round has been changed. Tap for **Round detail**: the explanation sentence, every value, who recorded it and when, the edit history for that round, and **Edit**.

**Progress:** the pips in the header, plus *1 round left* language near the end. The final round is marked *Final round* in the dock.

**Screen awake:** while the live game is on screen, the idle timer is disabled. It's re‑enabled the moment you leave the game view, background the app, or the game ends.

**Landscape "table display":** rotating the phone in the live game shows a big‑type scoreboard meant to sit in the middle of the table, with all totals, deltas, and round progress. The same layout serves StandBy through the Live Activity.

---

## 6. Corrections and the audit trail (F8, F9)

### 6.1 Editing a round

Any player in the game: **Rounds → Round 2 → Edit** → the same entry sheet, pre‑filled. Change any hand value or the knocker. Before saving, a **diff preview** shows:

```
Round 2 · edit by Leo
Priya   6 → 5
Knock   Leo ✓ −10  →  = tie (5)
Totals  Leo 2 → 17  ·  Priya unchanged
```

**Save edit** re‑runs §2.6, updates every phone, and posts a non‑blocking banner on every device: *Leo corrected Round 2 · View*. The round card gets an *edited* dot.

### 6.2 The Log (audit trail)

A chronological list, grouped by time, of every state change, each with who, when, and before → after:

- Game created · planned rounds · scoring mode · scorekeeper
- Seats added or removed · guest added (by whom) · seat linked to a phone
- Knocker set or changed
- Round recorded (scorekeeper) / hand reported (self‑report, including *reported for*)
- Round edited (full diff, knock outcome change, totals impact)
- **Rounds extended** (8 → 10) · **Ended early** · **Abandoned**
- Scoring handed off
- **Sync events:** *4 changes made offline synced* · *Round 4 recorded on two phones while apart, identical, merged* · *Leo's edit was superseded by Maya's later edit (both shown)*
- **Game sealed** (finished, now immutable)

Entries not yet synced to the backend carry a small clock glyph. The Log is visible to everyone in the game and stays readable forever on the game record.

### 6.3 Extending, ending early, abandoning (the ⋯ menu)

| Action | Interaction | Effect |
|---|---|---|
| **Add rounds** | Menu → *Add rounds* → +1 / +2 / +5 | Planned rounds increase. Logged. Pips extend with an animation. Also offered on the finish screen during the settle window. |
| **End early** | Menu → *End after Round 4* → confirmation dialog: "End now? The game counts fully in stats." | Goes to the finish moment (§7) with the current standings. Logged. |
| **Abandon** | Menu → *Abandon game* (destructive) → confirmation dialog: "Abandoned games stay in history, marked Abandoned, and don't count for stats, leaderboards, or achievements." | The game record is marked **Abandoned** (a gray banner on the record). Logged. |

Any player can do any of these.

### 6.4 The settle window ("photo finish review")

Ending is final, and finished games are immutable, so a typo in the last round would otherwise be permanent. When the planned rounds complete, or someone ends early or abandons, the game enters a **30‑second settle window** on every phone: *Final in 0:24 · Fix a round · Undo* (Undo applies to end‑early and abandon). Edits during the window are allowed and logged. When it closes, a **Game sealed** event is written and the record is immutable. The seal time is deterministic (HLC of the ending event + 30 s), so offline phones agree, and any edit stamped after the seal is rejected and logged as *Rejected: game already final*.

The PRD says the app "recognizes that the game is over" when the planned rounds complete, and that's still true here: the finish celebration starts immediately, and the settle bar only sits along its bottom edge.

---

## 7. The finish (F10) and guest claim (F11)

### 7.1 The game‑end moment

A `fullScreenCover` on every phone at the same moment:

1. **Winner reveal:** the winner's marking scales up inside a horseshoe laurel and the title reads *Noah takes it · 38*. On a tie: *Photo finish: Noah & Priya share the win* with both markings, both crowned, and both credited (PRD 2.7). Haptics: a three‑beat "canter" pattern. Under Reduce Motion: a crossfade and one haptic.
2. **Final standings:** compact, with totals and the gap to the winner.
3. **Highlights** (computed from rounds): *Best round* (lowest round score), *Clean knocks* (successful knocks by player), *Biggest comeback* (largest rank climb from the lowest point after Round 3), *Red Royal* (any negative hand), *Closest finish* (smallest gap between first and second).
4. **Personal strip** (yours, different on each phone): achievements unlocked this game, rating change, head‑to‑head changes (*You're now 8–13 against Maya*), and **first‑five progress** (*Priya is ranked! #540 globally*).
5. **Actions:** **Rematch** (primary) · **Share** (an `ImageRenderer` result card via `ShareLink`) · **Done**.
6. **Guests:** each unclaimed guest gets a row: *Sam played as a guest. Give them their history* → the Hand‑off sheet.
7. The **settle bar** along the bottom (§6.4).

### 7.2 Guest claim by link or code (F11)

- Every guest identity has a **claim code** (6 characters, ambiguity‑free alphabet, e.g. `HX7‑4QP`) and a universal link `kedro.app/claim/HX74QP`.
- **Hand‑off sheet:** a large QR code, the code in big monospaced type, and **AirDrop** / **Message** buttons (`ShareLink`). It also previews what they'll get: *1 game · 10 rounds · Red Royal earned*.
- Any player who shared a game with that guest can reopen the hand‑off later from the game record until it's claimed. The code is the same for that guest identity across every game it played (PRD 3.2).
- **Claiming:** the guest opens the link → the App Clip or app → **Sign in with Apple** → *Claim Sam's history? 1 game with Maya, Noah, Leo, Priya* → **Claim**. The guest's games, rounds, stats, rivalries, achievements, and leaderboard progress become theirs, recomputed from the recorded rounds. Their marking changes from dashed to filled, and they pick a coat (they keep the generated one by default).
- **Typed‑code path:** You → *Claim a guest history* → enter the code.
- **Already claimed:** *This history already belongs to a Kedro player.* No details are revealed.
- **Legacy web identities** (PRD 9) use exactly the same flow. They appear in Played‑with lists as *noahj (web)*, with dashed markings, and any player who shared a legacy game with them can hand off the code.

---

## 8. Offline play and resync

### 8.1 Data model (summary for design)

Each game is an **append‑only event log**: `SeatAdded`, `KnockerSet`, `HandReported`, `RoundRecorded`, `RoundEdited`, `RoundsExtended`, `EndedEarly`, `Abandoned`, `Sealed`. Every event has a UUID, a hybrid logical clock (HLC) timestamp, an author, and a device. Each phone stores the log locally (SwiftData) and gossips it to peers over the Table Link and to the backend when online. State is a deterministic fold of the log, so:

- **No loss:** nothing is overwritten. Events only accumulate.
- **No duplication:** events are idempotent by UUID. Two phones that both recorded "Round 4" while partitioned are reconciled by round index. If the values are identical they're merged. If they differ, the version with the later HLC wins, and the other remains in the Log as a superseded edit, restorable by an edit.
- **Deterministic conflicts:** concurrent edits to the same field are ordered by (HLC, device ID). Every phone and the server compute the same result, and the Log shows both writes with *superseded*.

### 8.2 Sync states (always visible in the game header pill)

| State | Pill | Meaning |
|---|---|---|
| **Live** | ● green dot · *Live* | Connected to the backend, real time. |
| **Table only** | hoof‑link glyph · *Offline · 5 phones in sync* | No internet. Phones are syncing directly. Everything works. |
| **This phone only** | amber half‑circle · *Offline · 2 changes waiting* | No peers in range and no internet. Changes are safe on this phone. |
| **Syncing** | spinner · *Syncing 4 changes* | Reconnected, uploading. |
| **Synced** | transient check, then back to Live | A Log entry *4 offline changes synced* is written. |

Tapping the pill opens a small popover explaining the state in a sentence, with no jargon ("Everyone at the table is up to date. Kedro will back this game up when you're online.").

**Offline edge cases:**
- *Setup offline:* works fully. Played‑with lists and profiles are cached. Guests can be added. New users who've never signed in can't create an account offline, so they can be seated as a guest and claim later.
- *Game ends offline:* the finish works. The seal is computed locally and confirmed on sync. The Rating change and leaderboard placement show *Updates when you're online*. Achievements derived from this game unlock locally and are confirmed on sync.
- *Phone rejoins after being away:* it catches up from peers. If it made changes while alone, the merge rules apply and a Log entry explains the outcome.

---

## 9. System surfaces

### 9.1 Live Activity and Dynamic Island (F17, F19)

Starts automatically when you take a seat (in the foreground) or via push‑to‑start when online. One activity per game.

**Lock Screen / banner (F17):**
- Header: the Kedro mark, *Thursday table*, **Round 5 of 10** with pips, sync state.
- Body: standings for up to 5 players (top 4 plus you for larger tables), each with total and last delta. Your row is ringed.
- State line: *Maya knocked · last turns* / *Waiting on Priya, Ava* / *Leo corrected Round 2*.
- Buttons (App Intents): **I knocked** (sets yourself as knocker, without unlocking), **Report hand** (self‑report; opens the app straight to the hand sheet, because Live Activities can't take text input), and **Open**.

**Dynamic Island:**
- *Compact leading:* your rank inside a horseshoe (**3rd**). *Compact trailing:* **R5/10**, or after a knock, the knocker's avatar with a pulse.
- *Minimal:* the horseshoe with your rank number.
- *Expanded:* the top 4 standings with deltas, the last round's outcome sentence, and the same buttons.

**Updates:** online through ActivityKit push on a per‑game broadcast channel. Offline through the Bluetooth state link to the scorekeeper's or any foreground phone. When neither is available, the activity shows *Updated 9:42* (`staleDate` drives a dimmed state). Knocks use an alerting update with **no sound** and a light haptic. Round results update silently.

**End:** the final state shows the winner and your place, then dismisses after 1 hour.

**StandBy:** a phone docked sideways on the table shows the Live Activity full‑screen, which works as a shared scoreboard.

### 9.2 Widgets (F18)

| Widget | Family | Content |
|---|---|---|
| **First Five → Rank** | systemSmall, accessoryCircular | Before 5 games: a horseshoe with 5 nail holes filling in (*3 of 5 · 2 games to the leaderboard*). After that: **#212**, rating 1,184, a weekly movement arrow. |
| **Rival** | systemMedium | You vs your nemesis (or a pinned rival): finished‑ahead record, your last 5 meetings as dots, *last played Thu*. Tapping it opens head‑to‑head. |
| **Form** | systemMedium / systemLarge | Win rate, current streak, knock success, average per round, and a sparkline of final scores (Swift Charts in the widget). |
| **Streak** | accessoryRectangular (Lock Screen) | *Streak 1 · Best 3 · #212*. |
| **Start a table** | `ControlWidget` (Control Center, Lock Screen, Action button) | Opens Kedro straight to a new lobby. Puts the whole join flow one press away. |

Widgets refresh on game sealed (via `WidgetCenter.reloadTimelines`) and on rank change pushes. There's no live game state in widgets, because that's what the Live Activity is for.

### 9.3 Notifications

| Notification | When | Level | Cap |
|---|---|---|---|
| **A table is right here** · *Maya's table is starting nearby* · action **Sit down** | Background BLE sees a table with someone you've played with, and you're not already seated | Active | 1 per table, max 3 per day |
| **Your hand, please** · *Round 5: Leo knocked. Report your hand* | Self‑report mode, **only if your Live Activity is disabled** (otherwise the Live Activity button does this) | Time‑sensitive | 1 per round, and never repeated |
| **Game recap** · *Noah took Thursday table. You finished 3rd* | The game sealed while Kedro wasn't in the foreground on your phone (you left early, or the phone was away) | Passive | Per game |
| **You're on the board** · *5 games in. You're ranked #540* | Your fifth completed game | Active | Once ever |
| **Weekly ledger** (opt‑in) · *Up 4 places this week. Maya is 12 rating points ahead* | Sunday evening, only if you played that week | Passive | Weekly |
| **Claimed** · *Sam claimed their guest history. Your head‑to‑head now includes them* | A guest you played with claims | Passive | Per claim |

**What Kedro deliberately does not notify, and why:**
- **Every round recorded or edited:** the people at the table already saw it, and the Live Activity updates silently. Buzzing five phones on a table every two minutes is the opposite of "table comes first".
- **Achievements unlocked during a game:** they're celebrated at the finish, where everyone's looking anyway. Mid‑game interruptions would break play.
- **Every leaderboard movement:** that's noise. It's batched into the opt‑in weekly ledger.
- **"Your streak is at risk" or "We miss you":** guilt mechanics would erode trust in a social app. Kedro motivates through visible progress, not nagging.
- **Friends playing elsewhere:** Kedro is for in‑person play, so a notification about a remote game is pure FOMO you can't act on.
- **Other players' achievements:** they're on public profiles for anyone curious.
- **Marketing:** never.

Permission is requested **in context** after your first finished game (*Want to know when a table is starting near you?*), never at first launch.

### 9.4 App Clip

`kedro.app/t/...` and `kedro.app/claim/...` invoke the App Clip. It offers the live standings view, Report my hand, Learn the basics, and Claim (Sign in with Apple, then upgrade to the full app). It's online‑only by design, and offline guests are scored by the table.

---

## 10. Stats, head‑to‑head, leaderboards, achievements

All numbers are **derived from recorded rounds and games** and recomputed when edits, seals, or claims land. Abandoned games are excluded everywhere. Shared wins count as wins.

### 10.1 Profile + stats (F12)

- **Header:** a large marking, the display name, **Kedro Rating** (or *3 of 5 to rank*), Global rank, Played‑with rank, and the achievement count.
- **Form row:** current streak · win rate · knock success (three big tiles).
- **Stats list (every PRD 5.1 stat):** Games played · Wins · Win rate · Best game · Worst game · Average score per game · Average score per round · Current win streak · Longest win streak · Knock rate · Knock success rate · **Knock outcomes** (a three‑segment bar ✓ / = / ✕ with counts) · **Nemesis** (a card with their marking and *finished ahead of you 13 times*; tapping it opens head‑to‑head).
- **Chart:** final scores over the last 20 games (Swift Charts line with a win marker), with VoiceOver audio graph via `AXChartDescriptor`.
- **Rivals:** the 5 most‑played opponents with records. **See all** opens a searchable list.
- **Achievements:** a preview of recently earned items plus the **closest to unlock**, with progress.
- **Games:** history with Abandoned games shown and marked.
- Other players' profiles show the same layout (public, PRD 3.3), with **Head‑to‑head with you** pinned at the top.

### 10.2 Head‑to‑head (F13)

From any profile, Rivals list, Rival widget, or finish screen.

- **Face‑off header:** two markings facing each other with the **finished‑ahead record** large (*8 – 13*). The name of whoever leads is set in bold, with a text label (*Maya leads*).
- **Rows:** Games together · Finished ahead (each) · Wins in shared games (each) · **Knock outcomes when facing each other** (✓ / = / ✕ for each player side by side) · Average final score in shared games · Last 5 meetings (dots with ahead/behind glyphs) · Biggest margin.
- **Nemesis callout** when applicable: *Maya is your nemesis*.
- **Call to action:** *Next time you sit down with Maya, it's 8–13*. There's no remote challenge, because play is in person.

### 10.3 Leaderboards (F14) and the required ranking recommendation

**Recommendation: one official rank, sorted by a skill rating, with secondary "lenses" for bragging, not ranking.**

- **The official rank** (*#212*) is determined only by the **Kedro Rating**, a multiplayer skill rating (Weng‑Lin/OpenSkill Plackett‑Luce, which handles 3–8 players and shared places natively). It's computed by replaying every completed game in order, so it stays a derived stat. It's displayed as a friendly number around a 1,000 base, using the conservative estimate (μ − 3σ), so a lucky three games can't top the board.
- **Why rating rather than win rate:** winning a 3‑player game is about twice as likely as winning an 8‑player one, and win rate ignores who you beat. A rating rewards beating strong tables, isn't distorted by table size, and still moves visibly after every game. Average score is distorted by game length. Knock success rewards timidity, since knocking only with a sure hand inflates it.
- **Why *one* official rank:** the PRD's "one source of truth" applies to bragging too. *"I'm #3 at our table"* has to mean the same thing on everyone's phone. Fully multi‑sort boards make every player #1 at something, and the rank becomes meaningless.
- **Lenses:** chips above the list let you sort by **Win rate · Avg per round · Knock success · Games played**. A lens re‑sorts the list and shows each row's value, but rows keep their official rank badge, and the lens position appears as a secondary label (*3rd by knock success*). This gives more people something to be proud of, which is a play‑more lever, without fracturing the truth.
- **Scopes:** **Played‑with** (default, because it's the board people actually care about: you among everyone you've shared a table with) and **Global**. Your row is pinned at the bottom of the viewport while scrolling (*You · #3 · 1,184*).
- **Eligibility (PRD 5.3):** 5 completed, non‑abandoned games to hold a rank. Below that:
  - The list ends with a **Community** section: *Not yet ranked · riding toward their first five*. Each entry has the marking, name, and a **5‑nail horseshoe progress** (*3 of 5*). There's **no number**, sorted by progress then recency.
  - The Global header counts both: *1,240 ranked · 3,118 in the community*.
  - Your own pre‑eligibility view replaces the pinned row with *You · 3 of 5 · 2 games to your first rank*.
- **Ties:** equal ratings (after rounding) share a rank: **=12**.
- **Unclaimed guests** don't appear on leaderboards (PRD 3.3). After claiming, they appear with their full history.

### 10.4 Play‑more incentives (required recommendation)

Every surface has a reason to play one more game, and none of them nag.

| Where | Incentive |
|---|---|
| **First five** (the headline goal) | A horseshoe with 5 nail holes that fills one nail per completed game. It appears on the profile header, the Ranks pinned row, the widget, the finish screen (*nail 3 driven in*), and the Rematch button caption (*2 more games to rank*). Reaching 5 triggers *You're on the board* with your debut rank. |
| **Finish screen** | Rating change, head‑to‑head changes, achievements unlocked, and *closest next achievement* (*1 more successful knock for Gambler's Nerve*). Rematch is the primary action, and its caption names what's at stake (*Win and you tie Maya's streak*). |
| **Played‑with board** | *Close races*: highlights anyone within 15 rating points above or below you (*Leo is 6 points behind you*). |
| **Streaks** | Current streak on the profile, the Lock Screen widget, and the finish. *Longest streak* gives a target. There are no at‑risk notifications. |
| **Rivalries** | The Rival widget keeps a single relationship on the Home Screen. Head‑to‑head shows *Next time you sit down with Maya, it's 8–13*. |
| **Achievements** | Progress bars on locked items. The 3 closest are always shown on the profile and the finish screen. |
| **Radar (Table tab, no game)** | *Rematch the Thursday crew* card (the last table, with one tap to open a lobby with the same seats) and *Start a table* via Control Center or the Action button. |
| **Learning** | Finishing Learn awards *Saddle Up*, and the first game after it says *Your first real game, good luck*. Learners convert to players. |
| **Guests** | The claim hand‑off shows the guest what they'll keep (*1 game, an achievement, 4 games to rank*), which turns a guest into a player. |

### 10.5 Achievement catalog (required recommendation)

Twenty‑three achievements. Each is derived from recorded data (hands, knockers, games, seats), excludes abandoned games, and is recomputed on edits within the settle window and on claims. **Names carry the horse spirit, and descriptions always use plain game terms.** Tiers: Bronze (early, everyone gets them), Silver, Gold. Two are **secret** (shown as ?? until earned).

| # | Name | Tier | Unlock rule |
|---|---|---|---|
| 1 | **First Hoofprint** | Bronze | Complete your first game. |
| 2 | **Saddle Up** | Bronze | Finish the Learn path (all 5 lessons and the scoring drill). |
| 3 | **First Past the Post** | Bronze | Win a game (shared wins count). |
| 4 | **Clean Knock** | Bronze | Knock with the strictly lowest hand (−10). |
| 5 | **Bucked Off** | Bronze | Have a knock beaten (+10). *Knocking is a gamble, so we celebrate the nerve.* |
| 6 | **Dead Heat** | Silver | Knock and tie for the lowest hand. |
| 7 | **Red Royal** | Bronze | Finish a round with a negative hand value (only possible with a red King). |
| 8 | **Shod** | Silver | Complete 5 games and earn your first leaderboard rank. |
| 9 | **Photo Finish** | Silver | Share a win (tie for the lowest final score). |
| 10 | **Hat Trick** | Silver | Win 3 games in a row. |
| 11 | **Thoroughbred** | Gold | Win 5 games in a row. |
| 12 | **Gambler's Nerve** | Silver | 3 successful knocks in a single game. |
| 13 | **Dark Horse** | Silver | Win a game after sitting in the bottom half of the standings after Round 3 or later. |
| 14 | **Wire to Wire** | Gold | Lead (or co‑lead) after every round of a game of 5+ rounds, and win. |
| 15 | **Below Zero** | Gold | Finish a game with a negative final total. |
| 16 | **Trail Rider** | Bronze | Complete 10 games. |
| 17 | **Iron Hoof** | Silver | Complete 50 games. |
| 18 | **Centaur** | Gold | Complete 100 games. |
| 19 | **Stable of Ten** | Silver | Play with 10 different people (claimed guests count once claimed). |
| 20 | **Full Paddock** | Silver | Play a complete game at an 8‑player table. |
| 21 | **Spread the Herd** | Gold | A guest you played with claims their history. |
| 22 | **?? Nemesis Tamed** *(secret)* | Gold | Finish ahead of your current nemesis in 3 straight shared games. |
| 23 | **?? Zero Hour** *(secret)* | Silver | Successfully knock with a hand value of exactly 0. |

*(Iron Hoof and Centaur continue the Trail Rider line, so the catalog reads as 21 distinct moments plus a 3‑tier games‑played track.)*

**Presentation (F15):** a grid of medallions. Earned items are struck in the tier's metal with your coat color. Locked items are debossed, with a progress ring where the rule is cumulative (*Iron Hoof 23/50*). Tapping one shows a detail sheet with the rule, the date earned, the game it was earned in (tap through to the record), and the percentage of players who have it. Achievements are visible on public profiles.

---

## 11. Rules and learning (F16)

**Learn tab** = a path, a rulebook, and drills.

1. **The path: "Learn Cambio in 4 minutes."** Five short interactive lessons, each 30–60 s, with progress saved:
   1. *Your grid:* four face‑down cards in a 2×2, and you can't peek (tap to "try" peeking and get a gentle "not yet").
   2. *Card values:* swipe a deck. Each card flips to its points. The surprises are highlighted: **red King −1, Joker 0, black King 13**.
   3. *Power cards:* 7/8 peek own, 9/10 peek opponent, J/Q blind switch, black K look and switch, each with a tiny animated demo.
   4. *Sticking:* a discard appears and you tap the matching card in your grid before the timer runs out. A wrong stick shows the penalty landing in your hand value.
   5. *Knocking and the gamble:* the **Knock simulator**. Drag your hand value against the other players' hands and watch the outcome flip between ✓ −10, = tie, and ✕ +10, with the sentence explaining why.
2. **Drill: "Score this round."** Five quick rounds of revealed cards. You total each hand and pick the knock outcome, and you get instant feedback. It's the same Cards helper used in real round entry, so learning carries straight over.
3. **Rulebook:** the full canonical ruleset (PRD §2), searchable, in plain sections with the worked examples. Always reachable mid‑game from **?** in the live game toolbar, as a sheet whose medium detent keeps the standings visible.
4. **In‑game reinforcement:** every round's explanation sentence (§4.4). For players with fewer than 3 games, the Cards helper is on by default, and TipKit tips appear once each (*Tap who knocked the moment they knock*).
5. **Teaching at the table:** the host can turn on **Learner hints** per seat in the lobby. That seat's phone (or App Clip) shows a one‑line hint during the round (*Peek‑own: 7 or 8*), and the hand sheet explains the knock outcome in more detail.

---

## 12. Visual identity

### 12.1 Mood

A warm wooden table under a pendant light: oat paper, chestnut leather, ink. It's confident and calm during play, and it brings out the brass only at the finish.

### 12.2 Horse spirit

- **Markings (avatars).** Every player is a front‑facing horse head drawn in a few geometric shapes: a **coat** color (Chestnut, Bay, Black, Grey, Palomino, Dun, Roan, Cremello) and a **face marking** (Star, Stripe, Blaze, Snip, Bald), on a tinted disc. That's 40 combinations before backgrounds. Markings are real equine face patterns, which gives identity a bit of lore: *"What's your marking?"* A new user picks theirs at onboarding (F1b). A random one is pre‑selected and kept distinct from frequent tablemates. **Guests are unbranded**: a dashed outline horse, which fills in with color when they claim. Within a game, seats keep distinct coats.
- **The horseshoe** is Kedro's one recurring object: the leader mark on standings, the rank glyph in the Dynamic Island, the 5‑nail first‑five progress meter, and the laurel around the winner.
- **Motion has a gait.** Standings reorders use a quick, two‑beat spring (a "canter"), and the finish uses a three‑beat haptic. It's never a literal animated horse during play.
- **App icon:** a chestnut horse head with a white blaze on oat, inside a thin brass horseshoe.

### 12.3 Color (semantic tokens; light / dark)

| Token | Light | Dark | Use |
|---|---|---|---|
| `background` | #F6F1E8 (oat) | #0F0E0C | Screens |
| `surface` | #FFFFFF | #1C1A17 | Cards, rows |
| `ink` | #1C1A17 | #F4EFE6 | Primary text |
| `inkSecondary` | #6B655C | #A39C90 | Secondary text (≥ 4.5:1 on surface in both) |
| `accent` (chestnut) | #B4532A | #E68A5C | Primary buttons, You ring, links (5.0:1 on white) |
| `brass` | #A87A1E | #D9AE4A | Leader horseshoe, finish, gold tier |
| `knockSuccess` | #2E7D52 | #5CC98E | ✓ −10 |
| `knockTie` | #9A6B12 | #E3B341 | = tie |
| `knockFail` | #B83232 | #F07A7A | ✕ +10 |

Knock outcomes always pair color with a glyph (✓ = ✕) and text. Increase Contrast swaps to darker or lighter variants of each token. Glass surfaces use the system Liquid Glass materials. The app's own colors tint glass only on primary actions (`.glassEffect(.regular.tint(.accent).interactive())`).

### 12.4 Type

The **SF family only**, deliberately. It's native, it scales with Dynamic Type, and it has the number features scores need.
- **SF Pro** for all UI text, using text styles (`.body`, `.headline`, and so on), never fixed sizes.
- **SF Pro Rounded** (`.fontDesign(.rounded)`) with **monospaced digits** (`.monospacedDigit()`) for every score and total. Rounded numerals feel friendly at the table and stay unambiguous (the "1" and "7" read clearly). Monospacing stops columns from jittering as numbers roll.
- **SF Mono** for claim codes only, so `HX7‑4QP` can be read aloud.
- The display weight for the finish and large totals is `.largeTitle` bold rounded.

### 12.5 Iconography

SF Symbols everywhere, plus a small set of **custom SF Symbols** (exported templates so they get weights, scale, and Dynamic Type): `kedro.horseshoe`, `kedro.knock` (knuckles meeting a tabletop), `kedro.table` (a ring of seats), `kedro.hooflink` (offline peer sync), and `kedro.marking` (used as the "You" tab glyph when no avatar is loaded).

### 12.6 Motion

- Totals: `.contentTransition(.numericText(value:))`.
- Reorders: `.animation(.snappy, value: standings)`.
- Knock badge: a single scale pop with `.symbolEffect(.bounce)`.
- Table card arrival: rises from the bottom with `matchedGeometryEffect` into the lobby seat.
- Finish: a `TimelineView` + `Canvas` "hoof dust" particle burst lasting 1.2 s, then still.
- **Reduce Motion:** all position and scale motion is replaced by opacity crossfades, the particle burst is removed, and the pips stop pulsing (the current pip is shown with an outline instead).

---

## 13. Accessibility

- **Dynamic Type:** every text uses text styles. At accessibility sizes, standings rows switch to a two‑line layout (name on top, total and delta below) using `ViewThatFits`, and the keypad keeps 64 pt keys while the seat list becomes a single "current player" card with a progress indicator (*Player 3 of 5*). Live Activity layouts are tested at the largest supported sizes.
- **VoiceOver:**
  - Standings rows are single elements: *"Maya, first, 18 points, leads by 15. Last round plus 13."* The custom rotor *Players* jumps between rows.
  - Delta chips and knock badges read their meaning: *"Knock beaten, plus 10. Priya knocked with 1, Sam had minus 1."*
  - Keypad keys are labeled (*"Minus sign", "Delete", "Next player, Leo"*). The value field announces the provisional score after each keystroke.
  - Round entry offers an **accessibility alternative**: a standard `TextField` with the numbers‑and‑punctuation keyboard for users who prefer the system keyboard.
  - The live game posts announcements (`AccessibilityNotification.Announcement`) when a round records or an edit lands: *"Round 4 recorded. Maya leads with 18."*
  - Charts provide audio graphs (`accessibilityChartDescriptor`).
- **Reduce Motion:** see §12.6. The finish still feels like an event through the haptic, typography, and color.
- **Reduce Transparency:** glass falls back to opaque `surface`.
- **Color and contrast:** text meets 4.5:1 and large numerals meet 3:1 in both appearances. No meaning is carried by color alone (glyphs ✓ = ✕, a "You" label plus ring, a crown shape for the leader). Coats are distinguishable by marking shape as well as color for color‑blind players.
- **Light and dark:** full token parity (§12.3). The live game is shown in both (F4, F5).
- **Haptics** are always paired with a visual state, and respect the system haptics setting.
- **Hit targets:** at least 44 pt everywhere, and 64 pt on the keypad and knock strip, because people use these while holding cards.

---

## 14. SwiftUI implementation map

All views are SwiftUI on iOS 26. State uses `@Observable` models (`TableSession`, `GameStore`, `Router`) owned with `@State` and injected with `.environment`. Persistence uses SwiftData for the local event log and cached profiles. Concurrency follows Swift 6 strict concurrency.

| Screen / surface | Native components and APIs | UIKit? |
|---|---|---|
| App shell | `TabView` + `Tab`, `Tab(role: .search)`, `.tabViewBottomAccessory` (game mini‑player), `.toolbarVisibility(.hidden, for: .tabBar)` while the live game is on screen, `.tabBarMinimizeBehavior(.onScrollDown)` on the other tabs, `NavigationStack` + `navigationDestination(for:)` per tab, `.onOpenURL` | No |
| Onboarding (F1, F1b) | `SignInWithAppleButton` (AuthenticationServices), `TabView(.page)` for 3 short panes, the custom marking picker (`Grid`, `Canvas`), permission primers before the Local Network / Bluetooth / NI prompts; debug test‑user sign‑in behind `#if DEBUG` only | No |
| Radar (F2) | `NetworkBrowser` (Network framework, Bonjour, peer‑to‑peer), `NISession` for distance, `.safeAreaInset(edge: .bottom)` glass Table cards with `GlassEffectContainer`, `ContentUnavailableView` for denied permission, `.sensoryFeedback(.impact)` on arrival | No |
| Lobby (F3) | Custom seat ring (`Layout` protocol, radial), `matchedGeometryEffect`, `Picker(.segmented)`, `Stepper`, `.confirmationDialog`, `ShareLink` + QR (Core Image `CIFilter.qrCodeGenerator()` → `Image(decorative:)`) | No |
| Live game (F4, F5) | `List`/`LazyVStack` standings, `.contentTransition(.numericText())`, `.animation(.snappy)`, segmented `Picker`, `.toolbar` with glass buttons, `Menu`, `.sheet` with `.presentationDetents([.medium, .large])`, `.presentationBackgroundInteraction(.enabled(upThrough: .medium))` for the rules sheet, `ViewThatFits` for Dynamic Type, landscape via `.onGeometryChange` | **Yes, one property:** keeping the screen awake requires `UIApplication.shared.isIdleTimerDisabled` (no SwiftUI equivalent exists). Set in a tiny `IdleTimerController` toggled by `scenePhase` and view visibility, with a comment as required by `apps/ios/AGENTS.md`. |
| Round entry (F6, F7) | Custom keypad (`Grid` of `Button`s, `.buttonStyle(.glass)`), `@FocusState`‑like current‑row model, Cards helper chips, `.sensoryFeedback(.selection)`, accessibility alternative `TextField` with `.keyboardType(.numbersAndPunctuation)` | No |
| Round history / detail / edit (F8) | `List` sections, `DisclosureGroup`, edit reuses the entry sheet, diff preview view, `.alert(item:)` for conflicts | No |
| Log (F9) | `List` with section headers by time, `TimelineView` for relative times | No |
| Finish (F10) | `.fullScreenCover`, `TimelineView` + `Canvas` particles (gated by `accessibilityReduceMotion`), Core Haptics `CHHapticPattern` (three‑beat canter), `ImageRenderer` share card + `ShareLink` | No |
| Guest hand‑off (F11) | `.sheet`, QR via Core Image, `ShareLink` (AirDrop and Messages appear in the share sheet), `Transferable` claim payload | No |
| Profile (F12), Head‑to‑head (F13) | `ScrollView` + `Grid`, Swift Charts `LineMark`/`PointMark`, `accessibilityChartDescriptor`, `NavigationLink(value:)` | No |
| Leaderboard (F14) | `List` with `.safeAreaInset` pinned "You" row, `ScrollViewReader`, lens chips (`ScrollView(.horizontal)`), `.searchable` | No |
| Achievements (F15) | `LazyVGrid`, `Gauge` (circular) for progress rings, `.sheet(item:)` detail, `.navigationTransition(.zoom)` | No |
| Learn (F16) | `NavigationStack` lessons, `Slider` knock simulator, `PhaseAnimator`/`KeyframeAnimator` demos, TipKit `Tip` + `.popoverTip`, rulebook with `.searchable` | No |
| Live Activity + Dynamic Island (F17–F19) | ActivityKit `Activity`, `ActivityConfiguration` + `DynamicIsland { expanded/compact/minimal }`, `LiveActivityIntent` buttons (App Intents), push‑to‑start and channel broadcast push, `staleDate`, `AlertConfiguration` (silent), StandBy via `.supplementalActivityFamilies` | No |
| Widgets (F18) | WidgetKit `StaticConfiguration` / `AppIntentConfiguration` (pick a rival), `.containerBackground`, accessory families, `ControlWidget` + `ControlWidgetButton` with an `OpenIntent` ("Start a table") | No |
| Notifications | UserNotifications, `UNNotificationCategory` actions (**Sit down**), interruption levels, provisional authorization off (we ask in context) | No |
| Proximity and sync | Network framework (P2P), Nearby Interaction, Core Bluetooth (background beacon + state link; `bluetooth-central`/`bluetooth-peripheral` background modes, state restoration), SwiftData event log, HLC ordering in a pure‑Swift `GameEngine` (unit‑tested with Swift Testing) | No |
| App Clip | Separate target sharing the SwiftUI live‑view and hand sheet, `SignInWithAppleButton`, `SKOverlay.AppClipConfiguration` via the SwiftUI `.appStoreOverlay` modifier | No |

**Info.plist keys required:** `NSLocalNetworkUsageDescription`, `NSBonjourServices` (`_kedro-table._tcp`), `NSBluetoothAlwaysUsageDescription`, `NSNearbyInteractionUsageDescription`, `NSSupportsLiveActivities`, `UIBackgroundModes` (`bluetooth-central`, `bluetooth-peripheral`, `remote-notification`).

**Risks I'm flagging honestly:**
- *Background BLE* on iOS is throttled. The "table is right here" notification and offline Live Activity updates are best‑effort, and the design never depends on them. Foreground discovery plus the QR fallback always work.
- *Nearby Interaction* needs UWB (iPhone 11 or later, not SE models). Without it, the design degrades to "Nearby", sorted by played‑with overlap.
- *App Clip* framework limits mean it's online‑only. Offline guests are scored by the table.

---

## 15. Tap and time estimates

Assumptions: phones already unlocked unless noted, hand values evenly mixed between one and two digits (an average of 1.6 digit taps), and occasional negatives.

### 15.1 Recording one round, 5‑player table

**Scorekeeper mode**

| Step | Taps | Time |
|---|---|---|
| Mark the knocker on the "Who knocked?" strip *(at the knock, during play)* | 1 | 1 s |
| Open **Enter hands** after reveal | 1 | 1 s |
| 5 players × (1.6 digits + Next) | 13 | 12–15 s |
| (the last Next is **Record round**) | (included) | — |
| **Total** | **≈ 15 taps** | **≈ 15–18 s**, of which only about 14 s happens after the reveal |

**Self‑report mode** (per phone, in parallel)

| Step | Taps | Time |
|---|---|---|
| Knocker taps **I knocked** (in‑app or Live Activity) | 1 (one person) | 1 s |
| Tap **Report your hand** (dock or Live Activity) | 1 | 1 s |
| Digits (± if negative) | 1.6 | 1–2 s |
| **Report** | 1 | 0.5 s |
| **Per player ≈ 3.6 taps · table wait ≈ 4–8 s** (the slowest player), plus about 2 taps for anyone reporting for one guest |

### 15.2 Getting 5 returning players into a game

| Who | Taps | Notes |
|---|---|---|
| Host | **2** (Start a table, Deal) | Rounds and mode carry over from last time. Optionally 1–2 more to change them. |
| Each of 4 players | **1** (Sit down on the Table card or notification action) | No typing, no codes, no approval (played‑with). |
| **Total** | **6 taps across 5 phones · ≈ 10–15 s wall time** | Via Control Center "Start a table", the host doesn't even hunt for the app. **Rematch:** 1 + 4 + Deal = **6 taps, ≈ 5 s.** |

### 15.3 A first‑time guest joining

| Path | Taps | Time |
|---|---|---|
| **Host adds guest by name** (no device) | **+ Guest** (1) + name (≈ 4 letters) + **Add** (1) ≈ **6 taps, host only** | ≈ 6–8 s |
| **Guest follows on their own phone** (App Clip, no install) | Host: **Show join code** (1). Guest: point Camera + tap the App Clip banner (1) + **Open** (1) + **That's me** (1) | ≈ 15 s, with no account and no download |
| **Guest claims after the game** | Host: **Give them their history** (1) + AirDrop (2). Guest: open the link (1) + Sign in with Apple (≈ 2) + **Claim** (1) | ≈ 30–40 s |
