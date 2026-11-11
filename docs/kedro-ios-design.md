# Kedro for iOS: Design Spec
### v1.0 · October 2026

> This is the single design source of truth for the Kedro iPhone app. It consolidates the design tournament winner (Table First v2), the ideas taken from the other entries, and the owner decisions of October 28, 2026 (`docs/design-tournament/RESULTS.md` §8). Requirements live in `docs/kedro-ios-prd.md`; every string lives in `docs/kedro-ios-copy.md` (IDs like **K-06** refer to it). Mockups: `docs/design/mockups.html`.
>
> Where this document and a tournament entry disagree, this document wins.

---

## 1. Thesis

**Kedro keeps the score so nobody else has to, and talks shit the whole time.**

At the table, Kedro is a scoreboard you glance at and a number pad you tap. It never makes the table wait: recording a round is the fastest path in the app, and nothing (no taunt, no banter, no celebration) is ever allowed to block it. Around that fast core, Kedro is loud: every round gets a roast, the standings get running commentary, players fire taunts at each other, and game end is a proper moment. Between games, rivalries, the leaderboard, badges and receipts give people a reason to come back and a reason to play again.

**Copy rule: math first, mouth second.** The fact comes first, then the verdict, then the roast. Delete the joke and the string still works.

**Look: late-night card table.** Dark-first and moody, led by the original Kedro logo: the red retro script over a gritty silver galloping horse. Near-black, Kedro red, cream, silver, and gold for whoever's winning.

---

## 2. Principles

1. **The table comes first.** Recording a round is never slowed down by anything else in the app.
2. **One source of truth.** Every phone shows the same score and the same roast at the same moment.
3. **Transparent, not locked down.** Anyone fixes anything during the game; everything is on the record; finished games are permanent.
4. **Loud, but never in the way.** Trash talk is everywhere, and all of it is skippable, mutable or dismissable.
5. **Apple's chrome, Kedro's soul.** Stock navigation, lists, sheets and controls; the brand lives in the logo, color, type, avatars and voice.

---

## 3. Visual system

### 3.1 Brand assets

| Asset | Use | Notes |
|---|---|---|
| **Full logo** (`Assets.xcassets/Logo`) | Splash, first launch, game-end hero, App Clip card, receipts, share images, empty states | Never recolored, never cropped, never animated except a single fade/scale on splash. Always on a dark surface. Minimum width 160 pt. |
| **Small mark** (to be produced) | App icon, Dynamic Island, widgets, leader badge, notification icon, tab-bar-free places where the full logo can't fit | See §3.2. |
| **Card-suit watermarks** (♠ ♥ ♦ ♣) | Large, faint background texture on Play, game end and the display mode | From the web app. 2–4% opacity, never behind numbers. Turned off with Reduce Transparency. |

The racing-club system from the tournament (silks, the Rail, photo-finish prints, plates, brass and oxblood, New York serif, racehorse names) is **retired** and must not appear.

### 3.2 Small mark (proposal)

The full logo doesn't read below about 120 pt. Three candidates, all derived from the existing artwork; **A is recommended**:

| | Mark | Strengths | Risks |
|---|---|---|---|
| **A (recommended)** | The **script "K"** from the wordmark, in Kedro red with its silver drop shadow, on near-black | Instantly ties to the wordmark; reads at 20 pt; works as a single-color template for tinted icons | Needs a redraw as a clean vector; the K alone is less distinctive than the horse |
| B | The **horse head and mane**, cropped from the logo, in silver on near-black | Distinctive silhouette; strong in the Dynamic Island | The illustration's grit turns to mush below 40 pt; needs a simplified redraw |
| C | **K over horse**: the script K overlapping a simplified horse silhouette | Closest to the full logo | Too busy at 20 pt; only usable at 60 pt and up (app icon, App Clip) |

Deliverables: vector K (A) for template use; app icon via Icon Composer with dark, tinted and clear variants (C or A at 1024 px); a leader badge (A at 14 pt in gold).

### 3.3 Color

Dark is the primary appearance. Light mode exists and is fully supported, but every screen is designed dark first.

| Token | Dark | Light | Use |
|---|---|---|---|
| `night` | #0A0A0E | #F5EFE6 | App background (matches the existing `BrandBackground` asset, so splash doesn't shift) |
| `nightGradient` | #15151C → #08080C | #FBF8F3 → #EFE8DD | Large backgrounds behind the logo (Play header, game end, display mode) |
| `surface` | #13131A | #FFFFFF | Cards, rows, sheets |
| `surfaceRaised` | #1C1C25 | #FFFFFF + shadow | Last-round card, Table card, taunt toasts |
| `rule` | #2A2A33 | #E2DBD0 | Separators |
| `cream` | #F5EFE6 | #14141A | Primary text (inverts in light) |
| `silver` | #C0C0C0 | #5E5E66 | Secondary text, the horse, metadata |
| `silverDim` | #888888 | #8A8A92 | Tertiary text, disabled |
| `kedroRed` | #E63946 | #D42B38 | **The** accent: primary buttons, the logo, you, the focused field, live state |
| `kedroRedDeep` | #B81D2A | #B81D2A | Pressed state, red fills behind cream text |
| `gold` | #F5C842 | #B88A0B | The leader, the winner, rank #1, badges earned. Never text below 17 pt on light. |

Rules:
- **Red never means "bad".** Lower is better in Cambio; a red number is not a warning. Outcomes are encoded by word and glyph (§3.6), not by color.
- **No green.** Not even for "live" or "synced". The sync state is a word.
- **Every number sits on a solid surface.** Glass is only for controls.
- Every text pair is ≥ 4.5:1, with Increase Contrast variants for `silver` and `silverDim`.

### 3.4 Type

| Style | Font | Size (Large) | Use |
|---|---|---|---|
| `score` | **Bebas Neue** | 34 / 28 compact | Cumulative scores, ranks, ratings. Tabular digits; a true minus (−). |
| `display` | Bebas Neue | 40 | Screen heroes: winner name, "ROUND 5 OF 8", leaderboard rank |
| `headline` | Bebas Neue | 22 | Section headers, player names in standings, button-like labels on cards |
| `label` | Bebas Neue, tracked +4% | 13 | Metadata line ("ROUND 6 OF 8 · COLD DECK"), LEADING tag, column heads |
| `body` / `callout` / `footnote` | **SF Pro** (system) | system | Everything you read: facts, verdicts, settings, rules |
| `roast` | SF Pro, italic | callout | The voice line under a fact |
| `pad` | SF Pro Rounded, semibold, monospaced digits | 30 | Number pad keys |

All Bebas styles are registered with `Font.custom(_:size:relativeTo:)` so they scale with Dynamic Type. Bebas is all-caps by design; names in Bebas are shown uppercase and must still be read correctly by VoiceOver (labels use the real casing).

### 3.5 Avatars

A player's avatar is one of:

1. **Photo**: picked with `PhotosPicker` or the camera, cropped to a circle. Moderated by the same report/block flow as custom taunts.
2. **Emoji on a color**: any emoji (system emoji keyboard), on one of 12 background colors from the palette family (no pastels). Default for new accounts: a random emoji from a short starter set on a random color.
3. **Curated**: a launch set of **24 illustrated avatars** in the logo's gritty, silver, hand-inked style, on near-black. Themes: card faces (the Jack, the red King, the Joker), bar objects (the last call glass, the dice, the ashtray), animals in the logo's style (the horse, the wolf, the crow, the bull), and table characters (the shark, the ghost, the hustler). Two are secret, unlocked by badges.

Guests: their initial on `surfaceRaised` with a **dashed silver ring** and the word "guest". Unclaimed guests can't pick an avatar.

Sizes: 44 pt standings, 32 pt compact, 20 pt Live Activity, 96 pt profile. The leader gets a 14 pt **gold K mark** badge on the avatar's top edge plus the word LEADING.

### 3.6 Outcomes

