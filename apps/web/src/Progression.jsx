// Badges, titles, the Hall of Shame and Kedro Wrapped on the web (design §12.6–§12.9). The server
// computes everything (GET /v1/players/:id/progression, /me/hall-of-shame, /me/wrapped) with the
// same rules as the iPhone app, so both show the same numbers. Copy is the deck's Clean level.

import { useEffect, useMemo, useState } from 'react';
import { progression } from '@kedro/shared';
import { api } from './lib/api';
import { CANNED_TAUNTS } from './lib/taunts';
import { BackBtn, C, s } from './ui';

const { BADGES, TITLES, SHAME_CATEGORY_NAMES } = progression;
const BADGE_BY_ID = new Map(BADGES.map((badge) => [badge.id, badge]));
const TITLE_BY_ID = new Map(TITLES.map((title) => [title.id, title]));

const TIER_COLOR = { gold: C.gold, red: C.red, silver: C.silver, none: C.creamDim };
const CATEGORY_ICON = { milestone: '🏁', knocking: '✊', cards: '🃏', streaks: '🔥', moments: '⚡', rivalry: '⚔️', social: '👥', learning: '📖' };

const bebas = (size, color = C.cream, extra = {}) => ({ fontFamily: "'Bebas Neue', sans-serif", fontSize: size, color, lineHeight: 1, letterSpacing: '.02em', ...extra });
const caption = { color: C.silverDim, fontSize: 11, textTransform: 'uppercase', letterSpacing: '.08em' };
/** Score format with a true minus sign. */
const num = (value) => (value < 0 ? `−${Math.abs(value)}` : String(value));
const ordinal = (n) => `${n}${(n % 100 >= 11 && n % 100 <= 13) ? 'th' : ({ 1: 'st', 2: 'nd', 3: 'rd' })[n % 10] ?? 'th'}`;
const shortDate = (iso) => new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });

export function titleName(id) {
  return TITLE_BY_ID.get(id)?.name ?? null;
}

// MARK: Home: the Wrapped slot

