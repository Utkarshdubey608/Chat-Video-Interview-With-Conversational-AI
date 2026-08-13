import type { AuthContext } from '../../shared/types'

// Attach the verified identity (set by the `authenticate` middleware) to the
// Express request object across the whole server.
declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request {
      auth?: AuthContext
    }
  }
}

export {}
