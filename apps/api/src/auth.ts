// Supabase JWT verification. Every /v1 route needs `Authorization: Bearer <access token>`.
//
// Supabase projects sign access tokens either with asymmetric signing keys (ES256/RS256, public
// keys at /auth/v1/.well-known/jwks.json) or with the legacy shared HS256 secret. Asymmetric
// tokens are verified locally against the JWKS. HS256 tokens are verified locally when
// SUPABASE_JWT_SECRET is set, and otherwise by asking Supabase Auth (GET /auth/v1/user), with
// the answer cached until the token expires (at most five minutes).

import { createMiddleware } from 'hono/factory'
import { createRemoteJWKSet, decodeJwt, decodeProtectedHeader, jwtVerify, type JWTPayload } from 'jose'
import { isUUID, type UUID } from '@kedro/shared'
import { HttpError } from './http.ts'

export type AuthUser = {
  id: UUID
  /** Supabase anonymous sign-ins have a uid but no identity. */
  isAnonymous: boolean
}

export interface TokenVerifier {
  /** The user behind a valid token, or null for an invalid, expired or revoked one. */
  verify(token: string): Promise<AuthUser | null>
}

export type AuthEnv = { Variables: { user: AuthUser } }

export function requireAuth(verifier: TokenVerifier) {
  return createMiddleware<AuthEnv>(async (c, next) => {
    const header = c.req.header('authorization') ?? ''
    const match = /^Bearer\s+(.+)$/i.exec(header)
    if (!match) throw new HttpError(401, 'unauthorized', 'Sign in to use this')
    const user = await verifier.verify(match[1].trim())
    if (!user) throw new HttpError(401, 'unauthorized', 'Your session expired. Sign in again.')
    c.set('user', user)
    await next()
  })
}

// MARK: Supabase

type SupabaseAuthOptions = {
  url: string
  anonKey: string
  jwtSecret?: string
  fetch?: typeof fetch
  now?: () => number
}

const REMOTE_CACHE_MS = 5 * 60 * 1000
const REMOTE_CACHE_MAX = 5000

export class SupabaseTokenVerifier implements TokenVerifier {
  private readonly issuer: string
  private readonly jwks: ReturnType<typeof createRemoteJWKSet>
  private readonly secret?: Uint8Array
  private readonly fetch: typeof fetch
  private readonly now: () => number
  private readonly remoteCache = new Map<string, { user: AuthUser; expiresAt: number }>()

  constructor(private readonly options: SupabaseAuthOptions) {
    this.issuer = `${options.url}/auth/v1`
    this.jwks = createRemoteJWKSet(new URL(`${this.issuer}/.well-known/jwks.json`))
    this.secret = options.jwtSecret ? new TextEncoder().encode(options.jwtSecret) : undefined
    this.fetch = options.fetch ?? fetch
    this.now = options.now ?? Date.now
  }

  async verify(token: string): Promise<AuthUser | null> {
    let alg: string | undefined
    try {
      alg = decodeProtectedHeader(token).alg
    } catch {
      return null
    }
    if (alg === 'HS256') {
      if (this.secret) return this.verifyLocally(token, this.secret)
      return this.verifyRemotely(token)
    }
    return this.verifyLocally(token, this.jwks)
  }

  private async verifyLocally(token: string, key: Uint8Array | ReturnType<typeof createRemoteJWKSet>): Promise<AuthUser | null> {
    try {
      const { payload } = await jwtVerify(token, key as Parameters<typeof jwtVerify>[1], {
        issuer: this.issuer,
        audience: 'authenticated',
      })
      return userFromClaims(payload)
    } catch {
      return null
    }
  }

  private async verifyRemotely(token: string): Promise<AuthUser | null> {
    const cached = this.remoteCache.get(token)
    const now = this.now()
    if (cached && cached.expiresAt > now) return cached.user

    let claims: JWTPayload
    try {
      claims = decodeJwt(token)
    } catch {
      return null
    }
    if (claims.iss !== this.issuer || (claims.exp !== undefined && claims.exp * 1000 <= now)) return null

    const response = await this.fetch(`${this.issuer}/user`, {
      headers: { apikey: this.options.anonKey, authorization: `Bearer ${token}` },
    }).catch(() => null)
    if (!response) throw new HttpError(503, 'unavailable', 'Sign-in is unavailable right now')
    if (response.status === 401 || response.status === 403) return null
    if (!response.ok) throw new HttpError(503, 'unavailable', 'Sign-in is unavailable right now')
    const body = (await response.json().catch(() => null)) as { id?: unknown; is_anonymous?: unknown } | null
    if (!body || !isUUID(body.id)) return null
    const user: AuthUser = { id: body.id.toLowerCase(), isAnonymous: body.is_anonymous === true }

    if (this.remoteCache.size >= REMOTE_CACHE_MAX) this.remoteCache.clear()
    const expiresAt = Math.min(now + REMOTE_CACHE_MS, claims.exp ? claims.exp * 1000 : now + REMOTE_CACHE_MS)
    this.remoteCache.set(token, { user, expiresAt })
    return user
  }
}

function userFromClaims(payload: JWTPayload): AuthUser | null {
  if (!isUUID(payload.sub)) return null
  if (payload.role !== undefined && payload.role !== 'authenticated') return null
  return { id: payload.sub.toLowerCase(), isAnonymous: payload.is_anonymous === true }
}

// MARK: Local development

/**
 * Accepts `dev:<uuid>` as a token for that user. Only for `KEDRO_DEV_AUTH=1` without Supabase
 * (index.ts refuses to combine it with real credentials) and for tests.
 */
export class DevTokenVerifier implements TokenVerifier {
  async verify(token: string): Promise<AuthUser | null> {
    const match = /^dev:(.+)$/.exec(token)
    if (!match || !isUUID(match[1])) return null
    return { id: match[1].toLowerCase(), isAnonymous: false }
  }
}
