import { describe, expect, test } from 'bun:test'
import { SignJWT } from 'jose'
import { SupabaseTokenVerifier } from '../src/auth.ts'
import { loadConfig } from '../src/config.ts'

const url = 'https://example-project.supabase.co'
const issuer = `${url}/auth/v1`
const user = '11111111-2222-4333-8444-555555555555'
const secret = 'test-only-jwt-secret-with-enough-entropy-0123456789'

async function hs256(claims: Record<string, unknown>, key = secret, expiresIn = '1h') {
  return new SignJWT(claims)
    .setProtectedHeader({ alg: 'HS256', typ: 'JWT' })
    .setIssuer(issuer)
    .setAudience('authenticated')
    .setSubject(user)
    .setIssuedAt()
    .setExpirationTime(expiresIn)
    .sign(new TextEncoder().encode(key))
}

describe('SupabaseTokenVerifier', () => {
  test('verifies HS256 tokens locally with the JWT secret', async () => {
    const verifier = new SupabaseTokenVerifier({ url, anonKey: 'anon', jwtSecret: secret })
    expect(await verifier.verify(await hs256({ role: 'authenticated' }))).toEqual({ id: user, isAnonymous: false })
    expect(await verifier.verify(await hs256({ role: 'authenticated', is_anonymous: true }))).toEqual({ id: user, isAnonymous: true })
    expect(await verifier.verify(await hs256({ role: 'authenticated' }, 'some-other-secret-that-is-long-enough'))).toBeNull()
    expect(await verifier.verify(await hs256({ role: 'service_role' }))).toBeNull()
    expect(await verifier.verify(await hs256({ role: 'authenticated' }, secret, '-1m'))).toBeNull()
    expect(await verifier.verify('garbage')).toBeNull()
  })

  test('without the secret, asks Supabase Auth and caches the answer', async () => {
    let calls = 0
    const fakeFetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
      calls += 1
      expect(String(input)).toBe(`${issuer}/user`)
      const headers = new Headers(init?.headers)
      expect(headers.get('apikey')).toBe('anon')
      const valid = headers.get('authorization')?.startsWith('Bearer ey')
      return valid ? Response.json({ id: user.toUpperCase(), is_anonymous: false }) : new Response('{}', { status: 401 })
    }) as typeof fetch
    const verifier = new SupabaseTokenVerifier({ url, anonKey: 'anon', fetch: fakeFetch })
    const token = await hs256({ role: 'authenticated' }, 'unknown-to-the-api-secret-0123456789')
    expect(await verifier.verify(token)).toEqual({ id: user, isAnonymous: false })
    expect(await verifier.verify(token)).toEqual({ id: user, isAnonymous: false })
    expect(calls).toBe(1)
  })

  test('remote check refuses tokens from another issuer without calling out', async () => {
    let calls = 0
    const verifier = new SupabaseTokenVerifier({ url, anonKey: 'anon', fetch: (async () => { calls += 1; return Response.json({}) }) as unknown as typeof fetch })
    const foreign = await new SignJWT({ role: 'authenticated' })
      .setProtectedHeader({ alg: 'HS256' })
      .setIssuer('https://elsewhere.example/auth/v1')
      .setSubject(user)
      .setExpirationTime('1h')
      .sign(new TextEncoder().encode(secret))
    expect(await verifier.verify(foreign)).toBeNull()
    expect(calls).toBe(0)
  })
})

describe('config', () => {
  test('reads Supabase keys, falling back to the VITE_ names', () => {
    const config = loadConfig({ VITE_SUPABASE_URL: `${url}/`, VITE_SUPABASE_ANON_KEY: 'anon', SUPABASE_SERVICE_ROLE_KEY: 'service' })
    expect(config.supabase).toEqual({ url, anonKey: 'anon', serviceRoleKey: 'service', jwtSecret: undefined })
    expect(loadConfig({}).missing).toEqual(['SUPABASE_URL', 'SUPABASE_ANON_KEY', 'SUPABASE_SERVICE_ROLE_KEY'])
  })
})
