import { describe, expect, test } from 'bun:test'
import { deploymentProblems, loadConfig } from '../src/config.ts'
import { harness, ids, sampleWireOperations } from './support.ts'

const supabase = { SUPABASE_URL: 'https://example.supabase.co', SUPABASE_ANON_KEY: 'anon', SUPABASE_SERVICE_ROLE_KEY: 'service' }
const signing = { KEDRO_CLIP_SECRET: 'clip', KEDRO_LINK_SIGNING_KEY: 'link', KEDRO_PUBLIC_URL: 'https://api.playkedro.com' }

describe('deployment checks', () => {
  test('the environment comes from VERCEL_ENV, or NODE_ENV off Vercel', () => {
    expect(loadConfig({}).environment).toBe('local')
    expect(loadConfig({ VERCEL_ENV: 'production' }).environment).toBe('production')
    expect(loadConfig({ VERCEL_ENV: 'preview', NODE_ENV: 'production' }).environment).toBe('preview')
    expect(loadConfig({ VERCEL_ENV: 'development' }).environment).toBe('preview')
    expect(loadConfig({ NODE_ENV: 'production' }).environment).toBe('production')
  })

  test('local runs anything, including dev auth on memory', () => {
    expect(deploymentProblems(loadConfig({ KEDRO_DEV_AUTH: '1', KEDRO_DEV_SEED: 'legacy' }))).toEqual([])
  })

  test('production refuses the in-memory fallback and per-process keys', () => {
    expect(deploymentProblems(loadConfig({ VERCEL_ENV: 'production', ...signing }))).toEqual([
      'Supabase is not configured (missing SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY)',
    ])
    expect(deploymentProblems(loadConfig({ VERCEL_ENV: 'production', ...supabase }))).toEqual([
      'missing KEDRO_CLIP_SECRET, KEDRO_LINK_SIGNING_KEY, KEDRO_PUBLIC_URL',
    ])
    expect(deploymentProblems(loadConfig({ VERCEL_ENV: 'production', ...supabase, ...signing }))).toEqual([])
  })

  test('no deployment runs dev auth or the dev seed', () => {
    expect(deploymentProblems(loadConfig({ VERCEL_ENV: 'preview', KEDRO_DEV_AUTH: '1', KEDRO_DEV_SEED: 'legacy' }))).toEqual([
      'KEDRO_DEV_AUTH is set',
      'KEDRO_DEV_SEED is set',
    ])
    expect(deploymentProblems(loadConfig({ VERCEL_ENV: 'production', KEDRO_DEV_AUTH: '1', ...supabase, ...signing }))).toEqual(['KEDRO_DEV_AUTH is set'])
  })

  test('a preview without keys may run (memory store, every /v1 request unauthorized)', () => {
    expect(deploymentProblems(loadConfig({ VERCEL_ENV: 'preview' }))).toEqual([])
  })
})

describe('background work', () => {
  test('the Live Activity broadcast is handed to defer, so the host keeps it alive after the response', async () => {
    const deferred: Promise<unknown>[] = []
    const h = harness({ defer: (work) => deferred.push(work) })
    await h.profile(ids.noah, 'Noah', 'noah')
    await h.profile(ids.ana, 'Ana', 'ana.k')
    const upload = await h.upload(ids.noah, sampleWireOperations({ throughRound: 1, finished: false }))
    expect(upload.body.rejected).toEqual([])
    expect(deferred.length).toBeGreaterThan(0)
    await Promise.all(deferred)
    expect(h.broadcaster.sent.get(ids.game)?.event).toBe('update')
  })
})
