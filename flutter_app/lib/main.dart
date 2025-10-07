import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'api_client.dart';
import 'models.dart';

extension _ColorAlpha on Color {
  Color withAlphaFraction(double opacity) => withValues(alpha: opacity.clamp(0, 1));
}

String _formatAxisTick(double value) {
  final absValue = value.abs();
  if (absValue >= 1000000) {
    return NumberFormat.compact().format(value);
  }
  if (absValue >= 1000) {
    return NumberFormat.compact().format(value);
  }
  if (absValue >= 100) {
    return value.toStringAsFixed(0);
  }
  if (absValue >= 10) {
    return value.toStringAsFixed(1);
  }
  if (absValue >= 1) {
    return value.toStringAsFixed(2);
  }
  return value.toStringAsFixed(3);
}

List<double> _generateAxisTicks(double min, double max, {int desiredCount = 4}) {
  if (!min.isFinite || !max.isFinite || desiredCount <= 1) {
    return [min];
  }
  if ((max - min).abs() < 1e-6) {
    final baseline = max == 0 ? 1 : max.abs();
    return [min - baseline / 2, min, min + baseline / 2, min + baseline];
  }
  final range = max - min;
  final rawStep = range / (desiredCount - 1);
  final magnitude = pow(10, (log(rawStep) / ln10).floor()).toDouble();
  final step = (rawStep / magnitude).ceil() * magnitude;
  final start = (min / magnitude).floor() * magnitude;
  final ticks = <double>[];
  var current = start;
  // Prevent infinite loops by limiting iterations.
  for (int i = 0; i < desiredCount + 4; i++) {
    if (current > max + step) break;
    if (current >= min - step * 0.5) {
      ticks.add(current);
    }
    current += step;
  }
  if (ticks.isEmpty) {
    ticks.addAll([min, min + step, max]);
  }
  return ticks;
}

bool _isApproximately(double value, double target, double tolerance) {
  return (value - target).abs() <= tolerance;
}

void main() {
  runApp(const StockInsightsApp());
}

class StockInsightsApp extends StatelessWidget {
  const StockInsightsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Stock Insights',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff6366f1),
          brightness: Brightness.dark,
        ).copyWith(
          surface: const Color(0xff070b16),
        ),
        fontFamily: 'Inter',
        scaffoldBackgroundColor: Colors.transparent,
        textTheme: Theme.of(context).textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          foregroundColor: Colors.white,
          titleTextStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 20),
        ),
        dividerColor: Colors.white12,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardParams {
  DashboardParams({
    required this.ticker,
    required this.interval,
    required this.preset,
    required this.days,
    required this.includeSentiment,
  });

  final String ticker;
  final String interval;
  final String preset;
  final int days;
  final bool includeSentiment;

  DashboardParams copyWith({
    String? ticker,
    String? interval,
    String? preset,
    int? days,
    bool? includeSentiment,
  }) {
    return DashboardParams(
      ticker: ticker ?? this.ticker,
      interval: interval ?? this.interval,
      preset: preset ?? this.preset,
      days: days ?? this.days,
      includeSentiment: includeSentiment ?? this.includeSentiment,
    );
  }
}

class DashboardState {
  DashboardState({
    required this.params,
    this.overview,
    this.forecast,
    this.sentiment,
    this.models = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  final DashboardParams params;
  final OverviewResponse? overview;
  final ForecastResponse? forecast;
  final SentimentResponse? sentiment;
  final List<ModelInfo> models;
  final bool isLoading;
  final String? errorMessage;

  bool get hasSavedLstmForTicker =>
      models.any((model) => model.ticker.toUpperCase() == params.ticker.toUpperCase());

  DashboardState copyWith({
    DashboardParams? params,
    OverviewResponse? overview,
    ForecastResponse? forecast,
    SentimentResponse? sentiment,
    List<ModelInfo>? models,
    bool? isLoading,
    Object? errorMessage = _sentinel,
  }) {
    final String? resolvedErrorMessage =
        identical(errorMessage, _sentinel) ? this.errorMessage : errorMessage as String?;

    return DashboardState(
      params: params ?? this.params,
      overview: overview ?? this.overview,
      forecast: forecast ?? this.forecast,
      sentiment: sentiment ?? this.sentiment,
      models: models ?? this.models,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: resolvedErrorMessage,
    );
  }
}

const _sentinel = Object();

String _formatErrorMessage(Object error) {
  if (error is ApiException) {
    try {
      final decoded = jsonDecode(error.body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is Map<String, dynamic>) {
          final message = detail['message'] ?? detail['detail'];
          if (message is String && message.isNotEmpty) {
            return message;
          }
        } else if (detail is String && detail.isNotEmpty) {
          if (error.statusCode == 404 && detail.contains('No price data')) {
            return 'No price data is available for that configuration. Try a shorter preset or a less granular interval.';
          }
          return detail;
        }
      }
    } catch (_) {
      // Ignore JSON decoding issues and fall back to status-based messages.
    }

    if (error.statusCode == 404) {
      return 'We couldn\'t find data for that configuration. Try a shorter preset or a less granular interval.';
    }
    if (error.statusCode >= 500) {
      return 'The server encountered an issue (${error.statusCode}). Please try again shortly.';
    }
    return 'Request failed (${error.statusCode}). Please adjust the inputs and try again.';
  }
  return 'Unexpected error: $error';
}

class DashboardController extends ChangeNotifier {
  DashboardController(this._client)
      : _state = DashboardState(
          params: DashboardParams(
            ticker: 'AAPL',
            interval: '1d',
            preset: '6M',
            days: 30,
            includeSentiment: true,
          ),
        );

