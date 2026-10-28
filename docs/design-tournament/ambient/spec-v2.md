# Kedro for iOS: "Ambient Table" (After Hours)
### Design tournament entry · spec v2 · October 2026

Companion file: [`mockups-v2.html`](./mockups-v2.html) has 22 frames (21 iPhone portrait frames at 393 × 852 pt and one landscape table display at 852 × 393 pt), plus a system sheet showing the palette, type and motifs. Frame numbers F1–F22 below refer to that file. The v1 files (`spec.md`, `mockups.html`) are unchanged.

---

## Changes from v1

### What the product owner asked for

All four round 1 entries read as childish. v1 Ambient had cartoon horse heads with face markings, rounded numerals, oat and chestnut "cozy" colors, an emoji Joker chip, and a "hoof dust" particle burst. v2 replaces the whole visual identity and all the copy:

| v1 | v2 |
|---|---|
| Cartoon front‑facing horse heads with coats and blazes | **Colours**: racing silks cut to a disc (hoops, quarters, chevrons, sash...) in a curated register. No faces anywhere. |
| SF Pro Rounded scores, bubbly 20+ pt radii, pill buttons everywhere | **New York** serif for display and the voice, SF Pro (condensed, monospaced digits) for numbers, squared 12 pt cards, 4 pt chips. Capsules only where the system draws Liquid Glass controls. |
| Oat, chestnut, green/amber/red outcome badges | **After Hours** palette: Onyx, Bone, Kedro Red, Pewter, a little Satin Brass. Outcomes are monochrome by **form** (solid / outline / hatched) plus words. Red never means bad. |
| "Hoof dust" particles and a "canter" spring | A **photo‑finish wipe**, a hairline that sweeps the winner in. Springs without bounce. |
| Friendly, explanatory copy | **The voice**: friends roasting each other over drinks, with real profanity where it lands, and a **Clean** rewrite of every line (§2). Rated for mature audiences. |

The philosophy is the same: the game lives across the whole device. v2 says it differently. Kedro is the after‑hours member's card for your table. It's on the Lock Screen face‑up next to the drinks, in the Island, on a phone propped sideways in the middle of the table, and it speaks like the people sitting there.

### Every round 1 must‑fix, and how v2 resolves it

| # | Must‑fix (judge) | Resolution in v2 | Where |
|---|---|---|---|
| 1 | Background BLE strictly optional. It no longer drives offline Live Activities, and a stale Live Activity is the normal offline locked state. Bluetooth is requested only when a user turns on the nearby‑table alert. (native, table, product) | **No background Bluetooth in the core design.** The Bluetooth state link is deleted. A locked, offline phone's Live Activity goes **stale by design**: it dims at `staleDate` and reads *"Last updated 9:42. Open Kedro to catch up."* When a phone is unlocked and Kedro opens, it catches up from peers in under a second. Background BLE survives only as an **opt‑in** setting, *Tell me when my people start a table nearby*, offered on the second finished game with a battery and privacy explanation. It's the only place Kedro asks for Bluetooth. | §5.1, §12.1, F19 |
| 2 | Move the Local Network and Bluetooth prompts out of onboarding to the first Start / Sit down. (native) | Onboarding asks for **nothing**. Local Network is requested, behind a one‑line primer, the first time you tap **Join a table**, **Start a table** or **Sit down**. Nearby Interaction is requested the first time two tables are visible at once, or from the lobby's *Tell tables apart* row. Notifications are requested on the **first finish screen** (*"Get told when you make the board..."*). | §5.1, F1, F3, F11 |
| 3 | Correct the StandBy claim and drop `supplementalActivityFamilies`. (native) | StandBy uses the **standard Lock Screen Live Activity presentation**, which the system scales up automatically. `supplementalActivityFamilies` is gone (it targets watchOS Smart Stack and CarPlay, which v1 doesn't target). The dedicated big‑type board is the in‑app **landscape table display** (F21). | §12.1, F21 |
| 4 | Replace the wooden‑oval lobby with a reorderable List. Seat actions need visible buttons or swipe actions with menu equivalents, and an AX5 layout. (native, table) | The lobby is a **`List` with `.onMove`** (seat order is the order around the table, used for knocker‑first entry and dealer rotation). Every row has a visible **⋯ seat menu** (Make scorekeeper, Assign reporter, Move, Remove), and the same actions are available as swipe actions and through VoiceOver custom actions. At AX5 the row stacks and the menu becomes a full‑width *Seat options* button (F22). | §6, F4, F22 |
| 5 | Confirmation on the knock dock and the Lock Screen "I knocked": an undoable banner, and only the knocker's own phone can claim from the Lock Screen. (native, table, product) | The dock is now **hold‑a‑face** (0.5 s press with a ring fill), so a stray touch does nothing. The phone that set it gets a **5‑second Undo** toast. Every other phone updates **silently**: no haptic, no sound, no alert configuration. The Lock Screen **I knocked** button exists only on your own Live Activity and only sets *you*. It's **two‑step**: the first tap turns it into *Tap again: you knocked* for 4 s. | §7.1, F5, F6, F19 |
| 6 | Add "Play as a guest" to first launch in the full app. (native) | First launch has three equal paths: **Join a table** (primary), **Play as a guest**, and **Sign in with Apple** (shown disabled with "Soon" until the developer account clears, per PRD 3.1). The guest gets a device‑bound guest identity and a claim token, so signing in later claims the history without a code. | §5.2, F1 |
| 7 | Replace the 30 s auto‑seal with an explicit Finish action plus an idle fallback. (native; also stolen from table‑first) | After the last planned round, every phone shows the **Finish gate**: *"That was round 10. Lock it in, or fix your shit first."* with **Finish game** / **Fix a round first** / **Add rounds**. Anyone, on any phone, can finish. If nobody records anything for **15 minutes** it finishes itself. Both seal times are **deterministic** (the HLC of the Finish event, or last event + 15 min), so offline phones agree. | §9, F10 |
| 8 | Cut round‑entry taps with two‑digit auto‑advance (~12 taps), and make the knock‑time tap optional so it isn't double work. (table, product) | The keypad **auto‑advances** after two digits, after **0**, and after **−1** or **−2** (the only legal negatives). A single digit takes **Next**. If nobody set the knocker during play, the entry sheet's first row asks for it. The knock‑time hold is a shortcut, never a requirement. A 5‑player round now takes **12 taps** (§17). | §7.2, F7 |
| 9 | Hide self‑report values until every hand is in, then reveal together. (table) | Self‑report hands are **sealed**. Phones show *In* with a lock, never the number, until the last hand arrives. Then all phones **flip together** at a shared reveal time (HLC of the last report + 600 ms). Your personal rule line never shows other people's numbers: *"If Leo had more than −1, his knock is busted."* | §7.3, F8 |
| 10 | Lens chips re‑sort the board while keeping the official rank badge. Give lenses their own ordinal, or use separate Records boards. (table, product) | **Lenses are gone.** The board has one sort: Rating, with official ranks. **Records** is a separate segment of read‑only category boards (Win rate, Knock success, Avg per round, Longest streak, Most games). Each has its own ordinal and minimum, and there's never an official rank badge beside it. | §13.3, F16 |
| 11 | Separate outcome badges from deltas. (table) | Deltas are **neutral signed numbers** in Pewter (*−10*, *+6*). The knock outcome is a separate **word chip** that appears only on the knocker's row and in the last‑round card: **↓ Landed −10** (solid), **= Dead heat** (outline), **× Busted +10** (hatched). Color carries no meaning. | §8, F5 |
| 12 | Background Bluetooth discovery as an explicit opt‑in after the first game; a visible seat menu. (table) | See #1 and #4. | — |
| 13 | Fix the mockup data: the lobby at 8 rounds (or drop the extension), and the F1 caption. (table) | The lobby (F4) shows **8 rounds**. The Changes log (F9) shows *Maya extended the game 8 → 10* after Round 4, and every live frame from Round 5 on says *of 10*. Every caption describes only what its frame shows. | F4, F9 |
| 14 | Add a "How rating works" sheet, and show each game's rating change. (product) | **How rating works** is linked from the board, the profile and the debut moment: *"Your rating is our best guess at how good you are, minus a margin for luck. Play more and the margin shrinks."* Every game in history shows its rating change (*+14*). The rating is calculated from game 1 but **revealed at game 5**, publicly, at the finish. | §13.3, F14, F16 |
| 15 | Hiding the tab bar and adding a custom dock inside the Table tab is non‑standard. (product, weakness) | The live game is now a **`fullScreenCover`** opened with a zoom transition from the Table tab. **Minimize** collapses it into the tab bar's **bottom accessory**, the Music Now Playing pattern. | §4 |

### Ideas adopted from the other entries

Only the ones that fit an ambient, whole‑device design: the explicit **Finish gate** with a 15‑minute idle fallback (table‑first); **History grid and Changes log on one page**, with downstream effects spelled out (table‑first); **signs and words, never red/green** (table‑first); the **last‑round sentence card** (table‑first); VoiceOver **announcements only when VoiceOver is running**, plus **Edited rounds** and **Knocks** rotors (table‑first); **Live Activity AlertConfiguration as the only self‑report nudge** (table‑first); a **claim token on the guest's device** (table‑first, via the App Clip); **Records** boards (table‑first); rating change on every game, and the **notification ask on the first finish** (table‑first); NI **"At your table" vs "Other tables nearby"** plus a **spoken table word** (rivalry; here it's a generated racehorse name, *Dubious Intent*); a **stakes strip** on the Table card and lobby (rivalry); **Since you last looked** (rivalry); **rating debut at game 5** (rivalry); **gap to level** (rivalry); a **5‑second Undo after Save round** (rivalry); **Why?** opening a prefilled knock calculator (rivalry); an **assigned reporter** for each guest (rivalry); **glass only on controls, numbers on solid surfaces** (playful); **guest‑first welcome** (playful); **name‑matched guest reuse** (playful); a **Restore window after Abandon** (playful); **rematch rotates the starting seat** (playful); **per‑table Colours de‑duplication** (playful).

