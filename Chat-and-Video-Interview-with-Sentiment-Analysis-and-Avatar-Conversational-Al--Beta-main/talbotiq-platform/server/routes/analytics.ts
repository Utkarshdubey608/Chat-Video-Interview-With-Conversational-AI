import { Router } from 'express'
import { computeAnalytics } from '../services/analytics'
import { requireAuth } from '../middleware/auth'
import type { AnalyticsFilters, TrackType } from '../../shared/types'

export const analyticsRouter = Router()

const TRACKS: TrackType[] = ['chat', 'chatbot', 'video_avatar', 'voice', 'video', 'two_way']
const str = (v: unknown) => (typeof v === 'string' && v.trim() ? v.trim() : undefined)

// GET /api/analytics — real aggregates over stored ResultReports. All filters
// optional. No matches → zeros + empty arrays (never fabricated data). Scoped to
// the requesting recruiter's own sessions; admins see the whole tenant.
analyticsRouter.get('/', (req, res) => {
  const auth = requireAuth(req)
  const q = req.query
  const track = str(q.track)
  const filters: AnalyticsFilters = {
    track: track && (TRACKS as string[]).includes(track) ? (track as TrackType) : undefined,
    templateId: str(q.templateId),
    role: str(q.role),
    dateFrom: str(q.dateFrom),
    dateTo: str(q.dateTo),
  }
  const ownerId = auth.admin ? undefined : auth.uid
  res.json(computeAnalytics(filters, undefined, ownerId))
})
