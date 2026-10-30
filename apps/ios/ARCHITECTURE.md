# Kedro iOS: Architecture

The map every agent works from. Read this with `apps/ios/AGENTS.md` (SwiftUI and concurrency rules),
`docs/kedro-ios-design.md` (what to build), `docs/kedro-ios-copy.md` (every string) and
`docs/design/mockups.html` (how it looks).

If you need a change in a folder you don't own, **don't make it**: report it as a shared need and code
against the existing contract (or a local adapter in your own folder).

---

## 1. Module map

```
apps/ios/Kedro/
  App/                      App shell (foundation)
    KedroApp.swift            @main; AppModel.live() + AuthStore + NetworkServices, push delegate, root hosts
    AppServices.swift         .appServices(): stats follow, blocked people → stats, widget snapshots, sound previews
    AppModel.swift            Services, identity, live game, navigation paths
    RootView.swift            Splash → OnboardingFlow (gate) → MainTabView; root toast host
    MainTabView.swift         Tab API: Play, Board, You, Search(.search); live game cover + mini bar
    LiveGameMiniBar.swift     tabViewBottomAccessory: "COLD DECK · R6/8 · You 1st · 26"
    PreviewEnvironment.swift  .previewEnvironment() / .appEnvironment(_:auth:)
    Navigation/AppRoute.swift AppTab, AppRoute, .appRouteDestinations()
    Navigation/GameRecordView.swift  AppRoute.gameHistory → read-only HistorySheet
  Core/
    Auth/                   AuthStore (Supabase, Sign in with Apple, DEBUG test user) (foundation)
    Config/                 AppConfig (Info.plist keys) (foundation)
    Networking/             APIClient (networking)
    Design/                 Tokens, type, components, toasts (foundation)
    Domain/                 IDs, people, seats, rounds, operations, HLC (foundation)
    Scoring/                The PRD §2.6 rules (foundation)
    Game/                   GameState fold, GameSession (foundation)
    Persistence/            SwiftData, GameStore, transport/directory/discovery protocols (foundation)
    Voice/                  LanguageLevel, CopyDeck, Voice, Literal, age gate (foundation)
    Sample/                 PreviewData, sample history, DEBUG seeder (foundation)
    Settings/               AppPreferences, SoundSettings (foundation)
    Stats/                  Derived stats, ratings, badges, titles, shame (stats)
    Moderation/             Taunt filter, report/block (talk)
    Sound/                  Sound pack player (talk)
    TableLink/ Nearby/ Sync/ Directory/ Push/   Real transports and services (networking)
    LiveActivity/           ActivityKit (platform)
  Features/                 One folder per feature (see ownership)
  Resources/Fonts/          BebasNeue-Regular.ttf (registered in Config/Info.plist UIAppFonts)
  Resources/Sounds/         Sound pack (talk)
  Assets.xcassets/          Logo, KMark, AppIcon, Colors/* (foundation; platform owns AppIcon)
apps/ios/KedroTests/        Swift Testing. Support/TestGame.swift builds operation logs.
```

The Xcode project uses folder-synchronized groups: new files under `Kedro/` or `KedroTests/` are
picked up automatically. Only the platform agent edits `project.pbxproj`.

---

## 2. Ownership

| Agent | Owns (everyone else: read-only) |
|---|---|
| **foundation** | `Core/Design`, `Core/Domain`, `Core/Scoring`, `Core/Game`, `Core/Persistence`, `Core/Voice`, `Core/Sample`, `Core/Settings`, `Core/Auth`, `Core/Config`, `App/`, `Features/Splash`, `Assets.xcassets` (except AppIcon), `ARCHITECTURE.md` |
| **table** | `Features/Table`, `Features/Round`, `Features/History`, `Features/GameEnd`, `Features/Display` |
| **lobby** | `Features/Onboarding`, `Features/Play`, `Features/Lobby`, `Features/Search`, `Features/Settings`, `Features/Learn`, `Features/SignIn` |
| **stats** | `Core/Stats`, `Features/Leaderboard`, `Features/Profile`, `Features/HeadToHead`, `Features/Badges`, `Features/HallOfShame`, `Features/Wrapped` |
| **talk** | `Features/Talk`, `Features/Feed`, `Features/Receipts`, `Core/Moderation`, `Core/Sound`, `Resources/Sounds` |
| **networking** | `Core/Networking`, `Core/TableLink`, `Core/Nearby`, `Core/Sync`, `Core/Directory`, `Core/Push` |
| **backend** | `supabase/`, `apps/api/`, `packages/shared/` |
| **platform** | `apps/ios/Kedro.xcodeproj`, `apps/ios/Config/`, `apps/ios/KedroWidgets/`, `apps/ios/KedroClip/`, `apps/ios/Shared/`, `Core/LiveActivity`, `Assets.xcassets/AppIcon.appiconset` |

