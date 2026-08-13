import { randomUUID } from 'node:crypto'
import type { SessionQuestion, Turn } from '../../shared/types'

/**
 * Build the (interviewer question, candidate answer) transcript turns for a
 * submitted Video Interview answer. The live transcript IS the answer — no video
 * is stored — and mirroring it into `session.transcript` lets scoring and results
 * run the same conversation path as the Voice interview. Pure (unit-tested).
 */
export function buildVideoTranscript(q: SessionQuestion, questionIndex: number, nowIso: string): Turn[] {
  return [
    { id: randomUUID(), role: 'interviewer', content: q.text, turnType: 'question', questionIndex, createdAt: nowIso },
    { id: randomUUID(), role: 'candidate', content: q.answerText ?? '', questionIndex, createdAt: nowIso },
  ]
}