---

## 0. Thesis

**After hours, the game lives in the room, not in an app.** A Cambio night is five phones on a bar table among glasses, cards and elbows. Ambient Table treats those phones as one object, the **table**. It forms when someone taps Start, other phones in arm's reach find it without typing, and it keeps itself in sync phone to phone with or without internet. Most of the night Kedro isn't "open". It's a Live Activity on a phone lying face‑up, a number in the Island, or a phone propped sideways as the table's scoreboard. It takes over the screen twice: entering a round, and the finish.

v2 adds a second idea: **the voice is part of the room.** The table is already roasting itself. Kedro joins in with the same joke on every phone at the same moment, and it never swears at the numbers.

| PRD goal | How Ambient Table delivers it |
|---|---|
| **Fast table flow** | The knocker can be set by holding a face at the knock, or on the entry sheet if nobody did. The keypad auto‑advances: **12 taps** for 5 players. In self‑report, hands go in sealed and in parallel. Phones can stay locked, because the Live Activity is the scoreboard. |
| **Everyone joins** | Peer‑to‑peer discovery puts a **Table card** on every nearby phone, named by the faces seated and a spoken table word. Returning players tap **Sit down** once. Guests are a typed name, a reused guest identity, or the App Clip. |
| **People come back** | Rival, Board and Close‑race widgets; the 5‑nail **shoe**; a rating debut at game 5; *Since you last looked*; gap‑to‑level lines; a catalog of achievements people will screenshot because they're funny. |
| **Spreads to new tables** | Learn in 4 minutes; a knock calculator behind every **Why?**; the App Clip; and a claim hand‑off that sells the guest their own trash talk. |

**Principles**

1. **Glanceable over interactive.** If a system surface the user is already looking at can show it, it goes there before it goes into a screen.
2. **Capture facts when they happen, and never require it.** The knock can be marked at the knock, and the entry sheet covers it if nobody did.
3. **The table is the trust boundary.** Being in the same room is the credential for joining. Transparency is the credential for edits.
4. **The numbers never swear.** Scores, rule lines, the Changes log and stat definitions are plain and exact. The voice comments around them, in serif italic, so commentary and record never blur.
5. **The horse is heritage, not a mascot.** It appears as a crest, a shoe, silks and racing vocabulary. It never has a face that smiles.

---

## 1. Information architecture

`TabView` with the iOS 26 `Tab` API and a Liquid Glass tab bar:

| Tab | Symbol | Purpose |
|---|---|---|
| **Table** | custom `kedro.table` (a ring of seats) | The Radar: nearby tables, Start a table, Since you last looked, rematch, recent games. |
| **You** | your Colours disc | Profile, stats, rivals, achievements, history, claim a guest history, Settings › Voice. |
| **Board** | custom `kedro.shoe` | Leaderboards: Rating (Played with / Global), Records, Community. |
| **Learn** | `book.closed` | Lessons, Score‑this‑round drill, knock calculator, rulebook. |
| **Search** (`Tab(role: .search)`) | `magnifyingglass` | Any player's public profile. |

**The live game** is a `fullScreenCover` with `.navigationTransition(.zoom)` from the Table card or lobby. **Minimize** (chevron, top left) dismisses it into `.tabViewBottomAccessory`. That's a glass strip that says *R6 of 10 · You're 2nd · Maya leads by 1*, and tapping it brings the game back. Round entry, Report hand, History, Rules and the game menu are sheets over the live game. The finish is part of the same cover.

```
TabView
├─ Table ─ Radar F3 → Table card → Sit down
│          └─ Start a table → Lobby F4 (List)
│   fullScreenCover: Live game F5/F6 ─ sheets: Enter hands F7 · Report hand F8 · History+Changes F9 · Rules/Calculator F18 · ⋯ menu
│                    └─ Finish gate F10 → Finish F11 → Hand‑off F12 → Rematch lobby
├─ You ── Profile F14 → Head‑to‑head F15 · Achievements F17 · History · Settings › Voice (F2 content)
├─ Board ─ F16 (Rating | Records) → How rating works
├─ Learn ─ F18
└─ Search
Outside: Lock Screen Live Activity F19 · Dynamic Island, widgets, Control F20 · Table display F21 · App Clip F13 · notifications
```

Deep links: `kedro.app/t/<table>?k=<rotatingToken>` (join), `/claim/<code>`, `/game/<id>`, `/game/<id>/report`, `/player/<id>`.

---

## 2. Voice & copy

### 2.1 Who's talking

Kedro talks like **the sharpest friend at the table, two drinks in**: quick, dry, a bit mean about bad decisions, and never mean about who you are. It isn't a brand that learned to swear, and it isn't a toy. It's the mate who says *"fucked around, found out"* when your knock gets beaten and then deals the next hand.

### 2.2 Tone principles

1. **Roast the play, never the person.** Fair targets are decisions, scores, luck, streaks, rivalries and slowness. Off limits: bodies, gender, race, ethnicity, sexuality, religion, disability, age, class, accents and names. There are no slurs, including "reclaimed" ones, and no sexual content.
2. **The numbers never swear.** Hand values, scores, rule lines, the Changes log, stat definitions and recovery steps are plain and exact. Commentary is set in New York italic around them, so you always know which line is the record and which is the joke (F5, F7).
3. **Swearing is punctuation, not every sentence.** At most one swear per string. About a third of strings swear, and the rest earn their attitude with timing. Profanity goes where it lands: the end of a line, a big moment, a bad decision.
4. **Everyone gets roasted, including the winner.** A winner headline always includes a jab. Last place always gets an exit (Rematch).
5. **Punch up, not down.** For a player's **first 3 games**, or any seat with **Learner hints** on, their own bad outcomes get a teaching line instead of a roast (*"Busted: Sam had less. Knock when you're at 4 or under."*). Nobody gets roasted for learning.
6. **Clean is a rewrite, not a bleep.** No asterisks and no "f***". Each Clean line is the same joke with different words, and it's written by a person.
7. **Same line, same moment, every phone.** Variants are chosen deterministically from the game ID, round and event, so the whole table reads the same joke at once. One source of truth applies to the jokes too.
8. **Glance length.** Lines for the Island, Lock Screen and notifications are **≤ 60 characters**, and the punchline can't be truncated off.
9. **Durable slang over this week's slang.** Use *cooked, mid, run it back, on the bounce, FAFO, bottled it*. Avoid anything that will be cringe by spring. Racing vocabulary beats horse puns: *dead heat, photo finish, wire to wire, broke maiden*. Never "neigh", "hay", "pony up" or "mane event".
10. **Plain when it matters.** Destructive confirmations, data‑loss risks, permission primers and accessibility labels lead with plain meaning. The joke, if any, comes after.

### 2.3 Settings: Voice, House voice, Lock Screen, and the age rating

| Setting | Where | Options | Default | Scope |
|---|---|---|---|---|
| **Your voice** | Onboarding (F2), Settings › Voice | **Unfiltered** · **Clean** | Unfiltered | Everything outside a game: profile, achievements (names and descriptions), board, widgets, your notifications. |
| **House voice** | Lobby (F4) | Unfiltered · Clean | **Clean if any seated player's voice is Clean**, otherwise Unfiltered. The host can force Clean (*"Keep it clean tonight"*). | Everything inside that game on **every phone**: live screen, last‑round card, Live Activities, Island, table display, finish. The lobby says *"Clean tonight: someone at the table prefers it"* and never says who. |
| **Swear on my Lock Screen** | F2, Settings › Voice, the notification primer | On · Off | On | When Off, every notification and Live Activity on your phone uses the Clean line, even when the house is Unfiltered. This is for the phone that lights up in a meeting. |

Achievements whose names swear have a Clean name too (*Fucked Around, Found Out* / *Found Out*). Visitors see a profile in **their own** voice, not the owner's.

**Age rating.** Unfiltered is the default, so the app is rated as a mature app whatever any one person chooses. In App Store Connect we answer **Profanity or Crude Humor: Frequent/Intense** and **Alcohol, Tobacco, or Drug Use or References: Infrequent/Mild** (drinks are mentioned, never encouraged). Under Apple's current age‑rating tiers that puts Kedro in the upper tiers (16+ or 18+). If the computed tier comes out below where the product owner wants it, we use App Store Connect's option to set a higher rating. First launch says it plainly: *"Mature: frequent profanity. Clean is one tap away."* The App Clip inherits the app's rating and uses the **house** voice. Other locales ship **Clean only** until a native writer does an Unfiltered pass, because we never machine‑translate swearing.

**Implementation.** Two String Catalog tables (`Voice‑Unfiltered.xcstrings`, `Voice‑Clean.xcstrings`) share keys. `Voice` is an `@Observable` value in the environment, and lines resolve with `String(localized: key, table: voice.table)`. Variant keys (`knock.landed.1…6`) are picked by `hash(gameID, round, event) % count`, so every phone picks the same one. Learner seats resolve to `*.learner` keys.

### 2.4 Copy deck

Names in examples come from the sample game. `{}` marks slots. **U** = Unfiltered (the default), **C** = Clean. Every row is used in the product, and rows marked with a frame number appear in the mockups.

