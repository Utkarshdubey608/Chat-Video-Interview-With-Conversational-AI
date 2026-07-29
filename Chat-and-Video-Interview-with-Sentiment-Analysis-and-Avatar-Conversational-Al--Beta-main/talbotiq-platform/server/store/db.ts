import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import type {
  InterviewTemplate,
  QuestionSet,
  InterviewSession,
  ResultReport,
  AppUser,
  AvatarInterviewSettings,
  InviteEmailTemplate,
  Pipeline,
  PipelineCandidate,
} from '../../shared/types'
import { seedData } from './seed'

const here = path.dirname(fileURLToPath(import.meta.url))
const DATA_DIR = path.join(here, '..', 'data')
const DATA_FILE = path.join(DATA_DIR, 'db.json')

/** A demo-request lead captured from the public Mimic marketing site. Server-side
 *  only (Express store) — deliberately NOT a Firestore collection, so the public
 *  form never needs a Firestore security-rule change. */
export interface MarketingLead {
  id: string
  firstName: string
  lastName: string
  email: string
  hiresPerYear: string
  source: string
  createdAt: string
}

export interface AppSettings {
  geminiApiKey?: string
  geminiModel?: string
  /** GLOBAL Tavus key — the single source of truth, synced from the Settings
   *  page. Takes precedence everywhere; saving it also updates avatar.tavusKey
   *  so every stored copy agrees and a key change applies everywhere at once. */
  tavusApiKey?: string
  /** Recruiter-applied Video Avatar config ("Apply to Candidate Interviews" on
   *  the Setup page). The Tavus key is SERVER-held — never sent to candidates. */
  avatar?: AvatarInterviewSettings & { tavusKey?: string; updatedAt?: string }
}

interface Snapshot {
  templates: InterviewTemplate[]
  questionSets: QuestionSet[]
  sessions: InterviewSession[]
  reports: ResultReport[]
  users?: AppUser[]
  settings?: AppSettings
  inviteEmailTemplates?: InviteEmailTemplate[]
  pipelines?: Pipeline[]
  pipelineCandidates?: PipelineCandidate[]
  leads?: MarketingLead[]
}

/**
 * Tiny in-memory store with debounced JSON-file persistence. Not a production
 * database — durable enough that templates/sets/sessions survive a restart,
 * which is all this build needs.
 */
class Database {
  templates = new Map<string, InterviewTemplate>()
  questionSets = new Map<string, QuestionSet>()
  sessions = new Map<string, InterviewSession>()
  reports = new Map<string, ResultReport>()
  users = new Map<string, AppUser>()   // keyed by Firebase uid
  inviteEmailTemplates = new Map<string, InviteEmailTemplate>() // owned per recruiter
  pipelines = new Map<string, Pipeline>()                     // owned per recruiter
  pipelineCandidates = new Map<string, PipelineCandidate>()   // owned per recruiter
  leads: MarketingLead[] = []                                 // public marketing demo requests
  settings: AppSettings = {}

  private timer: ReturnType<typeof setTimeout> | null = null

  init() {
    try {
      if (fs.existsSync(DATA_FILE)) {
        const snap = JSON.parse(fs.readFileSync(DATA_FILE, 'utf8')) as Snapshot
        snap.templates?.forEach((t) => this.templates.set(t.id, t))
        snap.questionSets?.forEach((s) => this.questionSets.set(s.id, s))
        snap.sessions?.forEach((s) => this.sessions.set(s.id, s))
        snap.reports?.forEach((r) => this.reports.set(r.sessionId, r))
        snap.users?.forEach((u) => this.users.set(u.uid, u))
        snap.inviteEmailTemplates?.forEach((t) => this.inviteEmailTemplates.set(t.id, t))
        snap.pipelines?.forEach((p) => this.pipelines.set(p.id, p))
        snap.pipelineCandidates?.forEach((c) => this.pipelineCandidates.set(c.id, c))
        if (snap.leads) this.leads = snap.leads
        if (snap.settings) this.settings = snap.settings
      }
    } catch (err) {
      console.error('[db] failed to load snapshot, starting fresh:', err)
    }

    if (this.templates.size === 0 && this.questionSets.size === 0) {
      const seed = seedData()
      seed.templates.forEach((t) => this.templates.set(t.id, t))
      seed.questionSets.forEach((s) => this.questionSets.set(s.id, s))
      this.scheduleSave()
      console.log('[db] seeded default template + question sets')
    }
  }

  /** Debounced persist — call after any mutation. */
  scheduleSave() {
    if (this.timer) clearTimeout(this.timer)
    this.timer = setTimeout(() => this.saveNow(), 400)
  }

  saveNow() {
    try {
      fs.mkdirSync(DATA_DIR, { recursive: true })
      const snap: Snapshot = {
        templates: [...this.templates.values()],
        questionSets: [...this.questionSets.values()],
        sessions: [...this.sessions.values()],
        reports: [...this.reports.values()],
        users: [...this.users.values()],
        inviteEmailTemplates: [...this.inviteEmailTemplates.values()],
        pipelines: [...this.pipelines.values()],
        pipelineCandidates: [...this.pipelineCandidates.values()],
        leads: this.leads,
        settings: this.settings,
      }
      fs.writeFileSync(DATA_FILE, JSON.stringify(snap, null, 2))
    } catch (err) {
      console.error('[db] save failed:', err)
    }
  }
}

export const db = new Database()
