# Kedro iOS design tournament: results

### Tournament director's report · October 2026

> Requirements: `docs/kedro-ios-prd.md` (v3.0, including Section 8, Brand constraints).
> Entries: `table-first/`, `rivalry/`, `ambient/` and `playful/`. Each has a v1 (`spec.md`, `mockups.html`) and a v2 (`spec-v2.md`, `mockups-v2.html`).
> Judges: native (HIG, platform and accessibility), table (play at a real table) and product (PRD fit and return value). The scores below are the averages of the three.

---

## 1. Winner: Table First

**Table First ("the members'-club racecard") wins both rounds and becomes the basis for the iOS app.**

**Thesis.** At the table, Kedro is a scoreboard you glance at and a tally board you tap eight times. Once the cards are down, it becomes the record of who's been talking shit and whether they've earned it. The app has two speeds with two volumes. At table speed it is quiet: one screen, one action, and one fact line about the last knock with one dry roast under it. Between games it is loud: Play, game end, the leaderboard, plates, widgets and notifications are where the voice gets to talk. Its reading of "adult" is restraint. The palette is bone paper, near-black, oxblood and brass. New York serif is used for content only, racing silks replace avatars, and the game ends on a still photo-finish print. The copy runs on one rule: **math first, mouth second.** Delete the joke and the string still works.

**Why it won.**

