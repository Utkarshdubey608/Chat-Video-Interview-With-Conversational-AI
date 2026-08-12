import { useEffect, useRef, useState } from 'react'
import toast from 'react-hot-toast'
import { UploadCloud, FileText, X, Trash2, Plus, Sparkles } from 'lucide-react'
import { Link } from 'react-router-dom'
import { Modal, Button, Input, Badge, cn } from '@/components/ui'
import { questionSetsApi, settingsApi } from '@/lib/api'
import type {
  QuestionSet, QuestionStyle, DifficultyChoice, GeminiModel,
  GeneratedInterviewQuestion, FixedQuestion,
} from '@shared/types'

type Editable = GeneratedInterviewQuestion & { _id: string }

const STYLES: { value: QuestionStyle; label: string }[] = [
  { value: 'technical', label: 'Technical' },
  { value: 'non_technical', label: 'Non-technical' },
  { value: 'mix', label: 'Mix' },
]
const DIFFICULTIES: DifficultyChoice[] = ['easy', 'medium', 'hard', 'mixed']
const MAX_MB = 10

/** Map a reviewed question onto the EXISTING FixedQuestion shape for persistence. */
const toFixed = (q: Editable): FixedQuestion => ({
  id: crypto.randomUUID(),
  text: q.text.trim(),
  category: q.category || undefined,
  idealAnswerNotes: [q.rationale, q.skillTag && `Skill: ${q.skillTag}`, `Type: ${q.type}`, `Difficulty: ${q.difficulty}`]
    .filter(Boolean)
    .join(' · '),
})

interface Props {
  open: boolean
  onClose: () => void
  defaultRole?: string
  onSaved: (set: QuestionSet) => void
}