/** Wrapped on Home from November: ready, on its way, or how many games to go (WR-23). */
export function WrappedHomeCard({ onOpen }) {
  const [wrapped, setWrapped] = useState(null);
  useEffect(() => {
    let cancelled = false;
    api.wrapped().then((data) => { if (!cancelled) setWrapped(data); }).catch(() => {});
    return () => { cancelled = true; };
  }, []);
  if (!wrapped) return null;
  const { availability, year } = wrapped;
  if (availability.kind === 'available' && wrapped.summary) {
    return (
      <button className="btn-press" onClick={() => onOpen(wrapped)} style={{ ...s.btn('gold'), width: '100%', padding: 16, marginBottom: 12, textAlign: 'left', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <span>✨ Your {year} Kedro Wrapped is ready</span>
        <span style={{ fontSize: 18 }}>→</span>
      </button>
    );
  }
  // The other states only matter once the year is nearly done.
  if (new Date().getMonth() < 10) return null;
  const line = availability.kind === 'needsGames'
    ? `Play ${availability.needed - availability.played} more game${availability.needed - availability.played === 1 ? '' : 's'} this year to get your Wrapped. (${availability.played} of ${availability.needed})`
    : `Your ${year} Wrapped drops ${new Date(availability.at).toLocaleDateString('en-US', { month: 'long', day: 'numeric' })}. Let's see the damage.`;
  return (
    <div style={s.card({ padding: '14px 16px', marginBottom: 12, display: 'flex', gap: 12, alignItems: 'center' })}>
      <div style={{ fontSize: 26 }}>🎁</div>
      <div>
        <div style={{ ...caption, color: C.gold }}>Kedro Wrapped {year}</div>
        <div style={{ color: C.cream, fontSize: 13, marginTop: 3 }}>{line}</div>
      </div>
    </div>
  );
}

// MARK: Wrapped

const PERSONA_LINES = {
  gambler: "You knock like you've got nothing to lose. You usually do.",
  snake: 'Sitting quietly, ruining knocks.',
  accountant: 'Low, steady, joyless. Effective.',
  menace: 'More taunts than anyone. Some were even good.',
  closer: 'When you knock, people fold.',
  comeback: 'Never ahead. Always winning. Make it make sense.',
  regular: "You didn't win the most. You showed up the most.",
  wildcard: 'No pattern. No plan. No notes.',
};

function tauntText(content) {
  if (!content) return null;
  return content.kind === 'custom' ? content.text : CANNED_TAUNTS[content.id] ?? null;
}

function RatingLine({ points }) {
  if (points.length < 2) return null;
  const values = points.map((point) => point.rating);
  const min = Math.min(...values), max = Math.max(...values);
  const span = Math.max(1, max - min);
  const width = 280, height = 110;
  const path = points.map((point, i) => `${(i / (points.length - 1)) * width},${height - ((point.rating - min) / span) * (height - 10) - 5}`).join(' ');
  return (
    <svg viewBox={`0 0 ${width} ${height}`} style={{ width: '100%', maxWidth: 320, height: 'auto', margin: '18px auto 0', display: 'block' }} role="img" aria-label={`Rating from ${values[0]} to ${values.at(-1)}`}>
      <polyline points={path} fill="none" stroke={C.gold} strokeWidth="3" strokeLinejoin="round" strokeLinecap="round" />
    </svg>
  );
}

/** The story cards, in design order (§12.9). Cards with nothing to say are left out. */
function wrappedCards(w) {
  const cards = [];
  const big = (text, color = C.cream) => <div style={bebas(56, color, { marginBottom: 12 })}>{text}</div>;
  const line = (text) => <div style={{ color: C.cream, fontSize: 18, lineHeight: 1.45 }}>{text}</div>;
  const sub = (text) => <div style={{ color: C.creamDim, fontSize: 14, marginTop: 12, lineHeight: 1.4 }}>{text}</div>;

  cards.push({ key: 'cover', body: <>{big(`Your ${w.year} in Kedro.`, C.gold)}{sub("Let's see the damage.")}</> });
  const hours = Math.max(1, Math.round(w.hours));
  cards.push({ key: 'volume', body: <>{big(`${w.games} games`)}{line(`${hours} hour${hours === 1 ? '' : 's'} at the table. ${w.people} ${w.people === 1 ? 'person' : 'people'} put up with you.`)}{sub(`${w.rounds} rounds played.`)}</> });
  const finishes = Object.entries(w.finishes).sort((a, b) => Number(a[0]) - Number(b[0])).map(([position, count]) => `${ordinal(Number(position))} ×${count}`).join(' · ');
  cards.push({ key: 'record', body: <>{big(`${w.wins} wins`, C.green)}{line(`${Math.round(w.winRate * 100)}%. ${w.isWinRateHigh ? 'Respectable. Annoyingly so.' : "Wins aren't everything. Clearly."}`)}{sub(finishes)}</> });
  cards.push({
    key: 'rating',
    body: <>{big(`${w.ratingNow}`, C.gold)}{line(`Started at ${w.ratingStart}. Peaked at ${w.ratingPeak}. Finished at ${w.ratingNow}.`)}{w.currentRank ? sub(`#${w.currentRank} on the board right now.`) : null}<RatingLine points={w.ratingLine} /></>,
  });
  if (w.knocks > 0) {
    cards.push({
      key: 'knocks',
      body: <>{big(`${w.knocks} knocks`, C.red)}{line(`${Math.round(w.knockSuccess * 100)}% landed.${w.favoriteKnockValue !== null ? ` Favorite knock: ${num(w.favoriteKnockValue)}.` : ''}`)}
        {w.worstKnock ? sub(`Knocked on ${num(w.worstKnock.hand)} into a ${num(w.worstKnock.lowestOther ?? w.worstKnock.hand)} on ${shortDate(w.worstKnock.date)}. We remember.`) : null}</>,
    });
  }
  if (w.nemesis || w.victim) {
    cards.push({
      key: 'rivals',
      body: <>
        {w.nemesis ? <>{big(w.nemesis.person.displayName, C.red)}{line(`beat you ${w.nemesis.count} time${w.nemesis.count === 1 ? '' : 's'} this year. They know.`)}</> : null}
        {w.victim ? <div style={{ marginTop: w.nemesis ? 28 : 0 }}>{big(w.victim.person.displayName, C.green)}{line(`You beat them ${w.victim.count} time${w.victim.count === 1 ? '' : 's'}. Send flowers.`)}</div> : null}
      </>,
    });
  }
  cards.push({ key: 'cards', body: <>{big('Card luck')}{line(`${w.redKings} red King${w.redKings === 1 ? '' : 's'}. ${w.ghostHands} ghost hand${w.ghostHands === 1 ? '' : 's'}. One ${num(w.biggestHand)}-point disaster.`)}</> });
  if (w.tauntsSent > 0) {
    const favorite = tauntText(w.favoriteTaunt);
    cards.push({
      key: 'mouth',
      body: <>{big(`${w.tauntsSent} taunts`)}{favorite ? line(`Favorite: “${favorite}”`) : null}{w.mostTaunted ? sub(`Most taunted: ${w.mostTaunted.person.displayName}.`) : null}</>,
    });
  }
  if (w.badges.length > 0 || w.titles.length > 0) {
    cards.push({
      key: 'badges',
      body: <>
        {big(`${w.badges.length} badge${w.badges.length === 1 ? '' : 's'}`, C.gold)}
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, justifyContent: 'center', marginTop: 6 }}>
          {w.badges.map((badge) => <Chip key={badge.badge} text={BADGE_BY_ID.get(badge.badge)?.name ?? badge.badge} color={TIER_COLOR[BADGE_BY_ID.get(badge.badge)?.tier ?? 'none']} />)}
        </div>
        {w.titles.length > 0 ? sub(`Titles: ${w.titles.map(titleName).filter(Boolean).join(', ')}.`) : null}
      </>,
    });
  }
  if (w.shame.length > 0) {
    cards.push({ key: 'shame', body: <>{big(`${w.shame.length} Hall of Shame entr${w.shame.length === 1 ? 'y' : 'ies'}`, C.red)}{line('A legacy of sorts.')}{sub(w.shame.map((entry) => SHAME_CATEGORY_NAMES[entry.category]).join(' · '))}</> });
  }
  cards.push({ key: 'persona', body: <>{big(w.persona.name.toUpperCase(), C.gold)}{line(PERSONA_LINES[w.persona.id] ?? '')}</>, persona: true });
  return cards;
}

