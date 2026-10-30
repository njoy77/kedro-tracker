import { describe, expect, test } from 'bun:test'
import { DEFAULT_BLOCKED_TERMS, checkTaunt, compileBlocklist, normalizeForFilter } from '../src/index.ts'

// Stand-in terms: the real list lives in the database, never in code.
const blocklist = compileBlocklist(['badword', 'zorp', 'two words'])

describe('custom taunt filter', () => {
  test('ships with no terms in code', () => {
    expect(DEFAULT_BLOCKED_TERMS).toEqual([])
    expect(checkTaunt('anything goes', compileBlocklist(DEFAULT_BLOCKED_TERMS))).toEqual({ allowed: true })
  })

  test('allows profanity and ordinary trash talk', () => {
    expect(checkTaunt('You knocked on 9 into a 1, damn', blocklist).allowed).toBe(true)
  })

  test('blocks listed terms, including disguised ones', () => {
    for (const text of ['badword', 'BADWORD!', 'b4dw0rd', 'b.a.d.w.o.r.d', 'bädword', 'you are a two  words', 'zorp!', 'z0rp']) {
      expect(checkTaunt(text, blocklist)).toEqual({ allowed: false, reason: 'blockedTerm' })
    }
  })

  test('short terms only match whole words', () => {
    expect(checkTaunt('zorp', blocklist).allowed).toBe(false)
    expect(checkTaunt('zorpington', blocklist).allowed).toBe(true)
  })

  test('enforces the 80-character limit and rejects empty text', () => {
    expect(checkTaunt('   ', blocklist)).toEqual({ allowed: false, reason: 'empty' })
    expect(checkTaunt('x'.repeat(81), blocklist)).toEqual({ allowed: false, reason: 'tooLong' })
    expect(checkTaunt('🔥'.repeat(80), blocklist).allowed).toBe(true)
  })

  test('normalization', () => {
    expect(normalizeForFilter('  Héllo,   W0rld ')).toBe('hello world')
    expect(normalizeForFilter('W0rld!', { lookalikes: false })).toBe('w0rld')
  })
})
