import { useCallback, useMemo, useRef, useState } from 'react'
import { useParams, Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import {
  DndContext, DragOverlay, PointerSensor, KeyboardSensor, useSensor, useSensors,
  useDraggable, useDroppable, pointerWithin, rectIntersection,
  type CollisionDetection, type DragEndEvent, type DragStartEvent,
} from '@dnd-kit/core'
import { ArrowLeft, AlertTriangle, GripVertical, Download, History as HistoryIcon, Undo2 } from 'lucide-react'
import { pipelinesApi, downloadCsv } from '@/lib/api'
import { useAutopilotActions } from '@/features/guide/autopilot/registry'
import { Card, Button, Badge, PageHeader, Skeleton, Select, cn } from '@/components/ui'
import { AdvanceModal, type AdvanceModalKind } from './AdvanceModal'
import type { BoardCard, BoardColumn, PipelineBoard, RoundDef, AuditEntry } from '@shared/types'

/** Pointer-first collision detection. `closestCenter` measured column-center to
 *  card-center, so dropping onto a SHORT/EMPTY column (Selected, Not-advancing)
 *  kept resolving to the taller source column and the drop silently no-op'd.
 *  `pointerWithin` registers the drop wherever the pointer actually is; the
 *  `rectIntersection` fallback covers keyboard drags / gaps between columns. */
const boardCollision: CollisionDetection = (args) => {
  const pointerHits = pointerWithin(args)
  return pointerHits.length > 0 ? pointerHits : rectIntersection(args)
}

/** Per-round status shown on a card. Mirrors `buildBoard`'s `roundStatus`
 *  derivation in server/routes/pipelines.ts (join of report + session state). */
const ROUND_STATUS_LABEL: Record<BoardCard['roundStatus'], { label: string; variant: 'success' | 'warning' | 'danger' | 'neutral' | 'info' }> = {
  completed: { label: 'Scored', variant: 'success' },
  in_progress: { label: 'In progress', variant: 'info' },
  invited: { label: 'Invited', variant: 'neutral' },
  expired: { label: 'Expired', variant: 'danger' },
  none: { label: 'Invited', variant: 'neutral' },
}

/** Client mirror of the server's pure `selectByCriteria` (server/routes/pipelines.ts)
 *  — kept in sync deliberately (both null-score-excluding, both top-N-by-score-desc)
 *  so the quick-advance preview always matches what the server would actually pick. */
function pickByCriteria(cards: BoardCard[], mode: 'threshold' | 'topN', value: number): BoardCard[] {
  const scored = cards.filter((c) => c.advanceable && c.score !== null)
  if (mode === 'threshold') return scored.filter((c) => (c.score as number) >= value)
  return [...scored].sort((a, b) => (b.score as number) - (a.score as number)).slice(0, Math.max(0, value))
}

function roundLabel(rounds: RoundDef[], idx: number | undefined): string {
  if (idx === undefined) return ''
  return rounds[idx]?.name ?? `Round ${idx + 1}`
}

const ACTION_VERB: Record<AuditEntry['action'], string> = {
  invited: 'Invited', advanced: 'Advanced', selected: 'Selected',
  not_advancing: 'Not advancing', moved_back: 'Moved back',
}

/** Read-only, human-readable rendering of one audit entry for the per-card history panel. */
function describeEntry(entry: AuditEntry, rounds: RoundDef[]): string {
  let what = ACTION_VERB[entry.action]
  if (entry.action === 'advanced' || entry.action === 'moved_back') {
    what += ` ${roundLabel(rounds, entry.fromRound)} → ${roundLabel(rounds, entry.toRound)}`
  } else if (entry.action === 'invited' && entry.toRound !== undefined) {
    what += ` to ${roundLabel(rounds, entry.toRound)}`
  } else if (entry.action === 'selected' && entry.fromRound !== undefined) {
    what += ` from ${roundLabel(rounds, entry.fromRound)}`
  }
  const bits = [what, new Date(entry.at).toLocaleString()]
  if (entry.basis) bits.push(entry.basis)
  if (entry.emailResult) bits.push(`email ${entry.emailResult}`)
  return bits.join(' · ')
}

function Cardlet({
  card, columnKey, rounds, onAdvance, onReject, onMoveBack, auditOpen, onToggleAudit,
}: {
  card: BoardCard
  columnKey: string
  rounds: RoundDef[]
  onAdvance: (card: BoardCard) => void
  onReject: (card: BoardCard) => void
  onMoveBack: (card: BoardCard) => void
  auditOpen: boolean
  onToggleAudit: () => void
}) {
  const s = ROUND_STATUS_LABEL[card.roundStatus]
  // Drag is a shortcut onto `advanceable` cards only — the modal (below) is what
  // actually mutates; dragging just pre-fills it with this one candidate.
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
    id: card.pipelineCandidateId,
    data: { card, columnKey },
    disabled: !card.advanceable,
  })
  const style = transform ? { transform: `translate3d(${transform.x}px, ${transform.y}px, 0)`, zIndex: 20 } : undefined
  // Mirrors the server's move-back guard (status must still be 'in_round' — a
  // terminal 'selected'/'not_advancing' candidate always 400s) plus the brief's
  // currentRoundIndex>0 + not-yet-completed conditions.
  const canMoveBack = card.status === 'in_round' && card.currentRoundIndex > 0 && card.roundStatus !== 'completed'

  return (
    <div
      ref={setNodeRef}
      style={style}
      className={cn('card p-3', card.advanceable && 'ring-1 ring-primary-300', isDragging && 'opacity-40 shadow-lg')}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0 flex-1">
          <div className="truncate text-sm font-medium text-neutral-800">{card.candidateName || card.candidateEmail}</div>
          <div className="truncate text-xs text-neutral-400">{card.candidateEmail}</div>
        </div>
        {card.advanceable && (
          <button
            {...attributes}
            {...listeners}
            className="shrink-0 cursor-grab touch-none rounded p-1 text-neutral-300 hover:text-neutral-500 active:cursor-grabbing"
            aria-label="Drag to advance"
          >
            <GripVertical size={14} />
          </button>
        )}
      </div>
      <div className="mt-2 flex items-center justify-between gap-2">
        <Badge variant={s.variant}>{s.label}</Badge>
        {card.score !== null
          ? <span className="text-sm font-semibold text-neutral-700">{card.score}</span>
          : <span className="text-xs text-neutral-300">—</span>}
      </div>
      <div className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1">
        {card.advanceable && (
          <button onClick={() => onAdvance(card)} className="text-xs font-medium text-primary-700 hover:underline">
            Advance →
          </button>
        )}
        {card.status === 'in_round' && (
          <button onClick={() => onReject(card)} className="text-xs text-neutral-400 hover:text-danger">
            Not advancing
          </button>
        )}
        {canMoveBack && (
          <button onClick={() => onMoveBack(card)} className="inline-flex items-center gap-1 text-xs text-neutral-400 hover:text-neutral-700">
            <Undo2 size={11} /> Move back
          </button>
        )}
        {card.history.length > 0 && (
          <button onClick={onToggleAudit} className="inline-flex items-center gap-1 text-xs text-neutral-400 hover:text-neutral-700">
            <HistoryIcon size={11} /> {auditOpen ? 'Hide' : 'History'}
          </button>
        )}
      </div>
      {auditOpen && card.history.length > 0 && (
        <div className="mt-2 space-y-1 rounded-lg bg-neutral-50 p-2 text-[11px] leading-snug text-neutral-500">
          {card.history.map((h, i) => <div key={i}>{describeEntry(h, rounds)}</div>)}
        </div>
      )}
    </div>
  )
}

