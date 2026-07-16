// lib/core/backend/gateways/analytics_gateway.dart
//
// Analytics gateway: fetch the aggregate recruiter dashboard metrics. Mirrors
// the website's GET /api/analytics (shared/types.ts: AnalyticsFilters ->
// AnalyticsSummary).
//
// ADDITIVE SCAFFOLDING — not wired into any screen yet.

import '../../security/gateway_config.dart';
import '../backend_client.dart';
import '../dtos.dart';

/// Contract for the aggregate analytics dashboard.
abstract class AnalyticsGateway {
  /// Fetch aggregate metrics, optionally narrowed by [filters]
  /// (all filter fields optional; omitted = no filter).
  Future<AnalyticsSummary> fetch([AnalyticsFilters filters]);
}

/// HTTP implementation backed by [BackendClient].
class HttpAnalyticsGateway implements AnalyticsGateway {
  HttpAnalyticsGateway(this._client);

  final BackendClient _client;

  static const String _path = '/api/analytics';

  @override
  Future<AnalyticsSummary> fetch([
    AnalyticsFilters filters = const AnalyticsFilters(),
  ]) async {
    GatewayConfig.ensureConfigured();
    // TODO(deploy): confirm GET /api/analytics accepts these query params and
    // returns AnalyticsSummary once functions/ is live.
    final query = filters.toQuery();
    final json = await _client.getJson(_path, query: query.isEmpty ? null : query);
    return AnalyticsSummary.fromJson(json);
  }
}
