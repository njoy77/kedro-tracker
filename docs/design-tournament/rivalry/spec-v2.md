# Kedro iOS: "Rivalry Engine" v2 design spec

Design tournament entry, round 2 · iOS 26 · SwiftUI · October 2026
Companion file: [`mockups-v2.html`](./mockups-v2.html) (26 frames plus a visual system board). Requirements: `docs/kedro-ios-prd.md` (v3.0, including the new Section 8). The round 1 files (`spec.md`, `mockups.html`) are unchanged.

> **Content note.** This spec quotes the app's Unfiltered copy, which swears on purpose (PRD 8). Every line has a Clean twin in the copy deck (Section 2.6).

---

## 0. Changes from v1

### 0.1 The brief change: adult aesthetic and voice

| Round 1 (judged childish) | Round 2 |
|---|---|
| Warm "racing-form paper" plus brass, cartoon horse heads in jockey-silk circles, rosettes with ribbons, a horseshoe "sparkle", a "gallop in" spring | **Members' Enclosure**: ink and bone, one oxblood accent, gilt kept for honours. Silks are flat geometric owners' colours with no faces. The horse is a monoline heraldic crest used in 4 places only. Honours are struck medals. A photo-finish wipe replaces particles. No confetti, no emoji, no bounce. |
| SF Pro Expanded and SF Pro Rounded score chips | **New York** (serif) for editorial headlines and the voice, **SF Pro** for UI and scores, **SF Mono** caps for racing-form metadata. All system families, nothing to download. |
| Polite "dash of the racetrack" copy ("Priya wins by a nose... well, by 1") | A contemporary, irreverent voice that swears where it lands: "Won by 1. From 16 back with one round to go. Stone-cold fucking killer." Every string has a Clean twin. There's a swearing budget per screen, a host "Clean for everyone" override, and a mature age rating (Section 2). |
| Rosettes, Paddock, Track, Rider, silks, Caught as everyday nouns | Plain game words everywhere. Equestrian words survive only in **honour names** and the crest. |
| Red/green deltas (turf green for −10) | Monochrome outcomes: sign, glyph, fill and word. Oxblood is the brand accent, so it never means "bad". |

### 0.2 Every round 1 must-fix and how v2 resolves it

