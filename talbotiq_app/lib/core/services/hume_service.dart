// lib/core/services/hume_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../models/app_models.dart';

class HumeService {
  String _apiKey = '';

  void setKey(String key) {
    _apiKey = key;
  }

  String getKey() => _apiKey;

  Map<String, String> _headers() {
    return {
      'X-Hume-Api-Key': _apiKey,
      'Content-Type': 'application/json',
    };
  }

  final Map<String, List<String>> _emotionCategoryMap = {
    'positive_high': [
      'Admiration', 'Amusement', 'Excitement', 'Elation', 'Enthusiasm',
      'Pride', 'Triumph', 'Joy', 'Ecstasy',
    ],
    'positive_calm': [
      'Calmness', 'Contentment', 'Satisfaction', 'Serenity', 'Awe',
      'Aesthetic Appreciation', 'Contemplation', 'Adoration', 'Interest',
    ],
    'cognitive': [
      'Concentration', 'Contemplation', 'Curiosity', 'Determination',
      'Realization', 'Surprise (positive)', 'Surprise (negative)',
    ],
    'social': [
      'Empathic Pain', 'Sympathy', 'Romance', 'Desire', 'Envy',
      'Jealousy', 'Nostalgia', 'Longing',
    ],
    'negative': [
      'Anger', 'Anxiety', 'Confusion', 'Contempt', 'Disappointment',
      'Disgust', 'Distress', 'Embarrassment', 'Fear', 'Guilt',
      'Horror', 'Shame', 'Sadness', 'Tiredness', 'Pain',
    ],
    'disengagement': [
      'Boredom', 'Doubt', 'Awkwardness', 'Sickness',
    ],
  };

  String categorizeEmotion(String name) {
    for (var entry in _emotionCategoryMap.entries) {
      if (entry.value.any((n) => n.toLowerCase() == name.toLowerCase())) {
        return entry.key;
      }
    }
    return 'cognitive';
  }

  Map<String, double> buildCategoryScores(List<HumeEmotion> emotions) {
    final Map<String, double> sums = {
      'positive_high': 0.0,
      'positive_calm': 0.0,
      'cognitive': 0.0,
      'social': 0.0,
      'negative': 0.0,
      'disengagement': 0.0,
    };
    final Map<String, int> counts = {
      'positive_high': 0,
      'positive_calm': 0,
      'cognitive': 0,
      'social': 0,
      'negative': 0,
      'disengagement': 0,
    };

    for (var emo in emotions) {
      final cat = categorizeEmotion(emo.name);
      sums[cat] = (sums[cat] ?? 0.0) + emo.score;
      counts[cat] = (counts[cat] ?? 0) + 1;
    }

    final Map<String, double> out = {};
    for (var key in sums.keys) {
      final count = counts[key] ?? 0;
      out[key] = count > 0 ? (sums[key] ?? 0.0) / count : 0.0;
    }
    return out;
  }

  String getDominantEmotion(List<HumeEmotion> emotions) {
    if (emotions.isEmpty) return 'Neutral';
    HumeEmotion dom = emotions[0];
    for (var emo in emotions) {
      if (emo.score > dom.score) {
        dom = emo;
      }
    }
    return dom.name;
  }

  List<HumeEmotion> getTopN(List<HumeEmotion> emotions, {int n = 5}) {
    final sorted = List<HumeEmotion>.from(emotions);
    sorted.sort((a, b) => b.score.compareTo(a.score));
    return sorted.take(n).toList();
  }

  Map<String, double> avgCategoryScores(List<EmotionSnapshot> snapshots) {
    final Map<String, double> sums = {
      'positive_high': 0.0,
      'positive_calm': 0.0,
      'cognitive': 0.0,
      'social': 0.0,
      'negative': 0.0,
      'disengagement': 0.0,
    };
    if (snapshots.isEmpty) return sums;

    for (var snap in snapshots) {
      for (var key in sums.keys) {
        sums[key] = (sums[key] ?? 0.0) + (snap.categoryScores[key] ?? 0.0);
      }
    }

    final Map<String, double> out = {};
    for (var key in sums.keys) {
      out[key] = (sums[key] ?? 0.0) / snapshots.length;
    }
    return out;
  }

  int computeCompositeScore(Map<String, double> overall) {
    final Map<String, double> weights = {
      'positive_high': 0.30,
      'positive_calm': 0.25,
      'cognitive': 0.20,
      'social': 0.10,
      'negative': -0.15,
      'disengagement': -0.20,
    };
    double score = 0.0;
    for (var key in weights.keys) {
      score += (overall[key] ?? 0.0) * (weights[key] ?? 0.0);
    }
    final rawVal = ((score + 0.35) * (100.0 / 0.7));
    return rawVal.clamp(0.0, 100.0).round();
  }

