// lib/core/services/gemini_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../models/app_models.dart';

class GeminiService {
  String _apiKey = '';
  String _model = 'gemini-2.5-flash';

  void setKey(String key) {
    _apiKey = key;
  }

  String getKey() => _apiKey;

  Future<ATSScorecard> analyze({
    required String candidateName,
    required String jobRole,
    required int interviewDurationSeconds,
    required List<TranscriptEntry> transcript,
    required List<String> questions,
    required HumeSessionResult? humeResult,
    required int wpm,
    required int totalFillers,
    required FacialSessionSummary? facialSummary,
  }) async {
    if (_apiKey.isEmpty) {
      throw Exception('Gemini API key not set. Go to Settings and add your Gemini key.');
    }
    
    final candidateEntries = transcript.where((e) => e.role == 'candidate').toList();
    final overallTranscript = candidateEntries.map((e) => e.text).join(' ').trim();

    if (overallTranscript.length < 30) {
      throw Exception('Transcript too short for reliable analysis. The candidate must speak enough for a meaningful assessment.');
    }

    final double overallFillerRate = interviewDurationSeconds > 0
        ? (totalFillers / interviewDurationSeconds) * 60.0
        : 0.0;

    final hasHumeData = humeResult != null && humeResult.perQuestion.isNotEmpty;
    final humeTopEmotions = humeResult?.overallTopEmotions ?? [];

    // Construct per-question block
    final List<Map<String, dynamic>> questionInputs = [];
    for (int idx = 0; idx < questions.length; idx++) {
      final qText = questions[idx];
      final qEntries = candidateEntries.where((e) => e.questionIdx == idx).toList();
      final answerTranscript = qEntries.map((e) => e.text).join(' ').trim();
      final wordCount = answerTranscript.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
      
      // Count fillers for this question
      int fillerCount = 0;
      final Set<String> fillerWordsFound = {};
      final words = answerTranscript.toLowerCase().replaceAll(RegExp(r'[.,!?;:]'), '').split(RegExp(r'\s+'));
      for (var w in words) {
        if (w.isNotEmpty && {
          'um', 'uh', 'hmm', 'er', 'erm', 'ah', 'like', 'basically', 'literally',
          'actually', 'right', 'okay', 'so', 'you know', 'i mean', 'kind of', 'sort of',
        }.contains(w)) {
          fillerCount++;
          fillerWordsFound.add(w);
        }
      }

      final humeQ = humeResult?.perQuestion.firstWhere(
        (q) => q.questionIdx == idx,
        orElse: () => QuestionEmotionSummary(
          questionIdx: idx,
          questionText: qText,
          avgCategoryScores: {},
          dominant: 'Neutral',
          timeline: [],
          topEmotions: [],
        ),
      );

      final hasEmotion = humeQ != null && humeQ.timeline.isNotEmpty;

      questionInputs.add({
        'questionIdx': idx,
        'questionText': qText,
        'answerTranscript': answerTranscript,
        'wordCount': wordCount,
        'fillerCount': fillerCount,
        'fillerWords': fillerWordsFound.toList(),
        'topEmotions': humeQ?.topEmotions.map((e) => {'name': e.name, 'score': e.score}).toList() ?? [],
        'dominantEmotion': humeQ?.dominant,
        'hasEmotionData': hasEmotion,
      });
    }

    final prompt = _buildAnalysisPrompt(
      candidateName: candidateName,
      jobRole: jobRole,
      durationSeconds: interviewDurationSeconds,
      overallTranscript: overallTranscript,
      wpm: wpm,
      totalFillers: totalFillers,
      fillerRate: overallFillerRate,
      humeResult: humeResult,
      hasHumeData: hasHumeData,
      humeTopEmotions: humeTopEmotions,
      questionInputs: questionInputs,
      facialSummary: facialSummary,
    );

    final requestBody = {
      'contents': [
        {
          'parts': [{'text': prompt}]
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'topK': 1,
        'topP': 0.8,
        'maxOutputTokens': 20000,
        'responseMimeType': 'application/json',
      },
    };

    final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$_apiKey');

    print('DEBUG: [Gemini API] Request model: $_model');
    print('DEBUG: [Gemini API] Request Body:\n${jsonEncode(requestBody)}');

    // Retry loop for 503 & 429
    int attempts = 4;
    http.Response? response;
    for (int i = 0; i < attempts; i++) {
      try {
        response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        );
        if (response.statusCode == 200) break;

        // Sleep with exponential backoff on transient errors
        if (response.statusCode == 503 || response.statusCode == 429) {
          await Future.delayed(Duration(milliseconds: 800 * (i + 1)));
          continue;
        }
        break;
      } catch (e) {
        if (i == attempts - 1) rethrow;
        await Future.delayed(Duration(milliseconds: 800 * (i + 1)));
      }
    }

    if (response == null) {
      print('DEBUG: [Gemini API] No response received.');
      throw Exception('Failed to generate content: No response received from Gemini.');
    }

    print('DEBUG: [Gemini API] Response Status Code: ${response.statusCode}');
    print('DEBUG: [Gemini API] Response Body:\n${response.body}');

    if (response.statusCode != 200) {
      throw Exception('Gemini API error: ${response.statusCode} - ${response.body}');
    }

    final data = jsonDecode(response.body);
    final rawText = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
    if (rawText == null || (rawText as String).isEmpty) {
      throw Exception('Gemini returned an empty response.');
    }

    try {
      final cleaned = rawText
          .replaceFirst(RegExp(r'^```json\s*'), '')
          .replaceFirst(RegExp(r'^```\s*'), '')
          .replaceFirst(RegExp(r'```\s*$'), '')
          .trim();
      final decodedMap = jsonDecode(cleaned);
      final scorecard = ATSScorecard.fromJson(decodedMap);
      return scorecard;
    } catch (e) {
      throw Exception('Failed to parse Gemini response as JSON: $e. Raw response head: ${rawText.toString().substring(0, 200)}');
    }
  }

