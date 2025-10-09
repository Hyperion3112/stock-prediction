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
  Color withAlphaFraction(double opacity) =>
      withValues(alpha: opacity.clamp(0, 1));
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

List<double> _generateAxisTicks(double min, double max,
    {int desiredCount = 4}) {
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
        textTheme: Theme.of(context)
            .textTheme
            .apply(bodyColor: Colors.white, displayColor: Colors.white),
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
    this.sma20 = false,
    this.sma50 = false,
    this.ema12 = false,
    this.ema26 = false,
  });

  final String ticker;
  final String interval;
  final String preset;
  final int days;
  final bool sma20;
  final bool sma50;
  final bool ema12;
  final bool ema26;

  DashboardParams copyWith({
    String? ticker,
    String? interval,
    String? preset,
    int? days,
    bool? sma20,
    bool? sma50,
    bool? ema12,
    bool? ema26,
  }) {
    return DashboardParams(
      ticker: ticker ?? this.ticker,
      interval: interval ?? this.interval,
      preset: preset ?? this.preset,
      days: days ?? this.days,
      sma20: sma20 ?? this.sma20,
      sma50: sma50 ?? this.sma50,
      ema12: ema12 ?? this.ema12,
      ema26: ema26 ?? this.ema26,
    );
  }
}

class DashboardState {
  DashboardState({
    required this.params,
    this.overview,
    this.forecast,
    this.models = const [],
    this.isLoading = false,
    this.errorMessage,
    this.loadingCounter = 0,
  });

  final DashboardParams params;
  final OverviewResponse? overview;
  final ForecastResponse? forecast;
  final List<ModelInfo> models;
  final bool isLoading;
  final String? errorMessage;
  final int loadingCounter;

  bool get hasSavedLstmForTicker => models.any(
      (model) => model.ticker.toUpperCase() == params.ticker.toUpperCase());

  DashboardState copyWith({
    DashboardParams? params,
    OverviewResponse? overview,
    ForecastResponse? forecast,
    List<ModelInfo>? models,
    bool? isLoading,
    Object? errorMessage = _sentinel,
    int? loadingCounter,
  }) {
    final String? resolvedErrorMessage = identical(errorMessage, _sentinel)
        ? this.errorMessage
        : errorMessage as String?;

    return DashboardState(
      params: params ?? this.params,
      overview: overview ?? this.overview,
      forecast: forecast ?? this.forecast,
      models: models ?? this.models,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: resolvedErrorMessage,
      loadingCounter: loadingCounter ?? this.loadingCounter,
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
    _state = _state.copyWith(
      isLoading: true,
      errorMessage: null,
      loadingCounter: _state.loadingCounter + 1,
    );
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
        sma20: params.sma20,
        sma50: params.sma50,
        ema12: params.ema12,
        ema26: params.ema26,
      );

      _state = _state.copyWith(
        overview: overview,
        forecast: forecast,
        isLoading: false,
        errorMessage: null,
      );
    } catch (err) {
      _state = _state.copyWith(
          isLoading: false, errorMessage: _formatErrorMessage(err));
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
  bool showSma20 = false;
  bool showSma50 = false;
  bool showEma12 = false;
  bool showEma26 = false;

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
                  padding:
                      EdgeInsets.fromLTRB(20, 12, 20, max(insets.bottom, 16)),
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: GlassContainer(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Icon(Icons.warning_amber_rounded,
                                            color: Colors.orangeAccent),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Text(
                                            state.errorMessage!,
                                            style: const TextStyle(
                                                color: Colors.orangeAccent),
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
                                child: state.isLoading
                                    ? Column(
                                        key: ValueKey('overview-loading-${state.loadingCounter}'),
                                        children: [
                                          _RollingLoadingMessage(accentColor: accent),
                                          const _OverviewLoadingSkeleton(),
                                        ],
                                      )
                                    : (state.overview != null
                                        ? _OverviewSection(
                                            key: ValueKey(
                                                'overview-${state.overview!.metadata.ticker}-${state.overview!.metrics.latestClose}'),
                                            overview: state.overview!,
                                            accentColor: accent,
                                          )
                                        : const SizedBox.shrink(
                                            key: ValueKey('overview-empty'),
                                          )),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 500),
                                transitionBuilder: _sectionTransitionBuilder,
                                child: state.isLoading
                                    ? Column(
                                        key: ValueKey('forecast-loading-${state.loadingCounter}'),
                                        children: const [
                                          _ForecastLoadingSkeleton(),
                                        ],
                                      )
                                    : (state.forecast != null
                                        ? _ForecastSection(
                                            key: ValueKey(
                                                'forecast-${state.forecast!.ticker}-${state.forecast!.forecast.length}'),
                                            forecast: state.forecast!,
                                            overview: state.overview,
                                            accentColor: accent,
                                          )
                                        : const SizedBox.shrink(
                                            key: ValueKey('forecast-empty'),
                                          )),
                              ),
                            ),
                            const SliverToBoxAdapter(
                                child: SizedBox(height: 24)),
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

