// Who a claimed guest counts as on the web app's screens. No imports, so it can be tested alone.

/**
 * The seat key a claimed guest's seats count under: a guest someone claimed is that account on
 * every screen, from game 1 (the server's `claims`: guest ID → player ID, the user's own included),
 * and a guest the user claimed is the user even before the server lists it. Other seats keep
 * their own key ("p:<id>" or "g:<id>").
 */
export function claimAlias({ claims = {}, ownGuestIds = new Set(), me = null } = {}) {
  return (seatId) => {
    if (typeof seatId !== 'string' || !seatId.startsWith('g:')) return seatId;
    const guestId = seatId.slice(2);
    if (claims[guestId]) return `p:${claims[guestId]}`;
    return ownGuestIds.has(guestId) && me ? me.id : seatId;
  };
}
