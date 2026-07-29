import { useNavigate } from 'react-router-dom'
import { ShieldAlert } from 'lucide-react'
import { useAuth } from './AuthProvider'

export default function AccessDenied() {
  const { isAuthenticated, role, signOutUser } = useAuth()
  const navigate = useNavigate()
  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-5">
      <div className="max-w-md rounded-2xl border border-border bg-white p-8 text-center shadow-sm">
        <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-danger-bg text-danger">
          <ShieldAlert size={22} />
        </span>
        <h1 className="mt-4 text-xl font-bold text-neutral-900">Access denied</h1>
        <p className="mt-2 text-sm text-neutral-500">
          You don’t have permission to view this page.
        </p>
        <div className="mt-5 flex justify-center gap-3">
          {isAuthenticated ? (
            <button
              onClick={() => navigate(role === 'recruiter' ? '/sessions' : '/candidate')}
              className="rounded-full bg-[#6B2BE0] px-5 py-2 text-sm font-semibold text-white hover:bg-[#4A1BA8]"
            >
              Go to my home
            </button>
          ) : (
            <button
              onClick={() => navigate('/login')}
              className="rounded-full bg-[#6B2BE0] px-5 py-2 text-sm font-semibold text-white hover:bg-[#4A1BA8]"
            >
              Sign in
            </button>
          )}
          {isAuthenticated && (
            <button
              onClick={() => void signOutUser()}
              className="rounded-full border border-border px-5 py-2 text-sm font-medium text-neutral-600 hover:bg-neutral-50"
            >
              Sign out
            </button>
          )}
        </div>
      </div>
    </div>
  )
}
