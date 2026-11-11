// Generates the client secret for Sign in with Apple on the web (Supabase → Authentication →
// Providers → Apple → "Secret Key (for OAuth)"). Apple accepts one for at most 6 months, so this
// has to be re-run and pasted again before it expires; the iPhone app's native sign-in doesn't
// use it and keeps working either way.
//
//   bun scripts/apple-client-secret.ts --key ~/Keys/AuthKey_ABCDE12345.p8 [--services-id com.njoy77.kedro.web]
//
// The key is the Sign in with Apple key from Apple Developer → Keys; its ID comes from the file
// name (or pass --key-id). The secret goes to the clipboard, not the terminal.

import { resolve } from 'node:path'

const TEAM_ID = '2RXNMCM34K'
/** Apple's limit is 15,777,000 s (about 182 days); stay a little under it. */
const LIFETIME_DAYS = 180

const args = process.argv.slice(2)
const value = (name: string) => {
  const index = args.indexOf(name)
  return index >= 0 ? args[index + 1] : undefined
}

const keyPath = value('--key')
if (!keyPath) throw new Error('Pass --key <path to AuthKey_XXXXXXXXXX.p8>')
if (resolve(keyPath).startsWith(resolve(import.meta.dir, '..'))) throw new Error('Keep the .p8 key outside the repo')
const keyID = value('--key-id') ?? keyPath.match(/AuthKey_([A-Z0-9]{10})\.p8$/)?.[1]
if (!keyID) throw new Error('Pass --key-id (the 10-character Key ID from Apple Developer → Keys)')
const servicesID = value('--services-id') ?? 'com.njoy77.kedro.web'

const pem = await Bun.file(keyPath).text()
const der = Buffer.from(pem.replace(/-----[^-]+-----/g, '').replace(/\s+/g, ''), 'base64')
const key = await crypto.subtle.importKey('pkcs8', der, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign'])

const now = Math.floor(Date.now() / 1000)
const expires = now + LIFETIME_DAYS * 24 * 60 * 60
const encode = (json: object) => Buffer.from(JSON.stringify(json)).toString('base64url')
const unsigned = `${encode({ alg: 'ES256', kid: keyID })}.${encode({ iss: TEAM_ID, iat: now, exp: expires, aud: 'https://appleid.apple.com', sub: servicesID })}`
// WebCrypto's ECDSA signature is already JWS's raw r‖s form.
const signature = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(unsigned))
const secret = `${unsigned}.${Buffer.from(signature).toString('base64url')}`

const copy = Bun.spawn(['pbcopy'], { stdin: 'pipe' })
copy.stdin.write(secret)
copy.stdin.end()
await copy.exited

const expiry = new Date(expires * 1000).toISOString().slice(0, 10)
console.log(`Copied the client secret for ${servicesID} (key ${keyID}) to the clipboard.`)
console.log('Paste it into Supabase → Authentication → Providers → Apple → Secret Key (for OAuth).')
console.log(`It expires on ${expiry}: run this again before then.`)
