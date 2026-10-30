// The Vercel entrypoint (vercel.json; the project's root directory is apps/api). Vercel's Hono
// preset serves the default export of the first of app, index, server, src/app, src/index,
// src/server that mentions "hono", and src/app.ts would win without this file, so it names the
// package. The server itself is src/index.ts.
import type {} from 'hono'

export { default } from './src/index.ts'