| Outcome | Word | Glyph | Form |
|---|---|---|---|
| Successful knock | **landed** | ✓ (`checkmark`) | Solid cream badge, dark text |
| Tied knock | **tied** | = (`equal`) | Outline badge |
| Failed knock | **failed** | ✗ (`xmark`) | Hatched badge |

The knocker's delta caption is always the math: `landed · −10`, `tied · 5`, `failed · 2 + 10`. Never a bare `+12`.

### 3.7 Motion and haptics

- Score changes: numbers count to their new value over 0.35 s; rows reorder with a spring. Reduce Motion: crossfade only.
- Taunts slide in from the top as a toast and leave on their own after 4 s.
- Game end: the logo lands (scale 1.08 → 1, 0.5 s), the winner's name is set in `display`, and the standings fill in from the bottom. No confetti, nothing bouncing.
- Haptics: `.selection` on pad keys, `.success` on round saved, `.impact(.heavy)` when a live knock is marked. All off with the system haptics setting.

### 3.8 Sound pack

Settings → **Sounds**: a master switch (**off by default**), a per-moment list with toggles and a preview button, and the **Table speaker** setting.

| Moment | Sound | Who hears it |
|---|---|---|
| Live knock marked | Two hard knuckle raps on wood | Table speaker |
| Knock landed | A clean whip crack | Table speaker |
| Knock tied | A flat shrug of a snare hit | Table speaker |
| Knock failed | Crowd groan | Table speaker |
| Red King decided the round | A low, sinister piano sting | Table speaker |
| Round saved | A card snapped onto the table | Saving phone only |
| Taunt received | A short "ooh" from a crowd | The recipient's phone (or Table speaker for "the table") |
| Winner | **The Kedro neigh**: gallop into the horse neigh from the web app (`apps/web/public/neigh.mp4`) | Table speaker, then every phone at game end |
| Dead last | A slow, sarcastic three-note trombone | Table speaker |
| Debut on the board | Gate bell | Table speaker |

Rules:
- **One phone plays the shared moments** so eight phones don't go off at once. The **Table speaker** is the phone in display mode if there is one, otherwise the scorekeeper's phone, otherwise the host's. Any phone can claim it from ⋯ → "Be the table speaker".
- Sounds use the `.ambient` audio session: they **respect the Silent switch**, mix with whatever music is playing, and never duck it.
- Every sound is under 1.5 s except the winner's neigh (3 s). Levels are normalized and quiet by default.
- Sounds never play for a learner's own bad outcome (§4.3).
- v1 ships one pack, **Classic**. The format allows more packs later (for example unlocked by badges).

---

## 4. Voice

Full rules and every string: `docs/kedro-ios-copy.md`. The design rules that shape screens:

### 4.1 Language levels

| Level | What it means | Default |
|---|---|---|
| **Clean** | Same attitude, zero swearing. Sharper words, never "heck" or "f***". | Locked on for under-18s (Declared Age Range) |
| **Spicy** | About a third of lines swear. One swear per line max. | — |
| **Unhinged** | Half or more of lines swear. Affectionate insults at full volume. | Chosen at first launch (§5.1) |