/** Compact "score ≥ X" / "top N" control shown on each round column, pre-filled from
 *  that round's `advanceRule` (if any). Apply computes the eligible set client-side
 *  (`pickByCriteria`) and hands it to the parent, which opens the confirm modal —
 *  it never mutates directly. */
function QuickAdvanceBar({ round, onApply }: { round: RoundDef | undefined; onApply: (mode: 'threshold' | 'topN', value: number) => void }) {
  const [mode, setMode] = useState<'threshold' | 'topN'>(round?.advanceRule?.kind ?? 'threshold')
  const [value, setValue] = useState<number>(round?.advanceRule?.value ?? 60)

  return (
    <div className="mb-2 flex items-center gap-1 px-1">
      <Select
        value={mode}
        onChange={(e) => setMode(e.target.value as 'threshold' | 'topN')}
        options={[{ value: 'threshold', label: 'Score ≥' }, { value: 'topN', label: 'Top N' }]}
        className="!h-8 w-24 !py-0 text-xs"
      />
      <input
        type="number"
        value={value}
        onChange={(e) => setValue(Number(e.target.value))}
        className="input-base h-8 w-16 px-2 text-xs"
      />
      <Button size="sm" variant="outline" onClick={() => onApply(mode, value)}>Apply</Button>
    </div>
  )
}

