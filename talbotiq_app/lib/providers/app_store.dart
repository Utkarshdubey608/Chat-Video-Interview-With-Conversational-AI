// lib/providers/app_store.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_models.dart';
import '../core/services/tavus_service.dart';
import '../core/services/hume_service.dart';
import '../core/services/deepgram_service.dart';
import '../core/services/gemini_service.dart';

class AppStore extends ChangeNotifier {
  // SharedPreferences keys
  static const String _kStoreKey = 'talbotiq_store';

  // API credentials
  String _tavusKey = '';
  String _deepgramKey = '';
  String _humeKey = '';
  String _awsKey = '';
  String _anthropicKey = '';
  String _geminiKey = '';
  String _awsProxyUrl = '';
  String _webhookUrl = '';

  // Defaults
  String _defaultReplicaId = '';
  String _defaultPersonaId = '';

  // Active Session
  TavusConversation? _currentConversation;
  List<String> _questions = [
    'Tell me about yourself and your background.',
    'Describe a challenging problem you solved recently.',
    'How do you handle pressure and tight deadlines?',
    'Where do you see yourself in 3 years?',
    'Do you have any questions for us?',
  ];
  int _currentQuestionIdx = 0;
  bool _interviewActive = false;

  // Saved Drafts
  List<Draft> _drafts = [];

  // Cached Tavus Data
  List<TavusReplica> _cachedReplicas = [];
  List<TavusPersona> _cachedPersonas = [];

  // Live Metrics
  int _confidence = 0;
  int _anxiety = 0;
  int _wpm = 0;
  int _fillers = 0;
  int _engagement = 0;

  // Recording preferences
  bool _storeLocalRecordings = false;

  // Hume Batch Job
  String? _humeJobId;
  String? _humeJobStatus;
  HumeSessionResult? _humeResult;
  List<int> _questionTimestamps = [];
  List<HumeEmotion> _liveEmotions = [];
  bool _humeStreamActive = false;

  // Transcript logs
  List<TranscriptEntry> _sessionTranscript = [];
  bool _deepgramConnected = false;
  Future<void>? _loadFuture;

  // Locally-recorded interview audio (native only). Captured during the call,
  // sent to Deepgram for transcription on the results page.
  List<int>? _recordingBytes;

  // Routing state
  String _currentRoute = '/setup';
  String get currentRoute => _currentRoute;

  void navigateTo(String route) {
    _currentRoute = route;
    notifyListeners();
  }

  // Getters
  String get tavusKey => _tavusKey;
  String get deepgramKey => _deepgramKey;
  String get humeKey => _humeKey;
  String get awsKey => _awsKey;
  String get anthropicKey => _anthropicKey;
  String get geminiKey => _geminiKey;
  String get awsProxyUrl => _awsProxyUrl;
  String get webhookUrl => _webhookUrl;

  String get defaultReplicaId => _defaultReplicaId;
  String get defaultPersonaId => _defaultPersonaId;

  TavusConversation? get currentConversation => _currentConversation;
  List<String> get questions => _questions;
  int get currentQuestionIdx => _currentQuestionIdx;
  bool get interviewActive => _interviewActive;
  List<Draft> get drafts => _drafts;

  List<TavusReplica> get cachedReplicas => _cachedReplicas;
  List<TavusPersona> get cachedPersonas => _cachedPersonas;

  int get confidence => _confidence;
  int get anxiety => _anxiety;
  int get wpm => _wpm;
  int get fillers => _fillers;
  int get engagement => _engagement;

  String? get humeJobId => _humeJobId;
  String? get humeJobStatus => _humeJobStatus;
  HumeSessionResult? get humeResult => _humeResult;
  List<int> get questionTimestamps => _questionTimestamps;
  List<HumeEmotion> get liveEmotions => _liveEmotions;
  bool get humeStreamActive => _humeStreamActive;

  List<TranscriptEntry> get sessionTranscript => _sessionTranscript;
  bool get deepgramConnected => _deepgramConnected;
  bool get storeLocalRecordings => _storeLocalRecordings;
  List<int>? get recordingBytes => _recordingBytes;

  AppStore() {
    loadFromPrefs();
  }

  Future<void> loadFromPrefs() {
    _loadFuture ??= _loadFromPrefs();
    return _loadFuture!;
  }

  // Setters
  void setTavusKey(String key) {
    if (_tavusKey != key) {
      _tavusKey = key;
      tavusService.setKey(key);
      _cachedReplicas = [];
      _cachedPersonas = [];
      _saveToPrefs();
      notifyListeners();
    }
  }

