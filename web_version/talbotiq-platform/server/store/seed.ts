import { randomUUID } from 'node:crypto'
import type { InterviewTemplate, QuestionSet, FixedQuestion } from '../../shared/types'
import {
  DEFAULT_TIMING,
  DEFAULT_INTEGRITY,
  DEFAULT_BRANDING,
  defaultRubric,
} from './defaults'

const q = (text: string, category: string, idealAnswerNotes?: string): FixedQuestion => ({
  id: randomUUID(),
  text,
  category,
  idealAnswerNotes,
})

/** Initial templates + question sets so the UI is populated on first run. */
export function seedData(): { templates: InterviewTemplate[]; questionSets: QuestionSet[] } {
  const now = new Date().toISOString()

  const set1: QuestionSet = {
    id: randomUUID(),
    name: 'Set 1 — General Behavioral',
    createdAt: now,
    updatedAt: now,
    questions: [
      q('Tell me about yourself and what drew you to this role.', 'Intro', 'Looks for a concise, relevant narrative tying background to the role.'),
      q('Describe a challenging problem you solved recently. What was your approach?', 'Behavioral', 'STAR structure; clear problem, concrete actions, measurable result.'),
      q('Tell me about a time you disagreed with a teammate. How did you handle it?', 'Behavioral', 'Looks for empathy, communication, and a constructive resolution.'),
      q('How do you handle pressure and competing deadlines?', 'Behavioral', 'Prioritization, calm under pressure, concrete tactics.'),
      q('Where do you see yourself in three years?', 'Motivation', 'Ambition aligned with the role and growth mindset.'),
    ],
  }

  const set2: QuestionSet = {
    id: randomUUID(),
    name: 'Set 2 — Software Engineering',
    createdAt: now,
    updatedAt: now,
    questions: [
      q('Walk me through how you would design a URL shortener.', 'System Design', 'Hashing/encoding, storage, scaling, collisions, read/write ratio.'),
      q('Explain the difference between a process and a thread.', 'Fundamentals', 'Memory isolation, scheduling, shared state, trade-offs.'),
      q('How do you ensure code quality in a team setting?', 'Practices', 'Reviews, tests, CI, linting, ownership, documentation.'),
      q('Describe a performance issue you diagnosed and fixed.', 'Debugging', 'Measurement first, root cause, the fix, and verification.'),
      q('How would you decide between SQL and NoSQL for a new service?', 'Data', 'Access patterns, consistency, scale, schema flexibility.'),
    ],
  }

  const set3: QuestionSet = {
    id: randomUUID(),
    name: 'Set 3 — Leadership & Ownership',
    createdAt: now,
    updatedAt: now,
    questions: [
      q('Tell me about a time you led a project from start to finish.', 'Leadership', 'Ownership, planning, delegation, outcome.'),
      q('How do you give difficult feedback to a peer?', 'Communication', 'Directness with empathy; specific, actionable, kind.'),
      q('Describe a decision you made with incomplete information.', 'Judgment', 'Framing trade-offs, managing risk, learning afterward.'),
      q('How do you keep a team motivated through a tough stretch?', 'Leadership', 'Empathy, transparency, small wins, recognition.'),
    ],
  }

  const template: InterviewTemplate = {
    id: randomUUID(),
    name: 'Software Engineer — Screen',
    role: 'Software Engineer',
    seniority: 'Mid',
    track: 'chat',
    questionSource: 'fixed',
    fixedQuestionSetId: set1.id,
    timing: { ...DEFAULT_TIMING },
    rubric: defaultRubric(),
    integrity: { ...DEFAULT_INTEGRITY },
    branding: { ...DEFAULT_BRANDING },
    createdAt: now,
    updatedAt: now,
  }

  return { templates: [template], questionSets: [set1, set2, set3] }
}
