import { NavLink, useNavigate } from 'react-router-dom'
import { LogOut } from 'lucide-react'
import { cn } from '@/components/ui'
import { useAppStore } from '@/store/useAppStore'
import { useAuth } from '@/features/auth/AuthProvider'

function initialsOf(label: string): string {
  const parts = label.split(/[\s@._-]+/).filter(Boolean).slice(0, 2)
  return parts.map((p) => p[0]?.toUpperCase() ?? '').join('') || 'U'
}

// Menu bar = the Mimic design's 7-tab standard (Sessions · Templates · Question
// sets · Pipelines · Analytics · Avatar studio · Settings). In Mimic's IA,
// candidate results live inside Sessions → View report, and the avatar interview
// room launches from Avatar studio (/setup) — so /interview and /results stay
// as working routes but are intentionally not top-level tabs.
const LINKS = [
  { to: '/sessions',      label: 'Sessions' },
  { to: '/templates',     label: 'Templates' },
  { to: '/question-sets', label: 'Question sets' },
  { to: '/pipelines',     label: 'Pipelines' },
  { to: '/analytics',     label: 'Analytics' },
  { to: '/setup',         label: 'Avatar studio' },
  { to: '/settings',      label: 'Settings' },
]

export function Nav() {
  const { interviewActive, tavusKey } = useAppStore()
  const { user, signOutUser } = useAuth()
  const navigate = useNavigate()
  const label = user?.displayName || user?.email || ''

  return (
    <header className="sticky top-0 z-40 bg-white border-b border-[#dde8e0]" style={{ boxShadow: '0 1px 3px rgba(0,0,0,0.06)' }}>
      <div className="max-w-[1440px] mx-auto px-6 h-[60px] flex items-center justify-between gap-6">

        {/* Brand — Mimic wordmark (product) */}
        <button
          onClick={() => navigate('/sessions')}
          className="flex items-center gap-2 focus:outline-none flex-shrink-0"
          aria-label="Mimic home"
        >
          <span className="grid place-items-center h-7 w-7 rounded-lg bg-primary">
            <svg viewBox="0 0 32 32" className="h-4 w-4" aria-hidden="true">
              <path d="M7 21V11l5 6 4-6 4 6 5-6v10" fill="none" stroke="#fff" strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
          </span>
          <span className="font-display text-[19px] font-extrabold tracking-[-0.03em] text-neutral-900">Mimic</span>
        </button>

        {/* Nav tabs — pill style exactly matching screenshot */}
        <nav className="flex items-center gap-1 flex-1 justify-center">
          {LINKS.map(l => (
            <NavLink
              key={l.to}
              to={l.to}
              className={({ isActive }) =>
                cn(
                  'px-4 py-1.5 rounded-full text-sm font-semibold transition-all duration-150 whitespace-nowrap',
                  isActive
                    ? 'bg-primary text-white'
                    : 'text-neutral-500 hover:text-neutral-800 hover:bg-neutral-100',
                )
              }
            >
              {l.label}
            </NavLink>
          ))}
        </nav>

        {/* Right */}
        <div className="flex items-center gap-3 flex-shrink-0">
          {interviewActive && (
            <span className="flex items-center gap-1.5 text-xs font-bold text-primary uppercase tracking-wider bg-primary-50 border border-primary-200 px-3 py-1 rounded-full">
              <span className="w-1.5 h-1.5 rounded-full bg-[#16a34a] animate-pulse" />
              Live
            </span>
          )}

          {!tavusKey && (
            <button
              onClick={() => navigate('/settings')}
              className="text-xs font-medium text-amber-700 bg-amber-50 border border-amber-200 px-3 py-1.5 rounded-full hover:bg-amber-100 transition-colors"
            >
              Add API Key →
            </button>
          )}

          {/* Signed-in user + sign out */}
          <div
            className="w-9 h-9 rounded-full bg-primary flex items-center justify-center text-white text-xs font-bold"
            title={label + (user?.admin ? ' (admin)' : '')}
          >
            {initialsOf(label)}
          </div>
          <button
            onClick={() => void signOutUser()}
            title="Sign out"
            aria-label="Sign out"
            className="flex items-center justify-center w-9 h-9 rounded-full text-neutral-500 hover:text-neutral-800 hover:bg-neutral-100 transition-colors"
          >
            <LogOut size={17} />
          </button>
        </div>
      </div>
    </header>
  )
}
