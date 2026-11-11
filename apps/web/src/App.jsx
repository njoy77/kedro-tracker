import { useState, useEffect, useRef, useMemo, useCallback } from 'react';
import { LOGO_B64 } from './lib/logo';
import { HANDLE_PATTERN, LEADERBOARD_MINIMUMS, SEAT_LIMITS, knockOutcome, parseSeatId } from '@kedro/shared';
import { ApiError, allPlayers as fetchAllPlayers, api } from './lib/api';
import { devSignInAvailable, isSignedIn, onAuthChange, signInAsDevAccount, signInWithApple, signInWithGoogle, signOut, stashClaimFromURL, takePendingClaim } from './lib/auth';
import { GameLog, abandonGame as writeAbandon, createGame, editRound as writeRoundEdit, emojiOf, finishGame, recordRound, roundOf, setDealer, toWebGame } from './lib/table';

const FONTS = `@import url('https://fonts.googleapis.com/css2?family=Bebas+Neue&family=Barlow:wght@300;400;500;600;700&family=Barlow+Condensed:wght@400;600;700&display=swap');`;

const C = {
  bg: '#0a0a0e',
  bgGradFrom: '#15151c',
  bgGradTo: '#08080c',
  // Translucent glass surfaces — used by s.card() with backdrop-filter blur
  surface:  'rgba(22, 22, 30, 0.55)',
  surface2: 'rgba(28, 28, 38, 0.55)',
  surface3: 'rgba(35, 35, 45, 0.55)',
  // Solid surfaces for inputs and elements where blur hurts readability
  inputBg: '#13131a',
  ink: '#0c0c12',
  // Near-opaque panel for modals and bottom sheets — content behind should NOT show through
  panel: 'rgba(16, 16, 22, 0.96)',
  border:       'rgba(255, 255, 255, 0.06)',
  borderLight:  'rgba(255, 255, 255, 0.12)',
  red:      '#e63946',
  redHover: '#ff4d6d',
  redDeep:  '#b81d2a',
  redGlow:  'rgba(230, 57, 70, 0.35)',
  silver: '#c0c0c0', silverDim: '#888888',
  cream:     '#f5efe6',
  creamDim:  'rgba(245, 239, 230, 0.55)',
  creamFaint:'rgba(245, 239, 230, 0.28)',
  green: '#3dba6a', blue: '#4a9edd',
  gold:     '#f5c842',
  goldDeep: '#d4a829',
  white: '#ffffff',
};

// A player in the shape the screens use: `id` is the seat ID ("p:<uuid>" or "g:<uuid>"), `ref` the
// {kind, id} a seat needs.
function webPlayer(summary) {
  return { id: `p:${summary.id}`, ref: { kind: 'player', id: summary.id }, playerId: summary.id, username: summary.displayName, emoji: emojiOf(summary.avatar), handle: summary.handle, avatar: summary.avatar };
}

function webGuest(guestId, name) {
  return { id: `g:${guestId}`, ref: { kind: 'guest', id: guestId }, username: name, emoji: '👤', isGuest: true };
}

/** A handle suggestion from a name: lowercase letters, digits, dots and underscores, 3–20 long. */
function suggestedHandle(name) {
  const base = name.toLowerCase().normalize('NFKD').replace(/[^a-z0-9._]/g, '').slice(0, 20);
  return base.length >= 3 ? base : `${base}${'kedro'.slice(0, 3 - base.length)}`.slice(0, 20);
}

const EMOJIS = ['🐴','🏇','🦄','🐎','🎠','🏆','🌾','🍀','🔱','⚜️','🌿','🪄','🎯','🌙','⭐'];
const RANK_BADGES = ['🥇','🥈','🥉'];
const SUITS = ['♠','♥','♦','♣'];

// ─── Trash Talk ──────────────────────────────────────────────────────────────
const TRASH = {
  pick: (arr) => arr[Math.floor(Math.random() * arr.length)],
  loginGreet: (name) => TRASH.pick([
    `Well well well... ${name} crawled back.`,
    `Oh look who decided to show up. ${name}.`,
    `${name}! Back for another ass whooping?`,
    `The audacity of ${name} showing their face again.`,
    `${name} returns! Hope you brought your A-game.`,
    `${name}... didn't you get enough last time?`,
  ]),
  loginSub: () => TRASH.pick([
    `Let's see if you can back it up tonight.`,
    `Try not to embarrass yourself... again.`,
    `Ready to get your ass handed to you?`,
    `Your throne awaits. Just kidding, you never had one.`,
    `Everyone's been talking shit. Prove them wrong.`,
  ]),
  homeGreet: (name) => TRASH.pick([
    `What's good, ${name}?`,
    `${name}. The legend. Allegedly.`,
    `${name}'s in the building. Hide your points.`,
    `${name}. Still delusional about winning?`,
    `Ah, ${name}. Ready to donate some points?`,
  ]),
  winnerTaunt: (name) => TRASH.pick([
    `${name} absolutely wiped the floor with everyone.`,
    `Bow down. ${name} owns this table now.`,
    `${name} just made the rest of you look pathetic.`,
    `Everybody shut up — ${name} is the real deal.`,
    `${name} ate and left no crumbs. Disgusting.`,
    `${name} destroyed the competition. Not even close.`,
  ]),
  loserRoast: () => TRASH.pick([
    `Better luck next time... maybe.`,
    `That was genuinely embarrassing.`,
    `Someone call an ambulance for that score.`,
    `You played like absolute garbage. Respectfully.`,
    `Your cards were fine. You were the problem.`,
    `Last time you got your ass beat this bad was... actually, last game.`,
  ]),
  dealCards: () => TRASH.pick([
    `Let's settle this 🐴`,
    `Time to deal some pain 🐴`,
    `Shuffle up and shut up 🐴`,
    `Talk is cheap. Deal the cards 🐴`,
  ]),
  endGamePrompt: () => TRASH.pick([
    `End this massacre?`,
    `Put them out of their misery?`,
    `Time to crown someone (or embarrass everyone)?`,
    `Seen enough? Let's finish this.`,
  ]),
  noGames: () => TRASH.pick([
    `No games yet. Scared?`,
    `Empty history. What a coward.`,
    `Play a damn game already.`,
    `Nothing here. Go deal some cards, you bum.`,
  ]),
  historyWin: () => TRASH.pick([`Dominated`, `Crushed it`, `Wrecked 'em`, `Victory`]),
  historyLoss: () => TRASH.pick([`Got cooked`, `Embarrassing`, `Took an L`, `Oof`]),
  nemesisComment: (name) => TRASH.pick([
    `${name} owns your soul`,
    `${name} keeps making you look silly`,
    `${name} has your number... and your dignity`,
  ]),
  streakComment: (n) => n >= 5 ? `${n} in a row. You're disgusting.` : n >= 3 ? `${n} straight. Okay, relax.` : `${n}`,
  resumeGame: () => TRASH.pick([
    `Unfinished business`,
    `Get back in there`,
    `Don't run from it`,
  ]),
  newGameTaunt: () => TRASH.pick([
    `Pick your victims.`,
    `Choose who's catching this L.`,
    `Select the unfortunate souls.`,
  ]),
  roundSave: () => TRASH.pick([
    `Lock it in →`,
    `Save Round →`,
    `That's the damage →`,
  ]),
  abandonTaunt: () => TRASH.pick([
    `Quit like a coward (won't count)`,
    `Rage quit (doesn't count)`,
    `Run away (no stats recorded)`,
  ]),
};

const displayPlayer = (p) => p?.deleted ? { ...p, username: 'Deleted Player', emoji: '👻' } : p;

function playNeigh() {
  try {
    const audio = new Audio('/neigh.mp4');
    audio.play();
  } catch (e) {}
}

const GLASS_SHADOW = '0 10px 30px rgba(0,0,0,.45), 0 1px 0 rgba(255,255,255,.04) inset, 0 0 0 1px rgba(0,0,0,.4)';

const s = {
  btn: (variant = 'red', extra = {}) => ({
    padding: '12px 22px', borderRadius: 12, border: 'none', cursor: 'pointer',
    fontFamily: 'Barlow, sans-serif', fontSize: 13, fontWeight: 700,
    transition: 'all .2s cubic-bezier(.4,0,.2,1)', letterSpacing: '.08em', textTransform: 'uppercase',
    ...(variant === 'red' ? {
      background: `linear-gradient(180deg, ${C.red}, ${C.redDeep})`, color: C.white,
      boxShadow: `0 8px 24px ${C.redGlow}, 0 2px 0 rgba(0,0,0,.3) inset, 0 1px 0 rgba(255,255,255,.18) inset`,
    } : {}),
    ...(variant === 'outline' ? {
      background: C.surface, backdropFilter: 'blur(20px) saturate(140%)', WebkitBackdropFilter: 'blur(20px) saturate(140%)',
      color: C.cream, border: `1px solid ${C.border}`,
      boxShadow: GLASS_SHADOW,
    } : {}),
    ...(variant === 'ghost'   ? { background: 'transparent', color: C.creamDim, padding: '8px 14px' } : {}),
    ...(variant === 'danger'  ? { background: 'rgba(230,57,70,.15)', color: C.red, border: `1px solid rgba(230,57,70,.3)` } : {}),
    ...(variant === 'gold'    ? {
      background: `linear-gradient(180deg, ${C.gold}, ${C.goldDeep})`, color: '#000', fontWeight: 800,
      boxShadow: `0 8px 24px rgba(245,200,66,.30), 0 1px 0 rgba(255,255,255,.4) inset`,
    } : {}),
    ...extra,
  }),
  card: (extra = {}) => ({
    background: C.surface,
    backdropFilter: 'blur(20px) saturate(140%)',
    WebkitBackdropFilter: 'blur(20px) saturate(140%)',
    border: `1px solid ${C.border}`,
    borderRadius: 14,
    padding: '20px',
    boxShadow: GLASS_SHADOW,
    ...extra,
  }),
  input: (extra = {}) => ({
    background: C.inputBg, border: `1px solid ${C.border}`, borderRadius: 10,
    color: C.cream, fontFamily: 'Barlow, sans-serif', fontSize: 15,
    padding: '12px 14px', outline: 'none', width: '100%', boxSizing: 'border-box',
    transition: 'border-color .2s, box-shadow .2s',
    ...extra,
  }),
  label: { color: C.creamFaint, fontSize: 10, fontWeight: 700, letterSpacing: '.14em', textTransform: 'uppercase', marginBottom: 8, display: 'block' },
  h1: { fontFamily: "'Bebas Neue', sans-serif", color: C.cream, margin: 0, letterSpacing: '.03em' },
  h2: { fontFamily: "'Bebas Neue', sans-serif", color: C.cream, margin: 0, letterSpacing: '.03em' },
};

// ─── Helper Components ────────────────────────────────────────────────────────

function StatBox({ label, value, accent }) {
  return (
    <div style={s.card({ padding: '14px 16px', textAlign: 'center', flex: 1, minWidth: 0 })}>
      <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 30, color: accent || C.red, lineHeight: 1 }}>{value}</div>
      <div style={{ fontSize: 10, color: C.creamDim, marginTop: 4, textTransform: 'uppercase', letterSpacing: '.08em' }}>{label}</div>
    </div>
  );
}

function BackBtn({ onBack, label = 'Back' }) {
  return (
    <button onClick={onBack} style={s.btn('ghost', { display: 'flex', alignItems: 'center', gap: 6, paddingLeft: 0, fontSize: 12 })}>
      ← {label}
    </button>
  );
}

function KedroLogo({ height = 60 }) {
  return <img src={LOGO_B64} alt="Kedro" style={{ height, display: 'block', mixBlendMode: 'screen' }} />;
}

function Snow({ intensity = 'normal' }) {
  const count = intensity === 'blizzard' ? 80 : intensity === 'light' ? 18 : 40;
  const flakes = useRef(
    Array.from({ length: count }, (_, i) => ({
      id: i,
      left: Math.random() * 100,
      delay: Math.random() * 5,
      duration: 4 + Math.random() * 6,
      size: 2 + Math.random() * (intensity === 'blizzard' ? 6 : 4),
      opacity: 0.2 + Math.random() * 0.7,
      drift: Math.floor(Math.random() * 6), // picks snowFall0–snowFall5
    }))
  ).current;
  const iter = intensity === 'blizzard' ? 'infinite' : '3';
  return (
    <div style={{ position: 'fixed', inset: 0, pointerEvents: 'none', zIndex: 60, overflow: 'hidden' }}>
      {flakes.map(f => (
        <div key={f.id} style={{
          position: 'absolute', left: `${f.left}%`, top: -10,
          width: f.size, height: f.size, borderRadius: '50%',
          background: '#fff', opacity: f.opacity, willChange: 'transform',
          animation: `snowFall${f.drift} ${f.duration}s ${f.delay}s linear ${iter}`,
        }} />
      ))}
    </div>
  );
}

// ─── Main App ─────────────────────────────────────────────────────────────────

