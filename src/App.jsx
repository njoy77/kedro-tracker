import { useState, useEffect, useRef } from 'react';
import { supabase } from './lib/supabase';
import { LOGO_B64 } from './lib/logo';

const FONTS = `@import url('https://fonts.googleapis.com/css2?family=Bebas+Neue&family=Barlow:wght@300;400;500;600;700&family=Barlow+Condensed:wght@400;600;700&display=swap');`;

const C = {
  bg: '#0a0a0a', surface: '#111111', surface2: '#181818', surface3: '#1f1f1f',
  border: '#2a2a2a', borderLight: '#3a3a3a',
  red: '#d42b2b', redHover: '#e83535', redGlow: 'rgba(212,43,43,0.25)',
  silver: '#c0c0c0', silverDim: '#888888',
  cream: '#f0f0f0', creamDim: '#999999',
  green: '#3dba6a', blue: '#4a9edd',
  gold: '#f5c842',
  white: '#ffffff',
};

const db = {
  async get(key) {
    const { data } = await supabase.from('kedro_kv').select('value').eq('key', key).maybeSingle();
    return data?.value ?? null;
  },
  async set(key, val) {
    await supabase.from('kedro_kv').upsert({ key, value: val }, { onConflict: 'key' });
  },
  async del(key) {
    await supabase.from('kedro_kv').delete().eq('key', key);
  },
};

const uid = () => Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
const EMOJIS = ['🐴','🏇','🦄','🐎','🎠','🏆','🌾','🍀','🔱','⚜️','🌿','🪄','🎯','🌙','⭐'];
const RANK_BADGES = ['🥇','🥈','🥉'];
const SUITS = ['♠','♥','♦','♣'];