  final ApiClient _client;
  DashboardState _state;

  DashboardState get state => _state;

  Future<void> initialize() async {
    try {
      final models = await _client.fetchModels();
      _state = _state.copyWith(models: models);
      notifyListeners();
    } catch (err) {
      _state = _state.copyWith(errorMessage: err.toString());
      notifyListeners();
    }
    await loadData(force: true);
  }

  Future<void> loadData({bool force = false}) async {
    if (_state.isLoading) return;
    _state = _state.copyWith(isLoading: true, errorMessage: null);
    notifyListeners();

    final params = _state.params;
    try {
      final overview = await _client.fetchOverview(
        ticker: params.ticker,
        preset: params.preset,
        interval: params.interval,
      );
      final forecast = await _client.fetchForecast(
        ticker: params.ticker,
        days: params.days,
        interval: params.interval,
        useLstm: true,
      );
      SentimentResponse? sentiment;
      if (params.includeSentiment) {
        sentiment = await _client.fetchSentiment(ticker: params.ticker);
      }

      _state = _state.copyWith(
        overview: overview,
        forecast: forecast,
        sentiment: sentiment,
        isLoading: false,
        errorMessage: null,
      );
    } catch (err) {
      _state = _state.copyWith(isLoading: false, errorMessage: _formatErrorMessage(err));
    }
    notifyListeners();
  }

  void updateParams(DashboardParams params) {
    _state = _state.copyWith(params: params);
    notifyListeners();
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DashboardController controller;
  late final TextEditingController tickerController;
  String preset = '6M';
  String interval = '1d';
  int horizon = 30;
  bool includeSentiment = true;

  @override
  void initState() {
    super.initState();
    controller = DashboardController(ApiClient());
    tickerController = TextEditingController(text: 'AAPL');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.initialize();
    });
  }