  static Widget _sectionTransitionBuilder(
      Widget child, Animation<double> animation) {
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
            .animate(curved),
        child: child,
      ),
    );
  }

  Color _tickerAccentColor(String ticker) {
    final normalized = ticker.isEmpty
        ? 0
        : ticker.codeUnitAt(0) + ticker.codeUnitAt(ticker.length - 1);
    // Use a more restricted hue range for better visual appeal
    // Map to green-to-purple range (120-280 degrees) avoiding blues
    final baseHue = (normalized * 17) % 160;
    final hue = baseHue + 120.0; // Range: 120-280 (green through purple)
    return HSLColor.fromAHSL(1, hue, 0.6, 0.58).toColor();
  }

  Widget _buildControls(
      BuildContext context, DashboardState state, Color accentColor) {
    const availablePresets = ['1M', '3M', '6M', '1Y', '2Y', '5Y'];
    const availableIntervals = ['1m', '5m', '15m', '30m', '1h', '1d', '1wk', '1mo'];
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                  const Spacer(),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 300),
                    opacity: state.isLoading ? 0.6 : 1,
                    child: Text(
                      'Ticker ${state.params.ticker}',
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
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
                      icon:
                          const Icon(Icons.expand_more, color: Colors.white70),
                      dropdownColor: const Color(0xff111c2d),
                      decoration: _glassFieldDecoration('Date range'),
                      items: [
                        for (final item in availablePresets)
                          DropdownMenuItem(value: item, child: Text(item)),
                      ],
                      onChanged: (value) =>
                          setState(() => preset = value ?? preset),
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('interval-$interval'),
                      initialValue: interval,
                      icon:
                          const Icon(Icons.expand_more, color: Colors.white70),
                      dropdownColor: const Color(0xff111c2d),
                      decoration: _glassFieldDecoration('Interval'),
                      items: [
                        for (final item in availableIntervals)
                          DropdownMenuItem(value: item, child: Text(item)),
                      ],
                      onChanged: (value) =>
                          setState(() => interval = value ?? interval),
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
                            const Text('Forecast horizon',
                                style: TextStyle(color: Colors.white70)),
                            Text('$horizon days',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 10),
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
                            onChanged: (value) =>
                                setState(() => horizon = value.round()),
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
                          label: const Text('SMA-20'),
                          labelStyle: const TextStyle(color: Colors.white),
                          selectedColor: accentColor.withAlphaFraction(0.25),
                          backgroundColor: Colors.white.withAlphaFraction(0.05),
                          side: BorderSide(
                              color: (showSma20 ? accentColor : Colors.white24)
                                  .withAlphaFraction(0.7)),
                          selected: showSma20,
                          onSelected: (value) =>
                              setState(() => showSma20 = value),
                        ),
                        FilterChip(
                          showCheckmark: false,
                          label: const Text('SMA-50'),
                          labelStyle: const TextStyle(color: Colors.white),
                          selectedColor: accentColor.withAlphaFraction(0.25),
                          backgroundColor: Colors.white.withAlphaFraction(0.05),
                          side: BorderSide(
                              color: (showSma50 ? accentColor : Colors.white24)
                                  .withAlphaFraction(0.7)),
                          selected: showSma50,
                          onSelected: (value) =>
                              setState(() => showSma50 = value),
                        ),
                        FilterChip(
                          showCheckmark: false,
                          label: const Text('EMA-12'),
                          labelStyle: const TextStyle(color: Colors.white),
                          selectedColor: accentColor.withAlphaFraction(0.25),
                          backgroundColor: Colors.white.withAlphaFraction(0.05),
                          side: BorderSide(
                              color: (showEma12 ? accentColor : Colors.white24)
                                  .withAlphaFraction(0.7)),
                          selected: showEma12,
                          onSelected: (value) =>
                              setState(() => showEma12 = value),
                        ),
                        FilterChip(
                          showCheckmark: false,
                          label: const Text('EMA-26'),
                          labelStyle: const TextStyle(color: Colors.white),
                          selectedColor: accentColor.withAlphaFraction(0.25),
                          backgroundColor: Colors.white.withAlphaFraction(0.05),
                          side: BorderSide(
                              color: (showEma26 ? accentColor : Colors.white24)
                                  .withAlphaFraction(0.7)),
                          selected: showEma26,
                          onSelected: (value) =>
                              setState(() => showEma26 = value),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 26, vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                    onPressed: state.isLoading
                        ? null
                        : () {
                            final params = state.params.copyWith(
                              ticker:
                                  tickerController.text.trim().toUpperCase(),
                              preset: preset,
                              interval: interval,
                              days: horizon,
                              sma20: showSma20,
                              sma50: showSma50,
                              ema12: showEma12,
                              ema26: showEma26,
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
  const _OverviewSection(
      {super.key, required this.overview, required this.accentColor});

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
      if ((overview.metadata.sector ?? '').isNotEmpty)
        overview.metadata.sector!,
      if ((overview.metadata.industry ?? '').isNotEmpty)
        overview.metadata.industry!,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(
          title: overview.metadata.name ?? overview.metadata.ticker,
          subtitle: subtitleParts.isEmpty
              ? 'Insights snapshot'
              : subtitleParts.join(' • '),
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
                subtitle:
                    '${metrics.pctChange.toStringAsFixed(2)}% vs previous close',
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
                  value:
                      '${highlights.annualizedVolatility!.toStringAsFixed(1)}%',
                  subtitle: 'Trailing 30 trading days',
                  accentColor: accentColor,
                  icon: Icons.speed_rounded,
                ),
              );
            }

            final count = cards.length;
            final availableWidth = max(constraints.maxWidth, 1.0);
            final targetWidth =
                (availableWidth - spacing * (count - 1)) / count;
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
                  ? const _EmptyChartState(
                      message: 'No price history available')
                  : LineChart(
                      key: ValueKey(
                          'history-${history.length}-${history.last.close}'),
                      _buildHistoryChart(history, accentColor),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeInOutCubic,
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
    if (history.isEmpty) {
      return LineChartData(lineBarsData: []);
    }
    final minDate = history.first.date;
    final maxDate = history.last.date;
    final minValue = history.map((p) => p.close).reduce(min);
    final maxValue = history.map((p) => p.close).reduce(max);
    final diffX =
        maxDate.millisecondsSinceEpoch - minDate.millisecondsSinceEpoch;
    final diffY = maxValue - minValue;
    final xTicks = _generateAxisTicks(
      minDate.millisecondsSinceEpoch.toDouble(),
      maxDate.millisecondsSinceEpoch.toDouble(),
      desiredCount: 4,
    );
    final intervalX = xTicks.length > 1
        ? (xTicks[1] - xTicks[0]).abs()
        : (diffX <= 0 ? 1.0 : diffX.toDouble());
    final yTicks = _generateAxisTicks(minValue, maxValue, desiredCount: 4);
    final yStep = yTicks.length > 1
        ? (yTicks[1] - yTicks[0]).abs()
        : (diffY == 0 ? (maxValue == 0 ? 1 : maxValue.abs()) : diffY.abs());
    final yTolerance = max(yStep.abs() * 0.35, 0.0001);
    final safeIntervalY = yStep == 0 ? 1.0 : yStep;
    final dateFormat = DateFormat.MMMd();
    final currencyFormat = NumberFormat.simpleCurrency();

    return LineChartData(
      lineTouchData: LineTouchData(
        handleBuiltInTouches: true,
        touchSpotThreshold: 30,
        getTouchedSpotIndicator: (bar, indexes) {
          return indexes
              .map(
                (index) => TouchedSpotIndicatorData(
                  FlLine(
                      color: Colors.white.withAlphaFraction(0.3),
                      strokeWidth: 2,
                      dashArray: [4, 4]),
                  FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, idx) =>
                        FlDotCirclePainter(
                      radius: 5,
                      color: Colors.white,
                      strokeWidth: 3,
                      strokeColor: accent,
                    ),
                  ),
                ),
              )
              .toList();
        },
        touchTooltipData: LineTouchTooltipData(
          tooltipBgColor: const Color(0xff1a1f2e),
          tooltipRoundedRadius: 12,
          tooltipPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          tooltipMargin: 24,
          tooltipBorder: BorderSide(
            color: accent.withAlphaFraction(0.3),
            width: 1.5,
          ),
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItems: (spots) {
            return spots.map((spot) {
              final date = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
              return LineTooltipItem(
                '${dateFormat.format(date)}\n',
                const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    height: 1.5),
                children: [
                  TextSpan(
                    text: '${currencyFormat.format(spot.y)}',
                    style: TextStyle(
                        color: accent,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        height: 1.5),
                  ),
                ],
              );
            }).toList();
          },
        ),
      ),
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        drawHorizontalLine: true,
        horizontalInterval: safeIntervalY.toDouble(),
        verticalInterval: intervalX <= 0 ? null : intervalX,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Colors.white.withAlphaFraction(0.06),
            strokeWidth: 1,
          );
        },
        getDrawingVerticalLine: (value) {
          return FlLine(
            color: Colors.white.withAlphaFraction(0.04),
            strokeWidth: 1,
          );
        },
      ),
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
              final isDesiredTick = xTicks.any(
                  (tick) => _isApproximately(value, tick, intervalX * 0.35));
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
              final showTick = yTicks
                  .any((tick) => _isApproximately(value, tick, yTolerance));
              if (!showTick) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _formatAxisTick(value),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11, height: 1.2),
                ),
              );
            },
          ),
        ),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          isCurved: true,
          curveSmoothness: 0.35,
          preventCurveOverShooting: true,
          color: accent,
          barWidth: 3,
          gradient: LinearGradient(
            colors: [accent, Color.lerp(accent, Colors.white, 0.3)!],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          spots: [
            for (final point in history)
              FlSpot(point.date.millisecondsSinceEpoch.toDouble(), point.close),
          ],
          dotData: const FlDotData(show: false),
          isStrokeCapRound: true,
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                accent.withAlphaFraction(0.15),
                accent.withAlphaFraction(0.0),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
    );
  }
}

