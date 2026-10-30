# Kedro for iOS
### Product Requirements Document · v3.0 (iOS) · October 2026

> **How to read this document.** This PRD defines *what* Kedro must do and *why*. It deliberately does not describe screens, navigation, layouts, controls, or visual treatments. Those belong to the design tournament. Where this document gives an example, it illustrates a requirement and is not a design direction. The legacy web PRDs (`kedro-prd.md`, `kedro-prd-v2.md`) are background only; where they disagree with this document, this document wins.

---

## 1. Product vision

Kedro is the companion for playing Cambio in person. When a group of people sit down at a table, Kedro gets them all into a game almost instantly, keeps an accurate and trusted score with no arguments, and turns every game into a lasting record: stats, rivalries, and bragging rights that bring people back between games. Kedro also teaches the game, so new people can learn Cambio and pick up Kedro at the same time.

Kedro has **no groups, leagues, or clubs**. The core unit is the individual player. Any set of people who are physically together can play a game, and their history builds up per person and per pairing.

### 1.1 Goals and success measures

| Outcome | What success means |
|---|---|
| **Fast table flow** | Recording a round takes seconds and never stalls the game. The app is never the reason the table is waiting. |
| **Everyone joins** | Every player at the table is in the game on their own phone, with close to zero setup and no typing for people who have played before. |
| **People come back** | Players open Kedro between games to check stats, rivalries, leaderboards, and achievements. |
| **Spreads to new tables** | New players learn Cambio through Kedro, and people who join as guests convert to their own accounts. |

### 1.2 Product principles

1. **The table comes first.** The app supports a live, social, in-person card game. It should demand as little attention as possible during play.
2. **One source of truth.** Everyone at the table sees the same score at the same moment, and trusts it.
3. **Transparent, not locked down.** Anyone in a game can fix a mistake, and every fix is visible to everyone.
4. **History is permanent.** A finished game is a fixed record.
5. **Native and modern.** A polished SwiftUI app that follows Apple's Human Interface Guidelines and uses system capabilities where they genuinely help.

### 1.3 Non-goals (v1)

- Playing Cambio remotely or digitally. Kedro tracks a physical game; it does not deal cards or simulate play.
- Groups, leagues, clubs, or tournaments as formal structures.
- Custom house rules or rule variants. Kedro has one canonical ruleset (Section 2).
- Feature parity with the web app (Section 9).
- iPad-optimized and Apple Watch experiences (other than the table display mode in 4.4).

---

## 2. Canonical Cambio ruleset

Kedro enforces exactly one ruleset. All scoring the app does automatically follows these rules.

### 2.1 Setup and objective
- Each player is dealt 4 cards face down in a 2×2 grid.
- Players may not look at their own cards unless a power card allows it.
- Objective: finish the game with the **lowest** cumulative score.

### 2.2 Card values

| Card | Points |
|---|---|
| Ace | 1 |
| 2–10 | Face value |
| Jack | 11 |
| Queen | 12 |
| Black King (♠K, ♣K) | 13 |
| Red King (♥K, ♦K) | −1 |
| Joker | 0 |

A player's **hand value** is the sum of their remaining cards when the round ends.

### 2.3 Power cards
- **7 / 8, peek own:** look at one of your own face-down cards.
- **9 / 10, peek opponent:** look at one of an opponent's face-down cards.
- **Jack / Queen, blind switch:** swap one of your cards with an opponent's without looking.
- **Black King, look and switch:** look at any card, then optionally swap it.

### 2.4 Sticking
When a card is discarded, any player may immediately play a matching card from their grid to remove it.

