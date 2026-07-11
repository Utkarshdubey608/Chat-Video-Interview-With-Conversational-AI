import { useEffect, useMemo, useState } from 'react'
import { useParams, useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { ArrowLeft, Plus, Trash2, Save, Sparkles } from 'lucide-react'
import {
  PageHeader, Card, Button, Input, Select, Toggle, Textarea, SectionTitle, Badge, Divider, Skeleton,
} from '@/components/ui'
import { templatesApi, questionSetsApi } from '@/lib/api'
import { GenerateFromResumeModal } from './GenerateFromResumeModal'
import type { InterviewTemplate, KpiDefinition, AdaptiveConfig, ConversationTimingConfig, InterviewMode, DifficultyChoice, QuestionStyle } from '@shared/types'

const num = (v: string, fallback: number) => {
  const n = Number(v)
  return Number.isFinite(n) ? n : fallback
}

const DEF_ADAPTIVE: AdaptiveConfig = {
  role: '', difficulty: 'mixed', style: 'mix', numberOfQuestions: 5, technicalCount: 3, nonTechnicalCount: 2,
  focusTopics: [], allowFollowUps: false, maxFollowUpsPerQuestion: 1, interviewerTone: 'friendly and professional', language: 'English',
}
const DEF_CONV: ConversationTimingConfig = {
  thinkingSeconds: 30, perQuestionSeconds: 120, allowSkipThinking: true, allowEarlySubmit: true, warningThresholdSeconds: 15,
}

function normalizedWeights(kpis: KpiDefinition[]) {
  const enabled = kpis.filter((k) => k.enabled && k.weight > 0)
  const total = enabled.reduce((s, k) => s + k.weight, 0)
  return (k: KpiDefinition) =>
    k.enabled && total > 0 ? Math.round((k.weight / total) * 100) : 0
}

export default function TemplateEditorPage() {
  const { id = '' } = useParams()
  const navigate = useNavigate()
  const qc = useQueryClient()

  const query = useQuery({ queryKey: ['template', id], queryFn: () => templatesApi.get(id) })
  const sets = useQuery({ queryKey: ['question-sets'], queryFn: questionSetsApi.list })
  const [t, setT] = useState<InterviewTemplate | null>(null)
  const [genOpen, setGenOpen] = useState(false)

  useEffect(() => { if (query.data) setT(query.data) }, [query.data])

  const save = useMutation({
    mutationFn: () => templatesApi.update(id, t!),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['templates'] })
      qc.invalidateQueries({ queryKey: ['template', id] })
      toast.success('Template saved')
    },
    onError: (e: Error) => toast.error(e.message),
  })

  const pctOf = useMemo(() => (t ? normalizedWeights(t.rubric.kpis) : () => 0), [t])

  if (query.isLoading || !t) {
    return <div className="max-w-[1440px] mx-auto px-6 py-8 space-y-4"><Skeleton className="h-10 w-64" /><Skeleton className="h-96" /></div>
  }

  const patch = (p: Partial<InterviewTemplate>) => setT({ ...t, ...p })
  const patchTiming = (p: Partial<InterviewTemplate['timing']>) => setT({ ...t, timing: { ...t.timing, ...p } })
  const patchBranding = (p: Partial<InterviewTemplate['branding']>) => setT({ ...t, branding: { ...t.branding, ...p } })
  const patchIntegrity = (p: Partial<InterviewTemplate['integrity']>) => setT({ ...t, integrity: { ...t.integrity, ...p } })
  const patchAdaptive = (p: Partial<AdaptiveConfig>) => setT({ ...t, adaptive: { ...DEF_ADAPTIVE, ...(t.adaptive ?? {}), role: t.role, ...p } })
  const patchConvTiming = (p: Partial<ConversationTimingConfig>) => setT({ ...t, conversationTiming: { ...DEF_CONV, ...(t.conversationTiming ?? {}), ...p } })
  const patchKpi = (kid: string, p: Partial<KpiDefinition>) =>
    setT({ ...t, rubric: { ...t.rubric, kpis: t.rubric.kpis.map((k) => (k.id === kid ? { ...k, ...p } : k)) } })
  const addKpi = () =>
    setT({ ...t, rubric: { ...t.rubric, kpis: [...t.rubric.kpis, { id: crypto.randomUUID(), label: 'New KPI', description: '', weight: 1, enabled: true }] } })
  const removeKpi = (kid: string) =>
    setT({ ...t, rubric: { ...t.rubric, kpis: t.rubric.kpis.filter((k) => k.id !== kid) } })

  const conversational = t.track === 'chatbot' || t.track === 'video_avatar'
  const selectedSet = sets.data?.find((s) => s.id === t.fixedQuestionSetId)
  const adaptiveCount = conversational ? (t.adaptive?.numberOfQuestions ?? 5) : (t.timing.numberOfQuestions ?? 0)
  const questionCount = t.questionSource === 'fixed' ? selectedSet?.questions.length ?? 0 : adaptiveCount
  const perQ =
    conversational
      ? t.mode === 'timed'
        ? (t.conversationTiming?.thinkingSeconds ?? 30) + (t.conversationTiming?.perQuestionSeconds ?? 120)
        : 90
      : t.timing.prepSeconds + t.timing.answerSeconds
  const totalMin = Math.round((questionCount * perQ) / 60)

  return (
    <div className="max-w-[1440px] mx-auto px-6 py-8">
      <button onClick={() => navigate('/templates')} className="mb-3 inline-flex items-center gap-1.5 text-sm font-medium text-neutral-500 hover:text-neutral-800">
        <ArrowLeft size={15} /> Templates
      </button>
      <PageHeader
        kicker="Template"
        title={t.name || 'Untitled template'}
        action={<Button icon={<Save size={16} />} loading={save.isPending} onClick={() => save.mutate()}>Save template</Button>}
      />

      <GenerateFromResumeModal
        open={genOpen}
        onClose={() => setGenOpen(false)}
        defaultRole={t.role}
        onSaved={(set) => {
          qc.invalidateQueries({ queryKey: ['question-sets'] })
          setT((prev) => (prev ? { ...prev, questionSource: 'fixed', fixedQuestionSetId: set.id } : prev))
          toast.success('New set selected — click Save template to keep it')
        }}
      />

      <div className="grid gap-6 lg:grid-cols-[1fr_360px]">
        {/* ── form ── */}
        <div className="space-y-8">
          <section>
            <SectionTitle>Basics</SectionTitle>
            <Card className="space-y-4 p-5">
              <Input label="Template name" value={t.name} onChange={(e) => patch({ name: e.target.value })} />
              <div className="grid grid-cols-2 gap-4">
                <Input label="Role" value={t.role} onChange={(e) => patch({ role: e.target.value })} />
                <Input label="Seniority" value={t.seniority ?? ''} onChange={(e) => patch({ seniority: e.target.value })} placeholder="e.g. Mid, Senior" />
              </div>
              <Select
                label="Track"
                value={t.track}
                onChange={(e) => patch({ track: e.target.value as InterviewTemplate['track'] })}
                options={[
                  { value: 'chat', label: 'Chat — one question at a time (timed slots)' },
                  { value: 'chatbot', label: 'Chatbot — conversational (ChatGPT-style)' },
                  { value: 'video_avatar', label: 'Video Avatar (scaffold)' },
                ]}
              />
            </Card>
          </section>

          <section>
            <SectionTitle>Questions</SectionTitle>
            <Card className="space-y-4 p-5">
              <Select
                label="Question source"
                value={t.questionSource}
                onChange={(e) => patch({ questionSource: e.target.value as InterviewTemplate['questionSource'] })}
                options={[{ value: 'fixed', label: 'Fixed — pick a saved question set' }, { value: 'adaptive', label: 'Adaptive — generated from résumé (Gemini)' }]}
              />
              {t.questionSource === 'fixed' ? (
                <div className="space-y-2">
                  <Select
                    label="Question set"
                    value={t.fixedQuestionSetId ?? ''}
                    onChange={(e) => patch({ fixedQuestionSetId: e.target.value })}
                    options={[{ value: '', label: '— select a set —' }, ...(sets.data ?? []).map((s) => ({ value: s.id, label: `${s.name} (${s.questions.length})` }))]}
                  />
                  <Button variant="outline" size="sm" icon={<Sparkles size={14} />} onClick={() => setGenOpen(true)}>
                    Generate set from résumé
                  </Button>
                </div>
              ) : conversational ? (
                <p className="text-sm text-neutral-500">
                  Questions are generated live from the résumé. Configure <b>style, difficulty, and count</b> under <b>Conversation</b> below.
                </p>
              ) : (
                <Input
                  label="Number of questions"
                  type="number"
                  value={t.timing.numberOfQuestions ?? 5}
                  onChange={(e) => patchTiming({ numberOfQuestions: num(e.target.value, 5) })}
                  hint="Tailored questions generated from the candidate's résumé at session start."
                />
              )}
            </Card>
          </section>

          {conversational && (
            <section>
              <SectionTitle>Conversation</SectionTitle>
              <Card className="space-y-4 p-5">
                <Select
                  label="Mode"
                  value={t.mode ?? 'conversational'}
                  onChange={(e) => patch({ mode: e.target.value as InterviewMode })}
                  options={[
                    { value: 'conversational', label: 'Conversational — relaxed, no timers' },
                    { value: 'timed', label: 'Timed — proctored thinking + answer limits' },
                  ]}
                />
                {t.questionSource === 'adaptive' ? (
                  <>
                    <div className="grid grid-cols-2 gap-4">
                      <Select
                        label="Question style"
                        value={t.adaptive?.style ?? 'mix'}
                        onChange={(e) => patchAdaptive({ style: e.target.value as QuestionStyle })}
                        options={[
                          { value: 'technical', label: 'Technical' },
                          { value: 'non_technical', label: 'Non-technical' },
                          { value: 'mix', label: 'Mixed' },
                        ]}
                      />
                      <Select
                        label="Difficulty"
                        value={t.adaptive?.difficulty ?? 'mixed'}
                        onChange={(e) => patchAdaptive({ difficulty: e.target.value as DifficultyChoice })}
                        options={['easy', 'medium', 'hard', 'mixed'].map((d) => ({ value: d, label: d[0].toUpperCase() + d.slice(1) }))}
                      />
                    </div>
                    {(t.adaptive?.style ?? 'mix') === 'mix' ? (
                      <div className="grid grid-cols-2 gap-4">
                        <Input
                          label="# Technical"
                          type="number"
                          value={t.adaptive?.technicalCount ?? 3}
                          onChange={(e) => {
                            const tc = num(e.target.value, 3)
                            patchAdaptive({ technicalCount: tc, numberOfQuestions: tc + (t.adaptive?.nonTechnicalCount ?? 2) })
                          }}
                        />
                        <Input
                          label="# Non-technical"
                          type="number"
                          value={t.adaptive?.nonTechnicalCount ?? 2}
                          onChange={(e) => {
                            const nc = num(e.target.value, 2)
                            patchAdaptive({ nonTechnicalCount: nc, numberOfQuestions: (t.adaptive?.technicalCount ?? 3) + nc })
                          }}
                        />
                      </div>
                    ) : (
                      <Input label="Number of questions" type="number" value={t.adaptive?.numberOfQuestions ?? 5} onChange={(e) => patchAdaptive({ numberOfQuestions: num(e.target.value, 5) })} />
                    )}
                    <Input
                      label="Focus topics (comma-separated)"
                      value={(t.adaptive?.focusTopics ?? []).join(', ')}
                      onChange={(e) => patchAdaptive({ focusTopics: e.target.value.split(',').map((s) => s.trim()).filter(Boolean) })}
                      placeholder="system design, Kafka, leadership"
                    />
                    <div className="grid grid-cols-2 gap-4">
                      <Input label="Interviewer tone" value={t.adaptive?.interviewerTone ?? ''} onChange={(e) => patchAdaptive({ interviewerTone: e.target.value })} placeholder="friendly and professional" />
                      <Input label="Language" value={t.adaptive?.language ?? ''} onChange={(e) => patchAdaptive({ language: e.target.value })} placeholder="English" />
                    </div>
                    <Divider className="my-1" />
                    <Toggle label="Allow follow-up questions" description="Off by default — the interview asks exactly the number of questions above. Turn on to let the interviewer drill into answers." checked={t.adaptive?.allowFollowUps ?? false} onChange={(v) => patchAdaptive({ allowFollowUps: v })} />
                    {(t.adaptive?.allowFollowUps ?? false) && (
                      <Input label="Max follow-ups per question" type="number" value={t.adaptive?.maxFollowUpsPerQuestion ?? 1} onChange={(e) => patchAdaptive({ maxFollowUpsPerQuestion: num(e.target.value, 1) })} />
                    )}
                  </>
                ) : (
                  <Toggle label="Allow follow-ups on the fixed set" description="Ask AI follow-ups between saved questions." checked={t.fixedAllowFollowUps ?? false} onChange={(v) => patch({ fixedAllowFollowUps: v })} />
                )}
                {t.mode === 'timed' && (
                  <>
                    <Divider className="my-1" />
                    <div className="grid grid-cols-3 gap-4">
                      <Input label="Thinking (s)" type="number" value={t.conversationTiming?.thinkingSeconds ?? 30} onChange={(e) => patchConvTiming({ thinkingSeconds: num(e.target.value, 30) })} />
                      <Input label="Answer (s)" type="number" value={t.conversationTiming?.perQuestionSeconds ?? 120} onChange={(e) => patchConvTiming({ perQuestionSeconds: num(e.target.value, 120) })} />
                      <Input label="Warning at (s)" type="number" value={t.conversationTiming?.warningThresholdSeconds ?? 15} onChange={(e) => patchConvTiming({ warningThresholdSeconds: num(e.target.value, 15) })} />
                    </div>
                    <Toggle label="Allow skipping thinking time" checked={t.conversationTiming?.allowSkipThinking ?? true} onChange={(v) => patchConvTiming({ allowSkipThinking: v })} />
                    <Toggle label="Allow early submit" checked={t.conversationTiming?.allowEarlySubmit ?? true} onChange={(v) => patchConvTiming({ allowEarlySubmit: v })} />
                  </>
                )}
              </Card>
            </section>
          )}

          {t.track === 'chat' && (
          <section>
            <SectionTitle>Timing</SectionTitle>
            <Card className="space-y-4 p-5">
              <div className="grid grid-cols-3 gap-4">
                <Input label="Prep (s)" type="number" value={t.timing.prepSeconds} onChange={(e) => patchTiming({ prepSeconds: num(e.target.value, 30) })} />
                <Input label="Answer (s)" type="number" value={t.timing.answerSeconds} onChange={(e) => patchTiming({ answerSeconds: num(e.target.value, 120) })} />
                <Input label="Warning at (s)" type="number" value={t.timing.warningThresholdSeconds} onChange={(e) => patchTiming({ warningThresholdSeconds: num(e.target.value, 15) })} />
              </div>
              <Divider className="my-1" />
              <Toggle label="Allow skipping preparation" description="Candidate can start answering before prep ends." checked={t.timing.allowSkipPrep} onChange={(v) => patchTiming({ allowSkipPrep: v })} />
              <Toggle label="Allow early submit" description="Candidate can submit before the answer timer ends." checked={t.timing.allowEarlySubmit} onChange={(v) => patchTiming({ allowEarlySubmit: v })} />
              <Input label="Overall time cap (s, optional)" type="number" value={t.timing.totalTimeCapSeconds ?? ''} onChange={(e) => patchTiming({ totalTimeCapSeconds: e.target.value ? num(e.target.value, 0) : undefined })} placeholder="No cap" />
            </Card>
          </section>
          )}

          <section>
            <SectionTitle>Scoring rubric</SectionTitle>
            <Card className="space-y-3 p-5">
              <p className="text-xs text-neutral-400">Toggle KPIs, edit labels, and set weights — weights are auto-normalized. Add custom KPIs as needed.</p>
              {t.rubric.kpis.map((k) => (
                <div key={k.id} className="flex items-start gap-3 rounded-xl border border-border p-3">
                  <button
                    onClick={() => patchKpi(k.id, { enabled: !k.enabled })}
                    role="switch" aria-checked={k.enabled}
                    className={`mt-1 h-5 w-9 flex-shrink-0 rounded-full transition-colors ${k.enabled ? 'bg-primary-700' : 'bg-neutral-200'}`}
                  >
                    <span className={`block h-4 w-4 rounded-full bg-white transition-transform ${k.enabled ? 'translate-x-4' : 'translate-x-0.5'}`} />
                  </button>
                  <div className="min-w-0 flex-1 space-y-2">
                    <input value={k.label} onChange={(e) => patchKpi(k.id, { label: e.target.value })} className="input-base h-8 text-sm font-semibold" />
                    <input value={k.description} onChange={(e) => patchKpi(k.id, { description: e.target.value })} placeholder="Description" className="input-base h-8 text-xs text-neutral-500" />
                  </div>
                  <div className="flex w-20 flex-shrink-0 flex-col items-center gap-1">
                    <input type="number" min={0} value={k.weight} onChange={(e) => patchKpi(k.id, { weight: num(e.target.value, 1) })} className="input-base h-8 w-16 text-center text-sm" />
                    <span className="text-[11px] font-semibold text-primary-700 tabular-nums">{pctOf(k)}%</span>
                  </div>
                  <button onClick={() => removeKpi(k.id)} className="mt-1 rounded-lg p-1.5 text-neutral-300 hover:bg-danger-bg hover:text-danger" aria-label="Remove KPI">
                    <Trash2 size={14} />
                  </button>
                </div>
              ))}
              <Button variant="secondary" size="sm" icon={<Plus size={14} />} onClick={addKpi}>Add custom KPI</Button>
            </Card>
          </section>

          <section>
            <SectionTitle>Branding</SectionTitle>
            <Card className="space-y-4 p-5">
              <div className="grid grid-cols-2 gap-4">
                <Input label="Company name" value={t.branding.companyName} onChange={(e) => patchBranding({ companyName: e.target.value })} />
                <div className="flex flex-col gap-1.5">
                  <label className="field-label">Accent color</label>
                  <div className="flex items-center gap-2">
                    <input type="color" value={t.branding.accentColor} onChange={(e) => patchBranding({ accentColor: e.target.value })} className="h-10 w-12 cursor-pointer rounded-lg border border-border" />
                    <input value={t.branding.accentColor} onChange={(e) => patchBranding({ accentColor: e.target.value })} className="input-base font-mono text-sm" />
                  </div>
                </div>
              </div>
              <Input label="Logo URL (optional)" value={t.branding.logoUrl ?? ''} onChange={(e) => patchBranding({ logoUrl: e.target.value })} placeholder="https://…" />
              <Textarea label="Welcome message" value={t.branding.welcomeMessage ?? ''} onChange={(e) => patchBranding({ welcomeMessage: e.target.value })} className="h-20" />
            </Card>
          </section>

          <section>
            <SectionTitle>Integrity</SectionTitle>
            <Card className="space-y-1 p-5">
              <Toggle label="Enforce fullscreen" description="Ask the candidate to stay in fullscreen during the interview." checked={t.integrity.enforceFullscreen} onChange={(v) => patchIntegrity({ enforceFullscreen: v })} />
              <Toggle label="Detect tab switching" description="Count window blur / tab changes and warn the candidate." checked={t.integrity.detectTabSwitch} onChange={(v) => patchIntegrity({ detectTabSwitch: v })} />
              <Toggle label="Disable paste in answers" checked={t.integrity.disablePasteInAnswers} onChange={(v) => patchIntegrity({ disablePasteInAnswers: v })} />
              <Toggle label="Disable copy" checked={t.integrity.disableCopy} onChange={(v) => patchIntegrity({ disableCopy: v })} />
              <Toggle label="Log integrity events" description="Surface events in the recruiter report." checked={t.integrity.logEvents} onChange={(v) => patchIntegrity({ logEvents: v })} />
              <div className="pt-2">
                <Input label="Max tab-switch warnings" type="number" value={t.integrity.maxTabSwitchWarnings} onChange={(e) => patchIntegrity({ maxTabSwitchWarnings: num(e.target.value, 3) })} />
              </div>
            </Card>
          </section>
        </div>

        {/* ── live preview ── */}
        <div className="lg:sticky lg:top-20 lg:self-start">
          <SectionTitle>Live preview</SectionTitle>
          <Card className="space-y-5 p-5">
            <div>
              <span className="text-xs font-semibold uppercase tracking-wide text-neutral-400">Candidate sees</span>
              <div className="mt-2 flex items-center gap-2 rounded-xl border border-border p-3">
                <span className="flex h-7 w-7 items-center justify-center rounded text-xs font-bold text-white" style={{ background: t.branding.accentColor }}>
                  {t.branding.companyName.charAt(0) || 'T'}
                </span>
                <span className="text-sm font-bold text-neutral-800">{t.branding.companyName}</span>
                <Badge variant={t.track === 'chatbot' ? 'info' : t.track === 'video_avatar' ? 'info' : 'neutral'} className="ml-auto">{t.track === 'chatbot' ? 'Chatbot' : t.track === 'video_avatar' ? 'Video' : 'Chat'}</Badge>
              </div>
            </div>

            <div>
              <span className="text-xs font-semibold uppercase tracking-wide text-neutral-400">Per-question flow</span>
              <div className="mt-2 flex flex-wrap items-center gap-1.5 text-xs">
                {conversational ? (
                  t.mode === 'timed' ? (
                    <>
                      <span className="rounded-md bg-neutral-100 px-2 py-1 font-medium text-neutral-600">Think {t.conversationTiming?.thinkingSeconds ?? 30}s</span>
                      <span className="text-neutral-300">→</span>
                      <span className="rounded-md px-2 py-1 font-medium text-white" style={{ background: t.branding.accentColor }}>Answer {t.conversationTiming?.perQuestionSeconds ?? 120}s</span>
                      <span className="text-neutral-300">→</span>
                      <span className="rounded-md bg-neutral-100 px-2 py-1 font-medium text-neutral-600">{t.adaptive?.allowFollowUps ? 'Follow-ups' : 'Next'}</span>
                    </>
                  ) : (
                    <>
                      <span className="rounded-md px-2 py-1 font-medium text-white" style={{ background: t.branding.accentColor }}>Conversational</span>
                      <span className="text-neutral-300">·</span>
                      <span className="rounded-md bg-neutral-100 px-2 py-1 font-medium text-neutral-600">{t.adaptive?.allowFollowUps ? `up to ${t.adaptive?.maxFollowUpsPerQuestion ?? 1} follow-up(s)/Q` : 'no follow-ups'}</span>
                    </>
                  )
                ) : (
                  <>
                    <span className="rounded-md bg-neutral-100 px-2 py-1 font-medium text-neutral-600">Prep {t.timing.prepSeconds}s</span>
                    <span className="text-neutral-300">→</span>
                    <span className="rounded-md px-2 py-1 font-medium text-white" style={{ background: t.branding.accentColor }}>Answer {t.timing.answerSeconds}s</span>
                    <span className="text-neutral-300">→</span>
                    <span className="rounded-md bg-neutral-100 px-2 py-1 font-medium text-neutral-600">Auto-submit</span>
                  </>
                )}
              </div>
              <div className="mt-3 flex gap-4 text-sm">
                <div><span className="font-bold text-neutral-900 tabular-nums">{questionCount || '—'}</span> <span className="text-neutral-400">questions</span></div>
                <div><span className="font-bold text-neutral-900 tabular-nums">~{totalMin || '—'}</span> <span className="text-neutral-400">min total</span></div>
              </div>
              {t.questionSource === 'fixed' && !selectedSet && (
                <p className="mt-2 text-xs text-amber-600">⚠ No question set selected — sessions can’t start.</p>
              )}
            </div>

            <div>
              <span className="text-xs font-semibold uppercase tracking-wide text-neutral-400">Rubric weights</span>
              <div className="mt-2 space-y-1.5">
                {t.rubric.kpis.filter((k) => k.enabled).map((k) => (
                  <div key={k.id} className="flex items-center gap-2">
                    <span className="w-28 truncate text-xs text-neutral-600">{k.label}</span>
                    <div className="h-2 flex-1 overflow-hidden rounded-full bg-neutral-100">
                      <div className="h-full rounded-full" style={{ width: `${pctOf(k)}%`, background: t.branding.accentColor }} />
                    </div>
                    <span className="w-9 text-right text-[11px] font-semibold text-neutral-500 tabular-nums">{pctOf(k)}%</span>
                  </div>
                ))}
              </div>
            </div>
          </Card>
        </div>
      </div>
    </div>
  )
}
