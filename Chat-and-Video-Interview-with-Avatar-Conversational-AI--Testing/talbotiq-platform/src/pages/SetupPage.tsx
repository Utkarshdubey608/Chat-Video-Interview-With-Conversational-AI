import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import toast from 'react-hot-toast'
import { useReplicas, usePersonas, useCreateConversation } from '@/hooks/useTavus'
import { useAppStore } from '@/store/useAppStore'
import type { Draft } from '@/store/useAppStore'
import { Button, Card, Input, Textarea, Select, Toggle, Slider, JsonPreview, SectionTitle, PageHeader, Divider } from '@/components/ui'
import { cn } from '@/components/ui'
import { formatDistanceToNow } from 'date-fns'
import type { CreateConversationInput, SupportedLanguage, PipelineMode } from '@/types/tavus.types'

// Tavus requires full language names — NOT ISO codes
const LANGS: { value: SupportedLanguage; label: string }[] = [
  { value: 'English',    label: 'English' },
  { value: 'Spanish',    label: 'Spanish' },
  { value: 'French',     label: 'French' },
  { value: 'German',     label: 'German' },
  { value: 'Italian',    label: 'Italian' },
  { value: 'Portuguese', label: 'Portuguese' },
  { value: 'Japanese',   label: 'Japanese' },
  { value: 'Korean',     label: 'Korean' },
  { value: 'Chinese',    label: 'Chinese' },
  { value: 'Hindi',      label: 'Hindi' },
  { value: 'Arabic',     label: 'Arabic' },
]
const PIPELINES: { value: PipelineMode; label: string }[] = [
  { value: 'full', label: 'Full — audio + video' }, { value: 'echo', label: 'Echo — test mode' },
  { value: 'no_audio', label: 'No audio' }, { value: 'video_only', label: 'Video only' },
]

type F = import('@/store/useAppStore').DraftForm
const DEF: F = {
  replica_id: '', persona_id: '', conversation_name: '', conversational_context: '', custom_greeting: '',
  callback_url: '', max_call_duration: 900, participant_left_timeout: 60, participant_absent_timeout: 300,
  enable_recording: false, enable_transcription: true, apply_conversation_override: false,
  apply_greenscreen: false, background_url: '', language: 'English', pipeline_mode: 'full',
  recording_s3_bucket_name: '', recording_s3_bucket_region: '', aws_assume_role_arn: '',
}

