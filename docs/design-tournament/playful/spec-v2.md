# Kedro for iOS · "Horse Play" v2: The Members' Enclosure

*Design tournament entry · playful track · round 2 · October 2026 · companion file: `mockups-v2.html` (22 phone frames, a Dynamic Island strip, and the visual-system sheet). The v1 files (`spec.md`, `mockups.html`) are unchanged.*

---

## Changes from v1

Round 1 lost on two things: it looked like a children's game, and it had some interaction bugs. v2 rebuilds the visual identity and the copy from scratch (PRD §8) and fixes every mustFix the judges listed. The philosophy stays the same: **brand-forward delight**. The horse spirit, the celebrations, the game feel, and a teaching path that makes people fall for Cambio are all still here, but they now come from a racecourse members' enclosure and a sharp-tongued friend group, not a petting zoo.

### Direction change (product owner, PRD §8)

| v1 | v2 |
|---|---|
| Cartoon horse avatars you build (coat, mane, blaze) | **Racing silks**: a jockey-silks crest per player (pattern × two colours × serif initial). Real silks were invented so a crowd can tell eight runners apart at a glance, which is exactly the job an avatar does at an 8-player table. |
| "Dash" the cheerful foal mascot in Learn, onboarding and empty states | **No mascot.** The brand is a monoline horse-head mark and editorial typography. Empty states are typographic: a serif line and a dry joke. |
| Parchment, chestnut orange, rosette gold, rounded numerals | **Bone, racing green, brass, oxblood**, ink-black dark mode. Apple's New York serif for display, SF Pro for text and numbers. |
| Rosettes, confetti, bucking wiggle, trotting horses | **Honours** (achievements styled like enamel racing badges), a **photo-finish** reveal at game end, and a horseshoe that rotates into place. No particles and no mocking animations. |
| Warm and cheeky copy, puns | **Contemporary and irreverent, with real swearing where it lands**, plus a **Clean** mode that keeps the attitude (see Voice & copy). The app is rated for mature audiences (§12.4). |
| Heavy brand vocabulary (Paddock, Track, Rosettes, Silks, Winner's Circle, Dash, Coach) | **Three brand words only**: *Silks* (your crest), *the Paddock* (under 5 games, no rank yet) and *Honours* (achievements). Each one is always shown with its plain meaning. Everything else uses plain words: Play, Board, Learn, You, History, Rematch. |

### Every judge mustFix, and how v2 resolves it

| # | mustFix (source) | Resolution in v2 | Where |
|---|---|---|---|
| 1 | Remove timed waits from auto-advance. Advance only on two digits or unambiguous input, otherwise require Next. Support 3-digit values with a normal field. (native, table, product) | **One rule with no timing: a second digit always advances; a single digit waits for Next.** The keypad has a large, permanent **Next** key. Nothing depends on how fast you type. Tapping a row's value turns it into a plain numeric `TextField` (no auto-advance) for the rare 3-digit hand. The rule is printed under the keypad: "Two digits jump ahead. One digit? Hit Next." | §4.3, frame 08 |
| 2 | Stop auto-presenting the Join sheet. (native) | **Nothing opens on its own.** A nearby table shows as a glass card at the top of Play with a **Sit down** button. Each player taps it. | §4.1, frame 03 |
| 3 | Stop auto-moving phones into the rematch lobby. Require an explicit "I'm in" per phone, keep the host's Start. (native, table, product) | **Rematch is an invitation.** "Run it back" sends a card to every phone in the game. Each person taps **I'm in** or **Not this time**. Nobody is seated by default. The host's **Start** stays enabled at 3 or more players and shows who hasn't answered. Guests are seated by whoever taps for them. | §4.9, frame 14 |
| 4 | Fix the implementation map: no `.symbolEffect` on a custom Shape; plain `TextField` with `.textInputAutocapitalization(.characters)` for claim codes. (native) | Custom marks (horse head, silks) animate with **`keyframeAnimator` / `PhaseAnimator`**. `.symbolEffect` is used only on SF Symbols and on custom SF Symbols exported from the symbol template (the horseshoe and knock glyphs, §9.4). The claim field is `TextField` + `.textInputAutocapitalization(.characters)` + `.autocorrectionDisabled()` + `.keyboardType(.asciiCapable)`. It has **no** `.oneTimeCode` content type. | §13 |
| 5 | Give Cards mode a visible remove control and accessibility actions. (native, table) | Picked cards form a **chip row**. Each chip has a visible **×** (tap to remove), the keypad's **⌫** removes the last card, and each chip has `accessibilityAction(named: "Remove")`. There are no hold gestures anywhere in the app. | §4.4, frame 09 |
| 6 | Show the live Table with 8 players and define the race strip's overlap rules, or collapse it during rounds. Cap motion during entry. (native, table, product) | The race strip is replaced by the **Gap rail**: one hairline with silks ticks placed by total. Rule: ticks closer than 14 pt **stack vertically** (up to 3), and beyond 3 they merge into a count bubble. The rail is **hidden whenever a Record or Report sheet is open**. At 7–8 players it collapses to a single line under the standings header. Frame 07 shows an 8-player Table. | §4.5, frames 05–07 |
| 7 | Expand the Lock Screen Live Activity to show standings: top 4 plus you, with deltas. (native) | The Lock Screen activity lists **top 4 + you** (your row is pinned as a 5th row if you're outside the top 4), with last-round deltas as signed numbers and the knocker marked. The expanded Island shows the top 3 + you. | §7.1, frame 21 |
| 8 | Add the `#if DEBUG` test-user sign-in to onboarding (PRD §3.1). (native) | The Welcome screen shows a **Debug: sign in as test user** button under Sign in with Apple. It is compiled only inside `#if DEBUG`, with a `DEBUG BUILD` label on the screen. It is not in release builds, and a CI check fails if the symbol `TestUserSignIn` is in a Release binary. | §4.1 C, frame 01 |
| 9 | Generate highlights only from recorded data. Drop "two Red Kings". Break ties between −10 rounds deterministically. (table) | Highlights come from a fixed list of **computable facts** (§4.9) and never mention cards unless the round was entered in Cards mode. A negative hand says only what the data proves: "a Red King was in there". Ties use a fixed order: biggest impact on the final standings, then earliest round, then seat order. Equal knock records are shown as a count ("Priya: 2 knocks, 2 clean"). | §4.9, frame 13 |
| 10 | Hard-block hand values below −2, with the reason. (table, product) | **Blocked.** Typing −3 shakes the field (a static outline under Reduce Motion) and shows: "Two Red Kings per deck, so −2 is the floor. Recount." In Cards mode, the Red King chip disables after two. Values over 50 get only a soft check, because wrong-stick penalty cards can push a hand that high. | §4.3, frame 09 |
| 11 | Lightweight "Everyone will see this" confirmation on edits, or a persistent Undo for the author. (table) | **Both.** Save shows a confirmation ("Everyone sees this fix, with your name on it"), and the author's Changes entry keeps an **Undo** button until the game finishes. An undo is logged as its own change. | §4.7, frames 10–11 |
| 12 | Count the Record-round tap in the tap estimate. (table, product) | Recounted. A 5-player scorekeeper round is **12 taps**, including opening the sheet and the Next taps that rule 1 adds. See §11. | §11 |
| 13 | Remove the bucking wiggle on beaten knocks; use a neutral glyph change. (product) | Removed. A beaten knock rotates the horseshoe to inverted with one spring, plus a light haptic. No animation is aimed at a player. | §9.5 |
| 14 | Hold a conflicting offline Round N as an unapplied alternate with "Use this version". (product) | A duplicate Round N recorded offline is kept in Changes as **Not applied**, with both versions side by side and **Use this version**. Nothing changes until a person chooses, and the choice is logged. | §4.11, frame 10 |
| 15 | Remove the "projected starting rating band", or drop "never shown". Pick one rule. (product) | **One rule:** the rating is computed from game 1 and **never shown until game 5**. It is then revealed to the whole table as a public moment, *the Debut* (stolen from Rivalry). The Paddock header shows only the 5-nail meter. | §5.3, frame 18 |
| 16 | Drop "Knocking at 4 or less wins most of the time", or compute it from Kedro data and label it. (product) | The simulator teaches only the rule. Its stats line is **your own computed record** ("Your knocks on 4 or under: 9 of 11 clean"). It is labelled *From your games* and appears only once you have 5 or more such knocks. | §6.1, frame 20 |

### Ideas adopted from other entries (credited)

- **Finish Game gate** with "Fix a round first" and a 15-minute idle auto-finish, sealed at a deterministic HLC time so offline phones agree (table-first, ambient). This replaces my 3-minute countdown.
- **Knocker-first entry order** in scorekeeper mode, so the outcome line can resolve early (ambient).
- **Deltas in signs and words, never red/green** (table-first). Lower is better, so colour only reinforces.
- **One scrolling History page**: grid, then the full Changes log (table-first). v1 already did this; v2 keeps it and adds "Not applied".
- **Rating revealed at game 5 as a table moment** (rivalry) → *the Debut*.
- **Stakes strip** on the Sit-down card and in the lobby, and a **Since you last looked** card on Play (rivalry).
- **Gap-to-level** lines on head-to-head (rivalry). In this voice they become trash talk.
- **5-nail horseshoe meter** for the first five games (ambient), shared by every surface.
- **Watch mode** for late arrivals, with an accepted-in-advance rematch seat (table-first).
- **Live Activity alert update as the only self-report nudge** (table-first).
- **VoiceOver announcements only when VoiceOver is running**, plus rotors for Edited rounds and Knocks (table-first).
- **ControlWidget "Start a table"** on Control Center and the Action button (ambient, rivalry).

---

## 0. The five bets (v2)

1. **One tap to sit down.** The phones at a table find each other with no internet. A returning player taps **Sit down** on a card they chose to look at. Nothing pops up uninvited.
2. **The app keeps score; the table talks shit.** The keypad has one deterministic rule. The outcome line explains the knock as you type. Swearing goes in the headline and never in the math.
3. **Silks, not cartoons.** Each player wears a racing-silks crest that stays distinct at 8 players. The brand is a members' enclosure: bone paper, racing green, brass, and New York serif.
4. **Ceremony at the end, quiet during play.** Rounds get one sentence and one glyph. Game end gets a photo-finish reveal, highlights that roast people with real data, and a rematch everyone opts into.
5. **Teach like a mate who's two drinks in.** A five-lesson course, a knock simulator, and coach tips that explain the rule plainly and then make fun of you a little.

---

## 1. Design thesis

**Kedro should feel like the members' enclosure on race day: well dressed, a bit loud, and fluent in the sport.** The look is premium and editorial. A racing programme meets a contemporary sports app: bone paper, ink, a single racing-green accent, brass for whoever is winning, oxblood for whoever just blew it. The voice is the friend at the table who keeps the score honest and never lets you forget a beaten knock. The horse spirit appears as heritage (silks, the furlong posts, the horseshoe, the photo finish, the Paddock), never as a mascot.

During a round the app is calm and literal: big tabular numbers, one sentence per knock, and a keypad you can predict. Between rounds and after the game it shows its personality: the headline line, the photo finish, the highlights, the rivalry receipts. Liquid Glass carries the controls, so the numbers sit on solid paper.

| PRD goal | How v2 serves it |
|---|---|
| **Fast table flow** | Knocker-first keypad with one deterministic advance rule: 12 taps for a 5-player round. Self-report runs in parallel. The Gap rail is hidden during entry. The screen stays awake. |
| **Everyone joins** | Local-network discovery with Nearby Interaction distance ("At your table" vs "Other tables nearby"). A **Sit down** card that you tap. People you've played with are admitted automatically. Guests take 2 host taps, and returning guests are matched by name. |
| **People come back** | The 5-nail Paddock meter, the Debut, rating movement, rivalry receipts with gap-to-level lines, Honours with Next up, Since you last looked, and widgets. |
| **Spreads to new tables** | Guest-first welcome when a table is near, a typed-name-only guest flow, coach tips that switch on automatically for anyone under 3 games, claim links over AirDrop, back-dated Honours, and the **Trainer** honour for bringing new people in. |

---

## 2. Vocabulary

Three brand words. Each is shown with its plain meaning the first time it appears on any surface, and VoiceOver reads the plain meaning.

| Brand word | Shown with | Use |
|---|---|---|
| **Silks** | "your crest" | The player identity crest (§9.2) |
| **The Paddock** | "under 5 games · no rank yet" | Players who aren't eligible for the board yet |
| **Honours** | "achievements" | The achievement catalog (§8c) |

Plain words everywhere else: **Play**, **Board** (leaderboard), **Learn**, **You** (profile), **History**, **Changes**, **Rematch**, **Finish game**. Game words are never renamed (PRD §8): knock, knocker, round, hand, hand value, stick, peek, switch.

**Knock outcomes** use a plain label, a horseshoe glyph and a signed number. Colour only reinforces them.

| Outcome | Label | Glyph | Colour token |
|---|---|---|---|
| Knocker strictly lowest | **Clean knock · −10** | horseshoe upright (luck holds) | `clean` (racing green) |
| Knocker tied for lowest | **Tied knock · hand** | horseshoe on its side | `tie` (graphite) |
| Someone lower than knocker | **Beaten knock · hand + 10** | horseshoe inverted (luck ran out) | `beaten` (oxblood) |

---

## 3. Information architecture and navigation

```
RootView
├─ Onboarding (first launch / signed out / guest-on-device)
└─ MainTabView  (TabView + Tab API, iOS 26 floating Liquid Glass tab bar)
   ├─ Tab "Play"    nearby tables (Sit down cards), Start a table, Since you last looked, stakes, recent games
   ├─ Tab "Board"   Global | Played with, lenses, the Paddock
   ├─ Tab "Learn"   five lessons, knock simulator, full rules, card values
   ├─ Tab "You"     silks, stats, Honours, rivals, history, settings (Voice, Claim a history)
   └─ Tab(role: .search) players by name; recent opponents first
   + tabViewBottomAccessory: active game ("Noah's table · R5/8 · You 5th")
   + .tabBarMinimizeBehavior(.onScrollDown)
```

- **The Table** (live game) is a `fullScreenCover`. It hides the tab bar, keeps the screen awake, and shows one primary action. Swiping down minimizes it into the bottom accessory (`navigationTransition(.zoom)` back).
- Inside the Table: pushes for **History** (grid + Changes) and **Player in this game**. Sheets for **Record round**, **Report your hand**, **Fix a round**, **Rules** (`.medium`/`.large`), **Invite** (`.medium`). A toolbar `Menu` for **Add rounds**, **End game now**, **Abandon game**, **Take over scorekeeping**, **Keep it clean tonight**.
- Each tab owns a `NavigationStack` with `navigationDestination(for:)` routes: `PlayerID`, `GameID`, `HeadToHead`, `HonourID`, `LessonID`.

**Deep links and entry points** (unchanged from v1 except where noted)

| Entry | Lands on |
|---|---|
| `kedro.app/t/<table>` (table QR / invite) | Sit-down sheet for that table |
| `kedro.app/c/<claim>` | Claim flow (§4.10) |
| Live Activity / Island tap | The Table |
| Live Activity button (App Intent) | Table with Record or Report open |
| ControlWidget / Action button "Start a table" | Lobby, hosting |
| "Noah added you" notification **Join** action | Seats you, opens the lobby |

---

## 4. Key flows

Sample cast: **Noah** (you; navy and bone hoops), **Mia** (oxblood and bone quartered), **Leo** (black, brass sash), **Priya** (racing green and brass halved), **Sam** (guest; plain stone, dashed ring). The main game is "Noah's table", set for 6 rounds and extended to 8 by Priya, with Noah keeping score. The canonical ledger is in §4.12 and at the top of the mockups.

### 4.1 Joining a co-located table

**Discovery.** The host's phone advertises `_kedro._tcp` over Wi-Fi and peer-to-peer Wi-Fi (Network framework `NWListener` with `includePeerToPeer`; iOS 26's `NetworkListener`/`NetworkBrowser` where available, with MultipeerConnectivity as the fallback transport). Browsing phones swap Nearby Interaction tokens. On UWB phones the card says **At your table** (≤ 2 m) or groups others under **Other tables nearby**. Non-UWB phones sort by signal and show the table's two-word code so people can say it out loud ("Brass Filly?" "That's us").

**The Sit down card (no auto-presentation).** A glass card at the top of Play: "Noah's table · At your table · Mia, Leo, Priya sitting" with a **stakes strip** ("Your 5th game. Finish it and you debut on the board.") and a **Sit down** button. Tapping it seats returning players at once (admitted automatically because they've played with the host). Strangers are shown to the host as "Ava wants in · Let her in".

**Fallbacks.** The lobby shows the two-word table code (*Brass Filly*), a QR universal link for the system Camera (no in-app scanner), and a rotating token in the QR so old screenshots stop working (ambient).

**A. Returning table.** Host: **Start a table** (1) → lobby advertising → **Start game** (1). Each joiner: **Sit down** (1). Host-added players who aren't in the app get the "Noah added you" notification with a **Join** action.

**B. Guest with no app.** **Add guest** → first name → **Done**. If the name matches a guest who has played with anyone at the table, Kedro offers "Sam · guest · 3 games with this lot" so one identity keeps building. Guests get silks that don't clash with anyone else's (§9.2) and a dashed ring.

**C. First launch, table detected.** The Local Network primer comes first ("Kedro uses Local Network to find the table. That's it. We're not reading your damn texts."). Then the Welcome screen leads with the table: "Noah's table is right here." → **Sit down as a guest**. **Sign in with Apple** is one button down. In **DEBUG builds only**, a third button, **Debug: sign in as test user**, sits under a `DEBUG BUILD` label (`#if DEBUG`, PRD §3.1). Making your silks needs only a first name. The pattern and colours are pre-filled and can be shuffled. The device keeps the guest identity so a later Apple sign-in claims it without a code.

**D. Mid-game arrivals.**

| Situation | Behaviour |
|---|---|
| A seated player's phone rejoins | "Round 5 of 8 · your seat's still warm." It pulls the event log from any peer. |
| A guest seat is claimed by a phone ("I'm Sam") | Sam taps **That's me**, the host approves (1 tap), and the device takes the identity. |
| A new player after Round 1 is recorded | Not allowed (no canonical late-entry rule). The sheet says: "They're on Round 3. Watch this one, play the next." → **Watch** (read-only Table) + **Save me a seat**. A saved seat is an *already-accepted* rematch invite. |
| Before Round 1 | Admitted at 0, logged. |
| Table full (8/8) | "Eight's the max. Watch, or grab the next one." + Watch + Save me a seat. |

### 4.2 The lobby

One scroll that **advertises while you set up**.

| Section | Contents | Default |
|---|---|---|
| Table | Name, two-word code, QR | "Noah's table" |
| At the table | Seat-ordered silks (drag to match real seats), status per seat | Join order |
| Add players | Played-with row (people nearby pre-checked), Search, **Add guest** | — |
| Planned rounds | 4 · 6 · 8 · 10 + stepper | Last used, else 6 |
| Scoring | **Scorekeeper** / **Everyone reports** | Everyone reports if every seat has its own phone |
| New player at the table | Coach tips for this game, on every phone | On if anyone has fewer than 3 games |
| **Keep it clean tonight** | Forces Clean voice on every phone for this game (§12.2) | Off |
| Stakes strip | "Sam's on 4 games. One more and he's on the board." · "Leo leads you 8–6." | — |

**Start game** stays disabled with a reason ("Need at least 3. Cambio's not a date." / Clean: same line) until the table is valid.

### 4.3 Recording a round: scorekeeper

The **Record round** sheet (`.large`, keypad pinned):

1. **Who knocked?** The silks row in seat order. Tap one (1). **The knocker's row moves to the top** of the entry list (knocker-first). The other rows follow in seat order.
2. **Hand values: one rule, no timing.**
   - **A second digit always advances** to the next player. **A single digit waits for Next.** The keypad has 0–9, **±** (works before or after the digits), **⌫**, and a tall **Next** key. On the last row, Next is replaced by **Record**.
   - Tapping a row moves focus there. Tapping a filled value opens it as a normal `TextField(value:format:)` with the system number pad, with no auto-advance. This is how you enter the rare 3-digit hand.
   - **Hard limit:** below −2 is blocked with the reason ("Two Red Kings per deck, so −2 is the floor. Recount."). **Soft check** above 50: "That's more than four cards' worth. Sure?"
3. **Conditional outcome line** (kept from v1, the judges' favourite). It updates on every keystroke: "Leo's on 4. Nobody under it so far. Noah: over 4 → Leo −10 · 4 → tie · under 4 → Leo 14." When the round is complete it settles into the final sentence with the glyph.
4. **Record round 6** (sheet toolbar, glass prominent). Disabled with a reason until the knocker and every hand are in ("Noah's hand missing"). On save: totals tick over (`.numericText`), rows reorder with one spring, the horseshoe rotates into its outcome, and a success or light haptic plays. Then **Undo** stays up for 5 s (logged if used).

Non-scorekeepers see "Noah's keeping score" where the button would be, and can still fix any round. **Take over scorekeeping** is in the menu and logged.

### 4.4 Recording a round: self-report

- After a round is recorded, every phone shows the **Report your hand** card for the next one. You don't have to open anything.
- My phone: keypad or **Cards** for my hand, an **I knocked** toggle, then **Send my hand** (2–3 taps).
- **Cards mode:** a grid of card chips (A–10, J, Q, K♠/♣ 13, K♥/♦ −1, Joker 0). Picked cards build a **chip row with a visible × on each chip**, **⌫** pops the last one, and the running total shows. After two Red Kings, the K♥/♦ chip disables: "Only two Red Kings in a deck. Nice try." VoiceOver: each chip has "Remove" as a custom action, and the total is announced.
- **The gate:** a strip of silks with ✓ as hands arrive. **Values stay hidden until everyone is in**, then all are revealed together.
- **Guests:** "Report for Sam" appears on every phone. The first person to tap it takes the row, and the log records "Reported by Noah". (An assigned reporter can be set in the lobby, which I took from Rivalry.)
- **Knocker rules:** if nobody claimed the knock, every phone asks "Who knocked? Somebody did." If two people claimed it: "Mia and Leo both say they knocked. Somebody's full of shit." / Clean: "Somebody's fibbing." Anyone resolves it, and both claims are logged.
- **Stragglers:** a Live Activity **alert update** after 20 s off-screen ("Round 6: 4 of 5 in. Yours is the holdup, chief."). It is a notification only if no activity exists.

### 4.5 Live standings ("the Table")

Top to bottom:

1. **Glass toolbar:** minimize · "Noah's table / Round 5 of 8" · Rules · Menu.
2. **Change banner** (only when someone else edits): "Mia fixed Round 3. You went from 1st to 5th. Brutal. · View". It stays 6 s and is also posted as a VoiceOver announcement (only when VoiceOver is running).
3. **Furlong posts:** one slim post per planned round. Played posts are filled ink, the current post is brass, and the label reads "R5 of 8 · 3 to go".
4. **Last-round card:** eyebrow "ROUND 5 · CLEAN KNOCK" + horseshoe glyph. **Headline** (voice) in New York: "Sam knocked on 2 and nobody could touch it. Smug bastard." **Rule line** (always plain, both voices): "Lowest hand at the table, so Sam scores −10 instead of 2." **Why?** opens the knock calculator pre-filled with this round.
5. **Standings:** rank, silks, name (+ You / Guest), movement in words and arrows ("▲2"), last-round delta (signed, with the horseshoe on the knocker's row), total in large tabular numerals. Ties show "=". The leader gets a brass rule on the left and "leads by 7".
6. **Gap rail** (in the standings header): one hairline from leader to last, with a silks tick at each total. **Overlap rules:** ticks closer than 14 pt stack vertically (max 3). A 4th or later tick in the same cluster becomes a count bubble ("+2"), and tapping the cluster lists those players. At 7–8 players the rail collapses to one line and stacking is limited to 2. The rail is **hidden while a Record/Report sheet is open** and at accessibility text sizes (the standings already carry the information). Rail changes animate only between rounds.
7. **Primary action** (glass prominent): **Record round 6** / **Report your hand** / "Noah's keeping score". Secondary: **History**.
8. **Sync chip** only when something is unusual (§4.11).

### 4.6 History and Changes

One scrolling page:

- **The grid:** players as rows, rounds as columns, totals pinned. The knocker's cell carries the outcome glyph. Edited cells have a small dot. Not-applied alternates have a hollow dot. Tapping a column opens Round detail with the rule sentence and **Fix this round**.
- **Changes** ("Every fix, in public. Nobody quietly edits their own hand."): reverse-chronological entries for round fixes (before → after, plus the effect: "Noah −10 → 14 · total 18 → 42 · 1st → 5th"), rounds added, ended early, abandoned/restored, scorekeeper handover, reported-for, sync events, and **Not applied** duplicates with **Use this version**. The author's own entries keep **Undo** until the game finishes.

### 4.7 Fixing a round

- Anyone in the game: tap a round → **Fix this round**. This is the Record sheet filled in, with the old value struck through next to each changed one, plus a **Before → After** panel (round score, total and rank for every affected player).
- Changing the knocker or a hand value re-runs §2.6 at once, and the outcome line explains the new result.
- **Save fix** → confirmation: "Everyone sees this fix, with your name on it." → **Save fix** / **Cancel**. Then the Undo in the author's Changes entry stays until the game finishes.
- Finished games are read-only: "Final · Oct 24, 10:14 PM. History doesn't take requests."

### 4.8 Add rounds, end early, abandon

| Action | Flow | Result |
|---|---|---|
| **Add rounds** | Menu → +1 / +2 / custom | Furlong posts extend. Logged "Priya added 2 rounds · 6 → 8". |
| **End game now** | Menu → current standings as the final result, "Counts fully in stats" → **End game** | Goes to the Finish gate. A part-reported round is discarded (logged). |
| **Abandon game** | Menu → "Abandon it? It stays in history marked Abandoned and counts for nothing. Anyone can restore it for 15 minutes, so don't rage-quit." → **Abandon** | Every phone shows Abandoned with **Restore game** for 15 minutes ("Priya restored the game. Nice try, Noah."). Restore beats Abandon by HLC order. |

**The Finish gate (recognising the end).** When the last planned round is recorded, the Table becomes **"Last round's in. Lock it?"** It shows the final standings and three actions: **Finish game** (any phone), **Fix a round first**, **Add rounds**. If nobody finishes, the game **seals after 15 minutes with no changes**, at a seal time derived from the HLC of the last event, so offline phones agree on when it locked. A visible line says "Locks itself at 10:14 PM".

### 4.9 Game end: the photo finish, and the rematch

**The photo finish** (full screen, every phone, at the same moment): a slit-scan strip sweeps across the final standings like a finish-line camera, freezes on the winner's silks, and the winner's name sets in New York at display size. One success haptic plays. **Co-winners** freeze together: "Dead heat. Priya and Leo share it. Nobody's happy." Both get full win credit.

**Highlights: facts first, then the roast.** Each one is computed from recorded rounds. The fixed set is below, with the top 3 shown by priority. Ties go to biggest impact on the final standings, then earliest round, then seat order.

| Highlight | Fact computed | Example (sample game) |
|---|---|---|
| Winning move | The round where the eventual winner took the lead for good | "Stole it on the last knock. Cold-blooded." (Priya, R8: from 2nd to 1st) |
| Bottled it | A player who led after the most rounds but didn't win | "Mia led for five rounds and finished third. Bottled it." |
| Perfect knocks | Most knocks with all of them clean (2 or more knocks) | "Priya: 2 knocks, 2 clean." |
| Sub-zero | Any negative hand (proves at least one Red King) | "Priya's −1 in Round 4. A Red King was in there." |
| Comeback | Largest rise from rank after the halfway round to final rank | "Priya: 3rd after Round 6, won it." |
| Beaten by | Each beaten knock, naming who beat it | "Mia knocked on 5 into Noah's 3. Absolutely fucked it." |
| Last place | The last finisher and their margin | "Noah, 62. Dead fucking last." |

Card-level highlights ("two Red Kings") appear **only** if that round was entered in Cards mode.

**Your night** (personal to each phone): rating change (or the 5-nail meter), Honours earned this game, streak, a gap-to-level line for your top rival.

**Guests:** "Send Sam their history" (AirDrop-first `ShareLink` with the claim link and code).

**Rematch ("Run it back").** Anyone can tap it. It creates a lobby with the same players, seat order, rounds and mode, with **the starting seat moved one place clockwise**. Every other phone gets an **invitation card**: "Leo wants a rematch. Same seats, Mia starts. You in?" → **I'm in** / **Not this time**. Saved seats from Watch mode are already accepted. The host sees each answer and can **Start** once 3 or more are in. Taps across a 5-phone table: Run it back 1 + I'm in ×4 + Start 1 = **6**, and nobody gets seated by accident.

### 4.10 Guest claim

- Each guest identity has one credential: `kedro.app/c/7H4Q-PXMA` (8-char Crockford base32). It's offered at game end and in that game's detail, shared with `ShareLink`, and re-issuing it voids the old one. Offline: "Link works once this game syncs."
- **Claim screen:** "Sam, your guest era is over." "3 games · 1 win · up 2–1 on Noah." "3 Honours back-dated · 2 games from the board." → **Claim my history**. It recomputes derived stats and back-dates Honours. Already claimed: "This history's already been claimed. Nice try though." Wrong code (rate-limited): "That code's not a thing. Check it and try again."
- **You → Settings → Claim a history** takes a typed code. Legacy web players claim this way too (PRD §9).
- Unclaimed guests have no profile page: "Sam · guest · in this game".

### 4.11 Offline play and resync

Append-only event log per game (GameCreated, PlayerSeated, RoundRecorded, HandReported, RoundEdited, RoundsChanged, GameEnded, GameAbandoned, GameRestored, AlternateChosen). Each event has a UUID + `(HLC, deviceID)`. Peers gossip over the discovery link. Uploads are idempotent by UUID.

**Conflicts:** two edits to the same field → the later `(HLC, deviceID)` wins, and the loser shows as *replaced* in Changes. **Two phones record Round N while apart → the earlier one is applied, and the later one is held as Not applied** with both versions side by side and **Use this version** (logged as AlternateChosen). Nothing changes until someone chooses. Ending and abandoning stand over later round events. Restore overrides Abandon.

| State | Chip | Copy (Unfiltered / Clean in §12) |
|---|---|---|
| Online, in sync | none | — |
| No internet, peers linked | **Offline · 5 phones linked** | "No internet. Doesn't matter. Game's fine." |
| This phone separated | **Only on this phone** | "This phone's wandered off. Get closer to the table to sync." |
| Reconnecting | **Syncing…** | — |
| Back online | **Synced ✓** (fades) + log entry | — |
| Finished offline | "Locked in. Uploads when the Wi-Fi stops being shit." | Ratings and board Honours show *pending*. |

### 4.12 Canonical sample game (verifies against PRD §2.6)

Round score, with the hand value in brackets where it differs. **K** marks the knocker.

| Player | R1 | R2 | R3 | R4 | R5 | R6 | R7 | R8 | Total |
|---|---|---|---|---|---|---|---|---|---|
| Priya | 7 | 5 | 13 | **K −10 (−1)** | 12 | 9 | 6 | **K −10 (2)** | **32** |
| Leo | 12 | **K 5** (tie) | 10 | 7 | 3 | **K −10 (4)** | 8 | 9 | **44** |
| Mia | **K −10 (3)** | 8 | 2 | 11 | 9 | 12 | **K 15 (5)** beaten | 4 | **51** |
| Sam | 15 | 11 | 6 | 9 | **K −10 (2)** | 6 | 10 | 7 | **54** |
| Noah | 9 | 6 | **K 14 (4)** beaten | 8 | 5 | 7 | 3 | 10 | **62** |

- Totals after R5: Mia 20 · Priya 27 · Sam 31 · Leo 37 · Noah 42 (R5 movement: Sam ▲2, Leo ▼1, Noah ▼1).
- **Round 3 fix** (Mia, after R5): Noah's hand 1 → 4. Before, Noah was strictly lowest → −10, total 18, 1st. After, Mia's 2 is lower → 4 + 10 = 14, total 42, 5th.
- Leaders by round: Mia R1–R5, Leo R6–R7, Priya R8. Priya was 3rd after R6.
- Knocks: 5 clean (R1, R4, R5, R6, R8), 1 tied (R2), 2 beaten (R3, R7).

**8-player sample (frame 07, "Leo's table", 8 planned, after R3):** R1 Ava knocks on 3 (clean −10). R2 Jules knocks on 6, beaten by Mia's 4 → 16. R3 Noah knocks on 2, tied with Theo's 2 → 2. Totals: Ava 12 · Noah 18 · Priya 20 · Leo 21 · Theo 22 · Mia 27 · Sam 29 · Jules 34.

---

## 5. Stats, head-to-head, leaderboards, Honours

All numbers are derived from finished, non-abandoned games (PRD §5).

### 5.1 Profile (You, and any public profile)

1. **Header:** large silks crest, name in New York, **Rating 1,108 · #142 global** (or the 5-nail Paddock meter), and a streak tag when the streak is 2 or more.
2. **Honours shelf:** 3 pinned + "14 of 26".
3. **Stats grid:** Games 23 · Wins 6 · Win rate 26% · Avg per game 41.3 · Avg per round 5.2 · Best 18 · Worst 71 · Current streak 0 · Longest 3 · Knock rate 18% · Knock success 55%. Every stat has an info popover with the PRD definition.
4. **Knock outcomes:** 18 clean / 4 tied / 11 beaten, with counts and glyphs on the bar.
5. **Nemesis:** "Leo. Finished ahead of you 8 times. He knows."
6. **Rivals**, **Game history** (Abandoned games marked "didn't count"), and on others' profiles a pinned "You vs them" card.

### 5.2 Head-to-head (where the trash talk lives)

"Noah vs Leo": silks facing each other over a split bar. **Leo 8 · 6 Noah** *finished ahead*. Games together 14 · wins in shared games Leo 4 · Noah 3 · knock outcomes facing each other (Noah 5 clean · 1 tied · 3 beaten; Leo 4 clean · 2 tied · 1 beaten). The **receipt line** comes from the record: "Leo's finished ahead of you 8 times out of 14. Two more and it's level. Or keep losing, it's your life." **Send the receipts** renders a share card (`ImageRenderer`) with the record and a line in your current voice. **Start a table with Leo** pre-fills the lobby.

### 5.3 Board (leaderboards)

- **Global | Played with.** Lenses: **Rating** (official rank) · Win rate · Avg round · Knock success · Longest streak.
- Rows: rank, silks, name, value, games, weekly movement.
- Your row is pinned at the bottom when you're scrolled away, with the gap to the next friend: "11 points behind Mia. Very catchable."
- **The Paddock · under 5 games, no rank yet** follows the ranked list. Silks with the 5-nail meter and **no rank number**. On Global it's collapsed to a count ("+2,341 in the Paddock") with your played-with friends listed.
- **The Debut.** The rating is computed from game 1 and shown to nobody until game 5 finishes. It is then revealed on every phone at that table: "Sam's on the board. 1,042 · #212. Look at him, a real fucking number." / Clean: "Look at him, a real number."

### 5.4 Honours

Enamel-badge grid (§9.3) by category. Earned honours are filled with the date and game, locked ones are outlined with a progress ring, and **Next up** shows the closest three. Each honour has a racing name and a roast subtitle, both with Clean versions. Full catalog: §8(c).

---

## 6. Rules and learning

### 6.1 Learn tab

**"Cambio in five minutes"**: five lessons (Card values · Peeks and switches · Sticking · The knock gamble · Your first game). Each is a stack of editorial cards with one interaction, and there is no mascot. The copy is the friend explaining it, sincere first and then one joke: "Red Kings are −1. Black Kings are 13. Same card, wildly different energy." Any line that leans on identity (even as a pun on card colours) fails review under §12.1 rule 1.

**Knock simulator:** two sliders, *your hand* and *lowest other hand*. The horseshoe rotates live between upright, side and inverted, and the result shows as −10 / hand / hand + 10. The stats line is only **from your games** ("Your knocks on 4 or under: 9 of 11 clean") and appears once you have 5 or more such knocks. It never shows a global claim.

**Rules reference:** the full PRD §2 ruleset, searchable, bundled for offline use. The text is always literal, in **both** voices, because the rules are the math.

### 6.2 In-game teaching

- **Rules sheet** (Table toolbar): `.medium` card values + knock table, drags up to the full reference.
- **Why?** on every delta, cell and last-round card opens the **knock calculator** pre-filled with that round: "Leo knocked on 4. Lowest other hand: Sam, 6. Clean knock: −10, his hand doesn't count."
- **Coach tips** (TipKit), on when anyone at the table has fewer than 3 games. They appear once each, **between rounds only**: first knock, first beaten knock ("That's the gamble. Strictly lowest, or +10. Don't be a hero on a 9."), first negative hand, final round.
- **Pupil** honour for finishing the course. **Trainer** for playing in 3 people's first games.

---

## 7. System surfaces

### 7.1 Live Activity and Dynamic Island

Started on every phone. Updated by ActivityKit push online and by local updates offline. It uses `staleDate`, and ends 10 minutes after the photo finish showing the winner.

| Presentation | Content |
|---|---|
| **Lock Screen** | "Noah's table · R5 of 8" + furlong posts. **Standings: top 4 + you** (pinned 5th row if you're outside the top 4), each with total and signed last-round delta. Knocker marked with the horseshoe. Last-round sentence (voice per §12.3). Button **Record round 6** / **Report your hand** (App Intent). |
| **Compact** | Leading: furlong ring "5/8". Trailing: "5th · 42". |
| **Minimal** | Ring with your rank. |
| **Expanded** | Top 3 + you with totals and deltas, the last-round sentence, and the button. |
| **Self-report alert** | `AlertConfiguration` update: "Round 6 · 4 of 5 in. Yours is the holdup." Sound off. |
| **Final** | Winner's silks + "Priya wins · 32". |

### 7.2 Widgets

| Widget | Sizes | Content |
|---|---|---|
| **Rank** | small, Lock Screen circular | "#142 ▲6" or the 5-nail meter "3/5" |
| **Rivalry** | medium | "Leo leads 8–6. Two to level." + **Start a table** (App Intent) |
| **Next honour** | small, Lock Screen rectangular | "Workhorse 23/25" |
| **Played-with board** | large | Five nearest neighbours, you highlighted |
| **Start a table** | `ControlWidget` | Control Center, Lock Screen, Action button |

### 7.3 Notifications (five, plus one alert update)

| # | Notification | When | Level | Unfiltered / Clean |
|---|---|---|---|---|
| 1 | Added to a table | Host adds you while the app is closed | Time-sensitive | "Noah put you at his table. Get in here." / "Noah added you to his table. Pull up a chair." |
| 2 | Your hand is needed | Self-report, 20 s, app off-screen. Live Activity alert update first, notification only as fallback. | Active, silent | "Round 6: 4 of 5 in. Yours is the holdup, chief." / "Round 6: 4 of 5 in. Yours is the holdup." |
| 3 | Game final | Finished while you were away from the screen. Bundles Honours and rating. | Passive | "Priya won. You came 5th, but two Honours, so not a total shitshow." / "…so not a total disaster." |
| 4 | The Debut | Once, at game 5 | Active | "Game 5 done. You're #212 on the board. Fuck yes." / "Game 5 done. You're #212 on the board. Let's go." |
| 5 | History claimed | A guest you played with claims | Passive | "Sam claimed his history. Your 2–1 is official now. Don't fuck it up." / "…Don't blow it." |

**Not sent:** every round/edit (you're at the table), "game near you" (battery, and strangers aren't invitations), rank drops, someone passed you, streak at risk, "we miss you", individual honours. No guilt mechanics.

---

## 8. Required recommendations

### (a) Leaderboard presentation and ranking

**One official rank from a single skill rating (Kedro Rating), plus lenses that re-sort without replacing the rank.** The rating is pairwise multiplayer Elo from finishing order (finishing ahead = win, equal final = draw), K = 32 ÷ (players − 1), start 1,000, replayed deterministically from history so corrections and claims recompute correctly. **Eligibility:** rank shown only at 5+ completed, non-abandoned games. Below that you're in **the Paddock**, visible as part of the community with the 5-nail meter and no rank. **The rating is hidden until the Debut**, so nobody's first number is a bad one. Lenses have their own floors (Knock success needs 10 or more knocks).

**Why:** win rate punishes big tables (a 12.5% baseline at 8 players vs 33% at 3). Average score depends on planned rounds. Five equal sorts make five #1s and no single number to chase. A rating accounts for table size and opponents, and gives one number to climb. Lenses still give everyone something they can be best at.

### (b) Play-more incentives

| Surface | Incentive |
|---|---|
| 5-nail meter (Play, You, Board, Rank widget, game end) | "Two more games and you're on the board. Right now you're a rumour." |
| The Debut | A public reveal at the table on game 5. The single biggest reason a new player comes back for game 5. |
| Your night (game end) | Rating move, Honours, streak, and a rival gap line. Every game, even a loss, ends with progress. |
| Rematch | 6 taps for the whole table, all opt-in. |
| Rivalry receipts | Gap-to-level on H2H, the Rivalry widget, and Send the receipts. |
| Played-with board | "11 points behind Mia. Very catchable." |
| Since you last looked (Play) | "Leo passed you on the played-with board. Petty, but true." Feed card, not a push. |
| Honours: Next up | Three closest, with rings. |
| Trainer honour + coach tips | Rewards bringing in new players. |
| Claim | Back-dated Honours + "2 games from the board". |
| Monthly form card (in-app) | "October: 9 games, 3 wins, four −10s. Mid, but improving." |

### (c) Honours catalog (26)

Derived from finished, non-abandoned games, awarded at finish (or back-dated on claim), and permanent once earned. Names are racing terms. Subtitles carry the voice, and each has a Clean version.

| # | Honour | Rule | Subtitle: Unfiltered / Clean |
|---|---|---|---|
| 1 | **Under Starter's Orders** | Complete your first game | "You played. Low bar, cleared." / same |
| 2 | **Broke Your Maiden** | First win (shared counts) | "First win. Don't make it your whole personality." / same |
| 3 | **Dead Heat** | Share a win | "Tied for first. Nobody's happy." / same |
| 4 | **Photo Finish** | Win by exactly 1 | "By one point. Disgusting. Iconic." / same |
| 5 | **Wire to Wire** | Lead after every round of a 4+ round game, and win | "Led the whole damn way." / "Led the whole way." |
| 6 | **Dark Horse** | Win after being alone in last past the halfway round | "Dead last at halftime. Won anyway. Who even are you." / same |
| 7 | **Triple Crown** | Win 3 in a row | "Three straight. Insufferable." / same |
| 8 | **Unbeaten** | Win 5 in a row | "Five straight. Someone stop this bastard." / "…Someone stop this person." |
| 9 | **Clean Knock** | First successful knock | "Knocked and it fucking worked." / "Knocked and it actually worked." |
| 10 | **Nerves of Steel** | 3 clean knocks in one game | "Three clean knocks. Ice in the veins." / same |
| 11 | **Neck and Neck** | Knock into a tie | "All that swagger for a draw." / "All that confidence for a draw." |
| 12 | **Found Out** | First beaten knock | "You fucked around." / "You messed around." |
| 13 | **Red Rum** | Record a negative hand | "Sub-zero. Sneaky shit." / "Sub-zero. Sneaky." |
| 14 | **Ghost** | Hand of exactly 0 | "Zero. Nothing. Spooky." / same |
| 15 | **Bottled It** | Lead after 5+ rounds of a game and finish outside the top 2 | "Had it. Lost it. We all saw." / same |
| 16 | **Marathon** | Complete a 12+ round game | "Twelve rounds. Go to bed." / same |
| 17 | **Workhorse I / II / III** | 25 / 50 / 100 games | "No life, great record." / same |
| 18 | **The Debut** | Reach 5 games and take a rank | "On the board. A real number." / same |
| 19 | **Podium** | Top 3 of your played-with board | "Top three of your mates. Don't let it go to your head." / same |
| 20 | **Group One** | Global top 100 | "Top 100 on Earth. At a card game. Respect." / same |
| 21 | **Full Field** | Complete an 8-player game | "Eight players and nobody stormed out." / same |
| 22 | **The Regulars I / II** | Play with 10 / 25 different people (accounts or claimed guests) | "Got around, socially." / same |
| 23 | **Old Rivals** | 10 games with the same player | "Ten games with them. It's a relationship now." / same |
| 24 | **Turned the Tables** | Finish ahead of your nemesis | "Finally beat them. Screenshot it." / same |
| 25 | **Trainer** | Play in 3 games that were someone else's first | "Corrupting new players since today." / same |
| 26 | **Studied** | Finish the Learn course | "Did the reading. Nerd." / same |

Where a subtitle has no profanity, the Clean version is identical, because Clean swaps words, not jokes. Anti-farming: The Regulars counts only accounts and claimed guests. Trainer needs a normally-finished game of 3 or more rounds.

---

## 9. Visual system

### 9.1 Principles

1. **Editorial over illustrative.** Type, rules (lines) and space do the work. Illustration is limited to the horse mark and silks.
2. **One accent.** Racing green is the only brand colour in the UI chrome. Brass marks the leader and the winner. Oxblood marks a beaten knock. Nothing else is coloured except silks.
3. **Numbers on paper.** Scores sit on solid surfaces. Glass is for controls only.
4. **Rectangles with discipline.** Corner radii are 12 (cards), 10 (chips), 22 (sheets, from the system). No pill blobs except system controls. Hairlines are 0.5 pt. A double hairline, **the running rail**, divides major sections.

### 9.2 The horse motif treatment

| Element | Treatment |
|---|---|
| **Horse-head mark** | A monoline-weight solid horse head in profile, facing left, drawn on a 64-unit grid. Used in the app icon (brass on racing green), the Welcome lockup, and as the **You** tab glyph (exported as a custom SF Symbol so it scales with Dynamic Type and takes `.symbolEffect`). Never shown smiling, never with eyes larger than 2 units, never posed. |
| **Wordmark** | KEDRO in New York semibold caps, tracked +18%, optionally with the mark at cap height. |
| **Silks (avatars)** | A circle filled with a jockey-silks pattern in two colours, with a serif initial on a small cap-button disc in the centre. **10 patterns**: plain, hoops, halved, quartered, sash, chevrons, diamonds, stars, cross-belts, braces. **10 colours**: racing green #1E4D3A, navy #1F2C4C, oxblood #6E1F2A, black #141414, bone #EDE6D6, brass #B08D57, claret #8C2F4B, sky #8FB3C9, saddle #8A5A3B, stone #A7A99F. Each crest has an 8% inner ring. **Per-table de-duplication:** no two players at a table share pattern **and** body colour. A later joiner who clashes gets the next free colourway for that game only. **Guests** get plain stone silks with a **dashed** ring and a "Guest" tag, and keep the silks when they claim. |
| **Furlong posts** | Round progress as slim vertical posts (2 × 14 pt) on a hairline, like the distance markers on a course. |
| **Horseshoe** | The knock-outcome glyph at three rotations (upright, side, inverted), drawn with 6 nail holes. The **5-nail meter** (first five games) is a horseshoe with five holes that fill one per game. |
| **Photo finish** | The game-end signature: a vertical slit-scan band (fine vertical stripes) sweeping across, freezing on the winner. |
| **Running rail** | Double 0.5 pt hairlines (3 pt apart) dividing major sections. |

### 9.3 Palette

Every text pair meets WCAG AA (measured ratios shown). Colour never carries meaning alone: outcomes always have a glyph and a word as well.

| Token | Light | Dark | Use | Contrast |
|---|---|---|---|---|
| `bg` | #F3F0E8 (bone) | #0C0D0C (stable black) | screen | — |
| `surface` | #FBFAF6 | #171A18 | cards, sheets | — |
| `ink` | #121412 | #ECE7DC | primary text | 16.3 : 1 / 15.8 : 1 |
| `ink2` | #545A55 | #A9ADA6 | secondary | 6.8 : 1 / 7.7 : 1 |
| `ink3` | #676C66 | #82877F | tertiary, captions | ≥ 4.6 : 1 / 4.8 : 1 |
| `brand` (racing green) | #173F31 | #8CC2A5 (text) · #24644B (fill) | tint, primary buttons, clean knocks | 11.2 : 1 / 8.7 : 1; bone on #24644B 5.7 : 1 |
| `brass` | #9C7A44 (graphics) · #6F5428 (text) | #C9A86A | leader, winner, Honours | text 6.8 : 1 / 7.8 : 1 |
| `oxblood` | #8A2433 | #E3818B | beaten knocks, destructive | 8.5 : 1 / 6.5 : 1 |
| `graphite` (tie) | #4E534F | #B9BDB6 | tied knocks | 7.5 : 1 / 9.2 : 1 |
| `sep` | rgba(18,20,18,.12) | rgba(236,231,220,.10) | hairlines | — |

Implemented as asset-catalog colour sets with Any/Dark/High-Contrast variants, exposed as `ShapeStyle` statics (`.kedroBrand`, `.kedroBrass`). The app `tint` is `brand`. Increase Contrast darkens brass to #5E4720 and lifts dark `ink3` to #9A9F97.

### 9.4 Typography

**Justification:** New York is Apple's system serif. It ships with iOS, supports Dynamic Type through `.fontDesign(.serif)`, and has optical sizes, so it gives the editorial feel without a bundled font or licence. In the HTML mockups it's referenced as `ui-serif, "New York"`, which is inline-safe and falls back to Georgia off Apple platforms.

| Style | Face | SwiftUI | Use |
|---|---|---|---|
| Display | New York Semibold | `.largeTitle.weight(.semibold)` + `.fontDesign(.serif)` | Winner's name, Welcome, profile name |
| Headline (voice) | New York Medium | `.title3` + `.serif` | The knock headline, empty states, coach tips |
| Title | SF Pro Semibold | `.title2` / `.headline` | Screen and section titles |
| Body | SF Pro | `.body` / `.subheadline` | Rule lines, lists, settings |
| Eyebrow | SF Pro Expanded Semibold caps, +8% tracking | `.caption.weight(.semibold).width(.expanded)` + `.textCase(.uppercase)` | "ROUND 5 · CLEAN KNOCK", section labels |
| Scores | SF Pro Semibold, tabular | `.title.monospacedDigit()` (`.width(.condensed)` at 8 players) | Totals, deltas, grid |
| Winner total | New York, scaled | `.system(size: 72, weight: .semibold, design: .serif)` with `@ScaledMetric` | Photo finish only |

Text styles everywhere, so Dynamic Type works to AX5. Serif is never used for numbers you need to compare (SF tabular is clearer), except the single winner total.

### 9.5 Iconography

SF Symbols at **regular** weight, monochrome, in `ink` or `brand`. Hierarchical rendering only for the Live Activity. Custom symbols built from the SF Symbols template (so they scale and take symbol effects): `kedro.horsehead`, `kedro.horseshoe` (+ `.side`, `.inverted` variants), `kedro.knock` (two short rap arcs beside a dot), `kedro.silks`. Tab bar: Play `suit.spade`, Board `list.number`, Learn `book.closed`, You `kedro.horsehead`, Search `magnifyingglass`. No emoji anywhere in the UI.

### 9.6 Motion

Restrained: one movement per event, `.smooth(duration: 0.35)` by default, no bounce over 0.1, and nothing moves while you're entering numbers.

| Moment | Motion | Reduce Motion |
|---|---|---|
| Totals update | `.contentTransition(.numericText(value:))` | Instant |
| Rank change | Rows reorder with `.smooth(0.4)` (after the sheet closes) | Crossfade |
| Clean / tied / beaten | Horseshoe rotates to upright / side / inverted (`.symbolEffect(.rotate)` on the custom symbol) + `.sensoryFeedback(.success)` / `.selection` / `.impact(weight: .light)` | Static glyph + haptic |
| Edit banner | Slides from the toolbar, 6 s | Fade |
| Gap rail | Ticks glide between rounds only | Jump |
| Self-report reveal | All values unmask together (`.blurReplace`) | Fade |
| **Photo finish** | A slit-scan band sweeps across (`keyframeAnimator`, 1.2 s), freezes on the winner's silks, name tracks in from +20% to 0 | Static final frame |
| **The Debut** | Rating digits roll in like a tote board (`.numericText`, staggered) | Instant |
| Table ↔ accessory | `navigationTransition(.zoom)` | System |

### 9.7 Liquid Glass

Glass only on the **controls layer**: tab bar, bottom accessory, toolbars, the primary action (`.buttonStyle(.glassProminent)` tinted `brand`), the Sit-down card (it floats over Play), and sheet chrome. Standings, grid, keypad keys, stats and the last-round card are **solid surfaces**. The edit banner and toolbar share a `GlassEffectContainer`. Reduce Transparency falls back to solid `surface` automatically.

---

## 10. Accessibility

- **Dynamic Type to AX5:** standings rows switch to two lines via `ViewThatFits`. The Gap rail hides (redundant). The keypad grows and the sheet scrolls with the keypad pinned. The stats grid goes to one column. Serif display styles scale with their text style.
- **VoiceOver:** each standings row is one element ("Mia, first, 20 points, last round plus 9, leads by 7"). Custom actions: *Why this score*, *View player*, *Fix this round*. Rotors: **Edited rounds**, **Knocks**. Announcements (`AccessibilityNotification.Announcement`) are posted **only when `UIAccessibility.isVoiceOverRunning`** (read through `@Environment(\.accessibilityVoiceOverEnabled)`). VoiceOver reads the rule line before the voice headline, so the facts come first. Profanity is read as written in Unfiltered. Clean is available for anyone who'd rather not hear it.
- **Reduce Motion:** §9.6. No sweeps, rolls or slides.
- **Colour:** outcome = glyph + word + sign. Guests = dashed ring + tag. Silks are always paired with a name and an initial.
- **Touch:** 44 × 44 pt minimum (keypad keys 80 × 52). No gesture-only actions anywhere: every swipe and every remove has a button.
- **Both appearances** designed (frames 05/06 and throughout).

---

## 11. Tap and time estimates (recounted)

| Task | Taps | Wall-clock |
|---|---|---|
| **Record a 5-player round, scorekeeper** (Leo knocks; hands 4, 9, 12, 6, 7 in knocker-first order) | **12**: open sheet 1 · knocker 1 · Leo "4" + Next 2 · Priya "9" + Next 2 · Mia "1","2" (auto) 2 · Sam "6" + Next 2 · Noah "7" 1 · Record 1 | ~10–15 s (limited by people calling values) |
| Same round with two-digit-heavy hands | 10–11 | same |
| Self-report round | 2–3 per player, in parallel | ~6–8 s to the last hand |
| 5 returning players into a game | **6**: Start a table 1 + Start game 1 + Sit down ×4 | ~15–20 s |
| Guest, no app | **2** host taps + a first name | ~8 s |
| First-time guest, just installed | **4** guest (open, allow Local Network, Sit down as a guest, Sit down) + **1** host (Let her in) | ~25–35 s |
| Rematch, whole 5-phone table | **6** (Run it back 1 + I'm in ×4 + Start 1) | ~8 s |
| Fix one hand value | **6** (tap round, Fix this round, tap value, digit, Save fix, confirm Save fix) | ~8 s |
| Claim a guest history | **4** | ~20 s |

---

## 12. Voice & copy

### 12.1 Tone principles

1. **Roast the play, never the person.** Mock knocks, hands, streaks, lateness, overconfidence. Never bodies, looks, intelligence-as-insult, identity, background, gender, sexuality, religion, disability, or money. No slurs, including reclaimed ones. "You knocked on a 9, you absolute menace": yes. Anything a stranger could read as being about who you are: no.
2. **Swear in the headline, never in the math.** Every scoring explanation, error fix, rule text and button label is literal and identical in both voices. The attitude sits in a separate headline line, so trust never depends on the joke.
3. **Punch sideways.** The winner gets ribbed as hard as the loser ("Insufferable now"). Nobody is the permanent butt.
4. **Earn the swear.** Profanity lands at peaks: beaten knocks, last place, comebacks, the Debut, sub-zero hands. Roughly one string in three swears. Routine UI (settings, lists, loading) is dry, not crude.
5. **Dry beats loud.** No exclamation marks, no emoji, no all caps (eyebrows aside), no "Oops!". Short sentences. British-adjacent understatement is welcome ("Brutal.").
6. **Current, not cringe.** Slang that has lasted: *bottled it, cooked, fumbled, receipts, no notes, mid, menace, run it back, chief*. Nothing that will look dated in six months. Reviewed every release.
7. **Clean keeps the joke.** Clean mode swaps the word, not the punchline: "fucked it" → "blew it", "smug bastard" → "smug". If a line only works with the swear, rewrite the line.
8. **The Lock Screen is public.** Push notifications default to Clean unless you opt in (§12.3).
9. **No guilt.** No "we miss you", no streak-loss shaming. The jokes are about the game you played, not the one you didn't.
10. **Teaching is sincere.** Coach tips explain the rule plainly and then add one joke. They never mock someone for not knowing.

### 12.2 The language setting

| Setting | Where | Effect |
|---|---|---|
| **Voice: Unfiltered / Clean** | You → Settings → Voice | Your phone's copy. Default **Unfiltered** for adults. |
| **Keep it clean tonight** | Lobby + Table menu (any player, logged) | Forces Clean on every phone for this game's shared copy: the Table, the photo finish, the Live Activity, share cards. For playing with parents, at work, or with a table that's had enough. |
| **Swearing on the Lock Screen** | Settings → Voice | Push notifications and widgets. Default **off** (Clean) because lock screens get seen. The Live Activity follows your Voice setting, since it only exists while you're at the table. |
| **Age-aware default** | Automatic | If the iOS 26 Declared Age Range API reports the account is under 18, Kedro sets Clean and hides the Unfiltered option. |

**Implementation:** two String Catalogs, `Unfiltered.xcstrings` and `Clean.xcstrings`, with **identical keys**. A `Voice` environment value picks the table: `Text(LocalizedStringResource(key, table: voice.table))`. A build-time test fails if a key exists in one catalog and not the other, or if any key in the `rule.*`, `button.*` or `error.fix.*` namespaces differs between them (principle 2). Highlights and receipts are templates with typed slots, so names and numbers are never parsed from free text.

### 12.3 Age rating and store

- **App Store age rating:** answer the questionnaire with *Profanity or Crude Humor: Frequent* and *Alcohol references: Infrequent*. That was 17+ under the old scale. Under the age-rating tiers Apple introduced in 2025 we expect the **16+ or 18+** tier, and we accept whichever the questionnaire assigns. Clean mode doesn't change the rating, because the rating covers the binary.
- **No simulated gambling.** "The knock gamble" is a rules term, with no wagering or currency.
- **Store metadata stays clean** (App Review Guideline 2.3.8): name, subtitle, keywords and screenshots use Clean copy. Subtitle: "Cambio, scored. No arguments." Screenshots show Clean voice with the attitude intact.
- **First launch** shows one line before the Welcome: "Heads up: Kedro swears. You can switch to Clean anytime in Settings." with **Keep it** / **Make it clean**.

### 12.4 Copy deck

The voice line is the headline only. Rule lines (labelled *rule*) are identical in both voices and are listed once.

| # | Key | Where | Unfiltered | Clean |
|---|---|---|---|---|
| 1 | `welcome.title` | Welcome | Score Cambio. Settle shit. | Score Cambio. Settle scores. |
| 2 | `welcome.nearby` | Welcome, table detected | Noah's table is right here. Sit your ass down. | Noah's table is right here. Pull up a chair. |
| 3 | `welcome.learn` | Welcome | Never played? Five minutes and you'll be dangerous. Nobody has to know. | Never played? Five minutes and you'll be dangerous. We won't tell. |
| 4 | `welcome.voiceNotice` | First launch | Heads up: Kedro swears. Switch to Clean anytime. | Heads up: Kedro can swear. You're on Clean. Switch anytime. |
| 5 | `primer.localNetwork` | Permission primer | Kedro uses Local Network to find the table. That's it. We're not reading your damn texts. | Kedro uses Local Network to find the table. That's it. We're not reading your texts. |
| 6 | `silks.prompt` | Make your silks | Pick your silks. Look like you know what the hell you're doing. | Pick your silks. Look like you know what you're doing. |
| 7 | `play.sitdown.stakes5` | Sit-down card | Your 5th game. Finish it and you're on the board. No pressure. Okay, some fucking pressure. | Your 5th game. Finish it and you're on the board. No pressure. Okay, some pressure. |
| 8 | `lobby.waiting` | Lobby seat | Waiting on Leo. Fucking classic. | Waiting on Leo. Classic. |
| 9 | `lobby.needThree` | Start disabled | Need at least 3. Cambio's not a damn date. | Need at least 3. Cambio's not a date. |
| 10 | `lobby.full` | Join, full | Eight's the max. Watch, or grab the next one, latecomer. | Eight's the max. Watch, or grab the next one. |
| 11 | `join.midgame` | Join after R1 | They're on Round 3. You missed the start, genius. Watch this one, play the next. | They're on Round 3. Watch this one, play the next. |
| 12 | `join.rejoin` | Seat rejoin | Round 5 of 8. Your seat's still warm. Weird, but warm. | Round 5 of 8. Your seat's still warm. |
| 13 | `knock.clean.other` | Last-round card | Sam knocked on 2 and nobody could touch it. Smug bastard. | Sam knocked on 2 and nobody could touch it. Smug. |
| 14 | `knock.clean.you` | Your clean knock | You knocked and it fucking worked. | You knocked and it actually worked. |
| 15 | `rule.clean` | *rule*, both | Lowest hand at the table, so Sam scores −10 instead of 2. | (identical) |
| 16 | `knock.tie.other` | Last-round card | Leo knocked on 5. So did Priya. All that swagger for a goddamn draw. | Leo knocked on 5. So did Priya. All that swagger for a draw. |
| 17 | `knock.tie.8p` | Last-round card | Noah knocked on 2. Theo also had 2. Anticlimactic as hell. | Noah knocked on 2. Theo also had 2. Anticlimactic. |
| 18 | `rule.tie` | *rule*, both | A tie isn't a clean knock, so Leo scores his hand: 5. | (identical) |
| 19 | `knock.beaten.other` | Last-round card | Noah knocked on 4. Mia had 2. Absolutely fucked it. | Noah knocked on 4. Mia had 2. Absolutely blew it. |
| 20 | `knock.beaten.you` | Your beaten knock | You knocked into a 2. Bold. Stupid as shit, but bold. | You knocked into a 2. Bold. Wrong, but bold. |
| 21 | `knock.beaten.byYou` | You beat a knock | Your 2 just ruined Noah's whole night. Love that for you. | Your 2 just ruined Noah's whole night. Lovely. |
| 22 | `rule.beaten` | *rule*, both | Someone was lower, so Noah scores 4 + 10 = 14. | (identical) |
| 23 | `entry.outcomeLine` | Record sheet, live | Leo's on 4. Nobody under it so far. Noah: over 4 → Leo −10 · 4 → tie · under 4 → Leo 14. | (identical: math) |
| 24 | `redking.subzero` | Negative hand entered | Sub-zero. Someone's sitting on a Red King, the sneaky shit. | Sub-zero. Someone's sitting on a Red King. Sneaky. |
| 25 | `redking.floor` | Hand < −2 blocked | Bullshit. Two Red Kings per deck, so −2 is the floor. Recount. | Nice try. Two Red Kings per deck, so −2 is the floor. Recount. |
| 26 | `redking.cardsCap` | Cards mode, 3rd Red King | Only two Red Kings in a deck. Nice try, you cheeky bastard. | Only two Red Kings in a deck. Nice try. |
| 27 | `entry.highHand` | Hand > 50 | 54? That's more than four cards' worth. Sure about that, champ? | 54? That's more than four cards' worth. Sure about that? |
| 28 | `entry.noKnocker` | Record disabled | Who knocked? Somebody fucking did. | Who knocked? Somebody did. |
| 29 | `report.twoKnockers` | Self-report conflict | Mia and Leo both say they knocked. Somebody's full of shit. | Mia and Leo both say they knocked. Somebody's fibbing. |
| 30 | `report.gate` | Self-report gate | 4 of 6 in. Hands stay hidden till everyone's in. No peeking, you animals. | 4 of 6 in. Hands stay hidden till everyone's in. No peeking. |
| 31 | `edit.banner` | Someone else fixed a round | Mia fixed Round 3. You went from 1st to 5th. Brutal. | Mia fixed Round 3. You went from 1st to 5th. Ouch. |
| 32 | `edit.confirm` | Save fix dialog | Everyone sees this fix, with your name on it. Still feel good about it? | Everyone sees this fix, with your name on it. |
| 33 | `changes.header` | History → Changes | Every fix, in public. Nobody quietly edits their own damn hand. | Every fix, in public. Nobody quietly edits their own hand. |
| 34 | `abandon.confirm` | Abandon dialog | It stays in history marked Abandoned and counts for nothing. Anyone can restore it for 15 minutes, so don't rage-quit like a little shit. | It stays in history marked Abandoned and counts for nothing. Anyone can restore it for 15 minutes, so don't rage-quit. |
| 35 | `abandon.restored` | Restore banner | Priya restored the game. Nice try, Noah. | Priya restored the game. Nice try, Noah. Really. |
| 36 | `finish.gate` | Finish gate | Last round's in. Lock it? After this it's history, and history doesn't give a shit. | Last round's in. Lock it? After this it's history, and history doesn't take requests. |
| 37 | `winner.headline` | Photo finish | Priya wins. Prepare to hear about it for a fucking week. | Priya wins. Prepare to hear about it all week. |
| 38 | `winner.lastKnock` | Highlight | Stole it on the last knock. Cold-blooded. | Stole it on the last knock. Ice cold. |
| 39 | `winner.coWin` | Photo finish, tie | Dead heat. Priya and Leo share it. Nobody's happy. | Dead heat. Priya and Leo share it. Awkward. |
| 40 | `winner.wire` | Highlight | Led every round. Didn't even sweat. Annoying as hell. | Led every round. Didn't even sweat. Annoying. |
| 41 | `highlight.bottled` | Highlight | Mia led for five rounds and finished third. Bottled it. | Mia led for five rounds and finished third. Fumbled it. |
| 42 | `highlight.perfect` | Highlight | Priya: 2 knocks, 2 clean. No notes. | Priya: 2 knocks, 2 clean. Flawless. |
| 43 | `highlight.subzero` | Highlight | Priya's −1 in Round 4. A Red King was in there, the sneaky shit. | Priya's −1 in Round 4. A Red King was in there. |
| 44 | `last.other` | Final standings | Noah, 62. Dead fucking last. | Noah, 62. Dead last. |
| 45 | `last.you` | Your night | Last place. Next round's on you. That's just science. | Last place. Next round's on you. That's just science, sorry. |
| 46 | `rematch.invite` | Rematch card | Leo wants a rematch. Same seats, Mia starts. You in, or are you scared shitless? | Leo wants a rematch. Same seats, Mia starts. You in, or are you scared? |
| 47 | `rematch.declined` | Host's lobby | Noah's out. Coward. | Noah's sitting this one out. Coward. |
| 48 | `paddock.meter` | 5-nail meter | Two more games and you're on the board. Right now you're a rumour. | Two more games and you're on the board. Right now you're a rumour, basically. |
| 49 | `paddock.header` | Board, you're unranked | You're in the Paddock: under 5 games, no rank yet. Get your reps in. | You're in the Paddock: under 5 games, no rank yet. Get your games in. |
| 50 | `debut.reveal` | The Debut | Sam's on the board. 1,042 · #212. Look at him, a real fucking number. | Sam's on the board. 1,042 · #212. Look at him, a real number. |
| 51 | `board.gap` | Your pinned row | 11 points behind Mia. Very catchable. Go catch her. | 11 points behind Mia. Very catchable. |
| 52 | `h2h.behind` | Head-to-head | Leo's finished ahead of you 8 times out of 14. Two more and it's level. Or keep losing, it's your life. | Leo's finished ahead of you 8 times out of 14. Two more and it's level. |
| 53 | `h2h.ahead` | Head-to-head | You're up 9–4 on Jules. Be gracious. Or don't, fuck it. | You're up 9–4 on Jules. Be gracious. Or don't. |
| 54 | `h2h.receipt` | Share card | Noah 6 · Leo 8. I'm coming for you, you smug prick. | Noah 6 · Leo 8. I'm coming for you. |
| 55 | `nemesis.card` | Profile | Leo. Finished ahead of you 8 times. He knows. He fucking knows. | Leo. Finished ahead of you 8 times. He knows. |
| 56 | `notify.added` | Push | Noah put you at his table. Get in here. | Noah added you to his table. Pull up a chair. |
| 57 | `notify.yourHand` | Live Activity alert | Round 6: 4 of 5 in. Yours is the holdup, chief. | Round 6: 4 of 5 in. Yours is the holdup. |
| 58 | `notify.final` | Push | Priya won. You came 5th, but two Honours, so not a total shitshow. | Priya won. You came 5th, but two Honours, so not a total disaster. |
| 59 | `notify.debut` | Push | Game 5 done. You're #212 on the board. Fuck yes. | Game 5 done. You're #212 on the board. Let's go. |
| 60 | `notify.claimed` | Push | Sam claimed his history. Your 2–1 is official now. Don't fuck it up. | Sam claimed his history. Your 2–1 is official now. Don't blow it. |
| 61 | `honour.foundOut` | Honour earned | Found Out · You fucked around. | Found Out · You messed around. |
| 62 | `honour.redRum` | Honour earned | Red Rum · Sub-zero hand. Sneaky shit. | Red Rum · Sub-zero hand. Sneaky. |
| 63 | `honour.unbeaten` | Honour earned | Unbeaten · Five straight. Someone stop this bastard. | Unbeaten · Five straight. Someone stop this person. |
| 64 | `empty.history` | You → History | No games yet. Zero wins, zero losses, zero fucks given. | No games yet. Zero wins, zero losses, zero clue. |
| 65 | `empty.rivals` | You → Rivals | No rivals yet. Play someone twice and it gets personal as hell. | No rivals yet. Play someone twice and it gets personal. |
| 66 | `empty.honours` | Honours | Nothing on the wall yet. Go knock something, damn it. | Nothing on the wall yet. Go knock something. |
| 67 | `empty.nearby` | Play, no tables | No tables nearby. Start one, or go find some damn friends. | No tables nearby. Start one, or go find some friends. |
| 68 | `empty.playedWith` | Board → Played with | Nobody to rank you against yet. Bit lonely, innit. | Nobody to rank you against yet. Bit quiet, innit. |
| 69 | `error.claimUsed` | Claim | This history's already been claimed. Nice try though. | This history has already been claimed. |
| 70 | `error.wrongCode` | Claim | That code's not a thing. Check it and try again. | That code doesn't match anyone. Check it and try again. |
| 71 | `error.syncFailed` | Upload retry | Upload failed. The internet's being a dick. Your game's safe on this phone; we'll retry. | Upload failed. The internet's being difficult. Your game's safe on this phone; we'll retry. |
| 72 | `offline.linked` | Sync chip detail | No internet. Doesn't matter. 5 phones linked, game's fine. | No internet. Doesn't matter. 5 phones linked, game's fine, honestly. |
| 73 | `offline.separated` | Sync chip detail | This phone's wandered off. Get closer to the table to sync, you stray. | This phone's wandered off. Get closer to the table to sync. |
| 74 | `offline.final` | Photo finish offline | Locked in. Uploads when the Wi-Fi stops being shit. | Locked in. Uploads when the Wi-Fi gets its act together. |
| 75 | `offline.duplicate` | Changes | Two phones recorded Round 5 while apart. One's in, one's on the bench. Pick one, for fuck's sake. | Two phones recorded Round 5 while apart. One's in, one's on the bench. Pick one. |
| 76 | `tip.knock` | Coach tip | Knocking's a gamble: strictly lowest hand gets −10, a tie scores your hand, anything else is hand + 10. Don't be a hero on a damn 9. | Knocking's a gamble: strictly lowest hand gets −10, a tie scores your hand, anything else is hand + 10. Don't be a hero on a 9. |
| 77 | `learn.kings` | Lesson 1 | Red Kings are −1. Black Kings are 13. Same card, wildly different energy. | Red Kings are −1. Black Kings are 13. Same card, very different energy. |
| 78 | `since.passed` | Since you last looked | Leo passed you on the played-with board. Petty, but true. Go fix it. | Leo passed you on the played-with board. Petty, but true. |
| 79 | `form.monthly` | Monthly form card | October: 9 games, 3 wins, four −10s. Mid as hell, but improving. | October: 9 games, 3 wins, four −10s. Mid, but improving. |
| 80 | `voice.settingFooter` | Settings → Voice | Clean swaps the swearing for gentler words. The jokes stay. So does the scoring, obviously. | Clean swaps the swearing for gentler words. The jokes stay. So does the scoring. |

**Buttons never change between voices** and are always literal: Sit down · Start a table · Start game · Record round 6 · Next · Send my hand · Fix this round · Save fix · Finish game · Fix a round first · Run it back · I'm in · Not this time · Claim my history · Send the receipts.

---

## 13. SwiftUI implementation map

| Screen / surface | Native components and APIs | UIKit? |
|---|---|---|
| App shell | `TabView` + `Tab`, `Tab(role: .search)`, `tabViewBottomAccessory`, `tabBarMinimizeBehavior(.onScrollDown)`, `@Observable` stores, `Voice` `EnvironmentKey` | No |
| Welcome / onboarding | `NavigationStack`, `SignInWithAppleButton`, **`#if DEBUG` `TestUserSignInButton`** (compiled out of Release; CI symbol check), horse mark as a custom `Shape` animated with `PhaseAnimator` (not `symbolEffect`) | No |
| Make your silks | `Canvas`-drawn silks patterns from a `SilksSpec` value, `Picker(.palette)`, `TextField`, `.sensoryFeedback(.selection)` | No |
| Play | `ScrollView` + `LazyVStack`, `.glassEffect()` Sit-down card (user-tapped; **no auto `.sheet`**), `ContentUnavailableView` | No |
| Discovery & sync | Network framework (`NWListener`/`NWBrowser`, or iOS 26 `NetworkListener`/`NetworkBrowser`), `includePeerToPeer`, framed event gossip, `NISession` distance; MultipeerConnectivity fallback (session only, never `MCBrowserViewController`) | No |
| Lobby | `List` + `.onMove`, played-with chips, `Picker(.segmented)`, `Stepper`, `Toggle` (Keep it clean tonight), CoreImage QR, `ShareLink` | No |
| Table | `fullScreenCover`, `NavigationStack`, glass `toolbar` + `Menu`, `GlassEffectContainer`, `.contentTransition(.numericText)`, `.popover` for Why?, TipKit, `.sensoryFeedback` | **Yes, one line:** `UIApplication.shared.isIdleTimerDisabled` (no SwiftUI API), wrapped in `IdleTimerLock` tied to `scenePhase` and Table visibility |
| Record / Fix sheet | `.sheet` `.presentationDetents([.large])`, custom keypad `Grid` of `Button`s, deterministic `EntryCursor` model (second digit → advance; Next → advance), `TextField(value:format:)` + `.keyboardType(.numbersAndPunctuation)` for direct edit, `.confirmationDialog` for Save fix | No |
| Cards mode | `LazyVGrid` of card chips, chip row with `Button` × per chip, `.accessibilityAction(named:)` Remove, disabled state for the 3rd Red King | No |
| Self-report | Same keypad, `Toggle("I knocked")`, `.blurReplace` reveal, `.alert` for two knockers | No |
| History & Changes | `Grid` with pinned totals (`.safeAreaInset`), `List` of change rows with Undo / Use this version buttons, Swift Charts `LineMark` + `accessibilityChartDescriptor`, `.accessibilityRotor` (Edited rounds, Knocks) | No |
| Finish gate | Plain view, deterministic seal time from the last event's HLC + 15 min, `TimelineView` for the "Locks itself at" label | No |
| Photo finish | `keyframeAnimator` slit-scan over a `Canvas`, `ImageRenderer` share card, `ShareLink` (AirDrop) for claim links | No |
| Rematch | Invitation event over the same sync layer, per-phone `I'm in` / `Not this time`, host `Start` | No |
| Claim | `onOpenURL`, `SignInWithAppleButton`, **`TextField` + `.textInputAutocapitalization(.characters)` + `.autocorrectionDisabled()` + `.keyboardType(.asciiCapable)`** (no `.oneTimeCode`) | No |
| Profile / H2H | `navigationDestination(for:)`, `Grid` stats, Swift Charts stacked `BarMark`, `ImageRenderer` receipts card | No |
| Board | `List` with ranked / Paddock `Section`s, `Picker(.segmented)`, lens chips, `.safeAreaInset(edge: .bottom)` pinned row | No |
| Honours | `LazyVGrid`, `Gauge(.accessoryCircular)` rings, detail `.sheet` | No |
| Learn | Paged `TabView(.page)` lessons, `Slider` simulator with the custom horseshoe symbol and `.symbolEffect(.rotate)`, `.searchable` bundled rules (`AttributedString` Markdown) | No |
| Voice | Two String Catalogs with identical keys, `LocalizedStringResource(table:)`, DeclaredAgeRange (iOS 26) for the under-18 default, build-time catalog parity test | No |
| Live Activity / Island | ActivityKit `Activity<GameAttributes>` (content state carries top 4 + you), push tokens, `DynamicIsland` regions, `LiveActivityIntent` buttons, `AlertConfiguration` for the self-report nudge, `staleDate` | No |
| Widgets / controls | WidgetKit `StaticConfiguration`, accessory families, `Button(intent:)`, `ControlWidget` "Start a table" | No |
| Notifications | `interruptionLevel`, `threadIdentifier = gameID`, `UNNotificationAction` Join via App Intent, Clean copy unless "Swearing on the Lock Screen" is on | No |

**Stretch (v1.1):** App Clip for guests with phones (scan the rotating-token QR → That's me → report). It relays through the backend, because App Clips may not get local peer-to-peer.

---

## 14. Risks and open questions

1. **Profanity misfires.** A roast that lands at one table can sting at another. Mitigations: the identity rule (§12.1), *Keep it clean tonight* for any player, Clean on the Lock Screen by default, and a copy review gate with two reviewers per release. Highlights are templates over facts, so the app can't improvise anything worse.
2. **Age rating tier** may come back as 18+, which narrows reach. Acceptable for the product (it's for adults playing over drinks). The Clean mode and clean store metadata keep the listing presentable.
3. **Single-digit Next** costs about 2 taps per round compared with v1's timed advance. That's the right trade for predictability. Real-table testing should check whether a "lock single digits" option (every value needs Next) is preferred.
4. **15-minute seal** could leave a game open if the table leaves without tapping Finish. The deterministic seal handles it, and the photo finish then shows on next open.
5. **New York serif at small sizes** is only for display and headline styles, never captions or numbers.
6. **Rematch opt-in** is slower than v1's auto-move (6 taps vs 2), on purpose. A saved seat is the only pre-accepted invite.
