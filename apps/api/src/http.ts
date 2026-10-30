// Error responses and request parsing shared by every route.

import type { Context } from 'hono'
import type { ContentfulStatusCode } from 'hono/utils/http-status'
import type { z } from 'zod'
import { formatZodError, isUUID, type ApiError, type ApiErrorCode, type UUID } from '@kedro/shared'

/** Thrown by handlers and services; rendered as `{error, message}` with the status. */
export class HttpError extends Error {
  constructor(
    readonly status: ContentfulStatusCode,
    readonly code: ApiErrorCode,
    message: string,
  ) {
    super(message)
  }
}

export const badRequest = (message: string) => new HttpError(400, 'invalidRequest', message)
export const notFound = (message = 'Not found') => new HttpError(404, 'notFound', message)
export const forbidden = (message = 'Not allowed') => new HttpError(403, 'forbidden', message)

export function errorBody(code: ApiErrorCode, message: string): ApiError {
  return { error: code, message }
}

/** Parses and validates a JSON body. */
export async function readJson<Schema extends z.ZodTypeAny>(c: Context, schema: Schema): Promise<z.output<Schema>> {
  let body: unknown
  try {
    body = await c.req.json()
  } catch {
    throw badRequest('Expected a JSON body')
  }
  const result = schema.safeParse(body)
  if (!result.success) throw badRequest(formatZodError(result.error))
  return result.data
}

/** A UUID path or query parameter, lowercased. Swift's `uuidString` is uppercase. */
export function uuidParam(value: string | undefined, name: string): UUID {
  if (!value || !isUUID(value)) throw badRequest(`${name} must be a UUID`)
  return value.toLowerCase()
}
