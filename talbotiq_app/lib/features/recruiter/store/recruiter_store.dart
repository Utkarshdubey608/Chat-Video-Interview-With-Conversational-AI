// lib/features/recruiter/store/recruiter_store.dart
//
// State for the native recruiter module. Deliberately SEPARATE from AppStore
// (the protected video-interview module): it uses its own SharedPreferences
// key so a bug here can never corrupt the video-flow blob, and recruiter
// changes never rebuild video-flow listeners. Mirrors AppStore's
// load-once / save-blob / notifyListeners persistence pattern.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recruiter_models.dart';
import '../engine/seed.dart';

/// Which feature occupies the first tab slot (formerly "Setup").
enum FeatureSlot { videoInterview, recruiter }

class RecruiterStore extends ChangeNotifier {
  static const String _kStoreKey = 'talbotiq_recruiter_store';

  List<InterviewTemplate> _templates = [];
  List<QuestionSet> _questionSets = [];
  List<InterviewSession> _sessions = [];
  final Map<String, ResultReport> _reports = {};

  FeatureSlot _slot0Feature = FeatureSlot.videoInterview;

  // Which recruiter bottom tab is selected (0=Sessions,1=Templates,
  // 2=Question Sets,3=Settings). Transient — restart reopens at the home tab.
  int _recruiterTabIndex = 0;

  Future<void>? _loadFuture;
  bool _loaded = false;

  // Persisted one-time flag: true once starter content has ever been seeded.
  // Prevents re-seeding after the recruiter intentionally deletes everything.
  bool _hasSeeded = false;

  // ── Getters ───────────────────────────────────────────────────────────────
  List<InterviewTemplate> get templates => List.unmodifiable(_templates);
  List<QuestionSet> get questionSets => List.unmodifiable(_questionSets);
  List<InterviewSession> get sessions => List.unmodifiable(_sessions);
  FeatureSlot get slot0Feature => _slot0Feature;
  int get recruiterTabIndex => _recruiterTabIndex;
  bool get loaded => _loaded;

  InterviewTemplate? templateById(String id) {
    for (final t in _templates) {
      if (t.id == id) return t;
    }
    return null;
  }

  QuestionSet? questionSetById(String id) {
    for (final s in _questionSets) {
      if (s.id == id) return s;
    }
    return null;
  }

  InterviewSession? sessionById(String id) {
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return null;
  }

  ResultReport? reportFor(String sessionId) => _reports[sessionId];

  Future<void> load() {
    _loadFuture ??= _loadFromPrefs();
    return _loadFuture!;
  }

  // ── Feature slot ────────────────────────────────────────────────────────
  void setSlot0Feature(FeatureSlot slot) {
    if (_slot0Feature == slot) return;
    _slot0Feature = slot;
    _saveToPrefs();
    notifyListeners();
  }

  void setRecruiterTabIndex(int index) {
    if (_recruiterTabIndex == index) return;
    _recruiterTabIndex = index;
    notifyListeners(); // transient — not persisted
  }

  // ── Templates ─────────────────────────────────────────────────────────────
  void upsertTemplate(InterviewTemplate template) {
    final idx = _templates.indexWhere((t) => t.id == template.id);
    if (idx >= 0) {
      _templates[idx] = template;
    } else {
      _templates.insert(0, template);
    }
    _saveToPrefs();
    notifyListeners();
  }

  void deleteTemplate(String id) {
    _templates.removeWhere((t) => t.id == id);
    _saveToPrefs();
    notifyListeners();
  }

  // ── Question sets ─────────────────────────────────────────────────────────
  void upsertQuestionSet(QuestionSet set) {
    final idx = _questionSets.indexWhere((s) => s.id == set.id);
    if (idx >= 0) {
      _questionSets[idx] = set;
    } else {
      _questionSets.insert(0, set);
    }
    _saveToPrefs();
    notifyListeners();
  }

  void deleteQuestionSet(String id) {
    _questionSets.removeWhere((s) => s.id == id);
    _saveToPrefs();
    notifyListeners();
  }

