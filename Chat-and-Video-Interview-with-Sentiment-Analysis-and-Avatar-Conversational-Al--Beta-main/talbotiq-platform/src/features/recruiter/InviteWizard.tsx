import { useCallback, useMemo, useRef, useState } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { MessageSquare, Mic, Video, Clock, Clapperboard, Users, ArrowLeft, Check, FileText, Layers, Plus, UploadCloud, Trash2, AlertTriangle, Loader2, CheckCircle2, Copy, Mail, RefreshCw } from 'lucide-react'
import { Button, Input, Skeleton, Badge, cn } from '@/components/ui'
import { questionSetsApi, invitesApi, settingsApi, pipelinesApi } from '@/lib/api'
import { GenerateFromResumeModal } from './GenerateFromResumeModal'
import { InviteEmailStep } from './invite-email/InviteEmailStep'
import { ReviewSend } from './invite-email/ReviewSend'
import { RoundBuilder, defaultRounds, toRoundDefs, type RoundDraft } from './RoundBuilder'
import { defaultInviteEmailTemplate, validateLockedTokens } from '@shared/inviteEmail'
import type { TrackType, QuestionStyle, DifficultyChoice, GeminiModel, QuestionSet, CreateInvitesResult, InviteEmailTemplate } from '@shared/types'
import { useAutopilotActions } from '@/features/guide/autopilot/registry'

const emailOk = (e: string) => /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(e.trim())

/**
 * Invite-first recruiter wizard (bulk invite).
 *
 * New model: the recruiter never uploads a résumé. They pick the interview MODE
 * and the candidate ROLE, choose a question source (tailor-per-résumé or a saved
 * set), then invite candidates in bulk — each candidate uploads their own résumé
 * when they begin, and the interview auto-configures to these settings.
 *
 * Implemented: shell + Step 1 (mode + role) + Step 2 (question source + config).
 * Step 3 (candidates + send) and the final "create invites" submit are wired once
 * the Firestore `interviews` schema + Admin credentials + email provider are in place.
 */

type Mode = Extract<TrackType, 'chatbot' | 'voice' | 'video_avatar' | 'chat' | 'video' | 'two_way'>
type Source = 'tailor' | 'set'

const MODES: { value: Mode; label: string; blurb: string; icon: React.ReactNode }[] = [
  { value: 'chatbot',      label: 'Chatbot',      blurb: 'Conversational, typed — ChatGPT-style.',   icon: <MessageSquare size={20} /> },
  { value: 'voice',        label: 'Voice',        blurb: 'Live spoken AI interviewer (Gemini Live).', icon: <Mic size={20} /> },
  { value: 'video_avatar', label: 'Video Avatar', blurb: 'Conversational AI video avatar (Tavus).',   icon: <Video size={20} /> },
  { value: 'chat',         label: 'Timed Q&A',    blurb: '30s prep + timed answers (HireVue-style).', icon: <Clock size={20} /> },
  { value: 'video',        label: 'Video Interview', blurb: 'Candidate records webcam answers per question.', icon: <Clapperboard size={20} /> },
  { value: 'two_way',      label: 'Two-way Interview', blurb: 'Live recruiter ↔ candidate video interview.', icon: <Users size={20} /> },
]

const STYLES: { value: QuestionStyle; label: string }[] = [
  { value: 'technical', label: 'Technical' },
  { value: 'non_technical', label: 'Non-technical' },
  { value: 'mix', label: 'Mix' },
]
const DIFFICULTIES: DifficultyChoice[] = ['easy', 'medium', 'hard', 'mixed']

const STEPS = [
  { n: 1, title: 'Basics', hint: 'Mode & role' },
  { n: 2, title: 'Questions', hint: 'Tailor or reuse' },
  { n: 3, title: 'Candidates', hint: 'Add recipients' },
  { n: 4, title: 'Invite email', hint: 'Configure & test' },
  { n: 5, title: 'Review', hint: 'Confirm & send' },
] as const

/** Config the interview auto-applies per candidate (persisted on the invite at submit). */
export interface TailorConfig {
  style: QuestionStyle
  techCount: number
  nonTechCount: number
  difficulty: DifficultyChoice
  domains: string[]
  model: GeminiModel
}

function Stepper({ step }: { step: number }) {
  return (
    <div className="flex items-center gap-2">
      {STEPS.map((s, i) => {
        const done = step > s.n
        const active = step === s.n
        return (
          <div key={s.n} className="flex items-center gap-2">
            <div className="flex items-center gap-2.5">
              <span className={cn(
                'flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-full text-sm font-bold transition-colors',
                done ? 'bg-primary-700 text-white' : active ? 'bg-primary-700 text-white ring-4 ring-primary-100' : 'bg-neutral-100 text-neutral-400',
              )}>
                {done ? <Check size={15} /> : s.n}
              </span>
              <div className="hidden sm:block">
                <p className={cn('text-sm font-semibold leading-tight', active || done ? 'text-neutral-800' : 'text-neutral-400')}>{s.title}</p>
                <p className="text-[11px] text-neutral-400">{s.hint}</p>
              </div>
            </div>
            {i < STEPS.length - 1 && <div className={cn('mx-1 h-px w-8 sm:w-12', done ? 'bg-primary-700' : 'bg-border')} />}
          </div>
        )
      })}
    </div>
  )
}