function DroppableColumn({ col, children }: { col: BoardColumn; children: React.ReactNode }) {
  const { setNodeRef, isOver } = useDroppable({ id: col.key })
  return (
    <div
      ref={setNodeRef}
      className={cn(
        // min-h keeps EMPTY columns (Selected / Not-advancing) a large, reliable
        // drop target — otherwise a short empty column is nearly impossible to hit.
        'flex min-h-[16rem] w-72 shrink-0 flex-col rounded-2xl bg-neutral-50 p-3 transition-colors',
        isOver && 'bg-primary-50 ring-2 ring-primary-300',
      )}
    >
      {children}
    </div>
  )
}

function Column({
  col, rounds, onQuickAdvance, onExportCsv, onAdvanceCard, onRejectCard, onMoveBackCard, auditOpenId, onToggleAudit,
}: {
  col: BoardColumn
  rounds: RoundDef[]
  onQuickAdvance: (col: BoardColumn, mode: 'threshold' | 'topN', value: number) => void
  onExportCsv: () => void
  onAdvanceCard: (card: BoardCard) => void
  onRejectCard: (card: BoardCard) => void
  onMoveBackCard: (card: BoardCard) => void
  auditOpenId: string | null
  onToggleAudit: (id: string) => void
}) {
  return (
    <DroppableColumn col={col}>
      <div className="mb-2 flex items-center justify-between px-1">
        <span className="text-sm font-semibold text-neutral-700">{col.title}</span>
        <span className="text-xs text-neutral-400">{col.cards.length}</span>
      </div>

      {col.kind === 'round' && (
        <QuickAdvanceBar
          round={col.roundIndex !== null ? rounds[col.roundIndex] : undefined}
          onApply={(mode, value) => onQuickAdvance(col, mode, value)}
        />
      )}

      {col.kind === 'selected' && col.cards.length > 0 && (
        <div className="mb-2 px-1">
          <Button size="sm" variant="outline" icon={<Download size={13} />} onClick={onExportCsv}>Export CSV</Button>
        </div>
      )}

      <div className="flex-1 space-y-2">
        {col.cards.length === 0
          ? <div className="flex h-full min-h-[6rem] items-center justify-center rounded-xl border border-dashed border-neutral-200 px-1 text-center text-xs text-neutral-300">Drop here</div>
          : col.cards.map((c) => (
            <Cardlet
              key={c.pipelineCandidateId}
              card={c}
              columnKey={col.key}
              rounds={rounds}
              onAdvance={onAdvanceCard}
              onReject={onRejectCard}
              onMoveBack={onMoveBackCard}
              auditOpen={auditOpenId === c.pipelineCandidateId}
              onToggleAudit={() => onToggleAudit(c.pipelineCandidateId)}
            />
          ))}
      </div>
    </DroppableColumn>
  )
}

