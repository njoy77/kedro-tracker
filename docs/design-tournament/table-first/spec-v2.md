# Kedro for iOS: "Table First"

### Design tournament entry · spec v2 · October 2026

> Companion file: [`mockups-v2.html`](./mockups-v2.html) has a visual-system board and 29 iPhone frames (393 × 852 pt). The live game is shown in light and dark, at 5 and 8 players, and Card mode is shown at standard and AX sizes.
> Requirements: `docs/kedro-ios-prd.md` (v3.0, including the new Section 8). The v1 files (`spec.md`, `mockups.html`) are unchanged. This document replaces them for round 2.

---

## Changes from v1

### The new direction, in one paragraph

The product owner found every round 1 entry too childish. v1 was restrained, but its warmth came from cute things: coat-colored horse-head avatars, a cartoon gallop, bright system red, and polite copy. v2 keeps the thesis and the interaction model, and replaces the visual identity and the voice. **Restraint is what makes something feel grown-up**, so Table First reads the new brief as permission to get quieter and sharper. The look moves to a **members'-club racecard**: bone paper and near-black, oxblood and brass, racing silks for identity, a New York serif for display, and a photo-finish print at the end. The voice moves to **friends roasting each other over drinks**. It is dry and current, and it swears where a swear lands. The rule that keeps Table First fast at the table also applies to the copy: **say the math first, then the joke.**

### Judge must-fixes and how v2 resolves them

