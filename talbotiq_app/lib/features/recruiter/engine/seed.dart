// lib/features/recruiter/engine/seed.dart
//
// Pure-Dart port of talbotiq-platform `server/store/seed.ts`. Populates the
// RecruiterStore on first run so the UI is not empty.

import '../models/recruiter_models.dart';
import 'defaults.dart';

class SeedData {
  final List<InterviewTemplate> templates;
  final List<QuestionSet> questionSets;
  const SeedData({required this.templates, required this.questionSets});
}

FixedQuestion _q(String text, String category, [String? idealAnswerNotes]) =>
    FixedQuestion(
      id: recruiterId('q'),
      text: text,
      category: category,
      idealAnswerNotes: idealAnswerNotes,
    );

/// Initial templates + question sets so the UI is populated on first run.
SeedData seedData() {
  final now = DateTime.now().toIso8601String();

  final set1 = QuestionSet(
    id: recruiterId('set'),
    name: 'Set 1 — General Behavioral',
    createdAt: now,
    updatedAt: now,
    questions: [
      _q('Tell me about yourself and what drew you to this role.', 'Intro',
          'Looks for a concise, relevant narrative tying background to the role.'),
      _q('Describe a challenging problem you solved recently. What was your approach?',
          'Behavioral',
          'STAR structure; clear problem, concrete actions, measurable result.'),
      _q('Tell me about a time you disagreed with a teammate. How did you handle it?',
          'Behavioral',
          'Looks for empathy, communication, and a constructive resolution.'),
      _q('How do you handle pressure and competing deadlines?', 'Behavioral',
          'Prioritization, calm under pressure, concrete tactics.'),
      _q('Where do you see yourself in three years?', 'Motivation',
          'Ambition aligned with the role and growth mindset.'),
    ],
  );

  final set2 = QuestionSet(
    id: recruiterId('set'),
    name: 'Set 2 — Software Engineering',
    createdAt: now,
    updatedAt: now,
    questions: [
      _q('Walk me through how you would design a URL shortener.', 'System Design',
          'Hashing/encoding, storage, scaling, collisions, read/write ratio.'),
      _q('Explain the difference between a process and a thread.', 'Fundamentals',
          'Memory isolation, scheduling, shared state, trade-offs.'),
      _q('How do you ensure code quality in a team setting?', 'Practices',
          'Reviews, tests, CI, linting, ownership, documentation.'),
      _q('Describe a performance issue you diagnosed and fixed.', 'Debugging',
          'Measurement first, root cause, the fix, and verification.'),
      _q('How would you decide between SQL and NoSQL for a new service?', 'Data',
          'Access patterns, consistency, scale, schema flexibility.'),
    ],
  );

  final set3 = QuestionSet(
    id: recruiterId('set'),
    name: 'Set 3 — Leadership & Ownership',
    createdAt: now,
    updatedAt: now,
    questions: [
      _q('Tell me about a time you led a project from start to finish.',
          'Leadership', 'Ownership, planning, delegation, outcome.'),
      _q('How do you give difficult feedback to a peer?', 'Communication',
          'Directness with empathy; specific, actionable, kind.'),
      _q('Describe a decision you made with incomplete information.', 'Judgment',
          'Framing trade-offs, managing risk, learning afterward.'),
      _q('How do you keep a team motivated through a tough stretch?',
          'Leadership', 'Empathy, transparency, small wins, recognition.'),
    ],
  );

  final template = InterviewTemplate(
    id: recruiterId('tpl'),
    name: 'Software Engineer — Screen',
    role: 'Software Engineer',
    seniority: 'Mid',
    track: TrackType.chat,
    questionSource: QuestionSource.fixed,
    fixedQuestionSetId: set1.id,
    timing: defaultTiming(),
    rubric: defaultRubric(),
    integrity: defaultIntegrity(),
    branding: defaultBranding(),
    createdAt: now,
    updatedAt: now,
  );

  // A conversational (chatbot) template so the track is demoable out of the box.
  final convTemplate = InterviewTemplate(
    id: recruiterId('tpl'),
    name: 'Behavioral — Conversational',
    role: 'Software Engineer',
    seniority: 'Mid',
    track: TrackType.chatbot,
    questionSource: QuestionSource.fixed,
    fixedQuestionSetId: set1.id,
    timing: defaultTiming(),
    rubric: defaultRubric(),
    integrity: defaultIntegrity(),
    branding: defaultBranding(),
    mode: InterviewMode.conversational,
    conversationTiming: defaultConversationTiming(),
    createdAt: now,
    updatedAt: now,
  );

  return SeedData(
      templates: [template, convTemplate],
      questionSets: [set1, set2, set3]);
}