Tests: put yours in `KedroTests/<YourArea>/` (e.g. `KedroTests/Stats/`). Shared helpers in
`KedroTests/Support/` are foundation's; copy what you need rather than editing them.

### Entry views

Every entry view below is implemented (none are stubs any more). Keep the type name and
initializer exactly; the shell and other features call them.

| Owner | Type | File |
|---|---|---|
| table | `TableView(session: GameSession)` | Features/Table/TableView.swift |
| table | `RoundSheet(session: GameSession)` | Features/Round/RoundSheet.swift |
| table | `HistorySheet(session: GameSession)` | Features/History/HistorySheet.swift |
| table | `GameEndView(session: GameSession)` | Features/GameEnd/GameEndView.swift |
| table | `DisplayModeView(session: GameSession)` | Features/Display/DisplayModeView.swift |
| lobby | `OnboardingFlow()` | Features/Onboarding/OnboardingFlow.swift |
| lobby | `PlayView()` | Features/Play/PlayView.swift |
| lobby | `NewTableView()` | Features/Lobby/NewTableView.swift |
| lobby | `SearchView()` | Features/Search/SearchView.swift |
| lobby | `SettingsView()` | Features/Settings/SettingsView.swift |
| lobby | `LearnView()` | Features/Learn/LearnView.swift |
| lobby | `RulesSheet()` | Features/Learn/RulesSheet.swift |
| lobby | `KnockCalculatorView(prefill: Round?)` | Features/Learn/KnockCalculatorView.swift |
| stats | `LeaderboardView()` | Features/Leaderboard/LeaderboardView.swift |
| stats | `ProfileView(player: PlayerRef)` | Features/Profile/ProfileView.swift |
| stats | `HeadToHeadView(a: PlayerRef, b: PlayerRef)` | Features/HeadToHead/HeadToHeadView.swift |
| stats | `BadgesView(player: PlayerRef)` | Features/Badges/BadgesView.swift |
| stats | `HallOfShameView()` | Features/HallOfShame/HallOfShameView.swift |
| stats | `WrappedView(year: Int)` | Features/Wrapped/WrappedView.swift |
| talk | `TalkSheet(session: GameSession, target: TauntTarget)` | Features/Talk/TalkSheet.swift |
| talk | `FeedView(session: GameSession)` | Features/Feed/FeedView.swift |
| talk | `ReceiptComposer(gameID: GameID)` | Features/Receipts/ReceiptComposer.swift |


---

## 3. How features reach services

Everything comes from the environment, injected once by `KedroApp` (`.appEnvironment`) and by
`.previewEnvironment()` in previews:

```swift
@Environment(AppModel.self) private var app        // services, identity, live game, navigation
@Environment(AppPreferences.self) private var prefs // level, taunts, sounds, learner hints
@Environment(ToastCenter.self) private var toasts   // same instance as app.toasts
@Environment(AuthStore.self) private var auth       // sign in/out (lobby, settings)
```

