import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiClient {
  ApiClient({http.Client? httpClient, String? baseUrl})
      : _client = httpClient ?? http.Client(),
        baseUrl = (baseUrl ?? const String.fromEnvironment('API_BASE_URL', defaultValue: 'https://stock-backend-nt1s.onrender.com'))
            .replaceAll(RegExp(r'/+$'), '');

  final http.Client _client;
  final String baseUrl;

  Future<http.Response> _getWithTimeout(Uri uri, {Duration timeout = const Duration(seconds: 60)}) async {
    try {
      return await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw Exception('Request timed out. The server may be starting up (cold start). Please try again in a moment.');
    } catch (e) {
      rethrow;
    }
  }

  Uri _buildUri(String path, [Map<String, dynamic>? queryParameters]) {
    final uri = Uri.parse(baseUrl + path);
    if (queryParameters == null) {
      return uri;
    }
    final filtered = <String, dynamic>{};
    for (final entry in queryParameters.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is bool) {
        filtered[entry.key] = value.toString();
      } else {
        filtered[entry.key] = value.toString();
      }
    }
    return uri.replace(queryParameters: filtered);
  }

  Future<OverviewResponse> fetchOverview({
    required String ticker,
    String? preset,
    String? interval,
    String? startDate,
    String? endDate,
  }) async {
    final response = await _getWithTimeout(
      _buildUri('/overview', {
        'ticker': ticker,
        'preset': preset,
        'interval': interval,
        'start_date': startDate,
        'end_date': endDate,
      }),
    );
    _ensureSuccess(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return OverviewResponse.fromJson(data);
  }

  Future<ForecastResponse> fetchForecast({
    required String ticker,
    required int days,
    bool useLstm = true,
    String? interval,
    String? startDate,
    String? endDate,
    int? window,
    bool sma20 = false,
    bool sma50 = false,
    bool ema12 = false,
    bool ema26 = false,
  }) async {
    final response = await _getWithTimeout(
      _buildUri('/forecast', {
        'ticker': ticker,
        'days': days,
        'use_lstm': useLstm,
        'interval': interval,
        'start_date': startDate,
        'end_date': endDate,
        'window': window,
        'sma_20': sma20,
        'sma_50': sma50,
        'ema_12': ema12,
        'ema_26': ema26,
      }),
    );
    _ensureSuccess(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return ForecastResponse.fromJson(data);
  }

  Future<SentimentResponse?> fetchSentiment({required String ticker, int limit = 10}) async {
    final response = await _getWithTimeout(
      _buildUri('/sentiment', {
        'ticker': ticker,
        'limit': limit,
      }),
    );
    if (response.statusCode == 503 || response.statusCode == 404) {
      return null;
    }
    _ensureSuccess(response);
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return SentimentResponse.fromJson(data);
  }

  Future<List<ModelInfo>> fetchModels() async {
    final response = await _client.get(_buildUri('/models'));
    _ensureSuccess(response);
    return parseModelsResponse(response.body);
  }

  void dispose() {
    _client.close();
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(response.statusCode, response.body);
    }
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiException(statusCode: $statusCode, body: $body)';
}