class _ForecastSection extends StatelessWidget {
  const _ForecastSection(
      {super.key,
      required this.forecast,
      required this.overview,
      required this.accentColor});

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
    final origin =
        history.isNotEmpty ? history.last.close : (latest == 0 ? 1 : latest);
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
                  const Icon(Icons.info_outline_rounded,
                      color: Colors.orangeAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      forecast.note!,
                      style: const TextStyle(
                          color: Colors.orangeAccent,
                          fontSize: 12.5,
                          height: 1.4),
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Legend
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 24,
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [accentColor, Color.lerp(accentColor, Colors.white, 0.3)!],
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Historical',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CustomPaint(
                        size: const Size(24, 3),
                        painter: _DashedLinePainter(
                          color: modelColor,
                          strokeWidth: 3,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Forecast',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 280,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 600),
                  transitionBuilder: SectionTransitions.chart,
                  child: (history.isEmpty && forecast.forecast.isEmpty)
                      ? const _EmptyChartState(
                          message: 'Forecast data not available yet')
                      : LineChart(
                          key: ValueKey(
                              'forecast-${forecast.ticker}-${forecast.forecast.length}-${history.length}'),
                          _buildForecastChart(history, forecast.forecast,
                              forecast.indicators, accentColor, modelColor),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeInOutCubic,
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  LineChartData _buildForecastChart(
    List<PricePoint> history,
    List<ForecastPoint> forecastPoints,
    TechnicalIndicators? indicators,
    Color accent,
    Color modelColor,
  ) {
    final baseData = [
      ...history
          .map((e) => FlSpot(e.date.millisecondsSinceEpoch.toDouble(), e.close))
    ];
    final forecastData = [
      ...forecastPoints
          .map((e) => FlSpot(e.date.millisecondsSinceEpoch.toDouble(), e.value))
    ];
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

    double? nearestValue(Map<double, double> source, double target,
        {double tolerance = 60000}) {
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
    // Include indicator values in min/max calculations
    if (indicators?.sma20 != null) {
      allValues.addAll(indicators!.sma20!.map(
          (e) => FlSpot(e.date.millisecondsSinceEpoch.toDouble(), e.value)));
    }
    if (indicators?.sma50 != null) {
      allValues.addAll(indicators!.sma50!.map(
          (e) => FlSpot(e.date.millisecondsSinceEpoch.toDouble(), e.value)));
    }
    if (indicators?.ema12 != null) {
      allValues.addAll(indicators!.ema12!.map(
          (e) => FlSpot(e.date.millisecondsSinceEpoch.toDouble(), e.value)));
    }
    if (indicators?.ema26 != null) {
      allValues.addAll(indicators!.ema26!.map(
          (e) => FlSpot(e.date.millisecondsSinceEpoch.toDouble(), e.value)));
    }
    if (allValues.isEmpty) {
      return LineChartData(lineBarsData: []);
    }
    final minX = allValues.first.x;
    final maxX = allValues.last.x;
    final minY = allValues.map((e) => e.y).reduce(min);
    final maxY = allValues.map((e) => e.y).reduce(max);
    final diffX = maxX - minX;
    final xTicks = _generateAxisTicks(minX, maxX, desiredCount: 4);
    final intervalX = xTicks.length > 1
        ? (xTicks[1] - xTicks[0]).abs()
        : (diffX <= 0 ? 1.0 : diffX);
    final diffY = maxY - minY;
    final yTicks = _generateAxisTicks(minY, maxY, desiredCount: 4);
    final yStep = yTicks.length > 1
        ? (yTicks[1] - yTicks[0]).abs()
        : (diffY == 0 ? (maxY == 0 ? 1 : maxY.abs()) : diffY.abs());
    final yTolerance = max(yStep.abs() * 0.35, 0.0001);
    final safeIntervalY = yStep == 0 ? 1.0 : yStep;
    final dateFormat = DateFormat.MMMd();
    final currencyFormat = NumberFormat.simpleCurrency();

    return LineChartData(
      lineTouchData: LineTouchData(
        handleBuiltInTouches: true,
        touchSpotThreshold: 30,
        getTouchedSpotIndicator: (bar, indexes) {
          return indexes
              .map(
                (index) => TouchedSpotIndicatorData(
                  FlLine(
                      color: Colors.white.withAlphaFraction(0.3),
                      strokeWidth: 2,
                      dashArray: [4, 4]),
                  FlDotData(
                    show: true,
                    getDotPainter: (spot, percent, barData, idx) {
                      final color = (barData.gradient?.colors.first ??
                          barData.color ??
                          Colors.white);
                      return FlDotCirclePainter(
                        radius: 5,
                        color: Colors.white,
                        strokeWidth: 3,
                        strokeColor: color,
                      );
                    },
                  ),
                ),
              )
              .toList();
        },
        touchTooltipData: LineTouchTooltipData(
          tooltipBgColor: const Color(0xff1a1f2e),
          tooltipRoundedRadius: 12,
          tooltipPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          tooltipMargin: 24,
          tooltipBorder: BorderSide(
            color: accent.withAlphaFraction(0.3),
            width: 1.5,
          ),
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          rotateAngle: 0,
          getTooltipItems: (spots) {
            return spots.map((spot) {
              final date = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
              final isHistory = spot.barIndex == 0;
              final isForecast = spot.barIndex == 1;
              final color = spot.bar.gradient?.colors.first ?? spot.bar.color;
              
              String label;
              if (isHistory) {
                label = 'Historical';
              } else if (isForecast) {
                label = 'Forecast';
              } else {
                // For technical indicators
                final indicatorNames = ['', '', 'SMA-20', 'SMA-50', 'EMA-12', 'EMA-26'];
                label = spot.barIndex < indicatorNames.length 
                    ? indicatorNames[spot.barIndex] 
                    : 'Indicator';
              }

              return LineTooltipItem(
                '${dateFormat.format(date)} • $label\n',
                const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
                children: [
                  TextSpan(
                    text: currencyFormat.format(spot.y),
                    style: TextStyle(
                      color: color ?? Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      height: 1.5,
                    ),
                  ),
                ],
              );
            }).toList();
          },
        ),
      ),
      minX: minX,
      maxX: maxX,
      minY: minY == maxY ? minY * 0.95 : minY * 0.98,
      maxY: minY == maxY ? maxY * 1.05 : maxY * 1.02,
      gridData: FlGridData(
        show: true,
        drawVerticalLine: true,
        drawHorizontalLine: true,
        horizontalInterval: safeIntervalY.toDouble(),
        verticalInterval: intervalX <= 0 ? null : intervalX,
        getDrawingHorizontalLine: (value) {
          return FlLine(
            color: Colors.white.withAlphaFraction(0.06),
            strokeWidth: 1,
          );
        },
        getDrawingVerticalLine: (value) {
          return FlLine(
            color: Colors.white.withAlphaFraction(0.04),
            strokeWidth: 1,
          );
        },
      ),
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
              final isDesiredTick = xTicks.any(
                  (tick) => _isApproximately(value, tick, intervalX * 0.35));
              if (!isDesiredTick) {
                return const SizedBox.shrink();
              }
              final date = DateTime.fromMillisecondsSinceEpoch(value.toInt());
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(DateFormat.Md().format(date),
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 11)),
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
              final showTick = yTicks
                  .any((tick) => _isApproximately(value, tick, yTolerance));
              if (!showTick) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _formatAxisTick(value),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 11, height: 1.2),
                ),
              );
            },
          ),
        ),
        rightTitles:
            const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      lineBarsData: [
        LineChartBarData(
          spots: baseData,
          isCurved: true,
          curveSmoothness: 0.35,
          preventCurveOverShooting: true,
          color: accent,
          barWidth: 3,
          gradient: LinearGradient(
            colors: [accent, Color.lerp(accent, Colors.white, 0.3)!],
          ),
          dotData: const FlDotData(show: false),
          isStrokeCapRound: true,
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                accent.withAlphaFraction(0.12),
                accent.withAlphaFraction(0.0),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
        LineChartBarData(
          spots: forecastData,
          isCurved: true,
          curveSmoothness: 0.35,
          preventCurveOverShooting: true,
          color: modelColor,
          barWidth: 3,
          gradient: LinearGradient(
            colors: [modelColor, Color.lerp(modelColor, Colors.white, 0.3)!],
          ),
          dashArray: const [6, 4],
          dotData: const FlDotData(show: false),
          isStrokeCapRound: true,
        ),
        // Add technical indicator lines
        if (indicators?.sma20 != null)
          LineChartBarData(
            spots: indicators!.sma20!
                .map((e) =>
                    FlSpot(e.date.millisecondsSinceEpoch.toDouble(), e.value))
                .toList(),
            isCurved: true,
            color: Colors.orange,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        if (indicators?.sma50 != null)
          LineChartBarData(
            spots: indicators!.sma50!
                .map((e) =>
                    FlSpot(e.date.millisecondsSinceEpoch.toDouble(), e.value))
                .toList(),
            isCurved: true,
            color: Colors.purple,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        if (indicators?.ema12 != null)
          LineChartBarData(
            spots: indicators!.ema12!
                .map((e) =>
                    FlSpot(e.date.millisecondsSinceEpoch.toDouble(), e.value))
                .toList(),
            isCurved: true,
            color: Colors.green,
            barWidth: 2,
            dotData: const FlDotData(show: false),
          ),
        if (indicators?.ema26 != null)
          LineChartBarData(
            spots: indicators!.ema26!
                .map((e) =>
                    FlSpot(e.date.millisecondsSinceEpoch.toDouble(), e.value))
                .toList(),
            isCurved: true,
            color: Colors.cyan,
            barWidth: 2,
            dotData: const FlDotData(show: false),
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
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (icon != null)
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: highlight.withAlphaFraction(0.18),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: highlight.withAlphaFraction(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: highlight, size: 22),
                ),
              if (icon != null) const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white60,
                    letterSpacing: 1.3,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                  parent: animation, curve: Curves.easeOutCubic);
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                          begin: const Offset(0, 0.12), end: Offset.zero)
                      .animate(curved),
                  child: child,
                ),
              );
            },
            child: Text(
              value,
              key: ValueKey(value),
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 10),
            Text(
              subtitle!,
              style: TextStyle(
                color: subtitleColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
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
  const _HighlightChip(
      {required this.label,
      required this.date,
      required this.percent,
      required this.accentColor});

  final String label;
  final DateTime date;
  final double percent;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final isPositive = percent >= 0;
    final icon =
        isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded;
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
            style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.w600,
                fontSize: 12.5),
          ),
        ],
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
              border: Border.all(
                  color: Colors.white.withAlphaFraction(strokeOpacity)),
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
  const SectionHeading(
      {super.key,
      required this.title,
      required this.subtitle,
      required this.accentColor});

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
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accentColor.withAlphaFraction(0.15),
            accentColor.withAlphaFraction(0.08),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: accentColor.withAlphaFraction(0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withAlphaFraction(0.2),
            blurRadius: 30,
            spreadRadius: 0,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(40, 50, 40, 50),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withAlphaFraction(0.08),
                  Colors.white.withAlphaFraction(0.04),
                ],
              ),
            ),
            child: Column(
              children: [
                // Main title with animation
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            accentColor.withAlphaFraction(0.3),
                            accentColor.withAlphaFraction(0.15),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withAlphaFraction(0.4),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        child: state.isLoading
                            ? SizedBox(
                                key: const ValueKey('loading'),
                                width: 40,
                                height: 40,
                                child: CircularProgressIndicator(
                                  strokeWidth: 3.5,
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
                    ),
                    const SizedBox(width: 24),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ShaderMask(
                            shaderCallback: (bounds) => LinearGradient(
                              colors: [
                                Colors.white,
                                accentColor.withAlphaFraction(0.9),
                              ],
                            ).createShader(bounds),
                            child: Text(
                              'AI Stock Insights',
                              style: TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.5,
                                height: 1.1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: 4,
                            width: 80,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  accentColor,
                                  accentColor.withAlphaFraction(0.3),
                                  Colors.transparent,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Subtitle with better styling
                Text(
                  'Advanced stock forecasting powered by LSTM neural networks and real-time sentiment analysis',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withAlphaFraction(0.85),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.5,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 20),
                // Feature pills
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _FeaturePill(
                      icon: Icons.psychology_rounded,
                      label: 'LSTM Neural Networks',
                      accentColor: accentColor,
                    ),
                    _FeaturePill(
                      icon: Icons.trending_up_rounded,
                      label: 'Price Predictions',
                      accentColor: accentColor,
                    ),
                    _FeaturePill(
                      icon: Icons.sentiment_satisfied_rounded,
                      label: 'Sentiment Analysis',
                      accentColor: accentColor,
                    ),
                    _FeaturePill(
                      icon: Icons.insights_rounded,
                      label: 'Market Insights',
                      accentColor: accentColor,
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Help button
                _HelpButton(accentColor: accentColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({
    required this.icon,
    required this.label,
    required this.accentColor,
  });

  final IconData icon;
  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withAlphaFraction(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withAlphaFraction(0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: accentColor,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withAlphaFraction(0.9),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpButton extends StatelessWidget {
  const _HelpButton({super.key, required this.accentColor});

  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      richMessage: WidgetSpan(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          accentColor.withAlphaFraction(0.3),
                          accentColor.withAlphaFraction(0.1),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: accentColor.withAlphaFraction(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.lightbulb_rounded,
                      color: accentColor,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'How to Use AI Stock Insights',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Divider
              Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      accentColor.withAlphaFraction(0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              // Step items
              _HelpStep(
                number: '1',
                icon: Icons.business_rounded,
                title: 'Select Ticker',
                description: 'Enter stock symbols like AAPL, MSFT, TSLA',
                accentColor: accentColor,
              ),
              const SizedBox(height: 12),
              _HelpStep(
                number: '2',
                icon: Icons.date_range_rounded,
                title: 'Choose Time Range',
                description: 'Select 1M, 3M, 6M, 1Y or custom dates',
                accentColor: accentColor,
              ),
              const SizedBox(height: 12),
              _HelpStep(
                number: '3',
                icon: Icons.schedule_rounded,
                title: 'Set Interval',
                description: 'Choose data frequency from 1m to 1mo',
                accentColor: accentColor,
              ),
              const SizedBox(height: 12),
              _HelpStep(
                number: '4',
                icon: Icons.trending_up_rounded,
                title: 'Configure Forecast',
                description: 'Set forecast days & enable indicators',
                accentColor: accentColor,
              ),
              const SizedBox(height: 12),
              _HelpStep(
                number: '5',
                icon: Icons.show_chart_rounded,
                title: 'Technical Indicators',
                description: 'SMA-20/50: Moving avg trends • EMA-12/26: Fast signals',
                accentColor: accentColor,
              ),
              const SizedBox(height: 12),
              _HelpStep(
                number: '6',
                icon: Icons.insights_rounded,
                title: 'Get Insights',
                description: 'Click "Refresh" to generate forecasts',
                accentColor: accentColor,
              ),
              
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xff1a1f2e),
            const Color(0xff0d1220),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withAlphaFraction(0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withAlphaFraction(0.15),
            blurRadius: 25,
            spreadRadius: 2,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withAlphaFraction(0.5),
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(8),
      preferBelow: false,
      child: IconButton(
        onPressed: () {},
        icon: Icon(
          Icons.help_outline_rounded,
          color: accentColor,
          size: 24,
        ),
        style: IconButton.styleFrom(
          backgroundColor: accentColor.withAlphaFraction(0.15),
          padding: const EdgeInsets.all(8),
        ),
      ),
    );
  }
}

class _HelpStep extends StatelessWidget {
  const _HelpStep({
    super.key,
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
    required this.accentColor,
  });

  final String number;
  final IconData icon;
  final String title;
  final String description;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Number badge
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accentColor,
                accentColor.withAlphaFraction(0.7),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: accentColor.withAlphaFraction(0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        
        // Icon
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: accentColor.withAlphaFraction(0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: accentColor.withAlphaFraction(0.2),
              width: 1,
            ),
          ),
          child: Icon(
            icon,
            color: accentColor.withAlphaFraction(0.9),
            size: 16,
          ),
        ),
        const SizedBox(width: 12),
        
        // Text content
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: TextStyle(
                  color: Colors.white.withAlphaFraction(0.7),
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}


class _HeaderPill extends StatelessWidget {
  const _HeaderPill(
      {required this.icon,
      required this.label,
      required this.accentColor,
      this.subtle = false});

  final IconData icon;
  final String label;
  final Color accentColor;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final background = subtle
        ? Colors.white.withAlphaFraction(0.05)
        : accentColor.withAlphaFraction(0.18);
    final border = subtle
        ? Colors.white.withAlphaFraction(0.15)
        : accentColor.withAlphaFraction(0.5);
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
            style: const TextStyle(
                color: Colors.white, fontSize: 12.5, letterSpacing: 0.6),
          ),
        ],
      ),
    );
  }
}

class SectionTransitions {
  static Widget chart(Widget child, Animation<double> animation) {
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
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
          const Icon(Icons.data_exploration_rounded,
              color: Colors.white24, size: 36),
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
    // Professional, clean gradient background
    const primary = Color(0xff0a0e1a);      // Deep navy
    const secondary = Color(0xff0f1729);    // Slightly lighter navy
    const tertiary = Color(0xff141d35);     // Mid navy
    
    return IgnorePointer(
      ignoring: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [primary, secondary, tertiary],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
      ),
    );
  }
}

// Loading Skeleton Widgets
class _LoadingSkeletonCard extends StatelessWidget {
  const _LoadingSkeletonCard({
    this.height = 200,
    this.margin = const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
  });

  final double height;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white.withAlphaFraction(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlphaFraction(0.08)),
      ),
      child: _ShimmerEffect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 150,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlphaFraction(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: 100,
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlphaFraction(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withAlphaFraction(0.05),
                    borderRadius: BorderRadius.circular(12),
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

class _ShimmerEffect extends StatefulWidget {
  const _ShimmerEffect({required this.child});

  final Widget child;

  @override
  State<_ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<_ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: const [
                Colors.transparent,
                Colors.white24,
                Colors.transparent,
              ],
              stops: [
                _controller.value - 0.3,
                _controller.value,
                _controller.value + 0.3,
              ].map((e) => e.clamp(0.0, 1.0)).toList(),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _RollingLoadingMessage extends StatefulWidget {
  const _RollingLoadingMessage({this.accentColor});

  final Color? accentColor;

  @override
  State<_RollingLoadingMessage> createState() => _RollingLoadingMessageState();
}

class _RollingLoadingMessageState extends State<_RollingLoadingMessage> {
  int _currentMessageIndex = 0;
  late Timer _timer;

  final List<Map<String, dynamic>> _messages = [
    {
      'icon': Icons.rocket_launch_rounded,
      'text': 'Initializing AI engine...',
    },
    {
      'icon': Icons.cloud_download_rounded,
      'text': 'Fetching real-time market data...',
    },
    {
      'icon': Icons.analytics_rounded,
      'text': 'Analyzing historical trends...',
    },
    {
      'icon': Icons.speed_rounded,
      'text': 'Calculating price momentum...',
    },
    {
      'icon': Icons.psychology_rounded,
      'text': 'Running AI predictions...',
    },
    {
      'icon': Icons.dataset_rounded,
      'text': 'Processing training datasets...',
    },
    {
      'icon': Icons.functions_rounded,
      'text': 'Computing LSTM neural networks...',
    },
    {
      'icon': Icons.calculate_rounded,
      'text': 'Computing technical indicators...',
    },
    {
      'icon': Icons.show_chart_rounded,
      'text': 'Generating SMA and EMA signals...',
    },
    {
      'icon': Icons.timeline_rounded,
      'text': 'Building forecast models...',
    },
    {
      'icon': Icons.data_exploration_rounded,
      'text': 'Detecting price patterns...',
    },
    {
      'icon': Icons.trending_up_rounded,
      'text': 'Analyzing market volatility...',
    },
    {
      'icon': Icons.query_stats_rounded,
      'text': 'Evaluating statistical significance...',
    },
    {
      'icon': Icons.insights_rounded,
      'text': 'Synthesizing market insights...',
    },
    {
      'icon': Icons.autorenew_rounded,
      'text': 'Calibrating prediction accuracy...',
    },
    {
      'icon': Icons.tune_rounded,
      'text': 'Fine-tuning model parameters...',
    },
    {
      'icon': Icons.assessment_rounded,
      'text': 'Validating forecast reliability...',
    },
    {
      'icon': Icons.scatter_plot_rounded,
      'text': 'Mapping data correlations...',
    },
    {
      'icon': Icons.compress_rounded,
      'text': 'Optimizing data structures...',
    },
    {
      'icon': Icons.pending_actions_rounded,
      'text': 'Almost there, finalizing insights...',
    },
  ];

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        setState(() {
          _currentMessageIndex = (_currentMessageIndex + 1) % _messages.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? Colors.blueAccent;
    final currentMessage = _messages[_currentMessageIndex];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withAlphaFraction(0.1),
            accent.withAlphaFraction(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accent.withAlphaFraction(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          // Animated loading icon
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeInOut,
            builder: (context, value, child) {
              return Transform.scale(
                scale: 0.8 + (value * 0.2),
                child: Opacity(
                  opacity: 0.6 + (value * 0.4),
                  child: child,
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: accent.withAlphaFraction(0.2),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: accent.withAlphaFraction(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(
                currentMessage['icon'] as IconData,
                color: accent,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 16),
          
          // Animated text message
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.3),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutCubic,
                    )),
                    child: child,
                  ),
                );
              },
              child: Text(
                currentMessage['text'] as String,
                key: ValueKey(_currentMessageIndex),
                style: TextStyle(
                  color: Colors.white.withAlphaFraction(0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
          
          // Loading spinner
          const SizedBox(width: 12),
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewLoadingSkeleton extends StatelessWidget {
  const _OverviewLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlphaFraction(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlphaFraction(0.08)),
      ),
      child: _ShimmerEffect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlphaFraction(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 120,
                          height: 20,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlphaFraction(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 180,
                          height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white.withAlphaFraction(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Metrics Grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: List.generate(
                  4,
                  (index) => Container(
                    width: 140,
                    height: 80,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlphaFraction(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            // Chart
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              child: Container(
                height: 280,
                decoration: BoxDecoration(
                  color: Colors.white.withAlphaFraction(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ForecastLoadingSkeleton extends StatelessWidget {
  const _ForecastLoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withAlphaFraction(0.03),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlphaFraction(0.08)),
      ),
      child: _ShimmerEffect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Row(
                children: [
                  Container(
                    width: 150,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlphaFraction(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 80,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white.withAlphaFraction(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              ),
            ),
            // Chart
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              child: Container(
                height: 280,
                decoration: BoxDecoration(
                  color: Colors.white.withAlphaFraction(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Animated Button Wrapper for micro-interactions
class _AnimatedPressable extends StatefulWidget {
  const _AnimatedPressable({required this.child, this.onPressed});

  final Widget child;
  final VoidCallback? onPressed;

  @override
  State<_AnimatedPressable> createState() => _AnimatedPressableState();
}

class _AnimatedPressableState extends State<_AnimatedPressable>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    _controller.reverse();
    widget.onPressed?.call();
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onPressed != null ? _onTapDown : null,
      onTapUp: widget.onPressed != null ? _onTapUp : null,
      onTapCancel: widget.onPressed != null ? _onTapCancel : null,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

// Custom painter for dashed lines in legend
class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({
    required this.color,
    this.strokeWidth = 2,
    this.dashWidth = 4,
    this.dashSpace = 3,
  });

  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(
        Offset(startX, size.height / 2),
        Offset(min(startX + dashWidth, size.width), size.height / 2),
        paint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.dashWidth != dashWidth ||
        oldDelegate.dashSpace != dashSpace;
  }
}
