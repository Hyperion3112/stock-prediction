# AI Stock Insights (FastAPI + Flutter)

The project now exposes a stateless **FastAPI** backend (`app.py`) that serves
historical market data, linear/LSTM forecasts, and VADER sentiment scores. A new
Flutter web client (`flutter_app/`) consumes these APIs and can be deployed to
Vercel as a static site after running `flutter build web`.

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

The Flutter front-end mirrors the Streamlit experience with a Material 3 UI,
interactive charts (via `fl_chart`), and toggles for LSTM/sentiment. It consumes
the FastAPI endpoints and is optimized for Flutter web builds so the output can
be hosted on Vercel.

### Project structure

```
flutter_app/
  pubspec.yaml            # Flutter + package dependencies
  analysis_options.yaml   # Lints
  lib/
    api_client.dart       # REST wrapper around FastAPI endpoints
    models.dart           # JSON data classes
    main.dart             # Dashboard UI + charts
```

### Local development

Make sure Flutter 3.3+ is installed (with web support enabled):

```bash
cd flutter_app
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

The `API_BASE_URL` `dart-define` points the web client at your local FastAPI server.

### Build for Vercel

```bash
cd flutter_app
flutter build web --release --dart-define=API_BASE_URL=https://your-backend.example.com
```

Deploy the `flutter_app/build/web` directory to Vercel as a static site. Add the
same `API_BASE_URL` as a Vercel environment variable (exposed at build time) so
the Flutter app points to your hosted FastAPI backend.

## Training LSTM models (optional)

The original training script still works:

```bash
source .venv/bin/activate
python train_lstm.py TSLA --epochs 5
```

It generates `models/TSLA.keras` and `models/TSLA_scaler.pkl`. Any ticker with a
matching pair automatically appears in both the `/models` endpoint and the
Flutter toggle for LSTM forecasts.

## Repository layout

- `app.py` — FastAPI backend.
- `flutter_app/` — Flutter web client ready for Vercel.
- `train_lstm.py` — Helper script to create new LSTM models.
- `models/` — Saved model/scaler artifacts (AAPL provided by default).
- `tests/` — Pytest suite.
- `requirements.txt` — Python backend dependencies.

## Next steps

- Secure the backend (auth, rate limiting) before exposing publicly.
- Add caching (e.g., Redis) to avoid repeated yfinance/news fetches.
- Expand the Flutter UI with watchlists, multi-ticker comparisons, and alerts.
