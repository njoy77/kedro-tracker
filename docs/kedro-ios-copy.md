# Kedro for iOS: Copy Deck
### v1.0 · October 2026

> Every user-facing voice string in the app, in all three language levels. Screen behavior is in `docs/kedro-ios-design.md`; IDs used there (K-06, N-01…) refer to this file. Literal strings (buttons, rules, errors' fix steps, the audit log, accessibility labels) are listed once in §20 because they are **identical in every level**.

---

## 1. Who's talking

Kedro talks like the friend who keeps score because nobody else at the table can be trusted with it: quick, dry, a shit-stirrer, always right about the math. It swears the way people swear over drinks: as punctuation and as affection.

## 2. Rules

1. **Math first, mouth second.** The fact, then the verdict, then the roast. Delete the roast and the string still works.
2. **Roast the play and the player, affectionately.** Calling a friend a smug bastard after a win is in, and so is roasting the loser. **Never:** slurs of any kind (including "reclaimed" ones); anything about race, ethnicity, religion, gender, sexuality, body, disability or age; gendered insults ("bitch", "pussy", "man up"); disability or mental-illness slurs ("retard", "psycho", "spaz").
3. **One swear per line in Spicy.** Unhinged can stack them when it's funnier.
4. **Names, not pronouns.** Use `{name}`, "you" or "they". Never assume he/she.
5. **Never push drinking, gambling or money.** Mentioning drinks is fine ("whoever's three drinks deep"). Telling anyone to drink, bet or pay is not.
6. **Punch at the moment.** Roast a knock, a hand, a lead blown tonight. Don't pile onto someone's long losing streak or someone being new (learners get teaching lines, §6).
7. **Buttons are verbs, never jokes.** Record Round 6, Sit Down, Run It Back, Send.
8. **Clean is not cute.** No heck, darn, frick, f***, "so-and-so", buddy, champ, yikes, oopsie. Swap in a sharper word or drop the clause.
9. **Dry beats loud.** No exclamation marks. No emoji in copy (reactions are emoji; copy isn't).
10. **Glance surfaces are ≤ 60 characters** (Live Activity, Dynamic Island, notifications, widgets, toasts), and the punchline can't be the part that gets cut.
11. **Slang review every release.** Durable slang only: cooked, mid, bottled it, run it back, no notes, FAFO, receipts, menace, ice cold.

## 3. The three levels

| Level | Target | Description in Settings |
|---|---|---|
| **Clean** | 0% profanity | "Clean: same attitude, zero swearing. For game night at your in-laws'." |
| **Spicy** | ~⅓ of lines swear, one per line | "Spicy: swears when it counts." |
| **Unhinged** | ½ or more swear, insults on | "Unhinged: no filter. Your friends will be called names. Lovingly." |

In the tables below, **"="** means "same as the column to its left".

Variables: `{name}`, `{knocker}`, `{hand}`, `{score}`, `{n}`, `{gap}`, `{round}`, `{word}` (table word), `{host}`.

---

## 4. Onboarding and settings (O, S)

| ID | Moment | Clean | Spicy | Unhinged |
|---|---|---|---|---|
| O-01 | Welcome headline | Keep score. Talk trash. | Keep score. Talk shit. | = |
| O-02 | Welcome subhead | Kedro does the math, so nobody has to trust whoever's three drinks deep. | = | = |
| O-03 | Guest path footnote | Just your first name. Sign in later and it's all still yours. | = | = |
| O-04 | Learn link | New to Cambio? Learn it in 2 minutes, not 20 minutes of someone's rambling explanation. | …someone's half-assed explanation. | = |
| O-05 | Local Network primer | Kedro finds the phones at your table so nobody has to type a code. iOS is about to ask. | = | Kedro finds the phones at your table so nobody has to type a fucking code. iOS is about to ask. |
| O-06 | Level picker title | How filthy do you want it? | = | = |
| O-07 | Sample line under Clean | "Bold. Wrong, but bold." | | |
| O-08 | Sample line under Spicy | | "Bold. Wrong as shit, but bold." | |
| O-09 | Sample line under Unhinged | | | "Bold. Wrong as shit, but bold, you magnificent idiot." |
| O-10 | Under-18 lock | Clean until you're 18. House rules, not ours. | = | = |
| O-11 | Avatar step | Pick a face. Photo, emoji or one of ours. | = | Pick a face. Make it a good one, you'll be staring at it while you lose. |
| S-01 | Settings: level footer | (Level descriptions, §3) | | |
| S-02 | Settings: custom taunts | Taunts from people at your table. You can mute or block anyone. | = | = |

## 5. Joining and stakes (J)

| ID | Moment | Clean | Spicy | Unhinged |
|---|---|---|---|---|
| J-01 | Stakes, 10th game | Your 10th game. Finish it and you're on the board. Don't blow it. | …Don't fuck it up. | = |
| J-02 | Stranger asks to sit | {name} wants a seat. You've never played together, so it's your call. | = | = |
| J-03 | Played-with sat down (toast) | {name} sat down. | = | {name} sat down. Hide your cards. |
| J-04 | Watch mode | Seats are set after Round 1. Watch this one; you're in the rematch. | = | Seats are set after Round 1. Watch, heckle, you're in the rematch. |
| J-05 | Stakes, rival at the table | {name} leads you {a}–{b}. Tonight's a good night to fix that. | = | {name} leads you {a}–{b}. Tonight's a good night to shut them up. |
| J-06 | Stakes, close rank | A win tonight would likely put you past {name} (based on your ratings). | = | = |
| J-07 | Since you last looked: passed | {name} passed you on the board. | = | {name} passed you on the board. Rude as hell. |
| J-08 | Since you last looked: rivalry flipped | You now lead {name} {a}–{b}. | = | You now lead {name} {a}–{b}. Rent's due. |
| J-09 | Since you last looked: last game | {result} at {word}. Rating {delta}. | = | = |
| J-10 | Tonight's stakes, empty | Nothing on the line. Play anyway. | = | Nothing on the line. Play anyway, coward. |
| J-11 | Guest claimed | {name} claimed their history. You've created a monster. | = | = |
| J-12 | App Clip QR caption | This code changes every minute, so screenshots won't work. Nice try. | = | = |
| J-13 | App Clip: which seat | {host}'s table. Which one's you? | = | = |
| J-14 | Nearby alert offer | Want a heads-up when your people start a table nearby? | = | = |
| J-15 | Lobby: house voice | Keeping it {level} tonight: someone at the table asked. | = | = |
| J-16 | Table card: other tables | {n} other tables nearby. | = | = |

## 6. Rounds, knocks and red Kings (K)

The **fact** and **verdict** lines are literal (§20). These are the roast lines; each moment has 3–6 variants (two shown).

K-24…K-27 (an inherent knock: the player went out with all four cards) are **drafts** awaiting review. They take precedence over the red King lines, since beating an inherent knock always takes a red King.

| ID | Moment | Clean | Spicy | Unhinged |
|---|---|---|---|---|
| K-01 | Landed | {knocker} knocked on {hand} and nobody could touch it. | {knocker} knocked on {hand} and nobody had shit. | = |
| K-02 | Landed (alt) | Called it. Ice cold. | = | Called it. Ice in the fucking veins. |
| K-03 | Landed on 0 or less | Knocked on {hand}. Disgusting. Respect. | = | Knocked on {hand}. Filthy fucking work. |
| K-04 | Tied | Tied for lowest. No bonus, no penalty, no glory. | = | Tied for lowest. No bonus, no penalty, no fucking glory. |
| K-05 | Tied (alt) | Technically not a loss. Technically. | = | = |
| K-06 | Failed | Bold. Wrong, but bold. | Bold. Wrong as shit, but bold. | Bold. Wrong as shit, but bold, you magnificent idiot. |
| K-07 | Failed (alt) | {knocker} knocked on {hand}. {name} had {low}. Found out the hard way. | …Fucked around, found out. | = |
| K-08 | Failed by 8 or more | Knocked on {hand} into a {low}. Absolute circus. | …Absolute clown shit. | Knocked on {hand} into a {low}. Absolute clown shit. Honk honk. |
| K-09 | Failed by 1 | Beaten by one point. One. | = | Beaten by one fucking point. |
| K-10 | Beat the knocker (to that player) | Your {low} just ruined {knocker}'s whole night. Love that for you. | = | = |
| K-11 | Typo guard | {name} had {hand}? That's a lot of cards. | = | {name} had {hand}? That's a lot of fucking cards. |
| K-12 | Red King decided it | Red King for −1. Dirty work. | Red King for −1. Dirty fucking work. | = |
| K-13 | Both red Kings | Both red Kings. −2. Ruthless. | Both red Kings. −2. Filthy. | Both red Kings. −2. Filthy bastard. |
| K-14 | Self-report waiting | Waiting on {names}. Any day now. | = | Waiting on {names}. Any day now, you animals. |
| K-15 | Two people claimed the knock | Two knockers. That's not how this works. Who actually knocked? | = | Two knockers. That's not how any of this works. Who knocked? |
| K-16 | Nobody claimed the knock | Nobody claimed the knock. Somebody did. Point at them. | Nobody claimed the knock. Somebody fucking did. Point at them. | = |
| K-17 | Proposal conflict | {a} says {x}, {b} says {y}. Sort it out. | = | = |
| K-18 | Verdict preview, in progress | {knocker} knocked on {hand} · lowest so far | = | = |
| K-19 | Round saved (toast) | Round {round} saved. | = | = |
| K-20 | Huge hand (40+) | {name}: {hand}. Bad sticks have consequences. | = | {name}: {hand}. That's not a hand, that's a fucking deck. |
| K-21 | Live knock (toast, all phones) | {knocker} knocked. Last turns. Pray. | = | {knocker} knocked. Last turns. Pray, you animals. |
| K-22 | Live knock (alt) | {knocker} knocked. Everybody look nervous. | = | {knocker} knocked. Clench. |
| K-23 | Live knock (Live Activity) | {knocker} knocked · last turns | = | = |
| K-24 | Went out (inherent knock), landed −10 · **draft** | {knocker} played all four cards and walked off with −10. Didn't even have to knock. | {knocker} played all four cards and walked off with −10. Cold as shit. | {knocker} emptied the whole fucking grid and took −10. Get out. |
| K-25 | Went out, landed (alt) · **draft** | Nothing left in front of {knocker}. Not one card. | = | Nothing left in front of {knocker}. Not one fucking card. Menace. |
| K-26 | Went out, beaten, no penalty · **draft** | {knocker} went out on nothing and {name} still had {low}. Robbed. | {knocker} went out on nothing and {name} still had {low}. Robbed as hell. | {knocker} went out on nothing and {name} still had {low}. Daylight fucking robbery. |
| K-27 | Went out, beaten (alt) · **draft** | Played every card and still got beaten. At least it's free. | = | Played every card and still got beaten. At least it's free, you poor bastard. |
| K-30 | Learner: own failed knock | Failed: someone had less. Knock when you're at 4 or under. | = | = |
| K-31 | Learner: own big hand | That's {hand}. Use your peeks on your highest cards. | = | = |
| K-32 | Learner: own tied knock | Tied for lowest: you keep your hand. Close. | = | = |
## 7. Standings banter (B)

Shown under the standings; changes only when a round is saved.

| ID | State | Clean | Spicy | Unhinged |
|---|---|---|---|---|
| B-01 | New leader | {name} takes the lead. Get comfortable, it won't last. | = | {name} takes the lead. Enjoy it, you smug bastard. |
| B-02 | Lead of 15+ | {name}'s up {gap}. Somebody do something. | = | {name}'s up {gap}. Somebody stop this asshole. |
| B-03 | Player cooked (estimate) | {name}'s {gap} back with {n} to play. Cooked. | = | {name}'s {gap} back with {n} to play. Cooked. Well done. Charred. |
| B-04 | Comeback in progress | {name} was last two rounds ago. Now 2nd. Watch your back. | = | {name} was dead last two rounds ago. Now 2nd. Watch your fucking back. |
| B-05 | Tie at the top | {a} and {b} are level at {score}. Delicious. | = | = |
| B-06 | Last round next | Last round. Everything's on the table. | = | Last round. Shit or get off the pot. |
| B-07 | Leader just failed a knock | The leader just ate +10. Blood in the water. | = | = |
| B-08 | Everyone within 10 | Whole table within 10. Anyone's game. | = | Whole table within 10. Absolute chaos. Love it. |
| B-09 | Same player last 3 rounds running | {name}'s been last three rounds straight. Consistent, at least. | = | {name}'s been last three rounds straight. Consistently shit. |

## 8. Game end (W) and flow (G)

| ID | Moment | Clean | Spicy | Unhinged |
|---|---|---|---|---|
| W-01 | Winner | {name} wins. Obviously. | {name} fucking wins. | = |
| W-02 | Comeback win | {pos} after Round {r}. Won it anyway. Ice in the veins. | …Ice in the fucking veins. | = |
| W-03 | Won on the last knock | Stole it on the last knock. Ice cold. | Stole it on the last knock. Cold-blooded. | Stole it on the last knock. Cold-blooded bastard. |
| W-04 | Wire to wire | Led every round. Didn't even break a sweat. | = | Led every round. Insufferable. |
| W-05 | Rating debut | {name}'s on the board. {rating}. Welcome. It's rough down here. | …It's a shithole down here. | = |
| W-06 | Shared win | Shared win. Half the glory, all the arguing. | = | = |
| W-07 | Lost by 1 | Lost by 1. One. Single. Point. | Lost by 1. One. Fucking. Point. | = |
| W-08 | Bottled it | {name} led for {n} rounds and finished {pos}. Fumbled it. | …Bottled it. | {name} led for {n} rounds and finished {pos}. Bottled it like a little shit. |
| W-10 | Last place | {name}: {score}. Dead last. | {name}: {score}. Dead fucking last. | = |
| W-11 | Last place near 100 | {name}: {score}. Dead last. One off triple digits, which is honestly impressive. | Dead fucking last. One off triple digits… | = |
| W-12 | Next goal | Two more straight for Three-Peat. Don't choke. | = | = |
| G-01 | Finish gate | That's the last round. Lock it in before anyone starts lawyering. | = | = |
| G-02 | Auto-finished | Nobody touched it for 15 minutes, so we locked it. | = | = |
| G-03 | End early confirm | End after Round {r}? It counts, standings as they are. | = | End after Round {r}? It counts. No take-backs. |
| G-04 | Abandon confirm | Abandon this game? It won't count for anyone. You can restore it for 15 minutes. | = | = |
| G-05 | Extended | {name} added {n} rounds. Now playing to {total}. | = | = |
| G-06 | Rematch invite | Run it back? Same seats, {n} rounds. | = | = |
| G-07 | End early confirm, under 3 rounds | End after Round {r}? Under 3 rounds, so it won't count for stats or the leaderboard. It stays in history. | End after Round {r}? Under 3 rounds doesn't count. No stats, no leaderboard. It stays in history. | End after Round {r}? Under 3 rounds is foreplay. Doesn't count for shit. It stays in history. |
| G-08 | End before Round 1 | Nobody's played a round yet, so there's nothing to count. End it? | Not one round played. End this before it starts? | = |
| G-09 | Game end, didn't count | Under 3 rounds, so this one doesn't count. Bragging rights only. | = | Under 3 rounds, so this one doesn't count. Talk all the shit you want, it's not on the record. |
| G-10 | Late join | {name} is in from Round {r}, starting at {score}. | = | = |

## 9. History and corrections (H)

| ID | Moment | Clean | Spicy | Unhinged |
|---|---|---|---|---|
| H-01 | Edit "What changes" header | Here's who this hurts. | Here's who this screws. | = |
| H-02 | Someone else edited (banner) | {name} fixed Round {r}. Check On the record. | = | = |
| H-03 | On the record, empty | No edits. Everyone's either honest or careful. | = | = |
| H-04 | Finished game | Final. Locked. Complain all you want; it's not changing. | = | = |
| H-05 | Late offline edit after finish | {name}'s edit arrived after the game was locked, so it wasn't applied. It's on the record. | = | = |
| H-06 | Duplicate round | Two versions of Round {r} came in. Kept the first; the other's here if it was right. | = | = |
| H-07 | History footer | Tap any score to fix it. | = | = |

## 10. Rivalry, profile and leaderboard (R, L)

| ID | Moment | Clean | Spicy | Unhinged |
|---|---|---|---|---|
| R-01 | H2H, they lead big | {name}'s finished ahead of you {n} times. That's not a rivalry, that's a hostage situation. | …a fucking hostage situation. | = |
| R-02 | Gap to level | {gap} behind. Every time you finish ahead of {name}, that's one back. | = | = |
| R-03 | H2H, you lead big | You lead {name} {a}–{b}. Be gracious. Or don't. | = | You lead {name} {a}–{b}. Be gracious. Don't, actually. |
| R-04 | H2H, dead even | {a}–{a}. Somebody has to blink. | = | = |
| R-05 | Nemesis | {name} has finished ahead of you {n} times. Your nemesis. | = | {name} has finished ahead of you {n} times. Your nemesis. Your personal hell. |
| R-06 | Rival widget | {name} {a}, you {b}. {name}'s living in your head rent-free. | = | = |
| L-01 | Your row, under 10 games | {n} of 10. Finish {left} more and you're ranked. | = | = |
| L-02 | Not Yet Ranked header | Still in their first ten. | = | = |
| L-03 | Global unranked count | {n} people are still in their first ten. | = | = |
| L-04 | Close race | {name}'s {gap} ahead of you. Very catchable. | = | {name}'s {gap} ahead of you. Go get the bastard. |
| L-05 | Below a sort's minimum | Needs {n} games for this one. | = | = |
| L-06 | #1 by rating | Top of the board. Everyone hates you now. Good. | = | = |

## 11. Notifications (N), offline (F), errors (E), taunt system (T)

All N- strings ≤ 60 characters.

| ID | Moment | Clean | Spicy | Unhinged |
|---|---|---|---|---|
| N-01 | Saved you a seat | {host} saved you a seat at {word}. | = | = |
| N-02 | Made the leaderboard | You're on the board. {rating}. No more hiding. | = | = |
| N-03 | Badge earned away | You earned {badge}. Go look. | = | = |
| N-04 | Guest claimed | {name} claimed their games. You did this. | = | = |
| N-05 | Self-report nudge (Live Activity) | Round {r}: your hand. The table's waiting. | …waiting a fucking while. | = |
| N-06 | Live Activity stale | Last update {time} · Open Kedro to catch up | = | = |
| N-07 | Nearby alert | {name} started a table nearby. | = | = |
| N-08 | Receipt received | {name} sent you a receipt from {word}. | = | = |
| N-09 | Wrapped is ready | Your {year} in Kedro is ready. Brace yourself. | = | Your {year} in Kedro is ready. It's a lot. |
| F-01 | Offline, peers in sync | Offline · {n} phones in sync | = | = |
| F-02 | Offline, solo | Offline · saved on this phone | = | = |
| F-03 | Syncing | Syncing… | = | = |
| F-04 | App Clip offline | This needs internet. Ask {host} to report your hand for now. | = | = |
| F-05 | Offline explainer | No internet? No problem. Phones at a table talk to each other directly. | No internet? Who gives a shit. Phones at a table talk… | = |
| E-01 | Server error | Our servers fell over. Your game's safe on this phone. | Our servers shat the bed. Your game's safe on this phone. | = |
| E-02 | Nearby permission denied | Kedro can't see the table without Local Network. Turn it on in Settings, or use the QR code. | = | = |
| E-03 | Couldn't join | Couldn't reach {host}'s phone. Move closer or scan their QR code. | = | = |
| E-04 | Under 3 seats | Cambio needs 3. Two people is just a staring contest. | = | = |
| T-01 | Talk sheet title | Talk your trash | Talk your shit | = |
| T-02 | Custom field placeholder | Say it. 80 characters. | = | Say it. 80 characters. Make them count. |
| T-10 | Rate limit | Save some for the next round. | = | Save some for the next round, motormouth. |
| T-11 | Muted (to sender, never) | (silent: the sender isn't told) | | |
| T-12 | Blocked by filter | That one's not going out. Kedro doesn't do slurs. | = | = |
| T-13 | Reported (to reporter) | Reported. You won't see it again. | = | = |

## 12. Canned taunt library

Each renders in the **recipient's** level. The full library targets ~150 taunts at launch; TT-15 onward are the launch lines kept in the app (`Features/Talk/TauntLibrary.swift`, which must match this table).

| ID | Group | Clean | Spicy | Unhinged |
|---|---|---|---|---|
| TT-01 | Knocks (at a knocker) | Knocking on that? Brave. | = | Knocking on that? Brave as shit. |
| TT-02 | Knocks | Knock now. I dare you. | = | Knock now. I fucking dare you. |
| TT-03 | Knocks (after a fail) | +10. Worth it? | = | +10. Worth it, dumbass? |
| TT-04 | Red Kings | Enjoy that red King. It's the last nice thing you'll get. | = | = |
| TT-05 | Leader | Comfortable up there? | = | Comfortable up there, you smug bastard? |
| TT-06 | Leader | It's a long game. | = | It's a long game, asshole. |
| TT-07 | Last place | Have you tried being lower? | = | Have you tried being lower, genius? |
| TT-08 | Last place | Thoughts and prayers. | = | = |
| TT-09 | Comebacks | I'm coming for you. | = | I'm coming for your ass. |
| TT-10 | General | Scoreboard. | = | = |
| TT-11 | General | Talk is cheap. Your hand isn't. | = | = |
| TT-12 | General | No notes. | = | No notes. Just disgust. |
| TT-13 | General | Somebody's sweating. | = | Somebody's sweating fucking bullets. |
| TT-14 | General | Deal faster. | = | Deal faster, I'm aging over here. |
| TT-15 | Knocks | Last turns. Make them count. | = | Last turns. Make them fucking count. |
| TT-16 | Knocks | Bold knock. Let's see the cards. | Bold knock. Let's see the damn cards. | Bold fucking knock. Cards up. |
| TT-17 | Knocks | That knock smells like a bluff. | That knock smells like bullshit. | = |
| TT-18 | Knocks | Knocked into a wall. | Knocked straight into a damn wall. | Knocked face-first into a wall, dumbass. |
| TT-19 | Knocks | Ten points for confidence. | = | Ten points for confidence. Zero for brains. |
| TT-20 | Knocks | That knock aged badly. | That knock aged like shit. | = |
| TT-21 | Knocks | Plus ten. Wear it. | = | Plus ten. Wear it, you menace. |
| TT-22 | Knocks | Fine. That one was clean. | Fine. That one was clean as hell. | = |
| TT-23 | Knocks | Minus ten. Don't get used to it. | = | Minus ten. Don't get fucking used to it. |
| TT-24 | Knocks | Lucky knock. Say it with me: lucky. | = | Lucky fucking knock. Say it. |
| TT-25 | Knocks | Tied. All that drama for nothing. | Tied. All that drama for shit. | = |
| TT-26 | Knocks | A tie. The most boring outcome. | A tie. Boring as shit. | = |
| TT-27 | Knocks | Knock already. We're waiting. | = | Knock already. We're fucking waiting. |
| TT-28 | Knocks | Scared to knock? Understandable. | = | Scared to knock? Understandable, coward. |
| TT-29 | Knocks | You're not knocking on that. Right? | = | You're not knocking on that. Right, genius? |
| TT-30 | Knocks | Somebody knocked. Everybody panic. | Somebody knocked. Shit's getting real. | = |
| TT-31 | Red Kings | Red King bailout. Must be nice. | = | Red King bailout. Must be fucking nice. |
| TT-32 | Red Kings | Saved by royalty. Embarrassing. | = | Saved by royalty, you lucky bastard. |
| TT-33 | Red Kings | That red King did all the work. | That red King did all the damn work. | = |
| TT-34 | Red Kings | Below zero. Show-off. | = | Below zero, you show-off bastard. |
| TT-35 | Red Kings | Who's hiding the red King? | Who's hiding the damn red King? | Who the fuck has the red King? |
| TT-36 | Red Kings | I can smell a red King from here. | = | = |
| TT-37 | Red Kings | Red King or not, you're in trouble. | Red King or not, you're in deep shit. | = |
| TT-38 | Red Kings | One card carried that whole round. | = | One card carried your sorry ass. |
| TT-39 | Red Kings | Peek at your cards. Go on. Peek. | = | Peek at your cards. Go on. I'll wait, asshole. |
| TT-40 | Leader | Enjoy the view. It won't last. | = | Enjoy the view. It won't fucking last. |
| TT-41 | Leader | First place looks nervous. | First place looks nervous as hell. | = |
| TT-42 | Leader | The crown's on loan. | = | The crown's on loan, dickhead. |
| TT-43 | Leader | Leading means nothing until it's final. | Leading means shit until it's final. | = |
| TT-44 | Leader | Big lead. Bigger target. | Big lead. Bigger target on your ass. | = |
| TT-45 | Leader | Every leader blows it eventually. | = | Every leader bottles it eventually. Your turn. |
| TT-46 | Leader | Somebody knock that one down a peg. | Somebody knock that smug ass down a peg. | = |
| TT-47 | Leader | You peaked. Respectfully. | = | You peaked. Respectfully, fuck you. |
| TT-48 | Leader | Nice lead. Shame about the rest of the game. | = | Nice lead. Shame about the rest of the damn game. |
| TT-49 | Leader | Wire to wire? Not on my watch. | = | Wire to wire? Not on my fucking watch. |
| TT-50 | Leader | Don't get comfortable. | Don't get comfortable, smartass. | = |
| TT-51 | Last place | The bottom has a great view of everyone. | = | = |
| TT-52 | Last place | Last place is a choice. Bold one. | Last place is a choice. A shit one. | = |
| TT-53 | Last place | Someone has to be last. Thanks for volunteering. | = | Someone has to be last. Thanks for volunteering, genius. |
| TT-54 | Last place | Rock bottom called. It wants its seat back. | = | = |
| TT-55 | Last place | Cooked. Fully cooked. | Cooked. Fully fucking cooked. | = |
| TT-56 | Last place | Still time. Not much, but some. | = | Still time. Not a lot, but some, dumbass. |
| TT-57 | Last place | Is the plan to lose on purpose? | = | Is the plan to lose on purpose, or what the hell? |
| TT-58 | Last place | Last place. Say something. | = | Last place. Say something, loser. |
| TT-59 | Last place | Thoughts, prayers and a calculator. | = | = |
| TT-60 | Last place | That score's a cry for help. | That score's a damn cry for help. | That score's a fucking cry for help. |
| TT-61 | Comebacks | Check your mirrors. | Check your damn mirrors. | Check your mirrors, asshole. |
| TT-62 | Comebacks | Gap's closing. Feel it? | = | Gap's closing. Feel it, you bastard? |
| TT-63 | Comebacks | Remember this round. I will. | = | Remember this round. I fucking will. |
| TT-64 | Comebacks | Comeback loading. | = | Comeback loading. Brace your ass. |
| TT-65 | Comebacks | Down isn't out. | Down isn't out. Not by a damn mile. | = |
| TT-66 | Comebacks | I've been worse. Then I won. | I've been in worse shit. Then I won. | = |
| TT-67 | Comebacks | Watch me climb. | = | Watch me climb, assholes. |
| TT-68 | Comebacks | Two rounds. That's all I need. | = | Two rounds. That's all I fucking need. |
| TT-69 | Comebacks | Nobody's safe. Least of all you. | = | Nobody's safe. Least of all your smug ass. |
| TT-70 | Comebacks | Hope you saved some luck. | Hope you saved some luck. You'll damn well need it. | Hope you saved some luck. You'll fucking need it. |
| TT-71 | General | Your game face needs work. | = | Your game face needs fucking work. |
| TT-72 | General | I saw that look. | = | I saw that look. You're fucked. |
| TT-73 | General | Count your cards. Then count again. | = | = |
| TT-74 | General | Big talk for someone with that hand. | Big talk for someone with that shit hand. | = |
| TT-75 | General | Interesting strategy. Wrong, but interesting. | = | Interesting strategy. Wrong as hell, but interesting. |
| TT-76 | General | Somebody's bluffing. | = | Somebody's bluffing their ass off. |
| TT-77 | General | Quiet over there. Suspicious. | Quiet over there. Suspicious as hell. | Quiet over there. Suspicious as fuck. |
| TT-78 | General | That swap was a mistake. | That swap was a damn mistake. | That swap was a fucking mistake. |
| TT-79 | General | Stop memorizing. It's not helping. | = | Stop memorizing. It's not helping, genius. |
| TT-80 | General | Whatever you're planning, no. | Whatever the hell you're planning, no. | = |
| TT-81 | General | Shuffle like you mean it. | = | Shuffle like you fucking mean it. |
| TT-82 | General | Play faster. The table has plans. | = | Play faster, for fuck's sake. |
| TT-83 | General | This is my table now. | This is my damn table now. | This is my fucking table now. |
| TT-84 | General | Menace behavior. Respect. | = | = |
| TT-85 | General | Act natural. You're failing. | = | Act natural. You're failing, dumbass. |
| TT-86 | General | Every card you touch turns to garbage. | Every card you touch turns to shit. | = |
| TT-87 | General | Somebody's about to get humbled. | Somebody's about to get humbled as hell. | Somebody's about to get fucking humbled. |
| TT-88 | General | I've seen better hands on a clock. | = | = |
| TT-89 | General | Last round. No pressure. | = | Last round. No pressure, asshole. |
| TT-90 | General | One round left. Finish strong. Or don't. | = | One round left. Don't fuck it up. |
| TT-91 | General | Receipts are coming. | = | Receipts are fucking coming. |
| TT-92 | General | Say less. Play more. | = | Say less. Play more, motormouth. |

## 13. Receipts (RC)

Pre-written only. One per rival per finished game. Outbound images default to Clean.

| ID | Situation | Clean | Spicy | Unhinged |
|---|---|---|---|---|
| RC-01 | You won | Scoreboard. | = | Scoreboard, dickhead. |
| RC-02 | They failed a knock | Knocking on {hand} is a choice. A bad choice. | …A shit choice. | = |
| RC-03 | Rematch | Run it back. I'll go easy. (I won't.) | …(I fucking won't.) | = |
| RC-04 | Chasing them | Gap's {gap}. Sleep with one eye open. | = | Gap's {gap}. Sleep with one eye open, asshole. |
| RC-05 | They finished last | Last place looked good on you. | = | Last place looked fucking great on you. |
| RC-06 | You beat their knock | Your knock. My {low}. Remember that. | = | = |

## 14. Badge lines

| Badge | Clean | Spicy | Unhinged |
|---|---|---|---|
| Out of the Gate | One down. The bar was low and you cleared it. | = | = |
| First Blood | First win. Screenshot it. | First win. Holy shit, screenshot it. | = |
| On the Board | Ten games, one number. No more hiding. | = | = |
| Regular | Twenty-five games. It's a habit now. | = | Twenty-five games. Get help. |
| Touch Grass | A hundred games. Genuinely, go outside. | = | = |
| Top Dog | #1 among your people. Everyone hates you now. Good. | = | = |
| Top 100 | Top 100 on Earth. At a card game. Respect. | = | = |
| Landed It | −10. Felt great, didn't it. | −10. Felt fucking great, didn't it. | = |
| Found Out | Knocked and got beaten. +10 for the audacity. | = | = |
| Dead Heat | Technically not a loss. Technically. | = | = |
| Bold Choice | Knocked on double digits and got beaten. We love the confidence. | = | = |
| Hat Trick | Three landed knocks in one game. Show-off. | = | = |
| Steady Hand | Ten straight. Ice in the veins. | Ten straight. Ice in the fucking veins. | = |
| Below Zero | Sub-zero hand. Sneaky. | Sub-zero hand. Sneaky shit. | = |
| Ghost Hand | Zero. Not a single point. | Zero. Not a goddamn point. | = |
| Royal Pair | Both red Kings. Ruthless. | Both red Kings. Filthy. | = |
| Nothing to See Here | Knocked on zero and landed it. Smooth. | …Smooth as hell. | = |
| Fat Stack | 40 or more in one hand. Bad sticks have consequences. | = | 40 or more in one hand. Bad sticks have fucking consequences. |
| Three-Peat | Three straight. Insufferable. | = | = |
| Untouchable | Five straight. People are starting to talk. | …starting to talk shit behind your back. | = |
| Comeback Kid | Behind at halfway. Won anyway. Disrespectful. | …Disrespectful as hell. | = |
| Dark Horse | Every opponent rated higher. Nobody saw that coming. | …Nobody saw that shit coming. | = |
| Never Trailed | Led every round. Didn't even break a sweat. | = | = |
| By a Hair | Won by a single point. Talk your trash, you've earned it. | …Talk your shit… | = |
| Shared Spoils | Half the glory, all the arguing. | = | = |
| Bottled It | Led into the final round and lost. Choked. | …Fucking bottled it. | = |
| Nemesis Tamed | Finished ahead of your nemesis. About time. | …About fucking time. | = |
| Grudge Match | Ten games with the same person. It's a relationship now. | = | = |
| Exorcism | Three straight over your nemesis. Demons: gone. | = | = |
| Plays Well With Others | Ten different people put up with you. Impressive. | = | = |
| Full House | Eight at one table and nobody stormed out. | = | = |
| Bad Influence | Someone you dragged into this made an account. You did this. | = | = |
| Trash Talker | Fifty taunts sent. Mouth like a sewer. | = | = |
| Did the Reading | Finished the lessons. Respect. | = | = |

## 15. Dealer (D)

| ID | Moment | Clean | Spicy | Unhinged |
|---|---|---|---|---|
| D-01 | Next-deal nudge (5 s after save) | Next deal: {name}. | = | = |
| D-02 | Dealer line (banter slot, occasional) | {name} deals. Watch the bottom of the deck. | = | {name} deals. Watch their fucking hands. |
| D-03 | Dealer line | {name}'s dealing. Cut it twice. | = | = |
| D-04 | Dealer who just failed a knock | {name} deals. Still recovering from that knock. | = | {name} deals. Still smells like that knock. |
| D-05 | Dealer is the leader | The leader deals. Of course they do. | = | The leader deals. Rigged as hell. |
| D-06 | Dealer changed (audit, literal) | {name} set the dealer to {name2}. | = | = |
| D-07 | Lobby footer (literal) | Drag seats to match where people are sitting. The deal goes left. | = | = |

## 16. Titles (TI)

Rendered in the **viewer's** level. Most titles are the same in every level.

| ID | Title | Clean | Spicy | Unhinged | Tagline on the profile (all levels unless noted) |
|---|---|---|---|---|---|
| TI-01 | Fresh Meat | Fresh Meat | = | = | First ten games. Be gentle. (Unhinged: Don't be gentle.) |
| TI-02 | Regular | Regular | = | = | Twenty-five games and counting. |
| TI-03 | Untouchable | Untouchable | = | = | Five straight wins. Once. |
| TI-04 | The Ghost | The Ghost | = | = | Has held a hand worth nothing. |
| TI-05 | Royalty | Royalty | = | = | Both red Kings. One hand. |
| TI-06 | Comeback Kid | Comeback Kid | = | = | Never count them out. |
| TI-07 | Dark Horse | Dark Horse | = | = | Beat a table rated higher across the board. |
| TI-08 | Exorcist | Exorcist | = | = | Beat the nemesis three straight. |
| TI-09 | Bad Influence | Bad Influence | = | = | Dragged a guest into this for good. |
| TI-10 | Stirrer | The Stirrer | Shit-Stirrer | = | Fifty taunts sent. |
| TI-11 | Touch Grass | Touch Grass | = | = | A hundred games. Concerning. |
| TI-12 | The Closer | The Closer | = | = | Best knock success among their people. |
| TI-13 | Knock Merchant | Knock Merchant | = | = | Knocks more than anyone they play with. |
| TI-14 | The Snake | The Snake | = | = | Beats other people's knocks for sport. |
| TI-15 | The Accountant | The Accountant | = | = | Lowest average round. Boring. Effective. |
| TI-16 | Red King Magnet | Red King Magnet | = | = | Red Kings just find them. |
| TI-17 | Top Dog | Top Dog | = | = | #1 among their people. |
| TI-18 | The Bottler | The Bottler | = | = | Blew more final-round leads than anyone. Wears it proudly. |
| TI-19 | Title lost | {name} took {title} off you. | = | {name} took {title} off you. Rude as hell. | (Since you last looked) |

## 17. Hall of Shame (HS)

| ID | Category / moment | Clean | Spicy | Unhinged |
|---|---|---|---|---|
| HS-01 | Screen subtitle | The worst moments among your people. Moments, not people. Mostly. | = | = |
| HS-02 | Worst Hand | {name} held {hand}. That's not a hand, that's a yard sale. | = | {name} held {hand}. That's not a hand, that's a fucking yard sale. |
| HS-03 | Worst Knock | Knocked on {hand} into a {low}. Historians will study it. | = | Knocked on {hand} into a {low}. Historians will study this shit. |
| HS-04 | Biggest Loss | {score} points in one game. A personal best, in the wrong direction. | = | {score} points in one game. Spectacularly shit. |
| HS-05 | Bottle Job | Up by {gap}. Didn't win. | Up by {gap}. Didn't win. Bottled it. | Up by {gap}. Didn't win. Bottled it like a little shit. |
| HS-06 | Ate It | {n} failed knocks in one game. Commitment to the bit. | = | {n} failed knocks in one game. Fucking committed to the bit. |
| HS-07 | Deepest Hole | {gap} behind the leader at one point. Spelunking. | = | {gap} behind. Dug straight to hell. |
| HS-08 | Game-end induction card | New Hall of Shame entry: {category}. Congratulations, {name}. | = | New Hall of Shame entry: {category}. Congratulations, you absolute disaster. |
| HS-09 | Since you last looked (wasn't there) | {name} made the Hall of Shame: {category}. | = | = |
| HS-10 | Empty state | Nobody here yet. Give it a game or two. | = | Nobody here yet. Give it time. Someone will fuck up. |
| HS-11 | Your scope, empty | You're not in here. Suspicious. | = | You're not in here. Suspiciously fucking clean. |

## 18. Kedro Wrapped (WR)

| ID | Card | Clean | Spicy | Unhinged |
|---|---|---|---|---|
| WR-01 | Cover | Your {year} in Kedro. | = | = |
| WR-02 | Cover subline | Let's see the damage. | = | Let's see how fucked up it got. |
| WR-03 | Volume | {games} games. {hours} hours at the table. {people} people put up with you. | = | = |
| WR-04 | Record | {wins} wins. {rate}%. {verdict} | = | = |
| WR-05 | Record verdict, high | Respectable. Annoyingly so. | = | Respectable. Annoying as shit. |
| WR-06 | Record verdict, low | Wins aren't everything. Clearly. | = | = |
| WR-07 | Rating journey | Started at {start}. Peaked at {peak}. Finished at {now}. | = | = |
| WR-08 | Knock | {knocks} knocks. {success}% landed. Favorite knock: {value}. | = | = |
| WR-09 | Worst knock of the year | Knocked on {hand} into a {low} on {date}. We remember. | = | Knocked on {hand} into a {low} on {date}. We will never fucking forget. |
| WR-10 | Nemesis | {name} beat you {n} times this year. They know. | = | {name} beat you {n} times this year. They fucking know. |
| WR-11 | Victim | You beat {name} {n} times. Send flowers. | = | = |
| WR-12 | Card luck | {kings} red Kings. {ghosts} ghost hands. One {big}-point disaster. | = | = |
| WR-13 | The mouth | {taunts} taunts sent. Favorite: "{taunt}". Most taunted: {name}. | = | = |
| WR-14 | Shame year | {n} Hall of Shame entries. A legacy of sorts. | = | {n} Hall of Shame entries. Iconic. Horrible. |
| WR-15 | Persona: The Gambler | THE GAMBLER. You knock like you've got nothing to lose. You usually do. | = | = |
| WR-16 | Persona: The Snake | THE SNAKE. Sitting quietly, ruining knocks. | = | THE SNAKE. Sitting quietly, ruining everyone's shit. |
| WR-17 | Persona: The Accountant | THE ACCOUNTANT. Low, steady, joyless. Effective. | = | = |
| WR-18 | Persona: The Menace | THE MENACE. More taunts than anyone. Some were even good. | = | = |
| WR-19 | Persona: The Closer | THE CLOSER. When you knock, people fold. | = | = |
| WR-20 | Persona: The Comeback | THE COMEBACK. Never ahead. Always winning. Make it make sense. | = | = |
| WR-21 | Persona: The Regular | THE REGULAR. You didn't win the most. You showed up the most. | = | You didn't win the most. You just never fucking left. |
| WR-22 | Persona: The Wildcard | THE WILDCARD. No pattern. No plan. No notes. | = | = |
| WR-23 | Not enough games | Play {left} more games this year to get your Wrapped. | = | = |

## 19. Sounds (SN)

Settings copy. Sound labels are literal.

| ID | Moment | Clean | Spicy | Unhinged |
|---|---|---|---|---|
| SN-01 | Sounds footer | Off by default. Respects your Silent switch. Only the table speaker plays the big moments. | = | = |
| SN-02 | Table speaker explainer | One phone plays the shared sounds so eight phones don't neigh at once. | = | One phone plays the shared sounds so eight phones don't neigh at once like a goddamn stable. |
| SN-03 | Turning sounds on | Sounds on. The neigh is earned, not given. | = | = |

## 20. Literal strings (identical in every level)

Buttons: Sit Down · Ask to Sit · Let {name} In · Remove · New Table · Deal · Record Round {r} · Report Your Hand · Knock · Talk · Send · Next: {name} › · Save Round {r} · Save Change · Undo · Cards · Keep {hand} · Fix {name} · Finish Game · Fix a Round First · Play Another Round · Extend · End Game · End Early · Abandon · Add Player · Restore Game · Run It Back · Send a Receipt · Share Results · Play Again with {name} · Invite with QR · Yes, that's me · Mute Their Taunts · Block · Report · Done.

Fact and verdict lines (templates): "**Round {r}.** {knocker} knocked on {hand}." · inherent knock: "**Round {r}.** {knocker} went out." · imported round with no knock recorded: "**Round {r}.** No knock recorded." · "Landed: −10." · "Tied: {hand}." · "Failed: {hand} + 10 = {score}." · "No penalty: {hand}." · Delta captions: "landed · −10", "tied · {hand}", "failed · {hand} + 10", "no penalty · {hand}".

Rules, the Knock Calculator, permission primers' factual sentence, error fix steps, the audit log ("{name} changed {player}'s R{r} hand {old} → {new} at {time}") and all accessibility labels are literal.

## 21. Enforcement

- **Catalog parity test** (Swift Testing): all three catalogs have identical keys; every `button.*`, `rule.*`, `fact.*`, `verdict.*`, `audit.*`, `a11y.*`, `error.fix.*` string is byte-identical across levels.
- **Banned-term lint** (`bun` script in CI): fails on slurs, gendered insults, disability/mental-illness slurs, and Clean-banned softeners. Runs on all three catalogs and the canned taunt library.
- **Density check:** Spicy must land between 25% and 40% profane strings; Unhinged ≥ 50%.
- **Length check:** glance-surface keys (`la.*`, `island.*`, `notif.*`, `widget.*`, `toast.*`) ≤ 60 characters after substituting the longest realistic values.
