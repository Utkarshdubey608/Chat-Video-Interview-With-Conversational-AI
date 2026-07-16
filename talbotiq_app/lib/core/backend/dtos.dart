// lib/core/backend/dtos.dart
//
// Dart data-transfer objects mirroring the website's shared/types.ts contract
// (the single source of truth shared by the Vite client and the Express/Cloud
// server). Field NAMES are kept identical to the TypeScript interfaces so the
// two clients interoperate on the same JSON — do not rename them casually.
//
// These are ADDITIVE SCAFFOLDING for the future secure backend; they carry no
// behaviour beyond fromJson/toJson. Nested shapes are modelled as their own
// DTOs where the contract nests an object, and left as typed lists/maps where
// the contract uses `Record<string, number>` etc.
//
// Only the request/response shapes the gateways need are modelled here (per the
// build spec): invites, candidate extraction, analytics, avatar start, the
// voice catalog, and app-settings status. The remaining contract types
// (sessions, reports, templates) are added when their gateways are wired.

// ─── helpers ────────────────────────────────────────────────────────────────

int _asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : 0);
double _asDouble(Object? v) => v is num ? v.toDouble() : 0.0;
String _asString(Object? v) => v is String ? v : (v?.toString() ?? '');
bool _asBool(Object? v) => v is bool ? v : false;

List<T> _mapList<T>(Object? v, T Function(Map<String, dynamic>) f) {
  if (v is! List) return <T>[];
  return v
      .whereType<Map>()
      .map((e) => f(Map<String, dynamic>.from(e)))
      .toList(growable: false);
}

List<String> _stringList(Object? v) =>
    v is List ? v.map(_asString).toList(growable: false) : const <String>[];

Map<String, double> _numMap(Object? v) {
  if (v is! Map) return <String, double>{};
  return v.map((k, val) => MapEntry(k.toString(), _asDouble(val)));
}

/* ─── Bulk invite — candidate extraction (POST /api/invites/extract) ──────── */

/// One candidate parsed out of an uploaded CSV / Excel / PDF / text file.
/// Mirrors `ExtractedCandidate`.
class ExtractedCandidate {
  const ExtractedCandidate({
    required this.email,
    required this.role,
    required this.valid,
  });

  final String email;
  final String role; // extracted role, or the recruiter's Step-1 role fallback
  final bool valid; // email passed format validation

  factory ExtractedCandidate.fromJson(Map<String, dynamic> json) =>
      ExtractedCandidate(
        email: _asString(json['email']),
        role: _asString(json['role']),
        valid: _asBool(json['valid']),
      );

  Map<String, dynamic> toJson() => {
        'email': email,
        'role': role,
        'valid': valid,
      };
}

/// Mirrors `ExtractCandidatesResult`.
class ExtractCandidatesResult {
  const ExtractCandidatesResult({required this.rows, required this.warnings});

  final List<ExtractedCandidate> rows;
  final List<String> warnings; // e.g. "N duplicates removed"

  factory ExtractCandidatesResult.fromJson(Map<String, dynamic> json) =>
      ExtractCandidatesResult(
        rows: _mapList(json['rows'], ExtractedCandidate.fromJson),
        warnings: _stringList(json['warnings']),
      );

  Map<String, dynamic> toJson() => {
        'rows': rows.map((r) => r.toJson()).toList(),
        'warnings': warnings,
      };
}

/* ─── Bulk invite — create (POST /api/invites) ────────────────────────────── */

/// Per-résumé tailoring params — mirrors the inline `config` object on
/// `CreateInvitesRequest` (used when source === 'tailor').
class CreateInvitesConfig {
  const CreateInvitesConfig({
    required this.style,
    required this.techCount,
    required this.nonTechCount,
    required this.difficulty,
    required this.domains,
    required this.model,
  });

  final String style; // QuestionStyle: 'technical' | 'non_technical' | 'mix'
  final int techCount;
  final int nonTechCount;
  final String difficulty; // DifficultyChoice: easy|medium|hard|mixed
  final List<String> domains;
  final String model; // GeminiModel: 'gemini-2.5-flash' | 'gemini-2.5-pro'

