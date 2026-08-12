import type { Request, Response, NextFunction, RequestHandler } from 'express'

/**
 * Async-handler wrapper. Express 4 does not forward rejected promises to the
 * error middleware, so we catch and pass them along explicitly.
 */
export const ah =
  (fn: (req: Request, res: Response, next: NextFunction) => unknown): RequestHandler =>
  (req, res, next) =>
    Promise.resolve(fn(req, res, next)).catch(next)

export class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message)
  }
}
