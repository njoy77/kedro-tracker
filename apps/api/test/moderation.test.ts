import { describe, expect, test } from 'bun:test'
import { readFileSync } from 'node:fs'
import { BLOCKED_TERM_HASHES } from '../src/services/blockedTermHashes.ts'
import { TauntFilter, containsHashedTerm, sha256Hex } from '../src/services/moderation.ts'
import { MemoryStore } from '../src/store/memory.ts'

const iosList = JSON.parse(readFileSync(new URL('../../ios/Kedro/Core/Moderation/TauntBlocklist.json', import.meta.url), 'utf8')) as { blockedSHA256: string[] }

describe('custom-taunt filter', () => {
  test('the server and the iOS app ship the same launch list', () => {
    expect(BLOCKED_TERM_HASHES.length).toBeGreaterThan(50)
    expect([...iosList.blockedSHA256].sort()).toEqual([...BLOCKED_TERM_HASHES].sort())
  })

  test('hashed terms match through case, look-alikes, spacing, repeats and suffixes (stand-in term)', () => {
    const hashes = new Set([sha256Hex('zorblax')])
    for (const text of ['zorblax', 'ZORBLAX!', 'z0rbl@x', 'z o r b l a x', 'zorrrrblax', 'zorblaxes', 'you zorb lax'])
      expect(containsHashedTerm(text, hashes)).toBe(true)
    for (const text of ['zorbla', 'nice knock', 'zorblaxian']) expect(containsHashedTerm(text, hashes)).toBe(false)
  })

  test('everyday trash talk passes the launch list', async () => {
    const filter = new TauntFilter(new MemoryStore())
    for (const text of ['Nice knock, genius', 'You knocked on a 9? Bold.', 'Spice it up', 'Shitty hand, Ana', 'Coin flip energy'])
      expect((await filter.check(text)).allowed).toBe(true)
  })
})