- **Per player.** Each phone renders every string in the viewer's level. Same variant index, different wording, so the table still sees "the same joke".
- **Lock Screen and Live Activity follow the player's level** (owner decision). There is no separate Lock Screen setting.
- **House voice (shared surfaces at a game):** the Table, Round sheet, History, game end and display mode render at the **lowest level of anyone seated**, and Kedro never says who. The lobby shows "Keeping it Spicy tonight: someone at the table asked." The host can lower it further, never raise it.
- **Variants:** each voice moment has 3–6 variants, chosen by a **stable hash** of (gameID, round, key) (FNV-1a, not Swift's `Hasher`, which is seeded per launch), so every phone shows the same line.

### 4.2 Where the voice shows up

| Surface | Voice |
|---|---|
| Last-round card | Fact · verdict · one roast (K-xx) |
| Standings | One **banter line** under the standings, updated only when a round is saved (B-xx) |
| Live knock | Toast on every phone (K-20s) |
| Taunts | Toasts on every phone at the table (§8) |
| Game end | Winner line, last-place line, highlights, badges (W-xx) |
| Play, You, H2H, Leaderboard | Stakes, rivalry lines, eligibility nudges (J-, R-, L-xx) |
| Notifications, widgets, Live Activity | ≤ 60 characters, punchline never truncated (N-xx) |
| Buttons, rules, errors, audit log, accessibility labels | **Literal. Identical in every level.** Enforced by the catalog parity test. |

### 4.3 Learners

For a player's first 3 games (or any seat with learner hints on), **their own** bad outcomes get a teaching line instead of a roast (K-30s). Everyone else still gets roasted.

---

## 5. Getting a table into a game

### 5.1 First launch

1. **Splash**: the full logo on `nightGradient`, fade-in, 1.2 s max.
2. **Welcome**: the logo, "Keep score. Talk shit." (O-01), the subhead (O-02), and three paths:
   - **Sign in with Apple** (shown dimmed with "Soon" while the developer account is pending; the debug test-user sign-in exists only under `#if DEBUG`).
   - **Play as a guest**: first name only. A claim token is stored on the device, so signing in later claims everything automatically.
   - Footer: "New to Cambio? Learn it in 2 minutes" (O-04) and "Got a claim code?"
3. **How filthy?**: pick **Clean / Spicy / Unhinged**, each with a live sample line (O-06). Unhinged is preselected for adults. Changeable any time in Settings.
4. **Your face and handle**: photo, emoji or curated avatar (§3.5), skippable (a random emoji is assigned); and a unique **@handle**, suggested from the first name (@noah, @noah.k) and changeable later.

No permission prompts at launch. Local Network, Nearby Interaction, Bluetooth and notifications are each asked in context, after a one-line primer.

### 5.2 Transport

- **Primary: iOS 26 Network framework**, peer-to-peer (Bonjour `_kedro-table._tcp`, AWDL enabled). The host runs a `NetworkListener`; others browse with `NetworkBrowser` and connect with `NetworkConnection` over TLS-PSK derived from the table token. The TXT record carries the table ID, host name, seat count, round state and the table word.
- **Fallback: MultipeerConnectivity**, behind a remote flag, if no peer-to-peer path is up within 5 s.
- **Nearby Interaction (UWB):** distance under ~3 m labels a table **At your table**; anything farther is **Other tables nearby**. Without UWB, tables are ordered by played-with overlap, and the **table word** settles it.
- **Table word:** every table gets a two-word name from a curated card-and-bar list (*Cold Deck, Last Call, Dead Hand, Top Shelf, Burnt Card, Back Room, Short Stack, Wild Joker*…). Shown in the Table header and on the Table card, and regenerable in the lobby.
- **Online:** Supabase Realtime and APNs. The backend is just another peer.

### 5.3 The Table card (from Ambient Table)

When Kedro is opened (or brought to the foreground) and a table is advertising nearby, a **Table card** rises from the bottom of Play, above everything else:

> **MAYA'S TABLE** · COLD DECK
> At your table · 0.6 m
> (avatars of who's seated) Maya, Noah, Ana + 1 guest
> Stakes line (J-01): "Your 10th game. Finish it and you're on the board."
> **[ Sit Down ]**

- **Played-with players and anyone the host already added: Sit Down seats you immediately.** The host gets a 5 s non-modal toast: "Ana sat down · Remove" (J-03).
- **Strangers:** Sit Down becomes **Ask to Sit**. The host (or any seated phone) gets "Jo wants a seat. You've never played together, so it's your call. · Let Jo In" (J-02).
- **Several tables nearby:** the card shows the closest; a "2 other tables nearby" link opens the list with table words.
- Dismissing the card moves the table to a Nearby row on Play.

### 5.4 Nearby alert (opt-in)

- Offered in context after a player's **second finished game**: "Want a heads-up when your people start a table nearby?" (J-14).
- If on: seated phones advertise a Kedro Bluetooth service UUID in the foreground; opted-in phones scan in the background and get a notification **"Maya started a table nearby."** (N-07). Max 3 per day, never during your own game, and never for strangers' tables (played-with only).
- Bluetooth is never used for game state.
- **Risk to track:** background Bluetooth is App Review–sensitive and its proximity is approximate. The copy never promises distance ("nearby", never "at your table").

### 5.5 "Saved you a seat"

When a host adds someone from their played-with list who isn't sitting yet, that person gets a push: **"Maya saved you a seat at Cold Deck."** (N-01). Tapping it opens Kedro straight into the Table card with **Sit Down** focused (or seats them directly if they're already nearby).

### 5.6 The lobby (New Table)

One grouped `List`, no wizard:

- **Table:** host name and the table word (regenerate).
- **Seats · 5 of 8:** reorderable (`onMove`) rows in clockwise order. Each row: avatar, name, role line (*Host*, *Scorekeeper*, *Guest · Ben reports for Sam*, *Played 21 together*), a ⋯ menu (Make scorekeeper · Assign reporter · Move · Remove). Seats added but not yet linked to a phone show "Seat saved · waiting for their phone".
- **Add:** three rows.
  - **Add Players:** one list to pick from, multi-select, no typing needed. Sections: **Nearby** (hosts and players at tables this phone can see), **Played With** (most recent first), then **Everyone** (every other Kedro player A–Z, loaded a page at a time). Rows show the avatar, handle, and "Played 3 together" or "Never played". The search field on top narrows every section and, from 2 characters, searches Kedro by display name or **@handle** ("On Kedro"). Blocked people never appear. Adding someone is the host vouching for them, so they're admitted without Ask to Sit. The list also has **Add a Guest** at the top.
  - **Guest:** a name only. Typing "Sam" suggests "Sam · guest · 2 games with you", so one guest identity builds up history.
  - **Invite with QR:** the rotating QR for anyone in the room. It opens the app if installed, or the App Clip if not. The same link can go by **AirDrop**.
- Everyone added from Add Players gets the "saved you a seat" push (§5.5).
- **Game:** Rounds (5 · 6 · 8 · 10 · Custom; default: last time's), **First deal** (default: the host; §6.4), Scoring (**Scorekeeper** | **Everyone reports**), House voice (read-only line plus "Keep it cleaner tonight").
- **Stakes:** 1–2 lines (J-xx).
- **Deal** (kedroRed, primary). Disabled under 3 seats with "Cambio needs 3. Two people is just a staring contest." (E-04).

After **Deal**, every phone flips into the Table and starts its Live Activity.

### 5.7 Mid-game and rematch

- **Seated player whose phone joins late:** Sit Down matches their seat by account. A guest taking over their seat on a phone confirms "Is this Sam? · Yes, that's me" (logged).
- **New person after Round 1:** any seated player adds them from ⋯ → **Add Player** (the same Add Players list). They play from the next round, start at the **highest total at the table** at that moment, and take the last seat in the dealing order; whoever was about to deal still deals. A toast says "{name} is in from Round {r}, starting at {score}." (G-10) and On the record logs it. History shows "–" for the rounds before they sat down. They can be removed until they've played a round, and the round before they joined can't be undone (edit it instead). Scanning the table's QR mid-game also seats them this way. A newcomer who finds the table on the Table card instead still gets **Watch** (read-only, can taunt) and is queued for the rematch.
- **Run It Back:** sends every phone an **invitation** with seats, rounds and mode pre-filled; players accept with one tap. Watchers are pre-accepted. The first dealer rotates one seat.

### 5.8 App Clip (guest with an iPhone, no app)

- **Invite with QR** shows a code for `https://playkedro.com/t/{gameID}?k={token}`; the token rotates every 60 s (J-12).
- `playkedro.com` (`apps/site`) serves the `apple-app-site-association` (applinks for `/t/*` and `/s/*`, the App Clip) and a page for each link for people without the app: Android, a desktop, or Safari before the App Clip card shows.
- The App Clip card shows the full logo and "Noah's table. Which one's you?" (J-13) with the unclaimed guest seats. The clip shows the live Table read-only, plus **Report Your Hand** in self-report games, and can send canned taunts.
- It uses the internet (not peer-to-peer), and says so when offline (F-04).
- At game end: the guest's result plus "Get Kedro to keep this" (`.appStoreOverlay`). The claim token goes into the app-group container, so installing and signing in claims the history automatically.

### 5.9 Every way into a game

| # | Who | How | Who starts it | Admission |
|---|---|---|---|---|
| 1 | Kedro player, nearby | **Table card** pops up → **Sit Down** | Player | Instant if you've played with the host or were added; otherwise **Ask to Sit** |
| 2 | Kedro player, nearby, card dismissed | **Nearby** row on Play → Sit Down | Player | Same as 1 |
| 3 | Kedro player, played with before | Host adds from **Add Players** (Played With section) → "saved you a seat" push → tap | Host | Instant (host vouched) |
| 4 | Any Kedro player, never played together | Host adds from **Add Players** (Everyone, or search by name or @handle) → push → tap | Host | Instant (host vouched) |
| 5 | Kedro player whose phone can't see the table (no UWB, Local Network off, crowded bar) | Scan the **QR** or receive it by **AirDrop** → opens Kedro → Sit Down | Either | Instant if played-with; otherwise Ask to Sit |
| 6 | Kedro player, proximity failing entirely | **Join with Code** on Play: type the 2-word table word ("cold deck") | Player | Ask to Sit, unless played-with |
| 7 | Guest with no phone (or no battery) | Host adds a **Guest** by name; a seated player reports for them | Host | Instant |
| 8 | Guest with an iPhone, no app | **QR / AirDrop → App Clip** → "That's me" on their guest seat | Either | Matches the seat the host added; if none, Ask to Sit |
| 9 | Guest who installs mid-game | Signs in → claim token claims the guest seat and history | Guest | Automatic |
| 10 | Seated player whose phone joins late | Sit Down → matched to their seat by account ("Is this Sam? · Yes, that's me" for guests) | Player | Automatic, logged |
| 11 | Someone arriving after Round 1 | A seated player adds them from ⋯ → **Add Player**, or they scan the **QR**; from the Table card they get **Watch** | Any seated player | Late join: next round onward, at the highest total (§5.7) |
| 12 | The same table again | **Run It Back** invitation, one tap to accept | Any player | Pre-accepted for watchers |

Rules that apply to all of them: a table holds 3–8 seats (a full table offers Watch); the host or any seated phone can **Remove** a seat before Round 1, or a late joiner before their first round (logged); and a blocked player can never be added or seated at a table with the person who blocked them.

---

## 6. The Table (live game)

Presented as a `fullScreenCover`; it minimizes into a `tabViewBottomAccessory` mini-bar ("COLD DECK · R6/8 · You 1st · 26") so players can check stats mid-game.

### 6.1 Layout (3–5 players)

1. **Toolbar (glass):** minimize · metadata line "ROUND 6 OF 8" over "COLD DECK · NOAH DEALS" · Rules · History · **End Game** (flag) · ⋯ (Invite, Hand off scorekeeping, Table display, Extend, Add Player, End Game, Abandon). A sync pill appears only when something's unusual (F-01–F-03).
2. **Last-round card** (`surfaceRaised`): fact ("**Round 5.** Noah knocked on 2. Nobody came close."), verdict ("**Landed: −10.**"), roast in `roast` (K-xx). If a red King decided it, the roast is the red King line. **Why?** opens the Knock Calculator, prefilled.
3. **Reactions row** on the last-round card: 5 quick reactions (🔥 💀 🤡 😂 🫡). Counts shown, tap to add yours, one per player per round.
4. **Standings:** rank (shared shown as "2="), avatar 44 pt with a small **D** dealer chip on the current dealer, name in `headline`, LEADING tag in gold for the leader(s), and the player's chosen **title** under the name in `footnote` (§12.7); on the right, the cumulative `score` with the delta under it in words (`landed −10`, `+9`, `failed · 2 + 10`).
5. **Banter line** under the standings, in `roast` (B-xx): one line of running commentary on the standings ("Sam's 21 back with 3 to play. Cooked."). Changes only when a round is saved.
6. **Bottom bar** (glass):
   - **Record Round 6** (kedroRed, prominent; in self-report mode **Report Your Hand**), captioned "You're keeping score · screen stays awake".
   - **Knock** (secondary, `hand.raised`): the optional live knock (§7.5).
   - **Talk** (secondary, `bubble.left.and.text.bubble.right`): the taunt sheet (§8).

### 6.2 6–8 players

Compact rows (54 pt, avatars 32 pt, `score` 28 pt, delta beside the score). Eight rows fit between the last-round card and the bottom bar up to AX1. From AX2 the list scrolls and **your row pins** to the bottom as a `safeAreaInset`.

### 6.3 Table display mode (v1)

A phone or iPad propped up in the middle of the table as a shared scoreboard.

- **Entry:** rotate the phone to landscape on the Table, or ⋯ → **Table display**. On iPad, the Table opens in display mode by default.
- **Layout (landscape):** left third: the full logo, the metadata line, round progress ("ROUND 6 OF 8"), and the last-round card. Right two-thirds: the standings in large `score` type (8 rows fit at 64 pt), the banter line underneath.
- **Taunts and live knocks** appear full-width across the top, larger, for 5 s.
- **Read-only.** No entry from display mode (avoids accidental taps from across the table). A single **Record Round** button is available after a long-press unlock, with a hint.
- Screen stays awake; brightness is not changed. Dark only (forced), because it's on a table at night.

### 6.4 Whose deal it is

- **Seat order is table order.** The lobby's seat list is clockwise around the table, so it doubles as the dealing order. "Drag seats to match where people are sitting" is the lobby's footer hint.
- **First dealer:** chosen in the lobby (a **First deal** row, default the host). On **Run It Back** the first deal rotates one seat.
- **The deal passes one seat to the left** each time a round is saved. Undoing the latest round moves it back. Editing older rounds never changes it.
- **Shown everywhere a player looks:** the Table's metadata line ("COLD DECK · NOAH DEALS"), a **D** chip on the dealer's avatar in the standings, the Live Activity ("Noah deals"), the Dynamic Island expanded view, and display mode.
- **Next-deal nudge:** right after a round is saved, the last-round card's footer reads "Next deal: Ana" (D-01) for the first 5 s, then settles into the metadata line.
- **Fixing it:** tap the D chip or the metadata line → "Who's dealing?" avatar row → tap. Logged in On the record ("Ben set the dealer to Cleo"). Sitting a player out (a guest leaves early) isn't supported; after Round 1 people can only be added (late joins, §5.7), not removed.
- **Voice:** the dealer occasionally gets a line in the banter slot when nothing else is happening (D-02 to D-05), never more than once every 3 rounds.

### 6.5 Attention rules

- Nothing ever covers the **Record Round** button or the Round sheet. Taunts and knock toasts queue while the Round sheet is open and appear after it closes (max 3; older ones collapse into "+2 more in the feed").
- No pushes reach a phone that's seated at a live table.
- The banter line and last-round card change only on round save, edit or undo.

---

## 7. Recording a round

### 7.1 Scorekeeper mode: the number pad

**Inherent knock:** once a knocker is picked, a **Went out (all four cards)** switch sits under "Who knocked?". On, it fills the knocker's hand with 0 and the verdict never shows +10 ("Noah went out · Ben had −2 · no penalty, 0"). Typing any other hand for the knocker turns it off. Fact line: "Round 4. Noah went out." The beaten case has its own outcome, **no penalty** (dashed outline badge).

`.sheet` at `.large`. Top to bottom:

1. **Who knocked?** A row of avatars. One tap selects (red ring + `hand.raised`). **Pre-filled** if someone marked a live knock (§7.5), with "(marked live by Ana)". Save is disabled until a knocker is set.
2. **Player rows**, knocker first, then seat order. Each row: avatar, name, the hand value as typed, and a preview of the round score (`2 → −10`). The focused row has a red outline. Tap any row to jump to it.
3. **Verdict line** under the rows: resolves once the knocker's value and at least one other are in, and updates as values come in ("Noah knocked on 2 · lowest so far · landed −10"). Final verdict (K-18/K-19) when all values are in.
4. **The number pad** (custom, not the system keyboard, so it has the keys Cambio needs):

```
 1   2   3
 4   5   6
 7   8   9
 −   0   ⌫
 [ Cards ]   [ Next: Ana › ]
```

- Keys are 1/3 width × 56 pt, `pad` style, `.selection` haptic.
- **−** toggles the sign of the current value (red Kings: −1 and −2 are the common negatives).
- **Next** commits the value and moves to the next player; on the last player it becomes **Save Round 6** (kedroRed).
- **No upper limit.** Hands above 32 happen (penalty cards from bad sticks); anything up to 999 is accepted.
- **Cards** swaps the pad for Card mode (§7.3).

5. **Save Round 6** dismisses the sheet. Every phone updates, the last-round card and banter line refresh, and the saving phone shows "Round 6 saved · Undo" for 5 s.

### 7.2 Typo guard

At Save, a value is flagged if it's **≥ 25 and at least double the next-highest hand**, or **≥ 45**: an alert "Sam had 52? That's a lot of cards." (K-11) with **Keep 52** / **Fix Sam**. At most once per round, never blocking.

### 7.3 Card mode (learners and disputes)

The card palette replaces the pad: `A 2 3 4 5 / 6 7 8 9 10 / J Q K♠♣ K♥♦ Joker`, drawn as minimal card faces (red Kings marked "−1"). A hand tray shows the cards picked and the running total ("K♥ 3 7 = 9"). ⌫ removes the last card; **Next** is explicit, because hands have different card counts after sticking. After two red Kings in one round, the red King key disables and says why. Card mode is the default for a player's first 3 games and is remembered per user.

### 7.4 Self-report mode

**Report Your Hand** (`.medium` detent): **I knocked** toggle (with **Went out (all four cards)** under it, which sets the hand to 0), the pad (or Cards), **Submit**. Values stay hidden until everyone has reported, then flip together at a shared reveal time on every phone.

Knocker resolution: exactly one "I knocked" → done. Nobody or several → every phone asks "Who knocked?" (K-15/K-16); the first tap is a **proposal** shown everywhere ("Ana says Noah knocked · Change", 5 s ring), which commits unless someone disagrees ("Ana says Noah, Ben says Cleo. Sort it out."). VoiceOver and Switch Control users get an untimed **Confirm**. All logged.

Guests get an **assigned reporter** (default: the player to their left). Stragglers get one Live Activity alert (N-05), never a push.

### 7.5 Live knock (optional)

- **Knock** on the Table's bottom bar → "Who knocked?" avatar row, defaulting to you → tap. One tap if it's you, two if it's someone else.
- Every phone shows a toast: **"Noah knocked. Last turns. Pray."** (K-21) with a heavy haptic, and the display mode shows it big. The Live Activity updates: "Noah knocked · last turns".
- It **pre-fills** the knocker in the Round sheet. Changing it there is allowed and logged.
- **Undo** on the marking phone for 5 s. Only one live knock per round; a second attempt shows "Ana already marked Noah" with **Change**.
- Not marking a knock is fine: the knocker is picked at entry, as always.

### 7.6 What the app computes

One pure function, `roundScores(hands:knocker:)`, implementing PRD §2.6 exactly (strictly lowest → −10 flat; tied for lowest → hand; beaten → hand + 10). Unit-tested against the PRD examples and the sample game (§14). Identical on every device and the server (mirrored in `packages/shared`).

---

## 8. Trash talk

### 8.1 Taunts

**Talk** opens a `.medium` sheet:

1. **At:** avatars of everyone at the table plus **The table** (default: the player who just did something roastable, otherwise The table).
2. **Canned** (default tab): a large library grouped as **Knocks · Red Kings · Leader · Last place · Comebacks · General**, filtered to what's relevant right now (e.g. after a failed knock, the Knocks group shows first). Each taunt has Clean/Spicy/Unhinged variants and **renders in each recipient's level**.
3. **Write your own:** a text field, 80 characters max, run through the filter on send (§8.3). Shown to recipients exactly as written, except Clean recipients see profanity masked (the one place masking is allowed, because it's someone else's words).
4. **Send.**

Delivery: a toast on every seated phone (and the display mode, larger): avatar, "**Ana** → **Noah**", the taunt. Tapping it opens the **feed** (§8.4).

Limits: 3 taunts per player per round; the 4th shows "Save some for the next round." (T-10). Watchers (latecomers and App Clip guests) can send canned taunts only.

### 8.2 Standings banter and automatic roasts

- **Automatic roasts** on the last-round card, every round (K-xx), selected by outcome: landed, tied, failed, failed by 8+, red King decided it, both red Kings, beat the knocker by 1, etc.
- **Banter line** under the standings (B-xx), selected by the state of the game: new leader, a 3+ round lead, a player cooked (needs more than the remaining rounds can give, estimated), comeback in progress, a tie at the top, last round coming.
- Banter states what the estimate is based on when it projects ("needs Ben to fail three knocks" is fine; "has no chance" is not, unless it's mathematically true).

### 8.3 Safeguards for custom taunts (App Store guideline 1.2)

| Requirement | Design |
|---|---|
| Who can receive | Only people **seated at your current table**, or (for receipts) people you've **played with**. Never strangers, never the global board. |
| Filter | On-device and server-side: slurs and identity-based abuse are **blocked** on send ("That one's not going out. Kedro doesn't do slurs." T-12). Profanity is allowed. |
| Report | Long-press (or context menu) any custom taunt → **Report**. Reported taunts are hidden for the reporter immediately and reviewed. |
| Mute / block | From a taunt or a profile: **Mute their taunts** (this game or always) and **Block** (they can't add you to a table, taunt you or send you receipts). |
| Under 18 | Custom taunts are **off** (receive and send) when Declared Age Range reports under 18. Canned taunts only, in Clean. |
| Rate limit | 3 per round per player; custom ones additionally 1 per round. |

### 8.4 The feed

A chronological feed per game: round results, live knocks, taunts, reactions and edits ("Ben changed Sam's R4 hand 1 → −1"). Opened from a taunt toast or the History sheet's **Feed** tab. It's part of the game's permanent record once finished, except reported and blocked content.

### 8.5 Receipts (v1)

After a finished game, each player can send each other player from that game **one receipt**: a share-ready card with the full logo, the result that's being roasted ("Noah knocked on 9 into a 1."), and a canned line (RC-xx). Two ways to send:

- **To the rival in Kedro:** shows up in their Since you last looked and as a passive notification (N-08). Mutable per person.
- **Out of Kedro:** the share sheet with an image card (to a group chat, etc.). Outbound images render **Clean by default**, with a toggle for the sender's level, because the people in that group chat didn't opt in.

Receipts are canned only (no free text) in v1.

---

## 9. History, audit trail and corrections

### 9.1 History sheet

Three tabs: **Scores** (rounds × players grid, knocker cell marked ✓ / = / ✗, Edited tags, pinned totals; scrolls horizontally at 6–8 players; becomes a per-round `List` at AX sizes), **On the record** (every edit: who, when, before → after, downstream effect), **Feed** (§8.4). Footer: "Tap any score to fix it." (H-07).

### 9.2 Corrections

**History → tap the cell → number pad with the old value shown → Save Change** (4 taps). The Save footer lists "What changes" with before → after for every affected score, headed "Here's who this screws." (H-01). Changing the knocker, or any edit that flips a knock outcome, adds a confirmation ("Cleo's knock: failed → landed, 12 → −10. Everyone sees this."). The author of an edit can **Undo** it from On the record until the game finishes.

### 9.3 Extend, end game, abandon, finish

- **Extend** and **Abandon** in ⋯, each with a confirmation, all logged. Abandon can be restored for 15 minutes.
- **End Game:** any seated player, at any time. It's on the Table's toolbar (flag) and in ⋯, and on Play you can swipe or long-press the live game's row to end it without opening the Table. One confirmation that says up front whether the game counts:
  - 3+ rounds: "End after Round {r}? It counts, standings as they are." (G-03) → **End Game** (or **Finish Game** once every planned round is in).
  - 1–2 rounds: "End after Round {r}? Under 3 rounds, so it won't count for stats or the leaderboard. It stays in history." (G-07).
  - No rounds: "Nobody's played a round yet, so there's nothing to count. End it?" (G-08); ending discards it.
  - **Abandon** is offered in the same sheet and gets its own confirmation (G-04).
- **What counts:** a finished game counts for stats, ratings, the leaderboard, badges, titles, the Hall of Shame and Wrapped only with **3+ rounds**, and a player counts in it only with 3+ rounds played (a late joiner may not). The game-end screen of a short game says "Under 3 rounds, so this one doesn't count. Bragging rights only." (G-09).
- **Finish gate:** when the last planned round is saved, the sheet stays on "That's the last round. Lock it in before anyone starts lawyering." (G-01) with **Finish Game**, **Fix a Round First**, **Play Another Round**. Auto-finishes after 15 minutes of inactivity (logged).
- After Finish, editing is gone everywhere: "Final. Locked. Complain all you want; it's not changing." (H-04).

---

## 10. Game end

A full-screen moment, then a scrollable summary:

1. **Hero:** the full logo lands on `nightGradient`; under it, the winner's avatar (96 pt, gold ring), name in `display`, and the winner line (W-01–W-06, picked by how they won: comeback, wire to wire, by 1, shared).
2. **Final standings** with final scores, the knock record per player (✓2 =1 ✗1), and the last-place line (W-10s).
3. **Highlights:** best round, knock record of the table, biggest comeback, the round that decided it.
4. **Ratings:** each player's rating change; a **debut** card for anyone who just finished game 10 ("Ben's on the board. 986." W-05), shown to the whole table.
5. **Badges earned** this game (§12.6), plus a **Hall of Shame** card if the game set a new top-3 moment (§12.8).
6. **Actions:** **Run It Back** (kedroRed), **Send a Receipt**, **Share Results** (image, Clean by default), **Done**.

---

## 11. Offline and sync

- **Operation log**, append-only: `GameCreated`, `PlayerSeated`, `RoundRecorded`, `RoundEdited`, `RoundUndone`, `KnockMarked`, `KnockerProposed`, `KnockerResolved`, `RoundsChanged`, `DealerChanged`, `TauntSent`, `ReactionAdded`, `GameFinished`, `GameAbandoned`, `GameRestored`. Each with a UUID and HLC timestamp, folded in (HLC, deviceID) order. Stored locally in SwiftData; ingested idempotently by the backend.
- **States** (a pill, only when unusual): "Offline · 5 phones in sync" (F-01), "Offline · saved on this phone" (F-02), "Syncing…" (F-03).
- **Conflicts:** later HLC wins for concurrent edits; duplicate rounds keep the earlier and offer **Use this version**; edits after finish don't apply; abandon beats everything except a logged restore.
- **Taunts offline** travel peer-to-peer like any operation; custom taunts are filtered on-device first and re-checked by the server on sync (a taunt that fails the server check is retracted from every phone).
- **Live Activity offline:** local updates while Kedro runs; when suspended, `staleDate` 3 min, then dimmed scores and "Last update 9:46 · Open Kedro to catch up" (N-06).

---

## 12. Stats, rivalries, leaderboard and badges

All derived from the operation log and finished, non-abandoned games of 3+ rounds (early-ended games count if they reach 3; §9.3).

### 12.1 Play tab (between games)

Top to bottom: the **Table card** if one's nearby (§5.3); **Since you last looked** (last result and rating change, board movement, rivalry change, receipts received, guest claims, closest badge); **Tonight's stakes** (one line: rank threshold > pass the player above > level a rivalry > closest badge; facts or labelled estimates); **New Table** (kedroRed) with **Join with Code** beside it (§5.9); the **Wrapped** card in December (§12.9); **Learn Cambio** (first 3 games only); **Recent** games with a **Run It Back** swipe.

### 12.2 You (profile)

Header: avatar 96 pt, name in `display`, the chosen **title** under it in `label` red (tap to change, §12.7), "#13 GLOBAL · 1,086 · +18 TONIGHT", **Form** (last five finishes: 2-1-3-2-1). Then: At a glance (games, wins, win rate, average per round), streaks, knocking (count, rate, landed/tied/failed, success %), best/worst/average game, **Nemesis** (R-05), rivals, badges preview, history (each game with its rating change). Every stat has an ⓘ with the PRD definition. Public: other players see the same view with **Play Again** and **Send a Receipt** (if you've played).

### 12.3 Head-to-head

Two avatars facing off, **"ANA LEADS 12–5"** in `display`, the rivalry line under it (R-01), the gap line ("7 behind. Every time you finish ahead of Ana, that's one back." R-02), the table (games together, finished ahead, wins in shared games, knock outcomes facing each other, average final score together), the last meeting, and **Play Again with Ana**.

### 12.4 Leaderboard (sortable; owner decision)

- **Scope** (segmented): **Played With** (default) | **Global** (opens on "Around me" with a Jump to top).
- **Sort** (menu in the toolbar, `Picker` in a `Menu`): **Rating** (default) · **Win rate** · **Wins** · **Avg score** (lower is better, sorted ascending) · **Knock success**. The header always says what you're looking at: "PLAYED WITH · BY WIN RATE". The rank number shown is the rank **for that sort**.
- **Rating:** multiplayer pairwise Elo from finishing order (ahead = win, equal = draw), K scaled by 1/(n−1), doubled for a player's first 10 games, start **1,000**, rebuilt deterministically by replaying finished games (so edits, claims and migrated history come out right). Computed from game 1, hidden until game 10, then revealed as a debut at game end.
- **Minimums per sort** (on top of the 10-game eligibility): Win rate needs 10 games (the same as eligibility); Knock success needs 15 knocks. Below a sort's minimum, a player is listed after the ranked rows without a number ("needs 10 games for this one").
- **Your row** is pinned with your neighbours. If the player above you (by the current sort) is close (within 15 rating points, 2% win rate, 1 win), your row says so (L-04).
- **Records** (a 2 × 2 grid under the pinned row): Best game · Longest win streak · Most successful knocks · Most games. Each pushes to a top-25 board. Under the grid, a full-width **Hall of Shame** row pushes to §12.8.
- **Not Yet Ranked:** players under 10 games appear below the board with a **10-step progress meter** ("3 of 10") and no number (L-02). Global shows the count ("1,214 people are still in their first ten."). Your own row under 10 games reads L-01. Unclaimed guests never appear.

### 12.5 Play-more incentives

| Where | What |
|---|---|
| Everywhere an unranked player appears | The 10-step meter ("3 of 10"): Table card, lobby seat, profile, board, widget, game end |
| Table card and lobby | Stakes lines (J-01: "Your 10th game. Finish it and you're on the board.") |
| Game 10 | The debut, revealed to the whole table |
| Game end | Rating change, rank movement, badges, the next goal ("Two more straight for Three-Peat."), Run It Back |
| Head-to-head | Gap line, Play Again |
| Leaderboard | Pinned row with neighbours, close races, Not Yet Ranked meters |
| Receipts | One per rival per game |
| Badges | **Next up**: the 3 closest, each with a progress meter; secret badges |
| Widgets | Standing (with the meter under 10 games), Rivalry, Next Badge |

Guardrails: no loss-framed pushes ("you were passed" only appears in Since you last looked), no streak-at-risk, no "we miss you", no countdowns, nothing paid.

### 12.6 Badges ("Bragging Rights")

Badges are shown as dark coins with the small mark struck in the center, rimmed by tier: **Silver** (most players), **Red** (10–40%), **Gold** (under 10%). The category is shown as an icon on the rim. Evaluated at game finish and on guest claims only. Public on profiles, in the viewer's level. Grid grouped by category; **Next up** shows the 3 closest with progress; detail shows the badge large, the line, the game it was earned in and "Earned by 18% of players".

| # | Badge | Category | Tier | Rule |
|---|---|---|---|---|
| 1 | Out of the Gate | Milestone | Silver | Finish your first game |
| 2 | First Blood | Milestone | Silver | Win a game (shared wins count) |
| 3 | On the Board | Milestone | Silver | Finish 10 games and get a rank |
| 4 | Regular | Milestone | Red | Finish 25 games |
| 5 | Touch Grass | Milestone | Gold | Finish 100 games |
| 6 | Top Dog | Milestone | Gold | #1 by rating on your Played With board (≥ 5 ranked people) |
| 7 | Top 100 | Milestone | Gold | Global top 100 by rating |
| 8 | Landed It | Knocking | Silver | First successful knock |
| 9 | Found Out | Knocking | Silver | First failed knock |
| 10 | Dead Heat | Knocking | Silver | A tied knock |
| 11 | Bold Choice | Knocking | Silver | Knock on 10 or more and fail |
| 12 | Hat Trick | Knocking | Red | 3 successful knocks in one game |
| 13 | Steady Hand | Knocking | Gold | 10 successful knocks in a row (career) |
| 14 | Below Zero | Cards | Red | Finish a round with a negative hand |
| 15 | Ghost Hand | Cards | Red | A hand of exactly 0 |
| 16 | Royal Pair | Cards | Gold | Both red Kings in one hand (−2) |
| 17 | Nothing to See Here *(secret)* | Cards | Gold | Land a knock on exactly 0 |
| 18 | Fat Stack | Cards | Silver | A hand of 40 or more (the bad-stick badge) |
| 19 | Three-Peat | Streaks | Red | Win 3 in a row |
| 20 | Untouchable | Streaks | Gold | Win 5 in a row |
| 21 | Comeback Kid | Moments | Red | Win from outside the lead at the halfway round |
| 22 | Dark Horse | Moments | Gold | Win where every opponent had a higher rating |
| 23 | Never Trailed | Moments | Gold | Lead or share the lead after every round of a 6+ round game, and win |
| 24 | By a Hair | Moments | Red | Win by exactly 1 point |
| 25 | Shared Spoils | Moments | Red | Share a win |
| 26 | Bottled It *(secret)* | Moments | Red | Lead after the second-to-last round, then lose |
| 27 | Nemesis Tamed | Rivalry | Silver | Finish ahead of your current nemesis |
| 28 | Grudge Match | Rivalry | Red | Play the same rival 10 times |
| 29 | Exorcism *(secret)* | Rivalry | Gold | Finish ahead of your nemesis in 3 straight shared games |
| 30 | Plays Well With Others | Social | Silver | Play with 10 different people |
| 31 | Full House | Social | Red | Finish an 8-player game |
| 32 | Bad Influence | Social | Red | A guest you played with claims their history and finishes a game on their own account |
| 33 | Trash Talker | Social | Silver | Send 50 taunts |
| — | Did the Reading | Learning | — | Finish Learn and the Score a Round drill |

Anti-farming: social and rivalry badges count only accounts and claimed guests, and only completed, non-abandoned games. Bad Influence counts once per guest, and that guest needs a completed game with someone other than you. Trash Talker counts at most 3 taunts per game. Two curated avatars unlock with secret badges (Exorcism → the Ghost; Nothing to See Here → the Hustler).

### 12.7 Titles

A title is a short label under a player's name: on the Table, the Table card, the leaderboard, profiles, head-to-head and receipts. Each player picks one from the titles they've earned (or **No title**) from their profile header. Titles render in the **viewer's** language level (TI-xx in the copy deck).

**Two kinds:**
- **Earned** titles are permanent, unlocked by a badge.
- **Held** titles are recalculated after every finished game, among the people you've played with (at least 5 ranked people), and can be **lost**. Losing a displayed title quietly switches you to your best earned one and adds a line to Since you last looked ("Ana took Knock Merchant off you.").

| Title | Kind | How you get it |
|---|---|---|
| Fresh Meat | Earned | Default for your first 10 games |
| Regular | Earned | Badge: Regular (25 games) |
| Untouchable | Earned | Badge: Untouchable (5 wins in a row) |
| The Ghost | Earned | Badge: Ghost Hand |
| Royalty | Earned | Badge: Royal Pair |
| Comeback Kid | Earned | Badge: Comeback Kid |
| Dark Horse | Earned | Badge: Dark Horse |
| Exorcist | Earned | Badge: Exorcism (secret) |
| Bad Influence | Earned | Badge: Bad Influence |
| Shit-Stirrer / The Stirrer | Earned | Badge: Trash Talker |
| Touch Grass | Earned | Badge: Touch Grass (100 games) |
| The Closer | Held | Highest knock success among your people (15+ knocks) |
| Knock Merchant | Held | Highest knock rate among your people (50+ rounds) |
| The Snake | Held | Most times beating someone else's knock |
| The Accountant | Held | Lowest average round score among your people (20+ games) |
| Red King Magnet | Held | Most red Kings in final hands this year |
| Top Dog | Held | #1 by rating among your people |
| The Bottler | Held | Most leads blown in the final round this year. Yes, people can choose to display it. |

Rules: held titles need minimum sample sizes so they can't be won in one lucky game; ties go to whoever got there first; nobody can be forced to display a title.

### 12.8 Hall of Shame

Pushed from the Board tab (under Records), and from a profile ("2 entries in the Hall of Shame").

- **Scope:** **Your people** (everyone you've played with; the default) and **Yours** (only your own entries). There is **no global Hall of Shame**: strangers don't get to laugh at you.
- **Categories** (moments only, never streaks or patterns; PRD §5.7):

| Category | The moment |
|---|---|
| Worst Hand | Highest single hand value |
| Worst Knock | Failed knock with the biggest gap between the knocker's hand and the lowest hand |
| Biggest Loss | Highest final score in a game |
| Bottle Job | Biggest lead blown (largest lead held at any point in a game that player didn't win) |
| Ate It | Most +10 penalties in one game |
| Deepest Hole | Furthest behind the leader at any point in a game |

- **Each entry:** the player's avatar and name, the numbers ("Knocked on 9 into a 1"), the table word and date, a roast (HS-xx), and **View the round**, which opens the read-only round from that game's history.
- Each category shows its **top 3**; the #1 holder gets a small cracked-K mark on the entry.
- **Inducted at game end:** when a game sets a new top-3 entry, the game-end summary shows a "Hall of Shame" highlight card for the whole table. No pushes. A quiet line in Since you last looked for people who weren't there.
- Learner games (a player's first 3) never produce entries for that player. Abandoned games never count. Blocked players are excluded from each other's view.

### 12.9 Kedro Wrapped

A once-a-year, story-style recap, released on **December 1** for the calendar year to date. It needs **10 or more finished games** in the year; under that, the slot on Play says "Play 10 games this year to get your Wrapped (6 of 10)".

**Delivery:** a Wrapped card on top of Play and one passive notification (N-09). It stays in You → Wrapped until next year's arrives; past years stay in an archive.

**The cards** (full-screen, tap or swipe to advance, `TabView` with `.page` style), each in the player's language level (WR-xx):

1. **Cover:** the full logo, "YOUR 2026 IN KEDRO", and the player's name and avatar.
2. **The volume:** games, rounds, hours at the table (from game start to finish), and the number of different people played with.
3. **The record:** wins, win rate, and finish distribution.
4. **The rating journey:** a line from January to now, start, peak and current rank.
5. **The knock:** knocks, success rate, favorite knock value, and the best and worst knock of the year.
6. **The nemesis and the victim:** who beat you most, and who you beat most.
7. **Card luck:** red Kings held, ghost hands, the biggest hand.
8. **The mouth:** taunts sent, your most-used taunt, and who you taunted most.
9. **Titles and badges** earned this year.
10. **Your Hall of Shame year:** your entries, roasted (skipped if there are none).
11. **Your Kedro persona:** one of 8 archetypes from your stats (*The Gambler*: high knock rate; *The Snake*: beats knocks; *The Accountant*: low and steady; *The Menace*: most taunts; *The Closer*: knock success; *The Comeback*: wins from behind; *The Regular*: volume; *The Wildcard*: none of the above). A big name, one roast line.
12. **Share card:** a single summary image (logo, persona, record, rating, nemesis), exported **Clean by default** like every outbound image.

Any card can be shared on its own. Everything comes from finished, non-abandoned games; other players appear only if you shared games with them, and blocked players never appear.

---

## 13. Rules, learning and system surfaces

### 13.1 Rules and learning

- **Learn Cambio in 2 minutes:** five cards (setup, card values, powers, sticking, knocking and the knock gamble), real card faces, ending in a knock-gamble quiz.
- **Score a Round** drill: the real Round sheet in practice mode (PRACTICE watermark, synthetic players, cards face up, nothing logged) covering landed, tied, failed and going out with all four cards (an inherent knock, which never takes the +10).
- **Rules reference:** a searchable `List`, available mid-game as a `.medium` sheet. Rule text is literal and identical in every level.
- **Knock Calculator:** opened from Rules or any **Why?**; prefilled from a round, editable without touching the game.
- **TipKit** tips in the first two games; Card mode on for the first 3 games.

### 13.2 Live Activity

| Presentation | Content |
|---|---|
| Lock Screen | Small mark + table word · "ROUND 6 OF 8 · NOAH DEALS" · up to 5 rows (avatar 20 pt, rank, name, score, last delta) · last-round fact line or the live knock line · **Record Round** / **Report Hand** (App Intents) |
| Truncation | In the top 5: ranks 1–5. Otherwise ranks 1–4, `···`, then your row with your true rank, highlighted. |
| Island compact | Leading: small mark + `R6/8`. Trailing: `1st · 26`. |
| Island minimal | Your rank. |
| Island expanded | Round, your score and delta, top 3 + you, last outcome, action button. |
| Live knock | The line becomes "Noah knocked · last turns" until the round is saved. |
| Self-report alert | `AlertConfiguration` only to phones that haven't reported (N-05). |
| Language | Follows the player's level (owner decision). ≤ 60 characters. |

Online updates go server → APNs **broadcast channel** per game; offline see §11.

### 13.3 Widgets

| Widget | Families | Content |
|---|---|---|
| Standing | small, `accessoryCircular`, `accessoryRectangular` | Rank, rating, weekly movement; the 10-step meter under 10 games |
| Rivalry | medium, `accessoryRectangular` | "You vs Ana · 5–12" plus the rivalry line (R-01) |
| Next Badge | small | Closest badge and its progress |

Widgets reload only when a game finishes (and on claims): frozen during live games.

### 13.4 Notifications (complete set; none time-sensitive; none to a phone seated at a live table)

| # | Notification | Copy | Level |
|---|---|---|---|
| 1 | A host saved you a seat | N-01 | Active |
| 2 | Your people started a table nearby (opt-in) | N-07 | Active |
| 3 | You made the leaderboard | N-02 | Passive |
| 4 | Badge earned while away from game end | N-03 | Passive |
| 5 | Your guest claimed their history | N-04 | Passive |
| 6 | Receipt received (mutable per person) | N-08 | Passive |
| 7 | Your Kedro Wrapped is ready (once a year, December 1) | N-09 | Passive |

Not notified: rounds recorded, edits, taunts (they're in-game only), "you were passed", streaks at risk, "we miss you", game ended.

---

## 14. Accessibility

- **Dynamic Type through AX5:** standings stack (name on line 1, score and delta on line 2); compact rows scroll from AX2 with your row pinned; the pad keys grow to 72 pt height and the player rows collapse to a single-player header with ‹ › ; History becomes a per-round list.
- **VoiceOver:** standings rows are one element ("Ana, second place, 29 points, last round plus 9"). The last-round card reads the fact and verdict, then the voice line **as a separate, skippable element in the user's chosen level**. Taunts are announced once ("Ana to Noah: …") and are skippable; announcements only post when VoiceOver is running. Pad keys read "minus", "1". Custom rotors in History (Rounds, Edited, Knocks).
- **Reduce Motion:** crossfades only; the game-end logo appears without scale. **Reduce Transparency:** glass becomes `surfaceRaised`; suit watermarks hidden.
- **Contrast:** all text ≥ 4.5:1; gold is never small text on light; nothing is conveyed by color alone (outcomes have words and glyphs, guests have a dashed ring and "guest", the leader has LEADING and the K badge).
- **Motor:** targets ≥ 44 pt; pad keys ≥ 56 pt tall; no long-press-only actions (display mode's unlock also has a menu path); every swipe action is also in a context menu.

---

## 15. SwiftUI implementation map

| Feature | Components and APIs | UIKit? |
|---|---|---|
| App structure | `TabView` with `Tab` (Play, Leaderboard, You, Search with `.search` role); `NavigationStack` with value routes | No |
| Live game | `fullScreenCover`, minimizing into `tabViewBottomAccessory` | No |
| Round sheet and pad | `.sheet` with detents; `Grid` of `Button`s for the pad; `@FocusState`-style selected-row binding; `.sensoryFeedback` | No |
| Discovery and sync | Network framework (`NetworkListener`, `NetworkBrowser`, `NetworkConnection`, TLS-PSK) in an `@Observable` `TableLink`; MultipeerConnectivity fallback behind a flag; NearbyInteraction; `NWPathMonitor` | No |
| Nearby alert | CoreBluetooth (peripheral advertising in foreground, central background scanning with service UUID) | No |
| Local data | SwiftData operation log; `@Observable` game model folded from it | No |
| Voice | String Catalogs (Clean, Spicy, Unhinged tables with identical keys); `Voice` resolver; FNV-1a variant hash; DeclaredAgeRange | No |
| Avatars | `PhotosPicker`; emoji text field with `.keyboardType` emoji hint; curated avatars as asset-catalog images | No |
| Taunts and toasts | `.safeAreaInset(edge: .top)` toast queue; `TimelineView` for timeouts; sheet with `Picker` tabs | No |
| Custom taunt filter | On-device word list + server check (`apps/api`), report/block endpoints | No |
| Display mode | `@Environment(\.verticalSizeClass)` and orientation-driven layout; forced dark with `.preferredColorScheme(.dark)` | No |
| Badges | `Circle` + rim `Shape`s with metal `LinearGradient`s; small mark as a template image | No |
| Game end | `KeyframeAnimator` for the logo landing; `ScrollView` summary | No |
| Receipts and share images | `ImageRenderer` → `ShareLink` | No |
| App Clip | App Clip target, `NSUserActivity` invocation, `.appStoreOverlay`, app-group claim token | No |
| Live Activity | ActivityKit with broadcast push channels, `staleDate`, `AlertConfiguration` | No |
| Widgets | WidgetKit, `Gauge` for the 10-step meter | No |
| Rules tips | TipKit | No |
| Sound pack | `AVAudioPlayer` with the `.ambient` `AVAudioSession` category (respects the Silent switch); bundled `.caf` files; Table speaker election as a peer operation | No |
| Kedro Wrapped | `TabView` with `.tabViewStyle(.page)`, Swift Charts for the rating line, `ImageRenderer` → `ShareLink` per card | No |
| Dealer | Derived from the operation log (seat order + first dealer + rounds saved); `DealerChanged` operation for corrections | No |
| Keep screen awake | `UIApplication.shared.isIdleTimerDisabled` in a tiny `IdleTimer` helper (SwiftUI has no equivalent) | **Yes, one property** |

---

## 16. Tap and time estimates

| Task | Taps |
|---|---|
| Record a 5-player round (scorekeeper; hands 2, 9, 6, 11, 4) | Record (1) + knocker (1) + 7 digits + 4 Next + Save (1) = **14 taps, ~12–15 s**. With a live knock already marked: 13. |
| Same round in Card mode | ~2.5 taps per player + Next: ~20 taps |
| Self-report | 3–5 taps per player, in parallel |
| 5 returning players join | Host: New Table → Deal (2). Others: Sit Down on the Table card (1 each). **6 taps total, ~10 s.** |
| Returning guest, no phone | 2 (Add → reuse suggestion) |
| Guest with iPhone, no app (App Clip) | 3 on the guest's phone (scan → Open → That's me) |
| Fix one value | 4 (History → cell → value → Save Change) |
| Undo the round just saved | 1 (within 5 s) |
| Live knock (yourself) | 2 (Knock → you) |
| Canned taunt | 3 (Talk → taunt → Send; target pre-selected) |

The number pad costs ~6 more taps per round than the tournament's Tally board, in exchange for no upper limit and zero learning. **Validate at 3 real tables** (time per round, error rate) before building; if it's slow, the first fix is an optional **auto-advance after two digits** (three-digit hands are practically impossible; a value of 100+ would be typed with Next held back by a long-press on the last digit, with a menu alternative).

---

## 17. Sample game (used in every mockup)

**Noah's table (COLD DECK), 5 players, scorekeeper Noah, 6 rounds extended to 8. Sam is a guest on their 3rd game.** Seats clockwise: Noah, Ana, Ben, Cleo, Sam. First deal: Noah, so the dealers for R1–R8 are Noah, Ana, Ben, Cleo, Sam, Noah, Ana, Ben.

| Round | Knocker | Hands (Noah, Ana, Ben, Cleo, Sam) | Outcome | Round scores |
|---|---|---|---|---|
| R1 | Ana | 9, 3, 12, 7, 15 | landed | 9, **−10**, 12, 7, 15 |
| R2 | Ben | 6, 11, 5, 5, 20 | tied with Cleo | 6, 11, **5**, 5, 20 |
| R3 | Noah | 8, 3, 14, 10, 9 | failed (Ana 3) | **18**, 3, 14, 10, 9 |
| R4 | Cleo | 3, 16, 7, 2, −1 | failed (Sam −1) | 3, 16, 7, **12**, −1 |
| *after R4* | | | | 36, 20, 38, 34, 43 |
| R5 | Noah | 2, 9, 6, 11, 4 | landed | **−10**, 9, 6, 11, 4 |
| *after R5* | | | | **Noah 26, Ana 29, Ben 44, Cleo 45, Sam 47** |
| R6 | Sam | 7, 2, 9, 8, 1 | landed | 7, 2, 9, 8, **−10** |
| R7 | Ana | 5, 2, 2, 6, 12 | tied with Ben | 5, **2**, 2, 6, 12 |
| R8 | Noah | 0, 1, 12, 6, 21 | landed | **−10**, 1, 12, 6, 21 |
| **Final** | | | 4 landed · 2 tied · 2 failed | **Noah 28, Ana 34, Cleo 65, Ben 67, Sam 70** |

After R3, Noah was 4th (33), so Noah wins from behind: **Comeback Kid**. Noah's R8 hand of 0 earns **Ghost Hand**; finishing ahead of Ana (Noah's nemesis) earns **Nemesis Tamed**. Sam's R4 hand of −1 earns **Below Zero**. Ratings: Noah 1,068 → **1,086 (+18)**, now #13 Global; Ana 1,138 → 1,142; Ben's **debut at game 10: 986**. Head-to-head: Ana leads **12–5**. Sam: 3 games, "Seven more games and you're ranked."

---

## 18. Open items

1. **Small mark:** pick A, B or C (§3.2), then commission the vector and the app icon.
2. **Curated avatars:** commission the 24 illustrations in the logo's style.
3. **Bebas Neue licensing:** it's under the SIL Open Font License, so bundling is fine; confirm the exact weight files.
4. **Nearby alert (background Bluetooth):** App Review risk. Ship behind a remote flag.
5. **Custom taunts:** the filter word list and the report-review process need an owner before launch.
6. **Age rating:** expected 16+ (frequent profanity, mild alcohol references, user-generated content). Confirm in App Store Connect.
7. **Number pad speed:** validate at real tables (§16).
8. **Backend:** the operation log, rating replay, taunts, reports, receipts and broadcast pushes all need the redesigned schema (PRD §6.4).