  factory CreateInvitesConfig.fromJson(Map<String, dynamic> json) =>
      CreateInvitesConfig(
        style: _asString(json['style']),
        techCount: _asInt(json['techCount']),
        nonTechCount: _asInt(json['nonTechCount']),
        difficulty: _asString(json['difficulty']),
        domains: _stringList(json['domains']),
        model: _asString(json['model']),
      );

  Map<String, dynamic> toJson() => {
        'style': style,
        'techCount': techCount,
        'nonTechCount': nonTechCount,
        'difficulty': difficulty,
        'domains': domains,
        'model': model,
      };
}

/// A single candidate line item on a create-invites request.
/// Mirrors the inline `{ email; role }` used by `CreateInvitesRequest.candidates`.
class InviteCandidate {
  const InviteCandidate({required this.email, required this.role});

  final String email;
  final String role;

  factory InviteCandidate.fromJson(Map<String, dynamic> json) =>
      InviteCandidate(
        email: _asString(json['email']),
        role: _asString(json['role']),
      );

  Map<String, dynamic> toJson() => {'email': email, 'role': role};
}

/// Mirrors `CreateInvitesRequest` — create one interview per candidate and
/// (optionally) email them.
class CreateInvitesRequest {
  const CreateInvitesRequest({
    required this.mode,
    required this.role,
    required this.source,
    required this.candidates,
    this.config,
    this.questionSetId,
    this.origin,
  });

  final String mode; // TrackType: chat|chatbot|video_avatar|voice
  final String role; // batch candidate role (Step 1)
  final String source; // 'tailor' | 'set'
  final CreateInvitesConfig? config; // tailor-per-résumé params
  final String? questionSetId; // when source === 'set'
  final List<InviteCandidate> candidates;
  final String? origin; // web origin, for the invite link in emails

  factory CreateInvitesRequest.fromJson(Map<String, dynamic> json) =>
      CreateInvitesRequest(
        mode: _asString(json['mode']),
        role: _asString(json['role']),
        source: _asString(json['source']),
        config: json['config'] is Map
            ? CreateInvitesConfig.fromJson(
                Map<String, dynamic>.from(json['config'] as Map))
            : null,
        questionSetId:
            json['questionSetId'] == null ? null : _asString(json['questionSetId']),
        candidates: _mapList(json['candidates'], InviteCandidate.fromJson),
        origin: json['origin'] == null ? null : _asString(json['origin']),
      );

  Map<String, dynamic> toJson() => {
        'mode': mode,
        'role': role,
        'source': source,
        if (config != null) 'config': config!.toJson(),
        if (questionSetId != null) 'questionSetId': questionSetId,
        'candidates': candidates.map((c) => c.toJson()).toList(),
        if (origin != null) 'origin': origin,
      };
}

/// A created interview row on the result — mirrors the inline
/// `{ id; email; link }` on `CreateInvitesResult.created`.
class CreatedInvite {
  const CreatedInvite({
    required this.id,
    required this.email,
    required this.link,
  });

  final String id;
  final String email;
  final String link;

  factory CreatedInvite.fromJson(Map<String, dynamic> json) => CreatedInvite(
        id: _asString(json['id']),
        email: _asString(json['email']),
        link: _asString(json['link']),
      );

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'link': link};
}

/// Mirrors `CreateInvitesResult`.
class CreateInvitesResult {
  const CreateInvitesResult({
    required this.testId,
    required this.created,
    required this.emailed,
    required this.dryRun,
  });

  final String testId;
  final List<CreatedInvite> created;
  final int emailed; // how many invite emails actually went out
  final bool dryRun; // true while the mailer isn't fully configured

  factory CreateInvitesResult.fromJson(Map<String, dynamic> json) =>
      CreateInvitesResult(
        testId: _asString(json['testId']),
        created: _mapList(json['created'], CreatedInvite.fromJson),
        emailed: _asInt(json['emailed']),
        dryRun: _asBool(json['dryRun']),
      );

  Map<String, dynamic> toJson() => {
        'testId': testId,
        'created': created.map((c) => c.toJson()).toList(),
        'emailed': emailed,
        'dryRun': dryRun,
      };
}