  String _buildAnalysisPrompt({
    required String candidateName,
    required String jobRole,
    required int durationSeconds,
    required String overallTranscript,
    required int wpm,
    required int totalFillers,
    required double fillerRate,
    required HumeSessionResult? humeResult,
    required bool hasHumeData,
    required List<HumeEmotion> humeTopEmotions,
    required List<Map<String, dynamic>> questionInputs,
    required FacialSessionSummary? facialSummary,
  }) {
    final questionSections = questionInputs.map((q) {
      final hasEmotion = q['hasEmotionData'] as bool;
      final emotions = q['topEmotions'] as List;
      final emoStr = hasEmotion && emotions.isNotEmpty
          ? emotions.map((e) => '    ${e['name']}: ${(e['score'] * 100).toStringAsFixed(1)}%').join('\n')
          : '    No Hume emotion data available for this answer';

      return '''
--- QUESTION ${q['questionIdx'] + 1} ---
Question asked: "${q['questionText']}"
Answer transcript: ${q['answerTranscript'] != '' ? '"${q['answerTranscript']}"' : '(no spoken answer captured)'}
Answer word count: ${q['wordCount']}
Filler words detected: ${q['fillerCount']} (${(q['fillerWords'] as List).join(', ')})
Dominant emotion (Hume prosody): ${q['dominantEmotion'] ?? 'N/A'}
Hume emotion signals during this answer:
$emoStr
''';
    }).join('\n');

    final topEmotionsText = hasHumeData && humeTopEmotions.isNotEmpty
        ? humeTopEmotions.map((e) => '  ${e.name}: ${(e.score * 100).toStringAsFixed(1)}%').join('\n')
        : '  No Hume prosody data available for this session';

    final f = facialSummary;
    final facialSection = f != null && f.dataQuality != 'insufficient'
        ? '''
---
FACIAL ANALYSIS DATA (AWS Rekognition — ${f.dataQuality} quality):
Data quality note: ${f.dataQualityNote}
Frames: ${f.usableFrames} usable of ${f.totalFrames} captured

IMPORTANT: Facial data is SUPPLEMENTARY only. Never override voice/transcript findings with facial
data alone. If facial data quality is "low", reduce its weight accordingly.

Session facial overview:
- Average camera attention: ${(f.sessionAvgAttention * 100).toStringAsFixed(1)}%
- Looking away from camera: ${f.overallLookingAwayPercent.toStringAsFixed(1)}% of frames
- Dominant facial emotions: ${f.sessionDominantEmotions.map((e) => '${e['type']} (${(e['avgConfidence'] as num).toStringAsFixed(1)}%)').join(', ')}

Per-question facial signals:
${f.perQuestion.map((q) => '  Q${q.questionIdx + 1}: ${q.usableFrameCount} usable frames — attention ${(q.avgAttentionScore * 100).toStringAsFixed(0)}%, looking away ${q.lookingAwayPercent.toStringAsFixed(0)}%, dominant facial emotion ${q.dominantEmotions.isNotEmpty ? '${q.dominantEmotions[0]['type']} (${(q.dominantEmotions[0]['avgConfidence'] as num).toStringAsFixed(0)}%)' : 'insufficient'}, head variance ${q.headPoseVariance.toStringAsFixed(0)} (>200 notable)').join('\n')}

Facial integrity flags: ${f.integrityFlags.isNotEmpty ? f.integrityFlags.join('; ') : 'none'}
Facial engagement signals: ${f.engagementFlags.isNotEmpty ? f.engagementFlags.join('; ') : 'none'}
Facial concern signals: ${f.concernFlags.isNotEmpty ? f.concernFlags.join('; ') : 'none'}

CROSS-VALIDATION RULES:
- If voice emotion (Hume) AND facial emotion (Rekognition) AGREE → higher-confidence signal.
- If they DISAGREE → flag as conflicting, reduce confidence, note for human review.
- Camera attention is an engagement proxy, NOT a measure of honesty.
- Multiple faces in frame is an integrity flag, NOT proof of cheating.
'''
        : '''
---
FACIAL ANALYSIS: Not available for this session (no camera, permission denied, or proxy not configured). Do not factor facial signals into scoring.
''';

    return '''You are an expert ATS (Applicant Tracking System) analyst. You are analyzing a job interview for the role of "$jobRole".

CRITICAL INSTRUCTIONS — READ BEFORE ANALYZING:

1. ACCURACY OVER COMPLETENESS: If you do not have sufficient evidence to score a dimension, set cannotAssess=true and explain why. Never fabricate scores.

2. TRANSCRIPT IS ASR OUTPUT: The transcript comes from Deepgram Nova-3 speech recognition. It is accurate but not infallible — treat oddly-worded fragments as possible transcription artifacts, not as the candidate misspeaking. Do not quote a garbled fragment as if it were a deliberate statement.

3. EMOTION DATA LIMITATIONS: Hume AI measures vocal prosody only — not facial expression, not intent, not personality. A high "Anxiety" score means the voice SOUNDED anxious; it does NOT prove the candidate IS anxious. Always interpret with appropriate uncertainty. If no Hume data is present, set the emotional dimensions' cannotAssess=true.

4. NO BIAS: Do not factor in name, perceived gender, accent, or any demographic signals. Score only communication quality, answer substance, and observable engagement signals.

5. EVIDENCE CITATIONS: Every score must cite specific evidence — "The candidate said X" or "Hume registered Y during question Z" — not vague impressions.

6. CONSERVATIVE SCORING: When in doubt, score lower and flag for human review rather than inflating. A false positive (advancing a poor candidate) and a false negative (rejecting a good one) are both serious errors.

7. RESPECT UNCERTAINTY: An interview transcript captures one moment in time. Do not make sweeping personality judgments from limited data.

---

CANDIDATE: $candidateName
ROLE: $jobRole
INTERVIEW DURATION: ${durationSeconds ~/ 60}m ${durationSeconds % 60}s
OVERALL WPM: $wpm
OVERALL FILLERS: $totalFillers (${fillerRate.toStringAsFixed(2)}/min)
HUME COMPOSITE SCORE: ${humeResult?.compositeScore ?? 'N/A'}

TOP EMOTION SIGNALS (full session average via Hume AI prosody):
$topEmotionsText

---
INTERVIEW Q&A:
$questionSections

---
FACIAL DATA:
$facialSection

---
FULL TRANSCRIPT (for context):
"${overallTranscript.isNotEmpty ? overallTranscript : '(no transcript captured)'}"

Now produce a complete ATS analysis. Respond ONLY with a valid JSON object matching this exact structure. No preamble, no markdown, no text outside the JSON.

Each ScoredDimension has: { "score": <1-10 integer>, "evidenceLevel": "strong"|"moderate"|"weak"|"insufficient", "evidenceSummary": "<string>", "quotes": ["<string>"], "flags": ["<string>"], "cannotAssess": <boolean>, "cannotAssessReason": "<string, only if cannotAssess true>" }.

{
  "overallFitScore": <number 1-100 or null if insufficient>,
  "overallFitLabel": "Strong Fit" | "Potential Fit" | "Needs Review" | "Insufficient Data",
  "overallConfidenceLevel": "strong" | "moderate" | "weak" | "insufficient",
  "communicationScore": <ScoredDimension>,
  "technicalDepthScore": <ScoredDimension>,
  "problemSolvingScore": <ScoredDimension>,
  "engagementScore": <ScoredDimension>,
  "consistencyScore": <ScoredDimension>,
  "communicationProfile": {
    "overallClarity": <ScoredDimension>,
    "vocabularyRichness": <ScoredDimension>,
    "fillerWordImpact": <ScoredDimension>,
    "pacingAssessment": "<string>",
    "structuredThinking": <ScoredDimension>,
    "note": "<string>"
  },
  "emotionalIntelligenceProfile": {
    "engagementLevel": <ScoredDimension>,
    "stressResponse": <ScoredDimension>,
    "authenticitySignals": "<string>",
    "emotionalVariability": "<string>",
    "concernFlags": ["<string>"],
    "dataQualityNote": "<string>"
  },
  "perQuestionAnalysis": [
    {
      "questionIdx": <number>,
      "questionText": "<string>",
      "answerSummary": "<1-2 sentence neutral summary>",
      "relevanceScore": <ScoredDimension>,
      "clarityScore": <ScoredDimension>,
      "depthScore": <ScoredDimension>,
      "dominantEmotions": [{ "name": "<string>", "score": <0-1>, "interpretation": "<cautious interpretation>" }],
      "emotionalConsistency": "<string>",
      "redFlags": ["<string>"],
      "strengths": ["<string>"],
      "transcriptQuality": "high" | "medium" | "low",
      "transcriptQualityNote": "<string>"
    }
  ],
  "topStrengths": ["<string>"],
  "topConcerns": ["<string>"],
  "recommendedFollowUpQuestions": ["<string>"],
  "hiringRecommendation": "Advance" | "Hold" | "Decline" | "Insufficient Data",
  "hiringRecommendationRationale": "<2-3 sentences, evidence-based>",
  "dataLimitations": ["<string>"],
  "transcriptReliabilityNote": "<string>",
  "biasWarnings": ["<string>"],
  "analysisTimestamp": ${DateTime.now().millisecondsSinceEpoch},
  "geminiModel": "gemini-2.5-flash",
  "inputDataQuality": "high" | "medium" | "low" | "insufficient"
}
''';
  }
}

final geminiService = GeminiService();
