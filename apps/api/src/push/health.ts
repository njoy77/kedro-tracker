// GET /health/push: proves the API can reach APNs from where it runs (HTTP/2 to Apple, the
// provider token, the key) without a game or a device. It lists the app's open broadcast
// channels on the channel management host, which sends nothing to any phone.
//
// The route is public, so the answer is cached per instance: at most one request to Apple every
// few minutes however often it is called. The channel count also shows channels piling up
// (Apple allows 10,000 per app per environment; ended games delete theirs).

import type { PushHealthResponse } from '@kedro/shared'
import type { Apns } from './apns.ts'

export const PUSH_HEALTH_CACHE_MS = 5 * 60 * 1000

export class PushHealth {
  private cached: { atMs: number; result: Promise<PushHealthResponse> } | null = null
  private readonly now: () => number

  constructor(
    private readonly apns: Apns | undefined,
    now: () => number = Date.now,
  ) {
    this.now = now
  }

  check(): Promise<PushHealthResponse> {
    const nowMs = this.now()
    if (this.cached && nowMs - this.cached.atMs < PUSH_HEALTH_CACHE_MS) return this.cached.result
    const result = this.probe(nowMs)
    this.cached = { atMs: nowMs, result }
    return result
  }

  private async probe(nowMs: number): Promise<PushHealthResponse> {
    const apns = this.apns
    if (!apns) return { apns: 'unconfigured' }
    const checkedAt = new Date(nowMs).toISOString()
    try {
      const channels = await apns.listChannels()
      return { apns: 'ok', environment: apns.environment, channels: channels.length, checkedAt }
    } catch (error) {
      return { apns: 'error', environment: apns.environment, error: error instanceof Error ? error.message : String(error), checkedAt }
    }
  }
}
