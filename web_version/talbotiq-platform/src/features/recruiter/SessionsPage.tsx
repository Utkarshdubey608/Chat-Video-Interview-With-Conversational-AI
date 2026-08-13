import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { AlertTriangle, Check, Copy, ExternalLink, Mic, Plus, RefreshCw, Sparkles } from 'lucide-react'
import {
  PageHeader, Card, Button, Input, Select, Badge, EmptyState, Skeleton, Modal, Toggle, cn,
} from '@/components/ui'
import { templatesApi, sessionsApi, settingsApi } from '@/lib/api'
import { GenerateFromResumeModal } from './GenerateFromResumeModal'
import type { SessionListItem, TrackType } from '@shared/types'

const statusVariant: Record<string, 'success' | 'warning' | 'neutral' | 'info' | 'danger'> = {
  completed: 'success',
  in_progress: 'info',
  system_check: 'warning',
  created: 'neutral',
  expired: 'danger',
}

const TRACK_LABEL: Record<string, string> = {
  video_avatar: 'Video Avatar',
  voice: 'Voice',
  chatbot: 'Chatbot',
  video: 'Video Interview',
  two_way: 'Two-way Interview',
  chat: 'Chat',
}

/** Up to two initials for the candidate avatar chip. */
const initials = (name: string) =>
  name.split(/\s+/).filter(Boolean).slice(0, 2).map((w) => w[0]!.toUpperCase()).join('') || '?'

/** Score ink by band: strong / borderline / low. */
const scoreTone = (score: number) =>
  score >= 80 ? 'text-success' : score >= 65 ? 'text-warning' : 'text-neutral-900'