- **It led both rounds and widened its lead.** Round 1: 49.67 / 60, 1.67 ahead of Rivalry Engine. Round 2: 61.50 / 70, 4.67 ahead of Rivalry Engine (56.83) and 5.00 ahead of Ambient Table (56.50).
- **It improved most on the six criteria both rounds share**: +3.33 (49.67 to 53.00). Rivalry gained +0.49, Ambient +0.82, and Playful lost 0.50.
- **It had the top score on 6 of 7 round-2 criteria**: table flow 9.17, joining 9.00, trust 9.00, learnability 8.83, native quality 9.00 and tone/aesthetic 8.50. It was beaten only on return value (8.00, against Rivalry's 9.00). That gap is the main thing the grafts in Section 3 fix.
- **It best answered the new direction.** All three judges called its look the most restrained and adult of the four. Its cleaner-language system was the most complete: three levels, an under-18 lock, and a Clean register that bans "heck", "darn" and masked swears.
- **It has the best table mechanics.** The Tally board makes one tap one complete hand value (−2 to 32), so two values can never merge. A 5-player round takes 8 taps. A correction takes 4 taps from the Table, and Undo takes 1 tap within 5 s. The table judge re-derived all of its scoring math and found no errors.

**What it must fix before it ships** (all three judges agree; details in Sections 3 and 4):

1. VoiceOver must read the register the user chose. v2 forces Clean, which every judge called paternalistic.
2. Remove "Bitch about it" (H-04) and "no bitching" (G-03), which are gendered. Retarget "Any day now, assholes" (K-14) and "your slow ass" (N-05) at the delay, not at the people.
3. "Clean" may only ever mean the language setting. Rename the Clean Knock and Clean Slate plates, and the "clean knocks" wording in Hat Trick.
4. Add a mis-tap safeguard to the Tally board, and validate the board at a real table.
5. Cap profanity per screen, and sharpen the 10–15 weakest roasts.
6. Change the knocker's delta caption to the math ("failed · 2 + 10") instead of "+12".

---

## 2. Scoreboard

**The direction changed between the rounds.** Round 1 was judged on the six PRD Section 7 criteria, before the product owner found every entry too childish. Round 2 was judged after PRD Section 8 was rewritten (adult, refined aesthetic; contemporary voice that is allowed to swear; a cleaner-language option; a mature age rating). It added a seventh criterion, **tone/aesthetic**, so the maximum went from 60 to 70. The totals are not directly comparable across rounds. The "6-criteria" column compares like with like.

### Round 1 (v1, out of 60, before the adult-tone direction)

| Rank | Entry | Table flow | Joining | Trust | Return value | Learnability | Native quality | **Total** | % |
|---|---|---|---|---|---|---|---|---|---|
| 1 | **Table First** | **8.83** | 8.17 | **9.00** | 7.00 | 7.67 | **9.00** | **49.67** | 82.8% |
| 2 | Rivalry Engine | 7.83 | 8.17 | 8.33 | **9.00** | 7.17 | 7.50 | 48.00 | 80.0% |
| 3 | Ambient Table | 7.33 | **8.83** | 7.83 | 7.67 | **8.67** | 7.33 | 47.67 | 79.4% |
| 4 | Horse Play (playful) | 7.50 | 8.33 | 7.33 | 8.00 | 8.33 | 7.00 | 46.50 | 77.5% |

### Round 2 (v2, out of 70, includes tone/aesthetic)

| Rank | Entry | Table flow | Joining | Trust | Return value | Learnability | Native quality | Tone / aesthetic | **Total** | 6-criteria total | Change on 6 criteria |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | **Table First** | **9.17** | **9.00** | **9.00** | 8.00 | **8.83** | **9.00** | **8.50** | **61.50** | 53.00 | **+3.33** |
| 2 | Rivalry Engine | 7.00 | 7.83 | 8.83 | **9.00** | 7.83 | 8.00 | 8.33 | 56.83 | 48.49 | +0.49 |
| 3 | Ambient Table | 7.33 | 8.83 | 7.83 | 8.17 | 8.33 | 8.00 | 8.00 | 56.50 | 48.49 | +0.82 |
| 4 | Horse Play (playful) | 7.17 | 7.83 | 7.67 | 7.83 | 8.17 | 7.33 | 6.50 | 52.50 | 46.00 | −0.50 |

Notes:

- **Rivalry Engine's table flow fell** (7.83 to 7.00). Its v2 still uses two-digit auto-advance (about 13 taps, with a merge risk), and the judges now set it beside Table First's merge-proof 8-tap board.
- **Ambient Table kept its joining score** (8.83), the best in the field after Table First. Its trust score did not move (7.83), because v2 never specifies or mocks a correction flow.
- **Horse Play scored lowest on tone/aesthetic** (6.50). The judges still found an illustrated horse head, pastel enamel honours, red/green outcome colours and the most person-aimed profanity.

---

## 3. Grafts into Table First

These are the ideas from the other entries that go into the winner. Each one fixes a judged weakness or adds something Table First lacks.

### 3.1 From Rivalry Engine (return value and voice governance)

| Graft | What it is | Why |
|---|---|---|
| **Receipts** | After a shared finished game, each player can send each other player at the table one pre-written line that fits the result. There is no free text. Receipts are capped at one per rival per game, can be muted per person, and are shown in the **recipient's** voice. They appear in Since you last looked and as a Passive notification. | Table First's weakest criterion is return value (8.00 against 9.00). Receipts were the between-games loop all three judges wanted to steal, and they need no moderation. **Rewrite them first** so they roast the result, not the person ("Scoreboard." not "Scoreboard, dickhead"; see Section 4.3). |
| **Profanity budget** | At most one swear per string and at most **two profane strings per screen**, by priority (outcome > celebration > stakes > empty state > ambient). | The product judge's must-fix for Table First, where nearly half the strings swear. **Changed from Rivalry's version:** the budget applies when screens are designed, not at runtime. Each screen template declares its voice slots, and a CI lint checks them. Rivalry's runtime swap depends on layout, and the native judge found it unpredictable and hard to QA. |
| **Banned-term CI lint plus "names, not pronouns"** | A string lint fails the build on banned terms (gendered insults, slurs, intelligence-as-trait insults, banned Clean softeners). Copy uses display names, "you" or "they", never assumed pronouns. | It would have caught "bitch" in Table First, and "Look at him" and "He knows" in Horse Play. Table First's W-01 ("He's going to be…"), R-02 ("ahead of her") and R-03 ("Remind him") need this. |
| **What leaves the phone defaults to Clean** | Share images, the shared results card, messages to guests, and anything sent to someone who hasn't chosen a voice all use Clean unless the sender changes it. | The person on the receiving end didn't opt in. |
| **Stakes are facts or labelled estimates** | "Ana leads 12–5" is a fact. "A win tonight would likely put you past Cleo" is an estimate, with its basis given. A projected rank is never stated as fact. | Table First's J-10 ("Win tonight and you're back past Cleo") states a rating projection as fact. Trust covers projections too. |
| **Widgets frozen during live games** | Widgets reload only when a game finishes (and on claims). | Mid-game Lock Screens never leak live standings or contradict the Live Activity. |
| **Clean is not a knock outcome** | A vocabulary table: Successful / Tied / Failed (Table First's "landed" stays as a data label). "Clean" and "nailed" are banned as outcome words. | Fixes the collision the table judge flagged (the Clean Knock plate, "clean knocks", and the Clean register). |
| **Edit review header** | The "What changes" list in the Save footer is headed "Here's who this screws." (Clean: "Here's who this hurts."). | A funnier header on a plain, exact list. Math first, mouth second. |
| **Newcomer-weighted rating** | K is doubled for a player's first 10 games. | New players settle faster, which makes the game-5 debut number meaningful. |

### 3.2 From Ambient Table (cleaner language and accessibility)

| Graft | What it is | Why |
|---|---|---|
| **House voice** | A game goes Clean on shared surfaces automatically **if any seated player's personal setting is Clean**, and it never says who. The lobby reads "Clean tonight: someone at the table prefers it." The host can still force it ("Keep it clean tonight"). | The most socially intelligent clean option in the field. It replaces Table First's host-only Clean table toggle as the default, so a Clean player never has to ask. |
| **Voice line as its own VoiceOver element** | VoiceOver reads the data first (the fact and the verdict), then the voice line as a separate element that can be skipped, **in the user's chosen register**. | Fixes Table First's top must-fix. Blind users get the same product as sighted users, and can swipe past the joke. |
| **Learner seats get teaching lines** | For a player's first 3 games, or any seat with learner hints on, their own bad outcomes get a teaching line instead of a roast ("Failed: someone had less. Knock when you're at 4 or under."). | Punch up, not down. Nobody gets roasted for learning, which is what makes the app spread to new tables. |
| **60-character glance rule** | Island, Lock Screen, notification and widget lines are 60 characters or fewer, and the punchline can't be truncated. | System surfaces truncate. A cut-off joke reads as a bug. |
| **Secret plates** | A few plates are hidden until earned (Section 5.3). | Screenshot bait between games, at no cost during play. |
| **Shared reveal time for self-report** | Sealed hands flip together at a shared HLC reveal time, not as each phone receives them. | Table First already hides values until everyone reports. A shared reveal time makes the reveal simultaneous on every phone. |
| **Locales ship Clean until a native writer does Unfiltered** | Swearing is never machine-translated. | Table First says something similar; Ambient's version is stricter. |

### 3.3 From Horse Play (process and safety rails)

| Graft | What it is | Why |
|---|---|---|
| **Catalog parity test** | Two String Catalogs with identical keys. A build-time Swift Testing test fails if a key is missing in either one, or if any `rule.*`, `button.*`, `a11y.*` or `error.fix.*` string differs between registers. | It enforces "the math never swears" in CI rather than in review. |
| **Clean store metadata** | The App Store name, subtitle, keywords and screenshots use Clean copy (App Review Guideline 2.3.8, metadata appropriate for all audiences). The description still says, up front, that the app swears. | Avoids a rejection and keeps the mature rating honest. |
| **Persistent author Undo** | The author of an edit can undo it from On the record until the game finishes, in addition to the 5-second Undo. | A safety net for edits noticed late, without opening a full edit. |
| **Rematch as an opt-in invitation** | Run It Back sends each phone an invitation with seats pre-filled. Players accept, and anyone queued in Watch mode is pre-accepted. The starting seat rotates (Table First's rule). | Nobody gets dragged into a game they've left. |
| **Red King cap in Card mode** | After two red Kings are picked in one round, the red King key disables and says why. | Prevents an impossible hand. |
| **First-launch choice** | "Kedro swears." with **Keep It** / **Make It Clean** buttons in place of Table First's inline link. | One explicit, equal-weight choice. The buttons stay literal. |
| **Voice toggle in design reviews** | Every mockup and preview can flip between registers. | Proves that every Clean string keeps the joke. Use it in SwiftUI `#Preview`s too. |
| **Honour names** | Red Rum, Broke Your Maiden, Bottled It, Group One. | The best racing names in the field (Section 5.3). |

### 3.4 Table First must-fixes folded in

| Fix | Resolution |
|---|---|
| Tally board mis-taps | After each tap, the key just tapped flashes and the player's row shows the value for about 0.6 s ("Ana · 9"). With 5 or more players, or at AX1 and above, the board reflows to 6 columns with larger keys. The typo guard also flags a value that is impossible for the round's card count when the hand was entered in Card mode. |
| Validate the Tally board | Run a time-to-find test at 3 real tables before the board is built (Section 7, step 1). Keep a fallback: the 33+ keypad with an explicit **Next** as a setting ("Number pad"), for players who find a 35-key grid slow. |
| Knocker delta caption | "failed · 2 + 10" and "landed · −10", never a bare "+12". |
| Timed knocker proposal ring | Keep the 5-second window, but VoiceOver and Switch Control users get an untimed **Confirm** (the proposal waits). The ring is never the only path. |
| Weak roasts | Rewrite K-03 "Cold-blooded shit", A-07 "Okay, we get it" and about 10 other generic lines, using the bank in Section 4.2. |

### 3.5 Considered and not grafted

- **Landscape table display** (Ambient). It is genuinely useful, but it conflicts with Table First's one-screen rule. Deferred to v1.1 (Section 6).
- **Hold-a-face to set the knocker** and a **Lock Screen "I knocked"** (Ambient). They create a second way to set the knocker at the moment of the knock, and the long press is non-standard. Rejected.
- **Background Bluetooth "table nearby" alerts** (Ambient). App Review risk, and it promises distance accuracy background BLE can't give. Rejected.
- **Leaderboard lenses that re-sort under the official rank** (Horse Play). Judges in both rounds found this confusing. Rejected (Section 5.1).
- **Colour-coded outcomes** (Horse Play's racing green and oxblood). A red/green meaning that is hostile to colour-blind players and contradicts lower-is-better. Rejected.
- **Conditional "what each remaining value would do" line during entry** (Horse Play). Too much to read mid-entry. Rejected for live play, and kept inside the Score a Round drill.

---

## 4. Voice and visual direction

### 4.1 Voice rules (final)

Table First's ten tone principles stand, with these changes:

1. **Math first, mouth second.** The fact line, then the verdict, then the roast. Buttons, rule lines, errors, the audit log and accessibility labels are literal and identical in both registers (enforced by the parity test).
2. **Roast the play, never the person.** No slurs, nothing aimed at identity, no gendered insults ("bitch", "pussy", "man up"), no intelligence-as-trait insults ("idiot", "genius" as sarcasm), no mental-health slang ("psycho", "unhinged", "delusional"), and no vice labels ("degenerate").
3. **One swear per string, two per screen.** The target is **about a third of strings** profane, which is where Ambient landed and the judges liked it. Table First is at about half.
4. **Names, not pronouns.**
5. **Never push drinking, gambling or money.** Mentioning drinks is allowed ("whoever's three drinks deep"). Telling anyone to drink is not ("Next round's on you" is out). There are no wagers and no money.
6. **Punch at the moment, not the pattern.** Roast one bad knock. Never pile onto a losing streak, someone being new, or someone not playing lately.
7. **Quiet at the table.** Live surfaces get one fact line and at most a six-word roast. The full voice runs at game end, on Play, in profiles, on plates and in notifications.
8. **Same line on every phone.** The variant is chosen deterministically from `hash(gameID, round, key)`.
9. **Clean is not cute.** The Clean register swaps in a sharper word or drops the clause. Banned in Clean: heck, darn, frick, masked swears ("f***"), so-and-so, spicy, buddy, champ, yikes, fibbing, and filler softeners (basically, honestly, sorry, "Really."). Settings never says Clean has "fewer f-words" or "gentler words". It says **"Clean: same attitude, zero swearing."**
10. **Slang has a shelf life.** Use durable slang (cooked, mid, bottled it, run it back, no notes, FAFO, receipts) and review it every release. Use one register: contemporary American with dry understatement, and avoid mixing in British "innit" and "cheeky".

### 4.2 The best copy across entries

These lines are the bar for the final deck. Some are lightly edited (marked "ed.") to meet the rules above. Source IDs refer to each entry's copy deck.

| Moment | Unfiltered | Clean | Source |
|---|---|---|---|
| First launch | Keep score. Talk shit. | Keep score. Talk trash. | Table First O-01 |
| First launch subhead | Kedro does the math, so nobody has to trust whoever's three drinks deep. | (same) | Rivalry O2 |
| Learn link | New to Cambio? Learn it in 2 minutes, not 20 minutes of someone's half-assed explanation. | …someone's rambling explanation. | Table First O-04 |
| Stakes, 5th game | Game 5. Finish it and you're on the board. Don't fuck it up. | …Don't blow it. | Table First J-01, Rivalry J4 |
| Successful knock | Noah knocked on 3 and nobody had shit. | …and nobody could touch it. | Rivalry K1 (ed.) |
| Failed knock | Bold. Wrong as shit, but bold. | Bold. Wrong, but bold. | Table First K-06 |
| Failed knock | Priya knocked on 1. Sam had −1. Fucked around, found out. | …Found out the hard way. | Ambient #19 (Clean ed.) |
| Failed knock, gap of 8+ | Knocked on 9 into a 1. Absolute clown shit. | …Absolute circus. | Rivalry K4 (ed.) |
| Beat a knock | Your 2 just ruined Noah's whole night. Love that for you. | (same) | Horse Play #21 |
| Red King | Red King for −1. Dirty fucking work. | Red King for −1. Dirty work. | Table First K-08 |
| Both red Kings | Both red Kings. −2. Filthy. | Both red Kings. −2. Ruthless. | Rivalry K6 |
| Nobody claimed the knock | Nobody claimed the knock. Somebody fucking did. Point at them. | …Somebody did. Point at them. | Table First K-16 |
| Self-report waiting | Waiting on Cleo and Sam. Any day now. | (same) | Table First K-14 (ed.: the swear is cut) |
| Self-report nudge (Live Activity) | Round 5: your hand. The table's been waiting a fucking while. | Round 5: your hand. The table's been waiting a while. | Replaces Table First N-05 and Rivalry L8 ("your slow ass") |
| Finish gate | That's the last round. Lock it in before anyone starts lawyering. | (same) | Table First G-01 |
| Finished game | Final. Locked. Complain all you want; it's not changing. | (same) | Table First H-04 (ed.: "bitch" removed) |
| Winner | Noah fucking wins. | Noah wins. Obviously. | Ambient #32 |
| Winner, comeback | 4th after Round 3. Won it anyway. Ice in the fucking veins. | …Ice in the veins. | Table First W-04 |
| Stole it late | Stole it on the last knock. Cold-blooded. | Stole it on the last knock. Ice cold. | Horse Play #38 |
| Lost by 1 | Lost by 1. One. Fucking. Point. | Lost by 1. One. Single. Point. | Rivalry W4 |
| Last place | Leo: 99. Dead fucking last. One off triple digits, which is honestly impressive. | Leo: 99. Dead last. One off triple digits… | Ambient #36 |
| Bottled it | Mia led for five rounds and finished third. Bottled it. | …Fumbled it. | Horse Play #41 |
| Rating debut | Ben's on the board. 1,486. Welcome. It's a shithole down here. | …It's rough down here. | Table First W-05 (ed.) |
| H2H, they lead big | Ana's finished ahead of you 12 times. That's not a rivalry, that's a fucking hostage situation. | …that's a hostage situation. | Table First R-01 |
| Rival widget | Maya 13, you 8. Maya's living in your head rent-free. | (same) | Ambient #58 (ed.: names, not pronouns) |
| Receipt, they failed a knock | Knocking on 9 is a choice. A shit choice. | …A bad choice. | Rivalry R3 |
| Receipt, rematch | Run it back. I'll go easy. (I fucking won't.) | …(I won't.) | Rivalry R4 |
| Receipt, you won | Scoreboard. | (same) | Rivalry R1 (ed.: "dickhead" removed) |
| Receipt, chasing | Gap's 3. Sleep with one eye open. | (same) | Rivalry R2 (ed.: "asshole" removed) |
| Guest claimed | Sam claimed their history. You've created a monster. | (same) | Table First J-11 |
| App Clip QR | This code changes every minute, so screenshots won't work. Nice try. | (same) | Table First J-12 |
| Server error | Our servers shat the bed. Your game's safe on this phone. | Our servers fell over. Your game's safe on this phone. | Rivalry ER3 (Clean ed.) |
| Offline | No internet? Who gives a shit. Phones at a table talk to each other directly. | No internet? No problem… | Rivalry OF1 |
| Under 3 players | Cambio needs 3. Two people is just a staring contest. | (same) | Rivalry ER4 |
| Rules sheet | Here's the math, no bullshit. | Here's the math, no nonsense. | Rivalry RU1 |
| Settings footer | Clean: same attitude, zero swearing. For game night at your in-laws'. | (same) | Table First S-01 |

**Lines to retire** (they fail Section 4.1): "Bitch about it", "no bitching later", "Any day now, assholes", "your slow ass", "Scoreboard, dickhead", "Sleep with one eye open, asshole", "you lucky bastard", "you smug prick", "rage-quit like a little shit", "scared shitless", "Coward" (on a declined rematch), "genius", "degenerate", "Psycho", "Unhinged", "you stray", "Next round's on you", "Your liver and your record say hi", "Grab a drink and heckle", Glue Factory, "Look at him", "He knows". Clean twins to rewrite: "How spicy do you want it?", "so-and-so", "buddy", "champ", "Yikes", "officially official", "fibbing", "basically", "honestly", "sorry", "Really.", "gentler words", "fewer f-words".

### 4.3 Cleaner-language approach (final)

| Level | Control | Default | Scope |
|---|---|---|---|
| **Personal** | First launch (Keep It / Make It Clean), then Settings → Language: Unfiltered / Clean | Unfiltered for adults. **Clean and locked** when the Declared Age Range API reports under 18. | Everything this phone renders outside a shared game |
| **House voice** (per game) | Automatic, plus a host override in the lobby ("Keep it clean tonight") | Clean if **any** seated player's personal setting is Clean, and Kedro never says who | Shared surfaces on every phone: the Table, Round sheet, History, game end, the Live Activity and the shared results card |
| **Lock Screen** | Settings → Language → Clean on Lock Screen | **On**, so the Lock Screen is Clean by default (decision 6.2) | Notifications, widgets and Live Activities |
| **Outbound** | Settings → Language → Clean on shared images | On | Share cards and guest messages |
| **Recipient decides** | None | None | Receipts, notifications and other people's profiles render in the viewer's register |
| **VoiceOver** | Follows the personal register. Optional **Clean for VoiceOver** toggle. | Follows the register | The voice line is a separate, skippable element after the data |

Implementation: two String Catalogs with identical keys (`Unfiltered.xcstrings`, `Clean.xcstrings`), resolved by an `@Observable` `Voice` through `String(localized:table:)`. Variants are keyed `knock.failed.roast.1…n`. The parity test and the banned-term lint run in CI. Display names go through a slur filter. Mild profanity in a name is masked for Clean viewers on the global board.

### 4.4 Visual direction (final)

Keep Table First's racecard system as specified in its spec-v2 Section 3, with these refinements:

- **Palette:** Bone `#F4F1EA` / Night `#0B0B0C`, Graphite surfaces, oxblood as the only accent (the primary action, you, the current post), and brass for the leader, the winner and plates. **Green doesn't exist, and red never means bad.** The existing `BrandBackground` (`#0A0A0E`) and Table First's Night (`#0B0B0C`) are close enough to merge. Keep the existing asset value so the splash doesn't shift.
- **Type:** New York for things worth reading and SF Pro for everything you operate or count ("serif speaks, sans counts", from Ambient). Scores are always SF with monospaced digits and a true minus. Add Rivalry's **SF Mono racing-form metadata line** ("ROUND 7 OF 10 · VELVET RAIL") as the `label` style on the Table header and plates.
- **Outcomes encoded by form as well as glyph:** successful is a solid ink badge, tied is an outline, failed is hatched, each always with its word (Rivalry and Ambient). This adds to Table First's ✓ / = / ✗.
- **Horse spirit:** racing silks as identity (legible down to 28 pt, guests in unregistered dashed silks until they "register their colours"), the engraved Mark (never animated, never given a face), the Rail as the one progress component, plates where shape is the category and metal is the tier, and the still photo-finish print at game end.
- **Retired across the field:** script wordmarks (Ambient's red script, Table First's v1 italic), illustrated horse heads, pastel or enamel badges, rosettes, horseshoe `symbolEffect` animations, confetti and anything that bounces.
- **Chrome is Apple's:** stock `List`, `Form`, sheets and toolbars. Liquid Glass is used only on controls, and every number sits on a solid surface.

---

## 5. Leaderboard, play-more and achievements

### 5.1 Leaderboard ranking (PRD 7a)

All four entries came to the same conclusion: **one official rank from one skill rating**, with other attributes shown as separate records. That consensus is the recommendation.

- **Kedro Rating:** multiplayer pairwise Elo from finishing order (finishing ahead counts as a win, an equal final score as a draw, and shared wins as ties). K is scaled by 1/(n−1), and **doubled for a player's first 10 games** (Rivalry). Every player starts at 1,500. The rating is rebuilt deterministically by replaying finished, non-abandoned games, so edits, claims and migrated history always come out right.
- **Why one rank:** "#3 among your people" has to mean the same thing on every phone. Win rate is skewed by table size (a 3-player win is far likelier than an 8-player win) and by small samples. Average score depends on the number of rounds. Pairwise rating accounts for who you beat.
- **Why not OpenSkill μ−3σ** (Ambient): it is more conservative, but it starts low on purpose, which makes the game-5 debut feel deflating (product judge). It is also harder to explain in a sentence at the table.
- **Hidden until game 5, then a debut at the table:** the rating is computed from game 1 and revealed on the game-end screen to the whole table when a player finishes game 5.
- **Scopes:** **Played With** (default) and **Global** (opens on "Around me", with a jump to the top). Your row is pinned, with your neighbours.
- **Records, not lenses:** four read-only boards, each with **its own ordinal**: Win rate (minimum 10 games), Knock success (minimum 15 knocks), Longest streak and Most games. They appear inline as a 2 × 2 grid under your pinned row, and each pushes to its own top-25 board. The official rank never appears on a re-sorted list.
- **Eligibility:** 5 completed, non-abandoned games. Below that, a player is listed under **Not Yet Ranked** with their silks, name and a 5-post Rail, and no number. Global shows the count ("1,214 people are still in their first five."). Unclaimed guests are never listed. Tied ratings share a rank ("2=").
- **Close races:** if the player above you is within 15 points, your row says so.

### 5.2 Play-more incentives (PRD 5.4)

| Surface | Incentive | Source |
|---|---|---|
| Play | **Since you last looked** (last game and its rating change, board movement, rivalry change, guest claims, receipts, the closest plate), then **Tonight's stakes** (facts or labelled estimates) | Table First, Rivalry |
| Everywhere an unranked player appears | The 5-post Rail ("3 of 5"): on the Nearby row, lobby seat, profile, board, widget and game end | Table First, Ambient's shoe |
| Game 5 | **The debut**, revealed to the whole table | All four |
| Game end | Rating change, rank movement, plates, the next goal ("Two more straight for Triple Crown."), and **Run It Back** as an opt-in rematch | Table First, Horse Play |
| Head-to-head | Gap-to-level line ("7 behind. Every time you finish ahead of Ana, that's one back.") and **Play Again with Ana** | Rivalry, Table First |
| Receipts | One pre-written line per rival per game, muteable | Rivalry |
| Plates | **Next up** shows the three closest with Rails. Secret plates. | Table First, Ambient |
| Learning | Score a Round drill, Did the Reading badge, learner seats that get teaching lines | Table First, Ambient |
| Guests | A claim card that sells their own story, **Bad Influence** for the host, and an App Clip claim token that claims history automatically after install | Table First, Ambient |
| Widgets and controls | Standing (with the Rail under 5 games), Rivalry (trash-talk line), Next Plate, and the **Start a Table** ControlWidget. Widgets are frozen during live games. | Table First, Rivalry |

**Notifications (the complete set, none Time Sensitive, none at a live table):** added to a table (Active), made the leaderboard (Passive), plate earned while away from game end (Passive), your guest claimed (Passive), receipt received (Passive, muteable). The self-report nudge is a Live Activity alert, not a push.

**Guardrails:** no loss-framed pushes ("you were passed" appears only in Since you last looked), no streak-at-risk, no "we miss you", no countdowns, nothing paid.

### 5.3 Achievement catalog: 31 plates plus one learning badge

Table First's presentation stays: **shape is the category, metal is the tier** (Iron: most players; Silver: about 10–40%; Brass: under 10%). The tier is fixed per plate. Plates are evaluated at game finish and on guest claims, never mid-game, and only from finished, non-abandoned games. They are public on profiles, in the viewer's register. Names were chosen across all four entries, and "Clean" is never used as an outcome word.

| # | Plate | Category (shape) | Tier | Rule | Voice line (Unfiltered / Clean if different) | Source |
|---|---|---|---|---|---|---|
| 1 | Out of the Gate | Milestone (roundel) | Iron | Finish your first game | One down. The bar was low and you cleared it. | Table First, Ambient |
| 2 | Broke Your Maiden | Milestone | Iron | Win a game (shared wins count) | First win. Holy shit, screenshot it. / First win. Screenshot it. | Ambient, Horse Play |
| 3 | On the Board | Milestone | Iron | Finish 5 games and get a rank | Five games, one number. No more hiding. | All |
| 4 | Seasoned | Milestone | Silver | Finish 25 games | Twenty-five games. It's a habit now. | Table First |
| 5 | Touch Grass | Milestone | Brass | Finish 100 games | A hundred games. Genuinely, go outside. | Ambient |
| 6 | Front Runner | Milestone | Brass | Reach #1 on your Played With board (at least 5 ranked people) | #1 among your people. Everyone hates you now. Good. | Rivalry |
| 7 | Group One | Milestone | Brass | Reach the global top 100 | Top 100 on Earth. At a card game. Respect. | Horse Play |
| 8 | Landed It | Knocking (shield) | Iron | First successful knock | −10. Felt fucking great, didn't it. / −10. Felt great, didn't it. | Table First (renamed from Clean Knock) |
| 9 | Fucked Around, Found Out / Found Out | Knocking | Iron | First failed knock | Knocked and got beaten. +10 for the audacity. | Ambient |
| 10 | Dead Heat | Knocking | Iron | A tied knock | Technically not a loss. Technically. | All |
| 11 | Bold Choice | Knocking | Iron | Knock on 10 or more and fail | Knocked on double digits and got beaten. We love the confidence. | Ambient (renamed from Delusional) |
| 12 | Hat Trick | Knocking | Silver | 3 successful knocks in one game | Three landed knocks in one game. Show-off. | Table First |
| 13 | Steady Hand | Knocking | Brass | 10 successful knocks in a row (career) | Ten straight. Ice in the fucking veins. / Ten straight. Ice in the veins. | Table First |
| 14 | Red Rum | Cards (lozenge) | Silver | Finish a round with a negative hand | Sub-zero hand. Sneaky shit. / Sub-zero hand. Sneaky. | Horse Play |
| 15 | Ghost Hand | Cards | Silver | A hand of exactly 0 | Zero. Not a goddamn point. / Zero. Not a single point. | Rivalry (replaces Clean Slate) |
| 16 | Royal Pair | Cards | Brass | Both red Kings in one hand (−2) | Both red Kings. Filthy. / Both red Kings. Ruthless. | Table First |
| 17 | Nothing to See Here (secret) | Cards | Brass | Land a knock on exactly 0 | Knocked on zero and landed it. Smooth as hell. / …Smooth. | Ambient |
| 18 | Triple Crown | Streaks (pennant) | Silver | Win 3 in a row | Three straight. Insufferable. | All |
| 19 | Thoroughbred | Streaks | Brass | Win 5 in a row | Five straight. People are starting to talk shit behind your back. / …People are starting to talk. | Table First |
| 20 | Late Charge | Moments (octagon) | Silver | Win from outside the lead at the halfway round | Behind at halfway. Won anyway. Disrespectful as hell. / …Disrespectful. | Table First |
| 21 | Dark Horse | Moments | Brass | Win where every opponent had a higher rating | Every opponent rated higher. Nobody saw that shit coming. / …Nobody saw that coming. | Table First |
| 22 | Wire to Wire | Moments | Brass | Lead or share the lead after every round of a 6+ round game, and win | Led every round. Didn't even break a sweat. | All |
| 23 | Photo Finish | Moments | Silver | Win by exactly 1 point | Won by a single point. Talk your shit, you've earned it. / …Talk your trash… | Rivalry, Horse Play |
| 24 | Shared Spoils | Moments | Silver | Share a win | Half the glory, all the arguing. | Rivalry name, Table First line |
| 25 | Bottled It (secret) | Moments | Silver | Lead after the second-to-last round, then lose | Led into the final round and lost. Fucking bottled it. / …Choked. | Ambient, Horse Play |
| 26 | Nemesis Tamed | Rivalry (hexagon) | Iron | Finish ahead of your current nemesis | Finished ahead of your nemesis. About fucking time. / …About time. | Table First, Rivalry |
| 27 | Grudge Match | Rivalry | Silver | Play the same rival 10 times | Ten games with the same person. It's a relationship now. | Table First, Horse Play |
| 28 | Exorcism (secret) | Rivalry | Brass | Finish ahead of your nemesis in 3 straight shared games | Three straight over your nemesis. Demons: gone. | Ambient |
| 29 | Stable | Social (square) | Iron | Play with 10 different people | Ten different people put up with you. Impressive. | Table First, Ambient |
| 30 | Full Field | Social | Silver | Finish an 8-player game | Eight at one table and nobody stormed out. | All |
| 31 | Bad Influence | Social | Silver | A guest you played with claims their history and finishes a game on their own account | Someone you dragged into this made an account. You did this. | Ambient (replaces Bring One In) |
| — | Did the Reading | Learning (kept separate) | — | Finish Learn and the Score a Round drill | Finished the lessons. Respect. | Ambient, Rivalry's Schooled |

**Anti-farming:** Stable, Grudge Match and Bad Influence count only accounts and claimed guests, and only completed, non-abandoned games. Bad Influence counts once per guest identity, and that guest needs a completed game with someone other than you. Dropped from the field: Glue Factory (dunks on a losing streak), Delusional, Cold-Blooded's "Psycho" line, and Unbeaten's "this asshole".

---

## 6. Unresolved risks and decisions for the product owner

### 6.1 Decisions needed

| # | Decision | Recommendation |
|---|---|---|
| 1 | **App Store age rating.** All four entries answer the questionnaire **Profanity or Crude Humor: Frequent/Intense** and **Alcohol, Tobacco, or Drug Use or References: Infrequent/Mild**. There is no gambling, no simulated gambling and no user-generated free text (receipts are pre-written). Under Apple's current age tiers the expected result is **16+**, possibly 18+, depending on what the questionnaire returns. **Clean mode does not change the rating**, because the rating covers the binary. Decide whether to accept the computed tier or set it higher. | Accept the computed tier (expected 16+). Lock Unfiltered under 18 through Declared Age Range. Keep store metadata Clean, and say "Kedro swears. There's a Clean mode." in the description. Confirm the actual tier in App Store Connect before submission. |
| 2 | **Lock Screen default.** Table First and Rivalry default to swearing on the Lock Screen. Horse Play defaults to Clean. Ambient defaulted to swearing, and judges marked it down. | **Clean on Lock Screen by default**, with opt-in swearing. Lock Screens get seen. |
| 3 | **Affectionate epithets.** Are "smug bastard", "magnificent bastard" and "you animals" roasting the play or the person? | Allow them only in celebrations and only aimed at a winner or a group, never in receipts or at a loser. Write it into the lint as a reviewed list. |
| 4 | **Profanity density.** Table First is at about half of all strings. | Aim for about a third, with the per-screen cap of two. |
| 5 | **Receipts in v1.** They need sending UI, a Passive notification and per-person mute. | Include them. They are the return-value graft that closes Table First's weakest gap. |
| 6 | **Landscape table display** (a phone propped mid-table as the shared scoreboard). | Defer to v1.1, and test it at a table first. |
| 7 | **Rating number scale.** Start at 1,500 (Table First, Rivalry) or 1,000 (Horse Play, Ambient)? | 1,500. A debut near 1,500 reads as respectable, not as a failure. |
| 8 | **Red Rum.** It is the name of a real, famous racehorse. | Run a quick trademark and naming check, and keep Ghost Hand-style alternatives ready. |
| 9 | **Alcohol references.** Copy mentions drinks ("three drinks deep", "over drinks") but never tells anyone to drink. | Keep mentions and ban nudges. The age-rating answer already covers mild references. |

### 6.2 Risks

- **The Tally board is unvalidated at real tables.** The 35-key visual search cost and adjacent mis-taps (11 vs 12, 2 vs 9) are real risks. Mitigations: the tap flash and readback, a 6-column reflow at 5 or more players, the typo guard, a Number pad fallback, and a time-to-find test before the board is built.
- **The iOS 26 Network framework peer-to-peer APIs are new.** MultipeerConnectivity stays behind a remote flag as a fallback. Test with 8 phones, mixed UWB and non-UWB, in a crowded bar.
- **Offline Live Activities go stale.** A locked phone at a table with no internet can't update. The designed stale state ("Last update 9:46 · Open Kedro to catch up") is the honest answer. Make sure it isn't read as a bug.
- **The App Clip needs internet**, and has a size limit for physical invocation. A table with no signal falls back to an assigned reporter.
- **Slang ages.** Copy needs an owner and a review every release.
- **Moderation is limited to display names.** Slurs are blocked, and mild profanity is masked for Clean viewers. Any future free-text feature (custom receipts, chat) changes the age-rating answers and needs moderation.
- **Localization:** non-English locales ship Clean only until a native writer does an Unfiltered pass. That is a weaker product in those markets.
- **The backend is not ready.** PRD 6.4 requires a redesigned schema. The operation log, server ingestion, rating replay, broadcast-channel Live Activity pushes and receipts all depend on it.
- **App Review on profanity.** A frequent-profanity app with Clean metadata is allowed, but screenshots and the description must match the rating. Expect a closer review.

---

## 7. Next steps toward implementation in `apps/ios`

The current app has `App/` (`KedroApp`, `RootView`, `MainTabView`, `AppModel`), `Core/` (Auth with Sign in with Apple, Config, Networking), and `Features/` (Games, Leaderboard, Players, SignIn, Splash). Follow `apps/ios/AGENTS.md` throughout: modern SwiftUI, `@Observable`, Swift Testing, a `#Preview` for every view, and UIKit only for the idle-timer property.

1. **Consolidate the spec (docs).** Write `docs/kedro-ios-design.md`, which is Table First v2 with the grafts and fixes in Sections 3–5. Write `docs/kedro-ios-copy.md`, the final copy deck run against Section 4.1, with every retired line replaced. Run the Tally board time-to-find test at 3 tables with the existing mockup (`table-first/mockups-v2.html`) before building it.
2. **Scoring core first** (`Kedro/Core/Scoring/`). Write a pure `roundScores(hands:knocker:)` and game totals, with Swift Testing tests against PRD 2.6, Table First's sample game (spec-v2 §16) and the 8-player tied-knock round. Mirror the same function in `packages/shared` so `apps/api` computes identical results.
3. **Design tokens** (`Kedro/Assets.xcassets`, `Kedro/Core/Design/`). Add color sets with Any, Dark and Increase Contrast variants: paper, surface, surfaceRaised, ink, ink2, rule, oxblood, oxbloodFill, brass, brassLeaf and night. Point `AccentColor` at oxblood, and keep `BrandBackground` as night. Add type helpers (`display`, `sentence`, `roast`, `label`, `score`) built on text styles so Dynamic Type works. Commission the Mark and the app icon (Icon Composer, with dark and tinted variants) to replace `Logo.png` and `AppIcon.png`.
4. **Voice system** (`Kedro/Core/Voice/`). Add the `Voice` resolver (personal, house, Lock Screen and outbound levels, with Declared Age Range for under-18 users) and the two String Catalogs with identical keys. The variant picker must use a **stable hash** (for example FNV-1a or SHA-256 over gameID, round and key). Swift's `Hasher` and `hashValue` are seeded per launch and would show different lines on different phones. Add the catalog parity test and a `bun` script for the banned-term lint, both wired into CI.
5. **Restyle what exists.** Update Splash and SignIn with the new tokens and the first-launch copy (Keep It / Make It Clean). Keep the `#if DEBUG` test-user sign-in. Restructure `MainTabView` into Play, Leaderboard, You and Search using the `Tab` API.
6. **The live game, offline first.** Store the operation log in SwiftData. Build the Table screen (`fullScreenCover` that minimizes into `tabViewBottomAccessory`), the Round sheet with the Tally board (mis-tap flash, typo guard, Number pad fallback), Card mode, History with tap-to-fix, On the record, the 5-second Undo and persistent author Undo, and the Finish gate. Previews for 3, 5 and 8 players, light and dark, and AX sizes.
7. **Table link.** Build an `@Observable` `TableLink` on the Network framework (`NetworkListener`, `NetworkBrowser`, `NetworkConnection` with TLS-PSK), with the Multipeer fallback behind a flag, Nearby Interaction for "At your table", table words, Sit In and auto-admit with a 5-second Remove.
8. **Backend.** Redesign the `supabase` schema for players, guests, games, rounds, operations, ratings, plates and receipts. Add `apps/api` routes for idempotent operation ingest, rating replay, Realtime and APNs broadcast-channel pushes. Push any new keys through `bun run env:push` and add them to `TARGETS` in `scripts/env.ts`.
9. **Between-games surfaces.** Build Play (Since you last looked, stakes), the Leaderboard (rating, scopes, Records, Not Yet Ranked), You, head-to-head, plates (shapes and metals), receipts, and the debut.
10. **System surfaces.** Live Activity (broadcast channel, truncation rule, `staleDate` state, self-report alert), widgets (frozen during games), the Start a Table ControlWidget, the App Clip with the rotating QR and app-group claim token, and the five notifications.
11. **Ship prep.** The age-rating questionnaire (decision 6.1.1), Clean store metadata and screenshots, an accessibility audit (VoiceOver register parity, AX5, Reduce Motion, Increase Contrast), and an 8-phone offline table test.

---

## 8. Owner decisions (October 28, 2026)

The product owner reviewed the four entries and this report. **These decisions override anything above that conflicts with them.** The PRD (`docs/kedro-ios-prd.md`) has been updated to match.

### 8.1 Base design
- **Table First is the base**, including its interaction model, information architecture and voice system.
- **Joining comes from Ambient Table:**
  - the **Table card** that pops up when you open Kedro near a table ("Maya's table · at your table · 0.6 m", the seated faces, one-tap Sit down);
  - the opt-in **nearby alert** (Bluetooth, at most 3 a day) when your people start a table;
  - the **"saved you a seat"** push when a host adds you from their played-with list.
  - Not adopted: the Control Center "Start a table" control.

### 8.2 Brand and look: replaces Section 4's visual direction
- **Drop the racing-club look entirely:** silks, the Rail, photo-finish prints, brass/oxblood/bone paper, the New York serif, racehorse names, the "plates" metaphor and Red Rum. Section 6.1 decision 8 no longer applies.
- **The original Kedro logo is the brand** (`apps/ios/Kedro/Assets.xcassets/Logo.imageset/Logo.png`, the red retro script over a gritty silver horse). Use the logo itself instead of horse imagery anywhere in the app. The design pass proposes a **small mark** derived from the logo for the app icon, Dynamic Island, widgets and badges.
- **Dark-first and moody**, with light mode secondary. Start from the web palette: near-black #0a0a0e (gradient #15151c → #08080c), Kedro red #e63946 (deep #b81d2a), cream #f5efe6, silver #c0c0c0, gold #f5c842 for leaders. The faint card-suit watermarks from the web app are on brand.
- **Type:** Bebas Neue for scores and headlines, SF Pro for body text, both with Dynamic Type.
- **Avatars:** photo, **or** any emoji on a chosen color, **or** a curated set of illustrated avatars in the logo's gritty style. Silks are gone.
- **Table words stay**, renamed in Kedro's voice (card and bar slang) instead of racehorse names.

### 8.3 Voice: replaces Section 4.1 rules 3, 6 and 7, and Section 6.1 decisions 2–4
- **Trash talk runs everywhere, including during play.** "Quiet at the table" no longer applies. Recording a round must still never slow down.
  - Automatic roasts every round.
  - Running banter about the standings.
  - **Player taunts**: a large canned library, plus **custom taunts** with safeguards. Custom taunts can only go to people at your table or people you've played with; a filter blocks slurs and abuse; players can report a taunt and mute or block a person.
- **Three language levels**, chosen by each player: **Clean**, **Spicy** (about a third of lines swear), **Unhinged** (half or more). This replaces the fixed one-third target.
- **The Lock Screen and Live Activity follow the player's setting**, not Clean by default.
- **Affectionate insults are allowed anywhere**, including at losers. Never slurs, nothing aimed at identity, and the under-18 lock stays.
- **Receipts ship in v1.**

### 8.4 The table: replaces Section 7.1 of Table First
- **Score entry uses a number pad by default, not the Tally board.** Hands can go above 32 after penalty cards from bad sticks. Card mode stays as the option for learners and disputed hands. Keep the typo guard and Undo. The table-test risk in Section 6.2 now applies to the number pad's speed instead.
- **Optional live knock:** anyone can mark a knock the moment it happens, which sets off a taunt and pre-fills the knocker. Otherwise the knocker is picked at entry, as before.

### 8.5 Leaderboard and scope
- **Sortable leaderboards:** skill rating (Elo-style, starting at 1,000; changed from 1,500 by the owner on October 28), win rate, wins, average score and knock success. Records boards stay, and so does the 5-game eligibility rule.
- **In v1:** the App Clip for guests, **table display mode** (a phone or iPad propped up in landscape as a shared scoreboard; this replaces Section 6.1 decision 6) and widgets.
- **Age rating:** expected 16+ (Section 6.1 decision 1 stands). Custom taunts are user-generated content, so the questionnaire answers must account for them.

### 8.6 Next design step
Write the consolidated spec (`docs/kedro-ios-design.md`) and copy deck (`docs/kedro-ios-copy.md`) from Table First v2, the grafts in Section 3, and the decisions above. Then produce new mockups in the logo-led, dark-first look so the visual direction can be checked before any build.

**Done (October 28, 2026):** the consolidated spec is `docs/kedro-ios-design.md`, the three-level copy deck is `docs/kedro-ios-copy.md`, and the dark-first, logo-led mockups are `docs/design/mockups.html` (21 frames, with a Clean / Spicy / Unhinged toggle).