/** Progression board for a single pipeline: one column per round plus Selected /
 *  Not-advancing. Advancement happens two ways — drag an advanceable card onto a
 *  valid column, or use the per-card "Advance →" button / a column's quick-advance
 *  criteria bar — and BOTH only open the confirm+preview `AdvanceModal` (Plan 4,
 *  Task 4); nothing here mutates a candidate directly. */
export default function PipelineBoardPage() {
  const { id = '' } = useParams()
  const q = useQuery({ queryKey: ['pipeline-board', id], queryFn: () => pipelinesApi.board(id), enabled: !!id })
  const [modal, setModal] = useState<{ kind: AdvanceModalKind; target: number; targetName: string; cards: BoardCard[] } | null>(null)
  const [activeCard, setActiveCard] = useState<BoardCard | null>(null)
  const [auditOpenId, setAuditOpenId] = useState<string | null>(null)

  const sensors = useSensors(
    useSensor(PointerSensor, { activationConstraint: { distance: 5 } }),
    useSensor(KeyboardSensor),
  )

  // ── Autopilot: drive advancement by voice/typed. These are side-effect actions,
  // so the Autopilot panel reads them back and requires an explicit Confirm before
  // running. They call the SAME pipelinesApi endpoints the board buttons use, and
  // read the live board through a ref (populated after load, below). Registered
  // before the early returns so the hook order is stable (Rules of Hooks). ──────
  const apRef = useRef<{
    id: string
    board: PipelineBoard | null
    advanceTargetFor: ((i: number) => { target: number; name: string }) | null
    refetch: () => void
  }>({ id: '', board: null, advanceTargetFor: null, refetch: () => {} })

  const apAdvance = useCallback(async (candidateIds: string[], target: number, basis: string) => {
    if (candidateIds.length === 0) { toast.error('No matching candidates to advance'); return }
    await pipelinesApi.advance(apRef.current.id, { candidateIds, targetRoundIndex: target, origin: window.location.origin, basis })
    toast.success(`Advanced ${candidateIds.length} candidate${candidateIds.length === 1 ? '' : 's'}`)
    apRef.current.refetch()
  }, [])

  const apActions = useMemo(() => {
    const roundCol = (name: string): BoardColumn | undefined =>
      apRef.current.board?.columns.find((c) => c.kind === 'round' && c.title.toLowerCase() === name.trim().toLowerCase())
    const cardByEmail = (email: string): BoardCard | undefined => {
      const want = email.trim().toLowerCase()
      for (const c of apRef.current.board?.columns ?? []) {
        const hit = c.cards.find((k) => k.candidateEmail.toLowerCase() === want)
        if (hit) return hit
      }
      return undefined
    }
    return {
      advanceByScore: {
        description: 'Advance all completed+scored candidates in a named round whose score is >= a threshold to the next round (or to the Selected list from the final round)',
        sideEffect: true,
        params: [
          { name: 'round', type: 'string' as const, required: true, description: 'the round name, e.g. Screening / Technical / Final' },
          { name: 'minScore', type: 'number' as const, required: true },
        ],
        run: async (args: Record<string, unknown>) => {
          const col = roundCol(String(args.round ?? ''))
          if (!col || col.roundIndex == null) { toast.error(`No round named "${String(args.round)}"`); return }
          const eligible = pickByCriteria(col.cards, 'threshold', Number(args.minScore))
          const t = apRef.current.advanceTargetFor?.(col.roundIndex)
          if (!t) return
          await apAdvance(eligible.map((c) => c.pipelineCandidateId), t.target, `autopilot score>=${String(args.minScore)}`)
        },
      },
      advanceTopN: {
        description: 'Advance the top N scoring completed candidates in a named round to the next round',
        sideEffect: true,
        params: [
          { name: 'round', type: 'string' as const, required: true },
          { name: 'n', type: 'number' as const, required: true },
        ],
        run: async (args: Record<string, unknown>) => {
          const col = roundCol(String(args.round ?? ''))
          if (!col || col.roundIndex == null) { toast.error(`No round named "${String(args.round)}"`); return }
          const eligible = pickByCriteria(col.cards, 'topN', Number(args.n))
          const t = apRef.current.advanceTargetFor?.(col.roundIndex)
          if (!t) return
          await apAdvance(eligible.map((c) => c.pipelineCandidateId), t.target, `autopilot top ${String(args.n)}`)
        },
      },
      advanceCandidate: {
        description: 'Advance one candidate (by email) to the next round; only works once they have completed and been scored in their current round',
        sideEffect: true,
        params: [{ name: 'email', type: 'string' as const, required: true }],
        run: async (args: Record<string, unknown>) => {
          const card = cardByEmail(String(args.email ?? ''))
          if (!card) { toast.error('No candidate with that email on this board'); return }
          if (!card.advanceable) { toast.error(`${card.candidateEmail} is not advanceable yet (round not completed + scored)`); return }
          const t = apRef.current.advanceTargetFor?.(card.currentRoundIndex)
          if (!t) return
          await apAdvance([card.pipelineCandidateId], t.target, 'autopilot single')
        },
      },
      notAdvancing: {
        description: 'Move a candidate (by email) into the Not advancing lane. Does NOT send a rejection email.',
        sideEffect: true,
        params: [{ name: 'email', type: 'string' as const, required: true }],
        run: async (args: Record<string, unknown>) => {
          const card = cardByEmail(String(args.email ?? ''))
          if (!card) { toast.error('No candidate with that email on this board'); return }
          await pipelinesApi.notAdvancing(apRef.current.id, { candidateIds: [card.pipelineCandidateId], sendRejection: false })
          toast.success(`Moved ${card.candidateEmail} to Not advancing`)
          apRef.current.refetch()
        },
      },
      moveBack: {
        description: 'Move a candidate (by email) BACK to their previous round. Only valid while they are in a round past the first and have not completed the current one; deletes their next-round link (the sent email cannot be unsent).',
        sideEffect: true,
        params: [{ name: 'email', type: 'string' as const, required: true }],
        run: async (args: Record<string, unknown>) => {
          const card = cardByEmail(String(args.email ?? ''))
          if (!card) { toast.error('No candidate with that email on this board'); return }
          if (!(card.status === 'in_round' && card.currentRoundIndex > 0 && card.roundStatus !== 'completed')) {
            toast.error(`${card.candidateEmail} can't be moved back from their current round`); return
          }
          await pipelinesApi.moveBack(apRef.current.id, { candidateId: card.pipelineCandidateId })
          toast.success(`Moved ${card.candidateEmail} back a round`)
          apRef.current.refetch()
        },
      },
      exportSelected: {
        description: 'Download the Selected candidates list (name, email, final score) as a CSV file.',
        params: [],
        run: () => {
          const b = apRef.current.board
          const selectedCol = b?.columns.find((c) => c.kind === 'selected')
          const cards = selectedCol?.cards ?? []
          if (cards.length === 0) { toast.error('No selected candidates to export yet'); return }
          const rows = cards.map((c) => [c.candidateName ?? '', c.candidateEmail, c.score ?? ''])
          downloadCsv(`${b?.pipeline.role ?? 'pipeline'}-selected.csv`, ['Name', 'Email', 'Final score'], rows)
        },
      },
    }
  }, [apAdvance])

  const apGetState = useCallback(() => {
    const b = apRef.current.board
    if (!b) return { board: 'loading' }
    return {
      role: b.pipeline.role,
      rounds: b.pipeline.rounds.map((r) => r.name),
      columns: b.columns.map((c) => ({
        column: c.title,
        count: c.cards.length,
        advanceable: c.cards.filter((k) => k.advanceable).map((k) => ({ email: k.candidateEmail, score: k.score })),
      })),
    }
  }, [])
  const apOpts = useMemo(() => ({ getState: apGetState }), [apGetState])
  useAutopilotActions('pipeline', apActions, apOpts)

  if (q.isLoading) {
    return (
      <div className="max-w-[1440px] mx-auto px-6 py-8 space-y-4">
        <Skeleton className="h-5 w-32" />
        <Skeleton className="h-10 w-72" />
        <div className="flex gap-3 overflow-x-auto pb-4">
          {[0, 1, 2].map((i) => <Skeleton key={i} className="h-64 w-72 shrink-0" />)}
        </div>
      </div>
    )
  }

  // Only a hard failure with NO data at all blocks the page (mirrors ReportPage).
  if (!q.data) {
    const reason = q.error instanceof Error ? q.error.message : 'Something went wrong while fetching it.'
    return (
      <div className="max-w-[1440px] mx-auto px-6 py-8">
        <Card className="p-0">
          <div className="flex flex-col items-center gap-3 p-10 text-center">
            <AlertTriangle className="text-warning" size={24} />
            <p className="font-semibold text-neutral-700">Couldn’t load this pipeline</p>
            <p className="text-sm text-neutral-400">{reason}</p>
            <div className="flex items-center gap-3">
              <Button onClick={() => void q.refetch()}>Try again</Button>
              <Link to="/pipelines" className="text-sm font-medium text-primary-700">Back to pipelines</Link>
            </div>
          </div>
        </Card>
      </div>
    )
  }

  const board = q.data
  const roundsLen = board.pipeline.rounds.length

  /** Open the shared confirm modal. `target` is the real numeric round index the
   *  server expects — for the terminal case it's `roundsLen` (>= rounds.length is
   *  how the server itself decides "selected" vs "advance"), never `null`, so the
   *  same code path is correct for both kinds. */
  const openAdvance = (target: number, targetName: string, cards: BoardCard[]) => {
    if (cards.length === 0) return
    setModal({ kind: target >= roundsLen ? 'selected' : 'advance', target, targetName, cards })
  }
  const openRejection = (cards: BoardCard[]) => {
    if (cards.length === 0) return
    setModal({ kind: 'rejection', target: 0, targetName: 'Not advancing', cards })
  }
  const advanceTargetFor = (fromRoundIndex: number): { target: number; name: string } => {
    const next = fromRoundIndex + 1
    return next >= roundsLen ? { target: roundsLen, name: 'Selected' } : { target: next, name: board.pipeline.rounds[next].name }
  }
  // Publish the live board + helpers so the Autopilot actions (registered above) act on current data.
  apRef.current = { id, board, advanceTargetFor, refetch: () => void q.refetch() }

  const onDragStart = (e: DragStartEvent) => {
    const data = e.active.data.current as { card: BoardCard } | undefined
    setActiveCard(data?.card ?? null)
  }
  const onDragEnd = (e: DragEndEvent) => {
    setActiveCard(null)
    const { active, over } = e
    if (!over) return
    const data = active.data.current as { card: BoardCard; columnKey: string } | undefined
    if (!data) return
    const targetKey = String(over.id)
    if (targetKey === data.columnKey) return
    const targetCol = board.columns.find((c) => c.key === targetKey)
    if (!targetCol) return
    const { card } = data
    const nextRoundIndex = card.currentRoundIndex + 1

    // Valid drop targets only: the immediate next round; Selected but only from the
    // LAST round; or Not-advancing. Anything else (skipping a round, dropping back
    // onto an earlier round, Selected from a non-final round) is a no-op + toast.
    if (targetCol.kind === 'round' && targetCol.roundIndex === nextRoundIndex) {
      openAdvance(nextRoundIndex, targetCol.title, [card])
    } else if (targetCol.kind === 'selected' && nextRoundIndex >= roundsLen) {
      openAdvance(roundsLen, 'Selected', [card])
    } else if (targetCol.kind === 'not_advancing') {
      openRejection([card])
    } else {
      toast.error('Can only advance to the next round')
    }
  }

  const handleQuickAdvance = (col: BoardColumn, mode: 'threshold' | 'topN', value: number) => {
    const eligible = pickByCriteria(col.cards, mode, value)
    if (eligible.length === 0) {
      toast.error('No candidates in this round meet that criteria')
      return
    }
    const { target, name } = advanceTargetFor(col.roundIndex ?? 0)
    openAdvance(target, name, eligible)
  }

  const handleAdvanceCard = (card: BoardCard) => {
    const { target, name } = advanceTargetFor(card.currentRoundIndex)
    openAdvance(target, name, [card])
  }

  const handleExportCsv = () => {
    const selectedCol = board.columns.find((c) => c.kind === 'selected')
    const rows = (selectedCol?.cards ?? []).map((c) => [c.candidateName ?? '', c.candidateEmail, c.score ?? ''])
    downloadCsv(`${board.pipeline.role}-selected.csv`, ['Name', 'Email', 'Final score'], rows)
  }

  const handleMoveBack = async (card: BoardCard) => {
    if (!confirm('Move this candidate back to the previous round? This deletes their next-round link; the email can’t be unsent.')) return
    try {
      await pipelinesApi.moveBack(id, { candidateId: card.pipelineCandidateId })
      toast.success('Moved back to the previous round')
      void q.refetch()
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Failed to move back')
    }
  }

  return (
    <div className="max-w-[1440px] mx-auto px-6 py-8">
      <Link to="/pipelines" className="mb-3 inline-flex items-center gap-1.5 text-sm font-medium text-neutral-500 hover:text-neutral-800">
        <ArrowLeft size={15} /> Pipelines
      </Link>
      <PageHeader
        kicker="Pipeline Board"
        title={board.pipeline.role}
        description={`${roundsLen} round${roundsLen === 1 ? '' : 's'} · candidate progression · drag an advanceable card, or use Advance / the quick-advance bar`}
      />

      <DndContext sensors={sensors} collisionDetection={boardCollision} onDragStart={onDragStart} onDragEnd={onDragEnd}>
        <div className="flex gap-3 overflow-x-auto pb-4">
          {board.columns.map((col) => (
            <Column
              key={col.key}
              col={col}
              rounds={board.pipeline.rounds}
              onQuickAdvance={handleQuickAdvance}
              onExportCsv={handleExportCsv}
              onAdvanceCard={handleAdvanceCard}
              onRejectCard={(card) => openRejection([card])}
              onMoveBackCard={(card) => void handleMoveBack(card)}
              auditOpenId={auditOpenId}
              onToggleAudit={(pcId) => setAuditOpenId((cur) => (cur === pcId ? null : pcId))}
            />
          ))}
        </div>
        <DragOverlay>
          {activeCard ? (
            <div className="card w-72 p-3 opacity-90 shadow-xl ring-2 ring-primary-400">
              <div className="truncate text-sm font-medium text-neutral-800">{activeCard.candidateName || activeCard.candidateEmail}</div>
              <div className="truncate text-xs text-neutral-400">{activeCard.candidateEmail}</div>
            </div>
          ) : null}
        </DragOverlay>
      </DndContext>

      {modal && (
        <AdvanceModal
          open={!!modal}
          onClose={() => setModal(null)}
          pipelineId={id}
          kind={modal.kind}
          targetRoundIndex={modal.target}
          targetRoundName={modal.targetName}
          candidates={modal.cards}
          onDone={() => void q.refetch()}
        />
      )}
    </div>
  )
}
