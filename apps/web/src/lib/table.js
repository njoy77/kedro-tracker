// Games as operation logs, the same way the iOS app keeps them (packages/shared fold.ts,
// operations.ts): this device writes ops with a hybrid logical clock, uploads them to the API, and
// folds every game's log into the state the screens show. Ops wait in localStorage until the API
// has them, so a round saved without signal isn't lost.
//
// The screens still read the web app's original shapes (`toWebGame`): players are keyed by seat ID
// ("p:<uuid>" or "g:<uuid>"), with a claimed guest's seats keyed as the account that claimed it.

import {
  PLANNED_ROUNDS_LIMITS,
  compareHlc,
  dealerForRound,
  foldGame,
  gameTotals,
  hlcString,
  isInherentKnock,
  outcomeOf,
  parseOperation,
  scoresOf,
  seatIdOf,
  standings,
} from '@kedro/shared';
import { api } from './api';

const DEVICE_KEY = 'kedro_device_id';
const PENDING_KEY = 'kedro_pending_ops';

export const deviceId = (() => {
  try {
    let id = localStorage.getItem(DEVICE_KEY);
    if (!id) { id = crypto.randomUUID(); localStorage.setItem(DEVICE_KEY, id); }
    return id;
  } catch {
    return crypto.randomUUID();
  }
})();

// MARK: Clock

const clock = { wallMs: 0, counter: 0 };

/** Moves the clock past an op from another device, so this device's next op sorts after it. */
function observe(hlc) {
  if (hlc.wallMs > clock.wallMs || (hlc.wallMs === clock.wallMs && hlc.counter > clock.counter)) {
    clock.wallMs = hlc.wallMs;
    clock.counter = hlc.counter;
  }
}

function tick() {
  const now = Date.now();
  if (now > clock.wallMs) { clock.wallMs = now; clock.counter = 0; }
  else clock.counter += 1;
  return { wallMs: clock.wallMs, counter: clock.counter, node: deviceId };
}

// MARK: Store

function loadPending() {
  try { return JSON.parse(localStorage.getItem(PENDING_KEY) || '[]'); } catch { return []; }
}

function savePending(ops) {
  try { localStorage.setItem(PENDING_KEY, JSON.stringify(ops)); } catch {}
}

export class GameLog {
  constructor() {
    /** gameId → (opId → wire op) the server has. */
    this.server = new Map();
    /** Ops written here that the server hasn't confirmed yet, oldest first. */
    this.pending = loadPending();
    for (const op of this.pending) observe(op.hlc);
    /** opId → reason, for ops the server refused. */
    this.rejected = new Map();
  }

  gameIds() {
    return [...new Set([...this.server.keys(), ...this.pending.map((op) => op.gameId)])];
  }

  /** Fetches a game's ops newer than the newest one already here. */
  async pull(gameId) {
    const known = this.server.get(gameId) ?? new Map();
    let after;
    for (const op of known.values()) if (!after || compareHlc(op.hlc, after) > 0) after = op.hlc;
    for (;;) {
      const { ops } = await api.ops(gameId, after ? hlcString(after) : undefined);
      for (const op of ops) { known.set(op.opId, op); observe(op.hlc); }
      this.server.set(gameId, known);
      if (ops.length < 2000) return;
      after = ops[ops.length - 1].hlc;
    }
  }

  folded(gameId) {
    const wires = [...(this.server.get(gameId)?.values() ?? []), ...this.pending.filter((op) => op.gameId === gameId)];
    const operations = [];
    for (const wire of wires) {
      const parsed = parseOperation(wire);
      if (parsed.ok) operations.push(parsed.value.operation);
    }
    return foldGame(operations, gameId);
  }

  /** Writes ops for one game, then uploads everything pending. */
  async write(gameId, actorPlayerId, entries) {
    const ops = entries.map(([type, payload]) => ({ opId: crypto.randomUUID(), gameId, deviceId, hlc: tick(), actorPlayerId, type, payload }));
    this.pending.push(...ops);
    savePending(this.pending);
    await this.flush();
    return ops;
  }

  /**
   * Uploads pending ops. Accepted, duplicate and rejected ops are all settled (the API's contract);
   * rejected ones are remembered so the screen can say so. Returns false while offline.
   */
  async flush() {
    while (this.pending.length > 0) {
      const batch = this.pending.slice(0, 500);
      let result;
      try {
        result = await api.postOps(batch);
      } catch (error) {
        if (error.status && error.status < 500 && error.status !== 401) {
          // The server will never take this batch as it is; drop it rather than retry forever.
          for (const op of batch) this.rejected.set(op.opId, error.code || 'invalid');
        } else {
          return false;
        }
      }
      const settled = new Set([...(result?.accepted ?? []), ...(result?.duplicates ?? []), ...(result?.rejected ?? []).map((row) => row.opId)]);
      for (const row of result?.rejected ?? []) this.rejected.set(row.opId, row.reason);
      for (const op of batch) {
        if (!result || settled.has(op.opId)) {
          const known = this.server.get(op.gameId) ?? new Map();
          if (!this.rejected.has(op.opId)) known.set(op.opId, op);
          this.server.set(op.gameId, known);
        }
      }
      this.pending = this.pending.filter((op) => !batch.includes(op));
      savePending(this.pending);
    }
    return true;
  }
}

