import { useEffect, useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import {
  DndContext, closestCenter, PointerSensor, KeyboardSensor, useSensor, useSensors, type DragEndEvent,
} from '@dnd-kit/core'
import {
  SortableContext, useSortable, verticalListSortingStrategy, arrayMove, sortableKeyboardCoordinates,
} from '@dnd-kit/sortable'
import { CSS } from '@dnd-kit/utilities'
import { Plus, Copy, Trash2, Save, GripVertical, FileText, Sparkles } from 'lucide-react'
import { PageHeader, Card, Button, Input, EmptyState, Skeleton, Badge } from '@/components/ui'
import { questionSetsApi } from '@/lib/api'
import { GenerateFromResumeModal } from './GenerateFromResumeModal'
import type { QuestionSet, FixedQuestion } from '@shared/types'

function SortableQuestion({
  q, index, onChange, onRemove,
}: { q: FixedQuestion; index: number; onChange: (p: Partial<FixedQuestion>) => void; onRemove: () => void }) {
  const { attributes, listeners, setNodeRef, transform, transition, isDragging } = useSortable({ id: q.id })
  const style = { transform: CSS.Transform.toString(transform), transition, opacity: isDragging ? 0.6 : 1, zIndex: isDragging ? 10 : undefined }
  return (
    <div ref={setNodeRef} style={style} className="flex gap-2 rounded-xl border border-border bg-white p-3">
      <button {...attributes} {...listeners} className="mt-1 cursor-grab touch-none self-start rounded p-1 text-neutral-300 hover:text-neutral-500 active:cursor-grabbing" aria-label="Drag to reorder">
        <GripVertical size={16} />
      </button>
      <span className="mt-1.5 text-xs font-bold text-neutral-300 tabular-nums">{index + 1}</span>
      <div className="min-w-0 flex-1 space-y-2">
        <textarea
          value={q.text}
          onChange={(e) => onChange({ text: e.target.value })}
          placeholder="Question text…"
          className="textarea-base h-16 text-sm"
        />
        <div className="grid grid-cols-2 gap-2">
          <input value={q.category ?? ''} onChange={(e) => onChange({ category: e.target.value })} placeholder="Category (optional)" className="input-base h-8 text-xs" />
          <input value={q.idealAnswerNotes ?? ''} onChange={(e) => onChange({ idealAnswerNotes: e.target.value })} placeholder="Ideal-answer notes (helps scoring)" className="input-base h-8 text-xs" />
        </div>
      </div>
      <button onClick={onRemove} className="self-start rounded-lg p-1.5 text-neutral-300 hover:bg-danger-bg hover:text-danger" aria-label="Remove question">
        <Trash2 size={15} />
      </button>
    </div>
  )
}

export default function QuestionSetsPage() {
  const qc = useQueryClient()
  const sets = useQuery({ queryKey: ['question-sets'], queryFn: questionSetsApi.list })
  const [activeId, setActiveId] = useState<string | null>(null)
  const [draft, setDraft] = useState<QuestionSet | null>(null)
  const [genOpen, setGenOpen] = useState(false)

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(KeyboardSensor, { coordinateGetter: sortableKeyboardCoordinates }),
  )

  // Select first set by default; load the active set into the editable draft.
  useEffect(() => {
    if (!activeId && sets.data?.length) setActiveId(sets.data[0].id)
  }, [sets.data, activeId])
  useEffect(() => {
    const found = sets.data?.find((s) => s.id === activeId)
    if (found) setDraft(structuredClone(found))
  }, [activeId, sets.data])

  const create = useMutation({
    mutationFn: () => questionSetsApi.create({ name: 'New set', questions: [] }),
    onSuccess: (s) => { qc.invalidateQueries({ queryKey: ['question-sets'] }); setActiveId(s.id); toast.success('Set created') },
  })
  const duplicate = useMutation({
    mutationFn: (id: string) => questionSetsApi.duplicate(id),
    onSuccess: (s) => { qc.invalidateQueries({ queryKey: ['question-sets'] }); setActiveId(s.id); toast.success('Set duplicated') },
  })
  const remove = useMutation({
    mutationFn: (id: string) => questionSetsApi.remove(id),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['question-sets'] }); setActiveId(null); setDraft(null); toast.success('Set deleted') },
  })
  const save = useMutation({
    mutationFn: () => questionSetsApi.update(draft!.id, { name: draft!.name, questions: draft!.questions }),
    onSuccess: () => { qc.invalidateQueries({ queryKey: ['question-sets'] }); toast.success('Set saved') },
    onError: (e: Error) => toast.error(e.message),
  })

  const onDragEnd = (e: DragEndEvent) => {
    if (!draft || !e.over || e.active.id === e.over.id) return
    const from = draft.questions.findIndex((q) => q.id === e.active.id)
    const to = draft.questions.findIndex((q) => q.id === e.over!.id)
    setDraft({ ...draft, questions: arrayMove(draft.questions, from, to) })
  }
  const addQuestion = () =>
    setDraft({ ...draft!, questions: [...draft!.questions, { id: crypto.randomUUID(), text: '', category: '', idealAnswerNotes: '' }] })

  return (
    <div className="max-w-[1440px] mx-auto px-6 py-8">
      <PageHeader kicker="AI Interview" title="Question Sets" description="Reusable fixed question sets for templates. Drag to reorder; notes improve scoring." />

      <GenerateFromResumeModal
        open={genOpen}
        onClose={() => setGenOpen(false)}
        onSaved={(set) => { qc.invalidateQueries({ queryKey: ['question-sets'] }); setActiveId(set.id) }}
      />

      {sets.isLoading ? (
        <Skeleton className="h-96" />
      ) : (
        <div className="grid gap-6 lg:grid-cols-[260px_1fr]">
          {/* set list */}
          <div className="space-y-2">
            <Button className="w-full" variant="outline" icon={<Sparkles size={15} />} onClick={() => setGenOpen(true)}>Generate from résumé</Button>
            <Button className="w-full" icon={<Plus size={15} />} loading={create.isPending} onClick={() => create.mutate()}>New set</Button>
            {(sets.data ?? []).map((s) => (
              <button
                key={s.id}
                onClick={() => setActiveId(s.id)}
                className={`flex w-full items-center gap-2 rounded-xl border p-3 text-left transition-all ${activeId === s.id ? 'border-primary-700 bg-primary-50' : 'border-border bg-white hover:border-neutral-300'}`}
              >
                <FileText size={15} className="flex-shrink-0 text-neutral-400" />
                <span className="min-w-0 flex-1 truncate text-sm font-medium text-neutral-800">{s.name}</span>
                <Badge variant="neutral">{s.questions.length}</Badge>
              </button>
            ))}
          </div>

          {/* editor */}
          {!draft ? (
            <Card className="p-0"><EmptyState icon="📚" title="Select or create a set" description="Pick a question set on the left, or create a new one." /></Card>
          ) : (
            <Card className="space-y-4 p-5">
              <div className="flex items-center gap-3">
                <input value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} className="input-base flex-1 text-base font-bold" />
                <Button variant="ghost" size="sm" icon={<Copy size={14} />} onClick={() => duplicate.mutate(draft.id)}>Duplicate</Button>
                <button onClick={() => { if (confirm(`Delete “${draft.name}”?`)) remove.mutate(draft.id) }} className="rounded-lg p-2 text-neutral-400 hover:bg-danger-bg hover:text-danger" aria-label="Delete set"><Trash2 size={15} /></button>
                <Button size="sm" icon={<Save size={14} />} loading={save.isPending} onClick={() => save.mutate()}>Save</Button>
              </div>

              {draft.questions.length === 0 ? (
                <EmptyState icon="✍️" title="No questions yet" description="Add the first question to this set." action={<Button size="sm" icon={<Plus size={14} />} onClick={addQuestion}>Add question</Button>} />
              ) : (
                <>
                  <DndContext sensors={sensors} collisionDetection={closestCenter} onDragEnd={onDragEnd}>
                    <SortableContext items={draft.questions.map((q) => q.id)} strategy={verticalListSortingStrategy}>
                      <div className="space-y-2">
                        {draft.questions.map((q, i) => (
                          <SortableQuestion
                            key={q.id}
                            q={q}
                            index={i}
                            onChange={(p) => setDraft({ ...draft, questions: draft.questions.map((x) => (x.id === q.id ? { ...x, ...p } : x)) })}
                            onRemove={() => setDraft({ ...draft, questions: draft.questions.filter((x) => x.id !== q.id) })}
                          />
                        ))}
                      </div>
                    </SortableContext>
                  </DndContext>
                  <Button variant="secondary" size="sm" icon={<Plus size={14} />} onClick={addQuestion}>Add question</Button>
                </>
              )}
            </Card>
          )}
        </div>
      )}
    </div>
  )
}