  @override
  void dispose() {
    tickerController.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).padding;
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        final accent = _tickerAccentColor(state.params.ticker);
        return Scaffold(
          extendBodyBehindAppBar: true,
          body: Stack(
            children: [
              _AnimatedGradientBackground(accentColor: accent),
              SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, max(insets.bottom, 16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DashboardHeader(
                        state: state,
                        accentColor: accent,
                      ),
                      const SizedBox(height: 16),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        child: state.isLoading
                            ? const LinearProgressIndicator(
                                minHeight: 3,
                                backgroundColor: Colors.white12,
                              )
                            : const SizedBox(height: 3),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: CustomScrollView(
                          physics: const BouncingScrollPhysics(),
                          slivers: [
                            SliverToBoxAdapter(
                              child: _buildControls(context, state, accent),
                            ),
                            if (state.errorMessage != null)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: GlassContainer(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            state.errorMessage!,
                                            style: const TextStyle(color: Colors.orangeAccent),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            SliverToBoxAdapter(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 500),
                                transitionBuilder: _sectionTransitionBuilder,
                                child: state.overview == null
                                    ? const SizedBox.shrink()
                                    : _OverviewSection(
                                        key: ValueKey('overview-${state.overview!.metadata.ticker}-${state.overview!.metrics.latestClose}'),
                                        overview: state.overview!,
                                        accentColor: accent,
                                      ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 500),
                                transitionBuilder: _sectionTransitionBuilder,
                                child: state.forecast == null
                                    ? const SizedBox.shrink()
                                    : _ForecastSection(
                                        key: ValueKey('forecast-${state.forecast!.ticker}-${state.forecast!.forecast.length}'),
                                        forecast: state.forecast!,
                                        overview: state.overview,
                                        accentColor: accent,
                                      ),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 500),
                                transitionBuilder: _sectionTransitionBuilder,
                                child: state.sentiment == null
                                    ? const SizedBox.shrink()
                                    : _SentimentSection(
                                        key: ValueKey('sentiment-${state.sentiment!.ticker}-${state.sentiment!.summary.total}'),
                                        sentiment: state.sentiment!,
                                        accentColor: accent,
                                      ),
                              ),
                            ),
                            const SliverToBoxAdapter(child: SizedBox(height: 24)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static Widget _sectionTransitionBuilder(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(curved),
        child: child,
      ),
    );
  }

  Color _tickerAccentColor(String ticker) {
    final normalized = ticker.isEmpty ? 0 : ticker.codeUnitAt(0) + ticker.codeUnitAt(ticker.length - 1);
    final hue = (normalized * 17) % 360;
    return HSLColor.fromAHSL(1, hue.toDouble(), 0.55, 0.55).toColor();
  }

  Widget _buildControls(BuildContext context, DashboardState state, Color accentColor) {
  const availablePresets = ['1M', '3M', '6M', '1Y', '2Y', '5Y'];
  const availableIntervals = ['1d', '1wk', '1mo', '1h', '30m'];
    return GlassContainer(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 860;
          final double fieldWidth = isCompact ? constraints.maxWidth : 200;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Configure analysis',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: state.isLoading ? 0.6 : 1,
                    child: Text(
                      'Ticker ${state.params.ticker}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 20,
                runSpacing: 18,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: TextField(
                      controller: tickerController,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(letterSpacing: 1.5),
                      decoration: _glassFieldDecoration('Ticker', hint: 'AAPL'),
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('preset-$preset'),
                      initialValue: preset,
                      icon: const Icon(Icons.expand_more, color: Colors.white70),
                      dropdownColor: const Color(0xff111c2d),
                      decoration: _glassFieldDecoration('Date range'),
                      items: [
                        for (final item in availablePresets)
                          DropdownMenuItem(value: item, child: Text(item)),
                      ],
                      onChanged: (value) => setState(() => preset = value ?? preset),
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('interval-$interval'),
                      initialValue: interval,
                      icon: const Icon(Icons.expand_more, color: Colors.white70),
                      dropdownColor: const Color(0xff111c2d),
                      decoration: _glassFieldDecoration('Interval'),
                      items: [
                        for (final item in availableIntervals)
                          DropdownMenuItem(value: item, child: Text(item)),
                      ],
                      onChanged: (value) => setState(() => interval = value ?? interval),
                    ),
                  ),
                  SizedBox(
                    width: isCompact ? constraints.maxWidth : 260,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Forecast horizon', style: TextStyle(color: Colors.white70)),
                            Text('$horizon days', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                            overlayShape: SliderComponentShape.noOverlay,
                            activeTrackColor: accentColor,
                            inactiveTrackColor: Colors.white24,
                            thumbColor: accentColor,
                          ),
                          child: Slider(
                            min: 7,
                            max: 90,
                            divisions: 12,
                            value: horizon.toDouble(),
                            onChanged: (value) => setState(() => horizon = value.round()),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilterChip(
                          showCheckmark: false,
                          label: const Text('Include sentiment'),
                          labelStyle: const TextStyle(color: Colors.white),
                          selectedColor: accentColor.withAlphaFraction(0.25),
                          backgroundColor: Colors.white.withAlphaFraction(0.05),
                          side: BorderSide(color: (includeSentiment ? accentColor : Colors.white24).withAlphaFraction(0.7)),
                          selected: includeSentiment,
                          onSelected: (value) => setState(() => includeSentiment = value),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: state.isLoading
                        ? null
                        : () {
                            final params = state.params.copyWith(
                              ticker: tickerController.text.trim().toUpperCase(),
                              preset: preset,
                              interval: interval,
                              days: horizon,
                              includeSentiment: includeSentiment,
                            );
                            controller.updateParams(params);
                            scheduleMicrotask(() => controller.loadData());
                          },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Refresh insights'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  InputDecoration _glassFieldDecoration(String label, {String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
  fillColor: Colors.white.withAlphaFraction(0.05),
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white54),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
  borderSide: BorderSide(color: Colors.white.withAlphaFraction(0.15)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
  borderSide: BorderSide(color: Colors.white.withAlphaFraction(0.12)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
  borderSide: BorderSide(color: Colors.white.withAlphaFraction(0.4)),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    );
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({super.key, required this.overview, required this.accentColor});

  final OverviewResponse overview;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final metrics = overview.metrics;
    final highlights = overview.highlights;
    final currencyFormat = NumberFormat.simpleCurrency();
    final history = overview.history.take(120).toList();

    final subtitleParts = [
      overview.metadata.ticker,
      if ((overview.metadata.sector ?? '').isNotEmpty) overview.metadata.sector!,
      if ((overview.metadata.industry ?? '').isNotEmpty) overview.metadata.industry!,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: overview.metadata.name ?? overview.metadata.ticker,
          subtitle: subtitleParts.isEmpty ? 'Insights snapshot' : subtitleParts.join(' • '),
          accentColor: accentColor,
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 16.0;
            final cards = <Widget>[
              AnimatedMetricCard(
                title: 'Latest close',
                value: currencyFormat.format(metrics.latestClose),
                subtitle: '${metrics.pctChange.toStringAsFixed(2)}% vs previous close',
                isPositive: metrics.pctChange >= 0,
                accentColor: accentColor,
                icon: Icons.stacked_line_chart_rounded,
              ),
              AnimatedMetricCard(
                title: 'Volume',
                value: metrics.latestVolume == null
                    ? '—'
                    : NumberFormat.compact().format(metrics.latestVolume),
                subtitle: 'Data points ${metrics.dataPoints}',
                accentColor: accentColor,
                icon: Icons.pie_chart_rounded,
              ),
              AnimatedMetricCard(
                title: 'Range',
                value:
                    '${metrics.rangeLow == null ? '—' : currencyFormat.format(metrics.rangeLow)} — ${metrics.rangeHigh == null ? '—' : currencyFormat.format(metrics.rangeHigh)}',
                subtitle: 'Rolling ${overview.history.length} samples',
                accentColor: accentColor,
                icon: Icons.auto_graph_rounded,
              ),
            ];

            if (highlights.annualizedVolatility != null) {
              cards.add(
                AnimatedMetricCard(
                  title: 'Annualized volatility',
                  value: '${highlights.annualizedVolatility!.toStringAsFixed(1)}%',
                  subtitle: 'Trailing 30 trading days',
                  accentColor: accentColor,
                  icon: Icons.speed_rounded,
                ),
              );
            }

            final count = cards.length;
            final availableWidth = max(constraints.maxWidth, 1.0);
            final targetWidth = (availableWidth - spacing * (count - 1)) / count;
            final cardWidth = max(220.0, targetWidth);

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 4),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: availableWidth),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i > 0) const SizedBox(width: spacing),
                      SizedBox(width: cardWidth, child: cards[i]),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        GlassContainer(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: SizedBox(
            height: 280,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              transitionBuilder: SectionTransitions.chart,
              child: history.isEmpty
                  ? const _EmptyChartState(message: 'No price history available')
                  : LineChart(
                      key: ValueKey('history-${history.length}-${history.last.close}'),
                      _buildHistoryChart(history, accentColor),
                    ),
            ),
          ),
        ),
        if (highlights.bestDay != null || highlights.worstDay != null) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (highlights.bestDay != null)
                _HighlightChip(
                  label: 'Best day',
                  date: highlights.bestDay!.date,
                  percent: highlights.bestDay!.percentChange,
                  accentColor: Colors.greenAccent,
                ),
              if (highlights.worstDay != null)
                _HighlightChip(
                  label: 'Worst day',
                  date: highlights.worstDay!.date,
                  percent: highlights.worstDay!.percentChange,
                  accentColor: Colors.orangeAccent,
                ),
            ],
          ),
        ],
      ],
    );
  }

  LineChartData _buildHistoryChart(List<PricePoint> history, Color accent) {
    final minDate = history.first.date;
    final maxDate = history.last.date;
    final minValue = history.map((p) => p.close).reduce(min);
    final maxValue = history.map((p) => p.close).reduce(max);
    final diffX = maxDate.millisecondsSinceEpoch - minDate.millisecondsSinceEpoch;
    final diffY = maxValue - minValue;
    final xTicks = _generateAxisTicks(
      minDate.millisecondsSinceEpoch.toDouble(),
      maxDate.millisecondsSinceEpoch.toDouble(),
      desiredCount: 4,
    );
    final intervalX = xTicks.length > 1 ? (xTicks[1] - xTicks[0]).abs() : (diffX <= 0 ? 1.0 : diffX.toDouble());
    final yTicks = _generateAxisTicks(minValue, maxValue, desiredCount: 4);
    final yStep = yTicks.length > 1 ? (yTicks[1] - yTicks[0]).abs() : (diffY == 0 ? (maxValue == 0 ? 1 : maxValue.abs()) : diffY.abs());
    final yTolerance = max(yStep.abs() * 0.35, 0.0001);
    final safeIntervalY = yStep == 0 ? 1.0 : yStep;
    final dateFormat = DateFormat.MMMd();
    final currencyFormat = NumberFormat.simpleCurrency();

    return LineChartData(
      lineTouchData: LineTouchData(
        handleBuiltInTouches: true,
        touchSpotThreshold: 18,
        getTouchedSpotIndicator: (bar, indexes) {
          return indexes
              .map(
                (index) => TouchedSpotIndicatorData(
                  FlLine(color: Colors.white.withAlphaFraction(0.18), strokeWidth: 1.2),
                  FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, idx) => FlDotCirclePainter(
                      radius: 4.5,
                      color: Colors.white,
                      strokeWidth: 2.5,
                      strokeColor: accent,
                    ),
                  ),
                ),
              )
              .toList();
        },
        touchTooltipData: LineTouchTooltipData(
          tooltipBgColor: const Color(0xff0d1220).withAlphaFraction(0.92),
          tooltipRoundedRadius: 14,
          tooltipPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItems: (spots) {
            return spots.map((spot) {
              final date = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
              return LineTooltipItem(
                '${dateFormat.format(date)}\n${currencyFormat.format(spot.y)}',
                const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
              );
            }).toList();
          },
        ),
      ),
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(color: Colors.white.withAlphaFraction(0.2)),
          left: BorderSide(color: Colors.white.withAlphaFraction(0.2)),
          right: const BorderSide(color: Colors.transparent),
          top: const BorderSide(color: Colors.transparent),
        ),
      ),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: intervalX <= 0 ? 1.0 : intervalX,
            getTitlesWidget: (value, meta) {
              final isDesiredTick = xTicks.any((tick) => _isApproximately(value, tick, intervalX * 0.35));
              if (!isDesiredTick) {
                return const SizedBox.shrink();
              }
              final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  DateFormat.Md().format(date),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 48,
            interval: safeIntervalY.toDouble(),
            getTitlesWidget: (value, meta) {
              final showTick = yTicks.any((tick) => _isApproximately(value, tick, yTolerance));
              if (!showTick) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _formatAxisTick(value),
                  style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.2),
                ),
              );
            },
          ),
        ),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          isCurved: true,
          color: accent,
          barWidth: 3,
          gradient: LinearGradient(
            colors: [accent, Color.lerp(accent, Colors.white, 0.4)!],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          spots: [
            for (final point in history)
              FlSpot(point.date.millisecondsSinceEpoch.toDouble(), point.close),
          ],
          dotData: const FlDotData(show: false),
        ),
      ],
    );
  }
}

