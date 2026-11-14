import { describe, expect, test } from 'bun:test'
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { OPERATION_TYPES } from '@kedro/shared'

const migrations = join(import.meta.dir, '../../../supabase/migrations')

describe('database schema', () => {
  test('ops_type_check (the latest migration that sets it) allows every op type', () => {
    const files = readdirSync(migrations).filter((file) => file.endsWith('.sql')).sort()
    const definitions = files.flatMap((file) =>
      [...readFileSync(join(migrations, file), 'utf8').matchAll(/add constraint ops_type_check check \(type in \(([^)]*)\)\)/g)].map((match) => match[1]),
    )
    const latest = definitions.at(-1) ?? ''
    const allowed = [...latest.matchAll(/'([A-Za-z]+)'/g)].map((match) => match[1])
    expect(allowed.sort()).toEqual([...OPERATION_TYPES].sort())
  })
})