  // Submit audio bytes to Hume
  Future<String> submitBatchJob(List<int> audioBytes, {String filename = 'interview.webm'}) async {
    final url = Uri.parse('https://api.hume.ai/v0/batch/jobs');
    
    final request = http.MultipartRequest('POST', url)
      ..headers['X-Hume-Api-Key'] = _apiKey.trim()
      ..fields['json'] = jsonEncode({
        'models': {'prosody': {}}
      })
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          audioBytes,
          filename: filename,
          contentType: MediaType('audio', 'webm'),
        ),
      );

    final response = await http.Response.fromStream(await request.send());

    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = jsonDecode(response.body);
      final jobId = body['job_id'] ?? body['id'];
      if (jobId == null) throw Exception('Hume response missing job_id');
      return jobId as String;
    } else {
      String msg = 'HTTP ${response.statusCode}';
      try {
        final errBody = jsonDecode(response.body);
        msg = errBody?['message'] ?? msg;
      } catch (_) {}
      throw Exception('Hume batch submit failed: $msg');
    }
  }

  // Submit audio URLs to Hume
  Future<String> submitBatchJobWithUrls(List<String> urls) async {
    final url = Uri.parse('https://api.hume.ai/v0/batch/jobs');
    final response = await http.post(
      url,
      headers: _headers(),
      body: jsonEncode({
        'urls': urls,
        'models': {'prosody': {}}
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      final body = jsonDecode(response.body);
      final jobId = body['job_id'] ?? body['id'];
      if (jobId == null) throw Exception('Hume response missing job_id');
      return jobId as String;
    } else {
      String msg = 'HTTP ${response.statusCode}';
      try {
        final errBody = jsonDecode(response.body);
        msg = errBody?['message'] ?? msg;
      } catch (_) {}
      throw Exception('Hume batch submit URLs failed: $msg');
    }
  }

  // Poll job status
  Future<Map<String, dynamic>> pollBatchJob(String jobId) async {
    final url = Uri.parse('https://api.hume.ai/v0/batch/jobs/$jobId');
    final response = await http.get(url, headers: _headers());

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final status = body['status'] ?? body['state']?['status'] ?? 'IN_PROGRESS';
      return {
        'job_id': jobId,
        'status': status,
        'created_at': body['created_at'] ?? 0,
      };
    } else {
      throw Exception('Hume poll failed: HTTP ${response.statusCode}');
    }
  }

  // Fetch predictions
  Future<List<dynamic>> fetchBatchPredictions(String jobId) async {
    final url = Uri.parse('https://api.hume.ai/v0/batch/jobs/$jobId/predictions');
    final response = await http.get(url, headers: _headers());

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data is List) return data;
      return data['results'] ?? data['predictions'] ?? [];
    } else {
      throw Exception('Failed to fetch predictions: HTTP ${response.statusCode}');
    }
  }

  HumeSessionResult buildSessionResult(
    String jobId,
    List<dynamic> predictions,
    List<int> questionTimestamps,
    List<String> questions,
  ) {
    final List<Map<String, dynamic>> allPredictions = [];

    // Parse standard Hume predictions format
    for (var pred in predictions) {
      final results = pred['results'] as Map?;
      final preds = results?['predictions'] as List?;
      if (preds == null || preds.isEmpty) continue;
      
      final models = preds[0]['models'] as Map?;
      final prosody = models?['prosody'] as Map?;
      final grouped = prosody?['grouped_predictions'] as List?;
      if (grouped == null) continue;

      for (var grp in grouped) {
        final itemPreds = grp['predictions'] as List?;
        if (itemPreds == null) continue;
        for (var p in itemPreds) {
          final time = p['time'] as Map?;
          final emotionsList = p['emotions'] as List?;
          if (time == null || emotionsList == null) continue;
          
          final List<HumeEmotion> emos = emotionsList
              .map((e) => HumeEmotion.fromJson(Map<String, dynamic>.from(e)))
              .toList();

          allPredictions.add({
            'begin': (time['begin'] as num).toDouble(),
            'end': (time['end'] as num).toDouble(),
            'emotions': emos,
          });
        }
      }
    }

    allPredictions.sort((a, b) => (a['begin'] as double).compareTo(b['begin'] as double));

    final List<EmotionSnapshot> timeline = allPredictions.map((p) {
      final emos = p['emotions'] as List<HumeEmotion>;
      return EmotionSnapshot(
        timestamp: p['begin'] as double,
        emotions: emos,
        categoryScores: buildCategoryScores(emos),
        dominant: getDominantEmotion(emos),
      );
    }).toList();

    // Map epoch timestamps to offsets in seconds
    final List<double> qTimestampsSec = [];
    if (questionTimestamps.isNotEmpty) {
      final first = questionTimestamps[0];
      for (var i = 0; i < questionTimestamps.length; i++) {
        qTimestampsSec.add(i == 0 ? 0.0 : (questionTimestamps[i] - first) / 1000.0);
      }
    }

    final List<QuestionEmotionSummary> perQuestion = [];
    for (var idx = 0; idx < questions.length; idx++) {
      final qText = questions[idx];
      final start = idx < qTimestampsSec.length ? qTimestampsSec[idx] : 0.0;
      final end = (idx + 1) < qTimestampsSec.length ? qTimestampsSec[idx + 1] : double.infinity;

      final slice = timeline.where((s) => s.timestamp >= start && s.timestamp < end).toList();
      if (slice.isEmpty) continue;

      final avg = avgCategoryScores(slice);
      final allEmotions = slice.expand((s) => s.emotions).toList();

      perQuestion.add(QuestionEmotionSummary(
        questionIdx: idx,
        questionText: qText,
        avgCategoryScores: avg,
        dominant: getDominantEmotion(getTopN(allEmotions, n: 1)),
        timeline: slice,
        topEmotions: getTopN(allEmotions),
      ));
    }

    final overallCat = avgCategoryScores(timeline);
    final allTop = getTopN(allPredictions.expand((p) => p['emotions'] as List<HumeEmotion>).toList());

    return HumeSessionResult(
      jobId: jobId,
      status: 'COMPLETED',
      overallCategoryScores: overallCat,
      overallTopEmotions: allTop,
      perQuestion: perQuestion,
      timeline: timeline,
      compositeScore: computeCompositeScore(overallCat),
    );
  }
}

final humeService = HumeService();