class _ForecastSection extends StatelessWidget {
  const _ForecastSection({super.key, required this.forecast, required this.overview, required this.accentColor});

  final ForecastResponse forecast;
  final OverviewResponse? overview;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.simpleCurrency();
    final history = forecast.history.take(120).toList();
    final latest = forecast.forecast.isNotEmpty
        ? forecast.forecast.last.value
        : (history.isNotEmpty ? history.last.close : 0.0);
    final origin = history.isNotEmpty ? history.last.close : (latest == 0 ? 1 : latest);
    final deltaValue = origin == 0 ? 0.0 : ((latest - origin) / origin * 100);
    final deltaText = deltaValue.isFinite ? deltaValue.toStringAsFixed(2) : '0';
    final modelColor = Color.lerp(accentColor, Colors.orangeAccent, 0.35)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        SectionHeading(
          title: 'Forecast',
          subtitle: 'Powered by ${forecast.source.toUpperCase()}',
          accentColor: accentColor,
        ),
        const SizedBox(height: 20),
        if (forecast.note != null && forecast.note!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: GlassContainer(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              borderRadius: 18,
              showShadow: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, color: Colors.orangeAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      forecast.note!,
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 12.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        _HorizontalMetricRow(
          cards: [
            AnimatedMetricCard(
              title: 'Target price',
              value: currency.format(latest),
              subtitle: '$deltaText% vs recent close',
              isPositive: deltaValue >= 0,
              accentColor: modelColor,
              icon: Icons.trending_up_rounded,
            ),
            AnimatedMetricCard(
              title: 'Forecast horizon',
              value: '${forecast.forecast.length} days',
              subtitle: overview?.metadata.name ?? forecast.ticker,
              accentColor: modelColor,
              icon: Icons.update_rounded,
            ),
          ],
        ),
        const SizedBox(height: 20),
        GlassContainer(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: SizedBox(
            height: 280,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 600),
              transitionBuilder: SectionTransitions.chart,
              child: (history.isEmpty && forecast.forecast.isEmpty)
                  ? const _EmptyChartState(message: 'Forecast data not available yet')
                  : LineChart(
                      key: ValueKey('forecast-${forecast.ticker}-${forecast.forecast.length}-${history.length}'),
                      _buildForecastChart(history, forecast.forecast, accentColor, modelColor),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  LineChartData _buildForecastChart(
    List<PricePoint> history,
    List<ForecastPoint> forecastPoints,
    Color accent,
    Color modelColor,
  ) {
    final baseData = [...history.map((e) => FlSpot(e.date.millisecondsSinceEpoch.toDouble(), e.close))];
    final forecastData = [...forecastPoints.map((e) => FlSpot(e.date.millisecondsSinceEpoch.toDouble(), e.value))];
    if (forecastData.isNotEmpty && baseData.isNotEmpty) {
      final anchor = baseData.last;
      if ((forecastData.first.x - anchor.x).abs() > 0.5) {
        forecastData.insert(0, anchor);
      } else {
        forecastData[0] = FlSpot(anchor.x, forecastData.first.y);
      }
    }
    final historyLookup = {for (final spot in baseData) spot.x: spot.y};
    final forecastLookup = {for (final spot in forecastData) spot.x: spot.y};

    double? nearestValue(Map<double, double> source, double target, {double tolerance = 60000}) {
      double? result;
      var bestDistance = tolerance;
      source.forEach((key, value) {
        final distance = (key - target).abs();
        if (distance <= bestDistance) {
          bestDistance = distance;
          result = value;
        }
      });
      return result;
    }

    final allValues = [...baseData, ...forecastData];
    if (allValues.isEmpty) {
      return LineChartData(lineBarsData: []);
    }
    final minX = allValues.first.x;
    final maxX = allValues.last.x;
    final minY = allValues.map((e) => e.y).reduce(min);
    final maxY = allValues.map((e) => e.y).reduce(max);
  final diffX = maxX - minX;
  final xTicks = _generateAxisTicks(minX, maxX, desiredCount: 4);
  final intervalX = xTicks.length > 1 ? (xTicks[1] - xTicks[0]).abs() : (diffX <= 0 ? 1.0 : diffX);
  final diffY = maxY - minY;
  final yTicks = _generateAxisTicks(minY, maxY, desiredCount: 4);
  final yStep = yTicks.length > 1 ? (yTicks[1] - yTicks[0]).abs() : (diffY == 0 ? (maxY == 0 ? 1 : maxY.abs()) : diffY.abs());
  final yTolerance = max(yStep.abs() * 0.35, 0.0001);
  final safeIntervalY = yStep == 0 ? 1.0 : yStep;
    final dateFormat = DateFormat.MMMd();
    final currencyFormat = NumberFormat.simpleCurrency();

    return LineChartData(
      lineTouchData: LineTouchData(
        handleBuiltInTouches: true,
        touchSpotThreshold: 18,
        getTouchedSpotIndicator: (bar, indexes) {
          return indexes
              .map(
                (index) => TouchedSpotIndicatorData(
                  FlLine(color: Colors.white.withAlphaFraction(0.16), strokeWidth: 1.1),
                  FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, idx) {
                      final color = (barData.gradient?.colors.first ?? barData.color ?? Colors.white);
                      return FlDotCirclePainter(
                        radius: 4.5,
                        color: Colors.white,
                        strokeWidth: 2.5,
                        strokeColor: color,
                      );
                    },
                  ),
                ),
              )
              .toList();
        },
        touchTooltipData: LineTouchTooltipData(
          tooltipBgColor: const Color(0xff0d1220).withAlphaFraction(0.92),
          tooltipRoundedRadius: 14,
          tooltipPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItems: (spots) {
            if (spots.isEmpty) return [];
            final touchedX = spots.first.x;
            final date = DateTime.fromMillisecondsSinceEpoch(touchedX.toInt());

            double? historyValue;
            double? forecastValue;
            for (final spot in spots) {
              if (spot.barIndex == 0) {
                historyValue = spot.y;
              } else if (spot.barIndex == 1) {
                forecastValue = spot.y;
              }
            }

            historyValue ??= nearestValue(historyLookup, touchedX);
            forecastValue ??= nearestValue(forecastLookup, touchedX);

            final children = <TextSpan>[];
            if (historyValue != null) {
              children.add(
                TextSpan(
                  text: 'Actual: ${currencyFormat.format(historyValue)}\n',
                  style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
                ),
              );
            }
            if (forecastValue != null) {
              children.add(
                TextSpan(
                  text: 'Forecast: ${currencyFormat.format(forecastValue)}',
                  style: TextStyle(color: modelColor, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
                ),
              );
            }
            return [
              LineTooltipItem(
                '${dateFormat.format(date)}\n',
                const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
                children: children,
              ),
            ];
          },
        ),
      ),
      minX: minX,
      maxX: maxX,
      minY: minY == maxY ? minY * 0.95 : minY * 0.98,
      maxY: minY == maxY ? maxY * 1.05 : maxY * 1.02,
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(
        show: true,
        border: Border(
          bottom: BorderSide(color: Colors.white.withAlphaFraction(0.2)),
          left: BorderSide(color: Colors.white.withAlphaFraction(0.2)),
          right: const BorderSide(color: Colors.transparent),
          top: const BorderSide(color: Colors.transparent),
        ),
      ),
      titlesData: FlTitlesData(
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 32,
            interval: intervalX <= 0 ? 1.0 : intervalX,
            getTitlesWidget: (value, _) {
              final isDesiredTick = xTicks.any((tick) => _isApproximately(value, tick, intervalX * 0.35));
              if (!isDesiredTick) {
                return const SizedBox.shrink();
              }
              final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(DateFormat.Md().format(date), style: const TextStyle(color: Colors.white70, fontSize: 11)),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 48,
            interval: safeIntervalY.toDouble(),
            getTitlesWidget: (value, meta) {
              final showTick = yTicks.any((tick) => _isApproximately(value, tick, yTolerance));
              if (!showTick) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _formatAxisTick(value),
                  style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.2),
                ),
              );
            },
          ),
        ),
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: baseData,
          isCurved: true,
          color: accent,
          barWidth: 3,
          gradient: LinearGradient(
            colors: [accent, Color.lerp(accent, Colors.white, 0.3)!],
          ),
          dotData: const FlDotData(show: false),
        ),
        LineChartBarData(
          spots: forecastData,
          isCurved: true,
          color: modelColor,
          barWidth: 3,
          gradient: LinearGradient(
            colors: [modelColor, Color.lerp(modelColor, Colors.white, 0.3)!],
          ),
          dashArray: const [6, 4],
          dotData: const FlDotData(show: false),
        ),
      ],
    );
  }
}