export default function SetupPage() {
  const navigate = useNavigate()
  const store = useAppStore()
  const { data: replicas } = useReplicas()
  const { data: personas } = usePersonas()
  const create = useCreateConversation()
  const [f, setF] = useState<F>({ ...DEF, replica_id: store.defaultReplicaId, persona_id: store.defaultPersonaId })
  const [modal, setModal] = useState(false)
  const [name, setName] = useState('')
  const [draftModal, setDraftModal] = useState(false)
  const [draftName, setDraftName] = useState('')
  const [errorModal, setErrorModal] = useState<{ open: boolean; message: string }>({ open: false, message: '' })

  useEffect(() => { if (store.defaultReplicaId && !f.replica_id) setF(p => ({ ...p, replica_id: store.defaultReplicaId })) }, [store.defaultReplicaId])
  const set = <K extends keyof F>(k: K, v: F[K]) => setF(p => ({ ...p, [k]: v }))

  const allReplicas = replicas ?? []
  const customReplicas = allReplicas.filter(r => r.replica_type !== 'stock')
  const stockReplicas  = allReplicas.filter(r => r.replica_type === 'stock')

  const repOpts = [
    { value: '', label: allReplicas.length ? 'None (demo mode)' : 'None — no replicas found' },
    // Custom replicas
    ...customReplicas.map(r => ({
      value: r.replica_id,
      label: `${r.replica_name}${r.status !== 'ready' ? ` (${r.status})` : ''}`,
    })),
    // Stock replicas with prefix
    ...stockReplicas.map(r => ({
      value: r.replica_id,
      label: `[Stock] ${r.replica_name}${r.status !== 'ready' ? ` (${r.status})` : ''}`,
    })),
  ]
  const perOpts = [{ value: '', label: 'None' }, ...(personas ?? []).map(p => ({ value: p.persona_id, label: p.persona_name }))]

  // Build clean payload — only include non-empty optional fields to avoid 400s
  function buildPayload(candidateName: string): CreateConversationInput {
    const qList = store.questions.filter(Boolean)
    const numbered = qList.map((q, i) => `${i + 1}. ${q}`).join('\n')

    // Persona / tone — either the recruiter's custom text or a sensible default
    const persona = f.conversational_context.trim() ||
      `You are Alex, a Senior Talent Specialist at TalbotIQ conducting a screening interview with ${candidateName}. Maintain a warm, professional tone.`

    // ALWAYS enforce the exact configured questions — this block is appended no matter what,
    // so the avatar never invents its own questions.
    const ctx =
`${persona}

INTERVIEW SCRIPT — STRICT RULES:
- Ask ONLY the questions listed below, exactly as written, in this exact order.
- Ask one question at a time and wait for ${candidateName} to fully finish answering before moving to the next.
- Do NOT invent, add, skip, reorder, or rephrase any questions.
- Do NOT ask any follow-up questions that are not in this list.
- After the final question, briefly thank ${candidateName} and end the interview.

QUESTIONS:
${numbered}`

    const greeting = f.custom_greeting ||
      `Hello ${candidateName}, welcome to your TalbotIQ interview. I'm excited to learn more about you today. Are you ready to begin?`

    const body: CreateConversationInput = {
      replica_id: f.replica_id,
      conversation_name: `TalbotIQ — ${candidateName}`,
      conversational_context: ctx,
      custom_greeting: greeting,
    }

    // Only add persona_id if explicitly chosen
    if (f.persona_id) body.persona_id = f.persona_id
    if (f.callback_url) body.callback_url = f.callback_url

    // Build properties — send only what's needed, never send pipeline_mode (causes 400 on some plans)
    const props: CreateConversationInput['properties'] = {
      max_call_duration: f.max_call_duration,
      participant_left_timeout: f.participant_left_timeout,
      enable_recording: f.enable_recording,
      enable_transcription: f.enable_transcription,
    }
    // Language: only send if not the default, and always as a full name
    if (f.language && f.language !== 'English') props.language = f.language
    if (f.participant_absent_timeout !== 300) props.participant_absent_timeout = f.participant_absent_timeout
    if (f.apply_conversation_override) props.apply_conversation_override = true
    if (f.apply_greenscreen) { props.apply_greenscreen = true; if (f.background_url) props.background_url = f.background_url }
    if (f.recording_s3_bucket_name) props.recording_s3_bucket_name = f.recording_s3_bucket_name
    if (f.recording_s3_bucket_region) props.recording_s3_bucket_region = f.recording_s3_bucket_region
    if (f.aws_assume_role_arn) props.aws_assume_role_arn = f.aws_assume_role_arn
    body.properties = props

    return body
  }

  // For the live JSON preview panel only
  const payload = buildPayload(name || 'Candidate')

  function resetHumeState() {
    store.setHumeJobId(null)
    store.setHumeJobStatus(null)
    store.setHumeResult(null)
    store.resetQuestionTimestamps()
    store.setLiveEmotions([])
    store.setHumeStreamActive(false)
    store.clearSessionTranscript()
    // Reset transcript-derived metrics so Results page never shows stale defaults
    store.updateMetrics({ wpm: 0, fillers: 0 })
  }

  function launchDemoMode() {
    resetHumeState()
    store.setCurrentConversation({
      conversation_id: `demo-${Date.now()}`,
      conversation_name: `TalbotIQ — ${name || 'Candidate'}`,
      status: 'active', conversation_url: '',
      replica_id: '', created_at: new Date().toISOString(),
    })
    store.setInterviewActive(true)
    store.setCurrentQuestionIdx(0)
    setErrorModal({ open: false, message: '' })
    setModal(false)
    toast('Running in Demo Mode — no avatar video')
    navigate('/interview')
  }

  function confirmLaunch() {
    if (!name.trim()) { toast.error('Enter a display name'); return }

    // No replica — demo mode
    if (!f.replica_id) { launchDemoMode(); return }

    const p = buildPayload(name)
    create.mutate(p, {
      onSuccess: (conv) => {
        resetHumeState()
        store.setCurrentConversation(conv)
        store.setInterviewActive(true)
        store.setCurrentQuestionIdx(0)
        setModal(false)
        toast.success('Session created!')
        navigate('/interview')
      },
      onError: (e: any) => {
        const msg = e.message ?? 'Failed to create conversation'
        console.error('Tavus error payload:', JSON.stringify(p, null, 2))
        setModal(false)
        setErrorModal({ open: true, message: msg })
      },
    })
  }

  return (
    <div className="max-w-[1400px] mx-auto px-6 py-8">
      {/* Hero header — matches screenshot style */}
      <div className="mb-10">
        <span className="pill mb-4 inline-flex">AI Avatar Screening</span>
        <h1 className="text-neutral-400 font-light text-4xl tracking-tight leading-none">
          Configure Your
        </h1>
        <h2 className="text-neutral-900 font-black text-5xl tracking-tighter leading-none mt-1 mb-5">
          Interview Session
        </h2>
        <p className="text-neutral-500 text-base max-w-xl leading-relaxed">
          Set up your AI avatar, questions, and analysis preferences. Everything
          is customisable — from the avatar persona to scoring thresholds.
        </p>
        <div className="flex gap-3 mt-6">
          <Button onClick={() => setModal(true)} loading={create.isPending}>
            Launch Session
          </Button>
          <Button variant="secondary" onClick={() => { setDraftName(''); setDraftModal(true) }}>Save Draft</Button>
        </div>
      </div>

      {/* Saved Drafts */}
      {store.drafts.length > 0 && (
        <Card className="mb-6 divide-y divide-border">
          <div className="px-6 py-4 flex items-center justify-between">
            <div>
              <h3 className="text-sm font-semibold text-neutral-800">Saved Drafts</h3>
              <p className="text-xs text-neutral-400 mt-0.5">{store.drafts.length} draft{store.drafts.length !== 1 ? 's' : ''} — click to load</p>
            </div>
          </div>
          <div className="px-6 py-4 grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            {store.drafts.map((d: Draft) => (
              <div key={d.id} className="flex items-start justify-between gap-2 p-3 rounded-xl border border-border hover:border-primary-300 hover:bg-primary-50 transition-all group cursor-pointer"
                onClick={() => { setF({ ...d.form }); store.setQuestions(d.questions); toast.success(`Loaded "${d.name}"`) }}>
                <div className="min-w-0">
                  <p className="text-sm font-semibold text-neutral-800 truncate">{d.name}</p>
                  <p className="text-xs text-neutral-400 mt-0.5">{d.questions.filter(Boolean).length} questions · saved {formatDistanceToNow(new Date(d.savedAt), { addSuffix: true })}</p>
                  {d.form.replica_id && <p className="text-xs font-mono text-primary-600 truncate mt-0.5">{d.form.replica_id}</p>}
                </div>
                <button
                  onClick={e => { e.stopPropagation(); store.deleteDraft(d.id); toast('Draft deleted') }}
                  className="opacity-0 group-hover:opacity-100 p-1 rounded text-neutral-300 hover:text-danger hover:bg-danger-bg transition-all flex-shrink-0 mt-0.5"
                  title="Delete draft"
                >
                  <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                </button>
              </div>
            ))}
          </div>
        </Card>
      )}

      <div className="grid grid-cols-1 xl:grid-cols-[1fr_380px] gap-6">
        {/* ── Left: form ── */}
        <div className="space-y-5">

          {/* Tavus config */}
          <Card className="divide-y divide-border">
            <div className="px-6 py-4">
              <h3 className="text-sm font-semibold text-neutral-800">Tavus Configuration</h3>
              <p className="text-xs text-neutral-400 mt-0.5">Avatar and persona selection for this session</p>
            </div>
            <div className="px-6 py-5 grid grid-cols-1 sm:grid-cols-2 gap-5">
              {/* Replica — dropdown + manual ID search */}
              <div className="flex flex-col gap-1.5">
                <label className="field-label">Replica (optional)</label>
                <Select
                  options={repOpts}
                  value={allReplicas.find(r => r.replica_id === f.replica_id) ? f.replica_id : ''}
                  onChange={e => set('replica_id', e.target.value)}
                />
                <div className="flex items-center gap-2 mt-1">
                  <div className="flex-1 h-px bg-border" />
                  <span className="text-[10px] text-neutral-400 uppercase tracking-wide font-medium">or enter ID</span>
                  <div className="flex-1 h-px bg-border" />
                </div>
                <div className="relative">
                  <input
                    type="text"
                    value={f.replica_id}
                    onChange={e => set('replica_id', e.target.value.trim())}
                    placeholder="e.g. r5f0577fc829"
                    className="input-base font-mono text-sm pr-8"
                  />
                  {f.replica_id && (
                    <button
                      type="button"
                      onClick={() => set('replica_id', '')}
                      className="absolute right-3 top-1/2 -translate-y-1/2 text-neutral-300 hover:text-neutral-600 transition-colors text-lg leading-none"
                      title="Clear"
                    >×</button>
                  )}
                </div>
                <p className="text-xs text-neutral-400">
                  {f.replica_id
                    ? <span className="text-primary-700 font-medium">✓ Replica ID set: <span className="font-mono">{f.replica_id}</span></span>
                    : allReplicas.length
                      ? `${customReplicas.length} custom · ${stockReplicas.length} stock available`
                      : 'No replicas loaded — check API key in Settings'}
                </p>
              </div>

              <Select label="Persona" options={perOpts} value={f.persona_id} onChange={e => set('persona_id', e.target.value)} hint="Optional — inherits replica defaults if unset" />
              <div className="sm:col-span-2"><Input label="Conversation Name" value={f.conversation_name} onChange={e => set('conversation_name', e.target.value)} placeholder="e.g. TalbotIQ — Senior Engineer Screen — Arjun Kumar" /></div>
              <div className="sm:col-span-2"><Textarea label="Conversational Context" value={f.conversational_context} onChange={e => set('conversational_context', e.target.value)} placeholder="You are Alex, a Senior Talent Specialist at TalbotIQ. Ask each question clearly and wait for the candidate's full response before proceeding. Maintain a warm, professional tone throughout." className="min-h-[100px]" hint="This is the system prompt sent to the Tavus LLM" /></div>
              <div className="sm:col-span-2"><Input label="Custom Greeting" value={f.custom_greeting} onChange={e => set('custom_greeting', e.target.value)} placeholder="Hello! Welcome to your TalbotIQ interview. I'm excited to learn more about you today." hint="The very first thing the avatar says when the session starts" /></div>
              <div className="sm:col-span-2"><Input label="Callback URL" value={f.callback_url} onChange={e => set('callback_url', e.target.value)} placeholder="https://api.yourcompany.com/tavus-events" hint="Receives all conversation webhook events" /></div>
            </div>
          </Card>

          {/* Questions */}
          <Card className="divide-y divide-border">
            <div className="px-6 py-4 flex items-center justify-between">
              <div>
                <h3 className="text-sm font-semibold text-neutral-800">Interview Questions</h3>
                <p className="text-xs text-neutral-400 mt-0.5">{store.questions.filter(Boolean).length} question{store.questions.filter(Boolean).length !== 1 ? 's' : ''} configured</p>
              </div>
            </div>
            <div className="px-6 py-5 space-y-2">
              {store.questions.map((q, i) => (
                <div key={i} className="flex gap-3 items-center group">
                  <span className="w-6 h-6 rounded-md bg-primary-50 text-primary-700 text-xs font-bold flex items-center justify-center flex-shrink-0">{i + 1}</span>
                  <input
                    value={q}
                    onChange={e => { const qs = [...store.questions]; qs[i] = e.target.value; store.setQuestions(qs) }}
                    className="input-base flex-1"
                    placeholder={`Question ${i + 1}`}
                  />
                  <button onClick={() => store.setQuestions(store.questions.filter((_, j) => j !== i))} className="opacity-0 group-hover:opacity-100 p-1.5 rounded-lg text-neutral-400 hover:text-danger hover:bg-danger-bg transition-all">
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                  </button>
                </div>
              ))}
              <button onClick={() => store.setQuestions([...store.questions, ''])}
                className="w-full h-9 border border-dashed border-neutral-200 rounded-lg text-xs font-medium text-neutral-400 hover:border-primary-300 hover:text-primary-600 hover:bg-primary-50 transition-all">
                + Add Question
              </button>
            </div>
          </Card>

          {/* Session properties */}
          <Card className="divide-y divide-border">
            <div className="px-6 py-4">
              <h3 className="text-sm font-semibold text-neutral-800">Session Properties</h3>
              <p className="text-xs text-neutral-400 mt-0.5">All values map to the Tavus conversation properties object</p>
            </div>
            <div className="px-6 py-5 space-y-5">
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-5">
                <Select label="Language" options={LANGS.map(l => ({ value: l.value, label: l.label }))} value={f.language} onChange={e => set('language', e.target.value as SupportedLanguage)} />
                <Select label="Pipeline Mode" options={PIPELINES.map(p => ({ value: p.value, label: p.label }))} value={f.pipeline_mode} onChange={e => set('pipeline_mode', e.target.value as PipelineMode)} />
              </div>
              <Slider label="Max Call Duration" min={60} max={7200} step={60} value={f.max_call_duration} onChange={v => set('max_call_duration', v)} formatValue={v => `${Math.floor(v / 60)} min`} />
              <div className="grid grid-cols-2 gap-4">
                <Input label="Participant Left Timeout (s)" type="number" value={f.participant_left_timeout} onChange={e => set('participant_left_timeout', Number(e.target.value))} />
                <Input label="Absent Timeout (s)" type="number" value={f.participant_absent_timeout} onChange={e => set('participant_absent_timeout', Number(e.target.value))} />
              </div>
            </div>
            <div className="px-6 py-2">
              <Toggle checked={f.enable_transcription} onChange={v => set('enable_transcription', v)} label="Enable Transcription" description="Real-time transcription of candidate speech via Tavus" />
              <Toggle checked={f.enable_recording} onChange={v => set('enable_recording', v)} label="Enable Recording" description="Save the full session video to storage" />
              <Toggle checked={f.apply_conversation_override} onChange={v => set('apply_conversation_override', v)} label="Conversation Override" description="Allow real-time text injection during the call" />
              <Toggle checked={f.apply_greenscreen} onChange={v => set('apply_greenscreen', v)} label="Virtual Background" description="Replace avatar background with a custom image" />
            </div>
            {f.apply_greenscreen && (
              <div className="px-6 pb-5">
                <Input label="Background Image URL" value={f.background_url} onChange={e => set('background_url', e.target.value)} placeholder="https://cdn.example.com/office-background.jpg" />
              </div>
            )}
          </Card>

          {/* S3 Storage */}
          {f.enable_recording && (
            <Card className="divide-y divide-border">
              <div className="px-6 py-4">
                <h3 className="text-sm font-semibold text-neutral-800">S3 Recording Storage</h3>
                <p className="text-xs text-neutral-400 mt-0.5">Configure AWS S3 to store session recordings</p>
              </div>
              <div className="px-6 py-5 space-y-4">
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <Input label="Bucket Name" value={f.recording_s3_bucket_name} onChange={e => set('recording_s3_bucket_name', e.target.value)} placeholder="my-talbotiq-recordings" />
                  <Input label="Region" value={f.recording_s3_bucket_region} onChange={e => set('recording_s3_bucket_region', e.target.value)} placeholder="us-east-1" />
                </div>
                <Input label="AWS Assume Role ARN" value={f.aws_assume_role_arn} onChange={e => set('aws_assume_role_arn', e.target.value)} placeholder="arn:aws:iam::123456789012:role/TavusRecordingRole" />
              </div>
            </Card>
          )}
        </div>

        {/* ── Right: JSON preview ── */}
        <div className="hidden xl:flex flex-col gap-4 sticky top-20 h-fit">
          <JsonPreview data={payload} title="Request Preview" method="POST" endpoint="/v2/conversations" />
          <Card className="p-4">
            <p className="text-xs font-semibold text-neutral-700 mb-2">Quick Reference</p>
            <div className="space-y-1.5 text-xs text-neutral-500">
              <p><span className="font-mono text-primary-600">conversational_context</span> = system prompt</p>
              <p><span className="font-mono text-primary-600">custom_greeting</span> = avatar's first words</p>
              <p><span className="font-mono text-primary-600">override</span> requires property set to true</p>
              <p><span className="font-mono text-primary-600">s3_*</span> fields only needed if recording enabled</p>
            </div>
          </Card>
        </div>
      </div>

      {/* Save Draft modal */}
      {draftModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-neutral-900/40 backdrop-blur-[2px]" onClick={() => setDraftModal(false)}>
          <div className="relative bg-white rounded-2xl shadow-xl border border-border p-8 w-full max-w-md animate-slide-up" onClick={e => e.stopPropagation()}>
            <h3 className="text-xl font-bold text-neutral-900">Save Draft</h3>
            <p className="text-sm text-neutral-500 mt-1 mb-6">Give this draft a name so you can find it later.</p>
            <Input label="Draft Name *" value={draftName} onChange={e => setDraftName(e.target.value)}
              onKeyDown={e => {
                if (e.key === 'Enter' && draftName.trim()) {
                  store.saveDraft(draftName.trim(), f, store.questions)
                  toast.success(`Draft "${draftName.trim()}" saved`)
                  setDraftModal(false)
                }
              }}
              placeholder="e.g. Senior Engineer Screen" autoFocus />
            <div className="flex gap-3 justify-end mt-6">
              <Button variant="secondary" onClick={() => setDraftModal(false)}>Cancel</Button>
              <Button onClick={() => {
                if (!draftName.trim()) { toast.error('Enter a draft name'); return }
                store.saveDraft(draftName.trim(), f, store.questions)
                toast.success(`Draft "${draftName.trim()}" saved`)
                setDraftModal(false)
              }}>Save Draft</Button>
            </div>
          </div>
        </div>
      )}

      {/* Launch modal */}
      {modal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-neutral-900/40 backdrop-blur-[2px]" onClick={() => setModal(false)}>
          <div className="relative bg-white rounded-2xl shadow-xl border border-border p-8 w-full max-w-md animate-slide-up" onClick={e => e.stopPropagation()}>
            <h3 className="text-xl font-bold text-neutral-900">Confirm Session</h3>
            <p className="text-sm text-neutral-500 mt-1 mb-6">Enter the candidate's name to personalise this interview session.</p>
            <Input label="Candidate Name *" value={name} onChange={e => setName(e.target.value)} onKeyDown={e => { if (e.key === 'Enter') confirmLaunch() }} placeholder="e.g. Arjun Kumar" autoFocus />
            <div className="flex gap-3 justify-end mt-6">
              <Button variant="secondary" onClick={() => setModal(false)}>Cancel</Button>
              <Button onClick={confirmLaunch} loading={create.isPending}>Launch Interview</Button>
            </div>
          </div>
        </div>
      )}

      {/* Tavus error — offer demo mode fallback */}
      {errorModal.open && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-neutral-900/50 backdrop-blur-[2px]" onClick={() => setErrorModal({ open: false, message: '' })}>
          <div className="relative bg-white rounded-2xl shadow-xl border border-border p-8 w-full max-w-md animate-slide-up" onClick={e => e.stopPropagation()}>
            {/* Header */}
            <div className="flex items-start gap-4 mb-5">
              <div className="w-10 h-10 rounded-xl bg-danger-bg flex items-center justify-center flex-shrink-0">
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#dc2626" strokeWidth="2.5"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
              </div>
              <div>
                <h3 className="text-lg font-bold text-neutral-900 leading-tight">Tavus API Error</h3>
                <p className="text-sm text-neutral-500 mt-0.5">The session could not be created.</p>
              </div>
            </div>

            {/* Error message */}
            <div className="bg-danger-bg border border-danger-border rounded-xl px-4 py-3 mb-5">
              <p className="text-sm text-danger font-medium">{errorModal.message}</p>
            </div>

            {/* Guidance */}
            {/credit/i.test(errorModal.message) && (
              <div className="bg-warning-bg border border-warning-border rounded-xl px-4 py-3 mb-5 text-sm text-amber-800 space-y-1">
                <p className="font-semibold">Your Tavus account is out of conversational credits.</p>
                <p>To resume live avatar interviews, purchase additional credits at <span className="font-mono text-xs">tavus.io → Billing</span>.</p>
              </div>
            )}

            {/* Actions */}
            <div className="flex flex-col gap-3">
              <Button onClick={launchDemoMode} className="w-full">
                Continue in Demo Mode (no avatar)
              </Button>
              <div className="flex gap-3">
                <Button variant="secondary" className="flex-1" onClick={() => { setErrorModal({ open: false, message: '' }); setModal(true) }}>
                  Try Again
                </Button>
                <Button variant="ghost" className="flex-1" onClick={() => setErrorModal({ open: false, message: '' })}>
                  Dismiss
                </Button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
