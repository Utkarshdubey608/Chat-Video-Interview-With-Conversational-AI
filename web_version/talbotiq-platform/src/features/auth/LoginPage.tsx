import { useState } from 'react'
import { Navigate, useLocation } from 'react-router-dom'
import { AlertCircle, Briefcase, Lock, Mail, User as UserIcon } from 'lucide-react'
import { Button, cn } from '@/components/ui'
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

const ROLE_OPTIONS: { value: UserRole; label: string; description: string; icon: React.ReactNode }[] = [
  { value: 'candidate', label: 'Candidate', description: 'Take AI interviews and follow your invites', icon: <UserIcon size={16} /> },
  { value: 'recruiter', label: 'Recruiter', description: 'Set up screenings and review results', icon: <Briefcase size={16} /> },
]

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
    <div className="flex min-h-screen items-center justify-center bg-background bg-brand-wash px-5 py-10">
      <div className="w-full max-w-md overflow-hidden rounded-3xl border border-border bg-white shadow-xl">
        {/* Brand band — the parent identity, one hairline of it. */}
        <div className="h-1 w-full bg-brand-band" aria-hidden />

        <div className="p-8">
          <div className="flex flex-col items-center text-center">
            {/* The logo is the identity — a generic sparkle plate stacked above
                it was a second, weaker mark competing with the real one. */}
            <img
              src="/talbotiq-logo-full.png"
              alt="TalbotIQ — Intelligent AI Automation"
              className="h-auto w-full max-w-[300px]"
            />
            <h1 className="mt-6 font-display text-2xl font-extrabold tracking-[-0.03em] text-neutral-900">
              {mode === 'signup' ? 'Create your account' : 'Welcome back'}
            </h1>
            <p className="mt-1.5 text-sm text-neutral-500">
              {mode === 'signup' ? 'Sign up to get started with TalbotIQ.' : 'Sign in to continue to TalbotIQ.'}
            </p>
          </div>

          {/* Role picker — only meaningful at sign-up (it's stored on users/{uid}.role). */}
          {mode === 'signup' && (
            <>
              <p className="field-label mb-2.5 mt-8">I am a</p>
              <div className="grid grid-cols-2 gap-2.5">
                {ROLE_OPTIONS.map(({ value: r, label, description, icon }) => {
                  const selected = roleIntent === r
                  return (
                    <button
                      key={r}
                      type="button"
                      aria-pressed={selected}
                      onClick={() => { setRoleIntent(r); setErr(null) }}
                      className={cn(
                        'flex flex-col items-start rounded-2xl border-[1.5px] p-3.5 text-left transition-all duration-150',
                        selected
                          ? 'border-primary-600 bg-primary-50 shadow-xs'
                          : 'border-border bg-white hover:border-primary-300 hover:bg-neutral-50',
                      )}
                    >
                      <span
                        className={cn(
                          'flex h-8 w-8 items-center justify-center rounded-xl transition-colors duration-150',
                          selected ? 'bg-brand-field text-white' : 'bg-neutral-100 text-neutral-400',
                        )}
                        aria-hidden
                      >
                        {icon}
                      </span>
                      <span className="mt-2.5 text-sm font-semibold text-neutral-900">{label}</span>
                      <span className="mt-0.5 text-xs leading-snug text-neutral-500">{description}</span>
                    </button>
                  )
                })}
              </div>
            </>
          )}

          {err && (
            <div role="alert" className="mt-5 flex items-start gap-2 rounded-xl border border-danger-border bg-danger-bg px-3.5 py-2.5 text-sm text-danger">
              <AlertCircle size={15} className="mt-0.5 shrink-0" aria-hidden />
              <span>{err}</span>
            </div>
          )}

          <form onSubmit={submit} className="mt-6">
            <div className="space-y-3">
              {mode === 'signup' && (
                <Field icon={<UserIcon size={16} />} type="text" placeholder="Full name" aria-label="Full name" value={name} onChange={setName} />
              )}
              <Field icon={<Mail size={16} />} type="email" placeholder="Email" aria-label="Email" required value={email} onChange={setEmail} />
              <Field icon={<Lock size={16} />} type="password" placeholder="Password" aria-label="Password" required value={password} onChange={setPassword} />
            </div>
            <Button type="submit" size="lg" loading={busy} className="mt-5 w-full">
              {mode === 'signup' ? `Create ${roleIntent} account` : 'Sign in'}
            </Button>
          </form>

          <div className="mt-6 border-t border-border pt-4 text-center">
            <button
              type="button"
              onClick={() => { setMode(mode === 'signup' ? 'signin' : 'signup'); setErr(null) }}
              className="text-sm text-neutral-500 transition-colors duration-150 hover:text-neutral-800"
            >
              {mode === 'signup' ? (
                <>Already have an account? <span className="font-semibold text-primary-700">Sign in</span></>
              ) : (
                <>New here? <span className="font-semibold text-primary-700">Create an account</span></>
              )}
            </button>
          </div>
        </div>
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
    <div className="relative">
      <span className="pointer-events-none absolute left-3.5 top-1/2 -translate-y-1/2 text-neutral-400">{icon}</span>
      <input
        {...rest}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="input-base pl-10"
      />
    </div>
  )
}
