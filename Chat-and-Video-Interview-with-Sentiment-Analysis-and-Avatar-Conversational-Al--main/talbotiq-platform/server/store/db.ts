import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import type {
  InterviewTemplate,
  QuestionSet,
  InterviewSession,
  ResultReport,
} from '../../shared/types'
import { seedData } from './seed'

const here = path.dirname(fileURLToPath(import.meta.url))
const DATA_DIR = path.join(here, '..', 'data')
const DATA_FILE = path.join(DATA_DIR, 'db.json')

export interface AppSettings {
  geminiApiKey?: string
  geminiModel?: string
}

interface Snapshot {
  templates: InterviewTemplate[]
  questionSets: QuestionSet[]
  sessions: InterviewSession[]
  reports: ResultReport[]
  settings?: AppSettings
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
        settings: this.settings,
      }
      fs.writeFileSync(DATA_FILE, JSON.stringify(snap, null, 2))
    } catch (err) {
      console.error('[db] save failed:', err)
    }
  }
}

export const db = new Database()