export default function SessionsPage() {
  const qc = useQueryClient()
  const navigate = useNavigate()
  const [open, setOpen] = useState(false)
  const [genOpen, setGenOpen] = useState(false)
  const [createdLink, setCreatedLink] = useState<string | null>(null)

  const sessions = useQuery({ queryKey: ['sessions'], queryFn: sessionsApi.list })
  const templates = useQuery({ queryKey: ['templates'], queryFn: templatesApi.list })
  // Whether a Video Avatar config has been applied (Setup page) — gates the
  // Conversational AI mode: without it, candidate avatar interviews can't start.
  const avatarApplied = useQuery({ queryKey: ['avatar-settings'], queryFn: settingsApi.avatarStatus })

  const [templateId, setTemplateId] = useState('')
  const [name, setName] = useState('')
  const [email, setEmail] = useState('')
  const [track, setTrack] = useState<TrackType | ''>('')
  const [timerOn, setTimerOn] = useState(true)
  const [timerSeconds, setTimerSeconds] = useState(120)

  // Reflect the selected template's effective timer state (chat templates
  // inherit their answer limit on the chatbot track, so they default ON).
  useEffect(() => {
    const tpl = templates.data?.find((t) => t.id === templateId)
    if (!tpl) return
    setTimerOn(tpl.chatbotTimer ? !!tpl.chatbotTimer.enabled : tpl.track === 'chat' || tpl.mode === 'timed')
    setTimerSeconds(tpl.chatbotTimer?.perQuestionSeconds ?? tpl.timing?.answerSeconds ?? 120)
  }, [templateId, templates.data])

  const create = useMutation({
    mutationFn: async () => {
      // Persist the timer choice on the template FIRST so the session (and any
      // future one from this template) runs with exactly what's shown here.
      const tpl = templates.data?.find((t) => t.id === templateId)
      if (tpl) {
        const chatbotTimer = {
          timeFollowUps: true, includeThinkingPhase: false, warningThresholdSeconds: 15,
          allowEarlySubmit: true, autoSubmitOnExpiry: true,
          ...(tpl.chatbotTimer ?? {}),
          enabled: timerOn,
          perQuestionSeconds: timerSeconds,
        }
        await templatesApi.update(templateId, timerOn
          ? { chatbotTimer, timing: { ...tpl.timing, answerSeconds: timerSeconds } } // keep Timed Q&A in sync
          : { chatbotTimer })
        qc.invalidateQueries({ queryKey: ['templates'] })
      }
      return sessionsApi.create({
        templateId,
        candidate: { name: name || 'Candidate', email },
        track: track || undefined,
      })
    },
    onSuccess: ({ id }) => {
      const link = `${window.location.origin}/take/${id}`
      setCreatedLink(link)
      qc.invalidateQueries({ queryKey: ['sessions'] })
      toast.success('Session created')
    },
    onError: (e: Error) => toast.error(e.message),
  })

  const openCreate = () => {
    setCreatedLink(null)
    setTemplateId(templates.data?.[0]?.id ?? '')
    setName('')
    setEmail('')
    setTrack('')
    setOpen(true)
  }

  return (
    <div className="max-w-[1440px] mx-auto px-6 py-8">
      <PageHeader
        kicker="AI Interview"
        title="Sessions"
        description="Create interview links for candidates and review their scored results."
        action={
          <div className="flex items-center gap-2">
            <Button variant="secondary" onClick={openCreate}>+ Single link</Button>
            <Button variant="mint" onClick={() => navigate('/sessions/new')}>Invite candidates</Button>
          </div>
        }
      />

      {sessions.isLoading ? (
        <Card className="overflow-hidden p-0" aria-hidden="true">
          <div className="border-b border-border px-5 py-3.5">
            <Skeleton className="h-3 w-52" />
          </div>
          {[0, 1, 2, 3].map((i) => (
            <div key={i} className="flex items-center gap-4 border-b border-border px-5 py-4 last:border-0">
              <Skeleton className="h-8 w-8 flex-shrink-0 rounded-full" />
              <div className="min-w-0 flex-1 space-y-2">
                <Skeleton className="h-3 w-40 max-w-full" />
                <Skeleton className="h-2.5 w-56 max-w-full" />
              </div>
              <Skeleton className="hidden h-5 w-24 rounded-full sm:block" />
              <Skeleton className="hidden h-5 w-20 rounded-full md:block" />
              <Skeleton className="h-5 w-10" />
            </div>
          ))}
        </Card>
      ) : sessions.isError ? (
        /* Without this branch a failed fetch fell through to the empty state,
           telling a recruiter their sessions don't exist when the server was
           simply unreachable. Say what actually happened, and reassure. */
        <Card className="p-0">
          <EmptyState
            icon={<AlertTriangle strokeWidth={1.75} />}
            title="Couldn't load your sessions"
            description="Nothing has been lost — this view just couldn't reach the server. Check your connection and try again."
            action={
              <Button variant="outline" onClick={() => sessions.refetch()} icon={<RefreshCw size={14} />}>
                Try again
              </Button>
            }
          />
        </Card>
      ) : !sessions.data?.length ? (
        <Card className="p-0">
          <EmptyState
            icon={<Mic strokeWidth={1.75} />}
            title="No interview sessions yet"
            description="Create a session to generate a candidate link. Once they finish, scored results appear here."
            action={<Button onClick={openCreate} icon={<Plus size={15} />}>New session</Button>}
          />
        </Card>
      ) : (
        <Card className="overflow-hidden p-0">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border text-left text-[11px] font-semibold uppercase tracking-wide text-neutral-500">
                  <th className="px-5 py-3">Candidate</th>
                  <th className="px-5 py-3">Template</th>
                  <th className="px-5 py-3">Track</th>
                  <th className="px-5 py-3">Status</th>
                  <th className="px-5 py-3 text-right">Score</th>
                  <th className="px-5 py-3 text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {sessions.data.map((s: SessionListItem) => (
                  <tr key={s.id} className="border-b border-border last:border-0 transition-colors duration-150 hover:bg-primary-50/40">
                    <td className="px-5 py-3.5">
                      <div className="flex items-center gap-3">
                        <span
                          aria-hidden="true"
                          className="flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full bg-primary-100 text-xs font-bold text-primary-800"
                        >
                          {initials(s.candidate.name)}
                        </span>
                        <div className="min-w-0">
                          <div className="truncate font-semibold text-neutral-900">{s.candidate.name}</div>
                          {/* Unnamed candidates fall back to their email in the
                              line above; repeating it here reads as a bug. */}
                          {s.candidate.email && s.candidate.email !== s.candidate.name && (
                            <div className="truncate text-xs text-neutral-400">{s.candidate.email}</div>
                          )}
                        </div>
                      </div>
                    </td>
                    <td className="px-5 py-3.5 text-neutral-600">{s.templateName}</td>
                    <td className="px-5 py-3.5">
                      <Badge variant="neutral">{TRACK_LABEL[s.track] ?? 'Chat'}</Badge>
                    </td>
                    <td className="px-5 py-3.5">
                      <Badge variant={statusVariant[s.status] ?? 'neutral'}>{s.status.replace('_', ' ')}</Badge>
                    </td>
                    <td className="px-5 py-3.5 text-right">
                      {typeof s.overallScore === 'number' ? (
                        <span className={cn('text-lg font-bold tabular-nums', scoreTone(s.overallScore))}>
                          {s.overallScore}
                        </span>
                      ) : (
                        <span className="text-neutral-400">—</span>
                      )}
                    </td>
                    <td className="px-5 py-3.5">
                      <div className="flex items-center justify-end gap-3">
                        <button
                          onClick={() => {
                            navigator.clipboard.writeText(`${window.location.origin}/take/${s.id}`)
                            toast.success('Candidate link copied')
                          }}
                          className="text-xs font-medium text-neutral-500 transition-colors duration-150 hover:text-primary-700"
                        >
                          Copy link
                        </button>
                        {s.track === 'two_way' && s.status !== 'completed' && s.status !== 'expired' && (
                          <Link
                            to={`/live/${s.id}`}
                            className="text-xs font-semibold text-primary-700 hover:underline"
                          >
                            Join live interview →
                          </Link>
                        )}
                        {s.status === 'completed' && (
                          <Link
                            to={`/sessions/${s.id}/report`}
                            className="text-xs font-semibold text-primary-700 hover:underline"
                          >
                            View report →
                          </Link>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      <Modal open={open} onClose={() => setOpen(false)} title="New interview session" description="Generates a shareable candidate link.">
        {createdLink ? (
          <div className="space-y-5">
            <div className="flex items-start gap-3 rounded-xl border border-mint-border bg-mint-bg p-4">
              <span className="mt-0.5 flex h-7 w-7 flex-shrink-0 items-center justify-center rounded-full bg-mint text-neutral-900">
                <Check size={15} strokeWidth={2.5} />
              </span>
              <div>
                <p className="text-sm font-semibold text-neutral-900">Interview link ready</p>
                <p className="mt-0.5 text-xs leading-relaxed text-neutral-600">
                  Share it with the candidate — the link opens their interview directly.
                </p>
              </div>
            </div>
            <div>
              <span className="field-label">Candidate link</span>
              <div className="flex items-center gap-2">
                <input
                  readOnly
                  value={createdLink}
                  aria-label="Candidate interview link"
                  className="input-base flex-1 font-mono text-xs"
                />
                <Button
                  variant="secondary"
                  icon={<Copy size={14} />}
                  onClick={() => { navigator.clipboard.writeText(createdLink); toast.success('Link copied') }}
                >
                  Copy
                </Button>
              </div>
            </div>
            <div className="flex justify-end gap-2 border-t border-border pt-4">
              <Button variant="ghost" onClick={() => setOpen(false)}>Close</Button>
              <a href={createdLink} target="_blank" rel="noreferrer">
                <Button icon={<ExternalLink size={14} />}>Open as candidate</Button>
              </a>
            </div>
          </div>
        ) : (
          <div className="space-y-5">
            <div>
              <Select
                label="Template"
                value={templateId}
                onChange={(e) => setTemplateId(e.target.value)}
                options={(templates.data ?? []).map((t) => ({ value: t.id, label: `${t.name} (${t.questionSource})` }))}
              />
              <button
                type="button"
                onClick={() => { setOpen(false); setGenOpen(true) }}
                className="mt-2 inline-flex items-center gap-1.5 text-xs font-semibold text-primary-700 hover:underline"
              >
                <Sparkles size={13} /> Generate questions from a résumé instead
              </button>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <Input label="Candidate name" value={name} onChange={(e) => setName(e.target.value)} placeholder="Jane Doe" />
              <Input label="Candidate email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="jane@example.com" />
            </div>
            <div>
              <Select
                label="Interview mode (optional override)"
                value={track}
                onChange={(e) => {
                  const v = e.target.value as TrackType | ''
                  // Conversational AI needs an APPLIED avatar setup (replica,
                  // persona, greeting — configured once on the Setup page and
                  // applied to all candidates). Not applied yet → take the
                  // recruiter there; applied → the mode is ready to use.
                  if (v === 'video_avatar' && !avatarApplied.data?.configured) {
                    setOpen(false)
                    toast('Configure your AI avatar once — it then applies to all Conversational AI candidates.')
                    navigate('/setup', { state: { candidateName: name.trim() || undefined, returnTo: '/sessions' } })
                    return
                  }
                  setTrack(v)
                }}
                hint="Best set on the template. Conversational AI uses the avatar applied on the Setup page."
                options={[
                  { value: '', label: 'Use template default' },
                  { value: 'chatbot', label: 'Chatbot — conversational, typed (ChatGPT-style)' },
                  { value: 'voice', label: 'Voice — live spoken AI interviewer (Gemini Live)' },
                  { value: 'chat', label: 'Timed Q&A — 30s prep + 2 min answer (HireVue-style)' },
                  { value: 'video_avatar', label: 'Conversational AI — Video Avatar (Tavus)' },
                ]}
              />
              {track === 'video_avatar' && avatarApplied.data?.configured && (
                <p className="mt-1.5 flex items-start gap-1.5 text-xs text-success">
                  <Check size={13} strokeWidth={2.5} className="mt-0.5 flex-shrink-0" />
                  <span>
                    Uses your applied avatar{avatarApplied.data.replicaId ? <> (<span className="font-mono">{avatarApplied.data.replicaId}</span>)</> : null} —{' '}
                    <button type="button" className="font-semibold text-primary-700 underline underline-offset-2" onClick={() => { setOpen(false); navigate('/setup', { state: { returnTo: '/sessions' } }) }}>
                      edit avatar setup
                    </button>
                  </span>
                </p>
              )}
            </div>
            <div className="space-y-3 rounded-xl border border-border bg-neutral-50 p-4">
              <Toggle
                label="Per-question timer"
                description="Each question gets its own answer countdown (greetings, “are you ready?” and wrap-up are never timed). Applies to the Chatbot and Timed Q&A tracks."
                checked={timerOn}
                onChange={setTimerOn}
              />
              {timerOn && (
                <Input
                  label="Answer time per question (seconds)"
                  type="number"
                  min={10}
                  value={timerSeconds}
                  onChange={(e) => setTimerSeconds(Math.max(10, Number(e.target.value) || 120))}
                  hint={`Candidates get ${Math.floor(timerSeconds / 60)}:${String(timerSeconds % 60).padStart(2, '0')} per question; auto-submits at 0.`}
                />
              )}
            </div>
            <div className="flex justify-end gap-2 border-t border-border pt-4">
              <Button variant="ghost" onClick={() => setOpen(false)}>Cancel</Button>
              <Button loading={create.isPending} disabled={!templateId} onClick={() => create.mutate()}>
                Create session
              </Button>
            </div>
          </div>
        )}
      </Modal>

      <GenerateFromResumeModal
        open={genOpen}
        onClose={() => { setGenOpen(false); setOpen(true) }}
        onSaved={async (set) => {
          try {
            const tpl = await templatesApi.create({
              name: set.name,
              role: '',
              track: 'chat',
              questionSource: 'fixed',
              fixedQuestionSetId: set.id,
            })
            await qc.invalidateQueries({ queryKey: ['templates'] })
            setTemplateId(tpl.id)
            toast.success(`Template “${tpl.name}” created and selected`)
          } catch {
            toast.error('Set saved, but creating a template from it failed')
          }
        }}
      />
    </div>
  )
}