  void setDeepgramKey(String key) {
    _deepgramKey = key;
    deepgramService.setKey(key);
    _saveToPrefs();
    notifyListeners();
  }

  void setHumeKey(String key) {
    _humeKey = key;
    humeService.setKey(key);
    _saveToPrefs();
    notifyListeners();
  }

  void setAwsKey(String key) {
    _awsKey = key;
    _saveToPrefs();
    notifyListeners();
  }

  void setAnthropicKey(String key) {
    _anthropicKey = key;
    _saveToPrefs();
    notifyListeners();
  }

  void setGeminiKey(String key) {
    _geminiKey = key;
    geminiService.setKey(key);
    _saveToPrefs();
    notifyListeners();
  }

  void setAwsProxyUrl(String url) {
    _awsProxyUrl = url;
    _saveToPrefs();
    notifyListeners();
  }

  void setWebhookUrl(String url) {
    _webhookUrl = url;
    _saveToPrefs();
    notifyListeners();
  }

  void setStoreLocalRecordings(bool enable) {
    _storeLocalRecordings = enable;
    _saveToPrefs();
    notifyListeners();
  }

  void setDefaultReplicaId(String id) {
    _defaultReplicaId = id;
    _saveToPrefs();
    notifyListeners();
  }

  void setDefaultPersonaId(String id) {
    _defaultPersonaId = id;
    _saveToPrefs();
    notifyListeners();
  }

  void setCurrentConversation(TavusConversation? c) {
    _currentConversation = c;
    notifyListeners();
  }

  void setQuestions(List<String> qs) {
    _questions = qs;
    _saveToPrefs();
    notifyListeners();
  }

  void setCurrentQuestionIdx(int idx) {
    _currentQuestionIdx = idx;
    if (_interviewActive) {
      pushQuestionTimestamp(DateTime.now().millisecondsSinceEpoch);
    }
    notifyListeners();
  }

  void setInterviewActive(bool active) {
    _interviewActive = active;
    if (active) {
      pushQuestionTimestamp(DateTime.now().millisecondsSinceEpoch);
    }
    notifyListeners();
  }

  void updateMetrics({int? conf, int? anx, int? w, int? f, int? eng}) {
    if (conf != null) _confidence = conf;
    if (anx != null) _anxiety = anx;
    if (w != null) _wpm = w;
    if (f != null) _fillers = f;
    if (eng != null) _engagement = eng;
    notifyListeners();
  }

  void saveDraft(String name, DraftForm form, List<String> qs) {
    final newDraft = Draft(
      id: 'draft-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      savedAt: DateTime.now().toIso8601String(),
      form: form,
      questions: qs,
    );

    // Remove existing draft with same name to avoid duplicates
    _drafts.removeWhere((d) => d.name == name);
    _drafts.insert(0, newDraft);

    _saveToPrefs();
    notifyListeners();
  }

  void deleteDraft(String id) {
    _drafts.removeWhere((d) => d.id == id);
    _saveToPrefs();
    notifyListeners();
  }

  void setCachedTavusData(List<TavusReplica> replicas, List<TavusPersona> personas) {
    _cachedReplicas = replicas;
    _cachedPersonas = personas;
    _saveToPrefs();
    notifyListeners();
  }

  void setHumeJobId(String? id) {
    _humeJobId = id;
    notifyListeners();
  }

  void setHumeJobStatus(String? status) {
    _humeJobStatus = status;
    notifyListeners();
  }

  void setHumeResult(HumeSessionResult? result) {
    _humeResult = result;
    notifyListeners();
  }

  void pushQuestionTimestamp(int ts) {
    _questionTimestamps.add(ts);
    notifyListeners();
  }

  void resetQuestionTimestamps() {
    _questionTimestamps = [];
    notifyListeners();
  }

  void setLiveEmotions(List<HumeEmotion> emos) {
    _liveEmotions = emos;
    notifyListeners();
  }

  void setHumeStreamActive(bool active) {
    _humeStreamActive = active;
    notifyListeners();
  }

  void pushTranscriptEntry(TranscriptEntry entry) {
    _sessionTranscript.add(entry);
    notifyListeners();
  }

  void updateTranscriptEntries(List<TranscriptEntry> entries) {
    _sessionTranscript = entries;
    notifyListeners();
  }

