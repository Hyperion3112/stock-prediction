# AI Powered Stock Forecast (FastAPI + Flutter)

[![Vercel](https://img.shields.io/badge/Vercel-Deployed-black?style=flat&logo=vercel)](https://vercel.com)
[![Flutter](https://img.shields.io/badge/Flutter-3.35.5-blue?style=flat&logo=flutter)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-Latest-green?style=flat&logo=fastapi)](https://fastapi.tiangolo.com)
[![License](https://img.shields.io/badge/License-MIT-yellow?style=flat)](LICENSE)

A cutting-edge financial analysis platform that leverages **LSTM (Long Short-Term Memory)** neural networks to predict stock price movements with unprecedented accuracy. This project combines a stateless **FastAPI** backend (`app.py`) that serves historical market data, linear/LSTM forecasts, and VADER sentiment scores with a modern **Flutter web client** (`flutter_app/`) featuring an elegant glass morphism UI, interactive charts, and comprehensive technical indicators.

The Flutter frontend can be deployed to Vercel as a static site, while the backend can be hosted on Render or any Python-compatible platform.

## 🎯 Live Demo

> **Note**: Replace with your actual Vercel deployment URL once live

## 📸 Screenshots

### Dashboard Overview
The main dashboard features a prominent hero header, interactive price charts, and comprehensive market metrics with a modern glass morphism design.

### Forecast Chart
Advanced LSTM-based predictions with technical indicator overlays (SMA/EMA) and smart tooltips for detailed analysis.

## Features

### Frontend (Flutter Web)
- **🎨 Modern Glass Morphism UI**: Professional gradient backgrounds with frosted glass containers and smooth animations
- **📊 Interactive Charts**: Real-time price history and forecast visualization using fl_chart library with tooltips
- **🤖 LSTM Neural Networks**: Advanced deep learning models for accurate price predictions
- **📈 Technical Indicators**: SMA-20/50 (Simple Moving Averages) and EMA-12/26 (Exponential Moving Averages)
- **💭 Sentiment Analysis**: Real-time news sentiment scoring using VADER
- **🎯 Responsive Design**: Optimized for desktop and mobile with adaptive layouts
- **✨ Animated Transitions**: Smooth fade-in effects, skeleton loaders, and rolling loading messages
- **🔄 Dynamic Color Accents**: Ticker-specific color schemes for better visual distinction
- **📱 Comprehensive Help**: Interactive tooltip with step-by-step usage guide

### Backend (FastAPI)
- **⚡ Fast REST API**: Efficient endpoints for market data, forecasts, and sentiment
- **🧠 LSTM Model Support**: Pre-trained models for AAPL, META, NVDA, and TSLA
- **📊 Real-time Data**: Yahoo Finance integration for live market data
- **🔍 Sentiment Scoring**: VADER-based analysis of financial news headlines
- **🎯 Flexible Forecasting**: Support for both linear and LSTM-based predictions
- **📦 Model Management**: Auto-discovery of trained models in the models/ directory

## Backend (FastAPI)

### Requirements

- Python 3.9+
- `pip install -r requirements.txt`
  - Includes FastAPI, Uvicorn, Pandas, NumPy, yfinance, joblib, TensorFlow (for
    optional LSTM inference), and VADER sentiment.
  - On Apple Silicon, install `tensorflow-macos` + `tensorflow-metal` for GPU acceleration.

### Running locally

```bash
cd "/Users/shaunak/Projects/Stock Prediction"
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn app:app --reload --port 8000
```

Key endpoints:

| Method | Path         | Description                                                |
|--------|--------------|------------------------------------------------------------|
| GET    | `/health`    | Lightweight health probe.                                 |
| GET    | `/overview`  | Historical OHLCV data + summary metrics + price history.  |
| GET    | `/forecast`  | Linear or LSTM forecast (if a saved model exists).        |
| GET    | `/sentiment` | Latest Yahoo Finance headlines scored with VADER.         |
| GET    | `/models`    | Lists available saved LSTM model + scaler pairs.          |

Environment variables:

- `HOST` / `PORT` (optional) when launching via `python app.py` or Uvicorn.
- Model artifacts live in `models/` and are auto-discovered (`*.keras` + scaler `.pkl`).

### Tests

Run the existing pytest suite (validates the linear forecast helper):

```bash
pytest
```

### Deploy to Render (production)

The repo ships with a `render.yaml` and `Procfile` so you can deploy the FastAPI
backend to [Render](https://render.com/) with a couple of clicks:

1. Commit and push your changes to GitHub.
2. Log in to Render, choose **New → Web Service**, and select your repository.
3. Render auto-detects the `render.yaml` manifest—accept the defaults (Python
  runtime, `uvicorn` start command, `/health` check).
4. Click **Create Web Service**; Render will build the service using
  `pip install -r requirements.txt` and launch `uvicorn app:app` on the
  allocated `$PORT`.
5. Once the service status is **Live**, grab the public URL (e.g.
  `https://stock-backend.onrender.com`) and set it as the
  `API_BASE_URL` for the Flutter web build.

Future pushes to the `main` branch will auto-deploy as long as
`autoDeploy: true` remains in `render.yaml`.

## Flutter Web Client

The Flutter front-end provides a premium user experience with a Material 3 glass morphism design, featuring interactive charts (via `fl_chart`), animated hero headers, comprehensive technical indicators (SMA/EMA), and real-time sentiment analysis. The UI adapts dynamically to different screen sizes and includes helpful tooltips and loading states. The app is optimized for Flutter web builds and can be deployed to Vercel as a static site.

### Key UI Components

- **Hero Header**: Large gradient title with animated icon, comprehensive project description, and positioned help button
- **Glass Containers**: Frosted glass effect with backdrop blur and gradient borders
- **Interactive Charts**: 
  - Historical price chart with 120-day lookback
  - Forecast chart with separate historical and predicted lines
  - Technical indicator overlays (SMA-20/50, EMA-12/26)
  - Smart tooltips with date and price information
- **Metric Cards**: Animated cards displaying latest close, volume, range, and volatility
- **Loading States**: Shimmer effects and rolling messages during data fetches
- **Dynamic Theming**: Ticker-based accent colors for visual variety

### Project structure

```
flutter_app/
  pubspec.yaml            # Flutter + package dependencies (fl_chart 0.66.2)
  analysis_options.yaml   # Lints
  lib/
    api_client.dart       # REST wrapper around FastAPI endpoints
    models.dart           # JSON data classes for API responses
    main.dart             # Dashboard UI + charts + animations
  build/
    web/                  # Compiled output for deployment
```

### Local development

Make sure Flutter 3.3+ is installed (with web support enabled):

```bash
cd flutter_app
flutter pub get

# Run with local backend
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000

# Or serve the built version locally
flutter build web --no-tree-shake-icons
cd build/web
python3 -m http.server 3000
```

**Note**: Use `--no-tree-shake-icons` flag to avoid icon tree shaking issues during build.

The `API_BASE_URL` `dart-define` points the web client at your local FastAPI server (default: `http://localhost:8000`).

### Build for Vercel

```bash
cd flutter_app
flutter build web --release --no-tree-shake-icons --dart-define=API_BASE_URL=https://your-backend.example.com
```

The compiled output will be in `flutter_app/build/web`. Deploy this directory to Vercel as a static site:

1. **Push to GitHub**: Commit and push the built files to your repository
2. **Connect to Vercel**: Import your repository in the Vercel dashboard
3. **Configure Build Settings**:
   - Build Command: `cd flutter_app && flutter build web --release --no-tree-shake-icons`
   - Output Directory: `flutter_app/build/web`
   - Install Command: (leave default or use custom Flutter installation)
4. **Set Environment Variables**: Add `API_BASE_URL` as a Vercel environment variable pointing to your hosted FastAPI backend
5. **Deploy**: Vercel will automatically build and deploy on every push to main

The project includes a `vercel.json` configuration for proper routing of Flutter web apps.

## Training LSTM models (optional)

The project includes pre-trained LSTM models for AAPL, META, NVDA, and TSLA. To train additional models:

```bash
source .venv/bin/activate
python train_lstm.py TSLA --epochs 50 --batch-size 32
```

This generates:
- `models/lstm_TSLA.keras` — Trained LSTM model
- `models/scaler_TSLA.save` — Min-max scaler for normalization

Any ticker with a matching model+scaler pair automatically appears in the `/models` endpoint and enables LSTM forecasts in the Flutter app.

## Repository layout

- `app.py` — FastAPI backend with REST endpoints
- `flutter_app/` — Flutter web client with glass morphism UI
  - `lib/main.dart` — Main dashboard with hero header, charts, and animations
  - `lib/api_client.dart` — API integration layer
  - `lib/models.dart` — Data models for API responses
  - `build/web/` — Compiled static site for Vercel deployment
- `train_lstm.py` — Training script for LSTM models
- `models/` — Pre-trained LSTM models and scalers (AAPL, META, NVDA, TSLA)
- `tests/` — Pytest suite for backend validation
- `requirements.txt` — Python backend dependencies
- `vercel.json` — Vercel deployment configuration
- `render.yaml` — Render deployment configuration for backend

## Technical Stack

### Frontend
- **Flutter 3.35.5** with Dart 3.9.2
- **fl_chart 0.66.2** for interactive charts
- **intl** for number and date formatting
- **http** for API communication
- Material 3 design with custom glass morphism theme

### Backend
- **FastAPI** for REST API
- **TensorFlow/Keras** for LSTM models
- **yfinance** for market data
- **VADER** for sentiment analysis
- **Pandas/NumPy** for data processing

## Recent Updates

### UI/UX Improvements (October 2025)
- ✅ Redesigned hero header with prominent title and comprehensive description
- ✅ Fixed tooltip positioning on forecast and history charts
- ✅ Added professional gradient background (removed complex patterns)
- ✅ Implemented glass morphism design system throughout
- ✅ Added animated loading states with rolling messages
- ✅ Repositioned help button to top-right corner for better accessibility
- ✅ Enhanced chart tooltips with better formatting and color coding
- ✅ Updated branding from "AI Stock Insights" to "AI Powered Stock Forecast"

### Technical Improvements
- ✅ Implemented proper chart axis tick generation
- ✅ Added technical indicator overlays (SMA-20/50, EMA-12/26)
- ✅ Improved tooltip logic with smart positioning
- ✅ Added skeleton loaders for better perceived performance
- ✅ Optimized build process with `--no-tree-shake-icons` flag

## Next steps

- 🔐 Secure the backend with authentication and rate limiting
- ⚡ Add caching layer (e.g., Redis) to reduce API calls
- 📊 Expand Flutter UI with watchlists and multi-ticker comparisons
- 🔔 Implement price alerts and notifications
- 📱 Add mobile app versions (iOS/Android)
- 🎯 Improve LSTM model accuracy with hyperparameter tuning
- 📈 Add more technical indicators (RSI, MACD, Bollinger Bands)
- 🌐 Support for international markets and cryptocurrencies
