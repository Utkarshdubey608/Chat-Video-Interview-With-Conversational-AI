import { useState } from 'react'
import toast from 'react-hot-toast'
import { usePersonas, useCreatePersona, useUpdatePersona, useDeletePersona, useReplicas } from '@/hooks/useTavus'
import { Button, Card, Modal, Input, Textarea, Select, Toggle, Slider, JsonPreview, SectionTitle, EmptyState, Skeleton, Badge, PageHeader } from '@/components/ui'
import { cn } from '@/components/ui'
import type { CreatePersonaInput, PersonaLayers, EmotionTag } from '@/types/tavus.types'

const EMOTIONS: EmotionTag[] = ['anger', 'positivity', 'surprise', 'sadness', 'curiosity']
const LLM_OPTS = [
  { value: 'gpt-4o', label: 'GPT-4o' }, { value: 'gpt-4o-mini', label: 'GPT-4o Mini' },
  { value: 'claude-3-5-sonnet', label: 'Claude 3.5 Sonnet' }, { value: 'gemini-1.5-pro', label: 'Gemini 1.5 Pro' },
  { value: 'custom', label: 'Custom endpoint' },
]
const TTS_OPTS = [{ value: 'tavus', label: 'Tavus (default)' }, { value: 'cartesia', label: 'Cartesia' }, { value: 'eleven_labs', label: 'ElevenLabs' }]
const STT_OPTS = [{ value: 'tavus', label: 'Tavus (default)' }, { value: 'deepgram', label: 'Deepgram' }, { value: 'custom', label: 'Custom' }]

const defaultLayers = (): PersonaLayers => ({
  llm: { model: 'gpt-4o', max_tokens: 1024, temperature: 0.7 },
  tts: { tts_engine: 'tavus', voice_settings: { speed: 1.0, emotion: ['positivity'] } },
  stt: { stt_engine: 'tavus', participant_pause_sensitivity: 0.5, smart_turn_detection: true },
  perception: { ambient_awareness_queries: [] }, vqa: { enable_camera: false },
})

type FormState = Omit<CreatePersonaInput, 'layers'> & { layers: PersonaLayers }

