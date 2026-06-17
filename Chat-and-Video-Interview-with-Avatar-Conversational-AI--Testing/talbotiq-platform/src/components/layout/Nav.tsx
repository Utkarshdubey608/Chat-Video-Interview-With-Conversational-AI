import { NavLink, useNavigate } from 'react-router-dom'
import { cn } from '@/components/ui'
import { useAppStore } from '@/store/useAppStore'

const LINKS = [
  { to: '/setup',     label: 'Setup' },
  { to: '/interview', label: 'Interview' },
  { to: '/results',   label: 'Results' },
  { to: '/replicas',  label: 'Replicas' },
  { to: '/personas',  label: 'Personas' },
  { to: '/analytics', label: 'Analytics' },
  { to: '/settings',  label: 'Settings' },
]

export function Nav() {
  const { interviewActive, tavusKey } = useAppStore()
  const navigate = useNavigate()

  return (
    <header className="sticky top-0 z-40 bg-white border-b border-[#dde8e0]" style={{ boxShadow: '0 1px 3px rgba(0,0,0,0.06)' }}>
      <div className="max-w-[1440px] mx-auto px-6 h-[100px] flex items-center justify-between gap-6">

        {/* Brand — leaf icon + wordmark exactly like screenshot */}
        <button
          onClick={() => navigate('/setup')}
          className="flex items-center gap-2.5 focus:outline-none flex-shrink-0"
        >
          <img src="/logo.jpg" alt="TalbotIQ" className="h-[90px] w-auto object-contain" />
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
                    ? 'bg-[#0d5c3a] text-white'
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
            <span className="flex items-center gap-1.5 text-xs font-bold text-[#0d5c3a] uppercase tracking-wider bg-[#f0faf5] border border-[#b3e9cd] px-3 py-1 rounded-full">
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

          {/* User avatar — matches screenshot */}
          <div className="w-9 h-9 rounded-full bg-[#0d5c3a] flex items-center justify-center text-white text-xs font-bold">
            SN
          </div>
        </div>
      </div>
    </header>
  )
}