| # | Judge | Must-fix | Resolution in v2 | Where |
|---|---|---|---|---|
| N1 | Native | Move discovery and sync to the iOS 26 Network framework peer-to-peer APIs, keep Multipeer as the fallback, state the offline Live Activity limit, design the stale state | Primary transport is now **NetworkListener / NetworkBrowser / NetworkConnection** (Bonjour `_kedro._tcp`, TLS-PSK from the table token, peer-to-peer enabled). MultipeerConnectivity is kept behind a flag as a fallback for when a P2P path can't be established within 5 s. **Stated plainly:** with no internet, a phone's Live Activity updates only while Kedro is in the foreground or briefly in the background. A locked phone at an offline table shows the last state, and once `staleDate` passes (last update + 3 min) it shows **"Last update 9:46 · Open Kedro to catch up"** with dimmed scores. With internet, every phone updates through a per-game ActivityKit **broadcast channel**, locked or not. | §5.1, §9.3, §11.1, frames 25–26 |
| N2 | Native | Mock Card mode in the Round sheet at standard and AX sizes, including how the palette fits a `.large` sheet with 8 players | Card mode is specified for 3–8 players. With 6–8 players the per-player list becomes a **2 × 4 seat grid**, and the palette is **15 card keys in a 5 × 3 grid** with an explicit **Next** key. At AX sizes the seat grid becomes a single-seat header with ‹ ›, and the palette reflows to 3 columns and scrolls, with the verdict line and Save pinned. | §7.3, frames 10–11 |
| N3 | Native | A between-games hook on Play (last game's rating change, nemesis delta, next goal) | Play now opens with **Since you last looked**: last game and its rating change, board movement, rivalry change, guest claims, and the closest plate. It is followed by **Tonight's stakes** ("Win tonight and you're back past Cleo"). These are computed when Play appears, so it is never empty, even when no table is nearby. | §4.2, frame 02 |
| N4 | Native | Differentiate achievement badges by category or tier, not the earner's coat color | Achievements are now **plates**. The **shape encodes the category** (roundel, shield, lozenge, pennant, octagon, hexagon, square) and the **metal encodes the tier** (iron, silver, brass). The glyph is engraved and monochrome, and the earner's colors are never used. | §3.6, §12.6, frame 22 |
| N5 | Native | Specify and mock the 6–8 player layout of the Table and the Lock Screen Live Activity, with the top-five truncation rule and where your own row goes | With 6–8 players the Table uses **compact rows** (54 pt, 28 pt score) and all players stay visible down to AX1. From AX2 up, the list scrolls and **your row pins to the bottom** when it is off-screen. The Live Activity shows **at most 5 rows: the top 5 if you're among them, otherwise the top 4, a "···" divider, then your row with your real rank.** | §6.2, §11.1, frames 08, 25 |
| T1 | Table | The Nearby row's Join should commit directly for auto-admitted players, with the sheet only for strangers or a mid-game seat match | The Nearby row's button is now **Sit In**, and it commits the join in one tap for anyone the host has played with or added. The confirmation sheet appears only for (a) a stranger, who waits for the host's **Let Them In**, or (b) a seat match mid-game ("Is this Sam?"). The tap counts in §15.2 are recounted: **6 taps for 5 returning players** is now literally true. | §5.3, §15.2, frame 03 |
| T2 | Table | Make hand entry deterministic and merge-proof, and flag a value far above the rest of the round | The two-digit auto-advance keypad is gone. The default entry is now a **Tally board**: 35 one-tap value keys from −2 to 32, so **one tap is one complete hand value**, and focus always advances. Merging two values into one is impossible. Values of 33 or more go through **33+**, a keypad with an explicit **Done**. **Typo guard:** at Save, any value of 25 or more that is at least double the next-highest hand, or any value of 45 or more, raises a non-blocking check: "Sam 29? Everyone else is 11 or under. Real or a fuck-up?" with **Keep 29** / **Fix Sam**. | §7.1–7.2, frames 09, 13 |
| T3 | Table | In self-report, show on every phone who set the knocker, with a short undo, instead of letting the first tap win silently | When the knocker is unresolved, the first tap becomes a **proposal** shown on every phone: "**Ana says Noah knocked** · Change", with a 5-second ring. Any phone can tap **Change**. If two different taps arrive within the window, the round waits: "Ana says Noah, Ben says Cleo. Sort it out." The next single answer settles it. Every step is logged. | §7.4, frame 12 |
| T4 | Table | Shorten the correction path with a tap or long-press on a History grid cell | **Tapping any History cell** opens the Edit sheet focused on that player's value in that round. Single-value edits put the "everyone sees this" notice in the Save footer instead of a separate dialog, so a fix is **4 taps from the Table** (down from 7–8). Edits that change the knocker or flip a knock outcome still go through a `confirmationDialog`. | §8.2, frames 14–15 |
| T5 | Table | A between-games hook on Play (rank movement, rivalry flip, guest claimed) | Same as N3. Every one of those events is a row type in Since you last looked. | §4.2 |
| T6 | Table | Fix the frame 11 caption/screen mismatch about games remaining | Sam's numbers are now consistent everywhere: 2 earlier guest games plus tonight, so **3 games, "Two more games and you're ranked"**, on the screen and in the caption. All v2 frames share one dataset (§16). | frame 18, §16 |
| P1 | Product | A between-games digest on Play | Same as N3. The closest unearned plate is one of the rows. | §4.2 |
| P2 | Product | More brand presence outside play: horse avatars at all legible sizes, a horse-mark meter for "3 of 5", horse-flavored empty states, with the Table kept austere | **Racing silks** replace coat avatars and are legible down to 28 pt. Guests wear unregistered plain silks until they claim and **register their colours**. **The Rail**, a racecourse rail with posts and a winning-post roundel, is the one progress component: round progress, "3 of 5 to rank", and plate progress. Empty states use the engraved **Mark** and racing copy ("No form yet."). The Table gets nothing new except silks. | §3.3–3.4, frames 02, 18–22 |
| P3 | Product | A "Score this round" practice drill on the real entry sheet and Card mode, and a rules-sheet knock calculator prefilled from a round | **Score a Round** is a drill that runs the real Round sheet (Tally board and Card mode) in practice mode, with a PRACTICE watermark and no logging. Every delta popover and last-round card has **Why?**, which opens the **Knock Calculator** in the Rules sheet, prefilled with that round's hands and knocker. | §10, frames 23–24 |
| P4 | Product | Fix the head-to-head header copy ("1 level") and show Records leaders inline on the leaderboard | The H2H header now reads **"Ana leads 12–5"**, with a gap line under it: "7 behind. Every time you finish ahead of her, that's one back." The four **Records** leaders appear inline as a 2 × 2 grid under your pinned row, and each one pushes to its full board. | §12.2–12.3, frames 20–21 |
| P5 | Product | Consider an App Clip or web view so a guest with a phone but no app can follow and self-report | Added a **Kedro App Clip**. The host's Table menu shows a **QR with a token that rotates every 60 s**. The guest scans it, taps **That's me · Sam**, and gets the standings plus Report Your Hand. It needs internet, which is stated in the clip. The claim token is saved to the App Clip's app-group container, so installing Kedro later claims the history automatically. | §5.5, frame 05 |

### New in v2 because of the brief (PRD 8)

| Change | Where |
|---|---|
| A complete **voice and copy system** with an Unfiltered and a Clean register, a deterministic way to pick variants so every phone shows the same line, and a 64-string copy deck | §2 |
| **Clean language** at three levels: personal, per table (host), and Lock Screen. Under-18 defaults use the Declared Age Range API | §2.3 |
| A **mature age rating** plan for the App Store questionnaire | §2.4 |
| A new visual system: palette, type, silks, Mark, Rail, plates, photo finish, motion | §3 |
| The script wordmark is retired, replaced by a New York small-caps wordmark and the engraved Mark | §3.5 |

### Ideas adopted from other entries (and why they fit Table First)

| Idea (source) | Why it fits |
|---|---|
| Network framework P2P plus NI "At your table" vs "Other tables nearby", with a spoken **table word** fallback (rivalry) | Joining becomes more certain without adding a step. |
| **Since you last looked** and **stakes** on Play (rivalry) | Between-games value that never reaches a live table. |
| **5-second Undo** after Save Round (rivalry) | Fixes the most common mistake in one tap, at table speed. The undo is logged. |
| **Why? → knock calculator** (rivalry) | Lets the scoring teach the rules (PRD 4.7). |
| Rating computed from game 1 and **revealed at game 5** as a table moment (rivalry) | The rank gets a debut at game end, never mid-game. |
| **Gap-to-level** line on H2H (rivalry) | Turns a record into a near-term goal. |
| **Assigned reporter** for each guest in self-report (rivalry) | Removes the "who's doing Sam?" pause. |
| **Knocker-first ordering** in entry (ambient) | The verdict line resolves after the first tap. |
| **App Clip** with a rotating-token QR (ambient) | A guest with a phone needs no install. |
| **ControlWidget "Start a Table"** (ambient, rivalry) | System-native and zero-attention. |
| **5-second "Remove"** on auto-admit arrivals (ambient) | Safety without approval friction. |
| **Glass only on controls, solid surfaces for numbers** (playful) | The purist HIG rule, and it keeps scores crisp. |
| **Guest identity reuse** by name in setup (playful) | One claim later brings everything. |
| **Abandon restore window** of 15 minutes (playful) | One sore loser can't void a game. |
| **Per-table silks de-duplication** (playful) | 8 players are always visually distinct. |
| **Rematch rotates the starting seat** (playful) | Fair and invisible. |

Not adopted: a landscape table display (it conflicts with "one screen"), conditional "what each remaining value would do" lines (too much to read at the table), and an automatic short seal timer (the Finish gate is safer).

---

## 1. Design thesis (re-expressed)

**At the table, Kedro is a scoreboard you glance at and a tally board you tap eight times. Once the cards are down, it becomes the record of who's been talking shit, and whether they've earned it.**

Two speeds, as in v1, and now each has its own **volume**:

- **Table speed: quiet.** One screen, the Table. It has one action, standings that can be read from arm's length, and one sentence that explains the last knock with one dry line under it. Nothing else speaks during play: no toasts, no achievements, no rank changes, no pushes.
- **Between-games speed: loud.** Game end, Play, You, Leaderboard, achievements, widgets and notifications are where the voice gets to talk: the roast, the trash talk, the rivalry. Nobody at a table is waiting on these screens, so they can take their time.

**What "adult" means here.** Expensive things don't shout. The craft is in a small number of exact decisions: a warm paper ground instead of gray, near-black instead of black, oxblood instead of fire-engine red, a serif reserved for things worth reading, real racing silks instead of a mascot, and copy that's funny because it's specific. The chrome stays Apple's: stock `List`, `Form`, sheets, toolbars and Liquid Glass. **The content is ours.**

| PRD goal | How v2 delivers it |
|---|---|
| **Fast table flow** | Tally board: **8 taps, about 8–10 s** for a 5-player round (v1: 12). Knocker first, so the verdict line resolves after the first value. A 5-second Undo after Save. No prompts during play. |
| **Everyone joins** | One-tap **Sit In** for returning players, an NI distance label plus a spoken table word, auto-admit with a 5-second Remove, guest name reuse, and an **App Clip** for guests with a phone. 5 returning players take **6 taps**. |
| **People come back** | **Since you last looked** and **Tonight's stakes** on Play, a game-end moment that roasts the result, a rating debut at game 5, rivalry trash talk with gap-to-level lines, 24 plates, widgets, and a ControlWidget. |
| **Spreads to new tables** | Learn in 2 minutes, the **Score a Round** drill on the real sheet, a **Knock Calculator** behind every Why?, Card mode, and an App Clip guest path that claims itself after install. |

---

## 2. Voice & copy

### 2.1 Who's talking

Kedro talks like the friend at the table who keeps score because nobody else can be trusted to. They're quick, dry, a bit of a shit-stirrer, never mean, and always right about the math. They swear the way people swear over drinks: as punctuation, not as a personality.

### 2.2 Tone principles

1. **Math first, mouth second.** Every roast comes after the fact it roasts. Delete the joke and the string must still work. ("Failed knock: 2 + 10 = 12." *then* "Bold. Wrong as shit, but bold.")
2. **Roast the play, never the person.** Punch at the knock, the hand, the streak, the decision. Never at identity: gender, race, ethnicity, religion, sexuality, body, disability or age. No slurs in any form, including "reclaimed" ones. No insults about intelligence as a trait ("idiot", "moron" and the like are out); mocking a *decision* is in.
3. **One swear, max, per string.** Many strings have none. A swear has to earn its place. If the line is funny without it, leave it out.
4. **Quiet at the table, loud after.** Live surfaces (the Table, Round sheet, Live Activity) use the shortest variant: one fact line and at most one six-word roast. The full voice is saved for game end, Play, profiles, achievements and notifications.
5. **Dry beats loud.** No exclamation marks. No emoji. No "Oops!", "Yay", "Awesome" or "Whoops". Kedro is never surprised by anything.
6. **Plain where it counts.** Blocking errors, destructive confirmations, permission prompts, privacy statements, the audit log, accessibility labels, and anything about data loss say exactly what happens, first and plainly. Flavor gets at most a short tail.
7. **Buttons are verbs, not jokes.** Record Round 5, Save Change, Finish Game, Sit In, Run It Back. A button label is a promise about what happens next, so it stays literal. "Run It Back" and "Sit In" are literal, just current.
8. **Clean ≠ cute.** The Clean register swaps a swear for a *sharper* word, never "heck", "darn", "frick" or a symbol-masked "f***". If there's no sharper word, drop the clause. Clean keeps the attitude.
9. **Never push drinking, gambling or money.** Kedro is used over drinks; it never tells anyone to drink, never suggests stakes, and never jokes about real-money bets.
10. **Same line, every phone.** Variant selection is deterministic (§2.5), so the whole table sees the same roast at the same moment. One source of truth applies to the jokes too.

### 2.3 Registers: Unfiltered and Clean

| Level | Control | Default | Effect |
|---|---|---|---|
| **Personal** | Settings → Language: **Unfiltered** / **Clean** | Unfiltered, or Clean when the Declared Age Range API reports under 18 (Unfiltered is then locked until 18) | Everything this phone renders: Play, You, profiles, game end, plates, notifications, widgets, Live Activity |
| **Table** | New Table → **Clean table** toggle (host; remembered per host) | Off | Every phone at this table renders shared surfaces (the Table, Round sheet, History, game end, and the shared results card) in Clean, whatever each personal setting is |
| **Lock Screen** | Settings → Language → **Clean on Lock Screen** | Off | Notifications, Live Activity and widgets use Clean even when the personal setting is Unfiltered, because other people can read a Lock Screen |

Rules:
- **Each phone renders its own register.** The game data is identical everywhere and only the strings differ, so a Clean player sitting next to an Unfiltered player sees the *same* joke (same variant index) in a different register. This does not break "everyone sees the same score".
- **Strictest wins.** If the table is Clean, shared surfaces are Clean. Personal surfaces follow the personal setting.
- **First launch** asks nothing. It shows one line under the sign-in buttons: "Kedro swears. Rather it didn't? **Switch to Clean.**" One tap, and it can be changed any time in Settings.
- **Accessibility labels never swear.** VoiceOver reads the fact line plus the roast in the **Clean** register, regardless of the setting. A screen reader shouting profanity in a quiet room is not the same experience as reading it.
- **Strings live in one String Catalog** (`Localizable.xcstrings`) with the key structure `knock.failed.roast.v3` and two variants per key via a custom `register` dimension (`unfiltered` / `clean`), resolved by a small `Voice` type. Localization teams get the tone principles and translate the meaning, not the words. A language without a natural equivalent ships Clean only.

### 2.4 Age rating

- The App Store Connect age-rating questionnaire is answered **Profanity or Crude Humor: Frequent/Intense** and **Alcohol, Tobacco, or Drug Use or References: Infrequent/Mild** ("over drinks" is in the marketing copy, and roasts like "pour one out" exist). No gambling, contests or user-generated content beyond display names.
- Under the iOS 26 age-rating tiers, that answer should put Kedro in the mature band (we expect **16+**, shown as 17+ on storefronts still using the older scale). The exact tier is whatever the questionnaire returns, and it is confirmed before submission.
- Display names go through a profanity and slur filter: swearing is the app's voice, not a username. Slurs are blocked outright. Mild profanity in names is allowed but shown masked on the global leaderboard to people using Clean.
- The App Store description says it up front: "Kedro swears. There's a Clean mode for game night at your in-laws'."

### 2.5 Variant rotation

Each outcome string has 3–6 variants. The variant is chosen by `hash(gameID, roundNumber, stringKey) % count`, so every phone shows the same one, an edit that doesn't change the outcome keeps the same line, and a re-render never shuffles it. A variant is not repeated within the same game while unused ones remain.

### 2.6 Copy deck

The **Unfiltered** column is the default. **Clean** is the same string with the Clean register on. "—" in Clean means the string has no profanity and is identical. **All strings in this deck appear in the mockups** where a frame is listed.

**Onboarding and permissions**

| ID | Where | Unfiltered | Clean | Frame |
|---|---|---|---|---|
| O-01 | First launch headline | Keep score. Talk shit. | Keep score. Talk trash. | 01 |
| O-02 | First launch subhead | Everyone on their own phone. Kedro does the knock math, so nobody gets to fudge it. | — | 01 |
| O-03 | First launch language line | Kedro swears. Rather it didn't? **Switch to Clean.** | Clean language is on. Same attitude, no swearing. | 01 |
| O-04 | Learn link | New to Cambio? Learn it in 2 minutes, not 20 minutes of someone's half-assed explanation. | New to Cambio? Learn it in 2 minutes, not 20 minutes of someone's rambling explanation. | 01 |
| O-05 | Local Network pre-prompt | Kedro finds your table over the local network. No internet, no tracking, no bullshit. | Kedro finds your table over the local network. No internet, no tracking, no nonsense. | (spec) |
| O-06 | Notification ask (first game end) | Want a heads-up when you make the board? We only ping for stuff that matters. No "we miss you" crap. | Want a heads-up when you make the board? We only ping for stuff that matters. No "we miss you" nonsense. | (spec) |

**Joining and Play**

| ID | Where | Unfiltered | Clean | Frame |
|---|---|---|---|---|
| J-01 | Stakes on a Nearby row (5th game) | Game 5. Finish it and you're on the board. Don't fuck it up. | Game 5. Finish it and you're on the board. Don't blow it. | 03 |
| J-02 | Stranger asks to join (host row) | Jo wants a seat. You've never played together, so it's your call. | — | (spec) |
| J-03 | Auto-admit toast (host) | Ana sat in. · Remove | — | 04 |
| J-04 | Watch mode (late arrival) | You're late as hell. Watch this one, and you're first in for the rematch. | You're late. Watch this one, and you're first in for the rematch. | (spec) |
| J-05 | No tables nearby | No tables nearby. Either nobody's playing or they're playing without you. Fucking rude. | No tables nearby. Either nobody's playing or they're playing without you. Rude. | (spec) |
| J-06 | Play empty, zero games | No form yet. Grab a deck and some people and get the fuck on with it. | No form yet. Grab a deck and some people and get on with it. | (spec) |
| J-07 | Digest: passed on the board | Cleo passed you on the board. #13 → #14. Bit of a dick move, honestly. | Cleo passed you on the board. #13 → #14. Bold move, honestly. | 02 |
| J-08 | Digest: rivalry | Ana leads you 12–4. Still your nemesis. Still smug as shit about it. | Ana leads you 12–4. Still your nemesis. Still smug about it. | 02 |
| J-09 | Digest: last game | Thursday · 2nd of 4 · 31 points · rating −6. Close, but who gives a shit about close. | Thursday · 2nd of 4 · 31 points · rating −6. Close, but nobody remembers close. | 02 |
| J-10 | Stakes card | Win tonight and you're back past Cleo. | — | 02 |
| J-11 | Digest: guest claimed | Sam claimed their history. You've created a monster. | — | (spec) |
| J-12 | App Clip seat picker footer | This code changes every minute, so screenshots won't work. Nice try. | — | 05 |
| J-13 | App Clip headline | Noah's table. Which one's you? | — | 05 |

**At the table: knocks and entry** (the Table shows the fact line, then the roast in a lighter weight)

| ID | Where | Unfiltered | Clean | Frame |
|---|---|---|---|---|
| K-01 | Successful knock roast (v1) | Called it. Smug bastard. | Called it. Smug, but earned. | 09 |
| K-02 | Successful knock roast (v2) | Clean knock. Absolute fucking menace. | Clean knock. Absolute menace. | (spec) |
| K-03 | Successful knock roast (v3) | Cold-blooded shit. | Cold-blooded. | 16 |
| K-04 | Tied knock roast (v1) | No bonus, no penalty, no fucking drama. | No bonus, no penalty, no drama. | 08 |
| K-05 | Tied knock roast (v2) | Dead heat. Anticlimactic as hell. | Dead heat. Anticlimactic. | (spec) |
| K-06 | Failed knock roast (v1) | Bold. Wrong as shit, but bold. | Bold. Wrong, but bold. | 06, 07 |
| K-07 | Failed knock roast (v2) | 18 points of pure hubris. Shit happens. | 18 points of pure hubris. It happens. | (spec) |
| K-08 | Red King in a hand | Red King for −1. Dirty fucking work. | Red King for −1. Dirty work. | 15 |
| K-09 | Outcome badges (data, all registers) | landed −10 · tied · failed +10 | — | 06–08 |
| K-10 | Knocker required hint | Who knocked? Every round has one, even the shitty ones. | Who knocked? Every round has one, even the ugly ones. | (spec) |
| K-11 | Typo guard | Sam 29? Everyone else is 11 or under. Real or a fuck-up? | Sam 29? Everyone else is 11 or under. Real or a typo? | 13 |
| K-12 | Below −2 (blocking error) | Lowest possible hand is −2. There are two red Kings in the deck, not three. Nice try. | — | (spec) |
| K-13 | Undo banner | Round 5 saved · Undo | — | 08 |
| K-14 | Self-report waiting | Waiting on Cleo and Sam. Any day now, assholes. | Waiting on Cleo and Sam. Any day now. | (spec) |
| K-15 | Two claimed the knock | Ana and Cleo both say they knocked. One of you is full of shit. | Ana and Cleo both say they knocked. One of you is lying. | (spec) |
| K-16 | Nobody claimed the knock | Nobody claimed the knock. Somebody fucking did. Point at them. | Nobody claimed the knock. Somebody did. Point at them. | 12 |
| K-17 | Knocker proposal | Ana says Noah knocked · Change | — | 12 |
| K-18 | Verdict line, live (successful) | Noah's 2 is the lowest. Landed: −10, whatever the hand. | — | 09 |
| K-19 | Verdict line, live (failed) | Sam's −1 is lower than Cleo's 2. Failed: 2 + 10 = 12. | — | 06, 15 |

**History, edits and game state**

| ID | Where | Unfiltered | Clean | Frame |
|---|---|---|---|---|
| H-01 | Edit Save footer | Everyone at the table sees this, with your name on it. Don't get cute. | — | 15 |
| H-02 | Edit banner | Ben edited Round 4 · Sam 1 → −1 · Cleo's knock still failed | — | 07 |
| H-03 | Audit log header | On the record. Every edit, who made it, and when. No take-backs, no bullshit. | On the record. Every edit, who made it, and when. No take-backs, no funny business. | 14 |
| H-04 | Finished game | Final. Locked. Bitch about it all you want; it's not changing. | Final. Locked. Complain all you want; it's not changing. | (spec) |
| H-05 | Late offline edit | Arrived after the game finished · not applied | — | (spec) |
| H-06 | Duplicate offline round | Two phones saved Round 5 offline. Kept Noah's (earlier). Ben's is below · Use this version | — | (spec) |
| H-07 | Tap-to-fix hint | Tap any score to fix it. | — | 14 |
| G-01 | Finish gate | That's the last round. Lock it in before anyone starts lawyering. | — | 16 |
| G-02 | Auto-finish note | Locks itself after 15 minutes of nothing. | — | 16 |
| G-03 | End early confirm | Call it after Round 6? It counts in everyone's stats, so no bitching later. | Call it after Round 6? It counts in everyone's stats, so no whining later. | (spec) |
| G-04 | Abandon confirm | Scrap this game? It stays in history as Abandoned and counts for nothing. Anyone can restore it for 15 minutes, so don't try that sore-loser shit. | Scrap this game? It stays in history as Abandoned and counts for nothing. Anyone can restore it for 15 minutes, so no sore-loser moves. | (spec) |
| G-05 | Extend sheet | Two more rounds? Greedy as hell. Fine. | Two more rounds? Greedy. Fine. | (spec) |

**Game end**

| ID | Where | Unfiltered | Clean | Frame |
|---|---|---|---|---|
| W-01 | Winner | Noah wins. He's going to be fucking unbearable. | Noah wins. He's going to be unbearable. | 17 |
| W-02 | Shared win | Ana and Noah share it. Split the glory like adults, or don't. | — | (spec) |
| W-03 | Last place | Sam, dead last. Rough fucking night. | Sam, dead last. Rough night. | 17 |
| W-04 | Highlight: comeback | 4th after Round 3. Won it anyway. Ice in the fucking veins. | 4th after Round 3. Won it anyway. Ice in the veins. | 17 |
| W-05 | Rating debut (game 5) | Ben's rating debut: 1,486. Welcome to the board. It's a shithole down here. | Ben's rating debut: 1,486. Welcome to the board. It's rough down here. | 17 |
| W-06 | Guest claim card | Keep Sam's game. Send the link before Sam pretends this never happened. | — | 17 |
| W-07 | Rematch button | Run It Back | — | 17 |

**Leaderboard and eligibility**

| ID | Where | Unfiltered | Clean | Frame |
|---|---|---|---|---|
| L-01 | Pinned row, under 5 games | 2 more games and you're ranked. Then the shit-talk is official. | 2 more games and you're ranked. Then the trash talk is official. | 03 (Ben's rail), (spec) |
| L-02 | Not Yet Ranked footer | 1,214 people are still in their first five. Everyone starts somewhere, usually the bottom. | — | 21 |
| L-03 | Made the board | #212. You're on the fucking board. | #212. You're officially on the board. | 27 |
| L-04 | Close race | 3 points behind Cleo. Close enough to taste it. | — | (spec) |
| L-05 | Claim screen nudge | Two more games and you're ranked. Then you get a number, and opinions. | — | 18 |

**Rivalry trash talk**

| ID | Where | Unfiltered | Clean | Frame |
|---|---|---|---|---|
| R-01 | H2H, they lead big | Ana's finished ahead of you 12 times. That's not a rivalry, that's a fucking hostage situation. | Ana's finished ahead of you 12 times. That's not a rivalry, that's a hostage situation. | 20, 28 |
| R-02 | H2H gap line | 7 behind. Every time you finish ahead of her, that's one back. | — | 20 |
| R-03 | H2H, you lead | You lead Ben 9–4. Remind him. Often. | — | (spec) |
| R-04 | H2H last meeting | Last time: tonight. You finished ahead. Savor it, it won't last. | — | 20 |
| R-05 | Nemesis label | Nemesis · finished ahead of you 12 times. Twelve. | — | 19 |

**Notifications** (the complete set, §11.4)

| ID | Notification | Unfiltered | Clean | Frame |
|---|---|---|---|---|
| N-01 | Added to a table | **Noah pulled you into a table.** Get your ass over there. | **Noah pulled you into a table.** Get over there. | 27 |
| N-02 | Made the leaderboard | **#212. You're on the fucking board.** Five games deep. Don't let it go to your head. It will. | **#212. You're officially on the board.** Five games deep. Don't let it go to your head. It will. | 27 |
| N-03 | Plate while you were away | **Late Charge.** You left early and still got it. Rude, but impressive. | — | (spec) |
| N-04 | Your guest claimed | **Sam claimed their Kedro history.** You've corrupted another one. | — | (spec) |
| N-05 | Self-report nudge (Live Activity alert, not a push) | Your hand for Round 5. The whole table's waiting on your slow ass. | Your hand for Round 5. The whole table's waiting on you. | 26 |
| N-06 | Stale Live Activity | Last update 9:46 · Open Kedro to catch up | — | 26 |

**Achievements (plates)**

| ID | Plate | Unfiltered | Clean | Frame |
|---|---|---|---|---|
| A-01 | Ate Dirt | Knocked and got absolutely cooked. Everyone does it once. Most do it twice. | — | 22 |
| A-02 | Clean Knock | First successful knock. −10 and a smug fucking face. | First successful knock. −10 and a smug face. | (spec) |
| A-03 | Below Zero | Finished a round under zero. Red King, you beautiful bastard. | Finished a round under zero. Red King, you beautiful thing. | 18 |
| A-04 | Thoroughbred | Five straight wins. People are starting to talk shit behind your back. | Five straight wins. People are starting to talk. | 22 |
| A-05 | Nemesis Tamed | Finished ahead of your nemesis. Savor it. It won't last. | — | (spec) |
| A-06 | Bring One In | A guest you played with claimed their history. You're a terrible influence. | — | (spec) |
| A-07 | Hat Trick | Three clean knocks in one game. Okay, we get it. | — | 22 |
| A-08 | Photo Finish | Shared a win. Half the glory, all the arguing. | — | (spec) |

**Errors, empty states and offline**

| ID | Where | Unfiltered | Clean | Frame |
|---|---|---|---|---|
| X-01 | Already claimed | This history's already been claimed. If it wasn't you, that's awkward as hell. | This history's already been claimed. If it wasn't you, that's awkward. | (spec) |
| X-02 | Claim into the same game | You're already in this game as Noah. One of you is plenty. | — | (spec) |
| X-03 | Server unreachable | Server's not answering. Your rounds are safe on this phone, and we'll keep trying. | — | (spec) |
| X-04 | Table full | Table's full. Eight's the limit. Somebody's watching this one. | — | (spec) |
| X-05 | Fewer than 3 | Cambio needs at least 3. Find another person. Any person. | — | (spec) |
| X-06 | Empty achievements | No plates yet. Play a game. Lose it, even. That counts for something. | — | (spec) |
| X-07 | Empty rivals | No rivals yet. Play the same people twice and it gets personal. | — | (spec) |
| X-08 | Empty search | Nobody by that name. Maybe they're a guest. Maybe they're imaginary. | — | (spec) |
| F-01 | Offline pill popover (table sync) | No internet. Doesn't matter: all 5 phones are synced to each other. Play on. | — | 07 |
| F-02 | This phone only | Offline and on your own. Rounds are saved here and catch everyone up when they're back. | — | (spec) |
| F-03 | Catching up | Caught up · 2 rounds from Ana's phone | — | (spec) |
| F-04 | App Clip needs internet | The App Clip needs internet. No signal? Someone at the table can report for you. | — | 05 |

**Settings**

| ID | Where | Unfiltered | Clean | Frame |
|---|---|---|---|---|
| S-01 | Language footer | Clean: same attitude, zero swearing. For game night at your in-laws'. | — | 29 |
| S-02 | Clean table footer | Everyone at this table sees clean language on shared screens, whatever their own setting. | — | 04, 29 |
| S-03 | Clean on Lock Screen footer | Notifications, widgets and Live Activities skip the swearing. Your boss can read your Lock Screen. | — | 29 |
| S-04 | Age note | Kedro is rated for mature audiences because it swears. A lot. | Kedro is rated for mature audiences because of its language. | 29 |

That is **97 strings**. **45 of them have a distinct Clean variant**, and the rest are identical by design (principles 3 and 6).

---

## 3. Visual system

### 3.1 Principles

1. **Chrome is Apple's, content is ours.** Navigation bars, tab bars, sheets, menus, dialogs, keyboards and Liquid Glass are stock. The brand lives in content: silks, numerals, serif headlines, the Rail, plates, and the photo finish.
2. **Glass for controls, solid for numbers.** Liquid Glass appears only on the controls layer (toolbar, tab bar, the bottom action, banners). Every score sits on a solid surface, so it never shimmers.
3. **One accent per screen.** Oxblood marks the one action that matters. Brass marks the one thing worth being proud of (the leader, a plate, the winner). Everything else is ink on paper.
4. **Nothing bounces.** Motion is weighted and decisive: smooth curves, no overshoot, no confetti, no loops.

### 3.2 Palette

| Token | Light | Dark | Increase Contrast (L / D) | Use |
|---|---|---|---|---|
| `paper` (background) | `#F4F1EA` Bone | `#0B0B0C` Night | — | Screen and grouped backgrounds. A warm paper, not gray. |
| `surface` (cells) | `#FFFFFF` | `#1A1917` Graphite | — | List cells, cards, the score surface |
| `surfaceRaised` (sheets) | `#F4F1EA` | `#222120` | — | Sheet backgrounds |
| `ink` (primary text) | `#121212` | `#F2EEE6` Ivory | `#000000` / `#FFFFFF` | Text, numerals. 16.6:1 on Bone, 17.0:1 on Night |
| `ink2` (secondary) | `#5F5A52` | `#A39E94` | `#3F3B35` / `#C9C4BA` | Captions, roast lines. 6.1:1 on Bone, 6.6:1 on Graphite |
| `rule` (separators) | `#DDD7CB` | `#2E2C29` | — | Hairlines, Rail track |
| `oxblood` (accent: text, glyphs) | `#8E1B2B` | `#E2606C` Claret | `#6E1422` / `#F08A93` | The tint: selected tab, links, current Rail post. 9.0:1 on white; Claret 5.7:1 on Night, 5.1:1 on Graphite |
| `oxbloodFill` (filled buttons) | `#8E1B2B` | `#A3232F` | `#6E1422` / `#8E1B2B` | The primary action. White label: 9.0:1 / 7.4:1 |
| `brass` (text) | `#7A6232` | `#C9A961` | — | Leader caption, plate tier labels, the winner line. 5.8:1 on white, 8.7:1 on Night |
| `brassLeaf` (decoration only) | `#9A7A3F` | `#C9A961` | — | Winning-post roundel, brass plates. ≥ 3:1 graphic contrast, never body text |
| `night` (brand) | `#0B0B0C` | `#0B0B0C` | — | Splash, first launch, game end, App Clip header (always dark) |

**Silks colours** (avatar fields; never used for meaning): Oxblood `#8E1B2B`, Racing Green `#2F4A3C`, Navy `#1C2A44`, Black `#121212`, Ivory `#F2EEE6`, Brass `#C9A961`, Slate `#5B6670`, Steel `#4E6A85`, Camel `#B39A72`, Plum `#4A2A3F`. Ivory on any dark silk is ≥ 5:1, and ink on Brass, Ivory or Camel is ≥ 6.9:1.

**Red still never means "bad".** Lower is better in Cambio, and oxblood is the brand, so deltas and outcomes use signs, words and glyphs ("failed +10", ✗) and never color alone. Green does not exist in the palette.

### 3.3 Type

Two system families, so nothing is bundled and Dynamic Type works everywhere: **New York** (`.fontDesign(.serif)`) for things worth reading, and **SF Pro** for everything you operate or scan. Inline-safe stack for the mockups: `ui-serif, "New York", "Iowan Old Style", Georgia, serif` and `-apple-system, system-ui, "SF Pro Text", sans-serif`.

| Token | Family | Size / line (Large) | Weight | Text style it scales with | Use |
|---|---|---|---|---|---|
| `display.xl` | New York | 44 / 46 | Semibold | `.largeTitle` × 1.3 | Winner name, first-launch headline |
| `display` | New York | 30 / 34 | Semibold | `.largeTitle` | Screen heroes: H2H record, profile name, Play digest headline |
| `sentence` | New York | 19 / 25 | Regular; the verdict is Semibold | `.title3` | Last-round sentence, outcome lines, plate names |
| `roast` | New York | 15 / 20 | Regular italic | `.subheadline` | The roast under a fact line |
| `title` | SF Pro | 22 / 28 | Semibold | `.title2` | Sheet titles |
| `headline` | SF Pro | 17 / 22 | Semibold | `.headline` | Player names |
| `body` | SF Pro | 17 / 22 | Regular | `.body` | Everything else |
| `label` | SF Pro | 11 / 13, +0.08 em, UPPERCASE | Semibold | `.caption2` | Racecard labels: LEADING, FORM, ON THE RECORD |
| `score` | SF Pro Display | 36 | Medium, `.monospacedDigit()` | `@ScaledMetric` relative to `.largeTitle` | Live cumulative score (5 players) |
| `score.compact` | SF Pro Display | 28 | Medium, monospaced digits | `@ScaledMetric` | Live score at 6–8 players, grid totals |
| `caption` | SF Pro | 13 / 16 | Regular | `.footnote` | Captions, deltas |

Rules: numerals are always SF Pro with monospaced digits and a true minus (U+2212). Serif text never appears in navigation chrome (no UIKit appearance proxies). Serif headlines live in content headers. Scores never use the serif, because SF digits read better at arm's length.

### 3.4 The horse, treated as a racecard would

The horse spirit appears in five places, and none of them is cute.

1. **Racing silks are identity.** Every player has registered silks: two colours from the silks palette and one of 9 patterns (Plain, Hoops, Halves, Quarters, Sash, Cross-sashes, Checks, Stripes, Chevron). They are drawn as a roundel:
   - **≥ 56 pt** (profile, H2H, claim): full silk pattern, no initial.
   - **28–55 pt** (standings, setup, history header): the pattern ring with an inner disc in the primary colour carrying the initial in New York semibold. The inner disc is 62% of the diameter, so the initial stays ≥ 4.5:1 and the pattern still reads as a band.
   - **< 28 pt** (Live Activity, Dynamic Island, grid cells, log rows): solid primary colour plus the initial.
   - **Guests wear unregistered silks**: plain Camel with a dashed ring. Claiming means **"Register your colours"**: pick a pattern, and the ring turns solid. Being a guest is obvious at the table, and the reward for claiming is something you can see.
   - **Per-table de-duplication**: if two players at a table share a primary colour *and* pattern, the later joiner is shown in their **second colours** (primary and secondary swapped) for that game. Eight players are always distinct.
2. **The Mark.** An engraved horse head in profile, in a single weight, cut like a seal. It is the app icon (Ivory Mark on an Oxblood field with a hairline brass ring), the leader glyph (10 pt, brass), and the empty-state illustration. It is never animated and never given a face or expression.
3. **The Rail.** The single progress component: a hairline racecourse rail with one post per unit. Passed posts are ink, the current post is oxblood and taller, and the final post is the **winning post** with a small roundel on top. It is used for round progress (8 posts), "3 of 5 to rank" (5 posts), and plate progress. Under the hood it is a `ProgressView` with a custom `ProgressViewStyle`, so VoiceOver reads "4 of 8 rounds complete".
4. **The photo finish.** The game-end header is a monochrome **photo-finish print**: slit-scan hairlines, the winning post as a vertical Ivory line, silhouettes in the leading players' silks at the post, and a timestamp in monospaced digits ("10:21:07.43"). It is still, editorial and specific to racing.
5. **Racecard vocabulary, used sparingly.** Headings and plate names borrow from racing: **Form** (recent finishes as racing form figures, `2-1-3-2-1`), **On the record** (the audit log), **Register your colours** (claim), **Velvet Rail** (spoken table words drawn from a racing word list). **Data labels always use Cambio's own words** (PRD 8: knocking is called knocking), so it's "Abandoned", never "Scratched".

### 3.5 Wordmark and icon

- **Wordmark:** KEDRO set in New York Semibold small caps, tracked +0.18 em, with the Mark at cap height to its left. It appears only on the splash, first launch, App Clip header and shared results card. The v1 italic script wordmark is retired, because it read as playful.
- **App icon:** the Mark in Ivory on an Oxblood field with a 1.5 pt Brass inner ring. iOS 26 icon variants: the dark variant is the Mark in Claret on Night, and the tinted variant is a single-channel Mark. It is built in Icon Composer with one glass layer for the ring only.

### 3.6 Iconography and plates

- **SF Symbols** at regular weight, monochrome or hierarchical rendering. Never multicolor, and never "fill" variants used as decoration. Key symbols: `hand.raised` (knock), `checkmark` / `equal` / `xmark` (landed / tied / failed), `book.closed` (rules), `clock.arrow.circlepath` (history), `antenna.radiowaves.left.and.right` (table sync), `person.crop.circle.dashed` (guest), `arrow.uturn.backward` (undo), `qrcode` (App Clip invite).
- **Custom symbols** (SF Symbol templates with weight variants): `kedro.mark` (the horse head), `kedro.post` (the winning post), `kedro.silks` (generic silks for an empty seat).
- **Plates (achievements).** **Shape = category, metal = tier.**

| Category | Shape | | Tier | Metal | Earned by |
|---|---|---|---|---|---|
| Milestone | Roundel (circle) | | Iron | graphite to iron gradient, Ivory glyph | most players |
| Knocking | Shield | | Silver | ash to silver gradient, ink glyph | about 10–40% |
| Cards | Lozenge | | Brass | brass gradient, ink glyph | under 10% |
| Streaks | Pennant | | | | |
| Moments | Octagon | | | | |
| Rivalry | Hexagon | | | | |
| Social | Square (22% corner radius) | | | | |

An unearned plate is the shape as a 1 pt `rule` outline with a `ink2` glyph and a Rail under it. Tier is fixed per plate (the catalog in §12.6), not by live rarity, so a plate never changes metal after you earn it.

### 3.7 Motion

| Moment | Motion | Reduce Motion |
|---|---|---|
| Round saved | Rows re-sort with `.smooth(duration: 0.35)` (no bounce), scores tick with `.contentTransition(.numericText(value:))`, Undo banner rises 0.25 s | Crossfade, no movement |
| Self-report reveal | Values resolve together, 0.2 s stagger by seat | Simultaneous fade |
| Knocker proposal ring | 5 s countdown ring drawn as a stroke, linear | Text countdown "5 s" |
| Game end | The photo-finish print develops left to right (a 0.9 s slit-scan wipe), then the winner name rises 8 pt and fades in | Static print, fade |
| Plate earned (game end only) | A single specular sweep across the metal, 0.6 s | No sweep |
| Rail | Posts fill with the score animation | Instant |

Nothing loops. Nothing moves during a live game except score changes and the Undo banner. Haptics: `.success` on the saving phone, `.impact(weight: .light)` elsewhere when standings change, and `.selection` on Tally keys.

---

## 4. Information architecture

### 4.1 Structure (unchanged in shape from v1)

```
App
├── TabView (between games)
│   ├── Play         ← Since you last looked · Tonight's stakes · Nearby · New Table · Learn (first 3 games)
│   ├── Leaderboard  ← Global | Played With · pinned You row · Records · Not Yet Ranked
│   ├── You          ← silks, Form, stats, rivals, plates, history, settings
│   └── Search (Tab role: .search)
└── Table (live) ← fullScreenCover; minimizes into tabViewBottomAccessory
    ├── Record Round sheet · History sheet (grid + On the record) · Rules sheet (+ Knock Calculator)
    └── ⋯ Menu: Invite (QR) · Hand off scorekeeping · Extend · End early · Abandon
```

Navigation rules are unchanged: sheets are for doing and pushes are for reading, state changes go through `confirmationDialog`, and deep links resolve to the same value routes.

### 4.2 Play: the between-games hook

From top to bottom, and never empty:

1. **Since you last looked** (up to 4 rows, newest first, computed at `onAppear` from server views and cached): last game result with its rating change (J-09), board movement (J-07), rivalry change (J-08), a guest claim (J-11), and the closest plate with a Rail. Each row pushes to its source. Rows already seen are dropped after 48 h.
2. **Tonight's stakes** (one line, J-10): the most reachable near-term goal. The priority is: rank threshold ("Game 5 puts you on the board") > pass the player above you > level a rivalry > the closest plate.
3. **Nearby** (shown only while discovering): **At your table** (NI < 2.5 m, or matching table word) and **Other tables nearby**.
4. **New Table** (the one oxblood button).
5. **Learn Cambio** row, for your first 3 games only, after which it moves into Rules.
6. **Recent** games, with a **Run It Back** swipe action.

---

## 5. Getting a table into a game (PRD 4.1)

### 5.1 Transport

- **Primary: iOS 26 Network framework**, peer-to-peer. The host runs a `NetworkListener` advertising Bonjour `_kedro._tcp` with peer-to-peer (AWDL) enabled. Joiners run a `NetworkBrowser` and open a `NetworkConnection`, TLS with a pre-shared key derived from the table token, framed with a small length-prefixed protocol carrying operations (§9). It is all structured concurrency (`async` sequences), wrapped in an `@Observable` `TableLink` service.
- **Topology:** a star around the host. If the host drops, the online player with the lowest seat number becomes the hub. The operation log converges whatever the topology, so a hub change never changes the score.
- **Fallback: MultipeerConnectivity**, behind a remote flag, used if no Network-framework P2P path is established within 5 s. This protects launch against regressions in a brand-new API. No `MCBrowserViewController`.
- **Nearby Interaction:** after the token exchange, NI distance under 2.5 m labels a table **At your table**. Anything farther is under **Other tables nearby**.
- **Table word:** every table has a spoken two-word name from a curated racing list (Velvet Rail, Brass Stirrup, Night Paddock…), shown in the Table title and on the Nearby row. On phones without UWB, "We're Velvet Rail" is the disambiguator.
- **Permissions** in context: the Local Network prompt is preceded by copy O-05 the first time someone taps New Table or Sit In.

### 5.2 Admission

| Who taps Sit In | Result |
|---|---|
| Played with the host before, or added by the host in setup | **In immediately.** The host gets a non-modal toast "Ana sat in · Remove" for 5 s (J-03). |
| Anyone else | The joiner sees a waiting sheet. The host gets a row: "Jo wants a seat. You've never played together, so it's your call. · **Let Jo In**" (J-02). |

### 5.3 Flows

- **5 returning players:** the host taps **New Table**, and nearby played-with players are already checked. The host taps **Start**. Each of the other 4 taps **Sit In** on the Nearby row, which commits the join. **6 taps.**
- **Guest without a phone:** Add Player → the reuse suggestion "Sam · guest · 2 games with you" → tap. **2 taps** for a returning guest; a new guest by name takes 6.
- **Mid-game seat match:** a seated player whose phone joins late taps **Sit In**, and Kedro matches the seat by account. For a guest, the sheet asks "Is this Sam?" → **Yes, that's me**.
- **New person after Round 1:** **Watch** mode (read-only Table) and auto-queued for the rematch (J-04). Seats are fixed after Round 1, because the canonical rules have no catch-up scoring.
- **Rematch:** **Run It Back** creates the same game with the starting seat rotated one place, and includes anyone queued from Watch.

### 5.4 Setup sheet

As in v1 (a stock `Form`), plus: guest reuse suggestions at the top of Add Player, the **Clean table** toggle (S-02), the table word in the footer, and an **Invite with QR** row.

### 5.5 App Clip (guest with a phone, no app)

- **Invocation:** Table ⋯ → **Invite** shows a QR for `https://kedro.app/t/{gameID}?k={token}`. The token is an HMAC of the game secret and the current minute, so it **rotates every 60 s**, and a screenshot sent to the group chat goes stale (J-12).
- **Experience:** the system App Clip card opens a clip with the Night header and wordmark. "Noah's table. Which one's you?" (J-13) lists the unclaimed guest seats ("Sam · guest · That's me"), plus "Not on the list? Ask Noah to add you." The clip shows the live Table read-only, and **Report Your Hand** in self-report mode.
- **Constraints, stated honestly:** the clip uses the internet (Realtime), not local peer-to-peer, and says so (F-04). It is kept under the size limit for physical invocations. There is no Live Activity from the clip.
- **Conversion:** at game end the clip shows Sam's result and an `.appStoreOverlay` ("Get Kedro to keep this"). The claim token is written to the clip's app-group container, which the full app reads on first launch, so signing in claims Sam's games without a code.

---

## 6. The Table (PRD 4.4)

### 6.1 Layout, 3–5 players

1. **Toolbar** (glass): minimize · "Round 5 of 8" over the table word · Rules · History · ⋯. A sync pill appears only when the state is unusual.
2. **The Rail:** 8 posts, 4 passed, post 5 current.
3. **Last-round card** (solid surface, never glass): the fact line in `sentence` ("**Round 4.** Cleo knocked on 2, but Sam had −1."), the verdict in semibold ("**Failed: 2 + 10 = 12.**"), then the roast in `roast` italic `ink2` (K-06). If a red King decided it, a second roast line can replace the first (K-08). Tapping the card opens Round Detail, and **Why?** opens the Knock Calculator.
4. **Standings:** rank (shared as "2="), silks 38 pt, name, and the caption "LEADING" in brass `label` with the Mark for the leader(s). On the right, the `score`, with the delta under it in sign and words (`failed +10`, `landed −10`, `tied`).
5. **Bottom action** (glass prominent, oxblood): **Record Round 5**, captioned "You're keeping score · screen stays awake". In self-report it is **Report Your Hand**.

### 6.2 6–8 players

- **Compact rows:** 54 pt high (from 74), silks 30 pt, `score.compact` 28 pt, and the delta beside the score instead of under it. Eight rows take 432 pt, so the whole field fits between the last-round card (limited to variants whose roast fits one line) and the bottom action, at sizes up to AX1.
- **AX2 and above:** the list scrolls. **Your row pins** to the bottom as a `safeAreaInset` when it is scrolled out of view, so "where am I?" never needs a scroll.
- **Live Activity:** at most 5 rows, using the truncation rule in §11.1.

### 6.3 Attention rules

Unchanged from v1, plus the voice rule: during play, **the only copy that changes is the last-round card** (one fact, one verdict, one roast). Edits by others produce a 4 s non-modal banner (H-02). The Undo banner (K-13) appears only on the saving phone. No pushes reach a player at a live table.

---

## 7. Recording a round (PRD 4.2, 4.3, 2.6)

### 7.1 Scorekeeper mode: the Tally board

`.sheet` at `.large`:

1. **Who knocked?** A row of silks. One tap selects the knocker (oxblood ring plus `hand.raised`). Save is disabled until a knocker is chosen.
2. **Knocker first.** Focus jumps to the knocker's value first, then the others in seat order. The verdict line resolves on the first value and updates as the rest come in.
3. **Tally board:** 35 keys in a 7 × 5 `Grid`, from −2 to 32 in reading order (`−2 −1 0 1 2 3 4` / `5 … 11` / `12 … 18` / `19 … 25` / `26 … 32`), each 47 × 44 pt with monospaced digits, plus a bottom row of **33+** · **Cards** · **Save Round 5**.
   - **One tap is one complete hand value.** Focus always advances to the next player. Tap any player row to go back to it. This is deterministic and merge-proof: there is no partial number to forget.
   - Negative keys exist because there are red Kings, and nothing below −2 exists because there are only two (K-12).
   - **33+** opens a 10-key pad with an explicit **Done**, for the rare big hand.
   - Each player row previews *hand → round score*, and the verdict line under the rows states the outcome (K-18 / K-19).
4. **Save Round 5** dismisses the sheet. The Table animates, every device updates, and the saving phone shows **"Round 5 saved · Undo"** for 5 s. Undo is logged as an operation, so it is visible in On the record.

**Why a Tally board instead of a keypad:** in a 4-card game, end-of-round hands are almost always between −2 and 32. A one-tap value removes the two failure modes the judges found (a forgotten Next merging "2" and "9" into 29, and auto-advance ambiguity) and cuts the round from 12 taps to 8. The visual search cost is small because keys are in numeric reading order with 7 per row, like a calendar.

### 7.2 Typo guard

At Save, a value is flagged if it is **≥ 25 and at least double the next-highest hand in the round**, or if it is **≥ 45**. It is shown as an alert (K-11) with **Keep 29** and **Fix Sam**, at most once per round. It is non-blocking, because sometimes a hand really is 29.

### 7.3 Card mode (learners, disputed hands)

The **Cards** key swaps the Tally board for a card palette. The setting is remembered per user and turned on automatically for anyone in their first 3 games.

- **Palette:** 15 keys in a 5 × 3 grid: `A 2 3 4 5` / `6 7 8 9 10` / `J Q K♠♣ K♥♦ Joker`, each 64 × 52 pt and drawn as a minimal card face (ink on Ivory; red Kings in oxblood plus the word "−1"). A bottom row holds **⌫** (removes the last card) and **Next: Dev ›**, which is explicit because hands have different numbers of cards after sticking.
- **Hand tray:** the cards picked so far as mini faces, plus the running total: "K♥ 3 7 = 9".
- **3–5 players:** player rows as in Total mode. **6–8 players:** the rows become a **2 × 4 seat grid** of chips (84 × 40 pt, silks 20 pt, name and value). The active chip has an oxblood outline and the knocker's chip has `hand.raised`. The `.large` sheet then holds header 54 + knocker row 70 + seat grid 92 + tray 56 + palette 168 + controls 52 + verdict 48 + Save 52 ≈ 650 pt, inside the 794 pt sheet.
- **AX sizes (AX1–AX5):** the seat grid becomes a single-seat header ("**Ana** · 3 of 8", ‹ ›). The palette reflows to 3 columns and scrolls vertically, with keys growing to 88 × 72 pt. The tray wraps. The verdict line and **Save** are pinned in a `safeAreaInset`.

### 7.4 Self-report mode

Each player opens **Report Your Hand** (`.medium` detent): an **I knocked** toggle, the Tally board (or Cards), and **Submit**. Values stay hidden until everyone has reported, then they resolve together.

**Knocker resolution (T3):**

| State when the last hand arrives | Behaviour |
|---|---|
| Exactly one "I knocked" | The round completes. |
| Nobody, or two or more | Every phone shows the prompt (K-16 or K-15) with silks. **The first tap is a proposal**, shown on every phone as "**Ana says Noah knocked** · Change" with a 5 s ring (K-17). If no other answer arrives, it commits and is logged ("Ana marked Noah as the knocker"). |
| A different answer arrives within the window | The proposal is cancelled on every phone: "Ana says Noah, Ben says Cleo. Sort it out." The next single answer starts a new 5 s window. Both taps are logged. |

**Guests:** each guest gets an **assigned reporter** at setup (default: the player seated to their left, and changeable). Their row reads "Ben reports for Sam". Anyone can still take over after 30 s.

**Stragglers:** no push. The Live Activity alert (N-05) goes only to phones that haven't reported.

### 7.5 What the app computes

Unchanged: one pure function, `roundScores(hands:knocker:)`, unit-tested against the PRD examples and the full sample game in §16. It runs identically on every device and on the server.

---

## 8. History, audit trail and corrections (PRD 4.4, 4.5)

### 8.1 History sheet

One scrolling page: the **score grid** (rounds × players, small silks in the header, the knocker's cell marked ✓ / = / ✗, Edited tags, and a pinned total row), then **On the record**, the full log (H-03), with each entry showing who, what, before → after and the downstream effect. At 6–8 players the grid scrolls horizontally inside its card with the round column pinned. At AX sizes it becomes a per-round `List`. A footer says "Tap any score to fix it." (H-07).

### 8.2 Correcting a value: 4 taps

1. **History** (Table toolbar).
2. **Tap the cell** (e.g. Sam, Round 4). The Edit sheet opens with Sam's row focused and the Tally board showing the old value outlined.
3. **Tap the new value** (−1).
4. **Save Change**. The footer says H-01, and "What changes" lists before → after for every affected score, including outcome flips.

Changing the **knocker**, or any edit that **flips a knock outcome**, adds a `confirmationDialog` ("Cleo's knock: failed → landed, 12 → −10. Everyone sees this.").

### 8.3 Extend, end early, abandon, finish

- **Extend** (G-05), **End early** (G-03) and **Abandon** (G-04) are in ⋯, each with a confirmation, and all are logged.
- **Abandon restore:** for 15 minutes after an abandon, anyone in the game sees **Restore Game** on Play and on the game's history row. A restore is logged.
- **Finish gate:** when the last planned round is saved, the sheet stays open on "That's the last round. Lock it in before anyone starts lawyering." (G-01), with **Finish Game** (primary), **Fix a Round First**, and **Play Another Round**. The game auto-finishes after 15 minutes of inactivity (G-02), and that is logged.
- **Immutability:** after Finish, Edit is gone everywhere. Round Detail says H-04. Late offline edits are logged as H-05.

---

## 9. Offline and sync (PRD 6.2)

### 9.1 Model

Unchanged from v1: an append-only operation log (`GameCreated`, `PlayerSeated`, `RoundRecorded`, `RoundEdited`, `RoundUndone`, `KnockerProposed`, `KnockerResolved`, `RoundsChanged`, `GameFinished`, `GameAbandoned`, `GameRestored`). Operations carry a UUID and an HLC timestamp and are folded in `(HLC, deviceID)` order. SwiftData stores them locally, and the backend ingests them idempotently.

### 9.2 Visible states

One pill, shown only when the state is unusual: **Offline · 5 phones in sync** (F-01), **Offline · saved on this phone** (F-02), and **Syncing…** followed by a banner (F-03). The conflict rules are unchanged from v1: later HLC wins for concurrent edits; for a duplicate round, the earlier HLC applies and the other is kept with **Use this version** (H-06); an edit after finish is not applied; abandon beats everything except a logged restore.

### 9.3 Live Activity truth table

| Connectivity | Phone state | How the Live Activity updates |
|---|---|---|
| Online | Any (including locked) | Server → APNs **broadcast channel** for the game (one push reaches every subscribed phone) |
| Offline, Kedro foreground | Unlocked, on the Table | Local `Activity.update` from the app on each operation |
| Offline, Kedro briefly backgrounded | Recently locked | Local updates for as long as iOS grants background execution (seconds, not minutes) |
| Offline, Kedro suspended | Locked | **No updates.** Every update sets `staleDate = now + 3 min`. Once stale, the presentation dims the scores and shows "Last update 9:46 · Open Kedro to catch up" (N-06) |

---

## 10. Rules and learning (PRD 4.7)

1. **Learn Cambio in 2 minutes:** five cards, as in v1, now in the editorial style (serif headline, real card faces, the Mark), with the knock-gamble quiz as the last card.
2. **Score a Round (drill):** the real Round sheet in **practice mode**. There's a PRACTICE watermark in the title, the game is synthetic (Ana, Ben, Cleo), the cards are shown face up on each row, and nothing is logged. Three hands cover landed, tied and failed. The learner taps the knocker, enters values with the Tally board or Cards, and gets the verdict line plus a practice-only line: "Right. Ana's 4 is strictly lowest: −10. You're a natural. Annoying."
3. **Rules reference:** a searchable `List`, available mid-game as a `.medium` sheet.
4. **Knock Calculator** (in Rules, and opened by any **Why?**): a knocker picker, one Tally field per player, and a live verdict line. Opened from a round, it is prefilled with that round's hands ("Round 4: Cleo knocked on 2…") and can be edited freely without touching the game.
5. **In-game:** TipKit tips in the first two games ("Tap a score to see why", "Cards adds it up for you"), Card mode on by default for the first 3 games, and Watch mode for latecomers.

---

## 11. System surfaces (PRD 6.3)

### 11.1 Live Activity

| Presentation | Content |
|---|---|
| **Lock Screen / banner** | The Mark plus the table word · "Round 6 of 10" plus the Rail · **at most 5 rows** (silks 20 pt, rank, name, score, last delta) · the last-round fact line · **Record Round** or **Report Hand** (App Intents). |
| **Truncation rule** | If you're in the top 5: show ranks 1–5. Otherwise: ranks 1–4, a `···` divider, then **your row with your true rank**, highlighted. Shared ranks count as one position. |
| **Dynamic Island compact** | Leading: `R6/10`. Trailing: your rank and score, `6th · 52`. |
| **Minimal** | Your rank, `6`. |
| **Expanded** | Round plus Rail · your score and delta · top 3 plus you · last outcome · action button. |
| **Self-report alert** | `AlertConfiguration` with copy N-05, sent only to phones that haven't reported. It is the only nudge. |
| **Stale** | Dimmed scores, a clock glyph, and N-06 (§9.3). |

### 11.2 Widgets

| Widget | Families | Content |
|---|---|---|
| **Standing** | small, `accessoryCircular`, `accessoryRectangular` | Rank, rating and weekly movement. Under 5 games, a 5-post Rail with "3 of 5". |
| **Rivalry** | medium, `accessoryRectangular` | "You vs Ana · 5–12" plus the trash-talk line (R-01) in the register setting. |
| **Next Plate** | small | The closest plate, shown as its shape plus a Rail. |

### 11.3 Controls

A **ControlWidget** "Start a Table" (`ControlWidgetButton` with an App Intent) for Control Center, the Lock Screen and the Action button. It opens Kedro straight into the New Table sheet and starts advertising.

### 11.4 Notifications: still four, still none at a live table

| # | Notification | Copy | Level |
|---|---|---|---|
| 1 | Added to a table (not already in it) | N-01 | `.active` |
| 2 | Made the leaderboard (after the game) | N-02 | `.passive` |
| 3 | Plate earned while you were away from the game-end screen | N-03 | `.passive` |
| 4 | Your guest claimed their history | N-04 | `.passive` |

Notifications follow **Clean on Lock Screen** (S-03). Deliberately not notified, as in v1: nearby games, rounds recorded, edits, "you were passed", streak at risk, "we miss you", and game ended.

---

## 12. Stats, rivalries, leaderboards and achievements (PRD 5)

All derived from the operation log and finished games. Abandoned games are excluded, and games ended early count.

### 12.1 You

Header: silks at 88 pt (full pattern) · name in `display` · "#13 Global · 1,586 · +18 tonight" · **Form `2-1-3-2-1`** (racing form figures, latest on the right). Then: At a glance (Games 25 · Wins 11 · Win rate 44% · Avg / round 7.1) · Streaks · Knocking (45 knocks, 23% of rounds; 26 landed / 7 tied / 12 failed, 58% success) · Best / worst / average game · Nemesis (R-05) · Rivals · Plates preview · History. Every stat has an ⓘ with the PRD definition. Every game in history shows its rating change.

### 12.2 Head-to-head

Header: two silks facing each other, and **"Ana leads 12–5"** in `display` (P4 fix), then R-01 under it in `roast`, and the gap line R-02. The table (games together 17, finished ahead 5 / 12, wins in shared games, knock outcomes when facing each other, average final score together). Then the last meeting (R-04), and **Play Again with Ana**, which prefills New Table.

### 12.3 Leaderboards (PRD 7a recommendation, unchanged in substance)

**One ranking attribute, Kedro Rating** (multiplayer pairwise Elo, K scaled by 1/(n−1), start 1500, recomputed deterministically from finished games), **plus four Records boards** for the multi-attribute itch without multi-sort. v1's reasoning stands: one rank is one story, win rate rewards small samples, average score isn't comparable across game lengths, and fewer controls means better reading.

v2 changes:
- **Records inline:** a 2 × 2 grid under the pinned You row: Win rate (min 10 games) · Knock success (min 15 knocks) · Longest streak · Most games. It shows each leader and their value, plus your own value in `caption`, and each one pushes to its top-25 board.
- **Rating debut at game 5:** the rating is computed from game 1 but hidden until game 5, then revealed on the game-end screen to the whole table (W-05).
- **Eligibility** (5 completed, non-abandoned games): a pinned **You** row with neighbors. **Not Yet Ranked** sits below the ranked list, with each player's 5-post Rail and no number (L-02). Your own pinned row under 5 games reads L-01 with a Rail. Unclaimed guests never appear.
- **Close races:** if the player above you is within 15 rating points, your row gets L-04.

### 12.4 Play-more incentives (PRD 7b)

| Surface | Incentive |
|---|---|
| Play | Since you last looked plus Tonight's stakes (§4.2) |
| Nearby row | Stakes on the row itself (J-01) |
| Game end | Rating change, rank movement, plates, rating debut, next goal ("Two more straight for Triple Crown. Don't choke."), and **Run It Back** |
| Leaderboard | Pinned You row with neighbors, close races, Not Yet Ranked Rails |
| H2H | Gap-to-level line plus Play Again |
| Widgets / Control | Rank Rail, rivalry trash talk, Start a Table |
| Notifications | Only earned moments (§11.4) |

### 12.5 Achievement presentation

Plates are evaluated at game finish and on a guest claim, never mid-game. The grid is grouped by category, so the shapes cluster. **Next up** shows the 3 closest, each with a Rail. The detail view shows the plate large, the copy, the game it was earned in, and "Earned by 18% of players".

### 12.6 Catalog: 24 plates

| # | Plate | Rule | Category (shape) | Tier |
|---|---|---|---|---|
| 1 | Out of the Gate | Finish your first game | Milestone (roundel) | Iron |
| 2 | First Past the Post | Win a game (shared wins count) | Milestone | Iron |
| 3 | On the Board | Complete 5 games and earn a rank | Milestone | Iron |
| 4 | Seasoned | Complete 25 games | Milestone | Silver |
| 5 | Century | Play 100 rounds | Milestone | Silver |
| 6 | Clean Knock | First successful knock (A-02) | Knocking (shield) | Iron |
| 7 | Ate Dirt | A failed knock (A-01) | Knocking | Iron |
| 8 | Dead Heat | A tied knock | Knocking | Iron |
| 9 | Hat Trick | Three successful knocks in one game (A-07) | Knocking | Silver |
| 10 | Steady Hand | 10 successful knocks in a row (career) | Knocking | Brass |
| 11 | Below Zero | A negative hand (A-03) | Cards (lozenge) | Silver |
| 12 | Clean Slate | A hand of exactly 0 | Cards | Silver |
| 13 | Royal Pair | Both red Kings in one hand (−2) | Cards | Brass |
| 14 | Triple Crown | Win 3 in a row | Streaks (pennant) | Silver |
| 15 | Thoroughbred | Win 5 in a row (A-04) | Streaks | Brass |
| 16 | Late Charge | Win from outside the lead at the halfway round | Moments (octagon) | Silver |
| 17 | Wire to Wire | Lead after every round of a 6+ round game, and win | Moments | Brass |
| 18 | Photo Finish | Share a win (A-08) | Moments | Silver |
| 19 | Dark Horse | Win where every opponent had a higher rating | Moments | Brass |
| 20 | Nemesis Tamed | Finish ahead of your current nemesis (A-05) | Rivalry (hexagon) | Iron |
| 21 | Grudge Match | Play the same rival 10 times | Rivalry | Silver |
| 22 | Stable | Play with 10 different people | Social (square) | Iron |
| 23 | Full Field | Play an 8-player game | Social | Silver |
| 24 | Bring One In | A guest you played with claims their history (A-06) | Social | Silver |

**Anti-farming:** Bring One In counts only claims where the guest identity has at least 1 completed game with someone other than you. Grudge Match and Stable count only completed, non-abandoned games.

---

## 13. Accessibility

- **Dynamic Type through AX5:** standings stack (name on line 1, score and delta on line 2). Compact 8-player rows scroll from AX2 with your row pinned. Tally keys grow and reflow from 7 to 5 columns at AX1–AX2 and to 4 columns from AX3 up, with the grid scrolling and the verdict line and Save pinned. Card mode is as in §7.3. History becomes a per-round List.
- **VoiceOver:** standings rows are one element ("Ana, first place, leading, 20 points. Last round plus 16."). The last-round card reads the fact and verdict, then the **Clean** roast (§2.3). Tally keys read "minus 1", "11". The knocker proposal reads "Ana proposed Noah as the knocker. Change, button. Commits in 5 seconds." There are custom rotors in History (Rounds, Edited rounds, Knocks). Announcements are posted only when VoiceOver is running.
- **Reduce Motion:** §3.7. **Reduce Transparency:** glass controls become solid `surfaceRaised`.
- **Contrast:** every token pair in §3.2 is ≥ 4.5:1 for text (brass decoration ≥ 3:1, and never text). There are Increase Contrast variants. Silks initials are ≥ 4.5:1. No meaning is carried by color alone: outcomes use word plus glyph, guests use a dashed ring plus the word "guest", the leader uses the word LEADING plus the Mark, and plate tier uses a metal label in the detail view.
- **Motor:** targets ≥ 44 pt, Tally keys 47 × 44, card keys 64 × 52. No long-press-only actions, and every swipe action is also in a context menu.

---

## 14. SwiftUI implementation map (deltas from v1)

| Feature | Native components and APIs | UIKit? |
|---|---|---|
| Discovery and sync | **Network framework** (iOS 26 `NetworkListener`, `NetworkBrowser`, `NetworkConnection`; Bonjour; peer-to-peer enabled; TLS-PSK) in an `@Observable` `TableLink`; MultipeerConnectivity fallback behind a flag; **NearbyInteraction** for distance; `NWPathMonitor` | No |
| Voice | String Catalog with a `register` dimension, `Voice` resolver, `@AppStorage("register")`, **DeclaredAgeRange** for under-18 defaults | No |
| Silks | `Canvas` drawing of 9 patterns, cached as `Image` per size bucket; `accessibilityLabel` "Noah, oxblood and ivory hoops" | No |
| The Rail | `ProgressView` with a custom `ProgressViewStyle`; `Gauge` for widgets | No |
| Serif display | `.font(.system(.title, design: .serif))` and `.fontDesign(.serif)` in content only | No |
| Tally board | `Grid` of `Button`s, `.sensoryFeedback(.selection)`, a selected-row binding drives focus | No |
| Card mode at 6–8 players / AX | `LazyVGrid` seat grid, `ViewThatFits` and `dynamicTypeSize.isAccessibilitySize` switching to the single-seat header, `ScrollView` with `.safeAreaInset` pins | No |
| Knocker proposal | Realtime/P2P operation `KnockerProposed`; countdown ring with `Circle().trim` and `TimelineView` | No |
| Undo banner | `.safeAreaInset(edge: .bottom)` overlay, `TimelineView` for 5 s | No |
| Plates | `Shape`s (roundel, shield, lozenge, pennant, octagon, hexagon, rounded square) filled with `LinearGradient` metals; `.symbolEffect` not used; specular sweep via `KeyframeAnimator` | No |
| Photo finish | `Canvas` slit-scan lines and silhouettes, `KeyframeAnimator` wipe | No |
| App Clip | App Clip target, `NSUserActivity` web-browsing invocation, `.appStoreOverlay`, app-group container for the claim token | No |
| Live Activity | ActivityKit with **broadcast push channels**, `staleDate`, `AlertConfiguration`; `ActivityConfiguration` and `DynamicIsland` | No |
| Control | `ControlWidget` + `ControlWidgetButton(action:)` with an App Intent | No |
| Idle timer | `UIApplication.shared.isIdleTimerDisabled` in a 10-line `IdleTimer` helper (unchanged; SwiftUI has no equivalent) | **Yes, one property** |

**Total UIKit surface: still one property.**

---

## 15. Tap and time estimates

### 15.1 Recording a 5-player round (scorekeeper, Tally board)

Hands: Noah 2 (knocker), Ana 9, Ben 6, Cleo 11, Sam 4.

| Step | Taps |
|---|---|
| Record Round 5 | 1 |
| Knocker: Noah | 1 |
| Noah `2` (knocker first) | 1 |
| Ana `9` | 1 |
| Ben `6` | 1 |
| Cleo `11` | 1 |
| Sam `4` | 1 |
| Save Round 5 | 1 |
| **Total** | **8 taps, about 8–10 s** (v1: 12 taps, 12–15 s) |

The range is 8 taps for any 5-player round with no hand of 33 or more; each such hand adds 3–4 taps. Card mode costs about 2.5 taps per player plus Next. Self-report is 3–4 taps per player, in parallel.

### 15.2 Getting 5 returning players in

| Who | Steps | Taps |
|---|---|---|
| Host | New Table → Start (nearby played-with players pre-checked) | 2 |
| Each of 4 others | **Sit In** on the Nearby row (commits) | 1 each |
| **Total** | | **6 taps, about 10 s** (now literally true; v1 was really about 10) |

### 15.3 Guests

| Scenario | Taps |
|---|---|
| Returning guest, no phone (reuse suggestion) | **2** (Add Player → "Sam · guest · 2 games with you") |
| New guest, no phone | 6 (Add Player → Guest → "Sam" → Add) |
| Guest with a phone, no app (App Clip) | **3** on the guest's phone (scan → Open → That's me). 0 for the host if Sam was already added |
| Fresh install, no account | about 8, as in v1 |
| Later claim | 3 from a link, or 1 (Sign in) with the claim token from the App Clip or a fresh install |

### 15.4 Corrections

| Path | Taps |
|---|---|
| Fix one value (History → cell → value → Save Change) | **4** (v1: 7–8) |
| Undo the round just saved | **1** (within 5 s) |
| Change the knocker | 6 (adds a knocker tap and the confirmation) |

---

## 16. One dataset across every frame

**Noah's table (Velvet Rail), 5 players, scorekeeper Noah, 6 rounds extended to 8. Sam is a guest on his 3rd guest game.**

| Round | Knocker | Hands (N, A, B, C, S) | Outcome | Round scores (N, A, B, C, S) |
|---|---|---|---|---|
| R1 | Ana | 9, 3, 12, 7, 15 | landed (3 < 7) | 9, **−10**, 12, 7, 15 |
| R2 | Ben | 6, 11, 5, 5, 20 | tied with Cleo at 5 | 6, 11, **5**, 5, 20 |
| R3 | Noah | 8, 3, 14, 10, 9 | failed (Ana 3 < 8) | **18**, 3, 14, 10, 9 |
| R4 | Cleo | 3, 16, 7, 2, −1 | failed (Sam −1 < 2) | 3, 16, 7, **12**, −1 |
| *after R4* | | | | **36, 20, 38, 34, 43** |
| R5 | Noah | 2, 9, 6, 11, 4 | landed | **−10**, 9, 6, 11, 4 |
| R6 | Sam | 7, 2, 9, 8, 1 | landed | 7, 2, 9, 8, **−10** |
| R7 | Ana | 5, 2, 2, 6, 12 | tied with Ben at 2 | 5, **2**, 2, 6, 12 |
| R8 | Noah | 0, 1, 12, 6, 21 | landed | **−10**, 1, 12, 6, 21 |
| **Final** | | | **4 landed · 2 tied · 2 failed** | **Noah 28, Ana 34, Cleo 65, Ben 67, Sam 70** |

After R3 the totals were Noah 33 (4th), Ana 4, Cleo 22, Ben 31 and Sam 44, so Noah wins from 4th: **Late Charge**. Noah's R8 hand of 0 gives him **Clean Slate**, and finishing ahead of Ana (his nemesis) gives him **Nemesis Tamed**. Sam's R4 hand of −1 gives him **Below Zero**. The edit in the log: Ben changed Sam's R4 hand 1 → −1 at 9:41 (Cleo's knock still failed: Sam was already lower), and Ana changed Ben's R1 hand 21 → 12 at 8:58 (Ana's knock still landed).