| # | Surface | U (default) | C | Frame |
|---|---|---|---|---|
| **Onboarding and first launch** |||||
| 1 | Welcome subhead | Kedro keeps score so nobody cooks the fucking books. | Kedro keeps score so nobody cooks the books. | F1 |
| 2 | Join a table caption | Someone's dealing? Get in. | Someone's dealing? Get in. | F1 |
| 3 | Play as a guest caption | No account, no bullshit. Sign up later if you're any good. | No account, no nonsense. Sign up later if you're any good. | F1 |
| 4 | Voice screen title | How filthy do you want it? | How spicy do you want it? | F2 |
| 5 | Voice screen subhead | Same scores, same app. Just a different mouth on it. | Same scores, same app. Just a different mouth on it. | F2 |
| 6 | Local Network primer | Kedro needs to see the phones around you. That's how the table finds itself. No tracking, no creepy shit. | Kedro needs to see the phones around you. That's how the table finds itself. No tracking, nothing creepy. | — |
| 7 | Nearby alert opt‑in (Bluetooth) | Want a heads‑up when your people start a table nearby? Costs a bit of battery. Kill it whenever. | Want a heads‑up when your people start a table nearby? Costs a bit of battery. Turn it off whenever. | §5.1 |
| **Joining** |||||
| 8 | Table card stakes, 5th game | Your 5th game. Win or lose, you're on the damn board after this. | Your 5th game. Win or lose, you're on the board after this. | F3 |
| 9 | Lobby stakes, rivalry | Maya leads Noah 13–7. Tonight's as good a night as any to fix that shit. | Maya leads Noah 13–7. Tonight's as good a night as any to fix that. | F4 (U), F22 (C) |
| 10 | Arrival toast (host) | Priya's in. Not your Priya? Remove | Priya's in. Not your Priya? Remove | F4 |
| 11 | Radar empty | Nobody's here. Start a table and make it everyone's problem. | Nobody's here yet. Start a table and round people up. | §5 |
| 12 | Late arrival, Watch | You missed the deal, genius. Watch this one. You're in the rematch. | You missed the deal. Watch this one. You're in the rematch. | §5.3 |
| 13 | Table full | Eight's the max. Grab a drink and heckle. | Eight's the max. Pull up a chair and heckle. | §5.3 |
| 14 | Since you last looked | Noah climbed 3 spots. Maya's streak died at 4. Pour one out. | Noah climbed 3 spots. Maya's streak ended at 4. Pour one out. | F3 |
| **Knocks and rounds** |||||
| 15 | Knock set (Live Activity, Island) | Maya knocked. Last turns, don't fuck it up. | Maya knocked. Last turns, don't blow it. | F6 |
| 16 | Landed (−10) | Noah knocked on 3 and fucking nailed it. | Noah knocked on 3 and nailed it. | F5, F6, F21 |
| 17 | Landed, variant | Cold‑blooded. {name} walks off with −10. | Cold‑blooded. {name} walks off with −10. | — |
| 18 | Dead heat (tie) | Dead heat. Maya keeps her 2. Bold move, shit payoff. | Dead heat. Maya keeps her 2. Bold move, meh payoff. | F19 |
| 19 | Busted (+10) | Priya knocked on 1. Sam had −1. Fucked around, found out. | Priya knocked on 1. Sam had −1. Messed around, found out. | F2 |
| 20 | Busted, big | Maya knocked on 3, Sam had 2. What the hell was that? | Maya knocked on 3, Sam had 2. What was that? | F10 |
| 21 | Busted, learner seat | Busted: someone had less. Knock when you're at 4 or under. | (same, already clean) | §2.2 |
| 22 | Red King in a hand | Red King. Minus one and a smug‑ass grin. | Red King. Minus one and a smug grin. | F8 |
| 23 | Both red Kings (−2) | Both red Kings. −2. Who the hell shuffled? | Both red Kings. −2. Who shuffled? | — |
| 24 | Self‑report sealed | Your hand's in and hidden. No peeking, you animals. | Your hand's in and hidden. No peeking, you lot. | F8 |
| 25 | Waiting on a hand | Waiting on Priya. Take your sweet‑ass time. | Waiting on Priya. Take your sweet time. | — |
| 26 | High value check | 53? What the hell is in that hand? Double‑check. | 53? What is in that hand? Double‑check. | §7.2 |
| 27 | Round saved, undo | Round 6 saved. Fat‑fingered it? Undo | Round 6 saved. Typo? Undo | §7.2 |
| 28 | Edit banner | Priya fixed Round 2. Leo's −10 is now a dead heat. Shit happens, Leo. | Priya fixed Round 2. Leo's −10 is now a dead heat. Tough luck, Leo. | F9 caption |
| 29 | Lead change | Maya's back in front. Somebody do something, for fuck's sake. | Maya's back in front. Somebody do something. Anything. | — |
| 30 | Final round | Last round. Make it count or make it ugly. | (same, already clean) | — |
| **Finish** |||||
| 31 | Finish gate | That was round 10. Lock it in, or fix your shit first. | That was round 10. Lock it in, or fix it first. | F10 |
| 32 | Winner headline | Noah fucking wins. | Noah wins. Obviously. | F11 |
| 33 | Winner subline | Fourth after Round 3, first at the post. Dark horse shit. | Fourth after Round 3, first at the post. Proper dark horse. | F11 |
| 34 | Shared win | Photo finish. Noah and Priya split it, and neither will shut the hell up about it. | Photo finish. Noah and Priya split it, and neither will shut up about it. | — |
| 35 | Runner‑up | Priya, 18 back. Close enough to be pissed about it. | Priya, 18 back. Close enough to be annoyed about it. | — |
| 36 | Last place | Leo: 99. Dead fucking last. One off triple digits, which is honestly impressive. | Leo: 99. Dead last. One off triple digits, which is honestly impressive. | F11 |
| 37 | Rematch caption (rotates the deal) | Run it back. You deal, don't fuck it up. | Run it back. You deal this time. | F11 |
| 38 | End early confirm | End it now? Counts fully in stats, so whoever's winning: congrats, you cheap bastard. | End it now? Counts fully in stats, so whoever's winning: congrats, you lucky so‑and‑so. | §9.3 |
| 39 | Abandon confirm | Abandon this game? It stays in history marked Abandoned and counts for jack shit. | Abandon this game? It stays in history marked Abandoned and counts for nothing. | §9.3 |
| 40 | Restore window | Leo rage‑quit while losing. Restore the damn game? 14:52 left. | Leo bailed while losing. Restore the game? 14:52 left. | §9.3 |
| **Board and eligibility nudges** |||||
| 41 | 3 of 5 (your own profile and Board) | 3 of 5. Two more and there's no hiding how shit you are. | 3 of 5. Two more and there's no hiding how bad you are. | — |
| 42 | 4 of 5, lobby | Next game puts you on the board. Don't fuck up your debut. | Next game puts you on the board. Don't blow your debut. | — |
| 43 | Debut (public, at the finish) | Priya's on the board. #540 in the world. Respectable as hell. | Priya's on the board. #540 in the world. Respectable. | F11 |
| 44 | Close race | Dana's 7 behind you. One shit game and she's past. | Dana's 7 behind you. One bad game and she's past. | F16, F20 |
| 45 | How rating works (opening) | Your rating is our best guess at how good you are, minus a margin for luck. Play more and the margin shrinks. Three lucky games can't fake it. | (same, already clean) | — |
| **Notifications** (all ≤ 60 characters in the title and body line) |||||
| 46 | Nearby table (opt‑in only) | Maya's table is starting 2 m away. Sit your ass down. | Maya's table is starting 2 m away. Pull up a chair. | §12.3 |
| 47 | Seat saved (host added you) | Maya saved you a seat. Don't make it weird. | (same, already clean) | §12.3 |
| 48 | Self‑report (Live Activity alert) | Leo knocked. Report your damn hand. | Leo knocked. Report your hand. | §12.3 |
| 49 | Recap (you left early) | Noah took Thursday table. You came 3rd. Mid as hell. | Noah took Thursday table. You came 3rd. Very mid. | §12.3 |
| 50 | Ranked | Five games. You're #540. Welcome to the board, degenerate. | Five games. You're #540. Welcome to the board. | §12.3 |
| 51 | Knocked off a rank | Dana just passed you. #4 now. Unacceptable shit. | Dana just passed you. #4 now. Unacceptable. | §12.3 |
| 52 | Guest claimed | Sam claimed their games. That 90 is on the record forever. Damn. | Sam claimed their games. That 90 is on the record forever. Ouch. | §12.3 |
| 53 | Notification primer (finish) | Get told when you make the board or someone nicks your spot. No spam, no guilt‑trip bullshit. | Get told when you make the board or someone nicks your spot. No spam, no guilt trips. | F11 caption |
| **Rivals and trash talk** |||||
| 54 | Head‑to‑head header | Maya's finished ahead of you 13 times. Thirteen. Jesus. | Maya's finished ahead of you 13 times. Thirteen. Yikes. | F15 |
| 55 | Gap to level | Five more finishes ahead of her and it's level. Get to work. | (same, already clean) | F15 |
| 56 | Nemesis card | Your nemesis. Your personal fucking problem. | Your nemesis. Your personal problem. | F14 |
| 57 | You lead | You lead Leo 11–4. Don't be a dick about it. Okay, a little. | You lead Leo 11–4. Don't gloat. Okay, a little. | — |
| 58 | Rival widget | Maya 13, you 8. She's living in your head rent‑free. | Maya 13, you 8. She's living in your head rent‑free. | F20 |
| **Empty states** |||||
| 59 | No games | No games yet. Spotless record. Suspicious as hell. | No games yet. Spotless record. Suspicious. | — |
| 60 | No rivals | No rivals yet. Play someone twice and it gets personal. | (same, already clean) | — |
| 61 | No achievements | Nothing earned. Go knock something. | (same, already clean) | — |
| 62 | No rounds yet (live) | No rounds yet. Deal, for fuck's sake. | No rounds yet. Deal already. | — |
| **Errors** |||||
| 63 | Local Network denied | Kedro's blind as shit right now. Let it look around in Settings, or scan the code. | Kedro can't see a thing right now. Let it look around in Settings, or scan the code. | — |
| 64 | Sign in failed | Apple said no. Try again, or play as a guest and sort that shit out later. | Apple said no. Try again, or play as a guest and sort it out later. | — |
| 65 | Claim code dead | That code's dead or already claimed. Nice try. | (same, already clean) | — |
| 66 | Two versions of a round | Two phones saved Round 4 differently. Pick the real one, then argue. | (same, already clean) | §11 |
| 67 | Game already final | This game's locked. History's permanent. Cope. | This game's locked. History's permanent. | — |
| **Offline** |||||
| 68 | Table only | No signal. Doesn't matter. All 5 phones are keeping score together. | (same, already clean) | F6 |
| 69 | This phone only | Just you out here. Your changes are safe till the others are back in range. | (same, already clean) | §11 |
| 70 | Back online | Back online. 4 offline changes synced. Nothing lost, unlike Leo. | (same, already clean) | §11 |
| 71 | Live Activity stale | Last updated 9:42. Open Kedro to catch up. | (same, plain by rule 10) | F19 |
| 72 | App Clip offline | The App Clip needs internet and this place has no damn signal. Someone at the table will score you. | The App Clip needs internet and this place has no signal. Someone at the table will score you. | — |

