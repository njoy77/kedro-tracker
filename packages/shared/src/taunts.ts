// Custom-taunt filter (design §8.3). Slurs and identity-based abuse are blocked; profanity is
// allowed. The phone filters before sending and the server re-checks on sync (a taunt that fails
// is retracted from every phone).
//
// PLACEHOLDER MECHANISM: the term list is not part of the code. `DEFAULT_BLOCKED_TERMS` is
// intentionally empty; the API loads terms from the `taunt_blocklist` table. The list itself and
// the report-review process need an owner before launch (design §18 item 5).

import { CUSTOM_TAUNT_MAX_LENGTH } from './domain.ts'

export const DEFAULT_BLOCKED_TERMS: readonly string[] = []

export type TauntCheckReason = 'empty' | 'tooLong' | 'blockedTerm'
export type TauntCheck = { allowed: true } | { allowed: false; reason: TauntCheckReason }

/** Look-alike characters people use to dodge filters. */
const LOOKALIKES: Record<string, string> = {
  '0': 'o', '1': 'i', '!': 'i', '|': 'i', '3': 'e', '4': 'a', '@': 'a', '5': 's', '$': 's', '7': 't', '+': 't', '8': 'b', '9': 'g',
}

/**
 * Lowercase and strip diacritics, keeping word boundaries as single spaces. With `lookalikes`,
 * digits and symbols that stand in for letters are mapped first ("b4dw0rd" → "badword").
 */
export function normalizeForFilter(text: string, { lookalikes = true } = {}): string {
  const folded = text
    .normalize('NFKD')
    .replace(/\p{M}+/gu, '')
    .toLowerCase()
  let out = ''
  for (const char of folded) out += (lookalikes ? LOOKALIKES[char] : undefined) ?? char
  return out.replace(/[^\p{L}\p{N}]+/gu, ' ').trim()
}

/** The text with every separator removed ("s l u r" and "s.l.u.r" become "slur"). */
function squash(normalized: string): string {
  return normalized.replace(/ /g, '')
}

/** Terms shorter than this only match as whole words, so they don't hit innocent words. */
const SQUASH_MIN_LENGTH = 5

export type CompiledBlocklist = { words: Set<string>; phrases: string[]; squashed: string[] }

export function compileBlocklist(terms: Iterable<string>): CompiledBlocklist {
  const words = new Set<string>()
  const phrases: string[] = []
  const squashed: string[] = []
  for (const term of terms) {
    const normalized = normalizeForFilter(term)
    if (!normalized) continue
    if (normalized.includes(' ')) phrases.push(normalized)
    else words.add(normalized)
    const flat = squash(normalized)
    if (flat.length >= SQUASH_MIN_LENGTH) squashed.push(flat)
  }
  return { words, phrases, squashed }
}

/** Visible characters (grapheme clusters), how the 80-character limit is counted. */
export function visibleLength(text: string): number {
  const segmenter = new Intl.Segmenter(undefined, { granularity: 'grapheme' })
  let count = 0
  for (const _ of segmenter.segment(text)) count += 1
  return count
}

export function checkTaunt(text: string, blocklist: CompiledBlocklist): TauntCheck {
  const trimmed = text.trim()
  if (!trimmed) return { allowed: false, reason: 'empty' }
  if (visibleLength(trimmed) > CUSTOM_TAUNT_MAX_LENGTH) return { allowed: false, reason: 'tooLong' }
  // Check with and without look-alike mapping: "zorp!" is "zorp" plus punctuation, "z0rp" is "zorp".
  for (const lookalikes of [false, true]) {
    if (containsBlockedTerm(normalizeForFilter(trimmed, { lookalikes }), blocklist)) return { allowed: false, reason: 'blockedTerm' }
  }
  return { allowed: true }
}

function containsBlockedTerm(normalized: string, blocklist: CompiledBlocklist): boolean {
  if (normalized.split(' ').some((token) => blocklist.words.has(token))) return true
  const spaced = ` ${normalized} `
  if (blocklist.phrases.some((phrase) => spaced.includes(` ${phrase} `))) return true
  const flat = squash(normalized)
  return blocklist.squashed.some((term) => flat.includes(term))
}
