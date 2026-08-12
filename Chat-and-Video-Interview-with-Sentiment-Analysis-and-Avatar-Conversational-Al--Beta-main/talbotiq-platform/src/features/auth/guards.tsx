import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { Loader2, ShieldAlert } from 'lucide-react'
import { useAuth } from './AuthProvider'

/* ─── shared states ─────────────────────────────────────────────────────── */

function FullScreen({ children }: { children: React.ReactNode }) {
  return <div className="flex min-h-screen items-center justify-center bg-background px-5">{children}</div>
}

export function AuthLoading() {
  return (
    <FullScreen>
      <Loader2 className="animate-spin text-primary-700" size={28} />
    </FullScreen>
  )
}

/** Shown when the Firebase env vars are missing — the app can't authenticate. */
export function FirebaseNotConfigured() {
  return (
    <FullScreen>
      <div className="max-w-md rounded-2xl border border-border bg-white p-8 text-center shadow-sm">
        <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-danger-bg text-danger">
          <ShieldAlert size={22} />
        </span>
        <h1 className="mt-4 text-xl font-bold text-neutral-900">Sign-in isn’t configured yet</h1>
        <p className="mt-2 text-sm text-neutral-500">
          Set the <span className="font-mono">VITE_FIREBASE_*</span> environment variables (and the server’s Firebase
          Admin credentials), then reload. See <span className="font-mono">docs/AUTH.md</span>.
        </p>
      </div>
    </FullScreen>
  )
}

function AccountError({ message }: { message: string }) {
  const { signOutUser } = useAuth()
  return (
    <FullScreen>
      <div className="max-w-md rounded-2xl border border-border bg-white p-8 text-center shadow-sm">
        <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-danger-bg text-danger">
          <ShieldAlert size={22} />
        </span>
        <h1 className="mt-4 text-xl font-bold text-neutral-900">We couldn’t verify your account</h1>
        <p className="mt-2 text-sm text-neutral-500">{message}</p>
        <button
          onClick={() => void signOutUser()}
          className="mt-5 rounded-full bg-[#6B2BE0] px-5 py-2 text-sm font-semibold text-white hover:bg-[#4A1BA8]"
        >
          Sign out and try again
        </button>
      </div>
    </FullScreen>
  )
}

/* ─── guards (used as layout routes) ────────────────────────────────────── */

/** Recruiter-only. Candidates are bounced to their own home; signed-out users to login. */
export function RequireRecruiter() {
  const { configured, loading, isAuthenticated, role, error } = useAuth()
  const location = useLocation()
  if (!configured) return <FirebaseNotConfigured />
  if (loading) return <AuthLoading />
  if (!isAuthenticated) return <Navigate to="/login" replace state={{ from: location.pathname }} />
  if (error) return <AccountError message={error} />
  if (role !== 'recruiter') return <Navigate to="/candidate" replace />
  return <Outlet />
}

/** Candidate-only. Recruiters are bounced to their dashboard; signed-out users to login. */
export function RequireCandidate() {
  const { configured, loading, isAuthenticated, role, error } = useAuth()
  const location = useLocation()
  if (!configured) return <FirebaseNotConfigured />
  if (loading) return <AuthLoading />
  if (!isAuthenticated) return <Navigate to="/login" replace state={{ from: location.pathname }} />
  if (error) return <AccountError message={error} />
  if (role === 'recruiter') return <Navigate to="/sessions" replace />
  return <Outlet />
}

/** Root/catch-all: send each user to the right home for their role. */
export function HomeRedirect() {
  const { configured, loading, isAuthenticated, role } = useAuth()
  if (!configured) return <FirebaseNotConfigured />
  if (loading) return <AuthLoading />
  if (!isAuthenticated) return <Navigate to="/login" replace />
  return <Navigate to={role === 'recruiter' ? '/sessions' : '/candidate'} replace />
}
