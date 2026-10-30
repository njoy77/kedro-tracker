// Sync environment variables between the Vercel project and each app's local secrets file.
//
//   bun run env:pull [--environment development|preview|production]
//   bun run env:push KEY=value [KEY=value ...] [--environment ...] [--sensitive] [--project web|api]
//   bun run env:push --file path/to/.env [--environment ...] [--sensitive] [--project web|api]
//   bun run env:push KEY            (reads the value from stdin)
//
// Vercel is the source of truth, in two projects (PROJECTS): kedro-tracker (the web app, and the
// Supabase URL and anon key every app uses) and kedro-api (the API's server-only keys, production
// only). `pull` regenerates the files listed in TARGETS; `push` uploads values to one project
// (`--project`, default web) and then pulls so local files match.

import { existsSync } from 'node:fs'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'

type Env = Record<string, string>

const PROJECTS = { web: 'kedro-tracker', api: 'kedro-api' } as const
type Project = keyof typeof PROJECTS

type Target = {
  file: string
  format: 'dotenv' | 'xcconfig'
  /** Values to write, derived from each project's pulled Vercel variables. */
  values: (env: Record<Project, Env>) => Env
}

const ROOT = join(import.meta.dir, '..')
const ENVIRONMENTS = ['development', 'preview', 'production'] as const

/** The API's server-only keys (apps/api/src/config.ts), kept in the kedro-api project. */
const API_KEYS = ['SUPABASE_SERVICE_ROLE_KEY', 'SUPABASE_JWT_SECRET', 'KEDRO_CLIP_SECRET', 'KEDRO_LINK_SIGNING_KEY', 'KEDRO_PUBLIC_URL']

// Add a target, or a key to an existing one, when an app needs a new secret.
const TARGETS: Target[] = [
  {
    file: 'apps/web/.env.local',
    format: 'dotenv',
    values: ({ web }) => pick(web, (key) => key.startsWith('VITE_')),
  },
  {
    file: 'apps/ios/Config/Secrets.xcconfig',
    format: 'xcconfig',
    values: ({ web }) => ({
      SUPABASE_HOST: new URL(required(web, 'VITE_SUPABASE_URL')).host,
      SUPABASE_ANON_KEY: required(web, 'VITE_SUPABASE_ANON_KEY'),
    }),
  },
  {
    // The API (apps/api/src/config.ts). Its own keys are production-only secrets in kedro-api,
    // which Vercel never hands back, so a development pull has none of them and the API runs on
    // memory (`bun run dev:seed` still reads the web data with the anon key).
    file: 'apps/api/.env.local',
    format: 'dotenv',
    values: ({ web, api }) => ({
      SUPABASE_URL: required(web, 'VITE_SUPABASE_URL'),
      SUPABASE_ANON_KEY: required(web, 'VITE_SUPABASE_ANON_KEY'),
      ...pick(api, (key) => API_KEYS.includes(key) && api[key] !== ''),
    }),
  },
]

// MARK: Commands

async function pull(environment: string) {
  const env = { web: await pullFromVercel(environment, 'web').catch((error: Error) => fail(error.message)), api: {} as Env }
  try {
    env.api = await pullFromVercel(environment, 'api')
  } catch (error) {
    // Before kedro-api exists (or without access to it), the other apps still get their keys.
    const message = error instanceof Error ? error.message : String(error)
    console.warn(`! Skipped ${PROJECTS.api}: ${message.match(/^Error: .*$/m)?.[0].slice(7) ?? message}`)
  }
  for (const target of TARGETS) {
    const values = target.values(env)
    await Bun.write(join(ROOT, target.file), render(target, values, environment))
    console.log(`✓ ${target.file} (${Object.keys(values).length} keys)`)
  }
}

async function push(entries: Env, environments: string[], sensitive: boolean, project: Project) {
  if (Object.keys(entries).length === 0) fail('Nothing to push. Pass KEY=value pairs or --file <path>.')
  if (sensitive && environments.includes('development')) {
    fail('Vercel does not allow sensitive variables in development. Pass --environment preview,production.')
  }

  for (const [key, value] of Object.entries(entries)) {
    await vercel(
      ['env', 'add', key, '--environment', environments.join(','), '--project', PROJECTS[project], '--force', '--yes',
        sensitive ? '--sensitive' : '--no-sensitive'],
      value,
    ).catch((error: Error) => fail(error.message))
    console.log(`✓ ${key} → ${PROJECTS[project]} (${environments.join(', ')})`)
  }

  if (!sensitive) await pull('development')
}

// MARK: Vercel

