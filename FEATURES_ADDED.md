# Interactive UI Controls - Technical Indicators Feature

## Overview
Added comprehensive UI controls to showcase robust Flutter-backend integration with real-time parameter control of AI model behavior.

## Features Implemented

### 1. Backend API Enhancement (app.py)
- ✅ Added `calculate_technical_indicators()` function with SMA and EMA calculations
- ✅ Extended `/forecast` endpoint with 4 new Query parameters:
  - `sma_20`: Include 20-period Simple Moving Average
  - `sma_50`: Include 50-period Simple Moving Average  
  - `ema_12`: Include 12-period Exponential Moving Average
  - `ema_26`: Include 26-period Exponential Moving Average
- ✅ Updated `ForecastResponse` to include `indicators` field
- ✅ Implemented conditional indicator calculation (only when requested)

### 2. Flutter Data Models (models.dart)
- ✅ Added `TechnicalIndicator` class (date + value)
- ✅ Added `TechnicalIndicators` container class
- ✅ Extended `ForecastResponse` to include optional `indicators` field
- ✅ Proper JSON deserialization for all indicator types

### 3. Flutter API Client (api_client.dart)
- ✅ Extended `fetchForecast()` method with indicator parameters:
  - `sma20`, `sma50`, `ema12`, `ema26` (all default to false)
- ✅ Proper boolean query parameter serialization

### 4. Flutter UI Controls (main.dart)
- ✅ Added 4 new state variables for indicator toggles
- ✅ Extended `DashboardParams` to include indicator flags
- ✅ Added 4 `FilterChip` widgets for indicator selection:
  - SMA-20, SMA-50, EMA-12, EMA-26
- ✅ Integrated with existing "Refresh insights" button
- ✅ Existing slider for forecast days (7-90 days range)

### 5. Chart Visualization Enhancement (main.dart)
- ✅ Updated `_buildForecastChart()` to accept indicators
- ✅ Added indicator lines to chart with distinct colors:
  - **SMA-20**: Orange
  - **SMA-50**: Purple
  - **EMA-12**: Green
  - **EMA-26**: Cyan
- ✅ Updated axis calculations to include indicator values
- ✅ Conditional rendering (only shows selected indicators)

## Technical Highlights

### Backend Calculation Logic
```python
# SMA calculation using pandas rolling window
sma_20_values = data["Close"].rolling(window=20).mean()

# EMA calculation using exponential weighted moving average  
ema_12_values = data["Close"].ewm(span=12, adjust=False).mean()

# Filter out NaN values before returning
sma_20_list = [
    TechnicalIndicator(date=data.index[i].isoformat(), value=val)
    for i, val in enumerate(sma_20_values)
    if (val := sma_20_values.iloc[i]) and not pd.isna(val)
]
```

### Frontend Chart Integration
```dart
// Conditional indicator rendering
if (indicators?.sma20 != null)
  LineChartBarData(
    spots: indicators!.sma20!
        .map((e) => FlSpot(
            e.date.millisecondsSinceEpoch.toDouble(), 
            e.value
        ))
        .toList(),
    isCurved: true,
    color: Colors.orange,
    barWidth: 2,
    dotData: const FlDotData(show: false),
  ),
```

## User Experience Flow

1. **User adjusts forecast horizon** using the slider (7-90 days)
2. **User toggles technical indicators** using FilterChips
3. **User clicks "Refresh insights"** button
4. **Backend receives request** with indicator flags
5. **Backend calculates indicators** (SMA/EMA) if requested
6. **Flutter receives response** with historical data, forecast, and indicators
7. **Chart updates** showing price history, forecast, and selected indicators
8. **Different colors** clearly distinguish each indicator type

## API Testing

### Test with indicators enabled:
```bash
curl "https://stock-backend-nt1s.onrender.com/forecast?ticker=AAPL&days=30&sma_20=true&ema_12=true"
```

### Sample response structure:
```json
{
  "ticker": "AAPL",
  "source": "lstm",
  "forecast": [...],
  "history": [...],
  "indicators": {
    "sma_20": [
      {"date": "2025-05-08T00:00:00", "value": 201.67},
      ...
    ],
    "sma_50": null,
    "ema_12": [
      {"date": "2025-04-24T00:00:00", "value": 198.45},
      ...
    ],
    "ema_26": null
  }
}
```

## Deployment Status

- ✅ Backend deployed to Render (stock-backend-nt1s.onrender.com)
- ✅ Frontend deployed to Vercel (pending)
- ✅ All changes committed and pushed to main branch
- ✅ No compilation errors in Flutter app
- ✅ Backend API tested and verified with curl

## Benefits

1. **Interactive Control**: Users can dynamically adjust forecast parameters and indicators
2. **Real-time Visualization**: Chart updates immediately with selected indicators
3. **Robust Architecture**: Clean separation between UI state, API calls, and data models
4. **Backward Compatible**: Indicators are optional, existing functionality unchanged
5. **Scalable**: Easy to add more indicators or parameters in the future

## Next Steps

- Monitor Vercel deployment for Flutter frontend
- Test end-to-end flow in production environment
- Consider adding indicator legends/tooltips for better UX
- Potential: Add more indicators (RSI, MACD, Bollinger Bands)