*Review gate:* every new string passes the same check before it ships. Is the target the play, not the person? Is it free of slurs and of words that read as gendered or identity insults (an early draft of #58 failed this test and was rewritten)? Does it fit in 60 characters on system surfaces? Does it have a hand‑written Clean line?

Achievement names and descriptions are part of the deck too (§13.5): 26 more strings, each with a Clean version.

---

## 3. Visual system: "After Hours"

**Mood:** a members' club at a night race meeting. Onyx lacquer, bone card stock, one red silk, and a satin brass rail. It's quiet and expensive, and the voice is the only loud thing in it.

### 3.1 Palette

The brand already owns two colors: the existing `BrandBackground` asset (`#0A0A0E`) and the red of the script wordmark. v2 builds around them.

| Token | Light | Dark | Use | Contrast note |
|---|---|---|---|---|
| `onyx` / `bg` (dark) | — | `#0A0A0E` | Dark background (the existing `BrandBackground`) | — |
| `bone` / `bg` (light) | `#F2EEE6` | — | Light background | — |
| `surface` | `#FBF9F5` (Paper) | `#17171B` (Graphite) | Cards, rows, all numbers | — |
| `sheet` | `#F7F4EE` | `#1E1E23` | Sheets | — |
| `ink` | `#111114` | `#EEE9DF` | Primary text, solid chips | ≈16:1 on background in both |
| `ink2` | `#5C5A57` | `#A19D96` | Secondary text, deltas | 6.6:1 on surface in both |
| `ink3` (Pewter) | `#8E8E93` | `#6E6C69` | Hairlines, inactive posts, never text under 17 pt | decorative |
| `kedroRed` | `#C8102E` | `#E0243B` fill / `#FF5A6A` text | The brand action (Sit down, Deal, Finish game, Run it back), the You marker, the wordmark | white on `#C8102E` 5.9:1; white on `#E0243B` 4.7:1 |
| `brass` (Satin Brass) | `#9C7A3C` | `#C9A86A` | Leader shoe, G1 plates, the finish rule. Graphics and ≥ 20 pt only. | 3.8:1 on Paper / 7.9:1 on Graphite |
| `line` | `rgba(17,17,20,.10)` | `rgba(238,233,223,.10)` | Hairlines | — |

**Red never means bad, and green doesn't exist.** Lower is better in Cambio, and red is the brand. Deltas are Pewter signed numbers. Knock outcomes are encoded by **form**: solid fill (*Landed*), outline (*Dead heat*), 45° hatch (*Busted*), each with a glyph and a word. Increase Contrast swaps `ink2` to `ink` and thickens outlines to 1.5 pt.

**The Colours register** (avatar silks only, never UI semantics): Onyx `#111114`, Bone `#EEE9DF`, Kedro Red `#C8102E`, Racing Green `#14342B`, Navy `#1C2740`, Camel `#C2A27A`, Pewter `#8E8E93`, Plum `#3E2A40`, Tan `#9A6B45`, Cream `#EAE0CB`.

### 3.2 Type

The system families only, so everything scales with Dynamic Type and nothing is bundled. In the HTML mockups `ui-serif` resolves to New York on Apple devices (Iowan or Georgia elsewhere), which is inline‑safe with no web fonts.

| Role | Face | Size / leading (default) | SwiftUI |
|---|---|---|---|
| Hero numeral (finish) | SF Pro Display Ultralight, monospaced digits | 96 / 96 | `.system(size: 96, weight: .ultraLight).monospacedDigit()` with `@ScaledMetric` |
| Display (winner, table names) | **New York** Medium | 40 / 44 | `.largeTitle.fontDesign(.serif)` scaled ×1.15 |
| Large title | New York Medium | 34 / 40 | `.largeTitle.fontDesign(.serif).weight(.medium)` |
| Title | New York Medium | 22 / 28 | `.title2.fontDesign(.serif)` |
| **The voice** | New York *Italic* | 19 / 25 | `.title3.fontDesign(.serif).italic()` |
| Headline | SF Pro Semibold | 17 / 22 | `.headline` |
| Body | SF Pro Regular | 17 / 22 | `.body` |
| Score total | SF Pro Semibold **Condensed**, monospaced digits | 30 / 32 | `.title.weight(.semibold).fontWidth(.condensed).monospacedDigit()` |
| Delta | SF Pro Medium, monospaced digits, true minus (U+2212) | 15 / 20 | `.subheadline.monospacedDigit()` |
| Label | SF Pro Semibold, uppercase, +12% tracking | 11 / 13 | `.caption2.weight(.semibold).textCase(.uppercase).tracking(1.3)` |
| Table word | SF Pro **Expanded** Semibold, uppercase | 13 / 16 | `.footnote.fontWidth(.expanded)` |
| Claim code | SF Mono Medium | 28 / 32 | `.title.monospaced()` |

The rule is simple: **serif speaks, sans counts.** Anything in New York is commentary, a name or a heading. Anything that's a number is SF Pro with monospaced digits.

### 3.3 The horse, refined

| Motif | What it is | Where |
|---|---|---|
| **Heritage wordmark** | The existing red script *Kedro*, flattened to a single `kedroRed` with no grey drop shadow, and the galloping horse redrawn as a single‑weight engraved line in Pewter. | Splash, App Clip card, share card. (In the HTML it's approximated with New York Bold Italic.) |
| **The Crest** | A modernist horse‑head profile in a fine roundel. One stroke weight, no eye shine, no smile, always in profile facing forward (left). | App icon (bone crest on onyx, satin brass ring), first launch, empty‑state watermark at 6% opacity, the finish header. |
| **Colours** (avatars) | Racing silks cut to a disc: 8 patterns (hoops, quarters, chevrons, sash, stripes, diamonds, cross‑belts, halved) × the 10‑color register. You "register your colours" at onboarding. Within one table no two seats share a pattern+color pair, and Kedro reassigns a guest's if needed. **Guests ride unregistered**: a hairline disc with a New York initial. It fills with colours on claim. | Everywhere a person appears. VoiceOver: *"Noah, red and bone hoops."* |
| **The Shoe** | A thin satin‑brass horseshoe with 5 nail holes. | The **first five** meter (one nail per completed game, *"getting shod"*), the leader mark beside the top total, the Island's minimal view. |
| **Rail & winning post** | Round progress is a rail of posts. The last post is the striped **winning post**, and posts added by an extension appear after a hairline break. | Live header, Live Activity, table display. |
| **Saddle cloth** | Rank numbers sit on small squared cloths in New York. First place is inverted (onyx on light, bone on dark). | Standings, board, finish. |
| **Photo‑finish line** | A vertical hairline. | Ties (it runs through the tied rows), the finish reveal, the self‑report flip. |

**Never:** cartoon horses, horse faces, rosette ribbons in toy colors, emoji, mascots, horse puns in UI labels.

### 3.4 Iconography

SF Symbols at **Light/Regular** weight in monochrome hierarchical rendering. There are no multicolor symbols and no emoji. Card suits (♠ ♥) appear only as data inside card chips, and the Joker chip says *JKR*. The custom symbols are exported as SF Symbol templates, so they get weights and Dynamic Type: `kedro.crest`, `kedro.shoe`, `kedro.table` (a ring of seats), `kedro.knock` (a knuckle striking a line), `kedro.peers` (three linked dots, for offline peer sync), and `kedro.post` (the winning post).

Outcome glyphs: **↓** Landed, **=** Dead heat, **×** Busted. Each always comes with its word.

### 3.5 Motion

Measured, never bouncy. Springs are `.smooth(duration: 0.3)` with zero bounce.

| Moment | Motion | Haptic | Reduce Motion |
|---|---|---|---|
| Totals change | `.contentTransition(.numericText(value:))` | none | crossfade |
| Standings re‑sort | `.animation(.smooth, value: order)` | none on any phone | crossfade |
| Knock set (hold) | Ring fill around the face for 0.5 s, then the dock morphs to *Enter hands* | `.selection` on **your** phone only | ring fill stays (a progress indicator, not decoration) |
| Self‑report reveal | All sealed chips **flip together** at the shared reveal time (`rotation3DEffect`, 0.4 s, staggered 40 ms) | `.impact(.soft)` once | values fade in together |
| Finish | **Photo‑finish wipe**: a 1 pt hairline sweeps left to right over 0.8 s and reveals the winner's name. Then the brass shoe draws on (`trim`), and the hero numeral counts up. | three soft taps 120 ms apart | name and number fade in; one tap |
| Table card arrival | Rises from the bottom; matched geometry into the lobby row | `.impact(.light)` on the host | fade |

---

## 4. The live game (F5, F6)

**Header (glass controls over a solid background):** minimize, the table name in New York with the table word in small expanded caps, **Round 6 of 10**, the **rail** (10 posts, 5 done, the current one outlined, a striped winning post), the **sync pill**, **?** (Rules and calculator) and **⋯**.

**Last‑round card** (always the first card, from table‑first): the round label, the **outcome chip**, the **voice line** in New York italic (*"Noah knocked on 3 and fucking nailed it."*), a **plain data line** (*"Lowest other hand: Priya's 4. Hand ignored, flat −10."*) and **Why?**, which opens the knock calculator prefilled with this round's hands.

**Standings** on solid surfaces: a saddle‑cloth rank, Colours, name, a plain subtitle (*Leads by 1*, *Knocked R5*), a **neutral delta** (*−10*, *+6*), and the **total** in condensed SF Pro. The leader's total has the brass shoe. Tied ranks share a cloth (=2) and get the photo‑finish hairline. **You** have a 2 pt `kedroRed` bar on the leading edge plus the word *You*. Only the knocker's row carries the outcome chip.

**The dock (glass, controls only):** *Who knocked? Hold a face.* The faces are 48 pt and hold‑to‑set (§7.1). After a knock it becomes **Enter hands** (scorekeeper) or **Report your hand** (self‑report, a sealed sheet). On the last planned round its caption is *Final round*.

**History** (sheet, F9) is **one scrolling page**: the score grid (rounds × players, with the knocker's cell marked by the outcome glyph and edited rounds dotted), then the **Changes** log with downstream effects. There are no segments, so a correction is never hidden.

**Screen awake** while the cover is visible: `UIApplication.shared.isIdleTimerDisabled`, the one sanctioned UIKit property (no SwiftUI equivalent), toggled by `scenePhase` and cover visibility, with a comment as `apps/ios/AGENTS.md` requires.

**Landscape (F21):** rotating the phone in the live game shows the **table display**: huge condensed totals in seat order, the rail, and the last‑round line in the house voice, for a phone propped in the middle of the table. It's a SwiftUI layout chosen by size class and orientation, and it isn't a separate mode.

**Dark live game (F6)** is the default after sunset if the system is in Automatic. Onyx is the brand background, so the dark game is the hero image of the identity.

---

## 5. Joining

### 5.1 Mechanism and permissions

| Layer | Framework | When permission is asked |
|---|---|---|
| Discovery + transport | **Network framework** (iOS 26 `NetworkListener` / `NetworkBrowser`, Bonjour `_kedro-table._tcp`, peer‑to‑peer included) in the **foreground**. The TXT record carries the table ID, host, seat count, round state and the table word. | **Local Network**: at the first *Join a table*, *Start a table* or *Sit down*, after a one‑line primer (deck #6). |
| At *this* table | **Nearby Interaction** (UWB). Tokens are exchanged over the peer connection. Within about 3 m is **At your table**, and anything farther is **Other tables nearby**. Without UWB, the list is ordered by played‑with overlap, and the **table word** (a generated racehorse name, *Dubious Intent*) disambiguates by voice. | **Nearby Interaction**: the first time two tables are visible together, or from the lobby's *Tell tables apart* row. |
| Online | Supabase Realtime + APNs. The backend is another peer. | Notifications: on the first finish (F11). |
| Fallback | QR universal link with a **30 s rotating token**, plus the spoken table word. | — |
| **Opt‑in only:** nearby‑table alert | Core Bluetooth service‑UUID advertising from foreground seated phones, and background scanning on opted‑in phones. Best effort, capped at 3 per day. **Never** used for game state. | **Bluetooth**: only when the user turns on *Tell me when my people start a table nearby*, offered in context on the **second** finished game (deck #7). |

Without the opt‑in there are still two ways to hear about a table without having Kedro open: the **Control Center / Action button "Start a table"** (for the host) and, online, the **"Maya saved you a seat"** push when a host adds you from Played‑with (deck #47).

**Trust model:** proximity is the credential. Played‑with people **sit down instantly**, and the host's arrival toast offers **Remove** for 5 s (deck #10). Strangers get **Ask to sit**, and any seated phone can **Let in**.

### 5.2 First launch (F1)

No permission prompts and no carousel. The crest, the wordmark, *"Cambio, scored properly."*, the voice subhead, and three paths:
- **Join a table** (`kedroRed`, primary): Local Network primer → Radar.
- **Play as a guest**: a first name → colours suggested → Radar. The guest identity and a **claim token** live on this device, so signing in later claims everything with no code.
- **Sign in with Apple**: shown dimmed with "Soon" while the developer account is pending (PRD 3.1). The debug test‑user sign‑in exists only under `#if DEBUG`.
- Footer: *Learn Cambio in 4 min* · *Got a claim code?* · *Mature: frequent profanity. Clean is one tap away.*

Then **Voice** (F2): Unfiltered vs Clean with live sample lines, and *Swear on my Lock Screen*. Then **Register your colours** (pattern and two colors, pre‑picked to stand apart from your frequent tablemates).

### 5.3 Flows

**A · Five returning players (F3 → F4):** Maya taps **Start a table**, either in the app or from the Control Center control (1). Noah, Leo and Priya open Kedro. A **Table card** rises: *Maya's table · DUBIOUS INTENT · at your table · 0.6 m*, with seated faces and the **stakes strip** (*"Your 5th game. Win or lose, you're on the damn board after this."*). **Sit down** (1 each). Maya adds Sam as a guest (§10). **Deal** (1). Every phone flips into the live game and starts its Live Activity. *6 taps across 5 phones, about 10 s.*

**B · Mid‑game:** *Your seat at Maya's table · Round 5 of 10 · You're 3rd* → **Take your seat**. A guest seat can be taken over from the App Clip with **That's me** (logged). A new person gets **Watch** (read‑only) and is queued for the rematch (deck #12), because a mid‑game entry score would be a house rule. A full table (8) shows Watch (deck #13). If the host's phone dies in the lobby, host duties pass to the earliest‑seated phone. After Deal there is no host.

**C · Rematch:** **Run it back** on the finish (deck #37). The lobby is prefilled with the same seats, rounds and mode, the **starting dealer rotates one seat clockwise**, and Watchers are seated. Other phones get a Table card: **I'm in** (1 each).

---

## 6. The lobby (F4, F22)

A single grouped `List`, no wizard:

- **Table:** name (editable) and the table word with *Say it to join* (it can be regenerated).
- **Seats · 5 of 8**: reorderable rows (`.onMove`, drag handle) in clockwise order. Each row has Colours, name, a role line (*Host*, *Scorekeeper*, *Guest · Noah reports for Sam*, *Played 21 together*) and a visible **⋯** menu: **Make scorekeeper · Assign reporter (guests) · Move up/down · Remove**. The same actions are trailing swipe actions and `accessibilityActions`. A seat saved from Played‑with but not yet linked to a phone shows *Seat saved · waiting for phone*.
- **Add:** **Played with** (people within range pre‑checked), **Guest** (typing "Sam" suggests *Sam · guest · 1 game with you*, so the identity is reused and one claim later brings everything), **Show join code**.
- **Game:** Rounds (**5 · 8 · 10 · Custom**; the default is last time's, or 8). Scoring (**Scorekeeper | Everyone reports**; the recommendation follows whether every seat is linked). **House voice** (deck §2.3).
- **Stakes** (from rivalry): one or two lines, such as *Priya's 5th game* and *Maya leads Noah 13–7* (deck #9).
- **Deal** (`kedroRed`), disabled below 3 seats with *Cambio needs at least 3.*

**AX5 (F22):** rows switch to a stacked layout via `dynamicTypeSize.isAccessibilitySize`. Colours and name go on one line, the role underneath, then a full‑width **Seat options** button. Settings rows wrap their labels above the controls. Deal stays pinned in a `.safeAreaInset`.

---

## 7. Recording a round

### 7.1 Marking the knock (optional, silent, undoable)

- **In the dock:** **hold a face for 0.5 s**. A ring fills, then it's set. A short tap shows the hint *Hold to set the knocker*, so nothing gets set by accident.
- **Your phone:** a glass toast, *"You set Maya as the knocker. Others updated quietly. Undo"*, with a 5 s countdown ring. Undo is logged.
- **Every other phone:** the dock and Live Activity update **silently** (no `AlertConfiguration`, no haptic, no sound). The Live Activity state line becomes *"Maya knocked. Last turns, don't fuck it up."* (deck #15).
- **Lock Screen:** your own Live Activity has **I knocked**, which only ever sets you. The first tap turns it into *Tap again: you knocked* for 4 s, and the second tap commits. If the phone is offline, the intent stores the event and it goes out to peers when Kedro next runs. The entry sheet always confirms the knocker anyway.
- **Never required:** if nobody marks it, entry starts with *Who knocked?* There is no "no knock" option anywhere (PRD 2.5).

### 7.2 Scorekeeper (F7)

A large‑detent sheet. The header is *Round 6 · Maya knocked · Change*. Rows start with the **knocker**, then go clockwise. Each row has the hand (live) and the **score preview** at the right.

**Keypad:** 1–9, **±**, 0, ⌫, **Next**, with 64 pt keys. **Auto‑advance** happens after two digits, after **0**, or after **−1/−2**. A single digit 1–9 needs **Next**. The current row's caption says *Auto‑advances after two digits*. After the last row, the button becomes **Save round**.

**Rule line** (plain, rule 2): *"Priya's on 2 too. Unless Sam goes lower, it's a dead heat and Maya keeps her 2."*

**Count cards** toggles a chip strip: **A 2 3 4 5 6 7 8 9 10 J Q K♠ K♥ JKR**. Tapping chips sums the hand, so K♥ is −1 and JKR is 0. It's on by default for players with fewer than 3 games.

**Validation:** −2 to 99. Above 52 it asks, without blocking (deck #26).

**After Save:** a 5 s **Undo** banner on the scorekeeper's phone (deck #27). Other phones re‑sort silently. The new last‑round card arrives with its voice line.

### 7.3 Self‑report (F8): sealed, then flipped together

1. After the knocker is set, each linked phone's dock and Live Activity show **Report your hand**.
2. The sheet has a keypad, Count cards, and a **personal, non‑revealing rule line**: *"If Leo had more than −1, his knock's busted. You'll all see at once."*
3. **Lock in −1.** The status row shows each seat as **In** (with a lock) or **Waiting**, never the value (deck #24). Guests have an **assigned reporter**, set in the lobby or defaulting to the host (*Noah reports for Ava*). Anyone can report for a linked player after 20 s, and it's logged.
4. When the last hand arrives, every phone **flips together** at the shared reveal time, then scores apply and standings re‑sort.
5. **Nudge:** the **only** self‑report prompt is a Live Activity **`AlertConfiguration`** update (deck #48). It goes only to phones still missing a hand, only after 20 s, once per round, and with sound off when the phone's ringer is off. There's no separate push notification.
6. Knocker conflict (two phones set different knockers concurrently): *"Two phones say different knockers. Who actually knocked?"* The round won't complete until someone picks.

### 7.4 What the app computes

Hands plus the knocker → PRD 2.6 → round scores and one outcome:

| Outcome | Chip | Plain data line (rule 2) | Voice line (examples) |
|---|---|---|---|
| Strictly lowest | **↓ Landed −10** (solid) | Noah knocked with 3, lowest at the table. Hand ignored, flat −10. | #16, #17 |
| Tied lowest | **= Dead heat** (outline) | Maya knocked with 2 and tied Priya's 2. Maya scores her hand: 2. | #18 |
| Beaten | **× Busted +10** (hatched) | Priya knocked with 1, Sam had −1. Priya scores 1 + 10 = 11. | #19, #20 |

The plain line is the VoiceOver label of the chip, and it's what **Why?** opens in the calculator.

---

## 8. Deltas and outcomes

- **Delta** is a signed number with a true minus, in `ink2`, on every row, every round. It never has color or a chip.
- **Outcome** is a chip with a glyph and a word, only on the knocker's row and in the last‑round card. It never sits next to a delta of the same shape. On the knocker's row the chip goes under the name and the delta stays on the right.
- Every delta and chip is tappable and opens the plain rule sentence for that round.

---

## 9. Finishing, ending early, abandoning

### 9.1 The Finish gate (F10)

When the last planned round is saved, every phone shows the gate over the dimmed standings: the last round's chip and voice line, then *"That was round 10."* / *"Lock it in, or fix your shit first."* (deck #31).
- **Finish game** (`kedroRed`): writes `Finished` (HLC), the seal. Any phone can do it.
- **Fix a round first** opens History. **Add rounds** offers +1, +2 or +5 and is logged.
- **Idle fallback:** with no new events for **15 minutes**, the game finishes itself at *last event HLC + 15 min*. Every phone, and the server, computes that same seal from the log. An edit stamped before the seal (from a phone that was offline) is applied. One stamped after it is rejected and logged *Rejected: game already final*.

### 9.2 The finish (F11)

The photo‑finish wipe reveals **"Noah fucking wins."** (deck #32), then the hero numeral **38**, the voice subline (#33), the standings with **gap to winner**, the last‑place line (#36), and **highlights** derived from rounds: Clean knocks (Noah 2, Maya 1, Priya 1), Best round (−10 ×4), Biggest comeback (Noah, 4th → 1st). Public moments shown to the whole table: **Priya's debut** (#43) and **Noah's Dark Horse**. A personal strip (different on each phone): rating change, head‑to‑head change, achievements, next closest achievement. **Run it back** (#37) · **Share** (an `ImageRenderer` card with the heritage wordmark) · **Done**. The **notification primer** appears here the first time (#53). Each unclaimed guest gets a row → Hand‑off (F12).

### 9.3 End early and Abandon (⋯ menu)

- **End early** → confirmation (#38) → the same Finish gate, reading *Ending after Round 4*. It counts fully. Logged.
- **Abandon** → destructive confirmation (#39). The game is marked Abandoned at once, and **any player can Restore for 15 minutes** (#40). That protects a game from a sore loser. After 15 minutes the game seals as Abandoned: kept in history and excluded from all stats, boards and achievements. Both actions are logged.

---

## 10. Guests and claiming (F12, F13)

- **Host‑added guest:** + Guest → name → **Add**, with the name‑matched reuse suggestion. Unregistered colours (a hairline disc with an initial). The scorekeeper or the assigned reporter enters their hand.
- **Guest with a phone, no app: the App Clip (F13).** The camera scans the join QR (rotating token) → *"You're at Maya's table"* → **That's me** on their seat. They see live standings and report their own sealed hand. The App Clip stores the guest's **claim token** in the shared app‑group container, so installing the full app and signing in claims the history automatically. App Clips are online‑only here (deck #72). Offline guests are scored by the table.
- **Hand‑off (F12):** at the finish, *Sam played as a guest* → a QR, the code `HX7‑4QP` in SF Mono, **AirDrop** and **Message** (`ShareLink`), and a preview that sells the claim: *1 game · 4th · Red Royalty earned · 4 more games to the board*, with the voice line *"Give Sam their history. A 90, and a −1 they'll never shut up about."*
- **Claiming:** link → App Clip or app → Sign in with Apple → *Claim Sam's history?* → **Claim**. Everything is recomputed from rounds, and colours get registered. An already‑claimed code says *"That code's dead or already claimed. Nice try."*
- **Legacy web identities** (PRD 9) use the same flow and show as *noahj · web* with unregistered colours.

---

## 11. Offline and sync

Each game is an append‑only event log (`SeatAdded`, `KnockerSet`, `HandReported`, `RoundSaved`, `RoundUndone`, `RoundEdited`, `RoundsExtended`, `EndedEarly`, `Abandoned`, `Restored`, `Finished`). Events have a UUID, HLC, author and device, and are stored in SwiftData, gossiped to peers and uploaded when online. State is a deterministic fold, so there's **no loss** (append‑only), **no duplication** (idempotent by UUID), and conflicts resolve by **(HLC, device ID)** with both writes kept in Changes. Two phones that saved "Round 4" while apart merge if the rounds are identical. If they differ, the later one applies and the other is kept as **Not applied**, with **Use this version** (deck #66).

| State | Pill | Line |
|---|---|---|
| Live | solid dot · *Live* | — |
| Table only | `kedro.peers` · *Offline · 5 phones in sync* | deck #68 |
| This phone only | hollow dot · *Offline · 2 changes waiting* | deck #69 |
| Syncing → synced | spinner → check | deck #70 |

**Locked phones offline:** their Live Activity goes stale (deck #71). That's the expected state, not a failure, and the design doesn't try to beat it with background radios.

---

## 12. System surfaces

### 12.1 Live Activity and Dynamic Island (F19, F20)

It starts when you take a seat (foreground), or via push‑to‑start when online. One per game.
- **Lock Screen:** the crest, table name, *Round 6 of 10* rail, sync state, the top 5 (or top 4 + you) with totals and neutral deltas, the **state line** in the house voice (or Clean if *Swear on my Lock Screen* is off), and buttons: **I knocked** (two‑step, yours only), **Report hand** (self‑report; opens the app to the sheet) and **Open**.
- **Island:** compact leading is your saddle‑cloth rank; compact trailing is *R6/10*, or the knocker's colours after a knock. Minimal is the shoe with your rank. Expanded shows the top 4, the last‑round chip and plain line, and the buttons.
- **Updates:** online via ActivityKit push on a **per‑game broadcast channel**, silently (no alert) for knocks and rounds. **`AlertConfiguration` is used only for the self‑report nudge** (§7.3), sent per activity token to missing reporters. Offline: updates happen only while Kedro is running in the foreground on that phone. Otherwise the activity dims at `staleDate` and says so.
- **StandBy:** the system shows the **standard Lock Screen presentation** scaled up. Kedro adds nothing special for it. The purpose‑built big board is the in‑app table display (F21).
- **End:** the final state shows the winner and your place in the house voice, then dismisses after 1 hour.

### 12.2 Widgets and Controls (F20)

| Widget | Family | Content |
|---|---|---|
| **Rival** | systemMedium | You vs nemesis or a pinned rival: the finished‑ahead record, the last 5 meetings as ahead/behind marks, and a voice line (deck #58). |
| **Board** | systemSmall, accessoryCircular | Before 5 games, the **shoe** (*3 of 5*). After that, rank, rating and the last game's change. |
| **Close race** | systemSmall | The nearest player within 15 rating points (deck #44). |
| **Form** | systemMedium | Streak, win rate, knock success, and a sparkline of final scores. |
| **Start a table** | `ControlWidget` (Control Center, Lock Screen, Action button) | Opens straight to a new lobby. |

Widgets reload when a game finishes (`WidgetCenter.reloadTimelines`) and on rank pushes. They never show live game state, because that's the Live Activity's job.

### 12.3 Notifications

| Notification | Trigger | Level | Cap |
|---|---|---|---|
| Seat saved (#47) | A host added you from Played‑with (online) | Time‑sensitive | per game |
| Nearby table (#46) | **Opt‑in only**, background BLE | Active | 3/day |
| Self‑report | **Not a notification.** A Live Activity alert (#48) | — | 1/round |
| Recap (#49) | The game finished while Kedro wasn't in the foreground | Passive | per game |
| Ranked (#50) | 5th completed game | Active | once |
| Knocked off a rank (#51) | Someone passes you on Played‑with | Passive | 1/day, batched |
| Claimed (#52) | A guest you played with claims | Passive | per claim |

**Not sent:** rounds, edits, mid‑game achievements, streak‑at‑risk guilt, remote games, marketing. Copy follows *Swear on my Lock Screen*.

---

## 13. Stats, rivals, board, achievements

All derived from recorded rounds. Abandoned games are excluded, and shared wins count.

### 13.1 Profile (F14)

Colours (large), name in New York, **Rating 1,198 · +14 last game**, *Global #212 · Played‑with #3*, and **How rating works**. Form tiles: streak, win rate, knock success. **Every PRD 5.1 stat** is listed with an info popover holding the PRD definition. Knock outcomes are a three‑part bar by form (solid / outline / hatched) with counts. **Nemesis** is a card with the voice line (#56). Games are listed with **rating change on each** (*+14*, *−6*), and Abandoned games are marked and show no change. Visitors see the same page, with *Head‑to‑head with you* pinned.

Sample (Noah): 21 games · 8 wins · 38% · best 22 · worst 97 · avg/game 58.4 · avg/round 6.5 · streak 1 · longest 3 · knock rate 20% (38 of 189 rounds) · knock success 53% (20 landed / 6 dead heat / 12 busted) · nemesis Maya (13).

### 13.2 Head‑to‑head (F15)

Facing colours, the **finished‑ahead record 8–13** big with *Maya leads*, and the voice header (#54). **Gap to level** (#55). Then games together 21, finished ahead 8/13, wins in shared games 6/9, knock outcomes facing each other (Noah 16/4/9, Maya 18/3/7), average final score in shared games (57.9 / 52.3), the last 5 meetings, and the biggest margin. **Play again with Maya** opens a prefilled lobby.

### 13.3 Leaderboard recommendation (F16)

**One official rank, from one skill rating. Records live elsewhere.**
- **Kedro Rating:** OpenSkill (Weng‑Lin, Plackett‑Luce), which handles 3–8 players and shared places natively. It's replayed from every completed game, so it's derived. Displayed as the conservative μ − 3σ on a ~1,000 base. **Why not win rate:** a 3‑player win is about twice as likely as an 8‑player win, and win rate ignores who you beat. **Why one rank:** "#3 at our table" has to mean the same thing on every phone (one source of truth).
- **How rating works** sheet: deck #45, plus *"New players start low on purpose. Your number rises as Kedro gets surer of you, even if your skill stays the same, so playing more always helps."* Every game in your history shows its change.
- **Debut at 5:** the rating is computed from game 1, but hidden until the 5th completed game. It's then revealed on the finish screen to the whole table (#43), and the ranked notification follows (#50).
- **Scopes:** **Played with** (the default) and **Global**. Your row is pinned at the bottom.
- **Records** (separate segment): Win rate (min 10 games), Knock success (min 15 knocks), Avg per round, Longest streak, Most games. Each has its own ordinal (*1st in knock success*), it's read‑only, and there are no official rank badges there.
- **Close races:** anyone within 15 rating points (#44).
- **Eligibility:** 5 completed non‑abandoned games. Below that you're in the **Community** section: colours, name, and the **shoe** (*3 of 5*), with no number. Global header: *1,240 ranked · 3,118 in the community*. Unclaimed guests aren't listed.
- Ties share a cloth (=12).

### 13.4 Play‑more incentives

| Where | Incentive |
|---|---|
| **The shoe** | 5 nails, one per completed game, on the Table card stakes strip, lobby, profile, board, widget and finish (*"nail 4 driven"*). The 5th is a public debut. |
| **Stakes strip** | On the Table card and lobby: *"Your 5th game..."*, *"Maya leads Noah 13–7..."* |
| **Since you last looked** | On the Radar: rank moves, streaks that died, rivals who played without you (#14). It gives a reason to open the app that isn't a notification. |
| **Finish** | Rating change, head‑to‑head change, gap to level, the next closest achievement, and **Run it back** as the primary action. |
| **Close races and rank pushes** | Someone 7 points behind you is a reason to play tonight (#44, #51). |
| **Achievements** | Funny enough to share, with visible progress on locked ones. |
| **Learn → first game** | *Did the Reading*, then a lobby hint for learner seats. |
| **Guests** | A claim that sells their own record (#52, F12) and *Bad Influence* for the person who brought them. |

No guilt pushes and no "we miss you".

### 13.5 Achievement catalog

Tiers borrow **race grades**: **G3** (most players get these), **G2**, **G1** (rare, struck in brass). Plates are engraved rectangles, not medals or rosettes. Descriptions follow the voice rules, and each has a Clean version. Four are **secret**. All are derived from rounds and seats, exclude abandoned games, and are recomputed on edits before the seal and on claims.

| # | Name (U / C) | Grade | Rule | Description (U / C) |
|---|---|---|---|---|
| 1 | Out of the Gate | G3 | Complete a game | Finished a whole game. Didn't cry. Probably. / *same* |
| 2 | Broke Your Maiden | G3 | First win (shared counts) | First win. Holy shit, screenshot it. / First win. Screenshot it. |
| 3 | Cold‑Blooded | G3 | A landed knock (−10) | Knocked, landed it, didn't blink. Psycho. / *same* |
| 4 | Fucked Around, Found Out / Found Out | G3 | A busted knock (+10) | Knocked and got beaten. +10 for the audacity. / *same* |
| 5 | Dead Heat | G2 | Knock into a tie | Technically not a loss. Technically. / *same* |
| 6 | Red Royalty | G3 | A negative hand in a round | Ended a round under zero. The red King works for you now. / *same* |
| 7 | On the Card | G2 | 5 completed games (ranked) | Five games, ranked. No more hiding in the community section, coward. / *same* |
| 8 | Photo Finish | G2 | Share a win | Split the win. Keep the trash talk. / *same* |
| 9 | Treble | G2 | 3 wins in a row | Three on the bounce. Insufferable. / *same* |
| 10 | Unbeaten Run | G1 | 5 wins in a row | Five straight. Someone check this asshole's sleeves. / Five straight. Someone check their sleeves. |
| 11 | Serial Knocker | G2 | 3 landed knocks in one game | Three clean knocks in one game. Unhinged. / *same* |
| 12 | Dark Horse | G2 | Win after being in the bottom half after Round 3 or later | Bottom half after Round 3, won anyway. Nobody saw that shit coming. / Nobody saw that coming. |
| 13 | Wire to Wire | G1 | Lead or co‑lead after every round of a 5+ round game, and win | Led every round and won. Absolute bully. / *same* |
| 14 | In the Red | G1 | Finish a game with a negative total | Finished a whole game under zero. Witchcraft. / *same* |
| 15 | Regular | G3 | 10 games | Ten games. It's a habit now. / *same* |
| 16 | Lifer | G2 | 50 games | Fifty games. Your liver and your record say hi. / Fifty games. Your record says hi. |
| 17 | Touch Grass | G1 | 100 games | A hundred games. Genuinely, go outside. / *same* |
| 18 | Full Stable | G2 | Play with 10 different people | Ten different people put up with you. Impressive. / *same* |
| 19 | Full Field | G2 | Complete an 8‑player game | Eight at one table. Chaos. You loved it. / *same* |
| 20 | Bad Influence | G1 | A guest you played with claims and then completes a game on their account (each guest counts once, max 1 a week) | Someone you dragged into this made an account. You did this. / *same* |
| 21 | Did the Reading | G3 | Finish Learn and the drill | Finished the lessons. Nerd. Respect. / *same* |
| 22 | Delusional / Bold Choice | G3 | Knock on 10+ and get busted | Knocked on double digits and got beaten. We love the confidence. / *same* |
| 23 | ?? Bottled It / Choked (secret) | G2 | Lead after the second‑to‑last round, then lose | Led into the final round and lost. Fucking bottled it. / Led into the final round and lost. Choked. |
| 24 | ?? Glue Factory (secret) | G2 | Last place 3 completed games running | Dead last three games running. They're warming up the van. / *same* |
| 25 | ?? Exorcism (secret) | G1 | Finish ahead of your nemesis in 3 straight shared games | Beat your nemesis three straight. Demons: gone. / *same* |
| 26 | ?? Nothing to See Here (secret) | G2 | Land a knock with exactly 0 | Knocked on zero and landed it. Smooth as hell. / Knocked on zero and landed it. Smooth. |

Presentation (F17): a grid of engraved plates. Earned plates are struck (onyx or bone, with brass for G1). Locked plates are debossed, with progress for cumulative rules (*Lifer 21/50*). Detail shows the rule in plain words, the date, the game (tap through), and the share of players who have it. All of it is public on profiles, in the viewer's voice.

---

## 14. Learning (F18)

- **Learn Cambio in 4 minutes:** five lessons (Your grid, Card values, Power cards, Sticking, The knock). Learn copy is warmer than game copy, because nobody gets roasted for learning: *"Red King is −1. Black King is 13. Yes, really."*
- **Knock calculator** (also behind every **Why?**): sliders for your hand and the lowest other hand. The outcome chip and plain line update live, with a voice line from the calculator deck: *"Knock on 3 and you're a genius. On 4 it's a coin toss with your mates. On 5, you're a cautionary tale."*
- **Score this round** drill on the **same Count cards chips** as real entry.
- **Rulebook:** the full PRD §2, searchable, reachable mid‑game from **?** at the medium detent with standings visible.
- **Learner hints:** a per‑seat lobby toggle. That phone shows a one‑line power‑card hint during the round, the Cards helper is on, and its bad outcomes use the `*.learner` voice keys.

---

## 15. Accessibility

- **Dynamic Type:** text styles everywhere. At AX sizes, standings rows stack (name, then total and delta), the lobby uses stacked rows with Seat options buttons (F22), the dock becomes a single **Who knocked?** button that opens a list, the keypad keeps 64 pt keys, and entry shows one player at a time (*Player 3 of 5*).
- **VoiceOver:** rows are single elements, with data before voice: *"Maya, first, 24, leads by 1. Last round plus 6."* The chip label is the plain line. Voice lines are a separate, skippable element after the data. **Announcements** (`AccessibilityNotification.Announcement`) fire only when `accessibilityVoiceOverEnabled` is true. **Rotors:** Players, **Knocks**, **Edited rounds**. The hold‑to‑set dock has an `accessibilityAction(named: "Set as knocker")` that works with no hold. Profanity is read as written; Clean changes what's written.
- **Reduce Motion:** §3.5. **Reduce Transparency:** glass becomes opaque `surface`. **Increase Contrast:** §3.1.
- **Color:** no meaning is carried by color. Outcomes use form + glyph + word. *You* uses a bar plus the word. Colours patterns stay distinct in grayscale (pattern, not hue).
- **Hit targets:** ≥ 44 pt, and 48 pt dock faces and 64 pt keys, because people use these while holding cards.

---

## 16. SwiftUI implementation map

| Area | APIs | UIKit? |
|---|---|---|
| Shell | `TabView` + `Tab`, `Tab(role: .search)`, `.tabViewBottomAccessory` (game strip), `.tabBarMinimizeBehavior(.onScrollDown)`, `NavigationStack` + `navigationDestination(for:)`, `.onOpenURL` | No |
| Live game | `.fullScreenCover` + `.navigationTransition(.zoom(sourceID:in:))`, `List`/`LazyVStack`, `.contentTransition(.numericText())`, `.animation(.smooth)`, `GlassEffectContainer` + `.glassEffect(.regular.interactive())` for the dock and toolbar only, `.onLongPressGesture(minimumDuration: 0.5)` with a `Gauge`‑style ring, `.sensoryFeedback(.selection, trigger:)` on the setter only | **Yes, one property:** `UIApplication.shared.isIdleTimerDisabled` (no SwiftUI equivalent), in an `IdleTimerController` with a comment |
| Lobby | `List` + `.onMove`, `.swipeActions`, `Menu`, `.accessibilityActions`, `Picker(.segmented)`, `Stepper`, `ShareLink`, Core Image QR, `ViewThatFits` / `dynamicTypeSize.isAccessibilitySize` | No |
| Entry | `Grid` keypad of `Button`s, an `@Observable EntryModel` (auto‑advance rules), Count cards chips, `TextField(.numbersAndPunctuation)` as the accessibility alternative | No |
| History + Changes | One `List` with sections, `Grid` for the score table, `.accessibilityRotor("Edited rounds")`, `.accessibilityRotor("Knocks")` | No |
| Finish | Same cover, `Canvas` hairline wipe, `Shape.trim` for the shoe, Core Haptics (3 soft taps), `ImageRenderer` + `ShareLink` | No |
| Voice | Two `.xcstrings` tables, an `@Observable VoiceSettings` in the environment, a deterministic `VariantPicker` | No |
| Proximity | Network framework `NetworkListener`/`NetworkBrowser` (P2P), `NISession`, Core Bluetooth **only behind the opt‑in** | No |
| Sync | SwiftData event log, a pure‑Swift `GameEngine` fold + HLC, tested with Swift Testing | No |
| Live Activity | ActivityKit, `ActivityConfiguration` + `DynamicIsland`, `LiveActivityIntent` (I knocked, two‑step state in the content state), channel push, per‑token `AlertConfiguration` for self‑report only, `staleDate`. **No** `supplementalActivityFamilies`. | No |
| Widgets / Control | WidgetKit `StaticConfiguration` / `AppIntentConfiguration`, `.containerBackground`, `ControlWidget` + `ControlWidgetButton` (OpenIntent) | No |
| App Clip | Shared SwiftUI live view + sealed hand sheet, app‑group container for the claim token, `.appStoreOverlay` | No |

Info.plist: `NSLocalNetworkUsageDescription`, `NSBonjourServices`, `NSNearbyInteractionUsageDescription`, `NSSupportsLiveActivities`, `NSBluetoothAlwaysUsageDescription` (requested only by the opt‑in), `UIBackgroundModes`: `remote-notification` plus `bluetooth-central` (used only when the opt‑in is on; we'll justify it in App Review notes, or cut it if review objects, and nothing else breaks).

**Risks, honestly:** the nearby alert is best effort and opt‑in, and cutting it removes no core flow. NI needs UWB, so the fallback is played‑with ordering plus the spoken table word. The App Clip is online‑only. The Lock Screen two‑step "I knocked" adds a tap. We accept that cost to stop pocket misfires.

---

## 17. Taps and time

**Scorekeeper, 5 players** (hands about 40% single‑digit, 50% two‑digit, 10% zero or negative):

| Step | Taps |
|---|---|
| Hold a face at the knock *(optional, during play)* | (1 hold) |
| Open **Enter hands** | 1 |
| Per player: two‑digit = 2 (auto), single digit = 1 + Next = 2, zero = 1, negative = ± + digit = 2 (auto) → about 1.9 | ≈ 10 |
| **Save round** | 1 |
| **Total after reveal** | **≈ 12 taps · ≈ 11–13 s** (+1 if the knocker wasn't held) |

**Self‑report**, per phone in parallel: Report your hand 1 + digits ≈ 1.6 + Lock in 1 = **≈ 3.6 taps**. The table waits for the slowest hand (about 5 s), and then the flip.

**Joining:** 5 returning players = **6 taps across 5 phones, about 10 s**. Rematch = 1 + 4 + Deal = **6**. Host‑added guest = **about 6 host taps**. App Clip guest = Show code (host 1) + camera + banner + Open + That's me ≈ **15 s, no install**. Claim at the finish ≈ **30–40 s**.

---

## 18. Sample game (canonical scoring, used in every frame)

Thursday table · *Dubious Intent* · Maya hosts, Noah keeps score · set up for **8 rounds**, extended to **10** by Maya after Round 4 · Round 2 corrected by Priya (Priya 6 → 5).

| R | Knocker | Hands (Noah, Maya, Leo, Priya, Sam) | Outcome | Round scores | Running totals (N, M, L, P, S) |
|---|---|---|---|---|---|
| 1 | Maya | 9, **3**, 12, 7, 15 | ↓ Landed | 9, −10, 12, 7, 15 | 9, −10, 12, 7, 15 |
| 2 | Leo | 6, 11, **5**, 5, 20 | = Dead heat (after edit) | 6, 11, 5, 5, 20 | 15, 1, 17, 12, 35 |
| 3 | Noah | **8**, 4, 14, 10, 9 | × Busted | 18, 4, 14, 10, 9 | 33, 5, 31, 22, 44 |
| 4 | Priya | 2, 13, 8, **1**, −1 | × Busted | 2, 13, 8, 11, −1 | 35, 18, 39, 33, 43 |
| 5 | Noah | **3**, 6, 9, 4, 11 | ↓ Landed | −10, 6, 9, 4, 11 | 25, 24, 48, 37, 54 |
| 6 | Maya | 5, **2**, 7, 2, 8 | = Dead heat | 5, 2, 7, 2, 8 | 30, 26, 55, 39, 62 |
| 7 | Leo | 4, 9, **6**, 12, 3 | × Busted | 4, 9, 16, 12, 3 | 34, 35, 71, 51, 65 |
| 8 | Noah | **1**, 10, 13, 6, 7 | ↓ Landed | −10, 10, 13, 6, 7 | 24, 45, 84, 57, 72 |
| 9 | Priya | 8, 5, 4, **0**, 16 | ↓ Landed | 8, 5, 4, −10, 16 | 32, 50, 88, 47, 88 |
| 10 | Maya | 6, **3**, 11, 9, 2 | × Busted | 6, 13, 11, 9, 2 | **38, 63, 99, 56, 90** |

Final: **Noah 38 (1st)**, Priya 56, Maya 63, Sam 90, Leo 99. Before the edit, Round 2 was Leo ↓ Landed (Priya had 6), with Leo's total at 2 after Round 2. The edit makes it 17 (and 24 → 39 after Round 4). After Round 3 Noah was 4th of 5 (bottom half), so **Dark Horse** is correct. Sam's −1 in Round 4 earns **Red Royalty**. Self‑report example (Friday table, F8): Leo knocks with 5, Maya 7, Noah −1 (K♥ + JKR), Ava 9. Noah's −1 busts Leo: 15.