function Chip({ text, color }) {
  return <span style={{ border: `1px solid ${color}`, color, borderRadius: 999, padding: '4px 10px', fontSize: 11, fontWeight: 700, letterSpacing: '.04em' }}>{text}</span>;
}

/** Story-style Wrapped: tap the right side for the next card, the left to go back. */
export function WrappedScreen({ wrapped, user, onBack }) {
  const w = wrapped.summary;
  const cards = useMemo(() => wrappedCards(w), [w]);
  const [index, setIndex] = useState(0);
  const [shared, setShared] = useState('');
  const card = cards[index];
  const last = index === cards.length - 1;

  async function share() {
    const text = `My ${w.year} in Kedro: ${w.persona.name.toUpperCase()}. ${w.games} games, ${w.wins} wins, rating ${w.ratingNow}. playkedro.com`;
    try {
      if (navigator.share) await navigator.share({ text });
      else {
        await navigator.clipboard.writeText(text);
        setShared('Copied. Go brag.');
      }
    } catch { /* closed the share sheet */ }
  }

  return (
    <div className="screen" style={{ paddingTop: 20, paddingBottom: 40, minHeight: '100vh', display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', gap: 4, marginBottom: 14 }}>
        {cards.map((entry, i) => <div key={entry.key} style={{ flex: 1, height: 3, borderRadius: 2, background: i <= index ? C.gold : C.border }} />)}
      </div>
      <BackBtn onBack={onBack} label="Done" />
      <div
        role="button"
        tabIndex={0}
        aria-label={last ? 'Last card' : 'Next card'}
        onClick={(event) => {
          const rect = event.currentTarget.getBoundingClientRect();
          if (event.clientX - rect.left < rect.width / 3) setIndex((i) => Math.max(0, i - 1));
          else setIndex((i) => Math.min(cards.length - 1, i + 1));
        }}
        onKeyDown={(event) => {
          if (event.key === 'ArrowLeft') setIndex((i) => Math.max(0, i - 1));
          if (event.key === 'ArrowRight' || event.key === ' ') setIndex((i) => Math.min(cards.length - 1, i + 1));
        }}
        style={{ ...s.card({ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', textAlign: 'center', padding: '40px 24px', marginTop: 8, cursor: 'pointer', minHeight: 380 }) }}
      >
        <div key={card.key} style={{ animation: 'fadeIn .35s ease' }}>{card.body}</div>
      </div>
      <div style={{ display: 'flex', gap: 10, marginTop: 14 }}>
        {last
          ? <button className="btn-red btn-press" onClick={share} style={s.btn('red', { flex: 1 })}>Share your year</button>
          : <button className="btn-press" onClick={() => setIndex((i) => i + 1)} style={s.btn('outline', { flex: 1 })}>Next</button>}
      </div>
      {shared && <div style={{ color: C.creamDim, fontSize: 12, textAlign: 'center', marginTop: 8 }}>{shared}</div>}
      <div style={{ color: C.creamFaint, fontSize: 11, textAlign: 'center', marginTop: 10 }}>{user.username} · {w.year}</div>
    </div>
  );
}

// MARK: Profile: badges and titles

/** Badges, next up and titles for a player (the caller's own: with the title picker). */
export function ProgressionCard({ playerId, isMe, onChooseTitle, onHallOfShame }) {
  const [data, setData] = useState(null);
  const [error, setError] = useState('');
  const [selected, setSelected] = useState(null);
  const [picking, setPicking] = useState(false);
  useEffect(() => {
    let cancelled = false;
    api.progression(playerId).then((body) => { if (!cancelled) setData(body); }).catch(() => { if (!cancelled) setError('Badges are taking a breather. Try again in a bit.'); });
    return () => { cancelled = true; };
  }, [playerId]);

  if (error) return <div style={s.card({ marginBottom: 14, color: C.creamDim, fontSize: 13 })}>{error}</div>;
  if (!data) return null;
  const earned = new Map(data.badges.map((badge) => [badge.badge, badge]));
  const available = TITLES.filter((title) => data.titles.earned.includes(title.id) || data.titles.held.includes(title.id));
  const detail = selected ? BADGE_BY_ID.get(selected) : null;
  const detailEarned = selected ? earned.get(selected) : null;

  async function choose(titleId) {
    setPicking(false);
    await onChooseTitle?.(titleId);
    setData((current) => current && { ...current, titles: { ...current.titles, display: titleId } });
  }

  return (
    <>
      <div style={s.card({ marginBottom: 10, padding: '14px 16px' })}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div>
            <div style={caption}>Title</div>
            <div style={{ ...bebas(24, data.titles.display ? C.gold : C.creamDim), marginTop: 4 }}>{titleName(data.titles.display) ?? 'No title'}</div>
            {data.titles.display && <div style={{ color: C.creamDim, fontSize: 12, marginTop: 4 }}>{TITLE_BY_ID.get(data.titles.display)?.tagline}</div>}
          </div>
          {isMe && <button className="btn-press" onClick={() => setPicking((open) => !open)} style={s.btn('ghost', { fontSize: 11 })}>{picking ? 'Close' : 'Change'}</button>}
        </div>
        {picking && (
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 12 }}>
            <button className="btn-press" onClick={() => choose(null)} style={s.btn('outline', { padding: '6px 12px', fontSize: 11 })}>No title</button>
            {available.map((title) => (
              <button key={title.id} className="btn-press" onClick={() => choose(title.id)} title={title.tagline}
                style={s.btn(title.id === data.titles.display ? 'gold' : 'outline', { padding: '6px 12px', fontSize: 11 })}>
                {title.name}{data.titles.held.includes(title.id) ? ' ★' : ''}
              </button>
            ))}
            <div style={{ color: C.creamFaint, fontSize: 11, width: '100%', marginTop: 4 }}>★ Held titles can be taken off you.</div>
          </div>
        )}
      </div>

      <div style={s.card({ marginBottom: 10 })}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 12 }}>
          <div style={caption}>Badges</div>
          <div style={{ color: C.creamDim, fontSize: 12 }}>{data.badges.length} of {BADGES.length}</div>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(64px, 1fr))', gap: 8 }}>
          {BADGES.map((badge) => {
            const has = earned.has(badge.id);
            const secret = badge.isSecret && !has;
            const color = has ? TIER_COLOR[badge.tier] : C.border;
            return (
              <button key={badge.id} onClick={() => setSelected(selected === badge.id ? null : badge.id)} aria-label={secret ? 'Secret badge' : `${badge.name}${has ? ', earned' : ''}`}
                style={{ background: 'transparent', border: 'none', padding: 0, cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, opacity: has ? 1 : 0.4 }}>
                <div style={{ width: 46, height: 46, borderRadius: '50%', border: `2px solid ${color}`, display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 20, background: has ? 'rgba(255,255,255,.04)' : 'transparent', boxShadow: selected === badge.id ? `0 0 0 2px ${C.cream}` : 'none' }}>
                  {secret ? '?' : CATEGORY_ICON[badge.category]}
                </div>
                <div style={{ color: has ? C.cream : C.creamDim, fontSize: 9, lineHeight: 1.2, textAlign: 'center' }}>{secret ? '???' : badge.name}</div>
              </button>
            );
          })}
        </div>
        {detail && (
          <div style={{ borderTop: `1px solid ${C.border}`, marginTop: 12, paddingTop: 10, fontSize: 13 }}>
            <div style={{ color: TIER_COLOR[detail.tier], fontWeight: 700 }}>{detail.isSecret && !detailEarned ? 'Secret badge' : detail.name}</div>
            <div style={{ color: C.creamDim, marginTop: 2 }}>
              {detail.isSecret && !detailEarned ? 'Earn it to find out.' : detail.rule.charAt(0).toUpperCase() + detail.rule.slice(1) + '.'}
              {detailEarned?.earnedAt ? ` Earned ${shortDate(detailEarned.earnedAt)}${detailEarned.tableWord ? ` at ${detailEarned.tableWord}` : ''}.` : ''}
            </div>
          </div>
        )}
        {data.nextUp.length > 0 && (
          <div style={{ borderTop: `1px solid ${C.border}`, marginTop: 12, paddingTop: 10 }}>
            {data.nextUp.map((entry) => (
              <div key={entry.badge} style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: 12, padding: '4px 0' }}>
                <span style={{ color: C.cream }}>Next up: {BADGE_BY_ID.get(entry.badge)?.name}</span>
                <span style={{ color: C.creamDim }}>{Math.min(entry.value, entry.target)} of {entry.target}</span>
              </div>
            ))}
          </div>
        )}
      </div>

      {isMe && onHallOfShame && (
        <button className="btn-press" onClick={onHallOfShame} style={{ ...s.card({ padding: '12px 16px', marginBottom: 14, display: 'flex', justifyContent: 'space-between', alignItems: 'center', width: '100%', cursor: 'pointer', textAlign: 'left' }) }}>
          <span style={{ color: C.cream, fontSize: 13 }}>💀 Hall of Shame</span>
          <span style={{ color: C.creamDim, fontSize: 12 }}>{data.hallOfShameEntries > 0 ? `You're in it ${data.hallOfShameEntries} time${data.hallOfShameEntries === 1 ? '' : 's'}` : "You're not in here. Suspicious."} →</span>
        </button>
      )}
    </>
  );
}

