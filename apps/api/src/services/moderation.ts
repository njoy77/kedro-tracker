// The server half of the custom-taunt filter (design §8.3): POST /v1/taunts/check, and the
// re-check of custom taunts that arrive through POST /v1/ops.
//
// Two lists, either one blocks:
// - the launch list, as SHA-256 hashes of normalized terms (blockedTermHashes.ts, the same set the
//   iOS app bundles), matched exactly like the phone's filter (`hashedCandidates`);
// - plain terms from the `taunt_blocklist` table (plus packages/shared DEFAULT_BLOCKED_TERMS), so
//   moderators can add terms without an app release.
// The list and the report-review process still need a named owner before launch (design §18.5).

import { createHash } from 'node:crypto'
import { DEFAULT_BLOCKED_TERMS, checkTaunt, compileBlocklist, type CompiledBlocklist, type TauntCheck } from '@kedro/shared'
import type { Store } from '../store/types.ts'
import { BLOCKED_TERM_HASHES } from './blockedTermHashes.ts'

const CACHE_MS = 5 * 60 * 1000

export class TauntFilter {
  private compiled: CompiledBlocklist | null = null
  private loadedAt = 0

  constructor(
    private readonly store: Store,
    private readonly now: () => number = Date.now,
    private readonly hashes: ReadonlySet<string> = new Set(BLOCKED_TERM_HASHES),
  ) {}

  async check(text: string): Promise<TauntCheck> {
    const plain = checkTaunt(text, await this.blocklist())
    if (!plain.allowed) return plain
    if (containsHashedTerm(text, this.hashes)) return { allowed: false, reason: 'blockedTerm' }
    return plain
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

// MARK: Hashed matching (mirrors iOS Core/Moderation/TauntFilter.swift)

const LOOKALIKES: Record<string, string> = { '0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '7': 't', '8': 'b', '@': 'a', $: 's', '!': 'i' }
const SUFFIXES = ['ing', 'ers', 'ed', 'er', 'es', 's', 'y']
const isLetter = (char: string) => /\p{L}/u.test(char)
const isWordChar = (char: string) => /[\p{L}\p{N}]/u.test(char) || LOOKALIKES[char] !== undefined

export function sha256Hex(text: string): string {
  return createHash('sha256').update(text, 'utf8').digest('hex')
}

/** Lowercased, accents removed, look-alikes swapped for letters, letters only. */
export function normalizedToken(word: string): string {
  const folded = word.normalize('NFKD').replace(/\p{M}+/gu, '').toLowerCase()
  let result = ''
  for (const char of folded) {
    const swap = LOOKALIKES[char]
    if (swap) result += swap
    else if (isLetter(char)) result += char
  }
  return result
}

/** Words of the text, normalized. Apostrophes join; a trailing "!" is punctuation. */
export function tokens(text: string): string[] {
  const words: string[] = []
  let current = ''
  const close = () => {
    const trimmed = current.replace(/!+$/, '')
    const normalized = normalizedToken(trimmed)
    if (normalized) words.push(normalized)
    current = ''
  }
  for (const char of text) {
    if (isWordChar(char)) current += char
    else if (char !== "'" && char !== '’') close()
  }
  close()
  return words
}

/** "fuuuuck" → "fuck": runs of three or more of one letter become one. */
export function collapsingRepeats(word: string): string {
  return word.replace(/(.)\1{2,}/gu, '$1')
}

/** Every string a blocked term could hash to: words, runs of up to three words, spaced-out letters, repeats collapsed, suffixes off. */
export function hashedCandidates(words: readonly string[]): Set<string> {
  const raw = new Set<string>()
  for (let start = 0; start < words.length; start++) {
    let joined = ''
    for (let end = start; end < Math.min(words.length, start + 3); end++) {
      joined += words[end]
      raw.add(joined)
    }
  }
  let run = ''
  for (const word of [...words, '']) {
    if ([...word].length === 1) run += word
    else {
      if ([...run].length > 2) raw.add(run)
      run = ''
    }
  }
  const result = new Set<string>()
  for (const candidate of raw) {
    for (const form of [candidate, collapsingRepeats(candidate)]) {
      result.add(form)
      for (const suffix of SUFFIXES) {
        if (form.length > suffix.length + 2 && form.endsWith(suffix)) result.add(form.slice(0, -suffix.length))
      }
    }
  }
  return result
}

export function containsHashedTerm(text: string, hashes: ReadonlySet<string>): boolean {
  if (hashes.size === 0) return false
  for (const candidate of hashedCandidates(tokens(text))) {
    if (hashes.has(sha256Hex(candidate))) return true
  }
  return false
}