| # | Judge(s) | Must-fix | Resolution in v2 | Where |
|---|---|---|---|---|
| 1 | native, table, product | Replace the 15 s auto-seal with an explicit Finish, a long idle fallback, and a timed window only for abandon | **Finish gate**: when planned rounds complete, every phone shows "That's the last round." with **Finish game** (any phone), **Fix a round**, **Add rounds**. If nothing changes for **15 minutes**, Kedro finishes the game. The seal time is deterministic: the last change's hybrid logical clock (HLC) plus 15 min, so offline phones agree. **Abandon** takes effect at once but any player can **Restore** it for 15 minutes (it can't be used by a sore loser to void a game). | 4.10, Frame 12 |
| 2 | native, table | Rebuild the leaderboard as a List: one primary value per row, secondary stats in a subtitle, no fixed column headers. Show AX5 | Stock `List`. Row = rank · silks · name over a subtitle ("23 games · 30% · up 1, passed Jordan") · rating as the single trailing value. No header row. At accessibility sizes the row stacks into three lines. | 5.3, Frames 16 and 17 (AX5) |
| 3 | native, table, product | Rename "Caught" to "Failed knock"; keep horse vocabulary to places and rewards; gloss brand words; plain tab names; drop "Rider" | Outcomes are **Successful / Tied / Failed knock**. Tabs: **Play · Rivals · Leaderboard · You**. "Track" and "Paddock" are gone; sub-threshold players are **Unranked (3 of 5)**. "Rider" is gone. Horse words remain only in honour names (Cold Open, Thrown Shoe, Dark Horse) where they're rewards, and every honour shows its rule in plain words. | 2.4, 5, 8c |
| 4 | native, table | Downgrade the self-report prompt; never push to a phone at the table running the Live Activity | No push notification exists for self-report. The **only** nudge is a silent Live Activity alert (`AlertConfiguration` with no sound) after 30 s if your hand isn't in. Scorekeeper games have no nudge at all. | 7.3, Frame 22 |
| 5 | native | Consistent sample data (one scoring mode per game); mock Rounds detail and the edit push, not just the diff | The whole sample game is **Scorekeeper** (Sam has no phone). Frames show the History page (grid and Changes), **Round 3 detail**, the edit **banner on another phone**, and the diff sheet. | Frames 05, 09, 10, 11 |
| 6 | native | Dynamic Island expanded within system height limits | Expanded is **150 pt** (limit 160): leading, trailing, center and a bottom region with top 4 and the last knock sentence. | 7.1, Frame 22 |
| 7 | table | Nearby card Join commits directly; no second button on the Join sheet | **Join** on the card seats you. The next screen is a waiting room ("You're in.") with the stakes strip and no button except a small "Leave table". Tap math fixed (Section 11). | 4.2, Frames 03 and 04 |
| 8 | table | Self-report: show "set by Jordan · Change" prominently; a conflicting "I knocked" needs agreement | The knocker row reads **"Jordan knocked · set by Maya · Change"** in the header of the entry sheet. If a phone taps **I knocked** while another phone named someone else, the round can't complete until the named player's phone or a second phone confirms one of them. Both claims are logged. | 4.6 |
| 9 | table | Drop the time-sensitive push for anyone running a Live Activity; hide the storyline by default | Covered by #4. The live storyline line is **removed**. The live screen shows only standings, the last-round sentence and one button. Stakes appear before play (lobby) and after (game end). | 4.4 |
| 10 | table | Mid-game Lock Screen widgets must show pre-game rivalry and rank values | Widgets reload only when a game finishes. Frame 21 (mid-game) shows Maya 11–7 and #5; Frame 23 (after) shows 11–8 and #4. | 7.2, Frames 21 and 23 |
| 11 | product | Phrase every stakes line as conditional or approximate against a stated assumption | Stakes are either **facts** ("Maya's up 11–7 on you", "Game 5 of 5") or **estimates** with a stated basis ("A win at a table like Friday's would likely put you back past Jordan", footnoted "Estimate · assumes Friday's five"). Projected ranks are never stated as fact. | 8b, Frame 02 |
| 12 | product | Deterministic resolution when two phones record the same round number offline; show the loser with "Use this version" | The round record with the **lower HLC** (ties broken by device ID) applies. If both copies are identical they merge silently. If they differ, the other copy is kept in Changes as **Not applied** with **Use this version**, which becomes an ordinary logged edit. | 4.9, Frame 09 |
| 13 | product | Live storyline opt-in, never while entry is open | Removed entirely during play (see #9). | 4.4 |
| 14 | table | Abandon needs a longer restore window | 15-minute **Restore** on every phone, logged. | 4.10 |
| 15 | native, table, product (weaknesses) | Too much custom chrome; live game split into segments with the audit trail hidden | Stock `List`, `Form`, `Picker`, sheets. Glass only on controls. The segmented Standings / Rounds / Log is replaced by one live screen plus a **History** page where the grid and the full Changes log scroll together. | 4.4, 4.8 |
| 16 | native | The Join-sheet stakes copy is too long for a one-tap moment | Stakes moved off the tap path: the Join button stands alone on the card; stakes show on the waiting screen while people wait anyway. Max two lines. | Frames 03 and 04 |

### 0.3 Ideas adopted from other entries

Adopted because they serve the rivalry loop or fix a v1 weakness: explicit Finish gate with a 15-minute idle fallback and a deterministic seal time (table-first, ambient); one-page History with grid and Changes (table-first); deltas in signs and words, never red/green (table-first); VoiceOver announcements only when VoiceOver is running, plus rotors for Edited rounds and Knocks (table-first); Live Activity alert as the only self-report nudge (table-first); Watch mode for late arrivals, auto-queued for the rematch (table-first); a claim token on the guest's own device (table-first); abandon Restore window (playful); glass only on controls (playful); guest identity reuse by name (playful); rematch rotates the starting seat (playful); per-table silks de-duplication (playful); knocker-first entry (ambient); a ControlWidget for Start a table (ambient, v1); a landscape table display for the middle of the table (ambient), which defaults to Clean voice.

Not adopted: an App Clip (deferred to v1.1; the "join as guest" path covers it), learner hints per seat (Table Coach already does this per phone), the μ−3σ rating (see 8a).

---

## 1. Design thesis

**Every game is a chapter in a rivalry.** Nobody comes back to a score tracker. They come back to find out whether they finally beat Maya, whether they cracked the top five among their people, and how many games until they're ranked. Kedro's job at the table is to be invisible: fast, exact, trusted. Between games its job is to turn those exact numbers into stories worth returning for, and to say them the way your friends would.

> **Stakes → Play → Payoff → Next stakes.** Before a game, Kedro shows what's on the line. During it, it shuts up. At the end, it pays off every storyline at once, with some attitude. Then it hands you the next reason to play.

### What changes in v2, in one paragraph
The loop is the same. The skin and the mouth are new. v1 dressed the loop as a county fair: rosettes, cartoon horses, warm paper. v2 dresses it as a **members' enclosure on a late race night**: ink, bone, oxblood, a little gilt, serif headlines like a racing paper's front page, and a voice that sounds like the friend who keeps score and won't let you forget it. The horse survives as heraldry and as owners' silks: a crest, not a character.

| PRD goal | How the Rivalry Engine delivers it |
|---|---|
| **Fast table flow** | During play: one list, one sentence about the last round, one button. About 13 taps to record a 5-player round. Nothing about rivalries, ranks or honours appears until the game is finished. |
| **Everyone joins** | Nearby tables appear on Play by themselves; distance separates your table from the next one; **Join** is one tap. Guests get silks and are first-class from round 1. |
| **People come back** | Play opens on **Since you last looked** (rank moves, receipts, guest claims) and **Next game** stakes. Rivals, Leaderboard and You carry gap-to-level and gap-to-rank goals. **Receipts** (pre-written trash talk) give rivals a reason to poke each other between games. |
| **Spreads to new tables** | The 5-game **debut** is a public moment at the table. Guests get a claim card that sells their own story. Hosts earn **Breaking In** when a guest claims. Learning is built into every "Why?". |

### Principles
1. **Stories between games, silence during them.** No toasts, rank pop-ups, receipts or notifications mid-game.
2. **One number to climb.** One rating, one rank (8a).
3. **The math is never a joke.** Every roast sits above a plain rule sentence.
4. **Every fix is public; nothing is permanent until someone says so** (or 15 quiet minutes pass).
5. **Roast the play, never the person.** (Section 2.)
6. **Unranked is a welcome, not a waiting room.** Progress to 5 is visible everywhere.

---

## 2. Voice & copy

### 2.1 Who Kedro sounds like
The friend at the table who keeps score: quick, dry, a bit of a shit-stirrer, fluent in current slang without trying too hard, and never actually mean. It swears the way adults swear over drinks: for rhythm and punchlines, not for volume. It's on everyone's side and no one's side.

### 2.2 Tone principles
1. **Roast the play, never the person.** Targets: knocks, hands, scores, luck, streaks, slowness, bravado. Never: bodies, looks, gender, race, ethnicity, sexuality, religion, disability, age, class, intelligence, money. No slurs in any language, ever, including "reclaimed" ones. No gendered insults (no "bitch", "pussy", "man up"). Banned-term list lives in the string-lint step of CI.
2. **Names, not pronouns.** Kedro doesn't know anyone's pronouns, so copy uses the display name ("Tie, so Jordan eats the hand"), "you", or "they".
3. **Controls stay plain.** Buttons, navigation titles, rule sentences, VoiceOver labels, error recovery steps and settings say exactly what happens: "Save round", "Finish game", "Use this version". Attitude lives in the line above the control, never in it.
4. **The math is always stated plainly.** Every knock line pairs a voice line (New York italic) with the rule (SF Pro, secondary): "Maya, what the fuck." / "Someone had a lower hand, so the knocker scores hand + 10: 5 + 10 = 15."
5. **One swear per string, two per screen.** Each string is tagged `profane` or not. A screen renders at most two profane strings, chosen by priority (outcome > celebration > stakes > empty state > ambient). Lower-priority strings on that screen fall back to their Clean twin. This keeps swearing a punchline, not wallpaper. Frames 13 and 25 show the fallback. Exempt: the receipt picker (you're choosing what to send).
6. **Punch at the moment, not the pattern.** Copy can roast one bad knock or a 106. It never piles onto a losing streak, someone being new, or someone not playing lately. No guilt, no "we miss you".
7. **New players get warmth with edge.** Learn, Table Coach and validation explain first and joke second. Nobody is roasted for not knowing a rule.
8. **Slang with a shelf life is rotated.** Strings ship in the String Catalog with a `voice` variant (Unfiltered, Clean). Copy is reviewed each release; anything that's aged badly is replaced.
9. **What leaves the phone defaults to Clean.** Share images, the table display, messages to guests and anything sent to someone who hasn't picked a voice use Clean unless you change it (Settings → Voice → Clean on shared screens).
10. **The recipient decides.** Receipts and notifications are rendered in the recipient's voice setting, never the sender's.

### 2.3 Cleaner-language option

- **Voice: Unfiltered / Clean**, chosen on the welcome screen ("How filthy do you want it?") and changeable in **You → Settings → Voice**. Stored per account and synced; guests use the device setting.
- **Clean keeps the attitude**: same jokes, same rhythm, same target, swaps the swear ("Stone-cold fucking killer" → "Stone-cold killer"; "Who gives a shit" → "No problem").
- **Clean on my Lock Screen** (default off): notifications and the Live Activity use Clean while the phone is locked, for people whose phone sits face-up at work.
- **Clean on shared screens** (default on): share images, the landscape table display, messages to guests.
- **Tables I host**: "Each player's own setting" (default) or **"Clean for everyone"**. A table forced Clean is Clean on every phone for that game (lobby, live game, game end, the Live Activity), shown as "Table voice: Clean" in the lobby. Anyone can see the setting; only the host can change it. The strictest setting wins.
- Implementation: a `VoiceStyle` environment value resolved from (table override ?? player setting) and per-surface rules; strings are `LocalizedStringResource`s keyed `knock.failed.line` with `.unfiltered` and `.clean` variants; a `ScreenVoiceBudget` preference collects profane strings per screen and downgrades extras.

### 2.4 Age rating
- App Store age rating questionnaire: **Profanity or Crude Humor: Frequent/Intense**; **Alcohol references: Infrequent/Mild** (copy mentions drinks); no user-generated free text (receipts are pre-written), so no unrestricted web or chat. Under Apple's current age tiers this lands in the **mature tier** (expected 16+, and we'd accept 18+ if Apple's mapping places it there).
- The rating covers the app's capability, so **Clean mode does not change the rating**. Settings states this plainly (Frame 24).
- Because there's no free text and no messaging between strangers, there's no moderation surface to staff in v1. Receipts can only go to someone you've shared a finished game with, one per game, and can be muted per person.

### 2.5 Game vocabulary (plain) vs brand vocabulary (flavour)

| Concept | In-app word | Never |
|---|---|---|
| Knock with strictly lowest hand | **Successful knock** (◆ −10) | Clean, nailed, rosette |
| Knock tied for lowest | **Tied knock** (= hand) | Matched, dead heat |
| Someone lower than the knocker | **Failed knock** (◇ +10) | Caught, busted (only in voice lines) |
| Leaderboard | **Leaderboard** | Track |
| Under 5 games | **Unranked · 3 of 5** | Paddock |
| Achievements | **Honours** (brand word, glossed as "honours: awards for milestones and moments" on first view) | Rosettes, badges |
| Shared win | **Shared win** (voice may say "dead heat") | |
| Player identity colours | **Silks** (glossed on first edit: "your racing colours") | |

### 2.6 Copy deck (81 strings)

Placeholders in braces. `—` in the Clean column means the Unfiltered line contains no profanity and ships unchanged (listed because it's part of the voice).

| ID | Surface | Unfiltered | Clean |
|---|---|---|---|
| **Onboarding** ||||
| O1 | Welcome headline | Keep score. Talk shit. Repeat. | Keep score. Talk trash. Repeat. |
| O2 | Welcome body | Kedro does the math, so nobody has to trust whoever's three drinks deep. | — |
| O3 | Voice picker title | How filthy do you want it? | How spicy do you want it? |
| O4 | Guest path line | Just here to play? Sit the hell down. | Just here to play? Pull up a chair. |
| O5 | Local network primer | We find the table you're sitting at. We don't track where you are, we're not that creepy. | — |
| O6 | New to Cambio toggle | New to Cambio? We'll teach you as you play. Nobody's judging. Much. | — |
| **Joining and stakes** ||||
| J1 | Nearby card | {host}'s table is right there. Get in. | — |
| J2 | Joined, waiting | You're in. Shuffle up, {host}'s still fucking around with the settings. | You're in. Shuffle up, {host}'s still fiddling with the settings. |
| J3 | No tables nearby | Dead in here. Start a table or find better friends. | Quiet in here. Start a table or round up some friends. |
| J4 | Stakes: 5th game | Game 5. Finish this and you're on the board. Don't fuck it up. | Game 5. Finish this and you're on the board. Don't blow it. |
| J5 | Stakes: rival leads you | {rival}'s up {a}–{b} on you. Embarrassing, frankly. | {rival}'s up {a}–{b} on you. Not a great look. |
| J6 | Stakes: level | You and {rival}: {a}–{a}. Somebody's got to blink. | — |
| J7 | Stakes: estimate | A win at a table like {when}'s would likely put you past {name}. Likely. Don't get cocky, it's annoying. | …Likely. Stay humble. |
| J8 | Since you last looked: passed | {name} passed you for #{n} on {day}. Rude as hell. | {name} passed you for #{n} on {day}. Rude. |
| J9 | 9th player blocked | Eight players max. Someone's gotta sit the fuck out. | Eight players max. Someone's sitting this one out. |
| **Live game: knocks and hands** ||||
| K1 | Successful knock | {knocker} knocked on {hand} and nobody had shit. | {knocker} knocked on {hand} and nobody could touch it. |
| K2 | Tied knock | {knocker} knocked on {hand}. {other} had {hand} too. Tie, so {knocker} eats the hand: {hand}. Bold. | —  (ships as is) |
| K3 | Failed knock | {knocker} knocked on {hand}. {lower} had {lowHand}. {knocker}, what the fuck. | …{knocker}, what was that. |
| K4 | Failed knock, by a lot (gap ≥ 8) | {knocker} knocked on {hand} into a {lowHand}. Absolute clown shit. | {knocker} knocked on {hand} into a {lowHand}. Absolute circus. |
| K5 | Red King hand | Red King. {name}'s sitting on {hand} like a smug bastard. | Red King. {name}'s sitting on {hand} looking very smug. |
| K6 | Both red Kings (−2) | Both red Kings. −2. Filthy. | Both red Kings. −2. Ruthless. |
| K7 | Zero hand | Zero. Not a goddamn point. | Zero. Not a single point. |
| K8 | Rule line, successful (plain, always shown) | Strictly lowest hand, so the knocker scores −10 flat. The {hand} is ignored. | — |
| K9 | Rule line, tied | Tied for lowest, so the knocker scores their hand. | — |
| K10 | Rule line, failed | Someone had a lower hand, so the knocker scores hand + 10: {hand} + 10 = {score}. | — |
| **Live game: entry, edits, sync** ||||
| L1 | No knocker chosen | Who the hell knocked? Every round has exactly one. | Who knocked? Every round has exactly one. |
| L2 | Hand below −2 | Bullshit. The lowest possible hand is −2 (both red Kings). | Not possible. The lowest possible hand is −2 (both red Kings). |
| L3 | Hand above 60 | {value}? Christ. Double-check that. | {value}? Yikes. Double-check that. |
| L4 | Undo toast | Round {n} saved. Fat-fingered it? | — |
| L5 | Edit banner, your score affected | {editor} fixed round {n}. Your knock just went to shit. | {editor} fixed round {n}. Your knock just fell apart. |
| L6 | Edit banner, general | {editor} fixed round {n}. Check the receipts. | — |
| L7 | Edit review subtitle | Here's who this screws. | Here's who this hurts. |
| L8 | Self-report Live Activity nudge | Round {n}: your hand. Everyone's waiting on your slow ass. | Round {n}: your hand. Everyone's waiting on you. |
| L9 | Self-report knocker conflict | Two knockers? Pick one, you animals. | — |
| **Ending** ||||
| F1 | Finish gate | That's the last round. Finish it, or fix your shit first. | That's the last round. Finish it, or fix a round first. |
| F2 | Abandon confirm | Abandon this game? It stays in history, marked Abandoned, and counts for fuck all. Your name goes on it. | …and counts for nothing. Your name goes on it. |
| F3 | Abandon restore banner | {name} abandoned the game. Bullshit? Restore it ({mm:ss}). | {name} abandoned the game. Disagree? Restore it ({mm:ss}). |
| **Game end** ||||
| W1 | Winner, comeback | Won by {m}. From {x} back with one round to go. Stone-cold fucking killer. | …Stone-cold killer. |
| W2 | Winner, wire to wire | Led every round. Didn't even break a sweat, the smug shit. | Led every round. Didn't even break a sweat. |
| W3 | Shared win | Shared win. {a} and {b} split it. Run it back and settle this shit. | …Run it back and settle this. |
| W4 | You lost by 1 | Lost by 1. One. Fucking. Point. | Lost by 1. One. Single. Point. |
| W5 | Last place | {name} finished on {score}. Rough fucking night. | {name} finished on {score}. Rough night, champ. |
| W6 | Your story: beat your nemesis | You finished ahead of {rival}. Still behind {a}–{b}, but less pathetically. | You finished ahead of {rival}. Still behind {a}–{b}, but closing. |
| W7 | Highlight: comeback | {x} back with one to play. {name} said fuck it and knocked. | {x} back with one to play. {name} said why not and knocked. |
| **Leaderboard eligibility** ||||
| E1 | 1 of 5 | Game 1 of 5 done. Four more and the leaderboard has to acknowledge your ass. | Game 1 of 5 done. Four more and the leaderboard has to acknowledge you. |
| E2 | 4 of 5 | 4 of 5. One more game and you're ranked. Go find a table, damn it. | 4 of 5. One more game and you're ranked. Go find a table. |
| E3 | Debut (game 5) | You're on the board, you magnificent bastard. | You're on the board, you magnificent menace. |
| E4 | Unranked section header | Unranked. Warming up, or just scared. | Unranked. Still warming up. |
| E5 | Global unranked count | {n} people still haven't played five games. Get on with it, for fuck's sake. (Lovingly.) | {n} people still warming up. We see you. |
| **Notifications** (all Passive or Active; none Time Sensitive) ||||
| N1 | Added to a table | {host} added you to the table. Get your ass over here. | {host} added you to the table. Get over here. |
| N2 | Game results (you weren't looking) | {winner} won by {m}. You came {place} and you'll be pissed about it for a week. | …and you'll be salty about it for a week. |
| N3 | Guest claimed | {guest} claimed their history. Your {a}–{b} over {guest} is now official as hell. | …is now officially official. |
| N4 | Ranked outside a game (claim pushed you to 5) | You're ranked: #{n} among your people. Holy shit, look at you. | You're ranked: #{n} among your people. Well, look at you. |
| N5 | Receipt received | {sender} sent you a receipt | — (the receipt text follows the recipient's voice) |
| N6 | Weekly report (opt-in) | Your week: {g} games, {w} wins, {f} failed knocks. Stop knocking on shit hands. | …Stop knocking on bad hands. |
| **Receipts** (pre-written trash talk, sent to a rival after a shared finished game) ||||
| R1 | You won the game | Scoreboard, dickhead. | Scoreboard, buddy. |
| R2 | You're chasing them | Gap's {n}. Sleep with one eye open, asshole. | Gap's {n}. Sleep with one eye open. |
| R3 | They failed a knock | Knocking on {hand} is a choice. A shit choice. | Knocking on {hand} is a choice. A bad choice. |
| R4 | Rematch | Run it back. I'll go easy. (I fucking won't.) | Run it back. I'll go easy. (I won't.) |
| R5 | They beat you | Enjoy it, you lucky bastard. Won't happen again. | Enjoy it, you lucky so-and-so. Won't happen again. |
| **Honours** (name stays; description is plain rule + voice line) ||||
| A1 | Cold Open (first successful knock) | First successful knock. Felt fucking great, didn't it. | First successful knock. Felt great, didn't it. |
| A2 | Thrown Shoe (first failed knock) | Knocked on a shit hand and paid for it. Happens to everyone. | Knocked on a bad hand and paid for it. Happens to everyone. |
| A3 | Turned the Tables (ahead of nemesis) | Finished ahead of your nemesis. About fucking time. | Finished ahead of your nemesis. About time. |
| A4 | Dark Horse (last at halfway, won) | Dead last at halfway. Won anyway. Disrespectful as hell. | Dead last at halfway. Won anyway. Disrespectful. |
| A5 | Photo Finish (won by 1) | Won by a single point. Talk your shit, you've earned it. | Won by a single point. Talk your trash, you've earned it. |
| A6 | Breaking In (a guest you played with claims) | A guest you played with signed up. You're a goddamn recruiter. | A guest you played with signed up. You're basically a recruiter. |
| A7 | Front Runner (#1 among your people) | #1 among your people. Everyone hates you now. Good. | — |
| Y1 | Profile nemesis card | {rival}'s finished ahead of you {n} times. Get your shit together. | …Get it together. |
| RU1 | Rules sheet, opened from Why? | Here's the math, no bullshit. | Here's the math, no nonsense. |
| **Empty states** ||||
| ES1 | Rivals, none yet | Go get your ass kicked by someone. | Go lose to someone. It builds character. |
| ES2 | History, no games | No games yet. What the hell are you doing with your evenings? | No games yet. What are you doing with your evenings? |
| ES3 | Honours, none | Zero. The shelf's bare as hell. | Zero. The shelf's looking bare. |
| ES4 | Receipts, none | Nobody's talked shit to you yet. Give it time. | Nobody's talked trash to you yet. Give it time. |
| **Errors** ||||
| ER1 | Claim code already used | Already claimed. Either you did this already or you're not {guest}, you sneaky shit. | Already claimed. Either you did this already or you're not {guest}, you sneaky so-and-so. |
| ER2 | Claim code invalid | That code's bullshit. Check it and try again. | That code doesn't work. Check it and try again. |
| ER3 | Server error (game unaffected) | Our servers shat the bed. Your game's safe on this phone. | Our servers tripped over. Your game's safe on this phone. |
| ER4 | Can't start: under 3 players | Cambio needs 3. Two people is just a staring contest. | — |
| **Offline** ||||
| OF1 | Table link, no internet | No internet? Who gives a shit. Phones at a table talk to each other directly. | No internet? No problem. Phones at a table talk to each other directly. |
| OF2 | Phone out of reach | {name}'s phone fucked off somewhere. Their entries catch up when it's back. | {name}'s phone wandered off. Their entries catch up when it's back. |
| OF3 | Rank pending | Rank updates when you're back online. Patience, damn it. | Rank updates when you're back online. Patience. |
| OF4 | Synced after offline | Synced. Not a damn thing lost. | Synced. Nothing lost. |

Every Unfiltered string above passes the principles in 2.2: one swear max, aimed at a play, a score or a phone, never at who someone is.

---

## 3. Visual system: "Members' Enclosure"

The reference points are a racing paper's front page, owners' silks in a paddock, a private members' card room, and a struck commemorative medal. Restraint is the point: one accent, hairlines instead of shadows, serif headlines, generous black.

### 3.1 Palette

Semantic tokens in the asset catalog, each with Any, Dark and Increase Contrast variants. Contrast was checked with the WCAG formula.

| Token | Light | Dark | Use | Contrast |
|---|---|---|---|---|
| `background` | Bone `#F2EEE6` | Ink `#0A0A0E` (existing `BrandBackground`) | Screens | |
| `surface` | Paper `#FBFAF7` | Stable `#141419` | Grouped content, sheets | |
| `elevated` | `#FFFFFF` | Saddle `#1D1D23` | Keys, selected segment, gate sheet | |
| `fill` | Vellum `#E6E0D4` | `#25252C` | Secondary buttons, tracks | |
| `ink` | Graphite `#17171C` | Bone `#F2EEE6` | Primary text, successful-knock fill | 15.4:1 / 17.1:1 |
| `secondary` | Smoke `#67635B` | Smoke `#9B978E` | Secondary text, metadata | 5.2:1 / 6.8:1 |
| `accent` (text) | Oxblood `#A3122A` | Oxblood lit `#F0485E` | You, the current round, links | 6.8:1 / 5.5:1 |
| `accentFill` | `#A3122A` | `#C21F38` | Primary buttons (white label), toggles | white 7.8:1 / 5.9:1 |
| `gilt` (text) | `#7D6129` | `#CDAE6C` | #1, winner, honours | 5.0:1 / 9.3:1 |
| `giltLeaf` | `#B8975A` | `#CDAE6C` | Medal faces, leader tick, crest | ink on it 6.5:1 |
| `hairline` | Graphite 13% | Bone 12% | Separators, outlines | |

**Silks colours** (10, muted and grown-up): Oxblood `#7A1424`, Navy `#1F2C4A`, Bottle `#1E4634`, Ochre `#C49A45`, Bone `#EDE6D6`, Jet `#121214`, Slate `#5A6573`, Plum `#4E2A45`, Tan `#A57C55`, Pale Blue `#7FA3C2`.

**Rules**
- Oxblood (the brand red, refined from the web app's `#E63946`) is the **only** accent. It marks the primary action, *you*, and the current round. It never means "bad".
- **Lower is better in Cambio**, so outcome and delta colours would lie. Outcomes are told by **sign, glyph, fill and word**: Successful = solid ink badge "◆ −10"; Tied = outline "= hand"; Failed = hatched outline "◇ +10". Deltas are signed numbers in secondary text.
- Gilt appears only for #1, the winner, the leader tick and honours. Never on buttons.
- Dark is the hero (people play at night), light is fully designed (Frames 06/07 show the live game in both).

### 3.2 Type scale

All system families, so nothing is downloaded and everything scales with Dynamic Type. In SwiftUI: `.font(.system(.largeTitle, design: .serif, weight: .semibold))`, `.monospaced()` for metadata, `.monospacedDigit()` on every score. In the HTML mockups these map to `ui-serif`, `system-ui` and `ui-monospace` with Georgia and Menlo fallbacks off-Apple; that's the inline-safe justification for leaving a pure `system-ui` stack.

| Role | Family | Size / weight (Large default) | Text style it scales with | Use |
|---|---|---|---|---|
| Display XL | New York | 52–64 / Semibold, −3% tracking | `.largeTitle` via `@ScaledMetric` | Welcome, winner name, debut |
| Display | New York | 36 / Semibold | `.largeTitle` | Screen titles (Play, Leaderboard), set as a custom scroll header |
| Title | New York | 28–32 / Semibold | `.title` | Sheet titles, "That's the last round." |
| Voice | New York Italic | 17 / Regular | `.body` | Every voice line, receipts |
| Score XL | SF Pro | 30–34 / Semibold, tabular | `.largeTitle` scaled | Cumulative scores |
| Rating hero | SF Pro | 84 / Semibold, tabular | `.largeTitle` scaled | Debut rating |
| Headline | SF Pro | 17 / Semibold | `.headline` | Names, row titles |
| Body | SF Pro | 15–17 / Regular | `.body` | Copy, rule sentences |
| Footnote | SF Pro | 13 / Regular | `.footnote` | Rule lines, subtitles |
| Form | SF Mono caps | 11 / Regular, +8% tracking | `.caption` | Metadata: "ROUND 7 OF 10 · TABLE MANE" |

Rank numerals in standings use New York lining figures, like a race card. Inline navigation titles stay SF Pro (system nav bar).

### 3.3 The horse motif

- **The crest.** A monoline heraldic horse head in profile inside a double roundel, drawn at a 1.6 pt stroke in gilt. It appears in exactly four places: the app icon, the welcome screen, the Live Activity leading glyph, and empty states (in secondary grey). It never animates, blinks or talks.
- **Owners' silks** are the identity system (a "silks" is a racing owner's colours). Each player gets one of 11 flat geometric patterns (hoops, quarters, chevron, sash, cross-belts, diamonds, stripes, braces, cross, spot, halves) in two silks colours, generated from a name hash and editable in You. No faces, no initials needed. Silks are **de-duplicated per table**: if two players at one table would share a pattern, the later joiner's silks shift pattern for that game, so 8 players are always distinguishable without colour. Guests wear a dashed ring.
- **Race-card typography**: lining serif rank numerals, SF Mono form lines, form figures ("2 4 1 3 2", latest first) on profiles.
- **Furlong ticks** replace horseshoe pips for round progress: thin bars, recorded = ink, current = oxblood, planned = hairline.
- **Honours are struck medals**: a gilt disc with a double rim and a numeral or card glyph struck into it ("−10", "1pt", "K♦", "3W"). Locked honours are a hairline outline with a gilt progress arc. Honour names keep the equestrian flavour (Cold Open, Thrown Shoe, Dark Horse, Photo Finish, Triple Crown, Breaking In, Stayer).
- **The photo finish** is the one signature motion: a vertical hairline sweeps across the winner card like a finish-line camera, revealing the name.

### 3.4 Iconography
- SF Symbols at **light/regular** weight, monochrome rendering. Tabs: `rectangle.portrait.on.rectangle.portrait` (Play), `figure.fencing` or a custom crossed-crops symbol (Rivals), `list.number` (Leaderboard), your silks (You), and the system search tab.
- Custom symbols, built from the SF template so they follow weight and Dynamic Type: **crest**, **knock** (two knuckle taps), **outcome diamonds** (◆ solid, = , ◇ hatched), **medal**, **furlong tick**.
- No emoji anywhere in the UI or copy. No filled cartoon glyphs.

### 3.5 Shape, surface and glass
- Radii: 10 (chips, keys), 18 (surfaces), capsules for buttons (system Liquid Glass shape). Sheets use system corner radii.
- **Hairlines, not drop shadows**, to separate rows and stats.
- **Liquid Glass only on the controls layer**: tab bar, toolbar buttons, banners, toasts, Lock Screen widgets. Scores, standings and rule sentences sit on solid surfaces so they're always legible.
- Buttons: oxblood `.glassProminent` with a white label for the one primary action per screen; `fill` for secondary; outline for tertiary.

### 3.6 Motion

| Moment | Motion | Duration / curve | Reduce Motion |
|---|---|---|---|
| Round saved | Rows re-sort with a damped slide (no overshoot); scores roll with `.contentTransition(.numericText())` | `.smooth(duration: 0.35)` | Crossfade, numbers swap |
| Undo toast | Slides up from the button, then retracts after 5 s | `.snappy` | Fade |
| Edit lands on another phone | Banner drops in; edited round's row in History gets a 1 s ink underline | `.smooth` | Fade |
| Finish gate | Sheet rises; no countdown ring (it's 15 minutes, not 15 seconds) | System sheet | System |
| Winner | **Photo-finish wipe**: a 1 pt hairline sweeps left to right across the card, the winner's name is revealed behind it, gilt rule draws in; `.sensoryFeedback(.success)` | 650 ms, `KeyframeAnimator` | Crossfade, haptic kept |
| Debut | Five furlong ticks fill in sequence, then the rating counts up from 1500 | 900 ms | Final state shown |
| Honour earned (at game end only) | Medal turns over once (`rotation3DEffect`), catches light (a single specular gradient pass) | 500 ms | Static medal |

Nothing bounces. No confetti, no particles, no looping animation anywhere.

---

## 4. Information architecture and key flows

### 4.1 Structure
`TabView` with the iOS 26 `Tab` API and the Liquid Glass tab bar:

| Tab | Content |
|---|---|
| **Play** | Start a table · nearby tables (At your table / Other tables nearby) · Since you last looked · Next game · Run it back · Learn Cambio · Got a claim code? |
| **Rivals** | Rivalries sorted by how close they are, nemesis pinned, received receipts, played-with list, head-to-head detail |
| **Leaderboard** | Your people (default) / Global, Unranked section, Spotlights |
| **You** | Profile, stats, knock profile, honours, history, silks, Settings (incl. Voice) |
| **Search** (`Tab(role: .search)`) | Any Kedro player → profile → head-to-head |

The live game is a `fullScreenCover` that collapses into a `tabViewBottomAccessory` mini bar ("R7/10 · You T2 · 27"). Rules are a sheet reachable from the live toolbar (book), every "Why?", Learn, and You → Rules.

Navigation map:
```
Welcome (voice + sign in / guest) → Main TabView
Play → Start a table → Lobby ─┐
Play → nearby card · Join ─────┼→ Waiting screen → Live game (cover)
Play → Run it back → Lobby ────┘     ├ Round entry (sheet)
                                     ├ History (push): grid + Changes → Round detail → Edit → Review
                                     ├ Rules (sheet) · Game menu (Add rounds / End early / Abandon / Scorekeeper / Table display)
                                     └ Finish gate → Game end → Debut (if game 5) → Rematch / Done
Rivals → Head-to-head → Send a receipt · Play again with {rival}
Leaderboard → Profile → Head-to-head
You → Stats · Honours · History · Silks · Settings → Voice
```

### 4.2 Joining
- **Transport**: Network framework peer-to-peer (`NetworkListener` / `NetworkBrowser` / `NetworkConnection` with peer-to-peer enabled, Bonjour over AWDL, no Wi-Fi network or internet needed). `MultipeerConnectivity` is the fallback.
- **Same-table filter**: peers exchange `NIDiscoveryToken`s and run an `NISession`. Within about 3 m = **At your table**; farther = **Other tables nearby**. Phones without UWB rank by signal and show the 4-letter **table word** (MANE, TACK, REIN, SPUR) the host reads out.
- Host advertises only while a lobby or live game is open; others browse only while Play is visible.
- **Returning players**: the card's **Join** seats you immediately (Frame 03). The waiting screen (Frame 04) shows seats filling and up to two stakes lines, with no further action. Host taps **Start game**.
- **Guests without phones**: host → `+` → Add guest → name → Add. If the name matches a guest from your shared history ("Sam · guest · 3 games with you"), Kedro offers to reuse that identity so one claim later brings everything.
- **Guests with the app but no account**: "Join a table as a guest" on Welcome; they join from the card. Their device holds the guest identity's claim token, so signing in later claims automatically.
- **Mid-game arrivals**: a seated player's late phone opens straight into the game; a guest can take over their own seat ("Sam's phone wants Sam's seat · Allow" on any phone); a new person after round 1 gets **Watch** (read-only standings) and is auto-seated in the rematch. Kedro doesn't invent a catch-up score (that would be a house rule).
- **Fallback without proximity**: Run it back prefills the lobby; added players get N1 and join in one tap.

### 4.3 Lobby (Frame 05)
Seats (3–8, drag to reorder; order sets scorekeeper entry order) · Rounds chips 5/8/10/12 (default: last game) · Scoring (Scorekeeper / Self-report, with a recommendation and its reason) · Scorekeeper · **Table voice** (host only) · one-line Stakes. **Start game** is disabled under 3 seats (ER4). Rematch rotates the starting seat.

### 4.4 The live game (Frames 06, 07)
- **Header**: collapse, "Round 7 of 10", Rules, menu. Furlong ticks. Sync pill: `Live · 4 phones`, `Table link` (no internet), `{name} out of reach`, `Uploading 3`, `Synced`.
- **Standings** (`List`): rank (T2 for shared), silks, name, a subtitle (Leads / 3 back / Guest), cumulative score, and the last-round delta as a signed number, or the knocker's outcome badge. Your row carries a 3 pt oxblood leading rule.
- **Last round card**: the knock in voice (K1–K7) and the rule in plain words (K8–K10), with **Why?**.
- **History & changes** row with a count. One tap pushes the History page.
- **Primary button**: "Record round 7" (anyone can record; first save wins, see 4.9).
- Nothing else. No storyline, no stakes, no rank changes, no honours, no receipts. The screen stays awake.

### 4.5 Recording a round, scorekeeper (Frame 08)
Sheet titled "Round 7". **Who knocked?** first (silks row); Save stays disabled until one is chosen (L1). Hands list in table order with a live `hand → score` preview; custom keypad with **−**, auto-advance after two digits, **Next**, **Cards** (a card picker that sums and teaches values), and a tall **Save round** key. Validation: below −2 is blocked (L2), above 60 asks (L3). As soon as all hands are in, the outcome line resolves in voice with the rule underneath. On save: haptic, rows re-sort on every phone, and a 5-second **Undo** toast (L4); the undo is logged.

### 4.6 Recording a round, self-report
- The round opens on every phone when the previous one is saved. Each player enters their own hand; **I knocked** is a shortcut for the knocker.
- The sheet header always shows the knocker and who set it: **"Jordan knocked · set by Maya · Change"**.
- **Conflicting knocker**: if any phone's "I knocked" disagrees with the named knocker, the round can't complete. Every phone shows "Two knockers? Pick one, you animals." (L9) with both names; it resolves when the named knocker's phone confirms, or when a second phone agrees with one claim. Both claims and the resolution are logged.
- Values stay hidden until everyone has reported, then reveal together.
- Guests have an assigned reporter (default: host). Anyone can "Report for {name}" from the reported chips (logged).
- **Nudge**: the Live Activity alert L8, silent, after 30 s, once per round. No push notification.

### 4.7 Live standings and deltas
VoiceOver reads each row as one sentence: "Tied second. Noah, you. 27 points. Last round minus 10, successful knock. 3 behind the leader." Deltas are never colour-coded (3.1).

### 4.8 History and Changes, one page (Frame 09)
A pushed page that scrolls as one: the **score grid** (rounds × players, knocker's score in bold, outcome glyph, ✎ for changed rounds, Total row), then the **Changes** log, newest first, visible to everyone. Each entry gives who, when, before → after, and the downstream effect ("After round 5, Noah 1st → 3rd"). Entries include edits, extensions, end early, abandon/restore, scorekeeper changes, offline merges, superseded edits and not-applied duplicates. Tapping a grid row opens **Round detail** (Frame 10): every hand → score, the knock line and rule, that round's change history, **Edit round**.

### 4.9 Corrections, conflicts and offline
- **Editing**: Round detail → Edit round (same entry sheet, prefilled) → **Review** (Frame 11): every changed field, the re-run knock outcome, totals and standings impact, with the voice line L7 above it. **Save change**. Other phones get a banner (L5 when it changes your score, L6 otherwise) that opens the round. No push.
- **Model**: each game is an append-only event log (UUID, author, wall time, **HLC**). Every phone holds it and derives standings. Events flow peer-to-peer and upload when any phone is online; the server dedupes by UUID.
- **Same field edited on two phones**: highest HLC wins (device ID breaks ties); the other is kept as *superseded* in Changes.
- **Same round recorded on two phones offline**: the record with the **lowest HLC** applies (first recorded wins). Identical copies merge silently. Different copies: the other is kept as **Not applied** with **Use this version**, which creates an ordinary logged edit (Frame 09).
- **Out of reach** phones keep playing on their own log and merge on return; the pill names them (OF2).
- Finished games are immutable: Round detail has no Edit button and History reads "Finished 10:12 PM".

### 4.10 Finishing, ending early, abandoning (Frame 12)

| Action | Who | Behaviour |
|---|---|---|
| **Planned rounds complete** | Automatic | The **Finish gate** sheet appears on every phone: "That's the last round." (F1) with **Finish game**, **Fix a round**, **Add rounds**. The game stays editable until someone taps Finish game, or until **15 minutes** pass with no change. The seal time is `lastChange.hlc + 15 min`, so every phone (online or not) agrees on the moment it became permanent. |
| **Add rounds** | Any player | +1/+2/+5 or set a total; logged. |
| **End early** | Any player | Confirmation ("End after round 6 of 10? It counts fully in stats."), then the same Finish gate. |
| **Abandon** | Any player | Destructive confirmation (F2). The game is marked Abandoned at once and every phone shows a **Restore** banner for **15 minutes** (F3). Any player can restore. After 15 minutes it's permanently Abandoned: kept in history, excluded from all stats, ranks and honours. |

### 4.11 Game end (Frame 13)
Same moment on every phone after Finish: the photo-finish wipe, winner's silks, name in New York, the comeback line (W1–W3), final standings, **Your night** (different per phone: W4, W6, rank and rating change), **table news** (a debut, a broken streak), highlights one swipe below (successful knocks, lead changes, best round, last place W5). **Rematch** is primary; **Done**; **Share** renders a results card with `ImageRenderer` in Clean voice by default. The first time a player reaches this screen, it asks for notification permission in context ("Get told when a guest claims, or when someone sends you a receipt").

### 4.12 The debut (Frame 14)
When a player finishes game 5, every phone at the table shows the debut after the winner card: "You're on the board, you magnificent bastard." (E3) on the debutant's phone, "{name}'s ranked: debuts #6" on everyone else's. Rating revealed (computed since game 1), rank among your people and global, honours earned, and the next near-term goal.

### 4.13 Rematch
Same seats, order rotated by one, same rounds and mode, same guest identities, watchers seated. Other phones on the result screen see "Rematch? · Join" (one tap). The lobby stakes lead with the result: "Priya won the last one by 1."

### 4.14 Guest claim (Frame 26)
At game end each guest gets a hand-off card: the story first ("Sam, your 3 games and 4 rivalries are waiting. So is that 106."), a 6-character code (`K7Q-4MD`), QR, AirDrop and Message. It goes out in Clean voice unless the sender changes it. One code covers all of that guest's games and dies once claimed (ER1). Claiming re-derives stats, rivalries, honours and rating; people who played with the guest see "Sam claimed their history" in Since you last looked (N3), and the host earns **Breaking In**.

---

## 5. Stats, rivalries, leaderboard, honours

All numbers are derived from rounds and games (PRD 5). Nothing is a stored counter.

### 5.1 You (Frame 18)
Silks, name (New York), "#4 among your people · #1,206 global · 1559" (or "Unranked · 3 of 5" with ticks). **Form** figures (last 10 places, latest first). Hairline stat grid: games, wins, win rate, best, worst, avg per game, avg per round, current streak, longest streak. **Knocks**: rate (41 of 230 = 18%), success (61%), and a monochrome bar (25 successful solid · 4 tied outline · 12 failed hatched). **Nemesis** card with voice. Honours shelf. History (abandoned games greyed and tagged). Every stat has an info popover with the PRD definition.

### 5.2 Head-to-head (Frame 15)
Silks facing; a plain status headline (Maya leads / You lead / Level / New rivalry, under 3 games); **finished ahead** 8–11 with a split bar; games together 19; wins in shared games; knocks facing each other; last 10 as a form line; **gap to level** ("Finish ahead of Maya the next 3 times you share a table and it's level at 11–11"); **Send a receipt**; **Play again with Maya** (lobby with her pre-added).

**Receipts**: after a shared finished game, each player can send each other player at that table one receipt, chosen from 3–4 pre-written lines that fit the result (R1–R5). The recipient sees it in their voice, in Since you last looked and as a Passive notification (N5). Receipts can be muted per person. No free text in v1.

### 5.3 Leaderboard (Frames 16, 17)
A stock `List`. Scope picker: **Your people** (default) / **Global** (opens on "Around me", with a Top jump). Each row: rank numeral, silks, name, subtitle (games · win rate · movement in words), rating as the single trailing value. Your row has the oxblood rule and pins to the bottom edge when scrolled off. **Unranked** section below with progress ticks and no number (E4); Global shows a count and "one game away" list (E5). Unclaimed guests aren't listed. **Spotlights** (read-only cards below the list): knock success, longest streak, avg per round, most games. At AX sizes rows stack into three lines, the picker stacks vertically, and nothing truncates.

### 5.4 Honours (Frame 19)
Grid of medals, grouped Milestones · Knocks · Moments · Streaks · Social · Ranked. **Close** sits at the top (sorted by % complete). Earned: date and the game it came from. Locked: rule in plain words plus progress. Awarded only when a game is finished, never mid-game; claims award retroactively. Public on profiles.

---

## 6. Rules and learning (Frame 20)
- **Rules sheet**: Setup · Card values · Power cards · Sticking · Knocking · Round scoring · Game end, searchable. Round scoring holds the **knock calculator** (knocker's hand, lowest other hand → result, with the applied rule row highlighted). **Why?** from any round opens it prefilled. Voice appears once at the top ("Here's the math, no bullshit." / "no nonsense."); the rules themselves are plain.
- **Learn Cambio**: 5 lessons, about 90 s each (card values with flips; power cards on a 2×2 grid; sticking; the knock gamble slider; scoring a practice round on the real entry sheet). Finishing earns **Schooled** (a learning badge kept separate from game honours).
- **Table Coach**: for players who said they're new, or with fewer than 3 games: one tip between rounds on their own phone only ("Priya's −1: that's a red King"), never during entry; off after 3 games or with one tap. Coach copy is warm first (principle 7).

---

## 7. System surfaces

### 7.1 Live Activity and Dynamic Island (Frames 21, 22)

| Presentation | Content | Size |
|---|---|---|
| Lock Screen | Crest, "Noah's table", "Round 7 of 10", furlong ticks, top 3 plus you (place, silks, name, score, your last outcome badge), one plain last-round sentence | ~170 pt |
| Compact | Leading: your silks + `R7`. Trailing: `T2 · 27` | system |
| Minimal | `T2` in oxblood | system |
| Expanded | Leading `R7/10` + silks, center table name, trailing `T2 · 27`; bottom region: top 4 in two columns and the last knock sentence | **150 pt** (limit 160) |
| Ended | "Priya won by 1 · You 2nd · 34" for one hour, then dismissed | |

Updates arrive via ActivityKit push tokens when online and local `Activity.update` when offline. Scorekeeper games have no buttons and no alerts. Self-report games add an **Enter my hand** `Button(intent:)` and the silent L8 alert. The Live Activity follows the voice setting, or Clean when "Clean on my Lock Screen" is on.

### 7.2 Widgets and controls
WidgetKit with `AppIntentConfiguration`; data in the App Group; **reloaded only when a game finishes** (and on claims), so mid-game widgets always show pre-game values.

| Widget | Families | Content |
|---|---|---|
| Rival | Small, Medium, Lock Screen rectangular | You vs a chosen rival (default nemesis): "Maya 11–7 You" |
| Rank | Small, Lock Screen circular | "#5 people", or Unranked ticks "3 of 5" |
| Since last game | Medium | Rank move, newest honour, closest honour, last receipt |
| **Start a table** (`ControlWidget`) | Control Center, Lock Screen, Action button | Opens straight into a lobby |

App Intents: Start a table, Record round, Open my standings (Siri, Shortcuts, Action button).

### 7.3 Notifications

Rule: **nothing reaches a phone that's in a running game.** Everything except the Live Activity is held until the game is finished, then bundled.

| # | Notification | Level | When |
|---|---|---|---|
| N1 | Added to a table | Active | A host adds you directly (not when you joined yourself) |
| N2 | Game results | Active | Game finished and you weren't looking at Kedro; bundles rank and honour news |
| N3 | Guest claimed | Passive | A guest you played with claims |
| N4 | Ranked outside a game | Active | A claim or migration takes you to 5 games |
| N5 | Receipt received | Passive | A rival sends one (muteable per person) |
| N6 | Weekly report | Passive, opt-in, off by default | Sunday, only if something changed |

Not sent, and why: every round or edit (everyone is already at the table); being overtaken (shown in Since you last looked, where it's discovered by choice); streak-at-risk or "come back" pings (guilt loops don't suit an in-person game); ambient "game nearby" (would need background tracking); other people's results.

---

## 8. Required recommendations (PRD Section 7)

### 8a. Leaderboard presentation and ranking
**One rank, from one rating, with read-only Spotlights. No user-chosen sort.**

- **Rating**: multiplayer pairwise Elo. Each finished game is split into pairwise results (finished ahead 1, tied 0.5, behind 0; final cumulative score decides; shared wins are ties). K is scaled by 1/(n−1) so table size doesn't inflate swings, doubled for a player's first 10 games so newcomers settle fast. Start 1500. Rebuilt by chronological replay of finished, non-abandoned games, so claims and migrations stay correct. Guests carry a hidden rating that appears on claim.
- **Hidden until game 5, then revealed at the table** (the debut, 4.12). Under 5 games a rank is noise; revealing it turns the threshold into a payoff.
- **Why one rank**: rivalries need one number ("I passed Jordan" must mean one thing); win rate and average score are skewed by table size and round count, which pairwise rating corrects; it rewards strong results against strong players over pure volume; and it fits the 5-game rule naturally.
- **Why not μ−3σ (ambient)**: it's more conservative, but it moves slowly and is harder to explain in one sentence at the table. Elo with a newcomer K is easier to narrate ("moves twice as fast for your first 10 games").
- **Spotlights** (knock success, longest streak, avg per round, most games) give other skills recognition without splitting what "rank" means.
- **Eligibility**: 5 finished, non-abandoned games to hold a rank. Unranked players are listed in Your people with progress ticks and no number, counted on Global with a "one game away" list, and shown on profiles as "Unranked · 3 of 5". Tied ratings share a rank.

### 8b. Play-more incentives

| Where | Incentive |
|---|---|
| Everywhere an unranked player appears | Progress ticks (3 of 5) on profile, lobby seat, waiting screen, Rank widget |
| Waiting screen and lobby | **Stakes strip**: facts ("Game 5", "Maya's up 11–7") or labelled estimates. Never a projected rank stated as fact. |
| Game end | **Your night** pays off every storyline; **Rematch** is the primary button right after a close finish |
| Game 5 | **The debut**, shown to the whole table |
| Play | **Since you last looked** and **Next game** |
| Head-to-head | **Gap to level**; **Play again with {rival}** |
| Rivals | **Receipts**: a reason to come back and a reason to play the person who sent one |
| Honours | **Close** sorted first with exact progress |
| Profile | Streak framed forward ("next win starts a streak; three ties your best") |
| Widgets | Rival and Rank on the Home and Lock Screens |
| Guests | Claim card sells their own story; host earns Breaking In |
| Learn | Schooled; Table Coach retires after 3 games |

Guardrails: no loss-framed notifications, no "come back" pushes, no countdowns, no paid anything. Receipts are capped at one per rival per game and are muteable.

### 8c. Honours catalog (25, plus Schooled)

All evaluated at finish, on finished non-abandoned games. "Hand" means the entered hand before knock adjustment. Names are the brand flavour; the rule is always shown in plain words.

| # | Honour | Group | Rule | Medal |
|---|---|---|---|---|
| 1 | First Start | Milestones | Finish your first game | I |
| 2 | Out of the Gate | Milestones | Win a game (shared wins count) | 1st |
| 3 | Stayer | Milestones | Finish 25 games | 25 |
| 4 | Iron Horse | Milestones | Finish 100 games | C |
| 5 | Cold Open | Knocks | First successful knock (−10) | −10 |
| 6 | Iron Nerve | Knocks | 3 successful knocks in one game | 3◆ |
| 7 | Even Money | Knocks | A tied knock | = |
| 8 | Thrown Shoe | Knocks | A failed knock (it happens to everyone) | ◇ |
| 9 | Sure-Footed | Knocks | 10 knocks in a row without a failed one, across games | 10 |
| 10 | Red Royal | Moments | Finish a round with a negative hand (a red King) | K♦ |
| 11 | Both Crowns | Moments | Finish a round with −2 (both red Kings) | −2 |
| 12 | Ghost Hand | Moments | Finish a round with a hand of 0 | 0 |
| 13 | Shared Spoils | Moments | Share a win | ½ |
| 14 | Wire to Wire | Moments | Lead or share the lead after every round, and win | W |
| 15 | Dark Horse | Moments | Win a game you were last in at the halfway round | ↑ |
| 16 | Photo Finish | Moments | Win by 1 point | 1pt |
| 17 | Triple Crown | Streaks | Win 3 games in a row | 3W |
| 18 | Unbeaten Run | Streaks | Win 5 games in a row | 5W |
| 19 | Herd | Social | Play with 5 different people | 5p |
| 20 | Stampede | Social | Play with 15 different people | 15 |
| 21 | Full Field | Social | Finish an 8-player game | 8 |
| 22 | Turned the Tables | Social | Finish ahead of your nemesis | ⇄ |
| 23 | Breaking In | Social | A guest you played with claims their history | ✓ |
| 24 | On the Board | Ranked | Finish your 5th game and get a rank | 5 |
| 25 | Front Runner | Ranked | Reach #1 among your people (with at least 5 ranked people) | #1 |
| — | Schooled | Learning (separate) | Complete all 5 Learn lessons | ✎ |

Anti-farming: Herd and Stampede count only people with at least one finished game with another person too; Breaking In counts once per guest identity.

---

## 9. Accessibility

| Area | Approach |
|---|---|
| Dynamic Type | Text styles everywhere, serif included (`design: .serif`). Standings and leaderboard rows use `ViewThatFits` to stack at AX sizes (Frame 17). The keypad keeps 48 pt keys and reflows. Furlong ticks become "Round 7 of 10" text at AX sizes. Tested to AX5. |
| VoiceOver | Rows read as full sentences. Outcome badges read their word and math ("Failed knock, 2 plus 10 equals 12"). Voice lines are read as written, in the selected voice. Custom rotors for **Edited rounds** and **Knocks** in History. Announcements (round saved, edit landed) fire only when `AccessibilityNotification` is relevant and VoiceOver is running. Round rows have actions **Edit round** and **Why?**. Charts use `AXChartDescriptor`. |
| Colour | Outcomes never rely on colour (glyph + fill + word). Silks rely on pattern and are de-duplicated per table. All text ≥ 4.5:1 (3.1). Increase Contrast variants for every token, and the hatched fill becomes solid stripes. |
| Reduce Motion | See 3.6: crossfades, no wipe, no count-up, haptics kept. |
| Reduce Transparency | Glass controls become solid `elevated`. |
| Motor | 44 pt minimum targets; no timed traps (the only windows are 5 s Undo, which is optional, and 15-minute Finish and Restore windows). |
| Cognitive | One primary action per screen in the live game; every voice line has a plain rule sentence; the Clean voice is one tap away. |

---

## 10. SwiftUI implementation map

| Area | Components and APIs | UIKit? |
|---|---|---|
| App shell | `TabView` + `Tab`, `Tab(role: .search)`, `tabViewBottomAccessory`, `.tabBarMinimizeBehavior(.onScrollDown)` | No |
| Voice system | String Catalog with `voice` variants, `LocalizedStringResource`, `VoiceStyle` environment, `ScreenVoiceBudget` `PreferenceKey` | No |
| Type | `.font(.system(_:design: .serif))`, `.monospaced()`, `.monospacedDigit()`, `@ScaledMetric` for display sizes | No |
| Welcome | `SignInWithAppleButton`; `#if DEBUG` test sign-in only | No |
| Proximity | Network framework `NetworkListener` / `NetworkBrowser` / `NetworkConnection` (peer-to-peer), `MultipeerConnectivity` fallback, `NearbyInteraction` | No |
| Lobby | `List` + `.onMove`, `Picker(.segmented)`, chips, `.sheet` | No |
| Live game | `.fullScreenCover`, `List` with animated reorder, `.contentTransition(.numericText())`, `.buttonStyle(.glassProminent)`, `.glassEffect()` toasts and banners, `.toolbar` `Menu` | **Yes, keep-awake only**: `UIApplication.shared.isIdleTimerDisabled` (no SwiftUI equivalent), isolated in an `IdleTimer` helper with the required comment |
| Round entry | `.sheet` `.presentationDetents([.large])`, custom keypad in `Grid` (system pad has no minus), `.sensoryFeedback` | No |
| History, detail, review | `ScrollView` + `Grid` for the score grid, `List` sections for Changes, `.accessibilityRotor`, `NavigationLink(value:)` | No |
| Finish gate, game end, debut | `.sheet`, `TimelineView`, `KeyframeAnimator` (photo-finish wipe), `rotation3DEffect`, `ImageRenderer` + `ShareLink` | No |
| Guest claim | `ShareLink`, Core Image `CIFilter.qrCodeGenerator()` | No |
| Profile, H2H | `Grid`, Swift Charts `BarMark` with `AXChartDescriptorRepresentable` | No |
| Leaderboard | `List`, `ViewThatFits`, `.safeAreaInset(edge: .bottom)` for the pinned own row, `.scrollPosition` | No |
| Honours | `LazyVGrid`, custom `Shape` medal, `Gauge` arcs, `.navigationTransition(.zoom)` | No |
| Rules, Learn, Coach | `List` + `.searchable`, `Stepper`, `Slider`, `TipKit` | No |
| Live Activity | ActivityKit, `DynamicIsland` regions, `AlertConfiguration` (self-report nudge), `LiveActivityIntent` | No |
| Widgets, controls, intents | WidgetKit `AppIntentConfiguration`, accessory families, `ControlWidget`, `AppShortcutsProvider` | No |
| Notifications | `UserNotifications` with `.active` / `.passive` (no `.timeSensitive`) | No |
| Sync | `@Observable` store, actors, SwiftData event log, HLC timestamps | No |

---

## 11. Tap and time estimates

| Task | Steps | Taps / time |
|---|---|---|
| Record a 5-player round, scorekeeper | Record (1) + knocker (1) + 5 hands (~10 with auto-advance and Next) + Save (1) | **≈ 13 taps · 10–15 s** |
| Self-report round | Each player in parallel: Enter my hand (1), 1–2 digits, Submit (1) | ≈ 4 taps each · 6–8 s wall time |
| 5 returning players into a game | Host: Start a table (1) + Start game (1). Each of 4 joiners: Join on the card (1). | **6 taps total** (was overstated as 2 per joiner in v1's flow; now exactly 1) · ≈ 15–20 s, mostly unlocking phones |
| Rematch | Proposer: Rematch (1) + Start game (1); others: Join (1) | 2 + 1 each |
| Guest with no phone | Host: + (1), Add guest (1), name (~4), Add (1) | ≈ 7 taps · 8 s, zero for the guest |
| Guest claiming later | Open link, Sign in with Apple (2), Claim (1) | ≈ 4 taps · 15 s |
| Finishing a game | Finish game (1) on any phone | 1 tap, or nothing for 15 minutes |
| Switching to Clean | You → Settings → Voice → Clean | 4 taps |

---

## 12. Sample game (used in every frame)

Noah (host, "you"), Maya, Jordan, Priya, Sam (guest, no phone). **Scorekeeper mode** throughout. 8 planned rounds, extended to 10 at 9:33 PM. All values follow PRD 2.6 and were checked by script.

| Rnd | Knocker | Hands N/M/J/P/S | Outcome | Round scores | Cumulative N/M/J/P/S |
|---|---|---|---|---|---|
| 1 | Maya | 9/3/12/7/15 | Successful | 9/−10/12/7/15 | 9/−10/12/7/15 |
| 2 | Jordan | 5/8/5/11/6 | Tied (Noah 5) | 5/8/5/11/6 | 14/−2/17/18/21 |
| 3 | Noah | 2/6/14/−1/9 | Failed (Priya −1) | 12/6/14/−1/9 | 26/4/31/17/30 |
| 4 | Priya | 10/4/8/3/13 | Successful | 10/4/8/−10/13 | 36/8/39/7/43 |
| 5 | Sam | 1/9/6/12/7 | Failed (Noah 1) | 1/9/6/12/17 | 37/17/45/19/60 |
| 6 | Noah | 3/7/11/8/5 | Successful | −10/7/11/8/5 | 27/24/56/27/65 |
| 7 | Jordan | 6/4/4/9/12 | Tied (Maya 4) | 6/4/4/9/12 | 33/28/60/36/77 |
| 8 | Maya | 4/5/10/2/8 | Failed (Priya 2) | 4/15/10/2/8 | 37/43/70/38/85 |
| 9 | Noah | 0/6/9/5/11 | Successful | −10/6/9/5/11 | 27/49/79/43/96 |
| 10 | Priya | 7/3/8/1/10 | Successful | 7/3/8/−10/10 | 34/52/87/**33**/106 |

- Priya wins 33–34, 16 back with one round left. It's her 5th game: she debuts at 1521, #6 among Noah's people.
- Leaders by round: Maya ×3, Priya, Maya ×3, Noah ×2, Priya: **4 lead changes**. Successful knocks: Noah 2, Priya 2, Maya 1.
- **Changes log** (Frame 09): 9:31 Round 5 conflict (Jordan set Sam 8, Maya set 7 later → 7 applied, Jordan's superseded); 9:33 extended 8 → 10; 9:35 Jordan edited round 2, Sam 9 → 6 (knock unchanged); 9:38 Maya edited round 3, Priya 3 → −1 (Noah's knock successful −10 → failed 12; Noah 15 → 37; after round 5 Noah 1st → 3rd, Maya 2nd → 1st, Priya 3rd → 2nd); 9:53 Jordan's offline copy of round 6 (Sam 15) not applied.
- **Before tonight**: Noah #5 (1545), Maya leads Noah 11–7 in 18 games, Priya and Noah 2–2. **After**: Noah #4 (1559, passed Jordan at 1547), Maya leads 11–8 in 19 games, Priya leads Noah 3–2. Noah: 23 games, 7 wins (30%), best 18, worst 96, 41 knocks in 230 rounds (25 successful, 4 tied, 12 failed), nemesis Maya (11).

---

## 13. Frame index (`mockups-v2.html`)

| # | Frame | Mode | Shows |
|---|---|---|---|
| — | Visual system board | both | Palette, silks, type scale, crest, outcome badges, medals, rules of the look |
| 01 | Welcome | dark | Voice choice first, O1–O4 |
| 02 | Play before the game | dark | Since you last looked (J8, receipt R1), estimate stakes (J7) |
| 03 | Nearby table | light | NI split, one-tap Join (J1) |
| 04 | Joined, waiting | light | No second button, J2, J4, J6 |
| 05 | Lobby | light | Scorekeeper recommendation, table voice |
| 06 | Live game | light | One list, last-round sentence (K1 + K8) |
| 07 | Live game, just saved | dark | Undo toast (L4), out-of-reach pill |
| 08 | Round entry | dark | Knocker first, keypad, tied line (K2 + K9) |
| 09 | History and Changes | light | One page, Not applied + Use this version |
| 10 | Round detail + edit banner | dark | L5 + K3 (the screen's two swears) |
| 11 | Edit review | light | L7, standings impact |
| 12 | Finish gate | dark | F1, 15-minute idle fallback |
| 13 | Game end | dark | W1, W4, W5 as Clean fallback, table news |
| 14 | Debut | light | E3, rating reveal, medals |
| 15 | Head-to-head | light | Gap to level, receipts R1–R2 |
| 16 | Leaderboard | dark | List rows, Unranked (E4) |
| 17 | Leaderboard at AX5 | light, Clean | Stacked rows |
| 18 | You | light | Form, stat grid, knock bar, nemesis |
| 19 | Honours | dark | Medals, A3, progress arcs |
| 20 | Rules from Why? | light | Knock calculator |
| 21 | Lock Screen mid-game | dark | Pre-game widget values, Live Activity |
| 22 | Dynamic Island | dark | Expanded 150 pt, compact, minimal, ended, L8 |
| 23 | Lock Screen after | dark | Reloaded widgets, N3, R5, ended Live Activity |
| 24 | Settings · Voice | light | Clean option, Lock Screen and shared-screen rules, age rating |
| 25 | Empty and offline | dark | ES1, ES3, OF1 Clean fallback |
| 26 | Guest hand-off | light, Clean | Claim code, outbound Clean |