/* ─── Analytics (GET /api/analytics) ──────────────────────────────────────── */

/// `AnalyticsSummary.totals`.
class AnalyticsTotals {
  const AnalyticsTotals({
    required this.created,
    required this.started,
    required this.completed,
    required this.scored,
  });

  final int created;
  final int started;
  final int completed;
  final int scored;

  factory AnalyticsTotals.fromJson(Map<String, dynamic> json) =>
      AnalyticsTotals(
        created: _asInt(json['created']),
        started: _asInt(json['started']),
        completed: _asInt(json['completed']),
        scored: _asInt(json['scored']),
      );

  Map<String, dynamic> toJson() => {
        'created': created,
        'started': started,
        'completed': completed,
        'scored': scored,
      };
}

/// `AnalyticsSummary.scoreDistribution[]` — `{ bucket; count }`.
class ScoreBucket {
  const ScoreBucket({required this.bucket, required this.count});

  final String bucket; // 0-20 … 81-100
  final int count;

  factory ScoreBucket.fromJson(Map<String, dynamic> json) => ScoreBucket(
        bucket: _asString(json['bucket']),
        count: _asInt(json['count']),
      );

  Map<String, dynamic> toJson() => {'bucket': bucket, 'count': count};
}

/// `AnalyticsSummary.kpiAverages[]`.
class KpiAverage {
  const KpiAverage({
    required this.kpiId,
    required this.label,
    required this.average,
    required this.coverage,
  });

  final String kpiId;
  final String label;
  final double average;
  final double coverage;

  factory KpiAverage.fromJson(Map<String, dynamic> json) => KpiAverage(
        kpiId: _asString(json['kpiId']),
        label: _asString(json['label']),
        average: _asDouble(json['average']),
        coverage: _asDouble(json['coverage']),
      );

  Map<String, dynamic> toJson() => {
        'kpiId': kpiId,
        'label': label,
        'average': average,
        'coverage': coverage,
      };
}

/// `AnalyticsSummary.byTrack[]`.
class TrackStat {
  const TrackStat({
    required this.track,
    required this.count,
    required this.averageOverall,
    required this.completionRate,
  });

  final String track; // TrackType
  final int count;
  final double averageOverall;
  final double completionRate;

  factory TrackStat.fromJson(Map<String, dynamic> json) => TrackStat(
        track: _asString(json['track']),
        count: _asInt(json['count']),
        averageOverall: _asDouble(json['averageOverall']),
        completionRate: _asDouble(json['completionRate']),
      );

  Map<String, dynamic> toJson() => {
        'track': track,
        'count': count,
        'averageOverall': averageOverall,
        'completionRate': completionRate,
      };
}

/// `AnalyticsSummary.byRole[]`.
class RoleStat {
  const RoleStat({
    required this.role,
    required this.count,
    required this.averageOverall,
  });

  final String role;
  final int count;
  final double averageOverall;

  factory RoleStat.fromJson(Map<String, dynamic> json) => RoleStat(
        role: _asString(json['role']),
        count: _asInt(json['count']),
        averageOverall: _asDouble(json['averageOverall']),
      );

  Map<String, dynamic> toJson() => {
        'role': role,
        'count': count,
        'averageOverall': averageOverall,
      };
}

/// `AnalyticsSummary.byTemplate[]`.
class TemplateStat {
  const TemplateStat({
    required this.templateId,
    required this.name,
    required this.count,
    required this.averageOverall,
  });

  final String templateId;
  final String name;
  final int count;
  final double averageOverall;

  factory TemplateStat.fromJson(Map<String, dynamic> json) => TemplateStat(
        templateId: _asString(json['templateId']),
        name: _asString(json['name']),
        count: _asInt(json['count']),
        averageOverall: _asDouble(json['averageOverall']),
      );

  Map<String, dynamic> toJson() => {
        'templateId': templateId,
        'name': name,
        'count': count,
        'averageOverall': averageOverall,
      };
}

/// `AnalyticsSummary.trend[]` — by completion day (UTC).
class TrendPoint {
  const TrendPoint({
    required this.date,
    required this.count,
    required this.averageOverall,
  });

  final String date;
  final int count;
  final double averageOverall;

