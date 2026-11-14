import { describe, expect, test } from 'bun:test'
import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { OPERATION_TYPES } from '@kedro/shared'

const migrations = join(import.meta.dir, '../../../supabase/migrations')
const sql = readdirSync(migrations).filter((file) => file.endsWith('.sql')).sort().map((file) => readFileSync(join(migrations, file), 'utf8'))

describe('database schema', () => {
  test('ops_type_check (the latest migration that sets it) allows every op type', () => {
    const definitions = sql.flatMap((text) => [...text.matchAll(/add constraint ops_type_check check \(type in \(([^)]*)\)\)/g)].map((match) => match[1]))
    const latest = definitions.at(-1) ?? ''
    const allowed = [...latest.matchAll(/'([A-Za-z]+)'/g)].map((match) => match[1])
    expect(allowed.sort()).toEqual([...OPERATION_TYPES].sort())
  })

  test('kedro_project_finished_game (the latest definition) reads and writes every seat field the API sends', () => {
    // The seat fields SupabaseStore.projectFinishedGame sends in p_seats.
    const store = readFileSync(join(import.meta.dir, '../src/store/supabase.ts'), 'utf8')
    const call = store.slice(store.indexOf("rpc('kedro_project_finished_game'"))
    const seatsBlock = call.slice(call.indexOf('p_seats:'), call.indexOf('})),'))
    const sent = [...seatsBlock.matchAll(/^\s+([a-z_]+):/gm)].map((match) => match[1]).filter((key) => key !== 'p_seats').sort()
    expect(sent).toContain('neighs')

    const definitions = sql.flatMap((text) => [...text.matchAll(/function public\.kedro_project_finished_game[\s\S]*?\n\$\$;/g)].map((match) => match[0]))
    const latest = definitions.at(-1) ?? ''
    const recordset = latest.slice(latest.indexOf('jsonb_to_recordset(p_seats) as s('))
    const read = [...recordset.slice(0, recordset.indexOf('left join')).matchAll(/([a-z_]+) (?:text|uuid|integer|boolean)/g)].map((match) => match[1]).sort()
    expect(read).toEqual(sent)
    const insert = latest.slice(latest.indexOf('insert into public.finished_game_seats ('))
    const written = insert.slice(insert.indexOf('(') + 1, insert.indexOf(')')).split(',').map((column) => column.trim())
    for (const column of sent) expect(written).toContain(column)
  })
})