export default function KedroApp() {
  const [view, setView]               = useState('splash');
  const [user, setUser]               = useState(null);
  const [allPlayers, setAllPlayers]   = useState([]);
  const [allGames, setAllGames]       = useState([]);
  const [historyGame, setHistoryGame] = useState(null);
  const [postGameData, setPostGameData] = useState(null);
  const [live, setLive]               = useState(false);
  const [navDir, setNavDir]           = useState('forward');
  const logRef                        = useRef(null);
  if (!logRef.current) logRef.current = new GameLog();
  const log = logRef.current;
  const claimedRef = useRef(new Set());
  const userRef = useRef(null);
  userRef.current = user;

  // Sign-in and onboarding state
  const [authError, setAuthError]     = useState('');
  const [devAccounts, setDevAccounts] = useState([]);
  const [rName, setRName]             = useState('');
  const [rHandle, setRHandle]         = useState('');
  const [rEmoji, setREmoji]           = useState('🐴');

  // Game state
  const [ngSelected, setNgSelected]         = useState([]);
  const [roundInputs, setRoundInputs]       = useState({});
  const [roundError, setRoundError]         = useState('');
  const [knockedBy, setKnockedBy]           = useState(null);
  const [lastRoundDeltas, setLastRoundDeltas] = useState(null);
  const [isSavingRound, setIsSavingRound]   = useState(false);
  const isSavingRoundRef                    = useRef(false);
  const isEndingGameRef                     = useRef(false);
  const isAbandoningGameRef                 = useRef(false);
  const [showScoreSheet, setShowScoreSheet] = useState(false);
  const [endConfirm, setEndConfirm]         = useState(false);
  const [editingRound, setEditingRound]     = useState(null);
  const [editInputs, setEditInputs]         = useState({});

  // Edit profile / claim state
  const [editingProfile, setEditingProfile]   = useState(false);
  const [editUsername, setEditUsername]         = useState('');
  const [editEmoji, setEditEmoji]             = useState('');
  const [profileError, setProfileError]       = useState('');
  const [claimMessage, setClaimMessage]       = useState('');

  // Neigh tracker state (this phone only: the shared game log has no neighs)
  const [neighCounts, setNeighCounts] = useState({});
  const [inherentKnock, setInherentKnock] = useState(null);

  // Dashboard state
  const [dashboardView, setDashboardView] = useState('table');

  // The game in play: the newest unfinished game this player is seated in.
  const session = useMemo(
    () => allGames.filter(g => g.status === 'active').sort((a, b) => (b.startedAt ?? 0) - (a.startedAt ?? 0))[0] ?? null,
    [allGames],
  );

  // ── Loading ─────────────────────────────────────────────────────────────────
  /** Re-folds every game in the log into the screens' shape, newest first. */
  const refreshGames = useCallback((me = userRef.current) => {
    const aliasFor = (seatId) => {
      const ref = parseSeatId(seatId);
      return ref?.kind === 'guest' && claimedRef.current.has(ref.id) && me ? me.id : seatId;
    };
    const games = log.gameIds()
      .map(id => toWebGame(log.folded(id), aliasFor))
      .filter(g => g.folded.created)
      .sort((a, b) => (b.endedAt ?? 0) - (a.endedAt ?? 0));
    setAllGames(games);
    return games;
  }, [log]);

  /** Fetches this player's games (and their logs) and the player directory. */
  const loadData = useCallback(async (me) => {
    const mine = await api.myGames();
    claimedRef.current = new Set(mine.claimedGuestIds);
    const ids = mine.games.map(g => g.gameId);
    for (let i = 0; i < ids.length; i += 6) await Promise.all(ids.slice(i, i + 6).map(id => log.pull(id)));
    await log.flush();
    const games = refreshGames(me);

    const [players, guests] = await Promise.all([fetchAllPlayers(), api.guests('').catch(() => ({ guests: [] }))]);
    const seen = new Set(players.map(p => `p:${p.id}`));
    const guestRows = [];
    for (const g of guests.guests) if (!seen.has(`g:${g.guestId}`)) { seen.add(`g:${g.guestId}`); guestRows.push(webGuest(g.guestId, g.name)); }
    // Guests from this player's games (e.g. web history no one has claimed yet).
    for (const game of games) for (const p of game.players) {
      if (p.kind === 'guest' && p.id === p.seatId && !seen.has(p.id)) { seen.add(p.id); guestRows.push({ ...webGuest(p.seatId.slice(2), p.username), emoji: p.emoji }); }
    }
    setAllPlayers([...players.map(webPlayer), ...guestRows]);
    setLive(true);
  }, [log, refreshGames]);

  /** Moves a guest's history onto this account; the outcome shows on Profile. */
  const redeemClaim = useCallback(async (code, me) => {
    const token = code.trim().replace(/^.*[/=]/, '');
    if (!token) return;
    try {
      const result = await api.claim(token);
      setClaimMessage(`Done: ${result.gamesClaimed} game${result.gamesClaimed === 1 ? '' : 's'} are now yours.`);
      await loadData(me);
    } catch (error) {
      setClaimMessage(error.code === 'alreadyClaimed' ? 'Someone already claimed that history.' : error.status === 404 ? "That code doesn't match anyone." : error.status === 400 ? "That doesn't look like a claim code. Check it and try again." : (error.message || 'Could not claim that code'));
    }
  }, [loadData]);

  /** Signed in: load the profile (or ask for one), then everything else. */
  const enter = useCallback(async () => {
    try {
      const player = await api.me();
      const me = { ...webPlayer(player), createdAt: player.createdAt };
      setUser(me);
      await loadData(me);
      // Arrived from a claim link: redeem it and show how it went.
      const claim = takePendingClaim();
      if (claim) {
        await redeemClaim(claim, me);
        navigate('profile', 'forward');
        return;
      }
      navigate('home', 'forward');
    } catch (error) {
      if (error instanceof ApiError && error.code === 'profileRequired') { navigate('onboarding', 'forward'); return; }
      if (error instanceof ApiError && error.status === 401) { await signOut(); navigate('login', 'back'); return; }
      setAuthError(error.message || 'Could not reach Kedro. Try again.');
      navigate('login', 'back');
    }
  }, [loadData, redeemClaim]);

  useEffect(() => {
    let cancelled = false;
    stashClaimFromURL();
    (async () => {
      const signedIn = await isSignedIn();
      if (devSignInAvailable) api.devAccounts().then(r => !cancelled && setDevAccounts(r.accounts ?? [])).catch(() => {});
      setTimeout(() => { if (!cancelled) (signedIn ? enter() : navigate('login', 'forward')); }, 1200);
    })();
    // Back from Google: Supabase stores the session, then this fires (also on token refreshes,
    // which aren't new sign-ins: only enter when nobody is signed in here yet).
    const stop = onAuthChange(event => { if (event === 'SIGNED_IN' && !cancelled && !userRef.current) enter(); });
    return () => { cancelled = true; stop(); };
    // Once, on launch: `enter` is stable (it only reads refs and setters).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // ── Live sync: follow the game in play, retry uploads ─────────────────────────
  useEffect(() => {
    if (!user) return;
    const timer = setInterval(async () => {
      try {
        if (session) await log.pull(session.id);
        await log.flush();
        refreshGames();
        setLive(true);
      } catch {
        setLive(false);
      }
    }, session ? 3000 : 15000);
    return () => clearInterval(timer);
  }, [user, session?.id, log, refreshGames]);

  // ── Navigation ───────────────────────────────────────────────────────────────
  function navigate(newView, dir = 'forward') {
    setNavDir(dir);
    setView(newView);
  }

  // ── Auth ─────────────────────────────────────────────────────────────────────
  async function handleSignIn(signIn) {
    setAuthError('');
    const { error } = await signIn();
    if (error) setAuthError(error.message);
  }

  function handleDevAccount(account) {
    signInAsDevAccount(account.id);
    enter();
  }

  async function handleRegister() {
    const name = rName.trim();
    const handle = (rHandle.trim() || suggestedHandle(name)).toLowerCase().replace(/^@/, '');
    if (!name) { setAuthError('Enter your name'); return; }
    if (!HANDLE_PATTERN.test(handle)) { setAuthError('Handles are 3–20 letters, numbers, dots or underscores'); return; }
    try {
      await api.saveProfile({ displayName: name, handle, avatar: { kind: 'emoji', emoji: rEmoji, colorIndex: 0 } });
      setAuthError(''); setRName(''); setRHandle(''); setREmoji('🐴');
      await enter();
    } catch (error) {
      setAuthError(error.code === 'handleTaken' ? `@${handle} is taken. Pick another handle.` : (error.message || 'Could not save your profile'));
    }
  }

  async function logout() {
    await signOut();
    setUser(null); setAllGames([]); setAllPlayers([]);
    navigate('login', 'back');
  }

  async function handleEditProfile() {
    const name = editUsername.trim();
    if (!name) return;
    try {
      const avatar = user.avatar?.kind === 'emoji' ? { ...user.avatar, emoji: editEmoji } : { kind: 'emoji', emoji: editEmoji, colorIndex: 0 };
      const player = await api.saveProfile({ displayName: name, handle: user.handle, avatar });
      setUser({ ...webPlayer(player), createdAt: player.createdAt });
      setProfileError('');
      setEditingProfile(false);
    } catch (error) {
      setProfileError(error.message || 'Could not save your profile');
    }
  }

  function handleClaim(code) {
    return redeemClaim(code, user);
  }

  // ── Game logic ───────────────────────────────────────────────────────────────
  function resetRoundState() {
    setRoundInputs({}); setKnockedBy(null); setRoundError(''); setInherentKnock(null);
  }

  async function startGame(players, firstPlayerIndex = 0) {
    const gameId = await createGame(log, user, players, firstPlayerIndex);
    refreshGames();
    setNgSelected([]); resetRoundState(); setNeighCounts({});
    navigate('game', 'forward');
    return gameId;
  }

  async function addRound() {
    if (!session) return;
    if (isSavingRoundRef.current) return;
    const missing = session.players.some(p => roundInputs[p.id] === undefined || roundInputs[p.id] === '' || Number.isNaN(parseInt(roundInputs[p.id])));
    if (missing) { setRoundError('Enter a hand for every player'); return; }
    if (!knockedBy) { setRoundError('Who knocked?'); return; }
    const knocker = session.players.find(p => p.id === knockedBy);
    const hands = Object.fromEntries(session.players.map(p => [p.seatId, parseInt(roundInputs[p.id])]));
    const ik = inherentKnock === knockedBy;
    if (ik && hands[knocker.seatId] !== 0) { setRoundError('An inherent knock means a hand of 0'); return; }

    isSavingRoundRef.current = true;
    setIsSavingRound(true);
    try {
      const round = roundOf(session.rounds.length + 1, hands, knocker.seatId, ik);
      await recordRound(log, user, session.id, round);
      const games = refreshGames();
      const saved = games.find(g => g.id === session.id)?.rounds.at(-1);
      if (saved) { setLastRoundDeltas(saved.scores); setTimeout(() => setLastRoundDeltas(null), 2500); }
      resetRoundState();
      setShowScoreSheet(false);
    } finally {
      isSavingRoundRef.current = false;
      setIsSavingRound(false);
    }
  }

  async function editRound(roundIndex) {
    if (!session) return;
    const r = session.rounds[roundIndex];
    const hands = Object.fromEntries(session.players.map(p => [p.seatId, parseInt(editInputs[p.id]) || 0]));
    const ik = !!r.inherentKnock;
    if (ik && hands[r.knockerSeat] !== 0) return;
    await writeRoundEdit(log, user, session.id, roundOf(r.number, hands, r.knockerSeat, ik));
    refreshGames();
    setEditingRound(null); setEditInputs({});
  }

  async function endGame() {
    if (!session) return;
    if (isEndingGameRef.current) return;
    isEndingGameRef.current = true;
    try {
      await finishGame(log, user, session.folded);
      const games = refreshGames();
      setPostGameData({ ...(games.find(g => g.id === session.id) ?? session), neighCounts });
      setEndConfirm(false);
      navigate('postgame', 'forward');
    } finally {
      isEndingGameRef.current = false;
    }
  }

  async function abandonGame() {
    if (!session) return;
    if (isAbandoningGameRef.current) return;
    isAbandoningGameRef.current = true;
    try {
      await writeAbandon(log, user, session.id);
      refreshGames();
      setEndConfirm(false);
      navigate('home', 'back');
    } finally {
      isAbandoningGameRef.current = false;
    }
  }

  async function setCurrentTurn(index) {
    if (!session) return;
    const seat = session.players[index];
    if (!seat) return;
    await setDealer(log, user, session.id, session.rounds.length + 1, seat.seatId);
    refreshGames();
  }

  async function rematch(players) {
    const people = players.map(p => p.id === user.id ? user : ({ ref: parseSeatId(p.seatId ?? p.id), username: p.username, emoji: p.emoji, ...(allPlayers.find(x => x.id === p.id) ?? {}) }));
    resetRoundState(); setNeighCounts({});
    setPostGameData(null);
    await startGame(people, 0);
  }

  // ── Stats ────────────────────────────────────────────────────────────────────
  // From the games this player was in (every finished game, once their web history is claimed).
  function getStats(playerId, opts = {}) {
    const { minRounds = 0 } = opts;
    const pg = allGames.filter(g =>
      g.status === 'complete' &&
      g.players.find(p => p.id === playerId) &&
      (g.rounds?.length || 0) >= minRounds
    );
    const wins = pg.filter(g => g.winnerId === playerId).length;
    const finalScores = pg.map(g => g.players.find(p => p.id === playerId)?.total).filter(x => x !== undefined);
    const roundScores = pg.flatMap(g =>
      (g.rounds || []).map(r => r.scores.find(s => s.playerId === playerId)?.score)
    ).filter(x => x !== undefined);

    // Streaks (oldest → newest)
    let currentStreak = 0, longestStreak = 0, tempStreak = 0;
    [...pg].reverse().forEach((g, i) => {
      if (g.winnerId === playerId) {
        tempStreak++;
        longestStreak = Math.max(longestStreak, tempStreak);
        if (i === 0) currentStreak = tempStreak;
      } else {
        if (i === 0) currentStreak = 0;
        tempStreak = 0;
      }
    });

    const allRounds = pg.flatMap(g => g.rounds || []);
    const myKnocks  = allRounds.filter(r => r.knockedBy === playerId);
    const kedroWins = myKnocks.filter(r => r.knockerWon).length;

    const nemesisCounts = {};
    pg.filter(g => g.winnerId && g.winnerId !== playerId).forEach(g => {
      nemesisCounts[g.winnerId] = (nemesisCounts[g.winnerId] || 0) + 1;
    });
    const nemesisId = Object.entries(nemesisCounts).sort((a, b) => b[1] - a[1])[0]?.[0];
    const nemesis   = nemesisId ? (allPlayers.find(p => p.id === nemesisId) ?? pg.flatMap(g => g.players).find(p => p.id === nemesisId)) : null;

    const totalInherentKnocks = allRounds.filter(r => r.inherentKnock === playerId).length;

    return {
      played: pg.length, wins,
      winRate:     pg.length      ? Math.round(wins / pg.length * 100) : 0,
      avgScore:    finalScores.length ? Math.round(finalScores.reduce((a, b) => a + b, 0) / finalScores.length) : '—',
      avgRound:    roundScores.length ? (roundScores.reduce((a, b) => a + b, 0) / roundScores.length).toFixed(1) : '—',
      best:        finalScores.length ? Math.min(...finalScores) : '—',
      worst:       finalScores.length ? Math.max(...finalScores) : '—',
      currentStreak, longestStreak,
      totalKnocks: myKnocks.length, kedroWins,
      knockRate:    allRounds.length  ? Math.round(myKnocks.length / allRounds.length * 100) : 0,
      kedroWinPct:  myKnocks.length   ? Math.round(kedroWins / myKnocks.length * 100) : '—',
      nemesis,
      totalInherentKnocks,
    };
  }

  // ── CSS ──────────────────────────────────────────────────────────────────────
  const CSS = `
    * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
    body { margin: 0; background: ${C.bg}; color: ${C.cream}; font-family: 'Barlow', system-ui, sans-serif; }
    input:focus { border-color: ${C.red} !important; box-shadow: 0 0 0 3px ${C.redGlow}; }
    input[type=number]::-webkit-inner-spin-button { -webkit-appearance: none; }
    .btn-press:active { transform: scale(0.97) !important; }
    .btn-red:hover { filter: brightness(1.08); }
    .btn-outline:hover { border-color: rgba(230,57,70,.5) !important; color: ${C.red} !important; }
    .player-tile:hover { border-color: rgba(230,57,70,.4) !important; }
    .emoji-btn:hover { transform: scale(1.2); }
    @keyframes fadeIn      { from { opacity:0; transform:translateY(8px); } to { opacity:1; transform:translateY(0); } }
    @keyframes slideInRight { from { opacity:0; transform:translateX(32px); } to { opacity:1; transform:translateX(0); } }
    @keyframes slideInLeft  { from { opacity:0; transform:translateX(-32px); } to { opacity:1; transform:translateX(0); } }
    @keyframes pulse       { 0%,100%{opacity:1;} 50%{opacity:.3;} }
    @keyframes slideUp     { from { transform:translateY(100%); } to { transform:translateY(0); } }
    @keyframes deltaFade   { 0%{opacity:0;transform:translateY(-6px);} 15%{opacity:1;transform:translateY(0);} 75%{opacity:1;} 100%{opacity:0;} }
    @keyframes snowFall0 { 0%{transform:translateY(-10px) translateX(0);opacity:0} 10%{opacity:1} 90%{opacity:.6} 100%{transform:translateY(105vh) translateX(-15px);opacity:0} }
    @keyframes snowFall1 { 0%{transform:translateY(-10px) translateX(0);opacity:0} 10%{opacity:1} 90%{opacity:.6} 100%{transform:translateY(105vh) translateX(20px);opacity:0} }
    @keyframes snowFall2 { 0%{transform:translateY(-10px) translateX(0);opacity:0} 10%{opacity:1} 90%{opacity:.6} 100%{transform:translateY(105vh) translateX(-25px);opacity:0} }
    @keyframes snowFall3 { 0%{transform:translateY(-10px) translateX(0);opacity:0} 10%{opacity:1} 90%{opacity:.6} 100%{transform:translateY(105vh) translateX(10px);opacity:0} }
    @keyframes snowFall4 { 0%{transform:translateY(-10px) translateX(0);opacity:0} 10%{opacity:1} 90%{opacity:.6} 100%{transform:translateY(105vh) translateX(-8px);opacity:0} }
    @keyframes snowFall5 { 0%{transform:translateY(-10px) translateX(0);opacity:0} 10%{opacity:1} 90%{opacity:.6} 100%{transform:translateY(105vh) translateX(30px);opacity:0} }
    @keyframes crownBob    { 0%,100%{transform:translateY(0);} 50%{transform:translateY(-3px);} }
    @keyframes shimmer     { 0%,100%{opacity:.7;} 50%{opacity:1;} }
    .screen-fwd { animation: slideInRight .25s cubic-bezier(.4,0,.2,1); }
    .screen-bk  { animation: slideInLeft  .25s cubic-bezier(.4,0,.2,1); }
    .red-line { width: 40px; height: 3px; background: ${C.red}; margin: 8px 0; }
  `;

  // ── Render ───────────────────────────────────────────────────────────────────
  const pad = { padding: '0 18px' };

  return (
    <>
      <style>{FONTS}{CSS}</style>
      <div style={{
        minHeight: '100vh',
        background: `radial-gradient(ellipse 80% 60% at 50% 0%, ${C.bgGradFrom} 0%, ${C.bg} 60%, ${C.bgGradTo} 100%)`,
        color: C.cream, fontFamily: "'Barlow', system-ui, sans-serif", position: 'relative',
      }}>

        {/* Atmospheric card suit watermarks */}
        <div style={{ position: 'fixed', inset: 0, pointerEvents: 'none', zIndex: 0, overflow: 'hidden' }}>
          <div style={{ position: 'absolute', top: '8%',     left: '-3%',   fontSize: 280, color: 'rgba(245,239,230,.025)', fontFamily: 'serif', lineHeight: 1 }}>♠</div>
          <div style={{ position: 'absolute', top: '38%',    right: '-5%',  fontSize: 320, color: 'rgba(230,57,70,.04)',    fontFamily: 'serif', lineHeight: 1 }}>♥</div>
          <div style={{ position: 'absolute', bottom: '8%',  left: '-2%',   fontSize: 260, color: 'rgba(230,57,70,.035)',   fontFamily: 'serif', lineHeight: 1 }}>♦</div>
          <div style={{ position: 'absolute', bottom: '32%', right: '-3%',  fontSize: 240, color: 'rgba(245,239,230,.02)',  fontFamily: 'serif', lineHeight: 1 }}>♣</div>
        </div>

        <div style={{ position: 'relative', zIndex: 1, maxWidth: 480, margin: '0 auto', ...pad }}>
          <div key={view} className={navDir === 'forward' ? 'screen-fwd' : 'screen-bk'}>

          {view === 'splash' && <SplashScreen />}

          {view === 'login' && (
            <LoginScreen
              error={authError} devAccounts={devAccounts}
              onApple={() => handleSignIn(signInWithApple)} onGoogle={() => handleSignIn(signInWithGoogle)} onDevAccount={handleDevAccount}
            />
          )}

          {view === 'onboarding' && (
            <OnboardingScreen
              error={authError} rName={rName} rHandle={rHandle} rEmoji={rEmoji}
              onRNameChange={setRName} onRHandleChange={setRHandle} onREmojiChange={setREmoji}
              onRegister={handleRegister} onSignOut={logout}
            />
          )}

          {view !== 'splash' && view !== 'login' && view !== 'onboarding' && user && (
            <>
              {view === 'home' && (
                <HomeScreen
                  user={user} stats={getStats(user.id)} session={session} live={live}
                  recentGames={allGames.filter(g => g.status === 'complete').slice(0, 5)}
                  lastGame={allGames.find(g => g.status === 'complete')}
                  onNewGame={() => navigate('newgame', 'forward')}
                  onResumeGame={() => navigate('game', 'forward')}
                  onHistory={() => navigate('history', 'forward')}
                  onProfile={() => navigate('profile', 'forward')}
                  onDashboard={() => navigate('dashboard', 'forward')}
                  onLogout={logout}
                  onRematch={(g) => rematch(g.players)}
                />
              )}

              {view === 'newgame' && (
                <NewGameScreen
                  user={user} allPlayers={allPlayers.filter(p => !p.deleted)} selected={ngSelected}
                  onToggle={p => setNgSelected(prev =>
                    prev.find(x => x.id === p.id) ? prev.filter(x => x.id !== p.id) : [...prev, p]
                  )}
                  onStart={(orderedPlayers, firstPlayerIndex) => {
                    if (orderedPlayers.length >= SEAT_LIMITS.min && orderedPlayers.length <= SEAT_LIMITS.max) startGame(orderedPlayers, firstPlayerIndex);
                  }}
                  onAddGuest={name => {
                    const guest = webGuest(crypto.randomUUID(), name);
                    setAllPlayers(prev => [...prev, guest]);
                    setNgSelected(prev => [...prev, guest]);
                  }}
                  onBack={() => navigate('home', 'back')}
                />
              )}

              {view === 'game' && session && (
                <GameScreen
                  session={session} user={user}
                  roundInputs={roundInputs} knockedBy={knockedBy}
                  roundError={roundError} lastRoundDeltas={lastRoundDeltas}
                  isSavingRound={isSavingRound}
                  showScoreSheet={showScoreSheet} endConfirm={endConfirm}
                  editingRound={editingRound} editInputs={editInputs}
                  onInput={(id, val) => setRoundInputs(prev => ({ ...prev, [id]: val }))}
                  onKnockedBy={id => { setKnockedBy(prev => prev === id ? null : id); setInherentKnock(null); }}
                  onAddRound={addRound}
                  onEndGame={endGame}
                  onEndConfirm={() => setEndConfirm(true)}
                  onCancelEnd={() => setEndConfirm(false)}
                  onShowSheet={() => setShowScoreSheet(true)}
                  onHideSheet={() => { setShowScoreSheet(false); setRoundError(''); }}
                  onAbandon={abandonGame}
                  onHome={() => navigate('home', 'back')}
                  onEditRound={idx => {
                    const r = session.rounds[idx];
                    const inputs = {};
                    session.players.forEach(p => { inputs[p.id] = String(r.hands[p.seatId] ?? ''); });
                    setEditInputs(inputs); setEditingRound(idx);
                  }}
                  onEditInput={(id, val) => setEditInputs(prev => ({ ...prev, [id]: val }))}
                  onSaveEdit={editRound}
                  onCancelEdit={() => { setEditingRound(null); setEditInputs({}); }}
                  neighCounts={neighCounts}
                  onNeigh={id => { playNeigh(); setNeighCounts(prev => ({ ...prev, [id]: (prev[id] || 0) + 1 })); }}
                  inherentKnock={inherentKnock}
                  onInherentKnock={id => {
                    setInherentKnock(prev => prev === id ? null : id);
                    setKnockedBy(id);
                    setRoundInputs(prev => ({ ...prev, [id]: '0' }));
                  }}
                  onSetTurn={setCurrentTurn}
                />
              )}

              {view === 'postgame' && postGameData && (
                <PostGameScreen
                  game={postGameData} user={user} getStats={getStats}
                  onRematch={() => rematch(postGameData.players)}
                  onHome={() => { setPostGameData(null); navigate('home', 'back'); }}
                />
              )}

              {view === 'history' && (
                <HistoryScreen
                  games={allGames} user={user} selected={historyGame}
                  onSelect={setHistoryGame} onBack={() => navigate('home', 'back')}
                />
              )}

              {view === 'profile' && (
                <ProfileScreen
                  user={user} stats={getStats(user.id)} games={allGames}
                  allPlayers={allPlayers} session={session}
                  onBack={() => navigate('home', 'back')}
                  onLogout={logout}
                  editingProfile={editingProfile}
                  onStartEdit={() => { setEditUsername(user.username); setEditEmoji(user.emoji); setEditingProfile(true); }}
                  onCancelEdit={() => { setEditingProfile(false); setProfileError(''); }}
                  editUsername={editUsername} onEditUsername={setEditUsername}
                  editEmoji={editEmoji} onEditEmoji={setEditEmoji}
                  onSaveEdit={handleEditProfile} profileError={profileError}
                  claimMessage={claimMessage} onClaim={handleClaim}
                />
              )}

              {view === 'dashboard' && (
                <DashboardScreen
                  allGames={allGames}
                  user={user}
                  viewMode={dashboardView} onToggleView={setDashboardView}
                  onBack={() => navigate('home', 'back')}
                />
              )}
            </>
          )}
          </div>
        </div>
      </div>
    </>
  );
}

// ─── Screens ──────────────────────────────────────────────────────────────────

function SplashScreen() {
  return (
    <div className="screen" style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 24, textAlign: 'center' }}>
      <Snow intensity="light" />
      <KedroLogo height={160} />
      <div style={{ color: C.silverDim, fontSize: 11, letterSpacing: '.2em', textTransform: 'uppercase' }}>Score Tracker</div>
      <div style={{ display: 'flex', gap: 8 }}>
        {[0, 1, 2].map(i => (
          <div key={i} style={{ width: 8, height: 8, borderRadius: '50%', background: C.red, animation: `pulse 1.2s ease ${i * .2}s infinite` }} />
        ))}
      </div>
    </div>
  );
}

