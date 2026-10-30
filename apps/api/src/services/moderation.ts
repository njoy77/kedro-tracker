// The server half of the custom-taunt filter (design §8.3): POST /v1/taunts/check, and the
// re-check of custom taunts that arrive through POST /v1/ops.
//
// PLACEHOLDER MECHANISM: terms come from the `taunt_blocklist` table (plus the empty
// DEFAULT_BLOCKED_TERMS in packages/shared). The list ships empty; curating it and reviewing
// reports needs an owner before launch (design §18 item 5).

import { DEFAULT_BLOCKED_TERMS, checkTaunt, compileBlocklist, type CompiledBlocklist, type TauntCheck } from '@kedro/shared'
import type { Store } from '../store/types.ts'

const CACHE_MS = 5 * 60 * 1000

export class TauntFilter {
  private compiled: CompiledBlocklist | null = null
  private loadedAt = 0

  constructor(
    private readonly store: Store,
    private readonly now: () => number = Date.now,
  ) {}

  async check(text: string): Promise<TauntCheck> {
    return checkTaunt(text, await this.blocklist())
  }

  /** Drops the cached list (after an admin edits the table). */
  invalidate(): void {
    this.compiled = null
  }

  private async blocklist(): Promise<CompiledBlocklist> {
    if (this.compiled && this.now() - this.loadedAt < CACHE_MS) return this.compiled
    const terms = await this.store.blocklistTerms()
    this.compiled = compileBlocklist([...DEFAULT_BLOCKED_TERMS, ...terms])
    this.loadedAt = this.now()
    return this.compiled
  }
}
