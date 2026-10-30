// Test harness: the real app on the in-memory store, with `dev:<uuid>` tokens.

import type { UpdateProfileRequest, WireOperation } from '@kedro/shared'
import { createApp } from '../src/app.ts'
import { DevTokenVerifier } from '../src/auth.ts'
import { StubLiveActivityBroadcaster } from '../src/push/liveActivity.ts'
import { MemoryStore } from '../src/store/memory.ts'
import { INVITE_WINDOW_MS, inviteCode } from '../src/services/invites.ts'

export { fixedUUID, ids, sampleSeats, sampleWireOperations, seats, OperationBuilder, SAMPLE_START_MS } from '../../../packages/shared/test/fixtures/sampleGame.ts'

export function harness(options: { now?: () => number } = {}) {
  const store = new MemoryStore()
  const broadcaster = new StubLiveActivityBroadcaster()
  const logs: string[] = []
  const { app, services } = createApp({
    store,
    verifier: new DevTokenVerifier(),
    broadcaster,
    now: options.now,
    log: (message) => logs.push(message),
  })

  async function call<T = any>(method: string, path: string, as: string | null, body?: unknown): Promise<{ status: number; body: T }> {
    const headers: Record<string, string> = {}
    if (as) headers.authorization = `Bearer dev:${as}`
    if (body !== undefined) headers['content-type'] = 'application/json'
    const response = await app.request(path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) })
    const text = await response.text()
    return { status: response.status, body: (text ? JSON.parse(text) : null) as T }
  }

  return {
    app,
    store,
    services,
    broadcaster,
    logs,
    call,
    get: <T = any>(path: string, as: string | null) => call<T>('GET', path, as),
    post: <T = any>(path: string, as: string | null, body: unknown) => call<T>('POST', path, as, body),
    put: <T = any>(path: string, as: string | null, body: unknown) => call<T>('PUT', path, as, body),
    del: <T = any>(path: string, as: string | null) => call<T>('DELETE', path, as),
    /** Creates a profile for a player. */
    async profile(id: string, displayName: string, handle: string) {
      const update: UpdateProfileRequest = { displayName, handle, avatar: { kind: 'emoji', emoji: '🦊', colorIndex: 1 } }
      const result = await call('PUT', '/v1/players/me', id, update)
      if (result.status !== 200) throw new Error(`profile ${handle}: ${JSON.stringify(result.body)}`)
      return result.body
    },
    async upload(as: string, ops: WireOperation[], invites?: Record<string, string>) {
      return call<{ accepted: string[]; duplicates: string[]; rejected: { opId: string | null; reason: string }[] }>('POST', '/v1/ops', as, invites ? { ops, invites } : { ops })
    },
    /** Registers a table invite key as `as` (seated) and returns a function making the current code. */
    async inviteKey(as: string, gameId: string) {
      const key = Buffer.alloc(32, 7)
      const result = await call('PUT', `/v1/games/${gameId}/invite-key`, as, { key: key.toString('base64url') })
      if (result.status !== 200) throw new Error(`invite key: ${JSON.stringify(result.body)}`)
      return (atMs: number = Date.now()) => inviteCode(key, gameId, Math.floor(atMs / INVITE_WINDOW_MS))
    },
  }
}

/** A copy of a game's ops under a new game ID, op IDs and start time (for building history). */
export function cloneGame(ops: WireOperation[], gameId: string, offsetMs: number): WireOperation[] {
  return ops.map((op, index) => ({
    ...structuredClone(op),
    gameId,
    opId: uuidFrom(gameId, index + 1),
    hlc: { ...op.hlc, wallMs: op.hlc.wallMs + offsetMs },
  }))
}

function uuidFrom(gameId: string, sequence: number): string {
  return `${gameId.slice(0, 24)}${sequence.toString(16).padStart(12, '0')}`
}

/** `0000000n-0000-4000-9000-000000000000`: game IDs for generated history. */
export function gameUUID(number: number): string {
  return `${number.toString(16).padStart(8, '0')}-0000-4000-9000-000000000000`
}
