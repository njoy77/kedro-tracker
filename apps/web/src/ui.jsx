// The web app's colors, glass styles and small shared components (used by App.jsx and the
// progression screens).

export const C = {
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

export const GLASS_SHADOW = '0 10px 30px rgba(0,0,0,.45), 0 1px 0 rgba(255,255,255,.04) inset, 0 0 0 1px rgba(0,0,0,.4)';

export const s = {
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

export function StatBox({ label, value, accent }) {
  return (
    <div style={s.card({ padding: '14px 16px', textAlign: 'center', flex: 1, minWidth: 0 })}>
      <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 30, color: accent || C.red, lineHeight: 1 }}>{value}</div>
      <div style={{ fontSize: 10, color: C.creamDim, marginTop: 4, textTransform: 'uppercase', letterSpacing: '.08em' }}>{label}</div>
    </div>
  );
}

export function BackBtn({ onBack, label = 'Back' }) {
  return (
    <button onClick={onBack} style={s.btn('ghost', { display: 'flex', alignItems: 'center', gap: 6, paddingLeft: 0, fontSize: 12 })}>
      ← {label}
    </button>
  );
}