export function GenerateFromResumeModal({ open, onClose, defaultRole, onSaved }: Props) {
  const [step, setStep] = useState<'form' | 'review'>('form')
  const [file, setFile] = useState<File | null>(null)
  const [dragOver, setDragOver] = useState(false)
  const [style, setStyle] = useState<QuestionStyle>('mix')
  const [techCount, setTechCount] = useState(5)
  const [nonTechCount, setNonTechCount] = useState(3)
  const [difficulty, setDifficulty] = useState<DifficultyChoice>('mixed')
  const [model, setModel] = useState<GeminiModel>('gemini-2.5-flash')
  const [name, setName] = useState('')
  const [role, setRole] = useState(defaultRole ?? '')
  const [apiKey, setApiKey] = useState('')
  const [keySet, setKeySet] = useState<boolean | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [questions, setQuestions] = useState<Editable[]>([])
  const fileInput = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (!open) return
    // Reset + check whether a server key already exists.
    setStep('form'); setFile(null); setError(null); setQuestions([])
    setStyle('mix'); setTechCount(5); setNonTechCount(3); setDifficulty('mixed')
    setName(''); setRole(defaultRole ?? ''); setApiKey('')
    settingsApi.status().then((s) => setKeySet(s.geminiKeySet)).catch(() => setKeySet(false))
  }, [open, defaultRole])

  const pickFile = (f: File | null) => {
    setError(null)
    if (!f) return
    if (f.type !== 'application/pdf') { setError('Please choose a PDF file.'); return }
    if (f.size > MAX_MB * 1024 * 1024) { setError(`File is too large (max ${MAX_MB} MB).`); return }
    setFile(f)
  }

  const total = style === 'mix' ? techCount + nonTechCount : style === 'technical' ? techCount : nonTechCount
  const needsKey = keySet === false
  const canGenerate = !!file && total >= 1 && total <= 25 && (!needsKey || apiKey.trim().length > 0)

  const generate = async () => {
    if (!file) return
    setBusy(true); setError(null)
    try {
      const fd = new FormData()
      fd.append('resume', file)
      fd.append('style', style)
      fd.append('technicalCount', String(techCount))
      fd.append('nonTechnicalCount', String(nonTechCount))
      fd.append('difficulty', difficulty)
      fd.append('model', model)
      if (role.trim()) fd.append('role', role.trim())
      if (name.trim()) fd.append('name', name.trim())
      if (needsKey && apiKey.trim()) fd.append('apiKey', apiKey.trim())

      const result = await questionSetsApi.generateFromResume(fd)
      setQuestions(result.questions.map((q) => ({ ...q, _id: crypto.randomUUID() })))
      if (!name.trim()) setName(result.suggestedName)
      setStep('review')
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Generation failed')
    } finally {
      setBusy(false)
    }
  }

  const save = async () => {
    const valid = questions.filter((q) => q.text.trim())
    if (!valid.length) { toast.error('Add at least one question'); return }
    setBusy(true)
    try {
      const set = await questionSetsApi.create({ name: name.trim() || 'Résumé Screen', questions: valid.map(toFixed) })
      toast.success(`Saved “${set.name}” (${set.questions.length} questions)`)
      onSaved(set)
      onClose()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Save failed')
    } finally {
      setBusy(false)
    }
  }

  const patch = (id: string, p: Partial<Editable>) =>
    setQuestions((qs) => qs.map((q) => (q._id === id ? { ...q, ...p } : q)))

  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Generate question set from résumé"
      description={step === 'form' ? 'Upload a PDF résumé — Gemini tailors questions to the candidate.' : 'Review and edit, then save as a new question set.'}
      width="max-w-2xl"
    >
      {step === 'form' ? (
        <div className="space-y-5">
          {/* dropzone */}
          <div>
            <label className="field-label mb-1.5 block">Résumé (PDF)</label>
            {file ? (
              <div className="flex items-center gap-3 rounded-xl border border-border bg-neutral-50 p-3">
                <FileText size={20} className="text-primary-700" />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium text-neutral-800">{file.name}</p>
                  <p className="text-xs text-neutral-400">{(file.size / 1024 / 1024).toFixed(2)} MB</p>
                </div>
                <button onClick={() => setFile(null)} className="rounded-lg p-1.5 text-neutral-400 hover:bg-neutral-200" aria-label="Remove file"><X size={16} /></button>
              </div>
            ) : (
              <div
                onClick={() => fileInput.current?.click()}
                onDragOver={(e) => { e.preventDefault(); setDragOver(true) }}
                onDragLeave={() => setDragOver(false)}
                onDrop={(e) => { e.preventDefault(); setDragOver(false); pickFile(e.dataTransfer.files?.[0] ?? null) }}
                className={cn(
                  'flex cursor-pointer flex-col items-center justify-center gap-2 rounded-xl border-2 border-dashed p-7 text-center transition-colors',
                  dragOver ? 'border-primary-700 bg-primary-50' : 'border-border bg-neutral-50 hover:border-neutral-300',
                )}
              >
                <UploadCloud size={26} className="text-neutral-400" />
                <span className="text-sm font-medium text-neutral-600">Drag a PDF here, or click to choose</span>
                <span className="text-xs text-neutral-400">PDF only · max {MAX_MB} MB</span>
                <input ref={fileInput} type="file" accept="application/pdf,.pdf" className="hidden" onChange={(e) => pickFile(e.target.files?.[0] ?? null)} />
              </div>
            )}
          </div>

          {/* style */}
          <div>
            <label className="field-label mb-1.5 block">Question style</label>
            <div className="grid grid-cols-3 gap-2">
              {STYLES.map((s) => (
                <button key={s.value} onClick={() => setStyle(s.value)}
                  className={cn('rounded-lg border px-3 py-2 text-sm font-semibold transition-all',
                    style === s.value ? 'border-primary-700 bg-primary-700 text-white' : 'border-border bg-white text-neutral-600 hover:border-neutral-300')}>
                  {s.label}
                </button>
              ))}
            </div>
          </div>

          {/* counts */}
          {style === 'mix' ? (
            <div className="grid grid-cols-2 gap-4">
              <Input label="# Technical" type="number" min={0} max={25} value={techCount} onChange={(e) => setTechCount(Math.max(0, Number(e.target.value)))} />
              <Input label="# Non-technical" type="number" min={0} max={25} value={nonTechCount} onChange={(e) => setNonTechCount(Math.max(0, Number(e.target.value)))} />
            </div>
          ) : (
            <Input
              label="Number of questions" type="number" min={1} max={25}
              value={style === 'technical' ? techCount : nonTechCount}
              onChange={(e) => { const v = Math.max(1, Number(e.target.value)); style === 'technical' ? setTechCount(v) : setNonTechCount(v) }}
            />
          )}
          {(total < 1 || total > 25) && <p className="text-xs text-danger">Total questions must be between 1 and 25 (currently {total}).</p>}

          {/* difficulty */}
          <div>
            <label className="field-label mb-1.5 block">Difficulty</label>
            <div className="grid grid-cols-4 gap-2">
              {DIFFICULTIES.map((d) => (
                <button key={d} onClick={() => setDifficulty(d)}
                  className={cn('rounded-lg border px-2 py-1.5 text-xs font-semibold capitalize transition-all',
                    difficulty === d ? 'border-primary-700 bg-primary-50 text-primary-700' : 'border-border bg-white text-neutral-500 hover:border-neutral-300')}>
                  {d}
                </button>
              ))}
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <Input label="Role (optional)" value={role} onChange={(e) => setRole(e.target.value)} placeholder="e.g. Senior Backend Engineer" />
            <Input label="Question set name" value={name} onChange={(e) => setName(e.target.value)} placeholder="Auto from role" />
          </div>

          {/* model + key */}
          <div className="flex items-center justify-between rounded-lg bg-neutral-50 px-3 py-2">
            <span className="text-xs font-medium text-neutral-500">Model</span>
            <div className="flex gap-1">
              {(['gemini-2.5-flash', 'gemini-2.5-pro'] as GeminiModel[]).map((m) => (
                <button key={m} onClick={() => setModel(m)}
                  className={cn('rounded-md px-2.5 py-1 text-xs font-semibold', model === m ? 'bg-primary-700 text-white' : 'text-neutral-500 hover:bg-neutral-200')}>
                  {m.replace('gemini-2.5-', '')}
                </button>
              ))}
            </div>
          </div>

          {needsKey && (
            <div>
              <label className="field-label mb-1.5 block">Gemini API key</label>
              <input type="password" value={apiKey} onChange={(e) => setApiKey(e.target.value)} placeholder="AIza…" className="input-base font-mono text-xs" />
              <p className="mt-1 text-xs text-neutral-400">
                No key saved yet — enter one here, or{' '}
                <Link to="/settings" className="text-primary-700 underline" onClick={onClose}>save it in Settings</Link>.
              </p>
            </div>
          )}

          {error && <p className="rounded-lg border border-danger-border bg-danger-bg p-2.5 text-sm text-danger">{error}</p>}

          <div className="flex justify-end gap-2 pt-1">
            <Button variant="ghost" onClick={onClose}>Cancel</Button>
            <Button icon={busy ? undefined : <Sparkles size={16} />} loading={busy} disabled={!canGenerate} onClick={generate}>
              {busy ? 'Generating…' : 'Generate questions'}
            </Button>
          </div>
        </div>
      ) : (
        <div className="space-y-4">
          <Input label="Question set name" value={name} onChange={(e) => setName(e.target.value)} />
          <div className="flex items-center justify-between">
            <p className="text-xs font-semibold uppercase tracking-wide text-neutral-400">{questions.length} questions</p>
            <button onClick={() => setQuestions((qs) => [...qs, { _id: crypto.randomUUID(), text: '', type: 'technical', category: '', difficulty: 'medium', skillTag: '', rationale: '' }])}
              className="inline-flex items-center gap-1 text-xs font-semibold text-primary-700 hover:underline">
              <Plus size={13} /> Add question
            </button>
          </div>

          <div className="max-h-[42vh] space-y-3 overflow-y-auto pr-1">
            {questions.map((q, i) => (
              <div key={q._id} className="rounded-xl border border-border bg-white p-3">
                <div className="mb-2 flex items-start gap-2">
                  <span className="mt-1.5 text-xs font-bold text-neutral-300 tabular-nums">{i + 1}</span>
                  <textarea value={q.text} onChange={(e) => patch(q._id, { text: e.target.value })} className="textarea-base h-14 flex-1 text-sm" placeholder="Question text…" />
                  <button onClick={() => setQuestions((qs) => qs.filter((x) => x._id !== q._id))} className="rounded-lg p-1.5 text-neutral-300 hover:bg-danger-bg hover:text-danger" aria-label="Delete"><Trash2 size={15} /></button>
                </div>
                <div className="flex flex-wrap items-center gap-2 pl-6">
                  <select value={q.type} onChange={(e) => patch(q._id, { type: e.target.value as Editable['type'] })} className="rounded-md border border-border bg-white px-2 py-1 text-xs">
                    <option value="technical">technical</option>
                    <option value="non_technical">non-technical</option>
                  </select>
                  <select value={q.difficulty} onChange={(e) => patch(q._id, { difficulty: e.target.value as Editable['difficulty'] })} className="rounded-md border border-border bg-white px-2 py-1 text-xs capitalize">
                    <option value="easy">easy</option>
                    <option value="medium">medium</option>
                    <option value="hard">hard</option>
                  </select>
                  {q.category && <Badge variant="neutral">{q.category}</Badge>}
                  {q.skillTag && <Badge variant="info">{q.skillTag}</Badge>}
                </div>
              </div>
            ))}
          </div>

          <div className="flex justify-between gap-2 pt-1">
            <Button variant="ghost" onClick={() => setStep('form')}>← Back</Button>
            <Button loading={busy} onClick={save}>Save question set</Button>
          </div>
        </div>
      )}
    </Modal>
  )
}
