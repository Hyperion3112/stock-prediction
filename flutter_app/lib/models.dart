import 'dart:convert';

DateTime _parseDateTime(dynamic value) {
  if (value is DateTime) {
    return value;
  }
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value);
  }
  if (value is String) {
    return DateTime.parse(value);
  }
  throw FormatException('Unsupported date value: $value');
}

class Metadata {
  Metadata({
    required this.ticker,
    this.name,
    this.sector,
    this.industry,
    this.website,
  });

  factory Metadata.fromJson(Map<String, dynamic> json) => Metadata(
        ticker: json['ticker'] as String,
        name: json['name'] as String?,
        sector: json['sector'] as String?,
        industry: json['industry'] as String?,
        website: json['website'] as String?,
      );

  final String ticker;
  final String? name;
  final String? sector;
  final String? industry;
  final String? website;
}

class OverviewMetrics {
  OverviewMetrics({
    required this.latestClose,
    required this.pctChange,
    this.latestVolume,
    this.rangeHigh,
    this.rangeLow,
    required this.dataPoints,
  });

  factory OverviewMetrics.fromJson(Map<String, dynamic> json) => OverviewMetrics(
        latestClose: (json['latest_close'] as num).toDouble(),
        pctChange: (json['pct_change'] as num).toDouble(),
        latestVolume: (json['latest_volume'] as num?)?.toDouble(),
        rangeHigh: (json['range_high'] as num?)?.toDouble(),
        rangeLow: (json['range_low'] as num?)?.toDouble(),
        dataPoints: json['data_points'] as int,
      );

  final double latestClose;
  final double pctChange;
  final double? latestVolume;
  final double? rangeHigh;
  final double? rangeLow;
  final int dataPoints;
}

class DayHighlight {
  DayHighlight({required this.date, required this.percentChange});

  factory DayHighlight.fromJson(Map<String, dynamic> json) => DayHighlight(
        date: _parseDateTime(json['date']),
        percentChange: (json['percent_change'] as num).toDouble(),
      );

  final DateTime date;
  final double percentChange;
}

class OverviewHighlights {
  OverviewHighlights({this.bestDay, this.worstDay, this.annualizedVolatility});

  factory OverviewHighlights.fromJson(Map<String, dynamic> json) => OverviewHighlights(
        bestDay: json['best_day'] == null
            ? null
            : DayHighlight.fromJson(json['best_day'] as Map<String, dynamic>),
        worstDay: json['worst_day'] == null
            ? null
            : DayHighlight.fromJson(json['worst_day'] as Map<String, dynamic>),
        annualizedVolatility: (json['annualized_volatility'] as num?)?.toDouble(),
      );

  final DayHighlight? bestDay;
  final DayHighlight? worstDay;
  final double? annualizedVolatility;
}

class PricePoint {
  PricePoint({required this.date, required this.close});

  factory PricePoint.fromJson(Map<String, dynamic> json) => PricePoint(
        date: _parseDateTime(json['date']),
        close: (json['close'] as num).toDouble(),
      );

  final DateTime date;
  final double close;
}

class ForecastPoint {
  ForecastPoint({required this.date, required this.value});

  factory ForecastPoint.fromJson(Map<String, dynamic> json) => ForecastPoint(
        date: _parseDateTime(json['date']),
        value: (json['value'] as num).toDouble(),
      );

  final DateTime date;
  final double value;
}

class TechnicalIndicator {
  TechnicalIndicator({required this.date, required this.value});

  factory TechnicalIndicator.fromJson(Map<String, dynamic> json) => TechnicalIndicator(
        date: _parseDateTime(json['date']),
        value: (json['value'] as num).toDouble(),
      );

  final DateTime date;
  final double value;
}

class TechnicalIndicators {
  TechnicalIndicators({
    this.sma20,
    this.sma50,
    this.ema12,
    this.ema26,
  });

  factory TechnicalIndicators.fromJson(Map<String, dynamic> json) => TechnicalIndicators(
        sma20: json['sma_20'] == null
            ? null
            : (json['sma_20'] as List<dynamic>)
                .map((item) => TechnicalIndicator.fromJson(item as Map<String, dynamic>))
                .toList(),
        sma50: json['sma_50'] == null
            ? null
            : (json['sma_50'] as List<dynamic>)
                .map((item) => TechnicalIndicator.fromJson(item as Map<String, dynamic>))
                .toList(),
        ema12: json['ema_12'] == null
            ? null
            : (json['ema_12'] as List<dynamic>)
                .map((item) => TechnicalIndicator.fromJson(item as Map<String, dynamic>))
                .toList(),
        ema26: json['ema_26'] == null
            ? null
            : (json['ema_26'] as List<dynamic>)
                .map((item) => TechnicalIndicator.fromJson(item as Map<String, dynamic>))
                .toList(),
      );