export default function PersonasPage() {
  const { data: personas, isLoading } = usePersonas()
  const { data: replicas } = useReplicas()
  const create = useCreatePersona(); const update = useUpdatePersona(); const del = useDeletePersona()
  const [showForm, setShowForm] = useState(false)
  const [editing, setEditing] = useState<string | null>(null)
  const [form, setForm] = useState<FormState>({ persona_name: '', system_prompt: '', context: '', default_replica_id: '', layers: defaultLayers() })

  const repOpts = [{ value: '', label: '— None —' }, ...(replicas ?? []).map(r => ({ value: r.replica_id, label: r.replica_name }))]
  const setF = <K extends keyof FormState>(k: K, v: FormState[K]) => setForm(p => ({ ...p, [k]: v }))
  const setLayer = <S extends keyof PersonaLayers>(s: S, patch: Partial<NonNullable<PersonaLayers[S]>>) =>
    setForm(p => ({ ...p, layers: { ...p.layers, [s]: { ...(p.layers[s] ?? {}), ...patch } } }))

  function openCreate() { setForm({ persona_name: '', system_prompt: '', context: '', default_replica_id: '', layers: defaultLayers() }); setEditing(null); setShowForm(true) }
  function openEdit(id: string) {
    const p = personas?.find(x => x.persona_id === id); if (!p) return
    setForm({ persona_name: p.persona_name, system_prompt: p.system_prompt, context: p.context ?? '', default_replica_id: p.default_replica_id ?? '', layers: p.layers ?? defaultLayers() })
    setEditing(id); setShowForm(true)
  }

  function submit() {
    const payload: CreatePersonaInput = { persona_name: form.persona_name, system_prompt: form.system_prompt, ...(form.context && { context: form.context }), ...(form.default_replica_id && { default_replica_id: form.default_replica_id }), layers: form.layers }
    const opts = { onSuccess: () => { toast.success(editing ? 'Persona updated' : 'Persona created'); setShowForm(false) }, onError: (e: any) => toast.error(e.message) }
    editing ? update.mutate({ id: editing, data: payload }, opts) : create.mutate(payload, opts)
  }

  const L = form.layers; const llm = L.llm ?? {}; const tts = L.tts ?? {}
  const stt = L.stt ?? {}; const perception = L.perception ?? {}; const vqa = L.vqa ?? {}

  return (
    <div className="max-w-[1400px] mx-auto px-6 py-8">
      <PageHeader
        kicker="AI Behaviour"
        title="Personas"
        description="Configure how your AI avatar thinks (LLM), speaks (TTS), listens (STT), and perceives the environment."
        action={<Button onClick={openCreate}>+ New Persona</Button>}
      />

      {isLoading ? (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">{[...Array(6)].map((_, i) => <Skeleton key={i} className="h-52" />)}</div>
      ) : !personas?.length ? (
        <EmptyState icon="🤖" title="No personas yet" description="Create a persona to define how your AI avatar thinks, speaks, and listens during interviews."
          action={<Button onClick={openCreate}>Create First Persona</Button>} />
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {personas.map(p => (
            <Card key={p.persona_id} hover className="p-5 flex flex-col gap-3">
              <div className="flex items-start justify-between gap-2">
                <div className="min-w-0">
                  <p className="text-sm font-semibold text-neutral-900 truncate">{p.persona_name}</p>
                  <p className="text-xs text-neutral-400 font-mono mt-0.5 truncate">{p.persona_id}</p>
                </div>
                {p.layers?.llm?.model && <Badge variant="info" className="flex-shrink-0">{p.layers.llm.model}</Badge>}
              </div>
              <p className="text-xs text-neutral-500 line-clamp-3 leading-relaxed flex-1">{p.system_prompt}</p>
              {p.layers?.tts?.tts_engine && p.layers.tts.tts_engine !== 'tavus' && (
                <p className="text-xs text-neutral-400">TTS: {p.layers.tts.tts_engine}</p>
              )}
              <div className="flex gap-2 pt-3 border-t border-border mt-auto">
                <Button variant="ghost" size="sm" onClick={() => openEdit(p.persona_id)}>Edit</Button>
                <Button variant="danger" size="sm" onClick={() => del.mutate(p.persona_id, { onSuccess: () => toast.success('Deleted'), onError: (e: any) => toast.error(e.message) })}>Delete</Button>
              </div>
            </Card>
          ))}
        </div>
      )}

      {/* Form modal */}
      <Modal open={showForm} onClose={() => setShowForm(false)} title={editing ? 'Edit Persona' : 'Create Persona'} description="All fields map directly to the Tavus personas API." width="max-w-5xl">
        <div className="grid grid-cols-1 lg:grid-cols-[1fr_340px] gap-6">
          {/* Form fields */}
          <div className="space-y-5 overflow-y-auto max-h-[64vh] pr-2">

            <SectionTitle>Identity</SectionTitle>
            <Input label="Persona Name *" value={form.persona_name} onChange={e => setF('persona_name', e.target.value)} placeholder="e.g. Alex — TalbotIQ Senior Interviewer" />
            <Select label="Default Replica" options={repOpts} value={form.default_replica_id} onChange={e => setF('default_replica_id', e.target.value)} />
            <Textarea label="System Prompt *" value={form.system_prompt} onChange={e => setF('system_prompt', e.target.value)} charLimit={4096} placeholder="You are Alex, a professional interviewer at TalbotIQ. Ask each question clearly and wait for the candidate's full response before proceeding. Maintain a warm, encouraging tone." className="min-h-[110px]" />
            <Textarea label="Context" value={form.context} onChange={e => setF('context', e.target.value)} placeholder="Additional context the avatar should know about the role, company, or candidate…" />

            <SectionTitle>LLM Layer</SectionTitle>
            <Select label="Model" options={LLM_OPTS} value={llm.model ?? 'gpt-4o'} onChange={e => setLayer('llm', { model: e.target.value as any })} />
            {llm.model === 'custom' && (
              <div className="space-y-3 p-4 bg-neutral-50 rounded-xl border border-border">
                <Input label="Base URL" value={llm.base_url ?? ''} onChange={e => setLayer('llm', { base_url: e.target.value })} placeholder="https://api.example.com/v1" />
                <Input label="API Key" value={llm.api_key ?? ''} onChange={e => setLayer('llm', { api_key: e.target.value })} placeholder="sk-…" />
              </div>
            )}
            <div className="grid grid-cols-2 gap-4">
              <Input label="Max Tokens" type="number" min={1} max={4096} value={llm.max_tokens ?? 1024} onChange={e => setLayer('llm', { max_tokens: Number(e.target.value) })} />
              <Slider label="Temperature" min={0} max={2} step={0.05} value={llm.temperature ?? 0.7} onChange={v => setLayer('llm', { temperature: v })} formatValue={v => v.toFixed(2)} hint="0 = deterministic  ·  2 = creative" />
            </div>

            <SectionTitle>TTS Layer</SectionTitle>
            <Select label="TTS Engine" options={TTS_OPTS} value={tts.tts_engine ?? 'tavus'} onChange={e => setLayer('tts', { tts_engine: e.target.value as any })} />
            {tts.tts_engine !== 'tavus' && (
              <div className="space-y-3 p-4 bg-neutral-50 rounded-xl border border-border">
                <Input label="TTS API Key" value={tts.api_key ?? ''} onChange={e => setLayer('tts', { api_key: e.target.value })} placeholder="ElevenLabs / Cartesia key" />
                <Input label="External Voice ID" value={tts.external_voice_id ?? ''} onChange={e => setLayer('tts', { external_voice_id: e.target.value })} placeholder="voice_xxxxxxxx" />
              </div>
            )}
            <Slider label="Speaking Speed" min={0.5} max={2} step={0.05} value={tts.voice_settings?.speed ?? 1.0} onChange={v => setLayer('tts', { voice_settings: { ...(tts.voice_settings ?? {}), speed: v } })} formatValue={v => `${v.toFixed(2)}×`} />
            <div>
              <label className="field-label mb-2 block">Voice Emotions</label>
              <div className="flex flex-wrap gap-2">
                {EMOTIONS.map(tag => {
                  const active = (tts.voice_settings?.emotion ?? []).includes(tag)
                  return (
                    <button key={tag} type="button"
                      onClick={() => { const cur = tts.voice_settings?.emotion ?? []; const next = active ? cur.filter(t => t !== tag) : [...cur, tag]; setLayer('tts', { voice_settings: { ...(tts.voice_settings ?? {}), emotion: next } }) }}
                      className={cn('px-3 h-7 rounded-full text-xs font-semibold border transition-all', active ? 'bg-primary-700 text-white border-primary-700' : 'bg-white text-neutral-500 border-border hover:border-primary-300 hover:text-primary-600')}>
                      {tag}
                    </button>
                  )
                })}
              </div>
            </div>

            <SectionTitle>STT Layer</SectionTitle>
            <Select label="STT Engine" options={STT_OPTS} value={stt.stt_engine ?? 'tavus'} onChange={e => setLayer('stt', { stt_engine: e.target.value as any })} />
            <Slider label="Pause Sensitivity" min={0} max={1} step={0.05} value={stt.participant_pause_sensitivity ?? 0.5} onChange={v => setLayer('stt', { participant_pause_sensitivity: v })} hint="Low (0.0) — Medium (0.5) — High (1.0)" />
            <div className="bg-neutral-50 rounded-xl p-2 border border-border">
              <Toggle checked={stt.smart_turn_detection ?? true} onChange={v => setLayer('stt', { smart_turn_detection: v })} label="Smart Turn Detection" description="Detects natural speech pauses to know when the avatar should respond" />
            </div>

            <SectionTitle>Perception Layer</SectionTitle>
            <div>
              <label className="field-label mb-2 block">Ambient Awareness Queries</label>
              <div className="space-y-2">
                {(perception.ambient_awareness_queries ?? []).map((q, i) => (
                  <div key={i} className="flex gap-2">
                    <input value={q} onChange={e => { const arr = [...(perception.ambient_awareness_queries ?? [])]; arr[i] = e.target.value; setLayer('perception', { ambient_awareness_queries: arr }) }}
                      className="input-base flex-1" placeholder="e.g. Is the candidate in a quiet environment?" />
                    <button onClick={() => { const arr = [...(perception.ambient_awareness_queries ?? [])]; arr.splice(i, 1); setLayer('perception', { ambient_awareness_queries: arr }) }}
                      className="p-2 rounded-lg text-neutral-400 hover:text-danger hover:bg-danger-bg transition-all">
                      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                    </button>
                  </div>
                ))}
                <button onClick={() => setLayer('perception', { ambient_awareness_queries: [...(perception.ambient_awareness_queries ?? []), ''] })}
                  className="text-xs font-medium text-primary-600 hover:text-primary-700 transition-colors">
                  + Add query
                </button>
              </div>
            </div>
            <Input label="Perception Model" value={perception.perception_model ?? ''} onChange={e => setLayer('perception', { perception_model: e.target.value })} placeholder="Optional custom model ID" />

            <SectionTitle>VQA Layer</SectionTitle>
            <div className="bg-neutral-50 rounded-xl p-2 border border-border">
              <Toggle checked={vqa.enable_camera ?? false} onChange={v => setLayer('vqa', { enable_camera: v })} label="Enable Camera (VQA)" description="Allow the avatar to see and respond to the candidate's visual environment" />
            </div>
          </div>

          {/* JSON Preview */}
          <div className="hidden lg:flex flex-col gap-4">
            <JsonPreview data={{ persona_name: form.persona_name, system_prompt: form.system_prompt, context: form.context, default_replica_id: form.default_replica_id, layers: form.layers }} title="API Preview" method={editing ? 'PATCH' : 'POST'} endpoint="/v2/personas" />
            <div className="flex gap-2 justify-end">
              <Button variant="secondary" onClick={() => setShowForm(false)}>Cancel</Button>
              <Button onClick={submit} loading={create.isPending || update.isPending}>{editing ? 'Save Changes' : 'Create Persona'}</Button>
            </div>
          </div>
        </div>
        <div className="flex gap-2 justify-end mt-4 lg:hidden border-t border-border pt-4">
          <Button variant="secondary" onClick={() => setShowForm(false)}>Cancel</Button>
          <Button onClick={submit} loading={create.isPending || update.isPending}>{editing ? 'Save Changes' : 'Create Persona'}</Button>
        </div>
      </Modal>
    </div>
  )
}
