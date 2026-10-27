import { useState } from 'react';

const C = {
  bg: '#0a0a0e',
  bgGradFrom: '#15151c',
  bgGradTo: '#08080c',
  surface: 'rgba(22, 22, 30, 0.55)',
  surfaceSolid: '#16161e',
  border: 'rgba(255, 255, 255, 0.06)',
  borderStrong: 'rgba(255, 255, 255, 0.12)',
  red: '#e63946',
  redDeep: '#b81d2a',
  redGlow: 'rgba(230, 57, 70, 0.35)',
  cream: '#f5efe6',
  creamDim: 'rgba(245, 239, 230, 0.55)',
  creamFaint: 'rgba(245, 239, 230, 0.28)',
  gold: '#f5c842',
  goldDeep: '#d4a829',
  green: '#3dba6a',
  ink: '#0c0c12',
};

const glass = (extra = {}) => ({
  background: C.surface,
  backdropFilter: 'blur(20px) saturate(140%)',
  WebkitBackdropFilter: 'blur(20px) saturate(140%)',
  border: `1px solid ${C.border}`,
  borderRadius: 16,
  boxShadow: '0 10px 30px rgba(0,0,0,.45), 0 1px 0 rgba(255,255,255,.04) inset, 0 0 0 1px rgba(0,0,0,.4)',
  ...extra,
});

const sectionLabel = {
  color: C.creamFaint,
  fontSize: 10,
  letterSpacing: '.14em',
  textTransform: 'uppercase',
  fontWeight: 700,
  marginBottom: 8,
};

const cardSuits = (
  <>
    <div style={{ position: 'fixed', top: '8%', left: '-3%', fontSize: 280, color: 'rgba(245,239,230,.025)', pointerEvents: 'none', fontFamily: 'serif', lineHeight: 1 }}>♠</div>
    <div style={{ position: 'fixed', top: '38%', right: '-5%', fontSize: 320, color: 'rgba(230,57,70,.04)', pointerEvents: 'none', fontFamily: 'serif', lineHeight: 1 }}>♥</div>
    <div style={{ position: 'fixed', bottom: '8%', left: '-2%', fontSize: 260, color: 'rgba(230,57,70,.035)', pointerEvents: 'none', fontFamily: 'serif', lineHeight: 1 }}>♦</div>
    <div style={{ position: 'fixed', bottom: '32%', right: '-3%', fontSize: 240, color: 'rgba(245,239,230,.02)', pointerEvents: 'none', fontFamily: 'serif', lineHeight: 1 }}>♣</div>
  </>
);