async function pullFromVercel(environment: string, project: Project): Promise<Env> {
  const dir = await mkdtemp(join(tmpdir(), 'kedro-env-'))
  const file = join(dir, '.env')
  try {
    await vercel(['env', 'pull', file, `--environment=${environment}`, '--project', PROJECTS[project], '--yes'])
    return parseDotenv(await Bun.file(file).text())
  } finally {
    await rm(dir, { recursive: true, force: true })
  }
}

async function vercel(args: string[], stdin?: string) {
  if (!existsSync(join(ROOT, '.vercel/project.json'))) {
    fail('This checkout is not linked to Vercel. Run: bun --bun run vercel link --project kedro-tracker')
  }
  const proc = Bun.spawn(['bun', '--bun', 'run', 'vercel', ...args], {
    cwd: ROOT,
    stdin: stdin === undefined ? 'ignore' : new Blob([stdin]),
    stdout: 'pipe',
    stderr: 'pipe',
  })
  const [code, stderr] = await Promise.all([proc.exited, new Response(proc.stderr).text()])
  if (code !== 0) throw new Error(`vercel ${args.slice(0, 2).join(' ')} failed:\n${stderr.trim()}`)
}

// MARK: Files

function parseDotenv(text: string): Env {
  const env: Env = {}
  for (const line of text.split('\n')) {
    const match = line.match(/^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$/)
    if (!match) continue
    let value = match[2]
    if (/^(["']).*\1$/.test(value)) value = value.slice(1, -1).replace(/\\n/g, '\n')
    env[match[1]] = value
  }
  return env
}

function render(target: Target, values: Env, environment: string) {
  const header = `Generated by \`bun run env:pull\` from Vercel (${environment}). Do not edit; run \`bun run env:push\` instead.`
  const lines = Object.entries(values).map(([key, value]) =>
    target.format === 'xcconfig' ? `${key} = ${value}` : `${key}=${JSON.stringify(value)}`,
  )
  const comment = target.format === 'xcconfig' ? '//' : '#'
  return `${comment} ${header}\n\n${lines.join('\n')}\n`
}

// MARK: Helpers

function pick(env: Env, include: (key: string) => boolean): Env {
  return Object.fromEntries(Object.entries(env).filter(([key]) => include(key)))
}

function required(env: Env, key: string): string {
  const value = env[key]
  if (!value) fail(`${key} is missing in Vercel. Add it with: bun run env:push ${key}=...`)
  return value
}

function fail(message: string): never {
  console.error(`✗ ${message}`)
  process.exit(1)
}

async function readEntries(args: string[]): Promise<Env> {
  const entries: Env = {}
  for (const arg of args) {
    const eq = arg.indexOf('=')
    if (eq > 0) {
      entries[arg.slice(0, eq)] = arg.slice(eq + 1)
    } else if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(arg)) {
      // Reading from stdin keeps the value out of shell history.
      const value = (await new Response(Bun.stdin.stream()).text()).trim()
      if (!value) fail(`No value for ${arg} on stdin.`)
      entries[arg] = value
    } else {
      fail(`Expected KEY=value or KEY, got "${arg}".`)
    }
  }
  return entries
}

// MARK: Main

const [command, ...rest] = process.argv.slice(2)
const flags = { environment: undefined as string | undefined, file: undefined as string | undefined, sensitive: false, project: 'web' as string }
const positional: string[] = []
for (let i = 0; i < rest.length; i++) {
  const arg = rest[i]
  const [flag, inline] = arg.split(/=(.*)/s, 2)
  const next = () => inline ?? rest[++i]
  if (flag === '--environment' || flag === '-e') flags.environment = next()
  else if (flag === '--file') flags.file = next()
  else if (flag === '--sensitive') flags.sensitive = true
  else if (flag === '--project') flags.project = next()
  else positional.push(arg)
}

// The API's keys are production-only unless --environment says otherwise (previews must never
// write to the production database).
const environments = (flags.environment ?? (flags.project === 'api' ? 'production' : ENVIRONMENTS.join(','))).split(',')
for (const environment of environments) {
  if (!ENVIRONMENTS.includes(environment as (typeof ENVIRONMENTS)[number])) fail(`Unknown environment "${environment}".`)
}

if (!(flags.project in PROJECTS)) fail(`Unknown project "${flags.project}". Use ${Object.keys(PROJECTS).join(' or ')}.`)

if (command === 'pull') {
  if (environments.length > 1 && flags.environment) fail('env:pull takes a single --environment.')
  await pull(flags.environment ?? 'development')
} else if (command === 'push') {
  const entries = flags.file ? parseDotenv(await Bun.file(flags.file).text()) : {}
  Object.assign(entries, await readEntries(positional))
  await push(entries, environments, flags.sensitive, flags.project as Project)
} else {
  fail('Usage: bun scripts/env.ts <pull|push> [options]')
}
