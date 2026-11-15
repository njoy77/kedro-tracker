// The Kedro API client (contract: packages/shared/src/api.ts). Every /v1 call carries the signed-in
// player's token from auth.js.

import { getAccessToken } from './auth';

// Local development talks to `bun run --filter '@kedro/api' dev:seed`; builds talk to production.
// VITE_KEDRO_API_URL overrides either (e.g. a preview API).
export const API_URL = (import.meta.env.VITE_KEDRO_API_URL || (import.meta.env.DEV ? 'http://localhost:8787' : 'https://api.playkedro.com')).replace(/\/+$/, '');

export class ApiError extends Error {
  constructor(status, code, message) {
    super(message || code || `HTTP ${status}`);
    this.status = status;
    this.code = code;
  }
}

async function request(method, path, body) {
  const token = await getAccessToken();
  const headers = {};
  if (token) headers.authorization = `Bearer ${token}`;
  if (body !== undefined) headers['content-type'] = 'application/json';
  const response = await fetch(`${API_URL}${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await response.text();
  const json = text ? JSON.parse(text) : null;
  if (!response.ok) throw new ApiError(response.status, json?.error, json?.message);
  return json;
}

/** The browser's IANA time zone (the API falls back to New York without one). */
const timeZone = () => {
  try { return Intl.DateTimeFormat().resolvedOptions().timeZone; } catch { return undefined; }
};

const query = (params) => {
  const entries = Object.entries(params).filter(([, value]) => value !== undefined && value !== null && value !== '');
  return entries.length ? `?${new URLSearchParams(entries)}` : '';
};

export const api = {
  me: () => request('GET', '/v1/players/me'),
  saveProfile: (profile) => request('PUT', '/v1/players/me', profile),
  handleAvailable: (handle) => request('GET', `/v1/handles/${encodeURIComponent(handle)}`),
  directory: (cursor) => request('GET', `/v1/players${query({ cursor, limit: 100 })}`),
  guests: (name) => request('GET', `/v1/players/me/guests${query({ name })}`),
  myGames: () => request('GET', '/v1/players/me/games'),
  // `features`: the op types this app decodes beyond the original set (the API leaves the rest out).
  ops: (gameId, after) => request('GET', `/v1/games/${gameId}/ops${query({ after, features: 'neighs' })}`),
  postOps: (ops) => request('POST', '/v1/ops', { ops }),
  profile: (playerId) => request('GET', `/v1/players/${playerId}/profile`),
  leaderboard: (sort) => request('GET', `/v1/leaderboard${query({ scope: 'global', sort, limit: 200 })}`),
  claim: (claimToken) => request('POST', '/v1/claims', { claimToken }),
  // Progression: badges, titles, the Hall of Shame and Wrapped (the server replays the same games
  // the iPhone app does). `tz` puts years and December 1 in the player's own calendar.
  progression: (playerId = 'me') => request('GET', `/v1/players/${playerId}/progression${query({ tz: timeZone() })}`),
  hallOfShame: (scope) => request('GET', `/v1/players/me/hall-of-shame${query({ scope, tz: timeZone() })}`),
  wrapped: (year) => request('GET', `/v1/players/me/wrapped${query({ year, tz: timeZone() })}`),
  /** Local only (`dev:seed`): the seeded test accounts. */
  devAccounts: () => fetch(`${API_URL}/dev/accounts`).then((response) => (response.ok ? response.json() : { accounts: [] })),
};

/** Every player in the directory (A–Z), following the cursor. */
export async function allPlayers() {
  const players = [];
  let cursor;
  do {
    const page = await api.directory(cursor);
    players.push(...page.players);
    cursor = page.next ?? undefined;
  } while (cursor);
  return players;
}