/** §2 config panel — role is read-only (from Step 1); NO "question set name". */
function TailorConfigPanel({ role, cfg, setCfg }: { role: string; cfg: TailorConfig; setCfg: (c: TailorConfig) => void }) {
  const [domainDraft, setDomainDraft] = useState('')
  const total = cfg.style === 'mix' ? cfg.techCount + cfg.nonTechCount : cfg.style === 'technical' ? cfg.techCount : cfg.nonTechCount
  const addDomain = () => {
    const v = domainDraft.trim()
    if (v && !cfg.domains.includes(v)) setCfg({ ...cfg, domains: [...cfg.domains, v] })
    setDomainDraft('')
  }
  return (
    <div className="mt-4 space-y-5 rounded-xl border border-border bg-white p-5">
      {/* role (read-only, from Step 1) */}
      <div>
        <label className="field-label mb-1.5 block">Role</label>
        <div className="flex h-11 items-center rounded-lg border border-border bg-neutral-50 px-3 text-sm text-neutral-700">
          {role} <span className="ml-2 text-xs text-neutral-400">(set in Step 1)</span>
        </div>
      </div>

      {/* style */}
      <div>
        <label className="field-label mb-1.5 block">Question style</label>
        <div className="grid grid-cols-3 gap-2">
          {STYLES.map((s) => (
            <button key={s.value} type="button" onClick={() => setCfg({ ...cfg, style: s.value })}
              className={cn('rounded-lg border px-3 py-2 text-sm font-semibold transition-all',
                cfg.style === s.value ? 'border-primary-700 bg-primary-700 text-white' : 'border-border bg-white text-neutral-600 hover:border-neutral-300')}>
              {s.label}
            </button>
          ))}
        </div>
      </div>

      {/* counts */}
      {cfg.style === 'mix' ? (
        <div className="grid grid-cols-2 gap-4">
          <Input label="# Technical" type="number" min={0} max={25} value={cfg.techCount} onChange={(e) => setCfg({ ...cfg, techCount: Math.max(0, Number(e.target.value)) })} />
          <Input label="# Non-technical" type="number" min={0} max={25} value={cfg.nonTechCount} onChange={(e) => setCfg({ ...cfg, nonTechCount: Math.max(0, Number(e.target.value)) })} />
        </div>
      ) : (
        <Input label="Number of questions" type="number" min={1} max={25}
          value={cfg.style === 'technical' ? cfg.techCount : cfg.nonTechCount}
          onChange={(e) => { const v = Math.max(1, Number(e.target.value)); setCfg(cfg.style === 'technical' ? { ...cfg, techCount: v } : { ...cfg, nonTechCount: v }) }} />
      )}
      {(total < 1 || total > 25) && <p className="text-xs text-danger">Total questions must be between 1 and 25 (currently {total}).</p>}

      {/* difficulty */}
      <div>
        <label className="field-label mb-1.5 block">Difficulty</label>
        <div className="grid grid-cols-4 gap-2">
          {DIFFICULTIES.map((d) => (
            <button key={d} type="button" onClick={() => setCfg({ ...cfg, difficulty: d })}
              className={cn('rounded-lg border px-2 py-1.5 text-xs font-semibold capitalize transition-all',
                cfg.difficulty === d ? 'border-primary-700 bg-primary-50 text-primary-700' : 'border-border bg-white text-neutral-500 hover:border-neutral-300')}>
              {d}
            </button>
          ))}
        </div>
      </div>

      {/* domains (focus topics) */}
      <div>
        <label className="field-label mb-1.5 block">Domains <span className="font-normal normal-case text-neutral-400">(optional focus areas)</span></label>
        <div className="flex gap-2">
          <input value={domainDraft} onChange={(e) => setDomainDraft(e.target.value)}
            onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addDomain() } }}
            placeholder="e.g. Distributed systems, SQL, System design" className="input-base flex-1" />
          <Button variant="secondary" onClick={addDomain} disabled={!domainDraft.trim()}>Add</Button>
        </div>
        {cfg.domains.length > 0 && (
          <div className="mt-2 flex flex-wrap gap-1.5">
            {cfg.domains.map((d) => (
              <span key={d} className="inline-flex items-center gap-1 rounded-full bg-primary-50 px-2.5 py-1 text-xs font-medium text-primary-700">
                {d}
                <button onClick={() => setCfg({ ...cfg, domains: cfg.domains.filter((x) => x !== d) })} className="text-primary-400 hover:text-primary-700">×</button>
              </span>
            ))}
          </div>
        )}
      </div>

      {/* model */}
      <div className="flex items-center justify-between rounded-lg bg-neutral-50 px-3 py-2">
        <span className="text-xs font-medium text-neutral-500">Model</span>
        <div className="flex gap-1">
          {(['gemini-2.5-flash', 'gemini-2.5-pro'] as GeminiModel[]).map((m) => (
            <button key={m} type="button" onClick={() => setCfg({ ...cfg, model: m })}
              className={cn('rounded-md px-2.5 py-1 text-xs font-semibold', cfg.model === m ? 'bg-primary-700 text-white' : 'text-neutral-500 hover:bg-neutral-200')}>
              {m.replace('gemini-2.5-', '')}
            </button>
          ))}
        </div>
      </div>
    </div>
  )
}