// MARK: Hall of Shame

const SHAME_ROAST = {
  worstHand: (e) => `${e.person.displayName} held ${num(e.value)}. That's not a hand, that's a yard sale.`,
  worstKnock: (e) => `Knocked on ${num(e.hand ?? 0)} into a ${num(e.low ?? 0)}. Historians will study it.`,
  biggestLoss: (e) => `${num(e.value)} points in one game. A personal best, in the wrong direction.`,
  bottleJob: (e) => `Up by ${e.value}. Didn't win.${e.finishPosition ? ` Finished ${ordinal(e.finishPosition)}.` : ''}`,
  ateIt: (e) => `${e.value} failed knocks in one game. Commitment to the bit.`,
  deepestHole: (e) => `${e.value} behind the leader at one point. Spelunking.`,
};

export function HallOfShameScreen({ onBack }) {
  const [scope, setScope] = useState('yourPeople');
  const [data, setData] = useState(null);
  const [error, setError] = useState('');
  useEffect(() => {
    let cancelled = false;
    setData(null);
    api.hallOfShame(scope).then((body) => { if (!cancelled) setData(body); }).catch(() => { if (!cancelled) setError('The Hall is closed for cleaning. Try again soon.'); });
    return () => { cancelled = true; };
  }, [scope]);
  const empty = data && data.boards.every((board) => board.entries.length === 0);

  return (
    <div className="screen" style={{ paddingTop: 28, paddingBottom: 60 }}>
      <BackBtn onBack={onBack} />
      <div style={{ textAlign: 'center', margin: '16px 0 18px' }}>
        <div style={bebas(36)}>💀 Hall of Shame</div>
        <div style={{ color: C.creamDim, fontSize: 13, marginTop: 6 }}>The worst moments among your people. Moments, not people. Mostly.</div>
      </div>
      <div style={{ display: 'flex', gap: 6, justifyContent: 'center', marginBottom: 16 }}>
        {[['yourPeople', 'Your people'], ['yours', 'Yours']].map(([value, label]) => (
          <button key={value} className="btn-press" onClick={() => setScope(value)} aria-pressed={scope === value}
            style={s.btn(scope === value ? 'red' : 'outline', { padding: '8px 16px', fontSize: 11 })}>{label}</button>
        ))}
      </div>
      {error && <div style={{ color: C.creamDim, textAlign: 'center', fontSize: 13 }}>{error}</div>}
      {empty && <div style={{ color: C.creamDim, textAlign: 'center', fontSize: 14, marginTop: 30 }}>{scope === 'yours' ? "You're not in here. Suspicious." : 'Nobody here yet. Give it a game or two.'}</div>}
      {data && !empty && data.boards.filter((board) => board.entries.length > 0).map((board) => (
        <div key={board.category} style={s.card({ marginBottom: 12 })}>
          <div style={{ ...caption, marginBottom: 10 }}>{board.name}</div>
          {board.entries.map((entry, i) => (
            <div key={`${entry.gameId}-${entry.person.id}-${entry.roundNumber ?? 0}`} style={{ display: 'flex', gap: 12, padding: '8px 0', borderTop: i === 0 ? 'none' : `1px solid ${C.border}` }}>
              <div style={bebas(26, i === 0 ? C.red : C.creamDim, { width: 20, textAlign: 'center' })}>{i + 1}</div>
              <div style={{ flex: 1 }}>
                <div style={{ color: C.cream, fontSize: 14 }}>{entry.person.displayName}</div>
                {i === 0 && <div style={{ color: C.creamDim, fontSize: 12, marginTop: 2 }}>{SHAME_ROAST[board.category]?.(entry)}</div>}
                <div style={{ color: C.creamFaint, fontSize: 11, marginTop: 2 }}>{entry.tableWord}{entry.tableWord.includes(shortDate(entry.finishedAt)) ? '' : ` · ${shortDate(entry.finishedAt)}`}{entry.roundNumber ? ` · Round ${entry.roundNumber}` : ''}</div>
              </div>
              <div style={bebas(24, i === 0 ? C.red : C.cream)}>{num(entry.value)}</div>
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}
