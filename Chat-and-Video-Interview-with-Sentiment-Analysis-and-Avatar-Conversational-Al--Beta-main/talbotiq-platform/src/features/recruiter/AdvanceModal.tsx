import { useEffect, useMemo, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import toast from 'react-hot-toast'
import { Badge, Button, Input, Modal, Toggle } from '@/components/ui'
import { RichTextEditor } from './invite-email/RichTextEditor'
import { TransitionEmailPreview, type TransitionEmailKind } from './TransitionEmailPreview'
import { inviteEmailTemplatesApi, pipelinesApi } from '@/lib/api'
import { defaultTemplateFor, validateLockedTokens } from '@shared/inviteEmail'
import type { AdvanceResult, BoardCard, InviteEmailTemplate } from '@shared/types'

/** The three board transitions this modal drives — the invite (round-1) flow has its own wizard. */
export type AdvanceModalKind = TransitionEmailKind

interface AdvanceModalProps {
  open: boolean
  onClose: () => void
  pipelineId: string
  kind: AdvanceModalKind
  /** Destination round for 'advance'; ignored for 'selected'/'rejection'. */
  targetRoundIndex: number | null
  /** Display name of the destination (round name, "Selected", or "Not advancing"). */
  targetRoundName: string
  /** The recipients being moved. */
  candidates: BoardCard[]
  onDone: () => void
}

const KIND_TITLE: Record<AdvanceModalKind, (n: number, round: string) => string> = {
  advance: (n, round) => `Advance ${n} candidate${n === 1 ? '' : 's'} to ${round}`,
  selected: (n) => `Select ${n} candidate${n === 1 ? '' : 's'}`,
  rejection: (n) => `Move ${n} candidate${n === 1 ? '' : 's'} to Not advancing`,
}

function seedDraft(kind: AdvanceModalKind): InviteEmailTemplate {
  return { ...defaultTemplateFor(kind), id: 'draft', recruiterId: '', createdAt: '', updatedAt: '' } as InviteEmailTemplate
}

/**
 * Confirm+preview modal for a pipeline-board transition (advance / selected /
 * rejection). Loads the recruiter's default template for `kind`, lets them edit the
 * subject/body and see a live preview — via the SAME `renderTransitionEmail` the
 * server uses to send, so what's previewed is exactly what goes out — lists the
 * recipients being moved, and only reaches the server once Confirm is pressed:
 * `pipelinesApi.advance` for advance/selected, `pipelinesApi.notAdvancing` for
 * rejection. The rejection email itself is OPT-IN and off by default — a recruiter
 * can move candidates to "Not advancing" without emailing them at all.
 */
export function AdvanceModal({
  open, onClose, pipelineId, kind, targetRoundIndex, targetRoundName, candidates, onDone,
}: AdvanceModalProps) {
  const qc = useQueryClient()
  const [draft, setDraft] = useState<InviteEmailTemplate | null>(null)
  const [sending, setSending] = useState(false)
  const [rejectOptIn, setRejectOptIn] = useState(false)
  const [results, setResults] = useState<AdvanceResult['results'] | null>(null)

  // (Re)load the recruiter's default template for this kind each time the modal opens.
  useEffect(() => {
    if (!open) return
    setDraft(null)
    setRejectOptIn(false)
    setResults(null)
    let cancelled = false
    inviteEmailTemplatesApi.list(kind)
      .then((list) => {
        if (cancelled) return
        const seed = list.find((t) => t.isDefault) ?? list[0]
        setDraft(seed ?? seedDraft(kind))
      })
      .catch(() => { if (!cancelled) setDraft(seedDraft(kind)) })
    return () => { cancelled = true }
  }, [open, kind])

  // advance requires the locked {{interview_link}} token; selected/rejection require
  // none (see requiredTokensFor), so `locked.ok` is always true for those two kinds.
  const locked = useMemo(
    () => (draft ? validateLockedTokens(draft.subject, draft.bodyHtml, kind) : { ok: true, missing: [] as string[] }),
    [draft, kind],
  )

  const sampleCandidate = candidates[0]
  const sampleVars = {
    candidate_name: sampleCandidate?.candidateName || sampleCandidate?.candidateEmail.split('@')[0] || 'there',
    role: '',
    recruiter_name: draft?.sender.fromName || 'TalbotIQ',
    company: draft?.branding.companyName || 'TalbotIQ',
    round_name: targetRoundName,
    score: sampleCandidate?.score != null ? String(sampleCandidate.score) : '',
  }

  // The email-editing UI (subject/body/preview) is always shown for advance/selected;
  // for rejection it only appears once the recruiter opts in (off by default).
  const showEmailEditor = kind !== 'rejection' || rejectOptIn
  const confirmDisabled = !draft || sending || (showEmailEditor && !locked.ok)
  const confirmLabel = kind === 'rejection' && !rejectOptIn ? 'Move without emailing' : 'Confirm & send'

  const confirm = async () => {
    if (!draft || confirmDisabled) return
    setSending(true)
    try {
      const ids = candidates.map((c) => c.pipelineCandidateId)
      const emailConfig: Partial<InviteEmailTemplate> = {
        name: draft.name, kind, sender: draft.sender, subject: draft.subject,
        bodyHtml: draft.bodyHtml, cta: draft.cta, branding: draft.branding,
      }
      const res: AdvanceResult = kind === 'rejection'
        ? await pipelinesApi.notAdvancing(pipelineId, { candidateIds: ids, sendRejection: rejectOptIn, emailConfig })
        : await pipelinesApi.advance(pipelineId, {
            candidateIds: ids,
            targetRoundIndex: targetRoundIndex ?? 0,
            emailConfig,
            origin: window.location.origin,
            basis: 'confirm-modal',
          })

      setResults(res.results)
      qc.invalidateQueries({ queryKey: ['pipeline-board', pipelineId] })
      onDone()

      const failed = res.results.filter((r) => r.error).length
      if (failed > 0) {
        toast.error(`${failed} of ${res.results.length} email${res.results.length === 1 ? '' : 's'} failed to send`)
      } else {
        toast.success(kind === 'selected' ? 'Marked as selected' : kind === 'rejection' ? 'Moved to Not advancing' : `Advanced to ${targetRoundName}`)
      }
    } catch (e) {
      toast.error(e instanceof Error ? e.message : 'Failed to send')
    } finally {
      setSending(false)
    }
  }

  const title = KIND_TITLE[kind](candidates.length, targetRoundName)

  return (
    <Modal open={open} onClose={onClose} title={title} width="max-w-3xl">
      {!draft ? (
        <p className="text-sm text-neutral-400">Loading email template…</p>
      ) : results ? (
        <div className="space-y-4">
          <div className="text-sm font-semibold text-neutral-700">Results</div>
          {results.some((r) => r.error) && (
            // The candidates WERE moved server-side; only email delivery failed.
            // Say so explicitly so a mail-server rejection doesn't look like the
            // whole action failed (and can't be un-done by mistake).
            <p className="text-xs text-neutral-500">
              Candidates were moved successfully. Some emails didn’t send — the reason is shown per recipient (this is a mail-server/Brevo delivery issue, not the advancement).
            </p>
          )}
          <div className="max-h-64 space-y-2 overflow-auto rounded-lg border border-border p-2 text-sm">
            {results.map((r) => (
              <div key={r.pipelineCandidateId} className="flex flex-col gap-0.5 border-b border-border/60 pb-2 last:border-0 last:pb-0">
                <div className="flex items-center justify-between gap-3">
                  <span className="truncate text-neutral-700">{r.email}</span>
                  {r.sent
                    ? <Badge variant="success">Email sent</Badge>
                    : r.error
                      ? <Badge variant="warning">Moved · email failed</Badge>
                      : <Badge variant="neutral">Moved</Badge>}
                </div>
                {r.error && <div className="break-words text-xs text-neutral-400">{r.error}</div>}
              </div>
            ))}
          </div>
          <div className="flex justify-end">
            <Button onClick={onClose}>Close</Button>
          </div>
        </div>
      ) : (
        <div className="space-y-4">
          <div>
            <div className="mb-1 text-sm font-semibold text-neutral-700">Recipients ({candidates.length})</div>
            <div className="max-h-24 overflow-auto rounded-lg border border-border p-2 text-sm">
              {candidates.map((c) => (
                <div key={c.pipelineCandidateId} className="truncate text-neutral-700">
                  {c.candidateName ? `${c.candidateName} · ${c.candidateEmail}` : c.candidateEmail}
                  {c.score != null ? ` · score ${c.score}` : ''}
                </div>
              ))}
            </div>
          </div>

          {kind === 'rejection' && (
            <Toggle
              checked={rejectOptIn}
              onChange={setRejectOptIn}
              label="Send a rejection email"
              description="Off by default — candidates can be moved to Not advancing silently."
            />
          )}

          {showEmailEditor && (
            <>
              <Input
                label="Subject"
                value={draft.subject}
                onChange={(e) => setDraft({ ...draft, subject: e.target.value })}
              />
              <div>
                <div className="mb-1 text-sm font-semibold text-neutral-700">Body</div>
                <RichTextEditor value={draft.bodyHtml} onChange={(html) => setDraft({ ...draft, bodyHtml: html })} />
              </div>
              {!locked.ok && (
                <Badge variant="warning">
                  Missing required link — insert {'{{interview_link}}'} so the candidate can reach their next round
                </Badge>
              )}
              <div>
                <div className="mb-1 text-sm font-semibold text-neutral-700">Preview</div>
                <TransitionEmailPreview draft={draft} kind={kind} vars={sampleVars} origin={window.location.origin} />
              </div>
            </>
          )}

          <div className="flex justify-end gap-2 border-t border-border pt-4">
            <Button variant="ghost" onClick={onClose}>Cancel</Button>
            <Button loading={sending} disabled={confirmDisabled} onClick={() => void confirm()}>{confirmLabel}</Button>
          </div>
        </div>
      )}
    </Modal>
  )
}
