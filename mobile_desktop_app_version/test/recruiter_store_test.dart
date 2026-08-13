// test/recruiter_store_test.dart
//
// RecruiterStore's Template/QuestionSet writes now report whether the change
// actually reached disk (see _saveToPrefs) rather than silently claiming
// success — Library editors (templates_page.dart, template_editor_page.dart,
// question_sets_page.dart, question_set_editor_page.dart,
// generate_from_resume_page.dart) use this to avoid telling a recruiter
// "Saved" when the write genuinely failed. These tests pin that contract at
// the store level, independent of any editor UI, using a fake
// SharedPreferences platform store that can be told to fail on demand —
// shared_preferences' own setString() resolves to `false` on a failed write,
// it does not always throw, so the fake fails the same way.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:talbotiq/features/recruiter/engine/seed.dart';
import 'package:talbotiq/features/recruiter/models/recruiter_models.dart';
import 'package:talbotiq/features/recruiter/store/recruiter_store.dart';

class _FailableStore extends InMemorySharedPreferencesStore {
  _FailableStore.empty() : super.withData({});

  bool shouldFail = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (shouldFail) return false;
    return super.setValue(valueType, key, value);
  }
}

QuestionSet _set({String id = 'set-1', String name = 'Set'}) => QuestionSet(
      id: id,
      name: name,
      questions: const [
        FixedQuestion(id: 'q1', text: 'Tell me about yourself.'),
      ],
      createdAt: '2026-01-01T00:00:00.000Z',
      updatedAt: '2026-01-01T00:00:00.000Z',
    );

void main() {
  late _FailableStore fakeStore;
  late RecruiterStore store;

  setUp(() async {
    fakeStore = _FailableStore.empty();
    SharedPreferencesStorePlatform.instance = fakeStore;
    store = RecruiterStore();
    await store.load();
  });

  group('upsertQuestionSet', () {
    test('a successful write returns true', () async {
      final ok = await store.upsertQuestionSet(_set());
      expect(ok, isTrue);
      expect(store.questionSetById('set-1'), isNotNull);
    });

    test('a failed write returns false, but the in-memory change still applies', () async {
      fakeStore.shouldFail = true;
      final ok = await store.upsertQuestionSet(_set());
      expect(ok, isFalse);
      // The recruiter still sees it this session — only durability failed.
      expect(store.questionSetById('set-1'), isNotNull);
    });
  });

  group('deleteQuestionSet', () {
    test('a successful delete returns true', () async {
      await store.upsertQuestionSet(_set());
      final ok = await store.deleteQuestionSet('set-1');
      expect(ok, isTrue);
      expect(store.questionSetById('set-1'), isNull);
    });

    test('a failed delete returns false, but the in-memory removal still applies', () async {
      await store.upsertQuestionSet(_set());
      fakeStore.shouldFail = true;
      final ok = await store.deleteQuestionSet('set-1');
      expect(ok, isFalse);
      expect(store.questionSetById('set-1'), isNull);
    });
  });

  group('duplicateQuestionSet', () {
    test('a successful duplicate returns true and adds exactly one set', () async {
      await store.upsertQuestionSet(_set());
      final before = store.questionSets.length;
      final ok = await store.duplicateQuestionSet('set-1');
      expect(ok, isTrue);
      expect(store.questionSets.length, before + 1);
    });

    test('a failed duplicate returns false, but the copy still applies in memory', () async {
      await store.upsertQuestionSet(_set());
      final before = store.questionSets.length;
      fakeStore.shouldFail = true;
      final ok = await store.duplicateQuestionSet('set-1');
      expect(ok, isFalse);
      expect(store.questionSets.length, before + 1);
    });
  });

  group('upsertTemplate / deleteTemplate', () {
    final template = seedData().templates.first;

    test('a successful template save returns true', () async {
      final ok = await store.upsertTemplate(template);
      expect(ok, isTrue);
      expect(store.templateById(template.id), isNotNull);
    });

    test('a failed template save returns false, but the in-memory change still applies', () async {
      fakeStore.shouldFail = true;
      final ok = await store.upsertTemplate(template);
      expect(ok, isFalse);
      expect(store.templateById(template.id), isNotNull);
    });

    test('a successful template delete returns true', () async {
      await store.upsertTemplate(template);
      final ok = await store.deleteTemplate(template.id);
      expect(ok, isTrue);
      expect(store.templateById(template.id), isNull);
    });

    test('a failed template delete returns false, but the in-memory removal still applies', () async {
      await store.upsertTemplate(template);
      fakeStore.shouldFail = true;
      final ok = await store.deleteTemplate(template.id);
      expect(ok, isFalse);
      expect(store.templateById(template.id), isNull);
    });
  });
}
