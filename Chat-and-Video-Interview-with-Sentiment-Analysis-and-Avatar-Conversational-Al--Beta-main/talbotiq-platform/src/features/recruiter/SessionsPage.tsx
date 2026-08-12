import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { Sparkles } from 'lucide-react'
import {
  PageHeader, Card, Button, Input, Select, Badge, EmptyState, Skeleton, Modal, Toggle,
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
            <Button onClick={() => navigate('/sessions/new')}>Invite candidates</Button>
          </div>
        }
      />

      {sessions.isLoading ? (
        <div className="space-y-3">{[0, 1, 2].map((i) => <Skeleton key={i} className="h-16 w-full" />)}</div>
      ) : !sessions.data?.length ? (
        <Card className="p-0">
          <EmptyState
            icon="🎤"
            title="No interview sessions yet"
            description="Create a session to generate a candidate link. Once they finish, scored results appear here."
            action={<Button onClick={openCreate}>+ New session</Button>}
          />
        </Card>
      ) : (
        <Card className="overflow-hidden p-0">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-border text-left text-xs font-semibold uppercase tracking-wide text-neutral-500">
                <th className="px-5 py-3">Candidate</th>
                <th className="px-5 py-3">Template</th>
                <th className="px-5 py-3">Track</th>
                <th className="px-5 py-3">Status</th>
                <th className="px-5 py-3">Score</th>
                <th className="px-5 py-3 text-right">Actions</th>
              </tr>
            </thead>
            <tbody>
              {sessions.data.map((s: SessionListItem) => (
                <tr key={s.id} className="border-b border-border last:border-0 hover:bg-neutral-50">
                  <td className="px-5 py-3">
                    <div className="font-medium text-neutral-800">{s.candidate.name}</div>
                    <div className="text-xs text-neutral-400">{s.candidate.email || '—'}</div>
                  </td>
                  <td className="px-5 py-3 text-neutral-600">{s.templateName}</td>
                  <td className="px-5 py-3 text-neutral-600">
                    {s.track === 'video_avatar' ? 'Video Avatar' : s.track === 'voice' ? 'Voice' : s.track === 'chatbot' ? 'Chatbot' : s.track === 'video' ? 'Video Interview' : s.track === 'two_way' ? 'Two-way Interview' : 'Chat'}
                  </td>
                  <td className="px-5 py-3">
                    <Badge variant={statusVariant[s.status] ?? 'neutral'}>{s.status.replace('_', ' ')}</Badge>
                  </td>
                  <td className="px-5 py-3 font-mono tabular-nums">
                    {typeof s.overallScore === 'number' ? s.overallScore : '—'}
                  </td>
                  <td className="px-5 py-3">
                    <div className="flex items-center justify-end gap-2">
                      <button
                        onClick={() => {
                          navigator.clipboard.writeText(`${window.location.origin}/take/${s.id}`)
                          toast.success('Candidate link copied')
                        }}
                        className="text-xs font-medium text-neutral-600 hover:text-neutral-900"
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
        </Card>
      )}

      <Modal open={open} onClose={() => setOpen(false)} title="New interview session" description="Generates a shareable candidate link.">
        {createdLink ? (
          <div className="space-y-4">
            <p className="text-sm text-neutral-600">Share this link with the candidate:</p>
            <div className="flex items-center gap-2">
              <input readOnly value={createdLink} className="input-base flex-1 font-mono text-xs" />
              <Button variant="secondary" onClick={() => { navigator.clipboard.writeText(createdLink); toast.success('Copied') }}>
                Copy
              </Button>
            </div>
            <div className="flex justify-end gap-2 pt-2">
              <Button variant="ghost" onClick={() => setOpen(false)}>Close</Button>
              <a href={createdLink} target="_blank" rel="noreferrer">
                <Button>Open as candidate ↗</Button>
              </a>
            </div>
          </div>
        ) : (
          <div className="space-y-4">
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
                <p className="mt-1.5 text-xs text-primary-700">
                  ✓ Uses your applied avatar{avatarApplied.data.replicaId ? <> (<span className="font-mono">{avatarApplied.data.replicaId}</span>)</> : null} —{' '}
                  <button type="button" className="font-semibold underline" onClick={() => { setOpen(false); navigate('/setup', { state: { returnTo: '/sessions' } }) }}>
                    edit avatar setup
                  </button>
                </p>
              )}
            </div>
            <div className="space-y-3 rounded-xl border border-border bg-neutral-50/60 p-3">
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
            <div className="flex justify-end gap-2 pt-2">
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