| Need | Use |
|---|---|
| Stored games, ops, finished games (stats input) | `app.store` (`GameStore`) |
| A session for a stored game | `try await app.makeSession(for: gameID)` then `await session.run()` in `.task` |
| Start a new table (lobby) | `try await app.createGame(config:others:)` → session in lobby; `session.start()` on Deal |
| The live game | `app.liveGame`, `app.presentTable()`, `app.minimizeTable()`, `app.closeLiveGame()` |
| Who am I | `app.profile` (`LocalProfile`), `app.identity` (`LocalIdentity`), `session.mySeat` |
| Player search / played-with / guest suggestions | `app.directory` (`PlayerDirectory`) |
| Nearby tables, advertising | `app.discovery` (`TableDiscovery`) |
| Sending ops off the phone | handled by `GameSession` via `app.transport`; read `app.transport.syncState` for the pill |
| Voice lines | personal surfaces `app.voice`; shared table surfaces `app.houseVoice(for: session.state)` |
| Literal strings | `Literal.recordRound(6)`, `Literal.verdict(...)`, `Literal.text("button.deal")` |
| Toasts | `app.toasts.show(Toast(...))`; set `app.toasts.isDeferring = true` while a Round sheet is open |
| Navigation | `NavigationLink(value: AppRoute.profile(ref))` or `app.navigate(to:in:)` |
| HTTP API | `app.api` (`APIClient`, networking owns it) |
| Under-18 | `prefs.isUnder18`, `prefs.effectiveLanguageLevel`, `prefs.effectiveCustomTaunts` |

Installing real implementations: `AppModel.live()` builds the store and local services, and
`KedroApp` installs the real `transport`, `directory`, `discovery` and `account` right after with
`NetworkServices.install(in:auth:)` (it needs the `AuthStore`). See §5 for every cross-feature seam.

---

## 4. Contracts

### 4.1 Domain (`Core/Domain`)

| Type | File | Notes |
|---|---|---|
| `PlayerID`, `GuestID`, `GameID`, `DeviceID` | Identifiers.swift | `Identifier<Tag>` over UUID; JSON lowercase UUID string |
| `PlayerRef` | Identifiers.swift | `.player(PlayerID)` / `.guest(GuestID)`; JSON `{"kind":"player","id":…}`; the identity used by stats and profiles |
| `SeatID` | Identifiers.swift | **Derived** from `PlayerRef`: `"p:<uuid>"` / `"g:<uuid>"`. Same person ⇒ same SeatID in every game. JSON string; dictionary keys encode as object keys |
| `Handle` | Handle.swift | lowercase, 3–20 `[a-z0-9._]`; `Handle(_:)` validates, `.suggestions(firstName:)` |
| `Avatar` | Avatar.swift | `.photo(URL)` (a reference, never bytes) / `.emoji(String, colorIndex:)` (0–11, `AvatarPalette`) / `.curated(CuratedAvatarID)` |
| `CuratedAvatarID` | Avatar.swift | 24 IDs; `.ghost` and `.hustler` are secret (`unlockingBadge`) |
| `Player`, `PlayerSummary` | Player.swift | API shapes; `titleID` is a `TI-xx` copy ID |
| `Seat` | Seat.swift | person, name, `order` (clockwise = dealing order), reporter, linked `deviceID`, `languageLevel`, `titleID`, `gamesPlayed` snapshot; `isLearner` |
| `GameConfig`, `ScoringMode`, `TableWord` | GameConfig.swift | planned rounds, mode, table word, first dealer, house voice cap, scorekeeper |
| `Round`, `KnockOutcome` | Round.swift | `number`, `hands: [SeatID: Int]`, `knocker`; scores derived; hand range −2…999 |
| `TauntTarget`, `TauntContent`, `Reaction` | TrashTalk.swift | |
| `HLC`, `HybridLogicalClock` | HLC.swift | `(wallMs, counter, node)`; `stringValue` = `"%015d-%05d-<node>"` (lexicographic = HLC order) |
| `GameOperation`, `OperationType`, `OperationPayload`, `Op.*` | GameOperation.swift | The op log. Swift name is `GameOperation` (avoids `Foundation.Operation`); the wire object is the contract's `Operation` |
| `KedroJSON` | GameOperation.swift | The only JSON coders to use (ISO 8601 dates, sorted keys) |
| `ScoreFormat` | ScoreFormat.swift | True minus (U+2212): `string`, `signed`, `spoken` |