  factory TrendPoint.fromJson(Map<String, dynamic> json) => TrendPoint(
        date: _asString(json['date']),
        count: _asInt(json['count']),
        averageOverall: _asDouble(json['averageOverall']),
      );

  Map<String, dynamic> toJson() => {
        'date': date,
        'count': count,
        'averageOverall': averageOverall,
      };
}

/// `AnalyticsSummary.timeStats`.
class TimeStats {
  const TimeStats({
    required this.avgDurationSeconds,
    required this.avgTimePerQuestionSeconds,
  });

  final double avgDurationSeconds;
  final double avgTimePerQuestionSeconds;

  factory TimeStats.fromJson(Map<String, dynamic> json) => TimeStats(
        avgDurationSeconds: _asDouble(json['avgDurationSeconds']),
        avgTimePerQuestionSeconds:
            _asDouble(json['avgTimePerQuestionSeconds']),
      );

  Map<String, dynamic> toJson() => {
        'avgDurationSeconds': avgDurationSeconds,
        'avgTimePerQuestionSeconds': avgTimePerQuestionSeconds,
      };
}

/// `AnalyticsSummary.recommendationDistribution[]`.
class RecommendationCount {
  const RecommendationCount({
    required this.recommendation,
    required this.count,
  });

  final String recommendation;
  final int count;

  factory RecommendationCount.fromJson(Map<String, dynamic> json) =>
      RecommendationCount(
        recommendation: _asString(json['recommendation']),
        count: _asInt(json['count']),
      );

  Map<String, dynamic> toJson() =>
      {'recommendation': recommendation, 'count': count};
}

/// `AnalyticsSummary.topCandidates[]`.
class TopCandidate {
  const TopCandidate({
    required this.sessionId,
    required this.name,
    required this.overallScore,
    this.role,
  });

  final String sessionId;
  final String name;
  final String? role;
  final double overallScore;

  factory TopCandidate.fromJson(Map<String, dynamic> json) => TopCandidate(
        sessionId: _asString(json['sessionId']),
        name: _asString(json['name']),
        role: json['role'] == null ? null : _asString(json['role']),
        overallScore: _asDouble(json['overallScore']),
      );

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'name': name,
        if (role != null) 'role': role,
        'overallScore': overallScore,
      };
}

/// Mirrors `AnalyticsSummary` — real aggregate metrics computed server-side.
class AnalyticsSummary {
  const AnalyticsSummary({
    required this.totals,
    required this.completionRate,
    required this.averageOverall,
    required this.scoreDistribution,
    required this.kpiAverages,
    required this.byTrack,
    required this.byRole,
    required this.byTemplate,
    required this.trend,
    required this.timeStats,
    required this.recommendationDistribution,
    required this.integrityFlagRate,
    required this.topCandidates,
    required this.generatedAt,
  });

