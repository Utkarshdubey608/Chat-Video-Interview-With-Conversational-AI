import { useState } from 'react'
import { Navigate, useLocation } from 'react-router-dom'
import { Loader2, Mail, Lock, User as UserIcon } from 'lucide-react'
import { useAuth } from './AuthProvider'
import { AuthLoading, FirebaseNotConfigured } from './guards'
import type { UserRole } from '@shared/types'

type Mode = 'signin' | 'signup'

/** Turn a Firebase auth error into a short, human message. */
function friendly(err: unknown): string {
  const code = (err as { code?: string })?.code ?? ''
  switch (code) {
    case 'auth/invalid-credential':
    case 'auth/wrong-password':
    case 'auth/user-not-found': return 'Incorrect email or password.'
    case 'auth/email-already-in-use': return 'An account with that email already exists — sign in instead.'
    case 'auth/weak-password': return 'Password should be at least 6 characters.'
    case 'auth/invalid-email': return 'That doesn’t look like a valid email address.'
    case 'auth/too-many-requests': return 'Too many attempts — please wait a moment and try again.'
    default: return (err as Error)?.message || 'Something went wrong. Please try again.'
  }
}

export default function LoginPage() {
  const { configured, loading, isAuthenticated, role, signInWithEmail, signUpWithEmail } = useAuth()
  const location = useLocation()

  const [mode, setMode] = useState<Mode>('signin')
  const [roleIntent, setRoleIntent] = useState<UserRole>('candidate')
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)

  if (!configured) return <FirebaseNotConfigured />
  if (isAuthenticated && role && !loading) {
    const from = (location.state as { from?: string } | null)?.from
    return <Navigate to={from ?? (role === 'recruiter' ? '/sessions' : '/candidate')} replace />
  }
  if (loading) return <AuthLoading />

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    setBusy(true); setErr(null)
    try {
      if (mode === 'signup') {
        await signUpWithEmail(email.trim(), password, roleIntent, name.trim() || undefined)
      } else {
        await signInWithEmail(email.trim(), password)
      }
      // On success, AuthProvider's live role stream re-routes via the <Navigate> above.
    } catch (e2) {
      setErr(friendly(e2))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-5 py-10">
      <div className="w-full max-w-md rounded-2xl border border-border bg-white p-8 shadow-sm">
        <div className="flex flex-col items-center text-center">
          <img
            src="/talbotiq-logo-full.png"
            alt="TalbotIQ — Intelligent AI Automation"
            className="w-full max-w-[340px] h-auto"
          />
          <h1 className="mt-6 text-2xl font-bold text-neutral-900">
            {mode === 'signup' ? 'Create your account' : 'Welcome'}
          </h1>
          <p className="mt-1 text-sm text-neutral-500">
            {mode === 'signup' ? 'Sign up to get started with TalbotIQ.' : 'Sign in to continue to TalbotIQ.'}
          </p>
        </div>

        {/* Role picker — only meaningful at sign-up (it's stored on users/{uid}.role). */}
        {mode === 'signup' && (
          <>
            <p className="mt-6 text-xs font-semibold uppercase tracking-wide text-neutral-400">I am a</p>
            <div className="mt-2 grid grid-cols-2 gap-2 rounded-xl bg-neutral-100 p-1">
              {(['candidate', 'recruiter'] as UserRole[]).map((r) => (
                <button
                  key={r}
                  type="button"
                  onClick={() => { setRoleIntent(r); setErr(null) }}
                  className={`rounded-lg px-3 py-2 text-sm font-semibold capitalize transition-colors ${
                    roleIntent === r ? 'bg-white text-[#6B2BE0] shadow-sm' : 'text-neutral-500 hover:text-neutral-700'
                  }`}
                >
                  {r}
                </button>
              ))}
            </div>
          </>
        )}

        {err && <div className="mt-4 rounded-lg border border-danger/30 bg-danger-bg px-3 py-2 text-sm text-danger">{err}</div>}

        <form onSubmit={submit} className="mt-5 space-y-3">
          {mode === 'signup' && (
            <Field icon={<UserIcon size={16} />} type="text" placeholder="Full name" value={name} onChange={setName} />
          )}
          <Field icon={<Mail size={16} />} type="email" placeholder="Email" required value={email} onChange={setEmail} />
          <Field icon={<Lock size={16} />} type="password" placeholder="Password" required value={password} onChange={setPassword} />
          <button
            type="submit"
            disabled={busy}
            className="flex w-full items-center justify-center gap-2 rounded-xl bg-[#6B2BE0] px-4 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-[#4A1BA8] disabled:opacity-60"
          >
            {busy && <Loader2 className="animate-spin" size={16} />}
            {mode === 'signup' ? `Create ${roleIntent} account` : 'Sign in'}
          </button>
        </form>

        <button
          type="button"
          onClick={() => { setMode(mode === 'signup' ? 'signin' : 'signup'); setErr(null) }}
          className="mt-4 w-full text-center text-sm text-neutral-500 hover:text-neutral-700"
        >
          {mode === 'signup' ? 'Already have an account? Sign in' : 'New here? Create an account'}
        </button>
      </div>
    </div>
  )
}

function Field({ icon, value, onChange, ...rest }: {
  icon: React.ReactNode
  value: string
  onChange: (v: string) => void
} & Omit<React.InputHTMLAttributes<HTMLInputElement>, 'value' | 'onChange'>) {
  return (
    <div className="flex items-center gap-2 rounded-xl border border-border bg-white px-3 py-2.5 focus-within:border-[#6B2BE0]">
      <span className="text-neutral-400">{icon}</span>
      <input
        {...rest}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full bg-transparent text-sm text-neutral-900 outline-none placeholder:text-neutral-400"
      />
    </div>
  )
}