class _SentimentSection extends StatelessWidget {
  const _SentimentSection({super.key, required this.sentiment, required this.accentColor});

  final SentimentResponse sentiment;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final summary = sentiment.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        SectionHeading(
          title: 'News sentiment',
          subtitle: '${summary.total} articles in focus',
          accentColor: accentColor,
        ),
        const SizedBox(height: 20),
        _HorizontalMetricRow(
          cards: [
            AnimatedMetricCard(
              title: 'Articles analysed',
              value: '${summary.total}',
              subtitle: 'Dominant: ${summary.dominantSentiment ?? 'N/A'}',
              accentColor: accentColor,
              icon: Icons.article_rounded,
            ),
            AnimatedMetricCard(
              title: 'Average score',
              value: summary.averageScore == null ? '—' : summary.averageScore!.toStringAsFixed(2),
              subtitle: 'Pos ${summary.positive} • Neu ${summary.neutral} • Neg ${summary.negative}',
              accentColor: accentColor,
              icon: Icons.sentiment_satisfied_alt_rounded,
            ),
          ],
        ),
        const SizedBox(height: 20),
        for (var i = 0; i < sentiment.records.length; i++)
          _HeadlineTile(
            key: ValueKey('headline-${sentiment.records[i].hashCode}'),
            record: sentiment.records[i],
            index: i,
            accentColor: accentColor,
          ),
      ],
    );
  }
}