  final AnalyticsTotals totals;
  final double completionRate; // completed / created, 0–1
  final double averageOverall;
  final List<ScoreBucket> scoreDistribution;
  final List<KpiAverage> kpiAverages;
  final List<TrackStat> byTrack;
  final List<RoleStat> byRole;
  final List<TemplateStat> byTemplate;
  final List<TrendPoint> trend;
  final TimeStats timeStats;
  final List<RecommendationCount> recommendationDistribution;
  final double integrityFlagRate;
  final List<TopCandidate> topCandidates;
  final String generatedAt;

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) =>
      AnalyticsSummary(
        totals: AnalyticsTotals.fromJson(
            Map<String, dynamic>.from((json['totals'] as Map?) ?? const {})),
        completionRate: _asDouble(json['completionRate']),
        averageOverall: _asDouble(json['averageOverall']),
        scoreDistribution:
            _mapList(json['scoreDistribution'], ScoreBucket.fromJson),
        kpiAverages: _mapList(json['kpiAverages'], KpiAverage.fromJson),
        byTrack: _mapList(json['byTrack'], TrackStat.fromJson),
        byRole: _mapList(json['byRole'], RoleStat.fromJson),
        byTemplate: _mapList(json['byTemplate'], TemplateStat.fromJson),
        trend: _mapList(json['trend'], TrendPoint.fromJson),
        timeStats: TimeStats.fromJson(
            Map<String, dynamic>.from((json['timeStats'] as Map?) ?? const {})),
        recommendationDistribution: _mapList(
            json['recommendationDistribution'], RecommendationCount.fromJson),
        integrityFlagRate: _asDouble(json['integrityFlagRate']),
        topCandidates: _mapList(json['topCandidates'], TopCandidate.fromJson),
        generatedAt: _asString(json['generatedAt']),
      );

  Map<String, dynamic> toJson() => {
        'totals': totals.toJson(),
        'completionRate': completionRate,
        'averageOverall': averageOverall,
        'scoreDistribution':
            scoreDistribution.map((e) => e.toJson()).toList(),
        'kpiAverages': kpiAverages.map((e) => e.toJson()).toList(),
        'byTrack': byTrack.map((e) => e.toJson()).toList(),
        'byRole': byRole.map((e) => e.toJson()).toList(),
        'byTemplate': byTemplate.map((e) => e.toJson()).toList(),
        'trend': trend.map((e) => e.toJson()).toList(),
        'timeStats': timeStats.toJson(),
        'recommendationDistribution':
            recommendationDistribution.map((e) => e.toJson()).toList(),
        'integrityFlagRate': integrityFlagRate,
        'topCandidates': topCandidates.map((e) => e.toJson()).toList(),
        'generatedAt': generatedAt,
      };
}

/// Query filters for GET /api/analytics — mirrors `AnalyticsFilters`
/// (all optional; omitted = no filter). [toQuery] emits only set fields so it
/// can be handed straight to [BackendClient] query params.
class AnalyticsFilters {
  const AnalyticsFilters({
    this.track,
    this.templateId,
    this.role,
    this.dateFrom,
    this.dateTo,
  });

  final String? track; // TrackType
  final String? templateId;
  final String? role;
  final String? dateFrom; // ISO date/time
  final String? dateTo; // ISO date/time

  Map<String, String> toQuery() => {
        if (track != null) 'track': track!,
        if (templateId != null) 'templateId': templateId!,
        if (role != null) 'role': role!,
        if (dateFrom != null) 'dateFrom': dateFrom!,
        if (dateTo != null) 'dateTo': dateTo!,
      };

  Map<String, dynamic> toJson() => toQuery();
}

/* ─── Video Avatar (POST /sessions/:id/avatar/start) ──────────────────────── */

/// Mirrors `AvatarStartResponse`.
class AvatarStartResponse {
  const AvatarStartResponse({
    required this.conversationUrl,
    required this.totalQuestions,
  });

  final String conversationUrl;
  final int totalQuestions;

  factory AvatarStartResponse.fromJson(Map<String, dynamic> json) =>
      AvatarStartResponse(
        conversationUrl: _asString(json['conversationUrl']),
        totalQuestions: _asInt(json['totalQuestions']),
      );

  Map<String, dynamic> toJson() => {
        'conversationUrl': conversationUrl,
        'totalQuestions': totalQuestions,
      };
}

/* ─── Voice track (GET /api/voices) ───────────────────────────────────────── */

/// A selectable voice for the catalog/preview UI — mirrors `VoiceOption`.
class VoiceOption {
  const VoiceOption({
    required this.id,
    required this.label,
    required this.language,
    required this.engine,
    this.gender,
    this.accent,
    this.description,
    this.sampleUrl,
  });

  final String id; // prebuiltVoiceConfig.voiceName for gemini_live
  final String label;
  final String? gender; // 'male' | 'female' | 'neutral'
  final String language;
  final String? accent;
  final String engine; // VoiceEngine: 'gemini_live' | 'pipeline'
  final String? description;
  final String? sampleUrl;