  void clearSessionTranscript() {
    _sessionTranscript = [];
    notifyListeners();
  }

  void setDeepgramConnected(bool connected) {
    _deepgramConnected = connected;
    notifyListeners();
  }

  void setRecordingBytes(List<int>? bytes) {
    _recordingBytes = bytes;
    notifyListeners();
  }

  void reset() {
    _currentConversation = null;
    _currentQuestionIdx = 0;
    _interviewActive = false;
    _confidence = 0;
    _anxiety = 0;
    _wpm = 0;
    _fillers = 0;
    _engagement = 0;
    _humeJobId = null;
    _humeJobStatus = null;
    _humeResult = null;
    _questionTimestamps = [];
    _liveEmotions = [];
    _humeStreamActive = false;
    _sessionTranscript = [];
    _deepgramConnected = false;
    _recordingBytes = null;
    notifyListeners();
  }

  // Load from local storage
  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? rawData = prefs.getString(_kStoreKey);
      if (rawData == null) return;

      final Map<String, dynamic> data = jsonDecode(rawData);

      _tavusKey = data['tavusKey'] ?? '';
      _deepgramKey = data['deepgramKey'] ?? '';
      _humeKey = data['humeKey'] ?? '';
      _awsKey = data['awsKey'] ?? '';
      _anthropicKey = data['anthropicKey'] ?? '';
      _geminiKey = data['geminiKey'] ?? '';
      _awsProxyUrl = data['awsProxyUrl'] ?? '';
      _webhookUrl = data['webhookUrl'] ?? '';
      _storeLocalRecordings = data['storeLocalRecordings'] ?? false;

      _defaultReplicaId = data['defaultReplicaId'] ?? '';
      _defaultPersonaId = data['defaultPersonaId'] ?? '';

      if (data['questions'] != null) {
        _questions = List<String>.from(data['questions']);
      }

      if (data['drafts'] != null) {
        final List draftsList = data['drafts'];
        _drafts = draftsList.map((d) => Draft.fromJson(d)).toList();
      }

      if (data['cachedReplicas'] != null) {
        final List replicasList = data['cachedReplicas'];
        _cachedReplicas = replicasList.map((r) => TavusReplica.fromJson(r)).toList();
      }

      if (data['cachedPersonas'] != null) {
        final List personasList = data['cachedPersonas'];
        _cachedPersonas = personasList.map((p) => TavusPersona.fromJson(p)).toList();
      }

      // Propagate keys to services
      tavusService.setKey(_tavusKey);
      humeService.setKey(_humeKey);
      deepgramService.setKey(_deepgramKey);
      geminiService.setKey(_geminiKey);

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading store: $e');
    }
  }

  // Save key credentials and drafts to local storage
  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> data = {
        'tavusKey': _tavusKey,
        'deepgramKey': _deepgramKey,
        'humeKey': _humeKey,
        'awsKey': _awsKey,
        'anthropicKey': _anthropicKey,
        'geminiKey': _geminiKey,
        'awsProxyUrl': _awsProxyUrl,
        'webhookUrl': _webhookUrl,
        'defaultReplicaId': _defaultReplicaId,
        'defaultPersonaId': _defaultPersonaId,
        'storeLocalRecordings': _storeLocalRecordings,
        'questions': _questions,
        'drafts': _drafts.map((d) => d.toJson()).toList(),
        'cachedReplicas': _cachedReplicas.map((r) => r.toJson()).toList(),
        'cachedPersonas': _cachedPersonas.map((p) => p.toJson()).toList(),
      };
      await prefs.setString(_kStoreKey, jsonEncode(data));
    } catch (e) {
      debugPrint('Error saving store: $e');
    }
  }

  // Clear preferences
  Future<void> clearAllPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kStoreKey);
    reset();
    _tavusKey = '';
    _deepgramKey = '';
    _humeKey = '';
    _awsKey = '';
    _anthropicKey = '';
    _geminiKey = '';
    _awsProxyUrl = '';
    _webhookUrl = '';
    _defaultReplicaId = '';
    _defaultPersonaId = '';
    _questions = [
      'Tell me about yourself and your background.',
      'Describe a challenging problem you solved recently.',
      'How do you handle pressure and tight deadlines?',
      'Where do you see yourself in 3 years?',
      'Do you have any questions for us?',
    ];
    _drafts = [];
    _cachedReplicas = [];
    _cachedPersonas = [];
    notifyListeners();
  }
}