export default function InviteWizard() {
  const navigate = useNavigate()
  const location = useLocation()
  const qc = useQueryClient()
  const [step, setStep] = useState(1)

  // Step 1 — mode is preselected when returning from the avatar Setup page.
  const [mode, setMode] = useState<Mode | ''>(
    (location.state as { mode?: Mode } | null)?.mode ?? '',
  )
  const [role, setRole] = useState('')
  // Single interview (default, unchanged behavior) vs. an ordered set of rounds
  // (multi) — round modes are chosen per-round in Step 2, not here.
  const [setupType, setSetupType] = useState<'single' | 'multi'>('single')
  // Video Avatar requires an APPLIED avatar setup (configured once, applies to
  // every candidate in the batch) — gate the mode card on it.
  const avatarApplied = useQuery({ queryKey: ['avatar-settings'], queryFn: settingsApi.avatarStatus })

  // Step 2
  const [source, setSource] = useState<Source | ''>('')
  const [cfg, setCfg] = useState<TailorConfig>({ style: 'mix', techCount: 5, nonTechCount: 3, difficulty: 'mixed', domains: [], model: 'gemini-2.5-flash' })
  const [selectedSetId, setSelectedSetId] = useState('')
  const [genOpen, setGenOpen] = useState(false)
  // Step 2 (multi) — the ordered rounds being authored; modes/config are per-round.
  const [rounds, setRounds] = useState<RoundDraft[]>(defaultRounds())

  // Step 3
  const [candidates, setCandidates] = useState<{ id: string; email: string; role: string }[]>([])
  const [manualEmail, setManualEmail] = useState('')
  const [warnings, setWarnings] = useState<string[]>([])
  const [extracting, setExtracting] = useState(false)
  const [fileError, setFileError] = useState<string | null>(null)
  const [dragOver, setDragOver] = useState(false)
  const fileInput = useRef<HTMLInputElement>(null)
  const [creating, setCreating] = useState(false)
  const [result, setResult] = useState<CreateInvitesResult | null>(null)
  const [retrying, setRetrying] = useState<Set<string>>(new Set())

  // Step 4 — the invite email config (a full template draft; server ignores the
  // synthetic id/owner/timestamps). Preloaded with the sensible default; the recruiter
  // can load/save their own saved templates in the step itself.
  const [emailDraft, setEmailDraft] = useState<InviteEmailTemplate>(() => ({
    id: 'draft',
    recruiterId: '',
    createdAt: '',
    updatedAt: '',
    ...defaultInviteEmailTemplate(),
  }))

  const sets = useQuery({ queryKey: ['question-sets'], queryFn: questionSetsApi.list, enabled: step === 2 && mode !== 'two_way' })

  const validCount = candidates.filter((c) => emailOk(c.email)).length
  const validCandidates = candidates.filter((c) => emailOk(c.email)).map((c) => ({ email: c.email.trim(), role: c.role.trim() || role }))
  const sampleEmail = validCandidates[0]?.email || 'candidate@example.com'
  const emailLocked = validateLockedTokens(emailDraft.subject, emailDraft.bodyHtml)
  const emailConfigPayload = (): Partial<InviteEmailTemplate> => ({
    name: emailDraft.name,
    sender: emailDraft.sender,
    subject: emailDraft.subject,
    bodyHtml: emailDraft.bodyHtml,
    cta: emailDraft.cta,
    branding: emailDraft.branding,
    deadlineText: emailDraft.deadlineText,
  })

  const mergeRows = (incoming: { email: string; role: string }[]) => {
    setCandidates((prev) => {
      const seen = new Set(prev.map((c) => c.email.trim().toLowerCase()))
      const add = incoming
        .filter((r) => r.email.trim() && !seen.has(r.email.trim().toLowerCase()))
        .map((r) => ({ id: crypto.randomUUID(), email: r.email.trim(), role: (r.role || role).trim() }))
      return [...prev, ...add]
    })
  }

  const onFile = async (f: File | null) => {
    setFileError(null); setWarnings([])
    if (!f) return
    setExtracting(true)
    try {
      const before = candidates.length
      const result = await invitesApi.extract(f, role)
      mergeRows(result.rows)
      setWarnings(result.warnings)
      if (!result.rows.length) setFileError('No email addresses found in that file.')
      else toast.success(`Found ${result.rows.length} email${result.rows.length === 1 ? '' : 's'}`)
      void before
    } catch (e) {
      setFileError(e instanceof Error ? e.message : 'Could not read that file.')
    } finally {
      setExtracting(false)
      if (fileInput.current) fileInput.current.value = ''
    }
  }

  const addManual = () => {
    const e = manualEmail.trim()
    if (!e) return
    if (candidates.some((c) => c.email.toLowerCase() === e.toLowerCase())) { toast('That email is already in the list'); setManualEmail(''); return }
    setCandidates((prev) => [...prev, { id: crypto.randomUUID(), email: e, role }])
    setManualEmail('')
  }

  const submit = async () => {
    if (setupType === 'multi') {
      if (validCount === 0 || !step2ValidMulti) return
      if (!emailLocked.ok) { toast.error(`The invite email is missing the interview link (${emailLocked.missing.join(', ')})`); return }
      setCreating(true)
      try {
        const pipeline = await pipelinesApi.create({ role: role.trim(), rounds: toRoundDefs(rounds) })
        const res = await pipelinesApi.inviteRound1(pipeline.id, {
          candidates: validCandidates,
          origin: window.location.origin,
          emailConfig: emailConfigPayload(),
          sendEmails: true,
        })
        setResult({
          testId: pipeline.id,
          created: res.created,
          emailed: res.emailed,
          dryRun: res.dryRun,
        } as CreateInvitesResult)
        toast.success(`Pipeline created — invited ${res.created.length} to Round 1`)
      } catch (e) {
        toast.error(e instanceof Error ? e.message : 'Could not create the pipeline')
      } finally {
        setCreating(false)
      }
      return
    }
    // Two-way Interview has no scripted question source (live recruiter-led
    // call) — every other mode requires one.
    if (!mode || (mode !== 'two_way' && !source) || validCount === 0) return
    if (!emailLocked.ok) { toast.error(`The invite email is missing the interview link (${emailLocked.missing.join(', ')})`); return }
    setCreating(true)
    try {
      const res = await invitesApi.create({
        mode: mode as Mode,
        role: role.trim(),
        ...(mode !== 'two_way' ? { source: source as Source } : {}),
        config: source === 'tailor' ? { style: cfg.style, techCount: cfg.techCount, nonTechCount: cfg.nonTechCount, difficulty: cfg.difficulty, domains: cfg.domains, model: cfg.model } : undefined,
        questionSetId: source === 'set' ? selectedSetId : undefined,
        candidates: validCandidates,
        origin: window.location.origin,
        emailConfig: emailConfigPayload(),
        sendEmails: true,
      })
      setResult(res)
      toast.success(`Created ${res.created.length} invite${res.created.length === 1 ? '' : 's'}`)
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Could not create invites')
    } finally {
      setCreating(false)
    }
  }

  const retryOne = async (id: string) => {
    setRetrying((s) => new Set(s).add(id))
    try {
      const r = await invitesApi.retry(id, { role: role.trim(), origin: window.location.origin, emailConfig: emailConfigPayload() })
      setResult((prev) => prev && ({
        ...prev,
        emailed: prev.emailed + (r.sent ? 1 : 0),
        created: prev.created.map((c) => c.id === id ? { ...c, sent: r.sent, status: r.status as CreateInvitesResult['created'][number]['status'], error: r.error } : c),
      }))
      if (r.sent) toast.success(`Resent to ${r.email}`)
      else toast.error(r.error || 'Retry failed')
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Retry failed')
    } finally {
      setRetrying((s) => { const n = new Set(s); n.delete(id); return n })
    }
  }

  // ── Autopilot instrumentation (additive; no existing behavior changes) ──
  // Autopilot reads the LATEST wizard state through this ref (registered once).
  const apStateRef = useRef({ step, setupType, mode, role, source, selectedSetId, candidates, cfg, step1Valid: false, step2Valid: false, step2ValidMulti: false, validCount: 0, emailLockedOk: false })
  // (.current is refreshed BELOW, after the validity flags are computed each render)

  // Add a candidate by explicit email/role (Autopilot path; mirrors addManual's dedupe).
  const addCandidateDirect = (email: string, r: string) => {
    const e = email.trim().toLowerCase()
    if (!e) return
    setCandidates((cs) => (cs.some((c) => c.email.toLowerCase() === e) ? cs : [...cs, { id: crypto.randomUUID(), email: email.trim(), role: (r || role).trim() }]))
  }
  // Advance only if the current step is valid (else no-op; Autopilot re-reads state and asks).
  const guardedNext = () => {
    // Read validity from the live ref — NOT the render closure (the action defs are
    // registered once, so a closure read would be frozen at first-render values).
    // Mirrors the REAL wizard's per-step Next gating exactly, so Autopilot can
    // never skip past Candidates with 0 recipients or a broken invite email.
    const s = apStateRef.current
    const ok =
      s.step === 1 ? s.step1Valid
      : s.step === 2 ? (s.setupType === 'multi' ? s.step2ValidMulti : s.step2Valid)
      : s.step === 3 ? s.validCount > 0
      : s.step === 4 ? s.emailLockedOk
      : true
    if (ok) setStep((n) => Math.min(n + 1, STEPS.length))
  }

  // Route the memoized action defs through this ref so they always invoke the
  // CURRENT render's handlers — a stale guardedNext saw step1Valid=false forever
  // (silent nextStep no-op), and a stale submit() would send first-render state.
  const apFnsRef = useRef({ guardedNext, addCandidateDirect, submit })
  apFnsRef.current = { guardedNext, addCandidateDirect, submit }

  const apActions = useMemo(() => ({
    setInterviewType: { description: 'Choose Single Interview or Multiple Rounds', params: [{ name: 'type', type: 'enum' as const, enum: ['single', 'multi'], required: true }], run: (a: any) => setSetupType(a.type) },
    selectMode: { description: 'Select the interview mode', params: [{ name: 'mode', type: 'enum' as const, enum: MODES.map((m) => m.value), required: true }], run: (a: any) => setMode(a.mode) },
    setRole: { description: 'Set the candidate role/title', params: [{ name: 'role', type: 'string' as const, required: true }], run: (a: any) => setRole(a.role) },
    setQuestionSource: { description: 'Choose question source: tailor (adaptive) or set (a saved question set)', params: [{ name: 'source', type: 'enum' as const, enum: ['tailor', 'set'], required: true }], run: (a: any) => setSource(a.source) },
    selectQuestionSet: { description: 'Pick a saved question set by id', params: [{ name: 'id', type: 'string' as const, required: true }], run: (a: any) => setSelectedSetId(a.id) },
    addCandidate: { description: 'Add a candidate by email', params: [{ name: 'email', type: 'string' as const, required: true }, { name: 'role', type: 'string' as const }], run: (a: any) => apFnsRef.current.addCandidateDirect(a.email, a.role) },
    nextStep: { description: 'Advance to the next step (only if the current step is complete)', params: [], run: () => apFnsRef.current.guardedNext() },
    backStep: { description: 'Go back one step', params: [], run: () => setStep((n) => Math.max(1, n - 1)) },
    createInvites: { description: 'Create and SEND the invites for the added candidates', sideEffect: true, params: [], run: () => { void apFnsRef.current.submit() } },
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }), [])

  // Memoized so `useAutopilotActions` registers ONCE (getState reads the live ref,
  // so a stable identity still returns current values — no per-render re-register).
  const apGetState = useCallback(() => {
    const s = apStateRef.current
    return {
      step: s.step, interviewType: s.setupType, mode: s.mode, role: s.role,
      questionSource: s.source, questionSetId: s.selectedSetId,
      candidateCount: s.candidates.length, candidates: s.candidates.map((c) => c.email),
      stepName: ['', 'Basics', 'Questions', 'Candidates', 'Invite email', 'Review'][s.step] ?? '',
      // Hard signal for the agent: the current step's required fields are done —
      // when true, its next move should be setup.nextStep (no permission-asking).
      stepComplete: s.step === 1 ? s.step1Valid
        : s.step === 2 ? (s.setupType === 'multi' ? s.step2ValidMulti : s.step2Valid)
        : s.step === 3 ? s.validCount > 0
        : s.step === 4 ? s.emailLockedOk
        : true,
    }
  }, [])
  const apOpts = useMemo(() => ({ getState: apGetState }), [apGetState])
  useAutopilotActions('setup', apActions, apOpts)

  const step1Valid = setupType === 'single'
    ? !!mode && role.trim().length >= 2
    : role.trim().length >= 2 // multi: mode is per-round (chosen in Step 2)
  const tailorTotal = cfg.style === 'mix' ? cfg.techCount + cfg.nonTechCount : cfg.style === 'technical' ? cfg.techCount : cfg.nonTechCount
  // Two-way Interview has no scripted question source to pick — it's a live
  // recruiter-led call, so Step 2 has nothing to require here.
  const step2Valid = mode === 'two_way'
    ? true
    : source === 'tailor' ? tailorTotal >= 1 && tailorTotal <= 25 : source === 'set' ? !!selectedSetId : false
  const step2ValidMulti = rounds.length >= 1 && rounds.every((r) => r.name.trim().length >= 1 && !!r.mode)

  // Refresh the Autopilot state ref AFTER the validity flags exist — every render.
  apStateRef.current = { step, setupType, mode, role, source, selectedSetId, candidates, cfg, step1Valid, step2Valid, step2ValidMulti, validCount, emailLockedOk: emailLocked.ok }

  return (
    <div className="mx-auto max-w-[900px] px-6 py-8">
      <button onClick={() => navigate('/sessions')} className="mb-5 inline-flex items-center gap-1.5 text-sm font-medium text-neutral-500 hover:text-neutral-800">
        <ArrowLeft size={15} /> Back to sessions
      </button>

      <div className="mb-6 flex flex-col gap-5 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <span className="pill mb-2 inline-flex">Invite candidates</span>
          <h1 className="text-2xl font-bold tracking-tight text-neutral-900">Set up an interview & invite</h1>
        </div>
        <Stepper step={step} />
      </div>

      <div className="mb-6 flex items-start gap-3 rounded-xl border border-primary-100 bg-primary-50/60 p-4 text-sm text-neutral-600">
        <span className="flex h-6 w-6 flex-shrink-0 items-center justify-center rounded-lg bg-primary-100 text-primary-700 font-bold">i</span>
        <p className="leading-relaxed">
          You don’t upload résumés here. Configure the interview once, then invite candidates by email —
          <span className="font-medium text-neutral-700"> each candidate uploads their own résumé when they begin</span>, and the interview auto-configures to these settings.
        </p>
      </div>

      {/* ── Success ── */}
      {result && (
        <div className="space-y-5">
          <div className="rounded-2xl border border-primary-100 bg-primary-50/50 p-6 text-center">
            <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-700 text-white"><CheckCircle2 size={28} /></div>
            <h2 className="text-xl font-bold text-neutral-900">{result.created.length} invite{result.created.length === 1 ? '' : 's'} created</h2>
            <p className="mt-1 text-sm text-neutral-500">
              Batch <span className="font-mono text-neutral-700">{result.testId.slice(0, 8)}</span> ·{' '}
              {result.dryRun
                ? 'emails are in dry-run (not sent yet — add the SMTP login + verified sender to send for real)'
                : `${result.emailed} invitation email${result.emailed === 1 ? '' : 's'} sent`}
            </p>
          </div>

          <div className="overflow-hidden rounded-xl border border-border">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border bg-neutral-50 text-left text-[11px] font-semibold uppercase tracking-wide text-neutral-500">
                  <th className="px-3 py-2">Candidate</th><th className="px-3 py-2">Status</th><th className="px-3 py-2">Invite link</th><th className="px-3 py-2 w-10"></th>
                </tr>
              </thead>
              <tbody>
                {result.created.map((c) => {
                  const failed = c.sent === false
                  const variant = c.status === 'delivered' ? 'success' : c.status === 'accepted' ? 'info' : failed ? 'danger' : 'neutral'
                  const label = c.status ?? (c.sent ? 'accepted' : 'pending')
                  return (
                    <tr key={c.id} className="border-b border-border last:border-0">
                      <td className="px-3 py-2 text-neutral-700">{c.email}</td>
                      <td className="px-3 py-2">
                        <span className="flex items-center gap-2">
                          <Badge variant={variant}>{label}</Badge>
                          {failed && (
                            <button onClick={() => void retryOne(c.id)} disabled={retrying.has(c.id)} className="inline-flex items-center gap-1 text-xs font-medium text-primary-700 hover:underline disabled:opacity-50" title={c.error || 'Retry'}>
                              <RefreshCw size={12} className={retrying.has(c.id) ? 'animate-spin' : ''} /> Retry
                            </button>
                          )}
                        </span>
                      </td>
                      <td className="px-3 py-2"><span className="block max-w-[340px] truncate font-mono text-xs text-neutral-500">{c.link}</span></td>
                      <td className="px-3 py-2 text-right">
                        <button onClick={() => { navigator.clipboard.writeText(c.link); toast.success('Link copied') }} className="rounded-md p-1 text-neutral-400 hover:bg-neutral-100 hover:text-neutral-700" aria-label="Copy link"><Copy size={14} /></button>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>

          <div className="flex justify-end gap-2 pt-1">
            <Button variant="secondary" onClick={() => { navigator.clipboard.writeText(result.created.map((c) => `${c.email}: ${c.link}`).join('\n')); toast.success('All links copied') }}>Copy all links</Button>
            <Button onClick={() => navigate('/sessions')}>Done</Button>
          </div>
        </div>
      )}

      {/* ── Step 1 ── */}
      {!result && step === 1 && (
        <div className="space-y-6">
          <section>
            <h2 className="mb-1 text-sm font-semibold text-neutral-800">Interview type</h2>
            <p className="mb-3 text-xs text-neutral-400">One interview, or an ordered set of rounds.</p>
            <div className="grid grid-cols-2 gap-3 max-w-md">
              {(['single', 'multi'] as const).map((t) => {
                const selected = setupType === t
                return (
                  <button key={t} type="button" onClick={() => setSetupType(t)}
                    className={cn('flex flex-col gap-1 rounded-xl border-2 p-4 text-left transition-all',
                      selected ? 'border-primary-700 bg-primary-50/50 shadow-primary-sm' : 'border-border bg-white hover:border-primary-300')}>
                    <span className="flex items-center gap-2">
                      <span className="text-sm font-semibold text-neutral-900">{t === 'single' ? 'Single Interview' : 'Multiple Rounds'}</span>
                      {selected && <Check size={14} className="text-primary-700" />}
                    </span>
                    <span className="text-xs leading-relaxed text-neutral-500">
                      {t === 'single' ? 'One interview per candidate (default).' : 'Screening → … → Final, with advancement.'}
                    </span>
                  </button>
                )
              })}
            </div>
          </section>

          {setupType === 'single' && (
          <section>
            <h2 className="mb-1 text-sm font-semibold text-neutral-800">Interview mode</h2>
            <p className="mb-3 text-xs text-neutral-400">How the interview is conducted.</p>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
              {MODES.map((m) => {
                const selected = mode === m.value
                return (
                  <button key={m.value} type="button"
                    onClick={() => {
                      // Video Avatar needs an applied avatar setup first — send the
                      // recruiter to the Setup page, then return here with the mode
                      // preselected once they've applied it.
                      if (m.value === 'video_avatar' && !avatarApplied.data?.configured) {
                        toast('Configure your AI avatar once — it then applies to every candidate in this batch.')
                        navigate('/setup', { state: { returnTo: '/sessions/new' } })
                        return
                      }
                      setMode(m.value)
                    }}
                    className={cn('flex items-start gap-3 rounded-xl border-2 p-4 text-left transition-all',
                      'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-700 focus-visible:ring-offset-1',
                      selected ? 'border-primary-700 bg-primary-50/50 shadow-primary-sm' : 'border-border bg-white hover:border-primary-300')}>
                    <span className={cn('flex h-10 w-10 flex-shrink-0 items-center justify-center rounded-lg', selected ? 'bg-primary-700 text-white' : 'bg-neutral-100 text-neutral-500')}>{m.icon}</span>
                    <span className="min-w-0">
                      <span className="flex items-center gap-2">
                        <span className="text-sm font-semibold text-neutral-900">{m.label}</span>
                        {selected && <Check size={14} className="text-primary-700" />}
                      </span>
                      <span className="mt-0.5 block text-xs leading-relaxed text-neutral-500">{m.blurb}</span>
                      {m.value === 'video_avatar' && selected && avatarApplied.data?.configured && (
                        <span className="mt-1 block text-xs font-medium text-primary-700">
                          ✓ Uses your applied avatar —{' '}
                          <span role="link" tabIndex={0} className="cursor-pointer font-semibold underline"
                            onClick={(e) => { e.stopPropagation(); navigate('/setup', { state: { returnTo: '/sessions/new' } }) }}
                            onKeyDown={(e) => { if (e.key === 'Enter') { e.stopPropagation(); navigate('/setup', { state: { returnTo: '/sessions/new' } }) } }}>
                            edit avatar setup
                          </span>
                        </span>
                      )}
                    </span>
                  </button>
                )
              })}
            </div>
          </section>
          )}

          <section>
            <label htmlFor="role" className="mb-1 block text-sm font-semibold text-neutral-800">Candidate role</label>
            <p className="mb-2 text-xs text-neutral-400">The position you’re interviewing for. Every invite in this batch uses it (you can override per candidate in Step 3).</p>
            <input id="role" value={role} onChange={(e) => setRole(e.target.value)} placeholder="e.g. Senior Backend Engineer" className="input-base max-w-md" autoFocus />
          </section>

          <div className="flex justify-end gap-2 border-t border-border pt-5">
            <Button variant="ghost" onClick={() => navigate('/sessions')}>Cancel</Button>
            <Button disabled={!step1Valid} onClick={() => setStep(2)}>Next: Questions →</Button>
          </div>
        </div>
      )}

      {/* ── Step 2: question source (single) / round builder (multi) ── */}
      {!result && step === 2 && (
        <div className="space-y-6">
          {setupType === 'multi' ? (
            <section>
              <h2 className="mb-1 text-sm font-semibold text-neutral-800">Rounds</h2>
              <p className="mb-3 text-xs text-neutral-400">Order candidates advance through. Each round has its own mode.</p>
              <RoundBuilder rounds={rounds} onChange={setRounds} />
              <div className="mt-6 flex justify-between gap-2 border-t border-border pt-5">
                <Button variant="ghost" onClick={() => setStep(1)}>← Back</Button>
                <Button disabled={!step2ValidMulti} onClick={() => setStep(3)}>Next: Candidates →</Button>
              </div>
            </section>
          ) : (
            <>
              {mode === 'two_way' ? (
                <div className="rounded-xl border border-border bg-neutral-50 p-5 text-sm text-neutral-600">
                  <p className="font-semibold text-neutral-800">No scripted questions to configure</p>
                  <p className="mt-1 leading-relaxed">
                    Two-way Interview is a live recruiter-led video call — there’s no résumé-tailored or saved
                    question set to pick here. Continue to invite candidates.
                  </p>
                </div>
              ) : (
                <>
                  <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
                    {/* Tailor */}
                    <button type="button" onClick={() => setSource('tailor')}
                      className={cn('flex flex-col gap-2 rounded-xl border-2 p-4 text-left transition-all',
                        source === 'tailor' ? 'border-primary-700 bg-primary-50/50 shadow-primary-sm' : 'border-border bg-white hover:border-primary-300')}>
                      <span className="flex items-center gap-2">
                        <FileText size={18} className={source === 'tailor' ? 'text-primary-700' : 'text-neutral-500'} />
                        <span className="text-sm font-semibold text-neutral-900">Tailor questions to each résumé</span>
                        {source === 'tailor' && <Check size={14} className="text-primary-700" />}
                      </span>
                      <span className="text-xs leading-relaxed text-neutral-500">
                        Each candidate uploads their own résumé when they begin. We generate a unique set tailored to that person’s background and your settings — so every candidate gets bespoke questions.
                      </span>
                    </button>

                    {/* Sets */}
                    <button type="button" onClick={() => setSource('set')}
                      className={cn('flex flex-col gap-2 rounded-xl border-2 p-4 text-left transition-all',
                        source === 'set' ? 'border-primary-700 bg-primary-50/50 shadow-primary-sm' : 'border-border bg-white hover:border-primary-300')}>
                      <span className="flex items-center gap-2">
                        <Layers size={18} className={source === 'set' ? 'text-primary-700' : 'text-neutral-500'} />
                        <span className="text-sm font-semibold text-neutral-900">Your question sets</span>
                        {source === 'set' && <Check size={14} className="text-primary-700" />}
                      </span>
                      <span className="text-xs leading-relaxed text-neutral-500">
                        Reuse a question set you’ve saved. Build sets from a sample résumé or by configuring them manually — your sets are private to your account.
                      </span>
                    </button>
                  </div>

                  {/* Tailor config */}
                  {source === 'tailor' && <TailorConfigPanel role={role} cfg={cfg} setCfg={setCfg} />}

                  {/* Set picker */}
                  {source === 'set' && (
                    <div className="rounded-xl border border-border bg-white p-5">
                      <div className="mb-3 flex items-center justify-between">
                        <p className="text-sm font-semibold text-neutral-800">Choose a question set</p>
                        <button onClick={() => setGenOpen(true)} className="inline-flex items-center gap-1.5 text-xs font-semibold text-primary-700 hover:underline">
                          <Plus size={13} /> Create new set
                        </button>
                      </div>
                      {sets.isLoading ? (
                        <div className="space-y-2">{[0, 1, 2].map((i) => <Skeleton key={i} className="h-14 w-full" />)}</div>
                      ) : !sets.data?.length ? (
                        <p className="rounded-lg border border-dashed border-border bg-neutral-50 p-6 text-center text-sm text-neutral-400">
                          No question sets yet. Click “Create new set” to build one from a sample résumé or manually.
                        </p>
                      ) : (
                        <div className="max-h-[40vh] space-y-2 overflow-y-auto">
                          {sets.data.map((s: QuestionSet) => {
                            const sel = selectedSetId === s.id
                            return (
                              <button key={s.id} type="button" onClick={() => setSelectedSetId(s.id)}
                                className={cn('flex w-full items-center justify-between rounded-lg border px-3 py-2.5 text-left transition-all',
                                  sel ? 'border-primary-700 bg-primary-50' : 'border-border hover:border-primary-300 hover:bg-neutral-50')}>
                                <span className="min-w-0">
                                  <span className="block truncate text-sm font-medium text-neutral-800">{s.name}</span>
                                  <span className="block text-xs text-neutral-400">{s.questions.length} question{s.questions.length !== 1 ? 's' : ''}</span>
                                </span>
                                {sel && <Check size={16} className="flex-shrink-0 text-primary-700" />}
                              </button>
                            )
                          })}
                        </div>
                      )}
                    </div>
                  )}
                </>
              )}

              <div className="flex justify-between gap-2 border-t border-border pt-5">
                <Button variant="ghost" onClick={() => setStep(1)}>← Back</Button>
                <Button disabled={!step2Valid} onClick={() => setStep(3)}>Next: Candidates →</Button>
              </div>

              {mode !== 'two_way' && (
                <GenerateFromResumeModal
                  open={genOpen}
                  onClose={() => setGenOpen(false)}
                  defaultRole={role}
                  onSaved={(set) => { qc.invalidateQueries({ queryKey: ['question-sets'] }); setSelectedSetId(set.id); setGenOpen(false) }}
                />
              )}
            </>
          )}
        </div>
      )}

      {/* ── Step 3: candidates ── */}
      {!result && step === 3 && (
        <div className="space-y-6">
          <section>
            <h2 className="mb-1 text-sm font-semibold text-neutral-800">Add candidates</h2>
            <p className="mb-3 text-xs text-neutral-400">
              Upload a file of candidate emails (CSV, Excel, PDF, DOCX, or text) — we extract each email and role — or add them manually. Review everything below before inviting.
            </p>

            <div
              onClick={() => !extracting && fileInput.current?.click()}
              onDragOver={(e) => { e.preventDefault(); setDragOver(true) }}
              onDragLeave={() => setDragOver(false)}
              onDrop={(e) => { e.preventDefault(); setDragOver(false); void onFile(e.dataTransfer.files?.[0] ?? null) }}
              className={cn(
                'flex cursor-pointer flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed p-7 text-center transition-colors',
                dragOver ? 'border-primary-700 bg-primary-50' : 'border-border bg-neutral-50 hover:border-neutral-300',
                extracting && 'pointer-events-none opacity-70',
              )}
            >
              {extracting ? <Loader2 size={26} className="animate-spin text-primary-700" /> : <UploadCloud size={26} className="text-neutral-400" />}
              <span className="text-sm font-medium text-neutral-600">{extracting ? 'Reading file…' : 'Drag a file here, or click to choose'}</span>
              <span className="text-xs text-neutral-400">CSV · Excel · PDF · DOCX · TXT — max 10 MB</span>
              <input
                ref={fileInput}
                type="file"
                accept=".csv,.tsv,.xlsx,.xls,.pdf,.docx,.txt,text/csv,application/vnd.ms-excel,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet,application/pdf,text/plain"
                className="hidden"
                onChange={(e) => void onFile(e.target.files?.[0] ?? null)}
              />
            </div>
            {fileError && <p className="mt-2 rounded-lg border border-danger-border bg-danger-bg p-2.5 text-sm text-danger">{fileError}</p>}

            <div className="mt-3 flex gap-2">
              <input
                value={manualEmail}
                onChange={(e) => setManualEmail(e.target.value)}
                onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addManual() } }}
                placeholder="Or type an email: name@company.com"
                className="input-base flex-1"
              />
              <Button variant="secondary" onClick={addManual} disabled={!manualEmail.trim()}>Add email</Button>
            </div>
          </section>

          {warnings.length > 0 && (
            <div className="flex items-start gap-2.5 rounded-xl border border-warning-border bg-warning-bg p-3 text-sm text-amber-800">
              <AlertTriangle size={16} className="mt-0.5 flex-shrink-0" />
              <ul className="list-inside list-disc space-y-0.5">{warnings.map((w, i) => <li key={i}>{w}</li>)}</ul>
            </div>
          )}

          {candidates.length > 0 && (
            <section>
              <div className="mb-2 flex items-center justify-between">
                <p className="text-sm font-semibold text-neutral-800">
                  {candidates.length} candidate{candidates.length === 1 ? '' : 's'}
                  <span className="ml-2 text-xs font-normal text-neutral-400">{validCount} valid{validCount !== candidates.length ? ` · ${candidates.length - validCount} to fix` : ''}</span>
                </p>
                <div className="flex items-center gap-3 text-xs">
                  {validCount !== candidates.length && (
                    <button onClick={() => setCandidates((cs) => cs.filter((c) => emailOk(c.email)))} className="font-medium text-neutral-500 hover:text-neutral-800">Remove invalid</button>
                  )}
                  <button onClick={() => { setCandidates([]); setWarnings([]) }} className="font-medium text-neutral-500 hover:text-danger">Clear all</button>
                </div>
              </div>

              <div className="overflow-hidden rounded-xl border border-border">
                <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-border bg-neutral-50 text-left text-[11px] font-semibold uppercase tracking-wide text-neutral-500">
                      <th className="px-3 py-2 w-8"></th>
                      <th className="px-3 py-2">Email</th>
                      <th className="px-3 py-2">Role</th>
                      <th className="px-3 py-2 w-10"></th>
                    </tr>
                  </thead>
                  <tbody className="max-h-[40vh]">
                    {candidates.map((c) => {
                      const ok = emailOk(c.email)
                      return (
                        <tr key={c.id} className="border-b border-border last:border-0">
                          <td className="px-3 py-1.5">
                            <span className={cn('flex h-5 w-5 items-center justify-center rounded-full text-[10px] font-bold', ok ? 'bg-success-bg text-success' : 'bg-danger-bg text-danger')} title={ok ? 'Valid email' : 'Invalid email format'}>
                              {ok ? '✓' : '!'}
                            </span>
                          </td>
                          <td className="px-3 py-1.5">
                            <input value={c.email} onChange={(e) => setCandidates((cs) => cs.map((x) => x.id === c.id ? { ...x, email: e.target.value } : x))}
                              className={cn('w-full rounded-md border bg-white px-2 py-1 font-mono text-xs', ok ? 'border-border' : 'border-danger')} />
                          </td>
                          <td className="px-3 py-1.5">
                            <input value={c.role} onChange={(e) => setCandidates((cs) => cs.map((x) => x.id === c.id ? { ...x, role: e.target.value } : x))}
                              placeholder={role} className="w-full rounded-md border border-border bg-white px-2 py-1 text-xs" />
                          </td>
                          <td className="px-3 py-1.5 text-right">
                            <button onClick={() => setCandidates((cs) => cs.filter((x) => x.id !== c.id))} className="rounded-md p-1 text-neutral-300 hover:bg-danger-bg hover:text-danger" aria-label="Remove"><Trash2 size={14} /></button>
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              </div>
            </section>
          )}

          <div className="flex items-center justify-between gap-2 border-t border-border pt-5">
            <Button variant="ghost" onClick={() => setStep(2)}>← Back</Button>
            <Button disabled={validCount === 0} onClick={() => setStep(4)}>
              Next: Invite email →
            </Button>
          </div>
        </div>
      )}

      {/* ── Step 4: invite email ── */}
      {!result && step === 4 && (
        <div className="space-y-6">
          <section>
            <h2 className="mb-1 flex items-center gap-2 text-sm font-semibold text-neutral-800"><Mail size={15} className="text-primary-700" /> Configure the invite email</h2>
            <p className="mb-3 text-xs text-neutral-400">
              Set the sender, subject, message, button, and branding — then preview and send yourself a test.
              Each candidate’s unique interview link and the “use this exact email” note are added automatically and can’t be removed.
            </p>
            <InviteEmailStep
              draft={emailDraft}
              onChange={setEmailDraft}
              role={role}
              sampleEmail={sampleEmail}
              origin={window.location.origin}
            />
          </section>

          <div className="flex items-center justify-between gap-2 border-t border-border pt-5">
            <Button variant="ghost" onClick={() => setStep(3)}>← Back</Button>
            <Button disabled={!emailLocked.ok} onClick={() => setStep(5)}>Next: Review →</Button>
          </div>
        </div>
      )}

      {/* ── Step 5: review & send ── */}
      {!result && step === 5 && (
        <div className="space-y-6">
          <section>
            <h2 className="mb-1 text-sm font-semibold text-neutral-800">Review & send</h2>
            <p className="mb-3 text-xs text-neutral-400">Confirm the recipients and the email below, then send.</p>
            <ReviewSend candidates={validCandidates} draft={emailDraft} role={role} origin={window.location.origin} />
          </section>

          <div className="flex items-center justify-between gap-2 border-t border-border pt-5">
            <Button variant="ghost" onClick={() => setStep(4)}>← Back</Button>
            <Button loading={creating} disabled={validCount === 0 || !emailLocked.ok} onClick={submit}>
              Send {validCount > 0 ? `${validCount} ` : ''}invite{validCount === 1 ? '' : 's'}
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}