  factory VoiceOption.fromJson(Map<String, dynamic> json) => VoiceOption(
        id: _asString(json['id']),
        label: _asString(json['label']),
        gender: json['gender'] == null ? null : _asString(json['gender']),
        language: _asString(json['language']),
        accent: json['accent'] == null ? null : _asString(json['accent']),
        engine: _asString(json['engine']),
        description:
            json['description'] == null ? null : _asString(json['description']),
        sampleUrl:
            json['sampleUrl'] == null ? null : _asString(json['sampleUrl']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        if (gender != null) 'gender': gender,
        'language': language,
        if (accent != null) 'accent': accent,
        'engine': engine,
        if (description != null) 'description': description,
        if (sampleUrl != null) 'sampleUrl': sampleUrl,
      };
}

/// A selectable interviewer character — mirrors `InterviewPersona`.
class InterviewPersona {
  const InterviewPersona({
    required this.id,
    required this.name,
    required this.description,
    required this.stylePrompt,
    required this.defaultVoiceId,
    this.speakingRate,
    this.pitch,
  });

  final String id;
  final String name;
  final String description;
  final String stylePrompt; // interviewer character injected into the prompt
  final String defaultVoiceId;
  final double? speakingRate; // pipeline TTS only
  final double? pitch; // pipeline TTS only

  factory InterviewPersona.fromJson(Map<String, dynamic> json) =>
      InterviewPersona(
        id: _asString(json['id']),
        name: _asString(json['name']),
        description: _asString(json['description']),
        stylePrompt: _asString(json['stylePrompt']),
        defaultVoiceId: _asString(json['defaultVoiceId']),
        speakingRate: json['speakingRate'] == null
            ? null
            : _asDouble(json['speakingRate']),
        pitch: json['pitch'] == null ? null : _asDouble(json['pitch']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'stylePrompt': stylePrompt,
        'defaultVoiceId': defaultVoiceId,
        if (speakingRate != null) 'speakingRate': speakingRate,
        if (pitch != null) 'pitch': pitch,
      };
}

/// Mirrors `VoiceCatalog` — the browsable catalog for the recruiter picker.
class VoiceCatalog {
  const VoiceCatalog({required this.voices, required this.personas});

  final List<VoiceOption> voices;
  final List<InterviewPersona> personas;

  factory VoiceCatalog.fromJson(Map<String, dynamic> json) => VoiceCatalog(
        voices: _mapList(json['voices'], VoiceOption.fromJson),
        personas: _mapList(json['personas'], InterviewPersona.fromJson),
      );

  Map<String, dynamic> toJson() => {
        'voices': voices.map((v) => v.toJson()).toList(),
        'personas': personas.map((p) => p.toJson()).toList(),
      };
}

/* ─── App settings status (server key status) ─────────────────────────────── */

/// Mirrors `AppSettingsStatus` — the Gemini key value is NEVER returned, only
/// a masked hint.
class AppSettingsStatus {
  const AppSettingsStatus({
    required this.geminiKeySet,
    required this.source,
    required this.model,
    this.geminiKeyMasked,
  });

  final bool geminiKeySet;
  final String? geminiKeyMasked;
  final String source; // 'saved' | 'env' | 'none'
  final String model;

  factory AppSettingsStatus.fromJson(Map<String, dynamic> json) =>
      AppSettingsStatus(
        geminiKeySet: _asBool(json['geminiKeySet']),
        geminiKeyMasked: json['geminiKeyMasked'] == null
            ? null
            : _asString(json['geminiKeyMasked']),
        source: _asString(json['source']),
        model: _asString(json['model']),
      );

  Map<String, dynamic> toJson() => {
        'geminiKeySet': geminiKeySet,
        if (geminiKeyMasked != null) 'geminiKeyMasked': geminiKeyMasked,
        'source': source,
        'model': model,
      };
}

/* ─── Shared value objects reused across gateways ─────────────────────────── */

/// `CreateSessionRequest.candidate` / `InterviewSession.candidate` — the
/// `{ name; email }` pair (candidate.email is the assignment key).
class CandidateRef {
  const CandidateRef({required this.name, required this.email});

  final String name;
  final String email;

  factory CandidateRef.fromJson(Map<String, dynamic> json) => CandidateRef(
        name: _asString(json['name']),
        email: _asString(json['email']),
      );

  Map<String, dynamic> toJson() => {'name': name, 'email': email};
}

// Note: the `_numMap` helper is exported for gateways that decode
// `Record<string, number>` shapes (e.g. scoring kpiScores/kpiAverages).
Map<String, double> parseNumMap(Object? v) => _numMap(v);