class AnimatedMetricCard extends StatelessWidget {
  const AnimatedMetricCard({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.isPositive,
    this.accentColor,
    this.icon,
  });

  final String title;
  final String value;
  final String? subtitle;
  final bool? isPositive;
  final Color? accentColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final highlight = accentColor ?? Theme.of(context).colorScheme.secondary;
    final subtitleColor = isPositive == null
        ? Colors.white70
        : (isPositive! ? Colors.greenAccent : Colors.orangeAccent);

    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: highlight.withAlphaFraction(0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: highlight, size: 20),
                ),
              if (icon != null) const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white70,
                    letterSpacing: 1.2,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(curved),
                  child: child,
                ),
              );
            },
            child: Text(
              value,
              key: ValueKey(value),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 8),
            Text(
              subtitle!,
              style: TextStyle(color: subtitleColor, fontSize: 12.5),
            ),
          ],
        ],
      ),
    );
  }
}

class _HorizontalMetricRow extends StatelessWidget {
  const _HorizontalMetricRow({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    const spacing = 16.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = max(constraints.maxWidth, 1.0);
        final count = cards.length;
        final targetWidth = (availableWidth - spacing * (count - 1)) / count;
        final cardWidth = max(220.0, targetWidth);

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 4),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: availableWidth),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: spacing),
                  SizedBox(width: cardWidth, child: cards[i]),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HighlightChip extends StatelessWidget {
  const _HighlightChip({required this.label, required this.date, required this.percent, required this.accentColor});

  final String label;
  final DateTime date;
  final double percent;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final isPositive = percent >= 0;
    final icon = isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded;
    return GlassContainer(
      showShadow: false,
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accentColor),
          const SizedBox(width: 8),
          Text(
            '$label • ${DateFormat.Md().format(date)}',
            style: const TextStyle(color: Colors.white, fontSize: 12.5),
          ),
          const SizedBox(width: 8),
          Text(
            '${percent.toStringAsFixed(2)}%',
            style: TextStyle(color: accentColor, fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _HeadlineTile extends StatelessWidget {
  const _HeadlineTile({super.key, required this.record, required this.index, required this.accentColor});

  final SentimentRecord record;
  final int index;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final color = switch (record.sentiment.toLowerCase()) {
      'positive' => Colors.greenAccent,
      'negative' => Colors.orangeAccent,
      _ => accentColor,
    };
    final dateText = record.published == null
        ? '—'
        : DateFormat.yMMMd().add_Hm().format(record.published!.toLocal());

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 400 + index * 60),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) => Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 26 * (1 - value)),
          child: child,
        ),
      ),
      child: GlassContainer(
        margin: EdgeInsets.only(bottom: index == 0 ? 12 : 18),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.headline,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${record.publisher ?? 'Unknown source'} • $dateText',
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: color.withAlphaFraction(0.6)),
                    color: color.withAlphaFraction(0.15),
                  ),
                  child: Text(
                    record.sentiment.toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.bolt_rounded, size: 16, color: color.withAlphaFraction(0.8)),
                const SizedBox(width: 6),
                Text(
                  'Score ${record.score.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.margin,
    this.borderRadius = 24,
    this.backgroundOpacity = 0.08,
    this.strokeOpacity = 0.16,
    this.blurSigma = 18,
    this.showShadow = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets? margin;
  final double borderRadius;
  final double backgroundOpacity;
  final double strokeOpacity;
  final double blurSigma;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return Container(
      margin: margin,
      decoration: showShadow
          ? BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlphaFraction(0.35),
                  blurRadius: 26,
                  offset: const Offset(0, 20),
                  spreadRadius: -14,
                ),
              ],
            )
          : null,
      child: ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: Colors.white.withAlphaFraction(strokeOpacity)),
              gradient: LinearGradient(
                colors: [
                  Colors.white.withAlphaFraction(backgroundOpacity),
                  Colors.white.withAlphaFraction(backgroundOpacity * 0.6),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Padding(
              padding: padding,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({super.key, required this.title, required this.subtitle, required this.accentColor});

  final String title;
  final String subtitle;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                accentColor.withAlphaFraction(0.75),
                accentColor.withAlphaFraction(0.25),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({required this.state, required this.accentColor});

  final DashboardState state;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
      borderRadius: 28,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI Stock Insights',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Fluent forecasts and sentiment intelligence tailored to your next move.',
                  style: TextStyle(color: Colors.white70, fontSize: 13.5),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    _HeaderPill(
                      icon: Icons.sell_outlined,
                      label: state.params.ticker.toUpperCase(),
                      accentColor: accentColor,
                    ),
                    if (state.models.isNotEmpty)
                      _HeaderPill(
                        icon: Icons.memory_rounded,
                        label: '${state.models.length} models',
                        accentColor: state.hasSavedLstmForTicker ? Colors.greenAccent : accentColor,
                        subtle: !state.hasSavedLstmForTicker,
                      ),
                    _HeaderPill(
                      icon: Icons.timer_rounded,
                      label: 'Interval ${state.params.interval}',
                      accentColor: accentColor,
                      subtle: true,
                    ),
                    _HeaderPill(
                      icon: Icons.calendar_month_rounded,
                      label: 'Range ${state.params.preset}',
                      accentColor: accentColor,
                      subtle: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: state.isLoading
                ? SizedBox(
                    key: const ValueKey('loading'),
                    width: 42,
                    height: 42,
                    child: CircularProgressIndicator(
                      strokeWidth: 3.2,
                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    ),
                  )
                : Icon(
                    Icons.auto_graph_rounded,
                    key: const ValueKey('idle'),
                    color: accentColor,
                    size: 40,
                  ),
          ),
        ],
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  const _HeaderPill({required this.icon, required this.label, required this.accentColor, this.subtle = false});

  final IconData icon;
  final String label;
  final Color accentColor;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
  final background = subtle ? Colors.white.withAlphaFraction(0.05) : accentColor.withAlphaFraction(0.18);
  final border = subtle ? Colors.white.withAlphaFraction(0.15) : accentColor.withAlphaFraction(0.5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: background,
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: accentColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12.5, letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }
}

class SectionTransitions {
  static Widget chart(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
        child: child,
      ),
    );
  }
}