function HomeMock() {
  return (
    <div style={{ padding: '24px 18px 110px', maxWidth: 420, margin: '0 auto', position: 'relative' }}>
      {/* Top bar */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 18 }}>
        <div style={{
          fontFamily: "'Bebas Neue', sans-serif", fontSize: 30, letterSpacing: '.04em',
          color: C.cream,
          background: `linear-gradient(180deg, ${C.cream}, #b8a99a)`,
          WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent',
        }}>KEDRO</div>
        <div style={{ ...glass({ borderRadius: 999, padding: '6px 12px', display: 'flex', alignItems: 'center', gap: 6, fontSize: 11, color: C.creamDim, letterSpacing: '.08em' }) }}>
          <div style={{ width: 7, height: 7, borderRadius: '50%', background: C.green, boxShadow: `0 0 8px ${C.green}` }} />
          LIVE
        </div>
      </div>

      {/* Greeting card */}
      <div style={glass({ padding: '20px 20px 22px', marginBottom: 16 })}>
        <div style={{ color: C.creamDim, fontSize: 13, marginBottom: 6, fontStyle: 'italic' }}>NJOY. Still delusional about winning?</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
          <div style={{ fontSize: 40, lineHeight: 1, filter: 'drop-shadow(0 4px 12px rgba(0,0,0,.5))' }}>🐴</div>
          <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 32, color: C.cream, letterSpacing: '.03em', lineHeight: 1 }}>NJOY</div>
        </div>
      </div>

      {/* Stats grid */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8, marginBottom: 18 }}>
        {[
          { label: 'Games', value: '15', color: C.red },
          { label: 'Wins', value: '3', color: C.green },
          { label: 'Win %', value: '23%', color: C.gold, gradient: true },
          { label: 'Best', value: '-10', color: C.cream },
        ].map(stat => (
          <div key={stat.label} style={glass({ padding: '14px 8px', textAlign: 'center', borderRadius: 14 })}>
            <div style={{
              fontFamily: "'Bebas Neue', sans-serif", fontSize: 28, lineHeight: 1,
              color: stat.color,
              ...(stat.gradient ? { background: `linear-gradient(180deg, ${C.gold}, ${C.goldDeep})`, WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' } : {}),
            }}>{stat.value}</div>
            <div style={{ fontSize: 9, color: C.creamFaint, letterSpacing: '.1em', textTransform: 'uppercase', marginTop: 6, fontWeight: 700 }}>{stat.label}</div>
          </div>
        ))}
      </div>

      {/* Unfinished business */}
      <div style={glass({ padding: '14px 16px', marginBottom: 16, border: `1px solid ${C.redGlow}`, cursor: 'pointer' })}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div>
            <div style={{ color: C.red, fontSize: 10, letterSpacing: '.12em', textTransform: 'uppercase', fontWeight: 700, marginBottom: 4 }}>● Unfinished Business</div>
            <div style={{ color: C.cream, fontSize: 14 }}>NJOY · 🪼Tyler · Gab</div>
            <div style={{ color: C.creamFaint, fontSize: 11, marginTop: 2 }}>0 rounds played</div>
          </div>
          <div style={{ color: C.red, fontSize: 18 }}>→</div>
        </div>
      </div>

      {/* Primary CTA */}
      <button style={{
        width: '100%', padding: '16px 24px', borderRadius: 14, border: 'none', cursor: 'pointer',
        background: `linear-gradient(180deg, ${C.red}, ${C.redDeep})`,
        color: '#fff', fontFamily: "'Bebas Neue', sans-serif", fontSize: 18, letterSpacing: '.06em',
        boxShadow: `0 8px 24px ${C.redGlow}, 0 2px 0 rgba(0,0,0,.3) inset, 0 1px 0 rgba(255,255,255,.18) inset`,
        marginBottom: 10,
      }}>+ New Game 🐴</button>

      {/* Rematch button — outline glass */}
      <button style={{
        width: '100%', padding: '12px 16px', borderRadius: 14, cursor: 'pointer',
        ...glass({ padding: '12px 16px', borderRadius: 14 }),
        color: C.cream, fontSize: 12, letterSpacing: '.06em', fontWeight: 600,
        marginBottom: 22,
      }}>🔁 Rematch — NJOY, Matt D, Tyler...</button>

      {/* Recent games */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 }}>
        <div style={sectionLabel}>Recent Games</div>
        <div style={{ color: C.creamDim, fontSize: 11 }}>View all →</div>
      </div>

      {[
        { players: '🐴NJOY · 🌾Matt D · 🦄Natalia · 🦄lionel · 🪼Tyler', winner: 'lionel messhri', winnerEmoji: '🦄', date: 'May 24', rounds: 6 },
        { players: '🐴NJOY · 🌾Matt D · 🪼Tyler · 🦄lionel', winner: '🪼Tyler', winnerEmoji: '🏆', date: 'May 24', rounds: 10 },
        { players: '🐴NJOY · 🦄Natalia · 🪼Tyler · 🦄lionel', winner: '🪼Tyler', winnerEmoji: '🏆', date: 'May 24', rounds: 7 },
      ].map((g, i) => (
        <div key={i} style={glass({ padding: '14px 16px', marginBottom: 8 })}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: 12 }}>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ color: C.cream, fontSize: 12, lineHeight: 1.4, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{g.players}</div>
              <div style={{ color: C.creamFaint, fontSize: 11, marginTop: 4 }}>{g.date} · {g.rounds}R</div>
            </div>
            <div style={{ textAlign: 'right' }}>
              <div style={{ color: C.gold, fontSize: 9, letterSpacing: '.1em', textTransform: 'uppercase', fontWeight: 700 }}>Winner</div>
              <div style={{ color: C.cream, fontSize: 12, marginTop: 2 }}>{g.winnerEmoji} {g.winner}</div>
            </div>
          </div>
        </div>
      ))}

      {/* Floating bottom nav */}
      <div style={{
        position: 'fixed', bottom: 16, left: '50%', transform: 'translateX(-50%)',
        ...glass({ borderRadius: 999, padding: '8px 14px' }),
        display: 'flex', gap: 4, alignItems: 'center', zIndex: 30,
      }}>
        {[
          { icon: '📊', label: 'Stats' },
          { icon: '📋', label: 'History' },
          { icon: '👤', label: 'Profile' },
        ].map((nav, i) => (
          <button key={i} style={{ background: 'transparent', border: 'none', color: C.creamDim, padding: '8px 14px', borderRadius: 999, cursor: 'pointer', fontSize: 11, letterSpacing: '.06em', display: 'flex', alignItems: 'center', gap: 5 }}>
            <span style={{ fontSize: 14 }}>{nav.icon}</span>{nav.label}
          </button>
        ))}
      </div>
    </div>
  );
}