### 4.2 Operations (wire contract, shared with `apps/api`)

```json
{"opId":"<uuid>","gameId":"<uuid>","deviceId":"<uuid>",
 "hlc":{"wallMs":1761700000000,"counter":0,"node":"<deviceId>"},
 "actorPlayerId":"<uuid>|null","type":"RoundRecorded","payload":{…}}
```

| type | payload | rule in the fold |
|---|---|---|
| `GameCreated` | `{config, host}` | first one wins |
| `GameStarted` | `{seatOrder:[SeatID], firstDealer}` | lobby → active; fixes order and first dealer |
| `GameConfigured` | `{tableWord, scoringMode, houseVoiceCap?}` | lobby only: replaces all three (no cap clears it); after Deal → late (`afterDeal`) |
| `PlayerSeated` | `{seat}` | upsert by seat; new seats refused after Round 1 or past 8; a new `deviceId` after start is logged |
| `SeatRemoved` | `{seatId}` | before Round 1 only; logged |
| `ScorekeeperChanged` | `{seatId}` | logged |
| `RoundRecorded` | `{round}` | must be the next number; a second different record for an existing number → `conflicts` (earlier kept) |
| `RoundEdited` | `{round}` (full new hands + knocker) | re-scores; logged with hand/knocker/outcome before → after and total effects |
| `RoundUndone` | `{roundNumber}` | latest round only; the deal moves back |
| `KnockMarked` | `{roundNumber, knocker\|null}` | live knock for the next round; null clears; a different knocker at save is logged |
| `KnockerProposed` / `KnockerResolved` | `{roundNumber, knocker}` | self-report knocker decision |
| `HandReported` | `{roundNumber, seatId, hand, knocked}` | self-report; the round auto-completes when all seats reported and the knocker is settled |
| `RoundsChanged` | `{plannedRounds}` | never below rounds played; logged |
| `DealerChanged` | `{roundNumber, dealer}` | re-anchors the rotation; logged |
| `TauntSent` | `{tauntId, roundNumber, from\|null, fromName, target, content}` | dedupe by tauntId |
| `TauntRetracted` | `{tauntId, reason?}` | hides it everywhere (server filter) |
| `ReactionAdded` | `{roundNumber, seatId, reaction}` | one per seat per round (last wins); allowed after finish |
| `ReceiptSent` | `{fromSeat, toSeat, receiptKey}` | one per pair per game; allowed after finish |
| `TableSpeakerClaimed` | `{deviceId}` | |
| `GameFinished` | `{reason: completed\|endedEarly\|autoFinished, finalRounds:[Round]}` | locks the game; `finalRounds` is authoritative |
| `GameAbandoned` | `{}` | beats everything (incl. a finish within 15 min) |
| `GameRestored` | `{}` | within 15 min of the abandon |

JSON keys are camelCase with `Id` (`opId`, `seatId`, `deviceId`, `titleId`); Swift properties use
`ID` and map via `CodingKeys`. Optional keys are omitted when nil, except `actorPlayerId`, which is
always present (`null` when absent). `Seat`, `GameConfig` and `Round` JSON are documented on the types.

`GameStarted`, `GameConfigured`, `ScorekeeperChanged` and `TauntRetracted` are additions to design
§11's list; the backend must accept all 23 types (`OperationType.allCases`).

**Fold order**: de-dupe by `opId`, sort by `(hlc, deviceId, opId)`, apply. Conflicts: later HLC wins
for concurrent edits; duplicate rounds keep the earlier; after `GameFinished` (or while abandoned)
state-changing ops are refused into `lateOperations` and logged (H-05). Reactions, receipts, speaker
claims and retractions are still accepted after finish.

### 4.3 Scoring (`Core/Scoring/Scoring.swift`)

`Scoring.roundScores(hands:knocker:)` (PRD §2.6 exactly), `knockOutcome`, `knockerScore`, `totals`,
`ranks` (competition ranking, `Rank.isShared` → "2="), `winners` (ties share), `ordered`. Generic over
the key, so stats can score by `SeatID` or `PlayerRef`. Server mirrors it in `packages/shared`.

