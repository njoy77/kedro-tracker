// Serves public/ the way Vercel does, with vercel.json's rewrites and headers, so the link pages
// and the AASA can be checked locally: `bun run --filter '@kedro/site' dev`.

import { join } from 'node:path'
import config from './vercel.json'

const PUBLIC = join(import.meta.dir, 'public')
const port = Number(process.env.PORT ?? 3001)

/** A vercel.json `source` ("/t/:gameID", "/assets/(.*)") as a whole-path regex. */
const pattern = (source: string) => new RegExp(`^${source.replace(/:[A-Za-z]+/g, '[^/]+')}$`)

const rewrites = config.rewrites.map((r) => ({ match: pattern(r.source), destination: r.destination }))
const headers = config.headers.map((h) => ({ match: pattern(h.source), headers: h.headers }))

Bun.serve({
  port,
  async fetch(request) {
    const { pathname } = new URL(request.url)
    let path = rewrites.find((r) => r.match.test(pathname))?.destination ?? pathname
    if (path.endsWith('/')) path += 'index.html'

    let file = Bun.file(join(PUBLIC, path))
    let status = 200
    if (path.includes('..') || !(await file.exists())) {
      file = Bun.file(join(PUBLIC, '404.html'))
      status = 404
    }
    const response = new Response(file, { status })
    for (const rule of headers.filter((h) => h.match.test(pathname))) {
      for (const { key, value } of rule.headers) response.headers.set(key, value)
    }
    return response
  },
})

console.log(`playkedro.com locally at http://localhost:${port}`)