function GameMock() {
  const players = [
    { emoji: '🐴', name: 'NJOY', total: 12, last: 5, neighs: 1, isYou: true, isLeader: false, isTurn: false, rank: 2 },
    { emoji: '🌾', name: 'Matt D', total: 8, last: 3, neighs: 0, isLeader: true, isTurn: true, rank: 1 },
    { emoji: '🦄', name: 'Ryan', total: 18, last: 7, neighs: 2, isTurn: false, rank: 3 },
  ];

  return (
    <div style={{ padding: '14px 16px 110px', maxWidth: 420, margin: '0 auto', position: 'relative' }}>
      {/* Sticky frosted header */}
      <div style={glass({ padding: '10px 14px', marginBottom: 12, display: 'flex', alignItems: 'center', justifyContent: 'space-between' })}>
        <button style={{ background: 'transparent', border: 'none', color: C.creamDim, fontSize: 12, cursor: 'pointer', letterSpacing: '.06em' }}>← Home</button>
        <div style={{ textAlign: 'center' }}>
          <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 18, color: C.cream, letterSpacing: '.04em', lineHeight: 1 }}>KEDRO</div>
          <div style={{ fontSize: 9, color: C.creamFaint, letterSpacing: '.14em', marginTop: 2, textTransform: 'uppercase', fontWeight: 700 }}>Round 4</div>
        </div>
        <button style={{
          ...glass({ borderRadius: 999, padding: '6px 12px' }),
          color: C.gold, fontSize: 11, letterSpacing: '.06em', cursor: 'pointer', fontWeight: 600,
        }}>📖 Cheat</button>
      </div>

      {/* Turn banner with subtle glow */}
      <div style={{
        ...glass({ padding: '12px 16px', borderRadius: 14, marginBottom: 14, border: `1px solid rgba(245,200,66,.25)` }),
        background: `linear-gradient(180deg, rgba(245,200,66,.10), rgba(245,200,66,.04))`,
        backdropFilter: 'blur(20px) saturate(140%)',
        textAlign: 'center',
        display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, cursor: 'pointer',
      }}>
        <span style={{ color: C.gold, fontSize: 10, letterSpacing: '.12em', textTransform: 'uppercase', fontWeight: 700 }}>Your turn</span>
        <span style={{ fontSize: 18 }}>🌾</span>
        <span style={{ color: C.cream, fontSize: 14, fontWeight: 600 }}>Matt D</span>
        <span style={{ color: C.creamFaint, fontSize: 10 }}>(tap to change)</span>
      </div>

      {/* Scoreboard cards */}
      <div style={sectionLabel}>Scoreboard</div>
      {players.sort((a, b) => a.total - b.total).map((p, i) => {
        const rank = i + 1;
        const medal = ['🥇', '🥈', '🥉'][i];
        return (
          <div key={p.name} style={{
            ...glass({ padding: '14px 16px', marginBottom: 8, borderRadius: 14 }),
            ...(p.isTurn ? {
              borderLeft: `3px solid ${C.gold}`,
              background: `linear-gradient(90deg, rgba(245,200,66,.10), rgba(22,22,30,.55) 60%)`,
              boxShadow: `0 10px 30px rgba(0,0,0,.45), 0 0 24px rgba(245,200,66,.10), 0 1px 0 rgba(255,255,255,.04) inset`,
            } : {}),
            display: 'grid', gridTemplateColumns: '28px 1fr 60px 60px', gap: 10, alignItems: 'center',
          }}>
            <div style={{ fontSize: 16, textAlign: 'center' }}>{medal || <span style={{ color: C.creamFaint, fontSize: 13 }}>{rank}</span>}</div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <div style={{ fontSize: 28, lineHeight: 1, position: 'relative', filter: 'drop-shadow(0 3px 8px rgba(0,0,0,.45))' }}>
                {p.emoji}
                {p.isLeader && <span style={{ position: 'absolute', top: -10, right: -8, fontSize: 12 }}>👑</span>}
              </div>
              <div>
                <div style={{ color: C.cream, fontSize: 13, display: 'flex', alignItems: 'center', gap: 4 }}>
                  {p.name}{p.isYou ? ' (you)' : ''}
                  {p.isTurn && <span style={{ fontSize: 12 }}>👉</span>}
                </div>
                {p.isLeader && (
                  <div style={{ fontSize: 9, color: C.gold, letterSpacing: '.1em', textTransform: 'uppercase', fontWeight: 700, marginTop: 2 }}>Leading</div>
                )}
              </div>
            </div>
            <button style={{
              ...glass({ padding: '4px 8px', borderRadius: 999 }),
              display: 'inline-flex', alignItems: 'center', gap: 4, justifySelf: 'center',
              border: p.neighs > 0 ? `1px solid ${C.redGlow}` : `1px solid ${C.border}`,
              background: p.neighs > 0 ? 'rgba(230,57,70,.10)' : C.surface,
              cursor: 'pointer',
            }}>
              <span style={{ fontSize: 13 }}>🐴</span>
              {p.neighs > 0 && <span style={{ color: C.red, fontSize: 11, fontWeight: 700 }}>{p.neighs}</span>}
            </button>
            <div style={{
              textAlign: 'right',
              fontFamily: "'Bebas Neue', sans-serif",
              fontSize: 34, lineHeight: 1, letterSpacing: '.02em',
              color: p.isLeader ? C.gold : C.cream,
              ...(p.isLeader ? { background: `linear-gradient(180deg, ${C.gold}, ${C.goldDeep})`, WebkitBackgroundClip: 'text', WebkitTextFillColor: 'transparent' } : {}),
            }}>{p.total}</div>
          </div>
        );
      })}

      {/* Round history mini */}
      <div style={{ ...glass({ padding: '14px 16px', marginTop: 14 }) }}>
        <div style={sectionLabel}>Round History</div>
        <div style={{ color: C.creamFaint, fontSize: 12, textAlign: 'center', padding: '12px 0' }}>3 rounds played — last: Matt D knocked & won 🃏</div>
      </div>

      {/* End game ghost button */}
      <button style={{
        ...glass({ padding: '12px 16px', borderRadius: 14 }),
        width: '100%', marginTop: 14, color: C.creamDim, fontSize: 12, letterSpacing: '.06em', cursor: 'pointer', fontWeight: 600,
      }}>End This Shit</button>

      {/* Floating primary CTA */}
      <button style={{
        position: 'fixed', bottom: 24, left: '50%', transform: 'translateX(-50%)',
        padding: '15px 36px', borderRadius: 999, border: 'none', cursor: 'pointer',
        background: `linear-gradient(180deg, ${C.red}, ${C.redDeep})`,
        color: '#fff', fontFamily: "'Bebas Neue', sans-serif", fontSize: 16, letterSpacing: '.06em',
        boxShadow: `0 12px 32px ${C.redGlow}, 0 2px 0 rgba(0,0,0,.3) inset, 0 1px 0 rgba(255,255,255,.18) inset`,
        zIndex: 30, whiteSpace: 'nowrap',
      }}>+ Enter Round Scores</button>
    </div>
  );
}