### 4.4 Game (`Core/Game`)

- `GameState.fold(_:gameID:)` → `GameState`: `config`, `status` (`lobby|active|finished|abandoned`),
  `seats` (clockwise), `rounds: [RoundRecord]` (scores, outcome, `editedSeats`), `standings: [Standing]`
  (total, rank, leader, dealer, `lastRound: SeatRoundResult`), `currentDealer`, `dealer(forRound:)`,
  `progress` ("ROUND n OF m"), `liveKnock`, `selfReport`, `reactions`, `taunts`, `receipts`, `audit:
  [AuditEntry]` (who/when/before→after/effects/literal `summary`), `feed: [FeedEntry]`, `conflicts`,
  `lateOperations`, `houseLevel`, `isAwaitingFinish`.
- **Dealer**: anchored at Round 1's first dealer; passes one seat (next in `seats`) per saved round;
  undo moves it back; `DealerChanged` re-anchors; editing old rounds never moves it.
- `GameSession` (`@Observable`): `state`, `operations`, `mySeat`, `canEdit`, `isScorekeeper`;
  `run()` (load + follow store and transport until cancelled); `send(_:)`; helpers `recordRound`,
  `editRound`, `undoLastRound`, `canUndo(_:)`/`undo(_:)` (author's own edits), `useConflictVersion`,
  `markKnock`, `reportHand`, `proposeKnocker`, `resolveKnocker`, `changeDealer`, `extendRounds`,
  `handOffScorekeeping`, `finish(reason:)`, `finishIfIdle(now:)`, `abandon`, `canRestore`, `restore`,
  `sendTaunt`, `react`, `claimTableSpeaker`, `sendReceipt`; `preview(_:)` for "What changes";
  `GameSession.create(...)` and `start(firstDealer:)` for the lobby.

### 4.5 Persistence (`Core/Persistence`)

| Protocol | Default implementation | Real implementation |
|---|---|---|
| `GameStore`: `append` (idempotent), `operations(for:)`, `updates(for:)`, `gameUpdates()`, `games()`, `gameState(_:)`, `finishedGames()` | `SwiftDataGameStore` (app), `InMemoryGameStore` (previews/tests) | foundation |
| `OperationTransport`: `syncState`, `connect`, `disconnect`, `send`, `incoming(for:)` | `LocalOnlyTransport` | networking (`Core/TableLink`, `Core/Sync`) |
| `PlayerDirectory`: `search`, `playedWith`, `guestSuggestions`, `player` | `LocalPlayerDirectory` (from stored games) | networking (`Core/Directory`) |
| `TableDiscovery`: `nearbyTables()`, `advertise`, `stopAdvertising` | `NoNearbyTables` | networking (`Core/Nearby`) |

SwiftData models (`PersistentModels.swift`): `StoredOperation` (contract JSON + index columns),
`StoredPlayer`, `StoredGuest` (claim token), `StoredProfile`. `ProfileStore` (`@Observable`) holds
the `LocalProfile`. `DeviceIdentity.current()` is this install's `DeviceID`.

Anything that receives operations (peer link, backend sync) writes them with `store.append`;
`GameSession` observes the store, so it never matters where an op came from.

### 4.6 Voice (`Core/Voice`)

- `LanguageLevel` (`clean < spicy < unhinged`), `LanguageLevel.house(seated:cap:)`.
- `CopyDeck.standard`: every string in `docs/kedro-ios-copy.md`, keyed by ID (`K-06`, `TI-01`,
  `TI-01.tagline`, `BG-01…BG-34` = badge lines in design §12.6 order). Literal keys
  (`button.*`, `fact.*`, `verdict.*`, `delta.*`, `label.*`, `audit.*`) are identical in all levels.
  Need strings that aren't in the deck (e.g. the full taunt library)? Keep `[CopyEntry]` in your own
  folder and render with `voice.line(entry, args)`; report additions to foundation.
- `Voice(level:)`: `line(id, args)`, `line(oneOf:args:seed:)`, `line(moment, args, gameID:round:)`.
  Variants are picked by `VoiceSeed` = FNV-1a 64 of `"<gameID>|<round>|<key>"` (never `Hasher`), so
  every phone shows the same joke. `Int` args render with a true minus.
- `Literal`: typed helpers for literal strings (`recordRound`, `fact`, `verdict`, `delta`, `roundOf`,
  `deals`, `miniBar`).
- `TauntGroup`: the canned taunt groups → `TT-xx` IDs.
- `AgeRangeProviding`: the under-18 hook (lobby implements Declared Age Range; `AppModel.ageRange`).

### 4.7 Design (`Core/Design`)

- Colors: asset colorsets (`Assets.xcassets/Colors`) with generated symbols: `.night`, `.surface`,
  `.surfaceRaised`, `.rule`, `.cream`, `.silver`, `.silverDim`, `.kedroRed`, `.kedroRedDeep`, `.gold`,
  `.nightGradientTop/Bottom`; `ShapeStyle.nightGradient`; `AvatarPalette` (12 emoji colors).
  Rules: red never means bad, no green, numbers on solid surfaces, glass only for controls.
- Type: `.kedroFont(.score | .scoreCompact | .scoreLarge | .display | .headline | .label | .roast | .pad)`
  (Dynamic Type, tracking, tabular digits, Bebas uppercased for display only) or `Font.kedro(_:)`.
- Components: `LogoView(width:)`, `KMark(height:style:)`, `AvatarView` (sizes 20/32/44/56/96, leader
  K badge, dealer D chip, focus/winner ring, guest dashed ring), `CuratedAvatarArt`, `OutcomeBadge`,
  `HatchPattern`, `ProgressMeter`, `ScoreText`, `.buttonStyle(.kedroPrimary | .kedroGlass | .kedroGlassWide)`,
  `.kedroGlassBackground(in:)`, `SuitWatermark`, `.keepsScreenAwake(_:)`, `SVGPath`.
- Toasts: `ToastCenter` (max 3, overflow "+n more in the feed", `isDeferring` while the Round sheet is
  open, auto-dismiss, VoiceOver announcement) and `.toastHost(center)`. **Every `fullScreenCover` root
  must apply `.toastHost(app.toasts)`** (a cover hides the root's host).

### 4.8 Settings (`Core/Settings`)

`AppPreferences` (`@Observable`, `UserDefaults` keys in `AppPreferences.Key`, usable with
`@AppStorage`): `languageLevel`, `isUnder18`, `effectiveLanguageLevel`, `customTauntsEnabled`,
`effectiveCustomTaunts`, `learnerHints` + `showsLearnerHints(gamesPlayed:)`, `prefersCardMode`,
`lastPlannedRounds`, `lastScoringMode`, `hasCompletedOnboarding`, `nearbyAlertsEnabled`,
`lastLookedAt`, `sounds`. `SoundSettings`: `isEnabled` (off by default), per-`SoundMoment` toggles,
`tableSpeaker: TableSpeakerPreference`, `plays(_:)`.

### 4.9 Sample data (`Core/Sample`)

- `PreviewData`: the §17 game (`sampleOperations(throughRound:finished:liveKnock:)`, `sampleState`,
  `sampleSession`), people (`noah`, `ana`, `ben`, `cleo`, `samID`, `priya`, `jo`, `max`, `maya`,
  `theo`, `leo`), seats (`noahSeat`…), `noahIdentity`, `noahProfile`.
- `PreviewData.history`: 40 finished + 1 abandoned generated games (seeded, deterministic; Ben 4 games,
  Sam 2). `historyOperations` flattens them.
- `DemoDataSeeder.seed(into:)` (DEBUG): history + the finished sample game. The DEBUG test user
  signs in **as Noah**, so the demo's "You" is Noah.
- `AppModel.preview(liveGame:seeded:)` and `.previewEnvironment()` for `#Preview`s.

### 4.10 App shell

- Gate: `RootView` shows `OnboardingFlow` while `app.needsOnboarding(isSignedIn:)`; onboarding ends by
  setting `prefs.hasCompletedOnboarding = true` once the phone has a profile (signed in → `didSignIn`
  creates it; guest → `app.playAsGuest(name:)`).
- Tabs: `AppTab.play | .board | .you | .search`. Each tab's `NavigationStack(path:)` lives in
  `MainTabView` and resolves `AppRoute` with `.appRouteDestinations()`. **Tab root views must not
  create their own `NavigationStack`.** Sheets and covers that need navigation create their own.
- `AppRoute`: `.profile(PlayerRef)`, `.headToHead(PlayerRef, PlayerRef)`, `.badges(PlayerRef)`,
  `.hallOfShame`, `.wrapped(year:)`, `.gameHistory(GameID)`, `.settings`, `.learn`, `.rules`,
  `.knockCalculator(Round?)`.
- Live game: `app.startLiveGame(session, present:)` keeps `session.run()` going; the Table is a
  `fullScreenCover` while `app.isTablePresented`; minimized it becomes the mini bar
  (`tabViewBottomAccessory`). `app.resumeLiveGame()` reopens an unfinished game at launch.

---

## 5. Integration (how the features are wired together)

| Seam | Where | How |
|---|---|---|
| Real services | `KedroApp.init` | `NetworkServices.install(in: appModel, auth:)` sets `app.transport` (`NetworkedTransport`), `app.directory` (`RemotePlayerDirectory`), `app.discovery` (`NearbyTableDiscovery`) and `app.account` (`AccountSync`) before `AppModel.start()`. `AppModel.live()`, previews and tests keep the local ones. |
| Network services in views | environment | `@Environment(NetworkServices.self) var network: NetworkServices?` (nil in previews): `network.push.pendingInvite` / `consumeInvite()` (Play's Table card), `network.push.requestAuthorization()` (in context, after a primer), `network.link` (J-02 `seatRequests` / `answer(_:admit:)`, `inviteLink()` for the QR code), `network.alerts`. |
| Joining | `Core/Nearby/NearbyTableDiscovery+Joining.swift` | The discovery adopts the lobby's `SeatRequesting` (Ask to Sit: joining the link without proof is the request; seating the person admits their phone) and `TableInviting` (QR codes the link's admission accepts; joining with a scanned `k`). |
| Account | `AppModel.didSignIn`, onboarding, Settings → Profile | `app.syncProfile()` (PUT /v1/players/me with `titleId`; 409 → `.handleTaken`), then `account.claimGuestHistory(guestToken:)` (the guest profile's token, "Got a claim code?" codes, App Clip seats). Guest seats carry `claimTokenHash`. |
| Table ← Stats | `MainTabView` cover | `.environment(\.tableInsights, .stats(titles:isLoaded:store:viewer:options:))` (`Core/Stats/StatsTableInsights.swift`): titles under names, game-end ratings, badges, Hall of Shame. |
| Table ↔ Talk | `MainTabView`, `LiveTableView` | `.trashTalk(for: app.liveGame, presentsFeed: false)` on the tab view runs taunt toasts and sounds (minimized or not). A tapped toast sets `TalkServices.feedRequest`; the Table opens History → Feed. Display mode registers in `TalkServices.bannerGames` (banners instead of toasts) and claims the table speaker. `\.tauntRendering` defaults to Talk's renderer. |
| Play/Lobby ← Stats | `PlayModel`, `LobbyModel` | `StatsModel.shared(for:)` is the `StakesProvider` (stakes, Since you last looked, the Wrapped slot) once loaded; `app.gamesPlayed(by:)` snapshots `Seat.gamesPlayed`. Stats follow the store app-wide (`.appServices()`), excluding blocked people. |
| Run It Back | game end → Play | `app.rematchRequest = state`, the cover closes, Play opens `NewTableView(rematchOf:)` (the `Rematch` plan: same circle, rotated first deal, saved seats). |
| Live Activity | `.liveGameActivity()` at the root | Follows `app.liveGame`; `channelProvider` / `onPushToStartToken` come from `PushService`. Buttons land in `pendingAction`, which `LiveTableView` takes. Server broadcasts use the same `ContentState` JSON (`packages/shared/src/live.ts`); phones apply `resolved(for: mySeatID)`. |
| Widgets | `.appServices()` | Publishes `StatsSnapshot.widgetSnapshot(...)` whenever finished games change (held while a game is live). |
| Outbound images | `AppPreferences.outboundImagesClean` | Receipts, Share Results and Wrapped start from `prefs.outboundImageLevel`. |
| Table invites ↔ server | `BackendSync.tableInvite` (`NetworkServices`) | Invite codes are made with `TableKey.inviteKey` (an HMAC of the table secret). Phones register that key (`PUT /v1/games/:id/invite-key`) and send the current code with uploads (`invites`); the server needs it before seating a phone that seated itself and before starting an App Clip session. |
| Link identity | `LinkIdentityService` (`Core/TableLink/LinkIdentity.swift`) | Hubs admit by identity (seated, played with) only with a server-attested, device-signed hello (`LinkHello.identity`). The TXT record no longer carries the host's player ID. Blocked people are refused, and their seat requests declined. |
| Server stats | `ServerStats.shared` (`Core/Stats/ServerStats.swift`) | The Global board and other players' rating, global rank and lifetime numbers come from the server (`GET /v1/leaderboard`, `GET /v1/players/:id/profile`); local snapshots stand in offline. |
| Account history | `BackendSync.pullAccountHistory()` | `GET /v1/players/me/games` at launch, sign-in and after a claim: games played on other phones, claimed guest history and migrated web games come down. Claimed guest IDs land in `ClaimedGuests`, which `.appServices()` turns into `StatsOptions.aliases`. |
| Guest claim codes | `GuestClaimCodes` (`Core/Persistence`) | Guests added by name get a `claimTokenHash`; the code stays in this phone's Keychain and game end offers "Send {name} Their Claim Code". |
| Photos | `AccountSync` → `PUT /v1/players/me/photo` | Local `file://` photos are uploaded and swapped for their https URL (`AppModel.adoptUploadedPhoto`); `LocalProfile.shareableAvatar` never puts a local file in a seat. |

Networking note: the iOS 26 structured `TLS` builder has no pre-shared-key option, so the table
link hosts and connects with `NWListener`/`NWConnection` and `sec_protocol_options_add_pre_shared_key`,
and browses with the iOS 26 `NetworkBrowser`.

---

## 6. Conventions

- **SwiftUI only**, per `AGENTS.md`. The only UIKit is `IdleTimer` in `KeepAwake.swift`.
- **Isolation**: the app target is `MainActor` by default. Value types used across actors (domain,
  state, voice data) are declared `nonisolated struct/enum` and `Sendable`. Service protocols are
  `AnyObject, Sendable` and implemented by main-actor classes.
- **Naming**: views end in `View`/`Sheet`/`Flow`; `@Observable` models are nouns (`GameSession`,
  `ToastCenter`). Copy IDs are strings exactly as in the deck.
- **Strings**: never hard-code voice lines; use `Voice`/`Literal`. Buttons are literal verbs.
  No exclamation marks, no emoji in copy. Bebas text is real-cased in code and uppercased for display.
- **Numbers**: always `ScoreFormat`/`ScoreText` (true minus). Knocker deltas via `Literal.delta`.
- **Ops**: never mutate `GameState`; send an op through `GameSession`. Read derived values from the
  fold (e.g. dealer, standings) rather than recomputing.
- **Previews**: every view has a `#Preview` using `.previewEnvironment()` and `PreviewData`.
- **Tests**: Swift Testing (`@Test`, `#expect`, `#require`); in-memory stores; no network. Use
  `PreviewData` and `KedroTests/Support/TestGame` patterns. Run on your assigned simulator only.
- **No force unwraps** outside tests/previews (`Handle(constant:)` exists for known-valid literals).
- **Accessibility**: Dynamic Type through AX5, VoiceOver labels in real casing, 44 pt targets,
  nothing by color alone, Reduce Motion/Transparency respected (see design §14).