### 2.5 Knocking and round end
- On their turn, one player may **knock** to end the round. Knocking is a gamble, not a win or loss in itself.
- After a knock, every other player gets exactly one more turn.
- All cards are revealed and each player's hand value is totaled.
- **Inherent knock.** A player who has played all four of their cards knocks automatically when their turn comes around. Their hand is 0.
- **Every round ends with exactly one knock** (regular or inherent). A round cannot be recorded without a knocker.
- A wrong stick is handled at the table under the physical rules (it shows up in the player's hand value). The app does not track it separately.

### 2.6 Round scoring (enforced by the app)

| Situation | Knocker's round score | Everyone else's round score |
|---|---|---|
| Knocker has the **strictly lowest** hand | **−10 flat** (hand value is ignored) | Their hand value |
| Knocker **ties** for the lowest hand | Their hand value | Their hand value |
| Someone has a **lower** hand than the knocker | Their hand value **+ 10** | Their hand value |

An **inherent knock** (hand 0) scores −10 if it's the strictly lowest hand, and otherwise 0: it never takes the +10 penalty.

Worked examples (knocker is A):
- A = 4, B = 7, C = 9 → A scores −10, B 7, C 9.
- A = 4, B = 4, C = 9 → A 4, B 4, C 9.
- A = 6, B = 3, C = 9 → A 16, B 3, C 9.
- Inherent: A = 0, B = 3 → A −10. A = 0, B = 0 → A 0. A = 0, B = −2 → A 0 (no penalty).

The app must apply these adjustments automatically from the hand values and the identity of the knocker. Players never compute the bonus or penalty themselves.

### 2.7 Game end and winner
- At setup, the game is given a **planned number of rounds**.
- The game ends when the planned rounds are complete. During the game, any player can **extend** the planned rounds or **end the game early**. These changes are logged like score edits (4.5).
- The winner is the player with the **lowest cumulative score**. **Ties share the win.** Every tied player gets credit for the win in all stats.

---

## 3. Players and identity

### 3.1 Accounts
- Players sign in with **Sign in with Apple**. *Status: temporarily disabled until the Apple Developer account is approved. A debug-only test-user sign-in exists for development and must never ship in release builds.*
- Each player has a public profile: a display name, a unique **@handle** (so players can find each other by search), and an avatar. An avatar can be a **photo**, **any emoji** on a chosen color, or one of a **curated set of on-brand illustrated avatars**.
- Once signed in, a player stays signed in on their device.

### 3.2 Guests
- Anyone at the table can be added to a game as a **guest**, with no account and no app.
- A guest's games, rounds, and stats are recorded in full.
- A guest can later **claim** their guest history when they create an account. Their past games then count toward their profile, stats, rivalries, achievements, and leaderboards.
- Claiming uses a **claim link or code** issued for that guest identity (for example when their game ends) and handed to them directly, such as by AirDrop or text. Only someone holding the link or code can claim the history. A claimed identity cannot be claimed again.
- Players from the legacy web app are migrated as guest identities and can be claimed the same way (Section 9).

### 3.3 Visibility
- **Profiles are public.** Any Kedro user can see any player's profile, lifetime stats, achievements, and game history.
- Guests who have not been claimed are visible only in the context of the games they played.

---

## 4. Core experience requirements

### 4.1 Getting a table into a game
Players in a Kedro game are **always physically together**. That fact is the foundation for joining.

Requirements:
- **Effortless co-located joining.** When people with Kedro open are together and a game is starting or underway nearby, joining it should take little more than a confirmation. Using proximity capabilities (for example Bluetooth or local-network discovery, Nearby Interaction, or similar Apple frameworks) is strongly encouraged. The mechanism and the experience are up to the design.
- **Host-led setup.** A host can always start a game and add players directly: people they have played with before, any Kedro user, or guests by name.
- **Pick from a list.** Adding players starts from a list to pick from, with no typing needed: people nearby first, then people you have played with, then every other Kedro user A–Z. Typing narrows the list and searches Kedro by name or @handle. Blocked people never appear.
- **Played-with list.** People you have played with before are easy to add to a new game.
- **Late joins.** Any player in a game in progress can add someone after Round 1. The late joiner plays from the next round, starts at the **highest total at the table** at that moment (so joining late is never an advantage), and takes the last seat in the dealing order. The deal is not disturbed. A late joiner can be removed until they have played a round.
- **Rematch.** After a game, the same table can start another game with the same players with minimal effort.
- Supported table size: **3–8 players**.
- At setup, the game records the planned number of rounds and the scoring mode (4.2).

### 4.2 Scoring modes
Each game uses one of two modes, chosen when the game is set up:
- **Scorekeeper mode.** One person enters every player's result for each round.
- **Self-report mode.** Each player enters their own result on their own phone. A round is complete once every player has reported. Guests without the app need someone to report for them.

In both modes, the knocker for the round must be recorded.

### 4.3 Recording a round
- The input for each player is their **hand value** (or the cards that make it up). The app derives round scores using the rules in Section 2.6.
- How results are captured (typing totals, selecting cards, or anything else) is **up to the design**. The requirements are speed, accuracy, and support for negative values.
- Once a round is recorded, every device in the game reflects it immediately (or as soon as it can sync; see 6.2).

### 4.4 During the game
Every player must be able to see, at any moment:
- current standings (cumulative score and rank), including who is leading;
- the effect of the most recent round on each player;
- the full round-by-round history of the game, including who knocked and the knock outcome;
- progress against the planned number of rounds.

The device should not sleep while a game is active and on screen.

**Table display mode:** a phone or iPad propped up in landscape in the middle of the table can act as a shared scoreboard for everyone.

**Whose deal it is:** the app tracks the dealer. The seat order set in the lobby is the order around the table; the first dealer is chosen when the game starts, and the deal passes one seat to the left after every round. Every phone (and the Live Activity and display mode) shows who deals next. Anyone can correct the dealer, and the change is logged.

### 4.5 Corrections and audit trail
- **Any player in the game** can edit any recorded round while the game is in progress.
- Every edit is **logged** (who, when, before → after) and **visible to everyone** in the game. This includes extending the planned rounds, ending early, and abandoning.
- Edits that change the knocker or hand values re-run the scoring rules automatically.
- Once a game is **finished, it is immutable**. No one can change it.

### 4.6 Ending a game
- When the planned rounds are complete, the app recognizes that the game is over.
- Any player can end the game at any time, from the game itself or without opening it. The confirmation says up front whether the game will count.
- **A game counts only with at least 3 rounds.** Games ended with fewer stay in history, clearly marked, but don't count for stats, ratings, the leaderboard, badges, titles, the Hall of Shame, or Wrapped. Within a counted game, a player who played fewer than 3 rounds (a late joiner) doesn't count either.
- Ending a game before any round is played simply discards it.
- Ending a game deserves a moment: the winner (or co-winners), the final standings, and the game's highlights (for example best round, successful knocks, biggest comeback).
- A game can be **abandoned**, which is distinct from ending early. Abandoned games stay in history, clearly marked, and are excluded from all stats, leaderboards, and achievements. Any player in the game can abandon it.

### 4.7 Rules and learning
- The full canonical ruleset (Section 2) is available in the app at all times, including mid-game.
- Kedro should help **new players learn Cambio**: card values, power cards, sticking, knocking, and the knock gamble. Teaching approach and format are up to the design.
- The scoring in a live game should reinforce the rules. For example, a player can always understand why a knock produced −10, their hand value, or +10.

### 4.8 Trash talk
Trash talk is part of the game, during play as well as between games.
- **Automatic roasts** react to each round: knocks (landed, tied, failed), red Kings, blowups.
- **Standings banter:** running commentary on who's leading, who's cooked, comebacks, and streaks.
- **Player taunts:** players can fire taunts and reactions at a player or the whole table, seen on everyone's phone. There is a large canned library, and players can also write **custom taunts**.
- **Custom-taunt safeguards** (required by App Store rules for user-generated content): custom taunts can be sent only to people at your table or people you've played with; a filter blocks slurs and abuse; any taunt can be reported; and players can mute or block a person.
- **Receipts:** shareable cards that roast a result (for example "Noah knocked on 9 into a 1"), sent to a group chat or a rival.
- **Live knock (optional):** anyone can mark a knock the moment it happens. This sets off a taunt and pre-fills the knocker at entry. If nobody marks it, the knocker is picked when the round is recorded.
- Trash talk must never slow down recording a round.

---

## 5. Stats, rivalries, and progression

All stats are **derived from recorded rounds and games**. They are not stored as separately maintained counters, so corrections and guest claims always produce correct numbers.

### 5.1 Per-player lifetime stats

| Stat | Definition |
|---|---|
| Games played | Completed (non-abandoned) games of 3+ rounds, including early-ended ones |
| Wins | Games won, including shared wins |
| Win rate | Wins ÷ games played |
| Best game | Lowest final cumulative score |
| Worst game | Highest final cumulative score |
| Average score per game | Sum of final scores ÷ games played |
| Average score per round | Sum of round scores ÷ rounds played |
| Current win streak | Consecutive most-recent games won |
| Longest win streak | Longest run of consecutive wins |
| Knock rate | Rounds knocked ÷ rounds played |
| Knock success rate | Knocks with strictly lowest hand (−10) ÷ total knocks (inherent knocks excluded) |
| Inherent knocks | Rounds a player went out with all four cards, and how many were −10. Tracked apart from knocks. |
| Knock outcomes | Count of successful, tied, and failed knocks |
| Nemesis | The player who has finished ahead of this player most often in shared games |

### 5.2 Head-to-head
For any two players: games played together, how often each finished ahead of the other, wins in shared games, and knock outcomes when facing each other.

### 5.3 Leaderboards
- A **global** leaderboard across all Kedro players is required.
- A **played-with** leaderboard: you ranked among people you have shared a table with.
- **Eligibility: a player must complete at least 5 games** (non-abandoned) to hold a leaderboard placement. Players below the threshold are still recognized as part of the global community, but they hold no rank.
- **Sortable.** Players can sort leaderboards by several attributes: at least a skill rating (Elo-style, starting at 1,000), win rate, wins, average score, and knock success.
- **Records** boards (for example best game, longest streak, most successful knocks) sit alongside the rankings.

### 5.4 Playing more games
Kedro should **encourage people to play more games**. Getting onto the leaderboard (reaching 5 games) is the clearest first goal, followed by climbing it, extending streaks, and earning achievements. Designs should look for ways across the whole app, not only on leaderboards, to show players their progress and give them a reason to play again.

### 5.5 Achievements
- Players earn achievements for milestones and memorable moments. Illustrative examples, not a final list: first win, first successful knock, a Red King round, a win streak, playing with N different people, reaching the leaderboard.
- Achievements are visible on public profiles.
- Designs should propose the achievement catalog (Section 7).

### 5.6 Titles
- Players earn **titles**: short labels such as "The Closer" or "Knock Merchant" that show under their name on their profile, at the table, and on leaderboards.
- Some titles are permanent (earned from achievements); others are **held** only while a player's stats qualify and can be lost.
- Each player chooses which of their titles to display, or none.

### 5.7 Hall of Shame
- A record of the worst **single moments** among the people you've played with: worst hand, worst failed knock, biggest loss, biggest blown lead, and similar.
- It records moments, never patterns: no "longest losing streak" or anything that piles on someone who's having a rough run.
- New entries are revealed at game end. There are no push notifications for them.

### 5.8 Kedro Wrapped
- Once a year, each player gets a personal, shareable recap of their year in Kedro: games played, record, rating journey, nemesis, best and worst moments, titles, and Hall of Shame entries.
- It's delivered in early December and stays available until the next one. It requires at least 10 finished games in the year.

---

## 6. Platform and system requirements

### 6.1 Platform
- iPhone, **iOS 26**, built with modern SwiftUI per `apps/ios/AGENTS.md`. UIKit only where SwiftUI cannot do the job.
- Follows Apple's Human Interface Guidelines, and supports Dynamic Type, VoiceOver, light and dark appearance, and Reduce Motion.

### 6.2 Offline and sync
- **A game must be fully playable without internet**: setup, joining, recording rounds, corrections, and ending.
- Co-located devices should keep each other in sync directly when there is no internet connection.
- When connectivity returns, everything syncs to the backend with no data loss or duplication. Conflicting edits are resolved deterministically and recorded in the audit trail.
- With a connection, updates appear on every device in the game in real time.

### 6.3 System surfaces (v1)
- **Live Activity / Dynamic Island:** the state of the active game, visible outside the app.
- **Widgets:** stats, rivalries, or leaderboard position on the Home Screen.
- **App Clip:** a guest with an iPhone but no app can scan a code to join the game, see the live scores, and report their own hand. Afterwards they can install Kedro and keep their history.
- **Sound pack:** optional sound effects for game moments (a knock, a landed or failed knock, a red King, the winner's horse neigh from the web app). Off by default. Sounds respect the Silent switch, and only one phone per table plays the shared moments so a table of eight doesn't neigh in unison.
- **Notifications:** timely, relevant prompts. Candidates include a nearby game you can join, a round recorded in self-report mode that needs your score, a game ending, and an achievement or leaderboard change. The final notification set must respect the "table comes first" principle and avoid noise.

### 6.4 Data integrity
- Each player's identity is stable across devices.
- Games, rounds, edits, and knock records are first-class, queryable data. *The legacy key-value document store does not meet these requirements; the backend schema needs to be redesigned. That is an engineering decision, noted here because it limits what the product can do.*

---

## 7. Design tournament brief

Competing designs are judged on how well they deliver Sections 1–6. The design owns, without constraint from this document or the legacy web app:

- information architecture, navigation, and screen structure;
- the joining experience and how proximity is used;
- round entry interaction;
- how live standings, deltas, history, and the audit trail are presented;
- how stats, rivalries, leaderboards, and achievements are explored;
- teaching and rules presentation;
- celebration and game-end moments;
- visual identity within the brand constraints (Section 8).

Each design must also include these **recommendations**:
- **Leaderboard presentation and ranking.** Single attribute vs. several sortable attributes (win rate, skill rating, etc.), with a rationale. It must respect the 5-game eligibility rule and show players under the threshold as part of the community without a rank.
- **Play-more incentives.** How the design motivates people to play more games, especially to reach the leaderboard (5.4).
- **Achievement catalog.** A proposed set of achievements (5.5).

Suggested judging criteria, mapped to goals:
1. **Table flow:** time and taps to record a round; attention the app demands during play.
2. **Joining:** steps for a full table of returning players and for a table that includes a guest.
3. **Trust:** how clearly scoring, knock outcomes, and edits are communicated.
4. **Return value:** how compelling the app is between games.
5. **Learnability:** how well a first-time Cambio player gets up to speed.
6. **Native quality:** HIG fit, accessibility, and appropriate use of system capabilities.

## 8. Brand constraints
- The name is **Kedro**. "Kedro" is the brand only; it is not a term used in gameplay (knocking is called knocking).
- **The Kedro logo is the brand.** The original logo from the web app (the red retro script "Kedro" over a gritty silver galloping horse, `apps/ios/Kedro/Assets.xcassets/Logo.imageset`) is the primary brand element. It replaces equestrian or racing-club motifs throughout the app. A simplified small mark derived from the logo is needed for the app icon, Dynamic Island, widgets, and badges; the design proposes it.
- **Aesthetic: dark-first, moody, adult, never childish.** Late-night card table, not a kids' game. The web app's palette is the starting point: near-black (#0a0a0e), Kedro red (#e63946), cream (#f5efe6), silver, and gold for leaders. Light mode is supported but secondary.
- **Typography:** Bebas Neue for scores and headlines (brand flavor); SF Pro for body text. Both scale with Dynamic Type.
- **Voice: contemporary, irreverent, and allowed to swear.** Copy throughout the app (during play, celebrations, knock outcomes, standings, notifications, achievements, profiles, leaderboards) should sound like friends roasting each other at the table: current slang, dry wit, and real profanity. Affectionate insults aimed at people ("smug bastard", "you animals") are allowed, including at losers. Never slurs, and never aimed at identity.
- **Language levels:** each player chooses **Clean**, **Spicy** (about a third of lines swear), or **Unhinged** (half or more). The Lock Screen and Live Activity follow the player's setting. The app's age rating must match the profanity (expected 16+).

## 9. Relationship to the web app
- iOS is the flagship. The web app will share the backend and catch up later.
- Web parity is **not** a v1 constraint, and the iOS experience must not be shaped by web limitations.
- **Existing web history is migrated.** Legacy games are imported, and each legacy username becomes a guest identity that its owner can claim with a claim link or code (3.2). Migrated games count toward stats once claimed, and are fixed records like any finished game.
  - The web app saved scores (with the knock result marked by the scorekeeper), not hands, and allowed rounds with no knocker. Imported rounds **keep the web's saved scores exactly**, even where the marked result doesn't match the hands.
  - A web round with no knocker recorded is imported with **no knock credited** to anyone (imported rounds only; live rounds always need a knocker). The web's inherent knock ("IK") is kept.
  - Web rounds where everyone scored 0 were testing and are dropped.

---

## 10. Decision log

| # | Question | Decision |
|---|---|---|
| 1 | Can a round end without a knock? | No. Every round has exactly one knocker. |
| 2 | Table size | 3–8 players. |
| 3 | Changing the planned rounds mid-game | Anyone can extend or end early; the change is logged. |
| 4 | Abandon vs. end early | Both exist. End early counts in stats; abandon voids the game. |
| 5 | Leaderboard ranking | A global board is required; 5-game minimum to place. Sort approach is a design recommendation. |
| 6 | Guest claim verification | Claim link or code given directly to the guest. |
| 7 | Web history migration | Migrate; legacy users become claimable guest identities. |
| 8 | Achievement catalog | Proposed by the designs in the tournament. |
| 9 | Wrong-stick penalty | Handled at the table; already reflected in hand value. |
| 10 | Short games | A game counts for stats only with 3+ rounds; a player counts in it only with 3+ rounds played. |
| 11 | Late joins | Allowed after Round 1, at the highest total at the table, from the next round. |
| 12 | Who can end a game | Any seated player, at any time. |
| 13 | Adding players | A browsable list (nearby, played with, everyone A–Z) with search on top. |
| 14 | Inherent knock | Part of the rules: hand 0, −10 if lowest alone, otherwise 0 (never +10). Its own stat, not counted as a knock. |
| 15 | Importing web history | Keep the web's saved scores; credit no knock where none was recorded; drop all-zero test rounds. |

*Kedro iOS PRD v3.0 · October 2026*