  final List<TechnicalIndicator>? sma20;
  final List<TechnicalIndicator>? sma50;
  final List<TechnicalIndicator>? ema12;
  final List<TechnicalIndicator>? ema26;
}

class OverviewResponse {
  OverviewResponse({
    required this.ticker,
    required this.metadata,
    required this.metrics,
    required this.highlights,
    required this.history,
  });

  factory OverviewResponse.fromJson(Map<String, dynamic> json) => OverviewResponse(
        ticker: json['ticker'] as String,
        metadata: Metadata.fromJson(json['metadata'] as Map<String, dynamic>),
        metrics: OverviewMetrics.fromJson(json['metrics'] as Map<String, dynamic>),
        highlights: OverviewHighlights.fromJson(json['highlights'] as Map<String, dynamic>),
        history: (json['history'] as List<dynamic>)
            .map((item) => PricePoint.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  final String ticker;
  final Metadata metadata;
  final OverviewMetrics metrics;
  final OverviewHighlights highlights;
  final List<PricePoint> history;
}

class ForecastResponse {
  ForecastResponse({
    required this.ticker,
    required this.source,
    required this.forecast,
    required this.history,
    this.indicators,
    this.note,
  });

  factory ForecastResponse.fromJson(Map<String, dynamic> json) => ForecastResponse(
        ticker: json['ticker'] as String,
        source: json['source'] as String,
        forecast: (json['forecast'] as List<dynamic>)
            .map((item) => ForecastPoint.fromJson(item as Map<String, dynamic>))
            .toList(),
        history: (json['history'] as List<dynamic>)
            .map((item) => PricePoint.fromJson(item as Map<String, dynamic>))
            .toList(),
        indicators: json['indicators'] == null
            ? null
            : TechnicalIndicators.fromJson(json['indicators'] as Map<String, dynamic>),
        note: json['note'] as String?,
      );

  final String ticker;
  final String source;
  final List<ForecastPoint> forecast;
  final List<PricePoint> history;
  final TechnicalIndicators? indicators;
  final String? note;
}

class SentimentRecord {
  SentimentRecord({
    required this.headline,
    required this.sentiment,
    required this.score,
    this.publisher,
    this.summary,
    this.link,
    this.published,
  });

  factory SentimentRecord.fromJson(Map<String, dynamic> json) => SentimentRecord(
        headline: json['headline'] as String,
        sentiment: json['sentiment'] as String,
        score: (json['score'] as num).toDouble(),
        publisher: json['publisher'] as String?,
        summary: json['summary'] as String?,
        link: json['link'] as String?,
        published: json['published'] == null ? null : _parseDateTime(json['published']),
      );

  final String headline;
  final String sentiment;
  final double score;
  final String? publisher;
  final String? summary;
  final String? link;
  final DateTime? published;
}

class SentimentSummary {
  SentimentSummary({
    required this.total,
    this.averageScore,
    required this.positive,
    required this.neutral,
    required this.negative,
    this.dominantSentiment,
  });

  factory SentimentSummary.fromJson(Map<String, dynamic> json) => SentimentSummary(
        total: json['total'] as int,
        averageScore: (json['average_score'] as num?)?.toDouble(),
        positive: json['positive'] as int? ?? 0,
        neutral: json['neutral'] as int? ?? 0,
        negative: json['negative'] as int? ?? 0,
        dominantSentiment: json['dominant_sentiment'] as String?,
      );

  final int total;
  final double? averageScore;
  final int positive;
  final int neutral;
  final int negative;
  final String? dominantSentiment;
}

class SentimentResponse {
  SentimentResponse({
    required this.ticker,
    required this.summary,
    required this.records,
  });

  factory SentimentResponse.fromJson(Map<String, dynamic> json) => SentimentResponse(
        ticker: json['ticker'] as String,
        summary: SentimentSummary.fromJson(json['summary'] as Map<String, dynamic>),
        records: (json['records'] as List<dynamic>)
            .map((item) => SentimentRecord.fromJson(item as Map<String, dynamic>))
            .toList(),
      );

  final String ticker;
  final SentimentSummary summary;
  final List<SentimentRecord> records;
}

class ModelInfo {
  ModelInfo({required this.ticker, required this.modelPath, required this.scalerPath});

  factory ModelInfo.fromJson(Map<String, dynamic> json) => ModelInfo(
        ticker: json['ticker'] as String,
        modelPath: json['model_path'] as String,
        scalerPath: json['scaler_path'] as String,
      );

  final String ticker;
  final String modelPath;
  final String scalerPath;
}

List<ModelInfo> parseModelsResponse(String body) {
  final data = jsonDecode(body) as List<dynamic>;
  return data
      .map((item) => ModelInfo.fromJson(item as Map<String, dynamic>))
      .toList();
}