**Ratings:** Noah 1,568 → **1,586 (+18)**, passing Cleo (1,571 → 1,563, −8) to **#13**. Ana 1,638 → 1,642 (+4). Ben's **debut at game 5: 1,486** (−14 from his hidden 1,500). The deltas sum to 0. Sam is unrated until claimed. **Head-to-head:** Ana led 12–4 before the game and leads **12–5** after (17 games together). **Sam's claim:** 3 games, so "Two more games and you're ranked."

**Saturday table (Night Paddock), 8 players, 10 rounds, viewer Noah.** R5: Dev knocked on 3, and Ben also had 3, so it's tied and Dev scores 3. Hands: Priya 4, Ana 7, Dev 3, Ben 3, Cleo 12, Noah 5, Jo 9, Max 15. Totals after R5: **Priya 31, Ana 38, Dev 40, Ben 44, Cleo 46, Noah 52, Jo 61, Max 74.** Noah is 6th, so the Live Activity shows ranks 1–4, ···, then 6 Noah 52. In the R6 Card-mode frames, Jo knocked; Jo 1, Priya 6, Ana building K♥ 3 7 = 9.

---

## 17. Requirements traceability

| PRD | Where |
|---|---|
| 2.5–2.6 knocker required, automatic scoring | §7.1, §7.4, §7.5, §16 |
| 2.7 planned rounds, extend, end early, shared wins | §5.4, §8.3, W-02 |
| 3.1 Sign in with Apple, debug-only test user, avatars with horse spirit | §3.4 silks, first launch (frame 01) keeps v1's `#if DEBUG` rule |
| 3.2 guests and claim · 3.3 visibility | §5.3, §5.5, §12.3 |
| 4.1 joining, host-led, played-with, rematch, 3–8 players | §5 |
| 4.2–4.3 modes, entry, negatives | §7 |
| 4.4 standings, deltas, history, progress, no sleep | §6, §8.1 |
| 4.5 edits, logging, immutability | §8 |
| 4.6 game end, end early, abandon | §8.3, frame 17 |
| 4.7 rules, learning, scoring explains itself | §10, Why? |
| 5.1–5.5 stats, H2H, leaderboards, play-more, achievements | §12 |
| 6.1 SwiftUI, accessibility | §13, §14 |
| 6.2 offline and sync | §9 |
| 6.3 Live Activity, widgets, notifications | §11 |
| 7 recommendations | §12.3 (a), §12.4 (b), §12.6 (c) |
| 8 brand: adult aesthetic, voice, profanity, Clean option, age rating | §2, §3 |