class _EmptyChartState extends StatelessWidget {
  const _EmptyChartState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.data_exploration_rounded, color: Colors.white24, size: 36),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _AnimatedGradientBackground extends StatelessWidget {
  const _AnimatedGradientBackground({required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    const primary = Color(0xff05070d);
    const secondary = Color(0xff0b1220);
    const tertiary = Color(0xff111a2e);
    final accentGlow = Color.lerp(accentColor, Colors.white, 0.25)!.withAlphaFraction(0.12);
    return IgnorePointer(
      ignoring: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primary, secondary, tertiary],
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _BackgroundGridPainter(
                  baseColor: Colors.white.withAlphaFraction(0.035),
                  accentOverlay: accentGlow,
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topLeft,
                    radius: 1.4,
                    colors: [accentGlow, Colors.transparent],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomLeft,
                    end: Alignment.topRight,
                    colors: [Colors.transparent, accentColor.withAlphaFraction(0.08)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BackgroundGridPainter extends CustomPainter {
  _BackgroundGridPainter({required this.baseColor, required this.accentOverlay});

  final Color baseColor;
  final Color accentOverlay;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 96.0;
    final gridPaint = Paint()
      ..color = baseColor
      ..strokeWidth = 1;

    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final accentPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [accentOverlay, Colors.transparent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final accentPath = Path()
      ..moveTo(size.width * 0.55, -size.height * 0.2)
      ..lineTo(size.width * 1.1, -size.height * 0.1)
      ..lineTo(size.width * 0.8, size.height * 1.2)
      ..lineTo(size.width * 0.3, size.height)
      ..close();

    canvas.drawPath(accentPath, accentPaint);
  }

  @override
  bool shouldRepaint(covariant _BackgroundGridPainter oldDelegate) {
    return oldDelegate.baseColor != baseColor || oldDelegate.accentOverlay != accentOverlay;
  }
}
