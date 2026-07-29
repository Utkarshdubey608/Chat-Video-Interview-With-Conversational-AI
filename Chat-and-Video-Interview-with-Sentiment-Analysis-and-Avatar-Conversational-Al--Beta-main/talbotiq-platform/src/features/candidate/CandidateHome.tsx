import { useQuery } from '@tanstack/react-query'
import { Link } from 'react-router-dom'
import { Loader2, CalendarClock, CheckCircle2, LogOut, Inbox } from 'lucide-react'
import { sessionsApi } from '@/lib/api'
import { useAuth } from '@/features/auth/AuthProvider'
import type { CandidateAssignedSession } from '@shared/types'

const TRACK_LABEL: Record<string, string> = {
  chat: 'Timed Q&A', chatbot: 'Conversational', video_avatar: 'Video Avatar', voice: 'Voice',
}

export default function CandidateHome() {
  const { user, signOutUser } = useAuth()
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['my-sessions'],
    queryFn: sessionsApi.mine,
  })

  return (
    <div className="min-h-screen bg-background">
      <header className="sticky top-0 z-40 border-b border-[#dde8e0] bg-white">
        <div className="mx-auto flex h-[60px] max-w-4xl items-center justify-between px-6">
          <img src="/talbotiq-logo.png" alt="TalbotIQ" className="h-9 w-auto" />
          <div className="flex items-center gap-3">
            <span className="hidden text-sm text-neutral-500 sm:inline">{user?.email}</span>
            <button
              onClick={() => void signOutUser()}
              className="flex items-center gap-1.5 rounded-full border border-border px-3 py-1.5 text-sm font-medium text-neutral-600 hover:bg-neutral-50"
            >
              <LogOut size={15} /> Sign out
            </button>
          </div>
        </div>
      </header>

      <main className="mx-auto max-w-4xl px-6 py-10">
        <h1 className="text-2xl font-bold text-neutral-900">Your interviews</h1>
        <p className="mt-1 text-sm text-neutral-500">Interviews assigned to {user?.email}.</p>

        <div className="mt-6">
          {isLoading ? (
            <div className="flex justify-center py-20"><Loader2 className="animate-spin text-primary-700" size={26} /></div>
          ) : isError ? (
            <Card>
              <p className="text-sm text-danger">{(error as Error)?.message ?? 'Could not load your interviews.'}</p>
            </Card>
          ) : (data && data.length > 0) ? (
            <ul className="space-y-3">
              {data.map((s) => <SessionRow key={s.id} s={s} />)}
            </ul>
          ) : (
            <Card>
              <div className="flex flex-col items-center py-8 text-center">
                <span className="flex h-12 w-12 items-center justify-center rounded-full bg-neutral-100 text-neutral-400">
                  <Inbox size={22} />
                </span>
                <h2 className="mt-4 text-lg font-semibold text-neutral-900">No interviews assigned</h2>
                <p className="mt-1 max-w-sm text-sm text-neutral-500">
                  There are no interviews assigned to this account. If you were expecting one, make sure you’re signed in
                  with the email address your invite was sent to, or contact the recruiter.
                </p>
              </div>
            </Card>
          )}
        </div>
      </main>
    </div>
  )
}

function SessionRow({ s }: { s: CandidateAssignedSession }) {
  const done = s.status === 'completed' || s.status === 'expired'
  return (
    <li className="flex items-center justify-between gap-4 rounded-xl border border-border bg-white p-4 shadow-sm">
      <div className="min-w-0">
        <p className="truncate font-semibold text-neutral-900">{s.templateName}</p>
        <p className="mt-0.5 text-xs text-neutral-500">
          {s.role ? `${s.role} · ` : ''}{TRACK_LABEL[s.track] ?? s.track}
        </p>
      </div>
      {done ? (
        <span className="flex flex-shrink-0 items-center gap-1.5 rounded-full bg-[#f0faf5] px-3 py-1.5 text-sm font-semibold text-[#0d5c3a]">
          <CheckCircle2 size={15} /> Completed
        </span>
      ) : (
        <Link
          to={`/take/${s.id}`}
          className="flex flex-shrink-0 items-center gap-1.5 rounded-full bg-[#0d5c3a] px-4 py-1.5 text-sm font-semibold text-white hover:bg-[#0a4a2f]"
        >
          <CalendarClock size={15} /> {s.status === 'in_progress' ? 'Continue' : 'Start interview'}
        </Link>
      )}
    </li>
  )
}

function Card({ children }: { children: React.ReactNode }) {
  return <div className="rounded-2xl border border-border bg-white p-6 shadow-sm">{children}</div>
}