  QuestionSet duplicateQuestionSet(String id) {
    final orig = questionSetById(id);
    final now = DateTime.now().toIso8601String();
    final copy = QuestionSet(
      id: recruiterId('set'),
      name: '${orig?.name ?? 'Question set'} (copy)',
      questions: (orig?.questions ?? [])
          .map((q) => FixedQuestion(
                id: recruiterId('q'),
                text: q.text,
                category: q.category,
                idealAnswerNotes: q.idealAnswerNotes,
              ))
          .toList(),
      createdAt: now,
      updatedAt: now,
    );
    _questionSets.insert(0, copy);
    _saveToPrefs();
    notifyListeners();
    return copy;
  }

  // ── Sessions & reports ────────────────────────────────────────────────────
  void upsertSession(InterviewSession session) {
    final idx = _sessions.indexWhere((s) => s.id == session.id);
    if (idx >= 0) {
      _sessions[idx] = session;
    } else {
      _sessions.insert(0, session);
    }
    _saveToPrefs();
    notifyListeners();
  }

  void deleteSession(String id) {
    _sessions.removeWhere((s) => s.id == id);
    _reports.remove(id);
    _saveToPrefs();
    notifyListeners();
  }

  void putReport(ResultReport report) {
    _reports[report.sessionId] = report;
    _saveToPrefs();
    notifyListeners();
  }

  // ── Persistence ─────────────────────────────────────────────────────────
  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kStoreKey);
      if (raw == null) {
        // Brand-new install: seed the starter content exactly once.
        _applySeed();
        _hasSeeded = true;
        await _saveToPrefs();
      } else {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        if (data['templates'] != null) {
          _templates = (data['templates'] as List)
              .map((t) => InterviewTemplate.fromJson(t))
              .toList();
        }
        if (data['questionSets'] != null) {
          _questionSets = (data['questionSets'] as List)
              .map((s) => QuestionSet.fromJson(s))
              .toList();
        }
        // Parse each session/report in isolation so one malformed entry does
        // not drop the entire sessions/reports list.
        if (data['sessions'] != null) {
          _sessions = [];
          for (final s in (data['sessions'] as List)) {
            try {
              _sessions.add(InterviewSession.fromJson(s));
            } catch (e) {
              debugPrint('RecruiterStore: skipping bad session: $e');
            }
          }
        }
        if (data['reports'] != null) {
          for (final r in (data['reports'] as List)) {
            try {
              final report = ResultReport.fromJson(r);
              _reports[report.sessionId] = report;
            } catch (e) {
              debugPrint('RecruiterStore: skipping bad report: $e');
            }
          }
        }
        final slot = data['slot0Feature'];
        if (slot == 'recruiter') _slot0Feature = FeatureSlot.recruiter;

        _hasSeeded = data['hasSeeded'] == true;
        if (!_hasSeeded) {
          // Legacy store written before the seed flag existed. Seed only if it
          // has never held starter content (genuine first-run recovery), never
          // clobbering existing data, then record the flag so an intentional
          // full deletion is not resurrected on the next load.
          if (_templates.isEmpty && _questionSets.isEmpty) {
            _applySeed();
          }
          _hasSeeded = true;
          await _saveToPrefs();
        }
      }
    } catch (e) {
      debugPrint('RecruiterStore load error: $e');
      if (_templates.isEmpty && _questionSets.isEmpty) _applySeed();
    } finally {
      _loaded = true;
      notifyListeners();
    }
  }

  void _applySeed() {
    final seed = seedData();
    _templates = seed.templates;
    _questionSets = seed.questionSets;
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = {
        'templates': _templates.map((t) => t.toJson()).toList(),
        'questionSets': _questionSets.map((s) => s.toJson()).toList(),
        'sessions': _sessions.map((s) => s.toJson()).toList(),
        'reports': _reports.values.map((r) => r.toJson()).toList(),
        'slot0Feature':
            _slot0Feature == FeatureSlot.recruiter ? 'recruiter' : 'video',
        'hasSeeded': _hasSeeded,
      };
      await prefs.setString(_kStoreKey, jsonEncode(data));
    } catch (e) {
      debugPrint('RecruiterStore save error: $e');
    }
  }
}