const s = {
  btn: (variant = 'red', extra = {}) => ({
    padding: '11px 22px', borderRadius: 6, border: 'none', cursor: 'pointer',
    fontFamily: 'Barlow, sans-serif', fontSize: 13, fontWeight: 700,
    transition: 'all .15s', letterSpacing: '.08em', textTransform: 'uppercase',
    ...(variant === 'red'     ? { background: C.red, color: C.white } : {}),
    ...(variant === 'outline' ? { background: 'transparent', color: C.silver, border: `1px solid ${C.borderLight}` } : {}),
    ...(variant === 'ghost'   ? { background: 'transparent', color: C.creamDim, padding: '8px 14px' } : {}),
    ...(variant === 'danger'  ? { background: 'rgba(212,43,43,.15)', color: C.red, border: `1px solid rgba(212,43,43,.3)` } : {}),
    ...(variant === 'gold'    ? { background: C.gold, color: '#000', fontWeight: 800 } : {}),
    ...extra,
  }),
  card: (extra = {}) => ({
    background: C.surface2, border: `1px solid ${C.border}`, borderRadius: 10, padding: '20px', ...extra,
  }),
  input: (extra = {}) => ({
    background: C.surface, border: `1px solid ${C.border}`, borderRadius: 6,
    color: C.cream, fontFamily: 'Barlow, sans-serif', fontSize: 15,
    padding: '11px 14px', outline: 'none', width: '100%', boxSizing: 'border-box', ...extra,
  }),
  label: { color: C.silverDim, fontSize: 11, fontWeight: 700, letterSpacing: '.1em', textTransform: 'uppercase', marginBottom: 6, display: 'block' },
  h1: { fontFamily: "'Bebas Neue', sans-serif", color: C.cream, margin: 0 },
  h2: { fontFamily: "'Bebas Neue', sans-serif", color: C.cream, margin: 0 },
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

function Confetti() {
  const particles = useRef(
    Array.from({ length: 55 }, (_, i) => ({
      id: i,
      left: Math.random() * 100,
      delay: Math.random() * 1.8,
      duration: 2.5 + Math.random() * 2,
      color: [C.red, C.gold, C.silver, C.green, C.blue, '#fff'][Math.floor(Math.random() * 6)],
      size: 6 + Math.floor(Math.random() * 8),
      isCircle: Math.random() > 0.5,
      rotate: Math.floor(Math.random() * 360),
    }))
  ).current;
  return (
    <div style={{ position: 'fixed', inset: 0, pointerEvents: 'none', zIndex: 60, overflow: 'hidden' }}>
      {particles.map(p => (
        <div key={p.id} style={{
          position: 'absolute', left: `${p.left}%`, top: -20,
          width: p.size, height: p.size, background: p.color,
          borderRadius: p.isCircle ? '50%' : 2,
          animation: `confettiFall ${p.duration}s ${p.delay}s cubic-bezier(.25,.46,.45,.94) forwards`,
          transform: `rotate(${p.rotate}deg)`,
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
  const [session, setSession]         = useState(null);
  const [historyGame, setHistoryGame] = useState(null);
  const [postGameData, setPostGameData] = useState(null);
  const [live, setLive]               = useState(false);
  const [navDir, setNavDir]           = useState('forward');

  // Login state
  const [lUsername, setLUsername]         = useState('');
  const [lStep, setLStep]                 = useState('username');
  const [lFoundPlayer, setLFoundPlayer]   = useState(null);
  const [lError, setLError]               = useState('');
  const [rName, setRName]                 = useState('');
  const [rEmoji, setREmoji]               = useState('🐴');

  // Game state
  const [ngSelected, setNgSelected]         = useState([]);
  const [roundInputs, setRoundInputs]       = useState({});
  const [roundError, setRoundError]         = useState('');
  const [knockedBy, setKnockedBy]           = useState(null);
  const [lastRoundDeltas, setLastRoundDeltas] = useState(null);
  const [showScoreSheet, setShowScoreSheet] = useState(false);
  const [endConfirm, setEndConfirm]         = useState(false);
  const [editingRound, setEditingRound]     = useState(null);
  const [editInputs, setEditInputs]         = useState({});

  // ── Initial load ────────────────────────────────────────────────────────────
  useEffect(() => {
    async function load() {
      const p = await db.get('kedro_players') || [];
      const g = await db.get('kedro_games')   || [];
      const active = await db.get('kedro_session');
      setAllPlayers(p); setAllGames(g);
      if (active) setSession(active);

      // Restore logged-in user from localStorage
      let loggedInUser = null;
      try {
        const saved = localStorage.getItem('kedro_user');
        if (saved) {
          const parsed = JSON.parse(saved);
          const found = p.find(pl => pl.id === parsed.id);
          if (found) { loggedInUser = found; setUser(found); }
        }
      } catch {}

      setTimeout(() => navigate(loggedInUser ? 'home' : 'login', 'forward'), 1800);
    }
    load();
  }, []);

  // ── Realtime sync ───────────────────────────────────────────────────────────
  useEffect(() => {
    const channel = supabase
      .channel('kedro-sync')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'kedro_kv' }, (payload) => {
        const key   = payload.new?.key || payload.old?.key;
        const value = payload.eventType === 'DELETE' ? null : payload.new?.value;
        if (key === 'kedro_players') setAllPlayers(value || []);
        else if (key === 'kedro_games')   setAllGames(value || []);
        else if (key === 'kedro_session') setSession(value || null);
        setLive(true);
      })
      .subscribe(status => { if (status === 'SUBSCRIBED') setLive(true); });
    return () => supabase.removeChannel(channel);
  }, []);

  // ── DB helpers ───────────────────────────────────────────────────────────────
  async function savePlayers(p) { setAllPlayers(p); await db.set('kedro_players', p); }
  async function saveGames(g)   { setAllGames(g);   await db.set('kedro_games', g); }
  async function saveSession(s) { setSession(s);    await db.set('kedro_session', s); }

  // ── Navigation ───────────────────────────────────────────────────────────────
  function navigate(newView, dir = 'forward') {
    setNavDir(dir);
    setView(newView);
  }

  // ── Auth ─────────────────────────────────────────────────────────────────────
  function handleUsernameNext() {
    const u = lUsername.trim();
    if (!u) return;
    const found = allPlayers.find(p => p.username.toLowerCase() === u.toLowerCase());
    if (found) { setLFoundPlayer(found); setLStep('confirm'); }
    else { setLStep('notfound'); }
    setLError('');
  }

  function handleLogin(player) {
    setUser(player);
    localStorage.setItem('kedro_user', JSON.stringify(player));
    setLUsername(''); setLStep('username'); setLFoundPlayer(null); setLError('');
    navigate('home', 'forward');
  }

  async function handleRegister() {
    const name = rName.trim();
    if (!name) { setLError('Enter a username'); return; }
    if (allPlayers.find(p => p.username.toLowerCase() === name.toLowerCase())) { setLError('Username taken'); return; }
    const np = { id: uid(), username: name, emoji: rEmoji, createdAt: Date.now() };
    await savePlayers([...allPlayers, np]);
    handleLogin(np);
    setRName(''); setREmoji('🐴');
  }

  function logout() {
    setUser(null);
    localStorage.removeItem('kedro_user');
    setLStep('username'); setLUsername('');
    navigate('login', 'back');
  }

  function switchPlayer() {
    setUser(null);
    localStorage.removeItem('kedro_user');
    setLStep('username'); setLUsername('');
    navigate('login', 'back');
  }

  // ── Game logic ───────────────────────────────────────────────────────────────
  async function startGame(players) {
    const newSession = {
      id: uid(), startedAt: Date.now(), status: 'active',
      players: players.map(p => ({ id: p.id, username: p.username, emoji: p.emoji, total: 0 })),
      rounds: [],
    };
    await saveSession(newSession);
    setNgSelected([]); setRoundInputs({}); setKnockedBy(null);
    navigate('game', 'forward');
  }

  async function addRound() {
    if (!session) return;
    const missing = session.players.some(p => roundInputs[p.id] === undefined || roundInputs[p.id] === '');
    if (missing) { setRoundError('Enter a score for every player'); return; }

    const roundScores = session.players.map(p => ({
      playerId: p.id,
      score: parseInt(roundInputs[p.id]) || 0,
    }));

    let knockerWon = false;
    if (knockedBy) {
      const knockerScore = roundScores.find(r => r.playerId === knockedBy)?.score;
      const minScore = Math.min(...roundScores.map(r => r.score));
      knockerWon = knockerScore !== undefined && knockerScore === minScore;
    }

    const round = { id: uid(), timestamp: Date.now(), scores: roundScores, knockedBy, knockerWon };
    const updated = {
      ...session,
      rounds: [...session.rounds, round],
      players: session.players.map(p => {
        const rs = roundScores.find(r => r.playerId === p.id);
        return { ...p, total: p.total + (rs?.score || 0) };
      }),
    };
    await saveSession(updated);
    setLastRoundDeltas(roundScores);
    setTimeout(() => setLastRoundDeltas(null), 2500);
    setRoundInputs({}); setKnockedBy(null); setRoundError('');
    setShowScoreSheet(false);
  }

  async function editRound(roundIndex) {
    if (!session) return;
    const updatedRounds = session.rounds.map((r, i) => {
      if (i !== roundIndex) return r;
      const newScores = session.players.map(p => ({
        playerId: p.id,
        score: parseInt(editInputs[p.id]) || 0,
      }));
      let knockerWon = false;
      if (r.knockedBy) {
        const knockerScore = newScores.find(s => s.playerId === r.knockedBy)?.score;
        knockerWon = knockerScore !== undefined && knockerScore === Math.min(...newScores.map(s => s.score));
      }
      return { ...r, scores: newScores, knockerWon };
    });

    const totals = {};
    session.players.forEach(p => { totals[p.id] = 0; });
    updatedRounds.forEach(r => r.scores.forEach(s => { totals[s.playerId] = (totals[s.playerId] || 0) + s.score; }));

    const updated = {
      ...session,
      rounds: updatedRounds,
      players: session.players.map(p => ({ ...p, total: totals[p.id] || 0 })),
    };
    await saveSession(updated);
    setEditingRound(null); setEditInputs({});
  }

  async function endGame() {
    if (!session) return;
    const sorted  = [...session.players].sort((a, b) => a.total - b.total);
    const winner  = sorted[0];
    const completed = { ...session, status: 'complete', endedAt: Date.now(), winnerId: winner.id };
    const updatedGames = [completed, ...allGames];
    await saveGames(updatedGames);
    await db.del('kedro_session');
    setSession(null); setAllGames(updatedGames);
    setPostGameData(completed);
    setEndConfirm(false);
    navigate('postgame', 'forward');
  }

  async function abandonGame() {
    if (!session) return;
    const abandoned = { ...session, status: 'abandoned', endedAt: Date.now() };
    const updatedGames = [abandoned, ...allGames];
    await saveGames(updatedGames);
    await db.del('kedro_session');
    setSession(null); setAllGames(updatedGames);
    navigate('home', 'back');
  }

  async function rematch(players) {
    const newSession = {
      id: uid(), startedAt: Date.now(), status: 'active',
      players: players.map(p => ({ id: p.id, username: p.username, emoji: p.emoji, total: 0 })),
      rounds: [],
    };
    await saveSession(newSession);
    setRoundInputs({}); setKnockedBy(null);
    setPostGameData(null);
    navigate('game', 'forward');
  }

  // ── Stats ────────────────────────────────────────────────────────────────────
  function getStats(playerId) {
    const pg = allGames.filter(g => g.status === 'complete' && g.players.find(p => p.id === playerId));
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
    const nemesis   = nemesisId ? allPlayers.find(p => p.id === nemesisId) : null;

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
    };
  }

  // ── CSS ──────────────────────────────────────────────────────────────────────
  const CSS = `
    * { box-sizing: border-box; }
    body { margin: 0; background: ${C.bg}; }
    input:focus { border-color: ${C.red} !important; box-shadow: 0 0 0 2px ${C.redGlow}; }
    input[type=number]::-webkit-inner-spin-button { -webkit-appearance: none; }
    .btn-press:active { transform: scale(0.97) !important; }
    .btn-red:hover  { background: ${C.redHover} !important; }
    .btn-outline:hover { border-color: ${C.red} !important; color: ${C.red} !important; }
    .player-tile:hover { border-color: ${C.red} !important; }
    .emoji-btn:hover { transform: scale(1.2); }
    @keyframes fadeIn      { from { opacity:0; transform:translateY(8px); } to { opacity:1; transform:translateY(0); } }
    @keyframes slideInRight { from { opacity:0; transform:translateX(32px); } to { opacity:1; transform:translateX(0); } }
    @keyframes slideInLeft  { from { opacity:0; transform:translateX(-32px); } to { opacity:1; transform:translateX(0); } }
    @keyframes pulse       { 0%,100%{opacity:1;} 50%{opacity:.3;} }
    @keyframes slideUp     { from { transform:translateY(100%); } to { transform:translateY(0); } }
    @keyframes deltaFade   { 0%{opacity:0;transform:translateY(-6px);} 15%{opacity:1;transform:translateY(0);} 75%{opacity:1;} 100%{opacity:0;} }
    @keyframes confettiFall { to { transform: translateY(110vh) rotate(720deg); opacity: 0; } }
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
      <div style={{ minHeight: '100vh', background: C.bg, color: C.cream, fontFamily: 'Barlow, sans-serif', position: 'relative' }}>

        {/* Radial glow */}
        <div style={{ position: 'fixed', inset: 0, backgroundImage: 'radial-gradient(ellipse at 15% 40%, rgba(212,43,43,.07) 0%, transparent 55%), radial-gradient(ellipse at 85% 80%, rgba(212,43,43,.04) 0%, transparent 50%)', pointerEvents: 'none', zIndex: 0 }} />

        {/* Card suit watermarks */}
        <div style={{ position: 'fixed', inset: 0, pointerEvents: 'none', zIndex: 0, overflow: 'hidden' }}>
          {SUITS.map((suit, i) => (
            <div key={suit} style={{ position: 'absolute', fontFamily: 'serif', fontSize: 150, userSelect: 'none', color: i % 2 === 0 ? 'rgba(212,43,43,.028)' : 'rgba(192,192,192,.022)', top: `${12 + i * 22}%`, left: i % 2 === 0 ? '3%' : '78%', transform: 'rotate(-12deg)' }}>{suit}</div>
          ))}
        </div>

        <div style={{ position: 'relative', zIndex: 1, maxWidth: 480, margin: '0 auto', ...pad }}>
          <div key={view} className={navDir === 'forward' ? 'screen-fwd' : 'screen-bk'}>

          {view === 'splash' && <SplashScreen />}

          {view === 'login' && (
            <LoginScreen
              step={lStep} username={lUsername} error={lError} found={lFoundPlayer}
              rName={rName} rEmoji={rEmoji}
              onUsernameChange={setLUsername}
              onUsernameNext={handleUsernameNext}
              onLogin={handleLogin}
              onRegister={handleRegister}
              onStepChange={setLStep}
              onErrorChange={setLError}
              onRNameChange={setRName}
              onREmojiChange={setREmoji}
            />
          )}

          {view !== 'splash' && view !== 'login' && user && (
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
                  onLogout={logout}
                  onRematch={(g) => rematch(g.players)}
                />
              )}

              {view === 'newgame' && (
                <NewGameScreen
                  user={user} allPlayers={allPlayers} selected={ngSelected}
                  onToggle={p => setNgSelected(prev =>
                    prev.find(x => x.id === p.id) ? prev.filter(x => x.id !== p.id) : [...prev, p]
                  )}
                  onStart={() => {
                    let players = [...ngSelected];
                    if (!players.find(p => p.id === user.id)) players = [user, ...players];
                    if (players.length >= 2) startGame(players);
                  }}
                  onBack={() => navigate('home', 'back')}
                />
              )}

              {view === 'game' && session && (
                <GameScreen
                  session={session} user={user}
                  roundInputs={roundInputs} knockedBy={knockedBy}
                  roundError={roundError} lastRoundDeltas={lastRoundDeltas}
                  showScoreSheet={showScoreSheet} endConfirm={endConfirm}
                  editingRound={editingRound} editInputs={editInputs}
                  onInput={(id, val) => setRoundInputs(prev => ({ ...prev, [id]: val }))}
                  onKnockedBy={id => setKnockedBy(prev => prev === id ? null : id)}
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
                    r.scores.forEach(s => { inputs[s.playerId] = String(s.score); });
                    setEditInputs(inputs); setEditingRound(idx);
                  }}
                  onEditInput={(id, val) => setEditInputs(prev => ({ ...prev, [id]: val }))}
                  onSaveEdit={editRound}
                  onCancelEdit={() => { setEditingRound(null); setEditInputs({}); }}
                />
              )}

              {view === 'postgame' && postGameData && (
                <PostGameScreen
                  game={postGameData} user={user}
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
                  allPlayers={allPlayers}
                  onBack={() => navigate('home', 'back')}
                  onSwitchPlayer={switchPlayer}
                  onLogout={logout}
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

function LoginScreen({ step, username, error, found, rName, rEmoji, onUsernameChange, onUsernameNext, onLogin, onRegister, onStepChange, onErrorChange, onRNameChange, onREmojiChange }) {
  const enter = (e, fn) => { if (e.key === 'Enter') fn(); };
  return (
    <div className="screen" style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: '40px 0' }}>
      <div style={{ textAlign: 'center', marginBottom: 32, display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
        <KedroLogo height={120} />
        <div style={{ color: C.creamDim, fontSize: 11, letterSpacing: '.18em', textTransform: 'uppercase', marginTop: 10 }}>Score Tracker</div>
        <div className="red-line" style={{ margin: '10px auto 0' }} />
      </div>
      <div style={s.card({ padding: 28 })}>
        {step === 'username' && (
          <>
            <div style={{ ...s.h2, fontSize: 26, marginBottom: 20 }}>Welcome Back</div>
            <label style={s.label}>Username</label>
            <input style={s.input()} placeholder="Enter your username..." value={username}
              onChange={e => onUsernameChange(e.target.value)} onKeyDown={e => enter(e, onUsernameNext)} autoFocus />
            {error && <div style={{ color: C.red, fontSize: 13, marginTop: 8 }}>{error}</div>}
            <button className="btn-red btn-press" onClick={onUsernameNext} style={{ ...s.btn('red'), width: '100%', marginTop: 16 }}>Continue →</button>
            <div style={{ textAlign: 'center', marginTop: 14 }}>
              <button onClick={() => { onStepChange('register'); onErrorChange(''); }} style={s.btn('ghost', { fontSize: 12 })}>New? Create a profile</button>
            </div>
          </>
        )}
        {step === 'confirm' && found && (
          <>
            <BackBtn onBack={() => { onStepChange('username'); onErrorChange(''); }} />
            <div style={{ textAlign: 'center', margin: '20px 0 28px' }}>
              <div style={{ fontSize: 60 }}>{found.emoji}</div>
              <div style={{ ...s.h2, fontSize: 30, marginTop: 10 }}>Hey, {found.username}!</div>
              <div style={{ color: C.creamDim, fontSize: 14, marginTop: 6 }}>Ready to play?</div>
            </div>
            <button className="btn-red btn-press" onClick={() => onLogin(found)} style={{ ...s.btn('red'), width: '100%', fontSize: 15, padding: 14 }}>Let's Play 🐴</button>
          </>
        )}
        {step === 'notfound' && (
          <>
            <BackBtn onBack={() => { onStepChange('username'); onErrorChange(''); }} />
            <div style={{ textAlign: 'center', margin: '20px 0' }}>
              <div style={{ fontSize: 40 }}>🤔</div>
              <div style={{ ...s.h2, fontSize: 22, marginTop: 12 }}>Not Found</div>
              <div style={{ color: C.creamDim, fontSize: 14, marginTop: 8 }}>"{username}" doesn't exist yet.</div>
            </div>
            <button className="btn-red btn-press" onClick={() => { onStepChange('register'); onRNameChange(username); onErrorChange(''); }}
              style={{ ...s.btn('red'), width: '100%' }}>Create Profile →</button>
          </>
        )}
        {step === 'register' && (
          <>
            <BackBtn onBack={() => { onStepChange('username'); onErrorChange(''); }} label="Back to login" />
            <div style={{ ...s.h2, fontSize: 24, margin: '16px 0 20px' }}>Create Profile</div>
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
              <label style={s.label}>Username</label>
              <input style={s.input()} placeholder="Choose a username..." value={rName} onChange={e => onRNameChange(e.target.value)} autoFocus />
            </div>
            {error && <div style={{ color: C.red, fontSize: 13, marginBottom: 10 }}>{error}</div>}
            <button className="btn-red btn-press" onClick={onRegister} style={{ ...s.btn('red'), width: '100%' }}>Create Profile 🐴</button>
          </>
        )}
      </div>
    </div>
  );
}

function HomeScreen({ user, stats, session, live, recentGames, lastGame, onNewGame, onResumeGame, onHistory, onProfile, onLogout, onRematch }) {
  return (
    <div className="screen" style={{ paddingTop: 36, paddingBottom: 60 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 24 }}>
        <div>
          <KedroLogo height={44} />
          <div style={{ marginTop: 10 }}>
            <div style={{ fontSize: 11, color: C.silverDim, textTransform: 'uppercase', letterSpacing: '.1em' }}>Player</div>
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
              <div style={{ color: C.red, fontSize: 11, letterSpacing: '.1em', textTransform: 'uppercase', marginBottom: 4 }}>Game in Progress</div>
              <div style={{ color: C.cream, fontSize: 14 }}>{session.players.map(p => p.username).join(' · ')}</div>
              <div style={{ color: C.creamDim, fontSize: 12, marginTop: 3 }}>{session.rounds.length} round{session.rounds.length !== 1 ? 's' : ''} played</div>
            </div>
            <div style={{ color: C.red, fontSize: 22 }}>→</div>
          </div>
        </div>
      )}

      <button className="btn-red btn-press" onClick={onNewGame} style={{ ...s.btn('red'), width: '100%', padding: 14, fontSize: 15, marginBottom: 8 }}>
        + New Game
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

      <div style={{ display: 'flex', justifyContent: 'center', gap: 8, marginTop: 28 }}>
        <button className="btn-press" onClick={onHistory} style={s.btn('ghost')}>📋 History</button>
        <button className="btn-press" onClick={onProfile} style={s.btn('ghost')}>👤 Profile</button>
        <button className="btn-press" onClick={onLogout} style={s.btn('ghost', { fontSize: 11 })}>Sign out</button>
      </div>
    </div>
  );
}

function NewGameScreen({ user, allPlayers, selected, onToggle, onStart, onBack }) {
  const others = allPlayers.filter(p => p.id !== user.id);
  const count = selected.length + 1;
  return (
    <div className="screen" style={{ paddingTop: 32, paddingBottom: 40 }}>
      <BackBtn onBack={onBack} />
      <div style={{ margin: '16px 0 6px' }}><KedroLogo height={36} /></div>
      <div style={{ ...s.h1, fontSize: 36 }}>New Game</div>
      <div className="red-line" />
      <div style={{ color: C.creamDim, fontSize: 14, marginBottom: 22 }}>Select who's playing. You're always in.</div>

      <div style={{ ...s.card({ padding: '12px 16px', marginBottom: 14, border: `1px solid ${C.red}`, background: 'rgba(212,43,43,.06)' }), display: 'flex', alignItems: 'center', gap: 12 }}>
        <div style={{ fontSize: 26 }}>{user.emoji}</div>
        <div>
          <div style={{ color: C.red, fontSize: 11, textTransform: 'uppercase', letterSpacing: '.07em' }}>You</div>
          <div style={{ color: C.cream, fontSize: 15 }}>{user.username}</div>
        </div>
        <div style={{ marginLeft: 'auto', color: C.red, fontSize: 16 }}>✓</div>
      </div>

      {others.length === 0 ? (
        <div style={{ ...s.card({ padding: 24, textAlign: 'center' }), color: C.creamDim }}>No other players registered yet.</div>
      ) : (
        <>
          <div style={{ color: C.silverDim, fontSize: 11, letterSpacing: '.08em', textTransform: 'uppercase', marginBottom: 10 }}>Add Players</div>
          {others.map(p => {
            const sel = !!selected.find(x => x.id === p.id);
            return (
              <div key={p.id} className="player-tile" onClick={() => onToggle(p)}
                style={{ ...s.card({ padding: '12px 16px', marginBottom: 8, cursor: 'pointer', border: `1px solid ${sel ? C.red : C.border}`, background: sel ? 'rgba(212,43,43,.07)' : C.surface2, transition: 'all .15s' }), display: 'flex', alignItems: 'center', gap: 12 }}>
                <div style={{ fontSize: 26 }}>{p.emoji}</div>
                <div style={{ flex: 1, color: C.cream, fontSize: 15 }}>{p.username}</div>
                <div style={{ width: 22, height: 22, borderRadius: '50%', border: `2px solid ${sel ? C.red : C.borderLight}`, background: sel ? C.red : 'transparent', display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#fff', fontSize: 12, transition: 'all .15s' }}>
                  {sel ? '✓' : ''}
                </div>
              </div>
            );
          })}
        </>
      )}

      <div style={{ marginTop: 14, padding: '12px 16px', borderRadius: 8, background: C.surface, color: C.creamDim, fontSize: 13, textAlign: 'center' }}>
        {count} player{count !== 1 ? 's' : ''} selected {count < 2 ? '— need at least 2' : '— ready!'}
      </div>
      <button className="btn-red btn-press" onClick={onStart} disabled={count < 2}
        style={{ ...s.btn('red', { width: '100%', marginTop: 12, padding: 14, fontSize: 15, opacity: count < 2 ? 0.5 : 1 }) }}>
        Deal Cards 🐴
      </button>
    </div>
  );
}

function GameScreen({
  session, user, roundInputs, knockedBy, roundError, lastRoundDeltas,
  showScoreSheet, endConfirm, editingRound, editInputs,
  onInput, onKnockedBy, onAddRound, onEndGame, onEndConfirm, onCancelEnd,
  onShowSheet, onHideSheet, onAbandon, onHome,
  onEditRound, onEditInput, onSaveEdit, onCancelEdit,
}) {
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
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 18 }}>
        <button onClick={onHome} style={s.btn('ghost', { paddingLeft: 0, fontSize: 12 })}>← Home</button>
        <div style={{ textAlign: 'center' }}>
          <KedroLogo height={28} />
          <div style={{ color: C.silverDim, fontSize: 10, letterSpacing: '.1em', textTransform: 'uppercase', marginTop: 2 }}>
            Round {session.rounds.length + 1}
          </div>
        </div>
        <div style={{ width: 60 }} />
      </div>

      {/* Scoreboard */}
      <div style={s.card({ padding: 0, overflow: 'hidden', marginBottom: 16 })}>
        <div style={{ background: C.surface3, padding: '8px 16px', borderBottom: `1px solid ${C.border}`, display: 'grid', gridTemplateColumns: '26px 1fr 48px 52px', gap: 6, alignItems: 'center' }}>
          <div />
          <div style={{ fontSize: 10, color: C.creamDim, textTransform: 'uppercase', letterSpacing: '.08em' }}>Player</div>
          {session.rounds.length > 0 && <div style={{ fontSize: 10, color: C.creamDim, textTransform: 'uppercase', textAlign: 'center' }}>Rnd</div>}
          <div style={{ fontSize: 10, color: C.creamDim, textTransform: 'uppercase', textAlign: 'right' }}>Total</div>
        </div>

        {sorted.map((p, i) => {
          const isLeader = p.id === leaderId;
          const delta    = lastRoundDeltas?.find(d => d.playerId === p.id);
          const lastRound = session.rounds.length > 0
            ? session.rounds[session.rounds.length - 1].scores.find(s => s.playerId === p.id)
            : null;
          return (
            <div key={p.id} style={{
              display: 'grid', gridTemplateColumns: '26px 1fr 48px 52px', gap: 6,
              alignItems: 'center', padding: '13px 16px', borderBottom: `1px solid ${C.border}`,
              background: isLeader ? 'rgba(245,200,66,.05)' : 'transparent',
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
                  <div style={{ color: C.cream, fontSize: 14 }}>{p.username}{p.id === user?.id ? ' (you)' : ''}</div>
                  {isLeader && session.rounds.length > 0 && (
                    <div style={{ fontSize: 10, color: C.gold, textTransform: 'uppercase', letterSpacing: '.06em' }}>Leading</div>
                  )}
                </div>
              </div>
              <div style={{ textAlign: 'center', position: 'relative', minWidth: 48 }}>
                {delta ? (
                  <span key={`d-${session.rounds.length}`} style={{ color: delta.score < 0 ? C.green : delta.score === 0 ? C.creamDim : C.red, fontSize: 14, fontWeight: 700, animation: 'deltaFade 2.5s ease forwards', display: 'block' }}>
                    {delta.score > 0 ? `+${delta.score}` : delta.score}
                  </span>
                ) : lastRound ? (
                  <span style={{ color: C.creamDim, fontSize: 13 }}>{lastRound.score > 0 ? `+${lastRound.score}` : lastRound.score}</span>
                ) : null}
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
                    <th key={p.id} style={{ color: C.creamDim, textAlign: 'center', paddingBottom: 8, fontWeight: 500, fontSize: 11 }}>{p.emoji}</th>
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
          End Game & See Winner
        </button>
      )}
      {endConfirm && (
        <div style={s.card({ border: `1px solid ${C.red}`, background: 'rgba(212,43,43,.06)', marginBottom: 10 })}>
          <div style={{ color: C.cream, fontSize: 14, marginBottom: 14, textAlign: 'center' }}>
            End game now?<br /><span style={{ color: C.creamDim, fontSize: 12 }}>Current scores will be final.</span>
          </div>
          <div style={{ display: 'flex', gap: 10, marginBottom: 8 }}>
            <button className="btn-press" onClick={onCancelEnd} style={s.btn('outline', { flex: 1 })}>Keep Playing</button>
            <button className="btn-press" onClick={onEndGame} style={s.btn('danger', { flex: 1 })}>🐴 Kedro!</button>
          </div>
          <button className="btn-press" onClick={onAbandon} style={s.btn('ghost', { width: '100%', fontSize: 11 })}>Abandon (won't count toward stats)</button>
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
          <div onClick={onHideSheet} style={{ flex: 1, background: 'rgba(0,0,0,.65)' }} />
          <div style={{
            background: C.surface, borderRadius: '18px 18px 0 0',
            border: `1px solid ${C.border}`, borderBottom: 'none',
            padding: '20px 20px 40px', animation: 'slideUp .22s ease',
            maxHeight: '85vh', overflowY: 'auto',
          }}>
            <div style={{ width: 36, height: 4, borderRadius: 2, background: C.borderLight, margin: '0 auto 20px' }} />
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 18 }}>
              <div className="red-line" style={{ margin: 0 }} />
              <div style={{ color: C.red, fontSize: 12, fontWeight: 700, letterSpacing: '.08em', textTransform: 'uppercase' }}>
                Round {session.rounds.length + 1} Scores
              </div>
            </div>
            {session.players.map(p => (
              <div key={p.id} style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 14 }}>
                <div style={{ fontSize: 22, width: 28, textAlign: 'center' }}>{p.emoji}</div>
                <div style={{ flex: 1, color: C.cream, fontSize: 14 }}>{p.username}</div>
                <input type="number" min={-100} max={100} inputMode="numeric"
                  style={s.input({ width: 74, textAlign: 'center', padding: '10px 6px', fontSize: 18 })}
                  placeholder="0" value={roundInputs[p.id] ?? ''}
                  onChange={e => onInput(p.id, e.target.value)} />
                <button onClick={() => onKnockedBy(p.id)} style={{
                  padding: '8px 10px', borderRadius: 6, cursor: 'pointer', whiteSpace: 'nowrap',
                  border: `1px solid ${knockedBy === p.id ? C.red : C.border}`,
                  background: knockedBy === p.id ? 'rgba(212,43,43,.2)' : 'transparent',
                  color: knockedBy === p.id ? C.red : C.creamDim,
                  fontSize: 11, fontFamily: 'Barlow, sans-serif', fontWeight: 600,
                  letterSpacing: '.04em', textTransform: 'uppercase', transition: 'all .15s',
                }}>
                  {knockedBy === p.id ? '🃏 Knocked' : 'Knocked?'}
                </button>
              </div>
            ))}
            {roundError && <div style={{ color: C.red, fontSize: 13, marginBottom: 10 }}>{roundError}</div>}
            <button className="btn-red btn-press" onClick={onAddRound}
              style={{ ...s.btn('red', { width: '100%', marginTop: 4, padding: 14, fontSize: 15 }) }}>
              Save Round →
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

function PostGameScreen({ game, user, onRematch, onHome }) {
  const sorted = [...game.players].sort((a, b) => a.total - b.total);
  const winner = sorted[0];

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
      <Confetti />

      {/* Winner hero */}
      <div style={{ textAlign: 'center', marginBottom: 28 }}>
        <div style={{ fontSize: 88, animation: 'crownBob 2s ease infinite', lineHeight: 1.1 }}>{winner.emoji}</div>
        <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 54, color: C.gold, letterSpacing: '.04em', lineHeight: 1, marginTop: 8 }}>{winner.username}</div>
        <div style={{ color: C.silver, fontSize: 14, letterSpacing: '.12em', textTransform: 'uppercase', marginTop: 6 }}>Wins · {winner.total} pts · {game.rounds.length} rounds</div>
        <div style={{ display: 'flex', justifyContent: 'center', marginTop: 14 }}>
          <KedroLogo height={46} />
        </div>
      </div>

      {/* Final standings */}
      <div style={s.card({ padding: 0, overflow: 'hidden', marginBottom: 14 })}>
        <div style={{ background: C.surface3, padding: '8px 16px', borderBottom: `1px solid ${C.border}` }}>
          <div style={{ fontSize: 10, color: C.creamDim, textTransform: 'uppercase', letterSpacing: '.1em' }}>Final Standings</div>
        </div>
        {sorted.map((p, i) => (
          <div key={p.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '14px 16px', borderBottom: `1px solid ${C.border}`, background: i === 0 ? 'rgba(245,200,66,.06)' : 'transparent' }}>
            <div style={{ fontSize: 18, width: 28, textAlign: 'center' }}>
              {i < 3 ? RANK_BADGES[i] : <span style={{ color: C.creamDim }}>{i + 1}</span>}
            </div>
            <div style={{ fontSize: 28 }}>{p.emoji}</div>
            <div style={{ flex: 1, color: C.cream, fontSize: 15 }}>{p.username}{p.id === user?.id ? ' (you)' : ''}</div>
            <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 30, color: i === 0 ? C.gold : C.cream }}>{p.total}</div>
          </div>
        ))}
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
    const winner = selected.players.find(p => p.id === selected.winnerId);
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
          {[...selected.players].sort((a, b) => a.total - b.total).map((p, i) => (
            <div key={p.id} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 0', borderBottom: `1px solid ${C.border}` }}>
              <div style={{ width: 24, textAlign: 'center' }}>{i < 3 ? RANK_BADGES[i] : <span style={{ color: C.creamDim }}>{i + 1}</span>}</div>
              <div style={{ fontSize: 22 }}>{p.emoji}</div>
              <div style={{ flex: 1, color: C.cream }}>{p.username}</div>
              <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 24, color: i === 0 ? C.gold : C.cream }}>{p.total}</div>
            </div>
          ))}
        </div>

        {selected.rounds && selected.rounds.length > 0 && (
          <div style={s.card()}>
            <div style={{ color: C.silverDim, fontSize: 11, textTransform: 'uppercase', letterSpacing: '.08em', marginBottom: 10 }}>Round by Round</div>
            <div style={{ overflowX: 'auto' }}>
              <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13 }}>
                <thead>
                  <tr>
                    <th style={{ color: C.creamDim, textAlign: 'left', paddingBottom: 8, fontWeight: 500, fontSize: 11 }}>#</th>
                    {selected.players.map(p => (
                      <th key={p.id} style={{ color: C.creamDim, textAlign: 'center', paddingBottom: 8, fontWeight: 500, fontSize: 11 }}>{p.emoji}</th>
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
        <div style={{ ...s.card({ textAlign: 'center', padding: 40 }), color: C.creamDim }}>No games yet. Deal some cards!</div>
      ) : displayGames.map(g => {
        const winner    = g.players.find(p => p.id === g.winnerId);
        const isUserWin = g.winnerId === user?.id;
        const date      = new Date(g.endedAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
        const abandoned = g.status === 'abandoned';
        return (
          <div key={g.id} onClick={() => onSelect(g)} className="player-tile"
            style={{ ...s.card({ padding: '14px 16px', marginBottom: 8, cursor: 'pointer', opacity: abandoned ? 0.6 : 1 }), display: 'flex', alignItems: 'center', gap: 14 }}>
            <div style={{ fontSize: 28 }}>{abandoned ? '⚠️' : winner?.emoji}</div>
            <div style={{ flex: 1 }}>
              <div style={{ color: C.cream, fontSize: 14 }}>{g.players.map(p => p.username).join(' · ')}</div>
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

function ProfileScreen({ user, stats, games, allPlayers, onBack, onSwitchPlayer, onLogout }) {
  const userGames = games.filter(g => g.status === 'complete' && g.players.find(p => p.id === user.id));
  return (
    <div className="screen" style={{ paddingTop: 28, paddingBottom: 60 }}>
      <BackBtn onBack={onBack} />
      <div style={{ textAlign: 'center', margin: '20px 0 28px' }}>
        <div style={{ fontSize: 64 }}>{user.emoji}</div>
        <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 36, color: C.cream, marginTop: 8 }}>{user.username}</div>
        <div className="red-line" style={{ margin: '8px auto 0' }} />
        <div style={{ color: C.creamDim, fontSize: 12, marginTop: 8, textTransform: 'uppercase', letterSpacing: '.08em' }}>
          Since {new Date(user.createdAt).toLocaleDateString('en-US', { month: 'long', year: 'numeric' })}
        </div>
      </div>

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
            <div style={{ color: C.creamDim, fontSize: 12 }}>Beats you most often</div>
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

      <div style={{ display: 'flex', gap: 10 }}>
        <button className="btn-press" onClick={onSwitchPlayer} style={{ ...s.btn('outline', { flex: 1 }) }}>Switch Player</button>
        <button className="btn-press" onClick={onLogout} style={{ ...s.btn('ghost', { flex: 1 }) }}>Sign Out</button>
      </div>
    </div>
  );
}
