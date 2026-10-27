import { Hono } from 'hono'
import { logger } from 'hono/logger'
import { API_VERSION, type HealthResponse } from '@kedro/shared'

const app = new Hono()

app.use('*', logger())

app.get('/health', (c) => c.json<HealthResponse>({ status: 'ok', version: API_VERSION }))

// Routes for games, players, and leaderboards will be mounted here, e.g.
// app.route('/v1/games', games)

export default {
  port: Number(process.env.PORT ?? 8787),
  fetch: app.fetch,
}