// MARK: Writing a game (this device keeps score)

export function emojiOf(avatar) {
  if (avatar?.kind === 'emoji') return avatar.emoji;
  if (avatar?.kind === 'photo') return '🙂';
  return '👤';
}

function seatFor(person, order) {
  const seat = { player: person.ref, displayName: person.username.slice(0, 40), order };
  if (person.handle) seat.handle = person.handle;
  if (person.avatar) seat.avatar = person.avatar;
  // A guest keeps the emoji the table knows them by.
  else if (person.emoji && person.emoji !== '👤') seat.avatar = { kind: 'emoji', emoji: person.emoji, colorIndex: 0 };
  return seat;
}

/**
 * Creates and starts a game with these people in clockwise order (`ref` is {kind, id}). The
 * creator keeps score. A new guest gets a fresh ID; a returning one keeps theirs.
 */
export async function createGame(log, me, people, firstDealerIndex) {
  const gameId = crypto.randomUUID();
  const seatIds = people.map((person) => seatIdOf(person.ref));
  const mySeat = seatIdOf({ kind: 'player', id: me.playerId });
  const firstDealer = seatIds[firstDealerIndex] ?? seatIds[0];
  const tableWord = `Web · ${new Intl.DateTimeFormat('en-US', { month: 'short', day: 'numeric' }).format(new Date())}`;
  await log.write(gameId, me.playerId, [
    ['GameCreated', { config: { plannedRounds: PLANNED_ROUNDS_LIMITS.max, scoringMode: 'scorekeeper', tableWord, firstDealerSeat: firstDealer, scorekeeperSeat: mySeat }, host: mySeat }],
    ...people.map((person, order) => ['PlayerSeated', { seat: seatFor(person, order) }]),
    ['GameStarted', { seatOrder: seatIds, firstDealer }],
  ]);
  return gameId;
}

/** A round from hand values and the knocker (seat IDs). The knock result follows from the hands. */
export function roundOf(number, hands, knocker, inherent) {
  const round = { number, hands, knocker };
  if (inherent) round.inherent = knocker;
  return round;
}

export const recordRound = (log, me, gameId, round) => log.write(gameId, me.playerId, [['RoundRecorded', { round }]]);
export const editRound = (log, me, gameId, round) => log.write(gameId, me.playerId, [['RoundEdited', { round }]]);
export const setDealer = (log, me, gameId, roundNumber, dealer) => log.write(gameId, me.playerId, [['DealerChanged', { roundNumber, dealer }]]);
export const abandonGame = (log, me, gameId) => log.write(gameId, me.playerId, [['GameAbandoned', {}]]);

/** Finishes a game where it stands: the rounds played become the plan, so it reads as completed. */
export function finishGame(log, me, game) {
  const rounds = game.rounds;
  return log.write(game.gameId, me.playerId, [
    ['RoundsChanged', { plannedRounds: Math.max(PLANNED_ROUNDS_LIMITS.min, rounds.length) }],
    ['GameFinished', { reason: 'completed', finalRounds: rounds }],
  ]);
}

// MARK: Reading a game (the web app's original shape)

const webStatus = { lobby: 'active', active: 'active', finished: 'complete', abandoned: 'abandoned' };

/**
 * A folded game in the shape the screens use. `alias` maps a seat ID to the key the screens
 * compare (a guest the user claimed becomes the user).
 */
export function toWebGame(game, alias = (seatId) => seatId) {
  const totals = gameTotals(game);
  const winner = game.status === 'finished' ? standings(game).find((row) => row.isWinner) : null;
  const seatIds = game.seats.map((seat) => seatIdOf(seat.player));
  const dealer = dealerForRound(game, game.rounds.length + 1);
  return {
    id: game.gameId,
    status: webStatus[game.status],
    startedAt: game.startedAtMs ?? game.createdAtMs,
    endedAt: game.finishedAtMs ?? game.abandonedAtMs ?? game.startedAtMs ?? game.createdAtMs,
    tableWord: game.config.tableWord,
    players: game.seats.map((seat) => {
      const seatId = seatIdOf(seat.player);
      return { id: alias(seatId), seatId, username: seat.displayName, emoji: emojiOf(seat.avatar), total: totals[seatId] ?? 0, kind: seat.player.kind };
    }),
    rounds: game.rounds.map((round) => {
      const scores = scoresOf(round);
      const outcome = round.knocker ? outcomeOf(round) : null;
      return {
        id: `${game.gameId}-${round.number}`,
        number: round.number,
        hands: round.hands,
        knockerSeat: round.knocker ?? null,
        scores: Object.entries(scores).map(([seatId, score]) => ({ playerId: alias(seatId), seatId, score })),
        knockedBy: round.knocker ? alias(round.knocker) : null,
        knockerWon: outcome === 'landed',
        knockResult: outcome,
        inherentKnock: isInherentKnock(round) ? alias(round.knocker) : null,
      };
    }),
    winnerId: winner ? alias(seatIdOf(winner.seat.player)) : null,
    currentTurnIndex: Math.max(0, seatIds.indexOf(dealer)),
    neighCounts: {},
    folded: game,
  };
}
