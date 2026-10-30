// Generates the API's signing keys and stores them in Vercel (kedro-api, production, sensitive)
// without printing them:
//
//   bun scripts/api-keys.ts            # once, before the first production deploy
//   bun scripts/api-keys.ts --rotate   # replace existing keys
//
//   KEDRO_CLIP_SECRET       32 random bytes; HMAC key for App Clip session tokens
//   KEDRO_LINK_SIGNING_KEY  Ed25519 private key (base64 PKCS#8 DER) for table-link attestations
//
// Rotating is disruptive: open App Clip sessions end, and hubs reject phones' attestations until
// both have been online again (hubs cache GET /link/key for offline tables).

import { generateKeyPairSync, randomBytes } from 'node:crypto'
import { join } from 'node:path'

const ROOT = join(import.meta.dir, '..')
const PROJECT = 'kedro-api'
const rotate = process.argv.includes('--rotate')

const keys = {
  KEDRO_CLIP_SECRET: randomBytes(32).toString('base64url'),
  KEDRO_LINK_SIGNING_KEY: generateKeyPairSync('ed25519').privateKey.export({ format: 'der', type: 'pkcs8' }).toString('base64'),
}

async function run(args: string[], stdin?: string): Promise<string> {
  const proc = Bun.spawn(args, { cwd: ROOT, stdin: stdin === undefined ? 'ignore' : new Blob([stdin]), stdout: 'pipe', stderr: 'pipe' })
  const [code, stdout, stderr] = await Promise.all([proc.exited, new Response(proc.stdout).text(), new Response(proc.stderr).text()])
  if (code !== 0) {
    console.error(`✗ ${args.slice(0, 5).join(' ')} failed:\n${stderr.trim()}`)
    process.exit(1)
  }
  return stdout + stderr
}

const listing = await run(['bun', '--bun', 'run', 'vercel', 'env', 'ls', 'production', '--project', PROJECT])
const existing = Object.keys(keys).filter((key) => new RegExp(`^\\s*${key}\\s`, 'm').test(listing))
if (existing.length > 0 && !rotate) {
  console.error(`✗ ${existing.join(', ')} already set in ${PROJECT}. Pass --rotate to replace (see the header first).`)
  process.exit(1)
}

for (const [key, value] of Object.entries(keys)) {
  await run(['bun', 'scripts/env.ts', 'push', key, '--project', 'api', '--environment', 'production', '--sensitive'], value)
  console.log(`✓ ${key} → ${PROJECT} (production)`)
}