export default function UIMockup() {
  const [screen, setScreen] = useState('home');

  const bg = {
    minHeight: '100vh',
    background: `radial-gradient(ellipse 80% 60% at 50% 0%, ${C.bgGradFrom} 0%, ${C.bg} 60%, ${C.bgGradTo} 100%)`,
    color: C.cream,
    fontFamily: "'Barlow', system-ui, sans-serif",
    position: 'relative',
    overflow: 'hidden',
  };

  return (
    <div style={bg}>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Bebas+Neue&family=Barlow:wght@400;600;700&display=swap');
        * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
        body { margin: 0; }
        button:active { transform: scale(0.98); transition: transform 80ms; }
        button { transition: all .2s cubic-bezier(.4,0,.2,1); }
      `}</style>
      {cardSuits}

      {/* Mock toolbar */}
      <div style={{
        position: 'sticky', top: 0, zIndex: 50,
        ...glass({ borderRadius: 0, padding: '10px 14px' }),
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        borderTop: 'none', borderLeft: 'none', borderRight: 'none',
      }}>
        <div style={{ color: C.red, fontSize: 10, fontWeight: 700, letterSpacing: '.12em', textTransform: 'uppercase' }}>● Mockup — Glass + Noir</div>
        <div style={{ display: 'flex', gap: 4, background: 'rgba(0,0,0,.35)', borderRadius: 999, padding: 3 }}>
          {['home', 'game'].map(s => (
            <button key={s} onClick={() => setScreen(s)} style={{
              padding: '5px 14px', borderRadius: 999, border: 'none', cursor: 'pointer',
              background: screen === s ? `linear-gradient(180deg, ${C.red}, ${C.redDeep})` : 'transparent',
              color: screen === s ? '#fff' : C.creamDim, fontSize: 10, letterSpacing: '.08em',
              textTransform: 'uppercase', fontWeight: 700,
            }}>{s}</button>
          ))}
        </div>
      </div>

      {screen === 'home' ? <HomeMock /> : <GameMock />}
    </div>
  );
}