function LoginScreen({ error, devAccounts, onApple, onGoogle, onDevAccount }) {
  return (
    <div className="screen" style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: '40px 0' }}>
      <div style={{ textAlign: 'center', marginBottom: 32, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        <KedroLogo height={120} />
        <div style={{ color: C.creamDim, fontSize: 11, letterSpacing: '.18em', textTransform: 'uppercase', marginTop: 10 }}>Score Tracker</div>
        <div className="red-line" style={{ margin: '10px auto 0' }} />
      </div>
      <div style={s.card({ padding: 28 })}>
        <div style={{ ...s.h2, fontSize: 26, marginBottom: 8 }}>Who's talking shit?</div>
        <div style={{ color: C.creamDim, fontSize: 13, marginBottom: 20 }}>Sign in to keep score. Same account, same scoreboard as the Kedro iPhone app.</div>
        <button className="btn-press" onClick={onApple} style={{ ...s.btn('ghost'), width: '100%', padding: 14, fontSize: 15, background: '#fff', color: '#000', border: 'none', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 }}>
          <svg width="17" height="17" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12.152 6.896c-.948 0-2.415-1.078-3.96-1.04-2.04.027-3.91 1.183-4.961 3.014-2.117 3.675-.546 9.103 1.519 12.09 1.013 1.454 2.208 3.09 3.792 3.039 1.52-.065 2.09-.987 3.935-.987 1.831 0 2.35.987 3.96.948 1.637-.026 2.676-1.48 3.676-2.948 1.156-1.688 1.636-3.325 1.662-3.415-.039-.013-3.182-1.221-3.22-4.857-.026-3.04 2.48-4.494 2.597-4.559-1.429-2.09-3.623-2.324-4.39-2.376-2-.156-3.675 1.09-4.61 1.09zM15.53 3.83c.843-1.012 1.4-2.427 1.245-3.83-1.207.052-2.662.805-3.532 1.818-.78.896-1.454 2.338-1.273 3.714 1.338.104 2.715-.688 3.559-1.701"/></svg>
          Continue with Apple
        </button>
        <button className="btn-red btn-press" onClick={onGoogle} style={{ ...s.btn('red'), width: '100%', padding: 14, fontSize: 15, marginTop: 10 }}>Continue with Google</button>
        <div style={{ color: C.creamDim, fontSize: 12, marginTop: 12, textAlign: 'center' }}>On an iPhone? Use Apple, the same as in the app, so it's one account.</div>
        {error && <div style={{ color: C.red, fontSize: 13, marginTop: 10 }}>{error}</div>}
        {devAccounts.length > 0 && (
          <div style={{ marginTop: 22 }}>
            <label style={s.label}>Test accounts (local API)</label>
            <div style={{ maxHeight: 220, overflowY: 'auto', border: `1px solid ${C.border}`, borderRadius: 6 }}>
              {devAccounts.map(account => (
                <div key={account.id} onClick={() => onDevAccount(account)}
                  style={{ padding: '10px 14px', cursor: 'pointer', display: 'flex', justifyContent: 'space-between', borderBottom: `1px solid ${C.border}` }}>
                  <span style={{ color: C.cream, fontSize: 14 }}>{account.displayName}</span>
                  <span style={{ color: C.creamDim, fontSize: 12 }}>@{account.handle} · {account.gamesClaimed} games</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
      <a href="/privacy.html" style={{ color: C.creamDim, fontSize: 12, textAlign: 'center', marginTop: 18 }}>Privacy Policy</a>
    </div>
  );
}

function OnboardingScreen({ error, rName, rHandle, rEmoji, onRNameChange, onRHandleChange, onREmojiChange, onRegister, onSignOut }) {
  const placeholder = rName.trim() ? suggestedHandle(rName.trim()) : 'yourname';
  return (
    <div className="screen" style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: '40px 0' }}>
      <div style={{ textAlign: 'center', marginBottom: 24, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        <KedroLogo height={90} />
      </div>
      <div style={s.card({ padding: 28 })}>
        <div style={{ ...s.h2, fontSize: 24, marginBottom: 6 }}>Fresh Meat</div>
        <div style={{ color: C.creamDim, fontSize: 13, marginBottom: 18 }}>Played on the old web app? Set up your profile, then enter your claim code under Profile to bring your games over.</div>
        <div style={{ marginBottom: 16 }}>
          <label style={s.label}>Choose your avatar</label>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
            {EMOJIS.map(e => (
              <button key={e} className="emoji-btn" onClick={() => onREmojiChange(e)}
                style={{ fontSize: 22, background: rEmoji === e ? C.surface3 : 'transparent', border: `2px solid ${rEmoji === e ? C.red : C.border}`, borderRadius: 8, padding: '5px 7px', cursor: 'pointer', transition: 'all .15s' }}>
                {e}
              </button>
            ))}
          </div>
        </div>
        <div style={{ marginBottom: 16 }}>
          <label style={s.label}>Name</label>
          <input style={s.input()} placeholder="What the table calls you" value={rName} onChange={e => onRNameChange(e.target.value)} autoFocus />
        </div>
        <div style={{ marginBottom: 16 }}>
          <label style={s.label}>Handle</label>
          <input style={s.input()} placeholder={`@${placeholder}`} value={rHandle} onChange={e => onRHandleChange(e.target.value)}
            onKeyDown={e => { if (e.key === 'Enter') onRegister(); }} autoCapitalize="none" autoCorrect="off" />
        </div>
        {error && <div style={{ color: C.red, fontSize: 13, marginBottom: 10 }}>{error}</div>}
        <button className="btn-red btn-press" onClick={onRegister} style={{ ...s.btn('red'), width: '100%' }}>Let's Go 🐴</button>
        <div style={{ textAlign: 'center', marginTop: 14 }}>
          <button onClick={onSignOut} style={s.btn('ghost', { fontSize: 12 })}>Use a different account</button>
        </div>
      </div>
    </div>
  );
}

function HomeScreen({ user, stats, session, live, recentGames, lastGame, onNewGame, onResumeGame, onHistory, onProfile, onDashboard, onLogout, onRematch }) {
  const greet = useMemo(() => TRASH.homeGreet(user.username), [user.username]);
  return (
    <div className="screen" style={{ paddingTop: 36, paddingBottom: 60 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 24 }}>
        <div>
          <KedroLogo height={44} />
          <div style={{ marginTop: 10 }}>
            <div style={{ fontSize: 12, color: C.creamDim, marginBottom: 2 }}>{greet}</div>
            <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 28, color: C.cream, lineHeight: 1 }}>{user.emoji} {user.username}</div>
          </div>
        </div>
        {live && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: 6 }}>
            <div style={{ width: 7, height: 7, borderRadius: '50%', background: C.green, boxShadow: `0 0 6px ${C.green}`, animation: 'pulse 2s ease infinite' }} />
            <span style={{ fontSize: 10, color: C.green, textTransform: 'uppercase', letterSpacing: '.1em' }}>Live</span>
          </div>
        )}
      </div>

      <div style={{ display: 'flex', gap: 8, marginBottom: 20 }}>
        <StatBox label="Games" value={stats.played} />
        <StatBox label="Wins" value={stats.wins} accent={C.green} />
        <StatBox label="Win %" value={stats.played ? `${stats.winRate}%` : '—'} accent={C.blue} />
        <StatBox label="Best" value={stats.best} accent={C.gold} />
      </div>

      {session && (
        <div style={{ background: 'rgba(212,43,43,.08)', border: `1px solid rgba(212,43,43,.4)`, borderRadius: 10, padding: '16px 18px', marginBottom: 12, cursor: 'pointer' }} onClick={onResumeGame}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <div style={{ color: C.red, fontSize: 11, letterSpacing: '.1em', textTransform: 'uppercase', marginBottom: 4 }}>Unfinished Business</div>
              <div style={{ color: C.cream, fontSize: 14 }}>{session.players.map(p => p.username).join(' · ')}</div>
              <div style={{ color: C.creamDim, fontSize: 12, marginTop: 3 }}>{session.rounds.length} round{session.rounds.length !== 1 ? 's' : ''} played</div>
            </div>
            <div style={{ color: C.red, fontSize: 22 }}>→</div>
          </div>
        </div>
      )}

      <button className="btn-red btn-press" onClick={onNewGame} style={{ ...s.btn('red'), width: '100%', padding: 14, fontSize: 15, marginBottom: 8 }}>
        + New Game 🐴
      </button>
      {lastGame && !session && (
        <button className="btn-outline btn-press" onClick={() => onRematch(lastGame)} style={{ ...s.btn('outline'), width: '100%', padding: 12, marginBottom: 0 }}>
          🔁 Rematch — {lastGame.players.map(p => p.username).join(', ')}
        </button>
      )}

      {recentGames.length > 0 && (
        <div style={{ marginTop: 24 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
            <div style={{ color: C.silverDim, fontSize: 11, letterSpacing: '.08em', textTransform: 'uppercase' }}>Recent Games</div>
            <button onClick={onHistory} style={s.btn('ghost', { fontSize: 11 })}>View all →</button>
          </div>
          {recentGames.map(g => {
            const winner = g.players.find(p => p.id === g.winnerId);
            const date = new Date(g.endedAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
            return (
              <div key={g.id} style={{ ...s.card({ padding: '12px 16px', marginBottom: 8 }), display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <div>
                  <div style={{ fontSize: 13, color: C.cream }}>{g.players.map(p => `${p.emoji}${p.username}`).join(' · ')}</div>
                  <div style={{ fontSize: 11, color: C.creamDim, marginTop: 3 }}>{date} · {g.rounds.length}R</div>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div style={{ fontSize: 10, color: C.red, textTransform: 'uppercase', letterSpacing: '.06em' }}>Winner</div>
                  <div style={{ fontSize: 13, color: C.cream }}>{winner?.emoji}{winner?.username}</div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      <div style={{ display: 'flex', justifyContent: 'center', gap: 6, marginTop: 28, flexWrap: 'wrap' }}>
        <button className="btn-press" onClick={onDashboard} style={s.btn('ghost')}>📊 Leaderboard</button>
        <button className="btn-press" onClick={onHistory} style={s.btn('ghost')}>📋 History</button>
        <button className="btn-press" onClick={onProfile} style={s.btn('ghost')}>👤 Profile</button>
        <button className="btn-press" onClick={onLogout} style={s.btn('ghost', { fontSize: 11 })}>Sign out</button>
      </div>
    </div>
  );
}

function NewGameScreen({ user, allPlayers, selected, onToggle, onStart, onAddGuest, onBack }) {
  const [filter, setFilter] = useState('');
  const others = allPlayers.filter(p => p.id !== user.id);
  const shown = others.filter(p => !filter.trim() || p.username.toLowerCase().includes(filter.trim().toLowerCase()) || p.handle?.includes(filter.trim().toLowerCase().replace(/^@/, '')) || selected.find(x => x.id === p.id));
  const count = selected.length + 1;
  const ready = count >= SEAT_LIMITS.min && count <= SEAT_LIMITS.max;

  // Seating order state — user is always included, kept in sync with `selected`.
  const [order, setOrder] = useState([user]);
  const [firstId, setFirstId] = useState(user.id);

  useEffect(() => {
    const desired = [user, ...selected];
    const desiredIds = new Set(desired.map(p => p.id));
    setOrder(prev => {
      const kept = prev.filter(p => desiredIds.has(p.id));
      const keptIds = new Set(kept.map(p => p.id));
      const added = desired.filter(p => !keptIds.has(p.id));
      return [...kept, ...added];
    });
    setFirstId(prev => desiredIds.has(prev) ? prev : user.id);
  }, [selected, user]);

  function move(idx, dir) {
    setOrder(prev => {
      const next = [...prev];
      const swap = idx + dir;
      if (swap < 0 || swap >= next.length) return prev;
      [next[idx], next[swap]] = [next[swap], next[idx]];
      return next;
    });
  }

  function handleStart() {
    const firstIndex = Math.max(0, order.findIndex(p => p.id === firstId));
    onStart(order, firstIndex);
  }

  return (
    <div className="screen" style={{ paddingTop: 32, paddingBottom: 40 }}>
      <BackBtn onBack={onBack} />
      <div style={{ margin: '16px 0 6px' }}><KedroLogo height={36} /></div>
      <div style={{ ...s.h1, fontSize: 36 }}>New Game</div>
      <div className="red-line" />
      <div style={{ color: C.creamDim, fontSize: 14, marginBottom: 22 }}>Pick your victims. You're always in.</div>

      <div style={{ ...s.card({ padding: '12px 16px', marginBottom: 14, border: `1px solid ${C.red}`, background: 'rgba(212,43,43,.06)' }), display: 'flex', alignItems: 'center', gap: 12 }}>
        <div style={{ fontSize: 26 }}>{user.emoji}</div>
        <div>
          <div style={{ color: C.red, fontSize: 11, textTransform: 'uppercase', letterSpacing: '.07em' }}>You</div>
          <div style={{ color: C.cream, fontSize: 15 }}>{user.username}</div>
        </div>
        <div style={{ marginLeft: 'auto', color: C.red, fontSize: 16 }}>✓</div>
      </div>

      <div style={{ color: C.silverDim, fontSize: 11, letterSpacing: '.08em', textTransform: 'uppercase', marginBottom: 10 }}>Add Players</div>
      <div style={{ display: 'flex', gap: 8, marginBottom: 10 }}>
        <input style={s.input({ flex: 1 })} placeholder="Find a player, or type a guest's name" value={filter} onChange={e => setFilter(e.target.value)} />
        <button className="btn-press" disabled={!filter.trim()}
          onClick={() => { onAddGuest(filter.trim().slice(0, 40)); setFilter(''); }}
          style={s.btn('outline', { whiteSpace: 'nowrap', opacity: filter.trim() ? 1 : 0.4 })}>+ Guest</button>
      </div>
      {shown.length === 0 ? (
        <div style={{ ...s.card({ padding: 24, textAlign: 'center' }), color: C.creamDim }}>{others.length === 0 ? 'No one else here yet. Add a guest above.' : 'No one by that name. Add them as a guest.'}</div>
      ) : (
        <>
          {shown.map(p => {
            const sel = !!selected.find(x => x.id === p.id);
            return (
              <div key={p.id} className="player-tile" onClick={() => onToggle(p)}
                style={{ ...s.card({ padding: '12px 16px', marginBottom: 8, cursor: 'pointer', border: `1px solid ${sel ? C.red : C.border}`, background: sel ? 'rgba(212,43,43,.07)' : C.surface2, transition: 'all .15s' }), display: 'flex', alignItems: 'center', gap: 12 }}>
                <div style={{ fontSize: 26 }}>{p.emoji}</div>
                <div style={{ flex: 1, color: C.cream, fontSize: 15 }}>
                  {p.username}
                  <div style={{ color: C.creamDim, fontSize: 11 }}>{p.isGuest ? 'Guest' : `@${p.handle}`}</div>
                </div>
                <div style={{ width: 22, height: 22, borderRadius: '50%', border: `2px solid ${sel ? C.red : C.borderLight}`, background: sel ? C.red : 'transparent', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontSize: 12, transition: 'all .15s' }}>
                  {sel ? '✓' : ''}
                </div>
              </div>
            );
          })}
        </>
      )}

      {count >= 2 && (
        <div style={{ marginTop: 22 }}>
          <div style={{ color: C.silverDim, fontSize: 11, letterSpacing: '.08em', textTransform: 'uppercase', marginBottom: 6 }}>Seating Order (Clockwise)</div>
          <div style={{ color: C.creamDim, fontSize: 12, marginBottom: 10, fontStyle: 'italic' }}>
            Use arrows to set the order. Tap a player to mark who deals first 👉
          </div>
          {order.map((p, i) => {
            const isFirst = p.id === firstId;
            return (
              <div key={p.id}
                style={{ ...s.card({ padding: '10px 12px', marginBottom: 6, border: `1px solid ${isFirst ? C.gold : C.border}`, background: isFirst ? 'rgba(245,200,66,.07)' : C.surface2 }), display: 'flex', alignItems: 'center', gap: 8 }}>
                <div style={{ width: 22, color: C.creamDim, fontSize: 12, textAlign: 'center' }}>{i + 1}</div>
                <div style={{ fontSize: 22 }}>{p.emoji}</div>
                <div onClick={() => setFirstId(p.id)} style={{ flex: 1, color: C.cream, fontSize: 14, cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 6 }}>
                  {p.username}{p.id === user.id ? ' (you)' : ''}
                  {isFirst && <span style={{ color: C.gold, fontSize: 12, fontWeight: 700 }}>👉 first</span>}
                </div>
                <button onClick={() => move(i, -1)} disabled={i === 0}
                  style={{ width: 32, height: 32, borderRadius: 6, border: `1px solid ${C.border}`, background: 'transparent', color: i === 0 ? C.borderLight : C.cream, fontSize: 14, cursor: i === 0 ? 'default' : 'pointer' }}>↑</button>
                <button onClick={() => move(i, 1)} disabled={i === order.length - 1}
                  style={{ width: 32, height: 32, borderRadius: 6, border: `1px solid ${C.border}`, background: 'transparent', color: i === order.length - 1 ? C.borderLight : C.cream, fontSize: 14, cursor: i === order.length - 1 ? 'default' : 'pointer' }}>↓</button>
              </div>
            );
          })}
        </div>
      )}

      <div style={{ marginTop: 14, padding: '12px 16px', borderRadius: 8, background: C.surface, color: C.creamDim, fontSize: 13, textAlign: 'center' }}>
        {count} player{count !== 1 ? 's' : ''} selected {count < SEAT_LIMITS.min ? `— need at least ${SEAT_LIMITS.min}` : count > SEAT_LIMITS.max ? `— ${SEAT_LIMITS.max} max` : '— ready!'}
      </div>
      <button className="btn-red btn-press" onClick={handleStart} disabled={!ready}
        style={{ ...s.btn('red', { width: '100%', marginTop: 12, padding: 14, fontSize: 15, opacity: ready ? 1 : 0.5 }) }}>
        Shuffle Up & Deal 🐴
      </button>
    </div>
  );
}

function GameScreen({
  session, user, roundInputs, knockedBy, roundError, lastRoundDeltas,
  isSavingRound,
  showScoreSheet, endConfirm, editingRound, editInputs,
  onInput, onKnockedBy, onAddRound, onEndGame, onEndConfirm, onCancelEnd,
  onShowSheet, onHideSheet, onAbandon, onHome,
  onEditRound, onEditInput, onSaveEdit, onCancelEdit,
  neighCounts = {}, onNeigh,
  inherentKnock, onInherentKnock,
  onSetTurn,
}) {
  const [showCheatSheet, setShowCheatSheet] = useState(false);
  const [showTurnPicker, setShowTurnPicker] = useState(false);
  const turnIndex = typeof session.currentTurnIndex === 'number' ? session.currentTurnIndex : 0;
  const currentTurnPlayer = session.players[turnIndex];
  const sorted   = [...session.players].sort((a, b) => a.total - b.total);
  const leaderId = session.rounds.length > 0 ? sorted[0].id : null;

  // Wake Lock — keep screen on during active game
  useEffect(() => {
    let wl = null;
    if ('wakeLock' in navigator) {
      navigator.wakeLock.request('screen').then(lock => { wl = lock; }).catch(() => {});
    }
    return () => { if (wl) wl.release(); };
  }, []);

  return (
    <div className="screen" style={{ paddingTop: 24, paddingBottom: 110 }}>

      {/* Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 12 }}>
        <button onClick={onHome} style={s.btn('ghost', { paddingLeft: 0, fontSize: 12 })}>← Home</button>
        <div style={{ textAlign: 'center' }}>
          <KedroLogo height={28} />
          <div style={{ color: C.silverDim, fontSize: 10, letterSpacing: '.1em', textTransform: 'uppercase', marginTop: 2 }}>
            Round {session.rounds.length + 1}
          </div>
        </div>
        <button onClick={() => setShowCheatSheet(true)} style={s.btn('ghost', { fontSize: 11, padding: '6px 10px' })}>
          📖 Cheat
        </button>
      </div>

      {/* Current turn banner — tappable to change */}
      {currentTurnPlayer && (
        <div onClick={() => setShowTurnPicker(true)}
          style={{ textAlign: 'center', marginBottom: 14, padding: '8px 12px', borderRadius: 8, background: 'rgba(245,200,66,.08)', border: `1px solid rgba(245,200,66,.3)`, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6 }}>
          <span style={{ color: C.gold, fontSize: 11, letterSpacing: '.08em', textTransform: 'uppercase' }}>Your turn:</span>
          <span style={{ fontSize: 16 }}>{currentTurnPlayer.emoji}</span>
          <span style={{ color: C.cream, fontSize: 14, fontWeight: 600 }}>
            {currentTurnPlayer.username}{currentTurnPlayer.id === user?.id ? ' (you)' : ''}
          </span>
          <span style={{ color: C.creamDim, fontSize: 10, marginLeft: 4 }}>(tap to change)</span>
        </div>
      )}

      {/* Turn picker modal */}
      {showTurnPicker && (
        <div onClick={() => setShowTurnPicker(false)}
          style={{ position: 'fixed', inset: 0, zIndex: 60, background: 'rgba(0,0,0,.7)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
          <div onClick={e => e.stopPropagation()}
            style={{ background: C.panel, backdropFilter: 'blur(20px) saturate(140%)', WebkitBackdropFilter: 'blur(20px) saturate(140%)', borderRadius: 14, border: `1px solid ${C.borderLight}`, padding: '22px 20px 18px', maxWidth: 340, width: '100%', animation: 'slideUp .22s ease', boxShadow: '0 20px 60px rgba(0,0,0,.7)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 14 }}>
              <div className="red-line" style={{ margin: 0 }} />
              <div style={{ color: C.red, fontSize: 12, fontWeight: 700, letterSpacing: '.08em', textTransform: 'uppercase' }}>Whose Turn?</div>
            </div>
            {session.players.map((p, i) => {
              const isTurnRow = i === turnIndex;
              return (
                <button key={p.id} onClick={() => { onSetTurn(i); setShowTurnPicker(false); }}
                  style={{ width: '100%', display: 'flex', alignItems: 'center', gap: 10, padding: '12px 14px', marginBottom: 6, borderRadius: 8, cursor: 'pointer',
                    border: `1px solid ${isTurnRow ? C.gold : C.border}`,
                    background: isTurnRow ? 'rgba(245,200,66,.10)' : C.surface2,
                    color: C.cream, fontSize: 14, fontFamily: 'Barlow, sans-serif', textAlign: 'left' }}>
                  <span style={{ width: 20, color: C.creamDim, fontSize: 12, textAlign: 'center' }}>{i + 1}</span>
                  <span style={{ fontSize: 22 }}>{p.emoji}</span>
                  <span style={{ flex: 1 }}>{p.username}{p.id === user?.id ? ' (you)' : ''}</span>
                  {isTurnRow && <span style={{ color: C.gold, fontSize: 13 }}>👉</span>}
                </button>
              );
            })}
            <button onClick={() => setShowTurnPicker(false)} className="btn-press"
              style={s.btn('ghost', { width: '100%', marginTop: 8, fontSize: 12 })}>
              Cancel
            </button>
          </div>
        </div>
      )}

      {/* Scoreboard */}
      <div style={s.card({ padding: 0, overflow: 'hidden', marginBottom: 16 })}>
        <div style={{ background: C.surface3, padding: '8px 16px', borderBottom: `1px solid ${C.border}`, display: 'grid', gridTemplateColumns: '26px 1fr 56px 52px', gap: 6, alignItems: 'center' }}>
          <div />
          <div style={{ fontSize: 10, color: C.creamDim, textTransform: 'uppercase', letterSpacing: '.08em' }}>Player</div>
          <div style={{ fontSize: 10, color: C.creamDim, textTransform: 'uppercase', textAlign: 'center' }}>Neigh</div>
          <div style={{ fontSize: 10, color: C.creamDim, textTransform: 'uppercase', textAlign: 'right' }}>Total</div>
        </div>

        {sorted.map((p, i) => {
          const isLeader = p.id === leaderId;
          const isTurn   = currentTurnPlayer && p.id === currentTurnPlayer.id;
          const neighCount = neighCounts[p.id] || 0;
          return (
            <div key={p.id} style={{
              display: 'grid', gridTemplateColumns: '26px 1fr 56px 52px', gap: 6,
              alignItems: 'center', padding: '13px 16px', borderBottom: `1px solid ${C.border}`,
              background: isTurn ? 'rgba(245,200,66,.10)' : (isLeader ? 'rgba(245,200,66,.05)' : 'transparent'),
              borderLeft: isTurn ? `3px solid ${C.gold}` : '3px solid transparent',
              transition: 'background .4s',
            }}>
              <div style={{ fontSize: 15, textAlign: 'center' }}>
                {i < 3 ? RANK_BADGES[i] : <span style={{ color: C.creamDim, fontSize: 12 }}>{i + 1}</span>}
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <div style={{ fontSize: 24, position: 'relative', lineHeight: 1 }}>
                  {p.emoji}
                  {isLeader && session.rounds.length > 0 && (
                    <span style={{ position: 'absolute', top: -12, right: -10, fontSize: 12, animation: 'crownBob 1.8s ease infinite' }}>👑</span>
                  )}
                </div>
                <div>
                  <div style={{ color: C.cream, fontSize: 14, display: 'flex', alignItems: 'center', gap: 4 }}>
                    {p.username}{p.id === user?.id ? ' (you)' : ''}
                    {isTurn && <span style={{ fontSize: 13 }}>👉</span>}
                  </div>
                  {isLeader && session.rounds.length > 0 && (
                    <div style={{ fontSize: 10, color: C.gold, textTransform: 'uppercase', letterSpacing: '.06em' }}>Leading</div>
                  )}
                </div>
              </div>
              <div style={{ textAlign: 'center' }}>
                <button
                  onClick={() => onNeigh(p.id)}
                  style={{
                    background: neighCount > 0 ? 'rgba(212,43,43,.15)' : 'transparent',
                    border: `1px solid ${neighCount > 0 ? C.red : C.border}`,
                    borderRadius: 20, cursor: 'pointer',
                    padding: '3px 7px', display: 'inline-flex', alignItems: 'center', gap: 3,
                    transition: 'all .15s',
                  }}
                >
                  <span style={{ fontSize: 14, lineHeight: 1 }}>🐴</span>
                  {neighCount > 0 && (
                    <span style={{ color: C.red, fontSize: 12, fontWeight: 700, lineHeight: 1 }}>{neighCount}</span>
                  )}
                </button>
              </div>
              <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 30, color: isLeader ? C.gold : C.cream, textAlign: 'right', lineHeight: 1 }}>
                {p.total}
              </div>
            </div>
          );
        })}
      </div>

      {/* Round history table */}
      {session.rounds.length > 0 && !showScoreSheet && (
        <div style={s.card({ padding: '14px 16px', marginBottom: 14 })}>
          <div style={{ color: C.silverDim, fontSize: 11, textTransform: 'uppercase', letterSpacing: '.08em', marginBottom: 10 }}>Round History</div>
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
              <thead>
                <tr>
                  <th style={{ color: C.creamDim, textAlign: 'left', paddingBottom: 8, fontWeight: 500, fontSize: 11 }}>#</th>
                  {session.players.map(p => (
                    <th key={p.id} style={{ color: C.creamDim, textAlign: 'center', paddingBottom: 8, fontWeight: 500, fontSize: 11 }}>
                      <div>{p.emoji}</div>
                      <div style={{ fontSize: 10, color: C.silverDim, marginTop: 2 }}>{p.username}</div>
                    </th>
                  ))}
                  <th style={{ width: 36 }} />
                </tr>
              </thead>
              <tbody>
                {session.rounds.map((r, i) => (
                  editingRound === i ? (
                    <tr key={r.id} style={{ borderTop: `1px solid ${C.border}`, background: 'rgba(212,43,43,.05)' }}>
                      <td style={{ padding: '6px 4px', color: C.creamDim, fontSize: 12 }}>{i + 1}</td>
                      {session.players.map(p => (
                        <td key={p.id} style={{ padding: '4px 3px' }}>
                          <input type="number" value={editInputs[p.id] ?? ''}
                            onChange={e => onEditInput(p.id, e.target.value)}
                            style={s.input({ width: 50, padding: '4px 6px', fontSize: 13, textAlign: 'center' })}
                            inputMode="numeric" />
                        </td>
                      ))}
                      <td>
                        <div style={{ display: 'flex', gap: 3 }}>
                          <button onClick={() => onSaveEdit(i)} style={{ fontSize: 11, background: C.red, color: '#fff', border: 'none', borderRadius: 4, padding: '4px 7px', cursor: 'pointer' }}>✓</button>
                          <button onClick={onCancelEdit} style={{ fontSize: 11, background: C.surface3, color: C.creamDim, border: 'none', borderRadius: 4, padding: '4px 7px', cursor: 'pointer' }}>✕</button>
                        </div>
                      </td>
                    </tr>
                  ) : (
                    <tr key={r.id} style={{ borderTop: `1px solid ${C.border}` }}>
                      <td style={{ padding: '7px 0', color: C.creamDim }}>{i + 1}{r.knockedBy ? ' 🃏' : ''}</td>
                      {session.players.map(p => {
                        const sc = r.scores.find(s => s.playerId === p.id);
                        return (
                          <td key={p.id} style={{ textAlign: 'center', padding: '7px 4px', color: sc?.score < 0 ? C.green : sc?.score === 0 ? C.creamDim : C.cream }}>
                            {sc?.score ?? '—'}
                          </td>
                        );
                      })}
                      <td>
                        <button onClick={() => onEditRound(i)} style={{ fontSize: 10, background: 'transparent', color: C.creamDim, border: `1px solid ${C.border}`, borderRadius: 4, padding: '2px 6px', cursor: 'pointer' }}>edit</button>
                      </td>
                    </tr>
                  )
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* End game controls */}
      {!showScoreSheet && !endConfirm && (
        <button className="btn-outline btn-press" onClick={onEndConfirm} style={{ ...s.btn('outline', { width: '100%', marginBottom: 10 }) }}>
          End This Shit
        </button>
      )}
      {endConfirm && (
        <div style={s.card({ border: `1px solid ${C.red}`, background: 'rgba(212,43,43,.06)', marginBottom: 10 })}>
          <div style={{ color: C.cream, fontSize: 14, marginBottom: 14, textAlign: 'center' }}>
            Put them out of their misery?<br /><span style={{ color: C.creamDim, fontSize: 12 }}>Current scores will be final. No take-backs.</span>
          </div>
          <div style={{ display: 'flex', gap: 10, marginBottom: 8 }}>
            <button className="btn-press" onClick={onCancelEnd} style={s.btn('outline', { flex: 1 })}>Not Yet</button>
            <button className="btn-press" onClick={onEndGame} style={s.btn('danger', { flex: 1 })}>🐴 Kedro!</button>
          </div>
          <button className="btn-press" onClick={onAbandon} style={s.btn('ghost', { width: '100%', fontSize: 11 })}>Rage quit (doesn't count)</button>
        </div>
      )}

      {/* Enter Scores floating button */}
      {!showScoreSheet && !endConfirm && (
        <button className="btn-red btn-press" onClick={onShowSheet} style={{
          ...s.btn('red', {
            position: 'fixed', bottom: 28, left: '50%', transform: 'translateX(-50%)',
            padding: '14px 40px', fontSize: 15, borderRadius: 30,
            boxShadow: `0 4px 24px ${C.redGlow}, 0 0 0 1px rgba(212,43,43,.3)`,
            zIndex: 40, whiteSpace: 'nowrap',
          }),
        }}>
          + Enter Round Scores
        </button>
      )}

      {/* Score entry bottom sheet */}
      {showScoreSheet && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 50, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
          <div onClick={onHideSheet} style={{ flex: 1, background: 'rgba(0,0,0,.75)', backdropFilter: 'blur(4px)', WebkitBackdropFilter: 'blur(4px)' }} />
          <div style={{
            background: C.panel,
            backdropFilter: 'blur(20px) saturate(140%)',
            WebkitBackdropFilter: 'blur(20px) saturate(140%)',
            borderRadius: '18px 18px 0 0',
            border: `1px solid ${C.borderLight}`, borderBottom: 'none',
            padding: '20px 20px 40px', animation: 'slideUp .22s ease',
            maxHeight: '85vh', overflowY: 'auto',
            boxShadow: '0 -20px 60px rgba(0,0,0,.7)',
          }}>
            <div style={{ width: 36, height: 4, borderRadius: 2, background: C.borderLight, margin: '0 auto 20px' }} />
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
              <div className="red-line" style={{ margin: 0 }} />
              <div style={{ color: C.red, fontSize: 12, fontWeight: 700, letterSpacing: '.08em', textTransform: 'uppercase' }}>
                Round {session.rounds.length + 1} Scores
              </div>
            </div>
            <div style={{ color: C.creamDim, fontSize: 12, marginBottom: 16, fontStyle: 'italic' }}>
              Enter everyone's cards and who knocked... we will do the math.... ya bisssssh
            </div>
            {session.players.map(p => {
              const isKnocker = knockedBy === p.id;
              const inputDisabled = inherentKnock === p.id;
              return (
                <div key={p.id}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexWrap: 'wrap', marginBottom: isKnocker ? 8 : 14 }}>
                    <div style={{ fontSize: 22, width: 28, textAlign: 'center' }}>{p.emoji}</div>
                    <div style={{ flex: 1, color: C.cream, fontSize: 14 }}>{p.username}</div>
                    <button
                      disabled={inputDisabled}
                      onClick={() => {
                        const cur = roundInputs[p.id];
                        if (cur === undefined || cur === '' || cur === '0' || cur === 0) return;
                        const num = parseFloat(cur);
                        if (!isNaN(num)) onInput(p.id, String(-num));
                      }}
                      style={{
                        width: 36, height: 42, borderRadius: 6, cursor: inputDisabled ? 'default' : 'pointer',
                        border: `1px solid ${C.border}`, background: 'transparent',
                        color: C.creamDim, fontSize: 18, fontWeight: 700,
                        opacity: inputDisabled ? 0.3 : 1, flexShrink: 0,
                      }}>±</button>
                    <input type="number" min={-100} max={100} inputMode="numeric"
                      style={s.input({ width: 74, textAlign: 'center', padding: '10px 6px', fontSize: 18, opacity: inputDisabled ? 0.5 : 1 })}
                      placeholder="0" value={inputDisabled ? '0' : (roundInputs[p.id] ?? '')}
                      disabled={inputDisabled}
                      onChange={e => onInput(p.id, e.target.value)} />
                    <button onClick={() => onKnockedBy(p.id)} style={{
                      padding: '8px 10px', borderRadius: 6, cursor: 'pointer', whiteSpace: 'nowrap',
                      border: `1px solid ${isKnocker ? C.red : C.border}`,
                      background: isKnocker ? 'rgba(212,43,43,.2)' : 'transparent',
                      color: isKnocker ? C.red : C.creamDim,
                      fontSize: 11, fontFamily: 'Barlow, sans-serif', fontWeight: 600,
                      letterSpacing: '.04em', textTransform: 'uppercase', transition: 'all .15s',
                    }}>
                      {isKnocker ? '🃏 Knocked' : 'Knocked?'}
                    </button>
                    <button onClick={() => onInherentKnock(p.id)} style={{
                      padding: '8px 10px', borderRadius: 6, cursor: 'pointer', whiteSpace: 'nowrap',
                      border: `1px solid ${inherentKnock === p.id ? C.gold : C.border}`,
                      background: inherentKnock === p.id ? 'rgba(245,200,66,.2)' : 'transparent',
                      color: inherentKnock === p.id ? C.gold : C.creamDim,
                      fontSize: 11, fontFamily: 'Barlow, sans-serif', fontWeight: 600,
                      letterSpacing: '.04em', textTransform: 'uppercase', transition: 'all .15s',
                    }}>
                      {inherentKnock === p.id ? '⚡ IK' : 'IK?'}
                    </button>
                  </div>
                  {isKnocker && <KnockPreview session={session} roundInputs={roundInputs} knockedBy={knockedBy} inherent={inherentKnock === p.id} />}
                </div>
              );
            })}
            {roundError && <div style={{ color: C.red, fontSize: 13, marginBottom: 10 }}>{roundError}</div>}
            <button className="btn-red btn-press" onClick={onAddRound} disabled={isSavingRound}
              style={{ ...s.btn('red', { width: '100%', marginTop: 4, padding: 14, fontSize: 15, opacity: isSavingRound ? 0.5 : 1, cursor: isSavingRound ? 'wait' : 'pointer' }) }}>
              {isSavingRound ? 'Saving…' : 'Save Round →'}
            </button>
          </div>
        </div>
      )}

      {/* Cheat sheet modal */}
      {showCheatSheet && (
        <div onClick={() => setShowCheatSheet(false)}
          style={{ position: 'fixed', inset: 0, zIndex: 60, background: 'rgba(0,0,0,.7)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
          <div onClick={e => e.stopPropagation()}
            style={{ background: C.panel, backdropFilter: 'blur(20px) saturate(140%)', WebkitBackdropFilter: 'blur(20px) saturate(140%)', borderRadius: 14, border: `1px solid ${C.borderLight}`, padding: '22px 22px 18px', maxWidth: 360, width: '100%', maxHeight: '85vh', overflowY: 'auto', animation: 'slideUp .22s ease', boxShadow: '0 20px 60px rgba(0,0,0,.7)' }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 14 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <div className="red-line" style={{ margin: 0 }} />
                <div style={{ color: C.red, fontSize: 12, fontWeight: 700, letterSpacing: '.08em', textTransform: 'uppercase' }}>
                  Cheat Sheet
                </div>
              </div>
              <button onClick={() => setShowCheatSheet(false)} style={{ background: 'transparent', border: 'none', color: C.creamDim, fontSize: 20, cursor: 'pointer', lineHeight: 1 }}>✕</button>
            </div>

            <div style={{ color: C.silverDim, fontSize: 11, letterSpacing: '.08em', textTransform: 'uppercase', marginBottom: 8 }}>Card Values</div>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13, marginBottom: 18 }}>
              <tbody>
                {[
                  ['🟥 Red King', '−1'],
                  ['🃏 Joker', '0'],
                  ['Ace', '1'],
                  ['2 – 10', 'face value'],
                  ['Jack', '11'],
                  ['Queen', '12'],
                  ['⬛ Black King', '13'],
                ].map(([label, val]) => (
                  <tr key={label} style={{ borderBottom: `1px solid ${C.border}` }}>
                    <td style={{ padding: '7px 0', color: C.cream }}>{label}</td>
                    <td style={{ padding: '7px 0', color: C.gold, textAlign: 'right', fontWeight: 700 }}>{val}</td>
                  </tr>
                ))}
              </tbody>
            </table>

            <div style={{ color: C.silverDim, fontSize: 11, letterSpacing: '.08em', textTransform: 'uppercase', marginBottom: 8 }}>Card Powers</div>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
              <tbody>
                {[
                  ['7 and 8', 'Look at your own'],
                  ['8 and 9', "Look at someone else's"],
                  ['J and Q', 'Blind swap'],
                  ['K', 'Look and swap'],
                ].map(([card, power]) => (
                  <tr key={card} style={{ borderBottom: `1px solid ${C.border}` }}>
                    <td style={{ padding: '7px 0', color: C.red, fontWeight: 700, width: 70 }}>{card}</td>
                    <td style={{ padding: '7px 0', color: C.cream }}>{power}</td>
                  </tr>
                ))}
              </tbody>
            </table>

            <button onClick={() => setShowCheatSheet(false)} className="btn-press"
              style={s.btn('outline', { width: '100%', marginTop: 16, padding: 11, fontSize: 13 })}>
              Got it
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

const OUTCOME_LINES = {
  landed:    { text: 'Knock landed: −10', color: C.green },
  tied:      { text: 'Tied for lowest: knocker keeps their hand', color: C.gold },
  failed:    { text: 'Someone was lower: knocker takes +10', color: C.red },
  noPenalty: { text: 'Inherent knock beaten: no +10', color: C.gold },
};

/** What the knock comes to with the hands entered so far (the server scores it the same way). */
function KnockPreview({ session, roundInputs, knockedBy, inherent }) {
  const knocker = session.players.find(p => p.id === knockedBy);
  const complete = session.players.every(p => roundInputs[p.id] !== undefined && roundInputs[p.id] !== '' && !Number.isNaN(parseInt(roundInputs[p.id])));
  if (!knocker || !complete) return <div style={{ marginLeft: 38, marginBottom: 14, color: C.creamDim, fontSize: 11 }}>Enter every hand to see how the knock went.</div>;
  const hands = Object.fromEntries(session.players.map(p => [p.seatId, parseInt(roundInputs[p.id])]));
  const outcome = knockOutcome(hands, knocker.seatId, inherent);
  const line = OUTCOME_LINES[outcome];
  return line ? <div style={{ marginLeft: 38, marginBottom: 14, color: line.color, fontSize: 12, fontWeight: 600 }}>{line.text}</div> : null;
}

function PostGameScreen({ game, user, getStats, onRematch, onHome }) {
  const sorted = [...game.players].sort((a, b) => a.total - b.total);
  const winner = sorted[0];
  const winnerStats = getStats ? getStats(winner.id) : null;
  const margin = sorted.length > 1 ? sorted[sorted.length - 1].total - sorted[0].total : 0;
  const snowIntensity = (margin > 30 || (winnerStats && winnerStats.currentStreak >= 3)) ? 'blizzard' : 'normal';
  const taunt = useMemo(() => TRASH.winnerTaunt(winner.username), [winner.username]);
  const roast = useMemo(() => TRASH.loserRoast(), []);

  // Best single round score
  let bestScore = null, bestScorePlayer = null;
  game.rounds.forEach(r => {
    r.scores.forEach(s => {
      if (bestScore === null || s.score < bestScore) {
        bestScore = s.score;
        bestScorePlayer = game.players.find(p => p.id === s.playerId);
      }
    });
  });

  // Most effective knocker
  const knockStats = {};
  game.rounds.forEach(r => {
    if (r.knockedBy) {
      if (!knockStats[r.knockedBy]) knockStats[r.knockedBy] = { total: 0, wins: 0 };
      knockStats[r.knockedBy].total++;
      if (r.knockerWon) knockStats[r.knockedBy].wins++;
    }
  });
  const topKnocker = Object.entries(knockStats).sort((a, b) => (b[1].wins / b[1].total) - (a[1].wins / a[1].total))[0];
  const topKnockerPlayer = topKnocker ? game.players.find(p => p.id === topKnocker[0]) : null;
  const topKnockerRate   = topKnocker ? Math.round(topKnocker[1].wins / topKnocker[1].total * 100) : 0;

  return (
    <div className="screen" style={{ paddingTop: 32, paddingBottom: 60 }}>
      <Snow intensity={snowIntensity} />

      {/* Winner hero */}
      <div style={{ textAlign: 'center', marginBottom: 28 }}>
        <div style={{ fontSize: 88, animation: 'crownBob 2s ease infinite', lineHeight: 1.1 }}>{winner.emoji}</div>
        <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 42, color: C.gold, letterSpacing: '.04em', lineHeight: 1.1, marginTop: 8 }}>{taunt}</div>
        <div style={{ color: C.silver, fontSize: 14, letterSpacing: '.12em', textTransform: 'uppercase', marginTop: 6 }}>{winner.total} pts · {game.rounds.length} rounds</div>
        <div style={{ color: C.creamDim, fontSize: 13, marginTop: 8, fontStyle: 'italic' }}>{roast}</div>
        <div style={{ display: 'flex', justifyContent: 'center', marginTop: 14 }}>
          <KedroLogo height={46} />
        </div>
      </div>

      {/* Final standings */}
      <div style={s.card({ padding: 0, overflow: 'hidden', marginBottom: 14 })}>
        <div style={{ background: C.surface3, padding: '8px 16px', borderBottom: `1px solid ${C.border}` }}>
          <div style={{ fontSize: 10, color: C.creamDim, textTransform: 'uppercase', letterSpacing: '.1em' }}>Final Standings</div>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: '28px 1fr auto auto', gap: 6, padding: '6px 16px 4px', background: C.surface3, borderBottom: `1px solid ${C.border}` }}>
          <div />
          <div style={{ fontSize: 10, color: C.creamDim, textTransform: 'uppercase', letterSpacing: '.08em' }}>Player</div>
          <div style={{ fontSize: 10, color: C.creamDim, textTransform: 'uppercase', textAlign: 'center', minWidth: 40 }}>Neigh</div>
          <div style={{ fontSize: 10, color: C.creamDim, textTransform: 'uppercase', textAlign: 'right', minWidth: 44 }}>Total</div>
        </div>
        {sorted.map((p, i) => {
          const neighCount = game.neighCounts?.[p.id] || 0;
          return (
            <div key={p.id} style={{ display: 'grid', gridTemplateColumns: '28px 1fr auto auto', gap: 6, alignItems: 'center', padding: '12px 16px', borderBottom: `1px solid ${C.border}`, background: i === 0 ? 'rgba(245,200,66,.06)' : 'transparent' }}>
              <div style={{ fontSize: 18, textAlign: 'center' }}>
                {i < 3 ? RANK_BADGES[i] : <span style={{ color: C.creamDim }}>{i + 1}</span>}
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <span style={{ fontSize: 26 }}>{p.emoji}</span>
                <span style={{ color: C.cream, fontSize: 14 }}>{p.username}{p.id === user?.id ? ' (you)' : ''}</span>
              </div>
              <div style={{ textAlign: 'center', minWidth: 40 }}>
                {neighCount > 0 ? (
                  <span style={{ fontSize: 13 }}>🐴 <span style={{ color: C.red, fontWeight: 700 }}>{neighCount}</span></span>
                ) : (
                  <span style={{ color: C.border, fontSize: 13 }}>—</span>
                )}
              </div>
              <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 28, color: i === 0 ? C.gold : C.cream, textAlign: 'right', minWidth: 44, lineHeight: 1 }}>
                {p.total}
              </div>
            </div>
          );
        })}
      </div>

      {/* Game highlights */}
      {(bestScorePlayer || topKnockerPlayer) && (
        <div style={s.card({ marginBottom: 14 })}>
          <div style={{ color: C.silverDim, fontSize: 11, textTransform: 'uppercase', letterSpacing: '.1em', marginBottom: 12 }}>Game Highlights</div>
          {bestScorePlayer && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 0', borderBottom: topKnockerPlayer ? `1px solid ${C.border}` : 'none' }}>
              <div style={{ fontSize: 22 }}>⚡</div>
              <div>
                <div style={{ color: C.cream, fontSize: 13 }}>Best Single Round</div>
                <div style={{ color: C.creamDim, fontSize: 12 }}>{bestScorePlayer.emoji} {bestScorePlayer.username} — {bestScore} pts</div>
              </div>
            </div>
          )}
          {topKnockerPlayer && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '8px 0' }}>
              <div style={{ fontSize: 22 }}>🃏</div>
              <div>
                <div style={{ color: C.cream, fontSize: 13 }}>Most Effective Knocker</div>
                <div style={{ color: C.creamDim, fontSize: 12 }}>{topKnockerPlayer.emoji} {topKnockerPlayer.username} — {topKnockerRate}% Kedro win rate</div>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Round breakdown */}
      {game.rounds.length > 0 && (
        <div style={s.card({ marginBottom: 20 })}>
          <div style={{ color: C.silverDim, fontSize: 11, textTransform: 'uppercase', letterSpacing: '.08em', marginBottom: 10 }}>Round Breakdown</div>
          <div style={{ overflowX: 'auto' }}>
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
              <thead>
                <tr>
                  <th style={{ color: C.creamDim, textAlign: 'left', paddingBottom: 8, fontWeight: 500, fontSize: 11 }}>#</th>
                  {game.players.map(p => (
                    <th key={p.id} style={{ color: C.creamDim, textAlign: 'center', paddingBottom: 8, fontWeight: 500, fontSize: 11 }}>{p.emoji}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {game.rounds.map((r, i) => (
                  <tr key={r.id} style={{ borderTop: `1px solid ${C.border}` }}>
                    <td style={{ padding: '7px 0', color: C.creamDim }}>{i + 1}{r.knockedBy ? ' 🃏' : ''}</td>
                    {game.players.map(p => {
                      const sc = r.scores.find(s => s.playerId === p.id);
                      return (
                        <td key={p.id} style={{ textAlign: 'center', padding: '7px 4px', color: sc?.score < 0 ? C.green : sc?.score === 0 ? C.creamDim : C.cream }}>
                          {sc?.score ?? '—'}
                        </td>
                      );
                    })}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      <button className="btn-red btn-press" onClick={onRematch} style={{ ...s.btn('red', { width: '100%', padding: 14, fontSize: 15, marginBottom: 10 }) }}>
        🔁 Rematch — Same Players
      </button>
      <button className="btn-press" onClick={onHome} style={{ ...s.btn('outline', { width: '100%', padding: 12 }) }}>
        Home
      </button>
    </div>
  );
}

function HistoryScreen({ games, user, selected, onSelect, onBack }) {
  const displayGames = games.filter(g => g.status === 'complete' || g.status === 'abandoned');
  if (selected) {
    const w = selected.players.find(p => p.id === selected.winnerId);
    const winner = displayPlayer(w);
    return (
      <div className="screen" style={{ paddingTop: 28, paddingBottom: 40 }}>
        <BackBtn onBack={() => onSelect(null)} label="Back to history" />
        <div style={{ margin: '14px 0 6px' }}><KedroLogo height={32} /></div>
        <div style={{ ...s.h1, fontSize: 32 }}>Game Detail</div>
        <div className="red-line" />
        <div style={{ color: C.creamDim, fontSize: 12, marginBottom: 18 }}>
          {selected.status === 'abandoned' ? '⚠️ Abandoned · ' : ''}
          {new Date(selected.endedAt).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric', year: 'numeric' })}
        </div>

        {winner && selected.status === 'complete' && (
          <div style={{ ...s.card({ padding: 20, textAlign: 'center', border: `1px solid ${C.red}`, background: 'rgba(212,43,43,.06)', marginBottom: 16 }) }}>
            <div style={{ fontSize: 48 }}>{winner.emoji}</div>
            <div style={{ color: C.red, fontSize: 11, textTransform: 'uppercase', letterSpacing: '.1em', marginTop: 8 }}>Winner</div>
            <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 28, color: C.cream }}>{winner.username}</div>
            <div style={{ color: C.creamDim, fontSize: 13, marginTop: 4 }}>{winner.total} pts</div>
          </div>
        )}

        <div style={s.card({ marginBottom: 14 })}>
          <div style={{ color: C.silverDim, fontSize: 11, textTransform: 'uppercase', letterSpacing: '.08em', marginBottom: 10 }}>Final Standings</div>
          {[...selected.players].sort((a, b) => a.total - b.total).map((p, i) => {
            const dp = displayPlayer(p);
            return (
              <div key={p.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 0', borderBottom: `1px solid ${C.border}` }}>
                <div style={{ width: 24, textAlign: 'center' }}>{i < 3 ? RANK_BADGES[i] : <span style={{ color: C.creamDim }}>{i + 1}</span>}</div>
                <div style={{ fontSize: 22 }}>{dp.emoji}</div>
                <div style={{ flex: 1, color: C.cream }}>{dp.username}</div>
                <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 24, color: i === 0 ? C.gold : C.cream }}>{p.total}</div>
              </div>
            );
          })}
        </div>

        {selected.rounds && selected.rounds.length > 0 && (
          <div style={s.card({ marginBottom: 16 })}>
            <div style={{ color: C.silverDim, fontSize: 11, textTransform: 'uppercase', letterSpacing: '.08em', marginBottom: 10 }}>Round by Round</div>
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
                <thead>
                  <tr>
                    <th style={{ color: C.creamDim, textAlign: 'left', paddingBottom: 8, fontWeight: 500, fontSize: 11 }}>#</th>
                    {selected.players.map(p => (
                      <th key={p.id} style={{ color: C.creamDim, textAlign: 'center', paddingBottom: 8, fontWeight: 500, fontSize: 11 }}>{displayPlayer(p).emoji}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {selected.rounds.map((r, i) => {
                    const running = {};
                    selected.players.forEach(p => { running[p.id] = 0; });
                    selected.rounds.slice(0, i + 1).forEach(rd =>
                      rd.scores.forEach(s => { running[s.playerId] = (running[s.playerId] || 0) + s.score; })
                    );
                    return (
                      <tr key={r.id} style={{ borderTop: `1px solid ${C.border}` }}>
                        <td style={{ padding: '7px 0', color: C.creamDim }}>{i + 1}{r.knockedBy ? ' 🃏' : ''}</td>
                        {selected.players.map(p => {
                          const sc = r.scores.find(s => s.playerId === p.id);
                          return (
                            <td key={p.id} style={{ textAlign: 'center', padding: '7px 4px' }}>
                              <div style={{ color: sc?.score < 0 ? C.green : sc?.score === 0 ? C.creamDim : C.cream, fontSize: 13 }}>{sc?.score ?? '—'}</div>
                              <div style={{ color: C.creamDim, fontSize: 10 }}>({running[p.id]})</div>
                            </td>
                          );
                        })}
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
        )}

      </div>
    );
  }

  return (
    <div className="screen" style={{ paddingTop: 28, paddingBottom: 40 }}>
      <BackBtn onBack={onBack} />
      <div style={{ margin: '14px 0 6px' }}><KedroLogo height={32} /></div>
      <div style={{ ...s.h1, fontSize: 32 }}>History</div>
      <div className="red-line" style={{ marginBottom: 18 }} />
      {displayGames.length === 0 ? (
        <div style={{ ...s.card({ textAlign: 'center', padding: 40 }), color: C.creamDim }}>{TRASH.noGames()}</div>
      ) : displayGames.map(g => {
        const w = g.players.find(p => p.id === g.winnerId);
        const winner = displayPlayer(w);
        const isUserWin = g.winnerId === user?.id;
        const date      = new Date(g.endedAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
        const abandoned = g.status === 'abandoned';
        return (
          <div key={g.id} onClick={() => onSelect(g)} className="player-tile"
            style={{ ...s.card({ padding: '14px 16px', marginBottom: 8, cursor: 'pointer', opacity: abandoned ? 0.6 : 1 }), display: 'flex', alignItems: 'center', gap: 14 }}>
            <div style={{ fontSize: 28 }}>{abandoned ? '⚠️' : winner?.emoji}</div>
            <div style={{ flex: 1 }}>
              <div style={{ color: C.cream, fontSize: 14 }}>{g.players.map(p => displayPlayer(p).username).join(' · ')}</div>
              <div style={{ color: C.creamDim, fontSize: 11, marginTop: 3 }}>{date} · {g.rounds.length}R{abandoned ? ' · Abandoned' : ''}</div>
            </div>
            <div style={{ textAlign: 'right' }}>
              {!abandoned && (isUserWin
                ? <div style={{ color: C.green, fontSize: 12, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.04em' }}>You won!</div>
                : <div style={{ color: C.creamDim, fontSize: 12 }}>{winner?.username}</div>
              )}
              <div style={{ color: C.red, fontSize: 11, marginTop: 2 }}>View →</div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

function ProfileScreen({ user, stats, games, onBack, onLogout, editingProfile, onStartEdit, onCancelEdit, editUsername, onEditUsername, editEmoji, onEditEmoji, onSaveEdit, profileError, claimMessage, onClaim }) {
  const [claimCode, setClaimCode] = useState('');
  const claimMessageRef = useRef(null);
  // A claim link lands here with the outcome at the bottom of the page: bring it into view.
  useEffect(() => { if (claimMessage) claimMessageRef.current?.scrollIntoView({ behavior: 'smooth', block: 'center' }); }, [claimMessage]);
  const userGames = games.filter(g => g.status === 'complete' && g.players.find(p => p.id === user.id));
  return (
    <div className="screen" style={{ paddingTop: 28, paddingBottom: 60 }}>
      <BackBtn onBack={onBack} />

      {editingProfile ? (
        <div style={{ margin: '20px 0 28px' }}>
          <div style={{ ...s.h2, fontSize: 24, marginBottom: 16, textAlign: 'center' }}>Edit Profile</div>
          <div style={{ marginBottom: 16 }}>
            <label style={s.label}>Avatar</label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
              {EMOJIS.map(e => (
                <button key={e} className="emoji-btn" onClick={() => onEditEmoji(e)}
                  style={{ fontSize: 22, background: editEmoji === e ? C.surface3 : 'transparent', border: `2px solid ${editEmoji === e ? C.red : C.border}`, borderRadius: 8, padding: '5px 7px', cursor: 'pointer', transition: 'all .15s' }}>
                  {e}
                </button>
              ))}
            </div>
          </div>
          <div style={{ marginBottom: 16 }}>
            <label style={s.label}>Name</label>
            <input style={s.input()} value={editUsername} onChange={e => onEditUsername(e.target.value)} autoFocus />
          </div>
          {profileError && <div style={{ color: C.red, fontSize: 13, marginBottom: 10 }}>{profileError}</div>}
          <div style={{ display: 'flex', gap: 10 }}>
            <button className="btn-press" onClick={onCancelEdit} style={s.btn('outline', { flex: 1 })}>Cancel</button>
            <button className="btn-red btn-press" onClick={onSaveEdit} style={s.btn('red', { flex: 1 })}>Save</button>
          </div>
        </div>
      ) : (
        <div style={{ textAlign: 'center', margin: '20px 0 28px' }}>
          <div style={{ fontSize: 64 }}>{user.emoji}</div>
          <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 36, color: C.cream, marginTop: 8 }}>{user.username}</div>
          <div className="red-line" style={{ margin: '8px auto 0' }} />
          <div style={{ color: C.creamDim, fontSize: 12, marginTop: 8, textTransform: 'uppercase', letterSpacing: '.08em' }}>
            @{user.handle}{user.createdAt ? ` · Since ${new Date(user.createdAt).toLocaleDateString('en-US', { month: 'long', year: 'numeric' })}` : ''}
          </div>
          <button className="btn-press" onClick={onStartEdit} style={s.btn('ghost', { fontSize: 12, marginTop: 8 })}>✏️ Edit Profile</button>
        </div>
      )}

      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, marginBottom: 10 }}>
        <StatBox label="Games"      value={stats.played} />
        <StatBox label="Wins"       value={stats.wins}       accent={C.green} />
        <StatBox label="Win Rate"   value={stats.played ? `${stats.winRate}%` : '—'} accent={C.blue} />
        <StatBox label="Avg Score"  value={stats.avgScore} />
        <StatBox label="Best Game"  value={stats.best}        accent={C.gold} />
        <StatBox label="Worst Game" value={stats.worst}       accent={C.red} />
        <StatBox label="Avg / Round" value={stats.avgRound}  accent={C.silver} />
        <StatBox label="🔥 Streak"  value={stats.currentStreak || 0} accent={C.green} />
      </div>

      {stats.totalKnocks > 0 && (
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, marginBottom: 10 }}>
          <StatBox label="Knock Rate"   value={`${stats.knockRate}%`} accent={C.blue} />
          <StatBox label="Kedro Win %"  value={typeof stats.kedroWinPct === 'number' ? `${stats.kedroWinPct}%` : '—'} accent={C.gold} />
        </div>
      )}

      {stats.nemesis && (
        <div style={{ ...s.card({ padding: '14px 16px', marginBottom: 10, display: 'flex', alignItems: 'center', gap: 12 }) }}>
          <div style={{ fontSize: 28 }}>😈</div>
          <div>
            <div style={{ color: C.silverDim, fontSize: 10, textTransform: 'uppercase', letterSpacing: '.08em' }}>Nemesis</div>
            <div style={{ color: C.cream, fontSize: 15 }}>{stats.nemesis.emoji} {stats.nemesis.username}</div>
            <div style={{ color: C.creamDim, fontSize: 12 }}>Has your number... and your dignity</div>
          </div>
        </div>
      )}

      {stats.longestStreak > 0 && (
        <div style={{ ...s.card({ padding: '12px 16px', marginBottom: 14, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }) }}>
          <div style={{ color: C.creamDim, fontSize: 13 }}>Longest win streak</div>
          <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 28, color: C.gold }}>{stats.longestStreak}</div>
        </div>
      )}

      {(() => {
        const h2h = {};
        userGames.forEach(g => {
          g.players.filter(p => p.id !== user.id).forEach(opp => {
            if (!h2h[opp.id]) h2h[opp.id] = { username: opp.username, emoji: opp.emoji, games: 0, userWins: 0, oppWins: 0 };
            h2h[opp.id].games++;
            if (g.winnerId === user.id) h2h[opp.id].userWins++;
            else if (g.winnerId === opp.id) h2h[opp.id].oppWins++;
          });
        });
        const h2hList = Object.values(h2h).sort((a, b) => b.games - a.games);
        if (h2hList.length === 0) return null;
        return (
          <div style={s.card({ marginBottom: 14 })}>
            <div style={{ color: C.silverDim, fontSize: 11, textTransform: 'uppercase', letterSpacing: '.08em', marginBottom: 12 }}>Head-to-Head</div>
            {h2hList.map(opp => {
              const winRate = opp.games ? Math.round(opp.userWins / opp.games * 100) : 0;
              return (
                <div key={opp.username} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '9px 0', borderBottom: `1px solid ${C.border}` }}>
                  <div style={{ fontSize: 22 }}>{opp.emoji}</div>
                  <div style={{ flex: 1 }}>
                    <div style={{ color: C.cream, fontSize: 13 }}>{opp.username}</div>
                    <div style={{ color: C.creamDim, fontSize: 11, marginTop: 2 }}>{opp.games} game{opp.games !== 1 ? 's' : ''}</div>
                  </div>
                  <div style={{ textAlign: 'right' }}>
                    <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 20, color: opp.userWins > opp.oppWins ? C.green : opp.userWins < opp.oppWins ? C.red : C.silver, lineHeight: 1 }}>
                      {opp.userWins}–{opp.oppWins}
                    </div>
                    <div style={{ fontSize: 10, color: C.creamDim, marginTop: 2 }}>{winRate}% win rate</div>
                  </div>
                </div>
              );
            })}
          </div>
        );
      })()}

      {userGames.length > 0 && (
        <div style={s.card({ marginBottom: 20 })}>
          <div style={{ color: C.silverDim, fontSize: 11, textTransform: 'uppercase', letterSpacing: '.08em', marginBottom: 12 }}>Recent Games</div>
          {userGames.slice(0, 6).map(g => {
            const myScore = g.players.find(p => p.id === user.id)?.total;
            const won     = g.winnerId === user.id;
            const date    = new Date(g.endedAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
            return (
              <div key={g.id} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '9px 0', borderBottom: `1px solid ${C.border}` }}>
                <div>
                  <div style={{ color: C.cream, fontSize: 13 }}>{g.players.filter(p => p.id !== user.id).map(p => p.username).join(', ') || 'Solo'}</div>
                  <div style={{ color: C.creamDim, fontSize: 11 }}>{date} · {g.rounds.length}R</div>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div style={{ color: won ? C.green : C.red, fontSize: 12, fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.04em' }}>{won ? '🏆 Win' : 'Loss'}</div>
                  <div style={{ color: C.creamDim, fontSize: 12 }}>{myScore} pts</div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      <div style={s.card({ marginBottom: 20 })}>
        <div style={{ color: C.silverDim, fontSize: 11, textTransform: 'uppercase', letterSpacing: '.08em', marginBottom: 6 }}>Got a claim code?</div>
        <div style={{ color: C.creamDim, fontSize: 12, marginBottom: 10 }}>Enter the code you were sent to add your old web games to this account.</div>
        <div style={{ display: 'flex', gap: 8 }}>
          <input style={s.input({ flex: 1 })} placeholder="kedro-legacy-…" value={claimCode} onChange={e => setClaimCode(e.target.value)} autoCapitalize="none" autoCorrect="off" />
          <button className="btn-red btn-press" disabled={!claimCode.trim()} onClick={() => onClaim(claimCode)} style={s.btn('red', { opacity: claimCode.trim() ? 1 : 0.5 })}>Claim</button>
        </div>
        {claimMessage && <div ref={claimMessageRef} style={{ color: C.cream, fontSize: 13, marginTop: 10 }}>{claimMessage}</div>}
      </div>

      <button className="btn-press" onClick={onLogout} style={{ ...s.btn('ghost', { width: '100%' }) }}>Sign Out</button>
    </div>
  );
}

// ─── Dashboard / Leaderboard ──────────────────────────────────────────────────

function ScoreChart({ allGames, allPlayers }) {
  // Chronological, completed, and at least 3 rounds — matches leaderboard table filter.
  const completed = [...allGames].filter(g => g.status === 'complete' && (g.rounds?.length || 0) >= 3).reverse();
  if (completed.length === 0) return <div style={{ color: C.creamDim, textAlign: 'center', padding: 30 }}>No qualifying games yet (need 3+ rounds).</div>;

  // 12 maximally distinct hues, ordered so adjacent colors in rotation contrast strongly.
  const COLORS = [
    '#ff4d4d', // vivid red
    '#4ecdc4', // turquoise
    '#ffd93d', // bright yellow
    '#c566ff', // purple
    '#6bcb77', // green
    '#ff9f1c', // orange
    '#45b7ff', // sky blue
    '#ff6bcb', // magenta
    '#a8e10c', // lime
    '#ff7f50', // coral
    '#00c9a7', // teal
    '#b388ff', // lavender
  ];
  const playerIds = allPlayers.map(p => p.id);

  // For each player: walk their participated games chronologically, track cumulative win %.
  // Colors are assigned by the player's index in allPlayers (stable across renders),
  // then the series is sorted by current win % so legend/lines read top→bottom.
  const series = playerIds.map((pid, idx) => {
    const points = [];
    let wins = 0, played = 0;
    completed.forEach((g, gi) => {
      if (!g.players.find(p => p.id === pid)) return;
      played++;
      if (g.winnerId === pid) wins++;
      points.push({ x: gi, y: Math.round((wins / played) * 100) });
    });
    return { playerId: pid, color: COLORS[idx % COLORS.length], points, player: allPlayers.find(p => p.id === pid) };
  })
    .filter(s => s.points.length >= 2)
    .sort((a, b) => b.points[b.points.length - 1].y - a.points[a.points.length - 1].y);

  if (series.length === 0) return <div style={{ color: C.creamDim, textAlign: 'center', padding: 30 }}>Need at least 2 qualifying games per player to chart.</div>;

  const W = 340, H = 200, PAD = { top: 10, right: 10, bottom: 25, left: 35 };
  const chartW = W - PAD.left - PAD.right;
  const chartH = H - PAD.top - PAD.bottom;
  const maxX = completed.length - 1 || 1;
  const scaleX = (x) => PAD.left + (x / maxX) * chartW;
  const scaleY = (y) => PAD.top + chartH - (y / 100) * chartH;

  return (
    <div>
      <div style={{ color: C.creamDim, fontSize: 11, textAlign: 'center', marginBottom: 8 }}>
        Cumulative win % over time (your games with 3+ rounds)
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: 'auto' }}>
        {[0, 25, 50, 75, 100].map(pct => {
          const y = scaleY(pct);
          return (<g key={pct}>
            <line x1={PAD.left} y1={y} x2={W - PAD.right} y2={y} stroke={C.border} strokeWidth="0.5" />
            <text x={PAD.left - 4} y={y + 3} fill={C.creamDim} fontSize="8" textAnchor="end">{pct}%</text>
          </g>);
        })}
        {series.map(sr => (
          <polyline key={sr.playerId} fill="none" stroke={sr.color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"
            points={sr.points.map(p => `${scaleX(p.x)},${scaleY(p.y)}`).join(' ')} />
        ))}
        {series.map(sr => {
          const last = sr.points[sr.points.length - 1];
          return <circle key={sr.playerId} cx={scaleX(last.x)} cy={scaleY(last.y)} r="3" fill={sr.color} />;
        })}
        <text x={PAD.left} y={H - 4} fill={C.creamDim} fontSize="7">Game 1</text>
        <text x={W - PAD.right} y={H - 4} fill={C.creamDim} fontSize="7" textAnchor="end">Game {completed.length}</text>
      </svg>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 10, marginTop: 10, justifyContent: 'center' }}>
        {series.map(sr => {
          const last = sr.points[sr.points.length - 1];
          return (
            <div key={sr.playerId} style={{ display: 'flex', alignItems: 'center', gap: 5 }}>
              <div style={{ width: 10, height: 3, background: sr.color, borderRadius: 2 }} />
              <span style={{ fontSize: 11, color: C.creamDim }}>{sr.player?.emoji} {sr.player?.username} <span style={{ color: sr.color, fontWeight: 700 }}>{last.y}%</span></span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// The leaderboard is GET /v1/leaderboard: the same board, rating, sorts and minimums as the Kedro
// iPhone app, over every finished game from either app.
const LEADERBOARD_SORT_OPTIONS = [
  { key: 'rating',       label: 'Rating' },
  { key: 'wins',         label: 'Wins' },
  { key: 'winRate',      label: 'Win %' },
  { key: 'avgScore',     label: 'Avg' },
  { key: 'knockSuccess', label: 'Knock %' },
];

function needsLine(needs) {
  if (needs?.games) return `needs ${needs.games} more game${needs.games === 1 ? '' : 's'} for this one`;
  if (needs?.knocks) return `needs ${needs.knocks} more knock${needs.knocks === 1 ? '' : 's'} for this one`;
  return '';
}

function DashboardScreen({ allGames, user, viewMode, onToggleView, onBack }) {
  const [sortKey, setSortKey] = useState('rating');
  const [showRatingInfo, setShowRatingInfo] = useState(false);
  const [board, setBoard] = useState(null);
  const [boardError, setBoardError] = useState('');

  useEffect(() => {
    let cancelled = false;
    api.leaderboard(sortKey)
      .then(response => { if (!cancelled) { setBoard(response); setBoardError(''); } })
      .catch(error => { if (!cancelled) setBoardError(error.message || 'Could not load the leaderboard'); });
    return () => { cancelled = true; };
  }, [sortKey]);

  const { ranked, notYetRanked } = useMemo(() => {
    if (!board) return { ranked: [], notYetRanked: [] };
    const rankCounts = {};
    board.rows.forEach(row => { if (row.rank !== null) rankCounts[row.rank] = (rankCounts[row.rank] || 0) + 1; });
    const ranked = board.rows.map(row => ({
      ...webPlayer(row.player),
      isShared: row.rank !== null && rankCounts[row.rank] > 1,
      entry: { rank: row.rank, rating: row.rating, needs: row.needs, stats: { wins: row.wins, winRate: row.winRate, avgScore: row.avgScore, knockSuccess: row.knockSuccess, gamesPlayed: row.gamesPlayed } },
    }));
    const notYetRanked = board.notYetRanked.map(row => ({ ...webPlayer(row.player), entry: { gamesPlayed: row.gamesPlayed } }));
    return { ranked, notYetRanked };
  }, [board]);

  // The chart covers the games this player was in.
  const chartPlayers = useMemo(() => {
    const byId = new Map();
    allGames.forEach(g => g.players.forEach(p => { if (!byId.has(p.id)) byId.set(p.id, p); }));
    return [...byId.values()];
  }, [allGames]);

  const th = (extra = {}) => ({ color: C.creamDim, padding: '8px 5px', fontWeight: 600, fontSize: 10, textTransform: 'uppercase', letterSpacing: '.04em', textAlign: 'center', whiteSpace: 'nowrap', ...extra });
  const sortTh = (key, label, extra) => (
    <th onClick={() => setSortKey(key)} style={th({ color: sortKey === key ? C.cream : C.creamDim, cursor: 'pointer', ...extra })}>
      {label}{sortKey === key ? <span style={{ color: C.red, marginLeft: 3 }}>↓</span> : null}
    </th>
  );
  const rankCell = (p) => {
    const { rank } = p.entry;
    if (rank === null) return <span style={{ color: C.creamFaint }}>–</span>;
    if (rank <= 3) return RANK_BADGES[rank - 1];
    return <span style={{ color: C.creamDim }}>{rank}{p.isShared ? '=' : ''}</span>;
  };
  const percent = (x) => x === null || x === undefined ? '—' : `${Math.round(x * 100)}%`;
  const decimal = (x) => (Math.round(x * 10) / 10).toFixed(1);

  return (
    <div className="screen" style={{ paddingTop: 28, paddingBottom: 40 }}>
      <BackBtn onBack={onBack} />
      <div style={{ margin: '14px 0 6px' }}><KedroLogo height={32} /></div>
      <div style={{ ...s.h1, fontSize: 32 }}>Leaderboard</div>
      <div className="red-line" />
      <div style={{ color: C.creamDim, fontSize: 13, marginBottom: 16 }}>Who actually runs this table?</div>

      {/* View toggle */}
      <div style={{ display: 'flex', background: C.surface, borderRadius: 6, padding: 2, marginBottom: 16 }}>
        {['table', 'chart'].map(mode => (
          <button key={mode} onClick={() => onToggleView(mode)} style={{
            flex: 1, padding: '8px 0', borderRadius: 5, border: 'none', cursor: 'pointer',
            background: viewMode === mode ? C.red : 'transparent',
            color: viewMode === mode ? '#fff' : C.creamDim,
            fontFamily: 'Barlow, sans-serif', fontSize: 13, fontWeight: 600,
            textTransform: 'uppercase', letterSpacing: '.06em', transition: 'all .15s',
          }}>
            {mode === 'table' ? 'Table' : 'Chart'}
          </button>
        ))}
      </div>

      {viewMode === 'table' ? (
        !board ? (
          <div style={{ ...s.card({ textAlign: 'center', padding: 40 }), color: boardError ? C.red : C.creamDim }}>{boardError || 'Loading…'}</div>
        ) : ranked.length === 0 && notYetRanked.length === 0 ? (
          <div style={{ ...s.card({ textAlign: 'center', padding: 40 }), color: C.creamDim }}>No stats yet. Play some games first.</div>
        ) : (
          <>
            {/* Sort */}
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 12 }}>
              {LEADERBOARD_SORT_OPTIONS.map(option => (
                <button key={option.key} onClick={() => setSortKey(option.key)} className="btn-press" style={{
                  padding: '6px 11px', borderRadius: 999, cursor: 'pointer', fontSize: 12, fontWeight: 600,
                  fontFamily: 'Barlow, sans-serif', letterSpacing: '.03em',
                  border: `1px solid ${sortKey === option.key ? C.red : C.border}`,
                  background: sortKey === option.key ? 'rgba(230,57,70,.14)' : 'transparent',
                  color: sortKey === option.key ? C.cream : C.creamDim,
                }}>
                  {option.label}
                </button>
              ))}
              <button onClick={() => setShowRatingInfo(true)} style={{ marginLeft: 'auto', background: 'transparent', border: 'none', color: C.creamDim, fontSize: 12, cursor: 'pointer', textDecoration: 'underline' }}>
                How ranking works
              </button>
            </div>

            {ranked.length > 0 && (
              <div style={{ overflowX: 'auto', marginBottom: 16 }}>
                <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 12 }}>
                  <thead>
                    <tr style={{ borderBottom: `1px solid ${C.border}` }}>
                      <th style={th()}>#</th>
                      <th style={th({ textAlign: 'left' })}>Player</th>
                      {sortTh('rating', 'Rating')}
                      {sortTh('wins', 'W')}
                      {sortTh('winRate', 'W%')}
                      {sortTh('avgScore', 'Avg')}
                      {sortTh('knockSuccess', 'K%')}
                      <th style={th()}>GP</th>
                    </tr>
                  </thead>
                  <tbody>
                    {ranked.map(p => {
                      const { entry } = p;
                      const below = entry.rank === null;
                      const dim = (key) => below && sortKey === key ? C.creamFaint : undefined;
                      return (
                        <tr key={p.id} style={{ borderBottom: `1px solid ${C.border}`, background: p.id === user.id ? 'rgba(230,57,70,.06)' : 'transparent' }}>
                          <td style={{ padding: '10px 5px', textAlign: 'center' }}>{rankCell(p)}</td>
                          <td style={{ padding: '10px 5px', whiteSpace: 'nowrap' }}>
                            <span style={{ fontSize: 16, marginRight: 6 }}>{p.emoji}</span>
                            <span style={{ color: C.cream, fontSize: 13 }}>{p.username}{p.id === user.id ? ' (you)' : ''}</span>
                            {below && <div style={{ color: C.creamFaint, fontSize: 10, marginTop: 2 }}>{needsLine(entry.needs)}</div>}
                          </td>
                          <td style={{ textAlign: 'center', padding: '10px 4px', fontFamily: "'Bebas Neue', sans-serif", fontSize: 18, color: C.gold }}>{entry.rating.toLocaleString()}</td>
                          <td style={{ textAlign: 'center', padding: '10px 4px', fontFamily: "'Bebas Neue', sans-serif", fontSize: 18, color: C.green }}>{entry.stats.wins}</td>
                          <td style={{ textAlign: 'center', padding: '10px 4px', fontFamily: "'Bebas Neue', sans-serif", fontSize: 18, color: dim('winRate') ?? C.blue }}>{percent(entry.stats.winRate)}</td>
                          <td style={{ textAlign: 'center', padding: '10px 4px', color: C.cream }}>{decimal(entry.stats.avgScore)}</td>
                          <td style={{ textAlign: 'center', padding: '10px 4px', color: dim('knockSuccess') ?? C.cream }}>{percent(entry.stats.knockSuccess)}</td>
                          <td style={{ textAlign: 'center', padding: '10px 4px', color: C.creamDim }}>{entry.stats.gamesPlayed}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}

            {notYetRanked.length > 0 && (
              <div style={s.card({ padding: '14px 16px', marginBottom: 16 })}>
                <div style={{ color: C.cream, fontWeight: 600, fontSize: 14 }}>Not yet ranked</div>
                <div style={{ color: C.creamDim, fontSize: 12, margin: '2px 0 10px' }}>
                  Everyone gets a rank and a rating after {LEADERBOARD_MINIMUMS.rankGames} games.
                </div>
                {notYetRanked.map(p => (
                  <div key={p.id} style={{ display: 'flex', alignItems: 'center', padding: '6px 0', borderTop: `1px solid ${C.border}`, background: p.id === user.id ? 'rgba(230,57,70,.06)' : 'transparent' }}>
                    <span style={{ fontSize: 16, marginRight: 8 }}>{p.emoji}</span>
                    <span style={{ color: C.cream, fontSize: 13, flex: 1 }}>{p.username}{p.id === user.id ? ' (you)' : ''}</span>
                    <span style={{ color: C.creamDim, fontSize: 12 }}>{p.entry.gamesPlayed} of {LEADERBOARD_MINIMUMS.rankGames}</span>
                  </div>
                ))}
              </div>
            )}
          </>
        )
      ) : (
        <div style={s.card({ padding: 16 })}>
          <ScoreChart allGames={allGames} allPlayers={chartPlayers} />
        </div>
      )}

      {/* How ranking works */}
      {showRatingInfo && (
        <div onClick={() => setShowRatingInfo(false)}
          style={{ position: 'fixed', inset: 0, zIndex: 60, background: 'rgba(0,0,0,.7)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20 }}>
          <div onClick={e => e.stopPropagation()}
            style={{ background: C.panel, backdropFilter: 'blur(20px) saturate(140%)', WebkitBackdropFilter: 'blur(20px) saturate(140%)', borderRadius: 14, border: `1px solid ${C.borderLight}`, padding: '22px 22px 18px', maxWidth: 360, width: '100%', maxHeight: '85vh', overflowY: 'auto', animation: 'slideUp .22s ease', boxShadow: '0 20px 60px rgba(0,0,0,.7)' }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 14 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <div className="red-line" style={{ margin: 0 }} />
                <div style={{ color: C.cream, fontWeight: 700, fontSize: 16 }}>How ranking works</div>
              </div>
              <button onClick={() => setShowRatingInfo(false)} style={{ background: 'transparent', border: 'none', color: C.creamDim, fontSize: 20, cursor: 'pointer', lineHeight: 1 }}>✕</button>
            </div>
            <div style={{ color: C.cream, fontSize: 13, lineHeight: 1.55 }}>
              <p style={{ marginTop: 0 }}>
                Same board as the Kedro app. Everyone starts at a rating of <strong style={{ color: C.gold }}>1,000</strong>.
              </p>
              <p>
                After each game, <strong>every pair of players</strong> at the table counts as a head-to-head: the lower total wins it, equal totals are a draw. So finishing 2nd still beats everyone below you.
              </p>
              <p>
                Beating stronger players is worth more. Each swing is split across the table, so a big table doesn't move ratings more than a small one, and your first 10 games count double so you find your level faster.
              </p>
              <div style={{ color: C.creamDim, fontSize: 12, marginBottom: 8 }}>The math, for one pair at a 4-player table:</div>
              <pre style={{ background: 'rgba(0,0,0,.35)', borderRadius: 8, padding: '12px 14px', fontSize: 11, lineHeight: 1.6, color: C.cream, fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace', margin: '0 0 14px', whiteSpace: 'pre-wrap', overflowX: 'auto' }}>
{`expected = 1 / (1 + 10^((them − you)/400))
         = 1 / (1 + 10^(200/400)) ≈ 0.24
K        = 32 ÷ (4 − 1) ≈ 10.7
you beat them: 10.7 × (1 − 0.24) ≈ +8.1`}
              </pre>
              <p>
                A rank and a rating show from your <strong>{LEADERBOARD_MINIMUMS.rankGames}th game</strong>. Win % needs {LEADERBOARD_MINIMUMS.winRateGames} games and knock % needs {LEADERBOARD_MINIMUMS.knockSuccessKnocks} knocks; until then you're listed without a rank for that sort. Ties share a rank.
              </p>
              <p style={{ color: C.creamDim, fontSize: 12, marginBottom: 0 }}>
                Only finished games with 3 to 8 players and 3+ rounds count.
              </p>
            </div>
            <button onClick={() => setShowRatingInfo(false)} className="btn-press"
              style={s.btn('outline', { width: '100%', marginTop: 16, padding: 11, fontSize: 13 })}>
              Got it
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
