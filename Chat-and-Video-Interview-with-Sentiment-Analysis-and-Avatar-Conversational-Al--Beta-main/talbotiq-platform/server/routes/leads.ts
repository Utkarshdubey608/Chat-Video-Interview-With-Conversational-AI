import { Router } from 'express'
import { z } from 'zod'
import { randomUUID } from 'node:crypto'
import { db, type MarketingLead } from '../store/db'

/**
 * PUBLIC lead capture for the Mimic marketing site's "Book a demo" form.
 * Deliberately unauthenticated (visitors are pre-login) and server-side only —
 * it writes to the Express store, NOT Firestore, so no Firebase security-rule
 * change is ever required. Additive: touches nothing else.
 */
export const leadsRouter = Router()

const LeadSchema = z.object({
  firstName: z.string().trim().min(1).max(120),
  lastName: z.string().trim().min(1).max(120),
  email: z.string().trim().email().max(200),
  hiresPerYear: z.string().trim().min(1).max(120),
  source: z.string().trim().max(120).optional(),
})

/** Pure: coerce a validated body into a stored lead. Exported for unit tests. */
export function buildLead(
  body: z.infer<typeof LeadSchema>,
  id: string,
  now: string,
): MarketingLead {
  return {
    id,
    firstName: body.firstName.trim(),
    lastName: body.lastName.trim(),
    email: body.email.trim().toLowerCase(),
    hiresPerYear: body.hiresPerYear.trim(),
    source: (body.source ?? 'mimic-site').trim() || 'mimic-site',
    createdAt: now,
  }
}

leadsRouter.post('/', (req, res) => {
  const parsed = LeadSchema.safeParse(req.body)
  if (!parsed.success) {
    res.status(400).json({ error: 'Please fill in your name, a valid work email, and hires per year.' })
    return
  }
  const lead = buildLead(parsed.data, randomUUID(), new Date().toISOString())
  db.leads.push(lead)
  db.scheduleSave()
  console.log(`[leads] new demo request: ${lead.email} (${lead.hiresPerYear}/yr)`)
  res.status(201).json({ ok: true })
})
