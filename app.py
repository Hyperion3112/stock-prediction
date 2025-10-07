"""FastAPI backend for AI Stock Analysis.

This module replaces the original Streamlit UI with a stateless API that a Flutter
frontend (deployed on Vercel) can consume. It keeps the core data, forecasting, and
sentiment utilities so existing tests remain valid.
"""

from __future__ import annotations

import os
import re
from datetime import datetime, timedelta
from pathlib import Path
from typing import Iterable, Optional

import joblib
import numpy as np
import pandas as pd
import yfinance as yf
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sklearn.preprocessing import MinMaxScaler

try:  # pragma: no cover - optional dependency
    from vaderSentiment.vaderSentiment import SentimentIntensityAnalyzer
except ImportError:  # pragma: no cover - optional dependency
    SentimentIntensityAnalyzer = None


PRESET_MAP = {
    "1M": 30,
    "3M": 90,
    "6M": 180,
    "1Y": 365,
    "2Y": 365 * 2,
    "5Y": 365 * 5,
}

INTERVAL_OPTIONS = ["1m", "5m", "15m", "30m", "1h", "1d", "1wk", "1mo"]
BASE_DIR = Path(__file__).resolve().parent
DEFAULT_MODEL_DIR = BASE_DIR / "models"
NEWS_RESULT_LIMIT = 10
SENTIMENT_ANALYZER = SentimentIntensityAnalyzer() if SentimentIntensityAnalyzer else None

_POSITIVE_WORDS = {
    "gain",
    "growth",
    "beat",
    "positive",
    "bullish",
    "surge",
    "record",
    "optimistic",
    "upgrade",
    "strong",
    "outperform",
    "improve",
    "rally",
    "advance",
    "profit",
}

_NEGATIVE_WORDS = {
    "loss",
    "decline",
    "drop",
    "negative",
    "bearish",
    "plunge",
    "downgrade",
    "weak",
    "miss",
    "concern",
    "risk",
    "lawsuit",
    "selloff",
    "crash",
    "debt",
}

MAX_INTERVAL_SPAN_DAYS: dict[str, int] = {
    "1m": 7,
    "2m": 60,
    "5m": 60,
    "15m": 60,
    "30m": 60,
    "60m": 730,
    "1h": 730,
    "90m": 60,
}


class Metadata(BaseModel):
    ticker: str
    name: Optional[str] = None
    sector: Optional[str] = None
    industry: Optional[str] = None
    website: Optional[str] = None


class OverviewMetrics(BaseModel):
    latest_close: float
    pct_change: float
    latest_volume: Optional[float] = Field(default=None, description="Most recent volume, if available")
    range_high: Optional[float] = None
    range_low: Optional[float] = None
    data_points: int


class DayHighlight(BaseModel):
    date: datetime
    percent_change: float


class OverviewHighlights(BaseModel):
    best_day: Optional[DayHighlight] = None
    worst_day: Optional[DayHighlight] = None
    annualized_volatility: Optional[float] = None


class PricePoint(BaseModel):
    date: datetime
    close: float


class OverviewResponse(BaseModel):
    ticker: str
    metadata: Metadata
    metrics: OverviewMetrics
    highlights: OverviewHighlights
    history: list[PricePoint]


class ForecastPoint(BaseModel):
    date: datetime
    value: float


class ForecastResponse(BaseModel):
    ticker: str
    source: str
    forecast: list[ForecastPoint]
    history: list[PricePoint]
    note: Optional[str] = None


class SentimentRecord(BaseModel):
    headline: str
    sentiment: str
    score: float
    publisher: Optional[str] = None
    summary: Optional[str] = None
    link: Optional[str] = None
    published: Optional[datetime] = None


class SentimentSummary(BaseModel):
    total: int
    average_score: Optional[float] = None
    positive: int = 0
    neutral: int = 0
    negative: int = 0
    dominant_sentiment: Optional[str] = None


class SentimentResponse(BaseModel):
    ticker: str
    summary: SentimentSummary
    records: list[SentimentRecord]


class ModelInfo(BaseModel):
    ticker: str
    model_path: str
    scaler_path: str


def _parse_iso_date(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        parsed = datetime.fromisoformat(value)
    except ValueError as exc:  # pragma: no cover - defensive
        raise ValueError(f"Invalid ISO date '{value}'") from exc
    if parsed.tzinfo:
        parsed = parsed.astimezone(tz=None).replace(tzinfo=None)
    return parsed


def _resolve_date_range(
    start: Optional[datetime],
    end: Optional[datetime],
    default_days: int,
) -> tuple[datetime, datetime]:
    today = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    if end is None:
        end = today
    if start is None:
        start = end - timedelta(days=default_days)
    if start >= end:
        raise ValueError("start_date must be earlier than end_date")
    return start, end


def _validate_interval(interval: str) -> str:
    return interval if interval in INTERVAL_OPTIONS else "1d"


def load_data(
    ticker: str,
    start: Optional[datetime],
    end: Optional[datetime],
    interval: str = "1d",
) -> Optional[pd.DataFrame]:
    ticker_clean = ticker.strip().upper()
    interval_clean = _validate_interval(interval)

    end = end or datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    start = start or end - timedelta(days=PRESET_MAP.get("6M", 180))

    max_span_days = MAX_INTERVAL_SPAN_DAYS.get(interval_clean)
    if max_span_days is not None and end is not None:
        span = end - start
        allowed_span = timedelta(days=max_span_days)
        if span > allowed_span:
            start = end - allowed_span

    start_str = start.strftime("%Y-%m-%d") if start else None
    end_str = end.strftime("%Y-%m-%d") if end else None

    try:
        df = yf.download(
            ticker_clean,
            start=start_str,
            end=end_str,
            interval=interval_clean,
            progress=False,
            prepost=False,
            threads=False,
        )
    except Exception:  # pragma: no cover - network failures
        return None

    if df is None or df.empty:
        return None

    df = df.reset_index()

    if isinstance(df.columns, pd.MultiIndex):
        try:
            df.columns = df.columns.droplevel(-1)
        except (ValueError, AttributeError):
            df.columns = ["_".join(str(level) for level in col if level) for col in df.columns]

    if "Date" not in df.columns and "Datetime" in df.columns:
        df = df.rename(columns={"Datetime": "Date"})

    df["Date"] = pd.to_datetime(df["Date"]).dt.tz_localize(None)

    numeric_cols = [col for col in ["Open", "High", "Low", "Close", "Adj Close", "Volume"] if col in df.columns]
    for col in numeric_cols:
        df[col] = pd.to_numeric(df[col], errors="coerce")

    df = df.dropna(subset=["Close"]).sort_values("Date").reset_index(drop=True)
    return df


def fetch_company_metadata(ticker: str) -> dict[str, Optional[str]]:  # pragma: no cover - network heavy
    ticker_clean = ticker.strip().upper()
    try:
        info = yf.Ticker(ticker_clean).get_info()
    except Exception:
        info = {}

    return {
        "name": info.get("longName") or info.get("shortName") or ticker_clean,
        "sector": info.get("sector"),
        "industry": info.get("industry"),
        "website": info.get("website"),
    }


def forecast_linear(data: pd.DataFrame, days: int = 30) -> pd.DataFrame:
    if data.empty:
        raise ValueError("No data available for forecasting")

    closes = data.dropna(subset=["Close"]).copy()
    closes_values = closes["Close"].astype(float).values

    if len(closes_values) == 1:
        slope = 0.0
        intercept = closes_values[0]
    else:
        x = np.arange(len(closes_values))
        slope, intercept = np.polyfit(x, closes_values, 1)

    future_index = np.arange(len(closes_values), len(closes_values) + days)
    forecast_values = slope * future_index + intercept

    last_date = pd.to_datetime(closes["Date"].iloc[-1])
    future_dates = pd.date_range(last_date + pd.Timedelta(days=1), periods=days, freq="D")

    return pd.DataFrame({"Date": future_dates, "Forecast": forecast_values})


def forecast_lstm_inference(
    data: pd.DataFrame,
    model_path: str,
    scaler_path: str,
    days: int = 30,
    window: int = 20,
) -> pd.DataFrame:
    if not os.path.exists(model_path):
        raise FileNotFoundError(f"Model file not found: {model_path}")
    if not os.path.exists(scaler_path):
        raise FileNotFoundError(f"Scaler file not found: {scaler_path}")

    closes = data.dropna(subset=["Close"])["Close"].astype(float).values.reshape(-1, 1)
    if len(closes) < window:
        raise ValueError("Not enough data points for the selected LSTM window size.")

    scaler = joblib.load(scaler_path)
    closes_scaled = scaler.transform(closes)

    from tensorflow.keras.models import load_model  # pylint: disable=import-error

    model = load_model(model_path, compile=False)

    history_scaled = list(closes_scaled.flatten())
    preds_scaled: list[float] = []

    for _ in range(days):
        window_slice = np.array(history_scaled[-window:]).reshape(1, window, 1)
        next_scaled = model.predict(window_slice, verbose=0)[0][0]
        preds_scaled.append(float(next_scaled))
        history_scaled.append(float(next_scaled))

    preds = scaler.inverse_transform(np.array(preds_scaled).reshape(-1, 1)).flatten()
    last_date = pd.to_datetime(data["Date"].iloc[-1])
    future_dates = pd.date_range(last_date + pd.Timedelta(days=1), periods=days, freq="D")

    return pd.DataFrame({"Date": future_dates, "Forecast": preds})


def forecast_lstm_autotrain(
    data: pd.DataFrame,
    days: int = 30,
    window: int = 20,
    epochs: int = 8,
    learning_rate: float = 5e-4,
    ticker: Optional[str] = None,
    persist: bool = False,
) -> pd.DataFrame:
    closes_series = data.dropna(subset=["Close"])["Close"].astype(float)
    closes = closes_series.values.reshape(-1, 1)
    if len(closes) <= window:
        raise ValueError("Not enough data points to train an LSTM model for the requested window size.")

    scaler = MinMaxScaler(feature_range=(0.0, 1.0))
    closes_scaled = scaler.fit_transform(closes).flatten()

    sequences: list[np.ndarray] = []
    targets: list[float] = []
    for idx in range(window, len(closes_scaled)):
        sequences.append(closes_scaled[idx - window : idx])
        targets.append(float(closes_scaled[idx]))

    if not sequences:
        raise ValueError("Unable to create training sequences for LSTM model.")

    X = np.array(sequences, dtype=np.float32).reshape(-1, window, 1)
    y = np.array(targets, dtype=np.float32)

    batch_size = int(min(32, len(X))) or 1

    from tensorflow.keras.callbacks import EarlyStopping  # pylint: disable=import-error
    from tensorflow.keras.layers import Dense, Dropout, LSTM  # pylint: disable=import-error
    from tensorflow.keras.models import Sequential  # pylint: disable=import-error
    from tensorflow.keras.optimizers import Adam  # pylint: disable=import-error

    model = Sequential(
        [
            LSTM(32, input_shape=(window, 1), return_sequences=True),
            Dropout(0.1),
            LSTM(24),
            Dense(12, activation="relu"),
            Dense(1),
        ]
    )
    model.compile(optimizer=Adam(learning_rate=learning_rate), loss="mse")

    callbacks = [EarlyStopping(monitor="loss", patience=2, restore_best_weights=True)]

    model.fit(X, y, epochs=epochs, batch_size=batch_size, shuffle=False, verbose=0, callbacks=callbacks)

    history_scaled = list(closes_scaled)
    preds_scaled: list[float] = []
    for _ in range(days):
        window_slice = np.array(history_scaled[-window:], dtype=np.float32).reshape(1, window, 1)
        next_scaled = float(model.predict(window_slice, verbose=0)[0][0])
        next_scaled = float(np.clip(next_scaled, 0.0, 1.0))
        preds_scaled.append(next_scaled)
        history_scaled.append(next_scaled)

    preds = scaler.inverse_transform(np.array(preds_scaled, dtype=np.float32).reshape(-1, 1)).flatten()

    if persist and ticker:
        ticker_clean = ticker.strip().upper()
        model_dir = Path(DEFAULT_MODEL_DIR)
        model_dir.mkdir(parents=True, exist_ok=True)
        model_path = model_dir / f"lstm_{ticker_clean}.keras"
        scaler_path = model_dir / f"scaler_{ticker_clean}.save"
        model.save(model_path, include_optimizer=False)
        joblib.dump(scaler, scaler_path)

    last_date = pd.to_datetime(data["Date"].iloc[-1])
    future_dates = pd.date_range(last_date + pd.Timedelta(days=1), periods=days, freq="D")

    return pd.DataFrame({"Date": future_dates, "Forecast": preds})


def _analyze_headline_sentiment(headline: str | None, summary: str | None = None) -> tuple[str, float]:
    if not headline and not summary:
        return "Neutral", 0.0

    weighted_texts: list[tuple[str, float]] = []
    if headline and headline.strip():
        weighted_texts.append((headline, 0.7))
    if summary and summary.strip():
        weight = 0.3 if weighted_texts else 1.0
        weighted_texts.append((summary, weight))

    if not weighted_texts:
        return "Neutral", 0.0

    if SENTIMENT_ANALYZER is not None:
        total_weight = sum(weight for _, weight in weighted_texts) or 1.0
        compound = 0.0
        for text, weight in weighted_texts:
            scores = SENTIMENT_ANALYZER.polarity_scores(text)
            compound += weight * float(scores.get("compound", 0.0))
        compound /= total_weight
    else:
        tokens: list[str] = []
        for text, _ in weighted_texts:
            tokens.extend(re.findall(r"[a-zA-Z']+", text.lower()))
        if not tokens:
            return "Neutral", 0.0
        pos_hits = sum(1 for token in tokens if token in _POSITIVE_WORDS)
        neg_hits = sum(1 for token in tokens if token in _NEGATIVE_WORDS)
        compound = (pos_hits - neg_hits) / max(len(tokens), 1)
        compound = max(min(compound, 1.0), -1.0)

    if compound >= 0.05:
        return "Positive", compound
    if compound <= -0.05:
        return "Negative", compound
    return "Neutral", compound


def fetch_news_with_sentiment(ticker: str, limit: int = NEWS_RESULT_LIMIT) -> pd.DataFrame:
    ticker_clean = ticker.strip().upper()
    try:
        raw_news = yf.Ticker(ticker_clean).news or []
    except Exception:
        raw_news = []

    records: list[dict[str, object]] = []
    for item in raw_news[: limit * 2]:  # fetch a few extra in case of missing fields
        title = item.get("title") or item.get("headline")
        if not title:
            continue
        summary = item.get("summary") or ""
        link = item.get("link") or item.get("url")
        publisher = item.get("publisher") or item.get("provider")
        ts = item.get("providerPublishTime") or item.get("published")
        published = None
        if ts:
            try:
                published = datetime.utcfromtimestamp(int(ts))
            except (TypeError, ValueError):
                try:
                    published = pd.to_datetime(ts)
                except Exception:  # pragma: no cover - defensive
                    published = None

        label, compound = _analyze_headline_sentiment(title, summary)

        records.append(
            {
                "Headline": title,
                "Summary": summary,
                "Link": link,
                "Publisher": publisher,
                "Published": published,
                "Score": compound,
                "Sentiment": label,
            }
        )

    if not records:
        return pd.DataFrame()

    news_df = pd.DataFrame(records).sort_values("Published", ascending=False)
    return news_df.head(limit)


def _normalise_ticker_from_stem(stem: str) -> Optional[str]:
    cleaned = stem.upper()
    for prefix in ("LSTM_", "MODEL_", "STOCK_"):
        if cleaned.startswith(prefix):
            cleaned = cleaned[len(prefix) :]
    cleaned = re.sub(r"[^A-Z0-9]", "", cleaned)
    return cleaned or None


def _find_scaler_path(model_root: Path, ticker: str) -> Optional[Path]:
    candidates: Iterable[Path] = [
        model_root / f"{ticker}_SCALER.pkl",
        model_root / f"{ticker}_SCALER.save",
        model_root / f"{ticker}_scaler.pkl",
        model_root / f"{ticker}_scaler.save",
        model_root / f"SCALER_{ticker}.pkl",
        model_root / f"SCALER_{ticker}.save",
        model_root / f"scaler_{ticker}.pkl",
        model_root / f"scaler_{ticker}.save",
        model_root / f"lstm_{ticker}_scaler.pkl",
        model_root / f"lstm_{ticker}_scaler.save",
        model_root / f"LSTM_{ticker}_SCALER.pkl",
        model_root / f"LSTM_{ticker}_SCALER.save",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    ticker_lower = ticker.lower()
    more_candidates = [
        model_root / f"{ticker_lower}_scaler.pkl",
        model_root / f"{ticker_lower}_scaler.save",
        model_root / f"scaler_{ticker_lower}.pkl",
        model_root / f"scaler_{ticker_lower}.save",
        model_root / f"lstm_{ticker_lower}_scaler.pkl",
        model_root / f"lstm_{ticker_lower}_scaler.save",
    ]
    for candidate in more_candidates:
        if candidate.exists():
            return candidate
    return None


def list_available_models(model_dir: str = DEFAULT_MODEL_DIR) -> dict[str, dict[str, Path]]:
    model_root = Path(model_dir)
    if not model_root.is_dir():
        return {}

    models: dict[str, dict[str, Path]] = {}
    model_files: Iterable[Path] = list(model_root.glob("*.keras")) + list(model_root.glob("*.h5"))
    for model_path in model_files:
        ticker = _normalise_ticker_from_stem(model_path.stem)
        if not ticker:
            continue
        scaler_path = _find_scaler_path(model_root, ticker)
        if scaler_path:
            models[ticker] = {"model": model_path, "scaler": scaler_path}
    return models


def load_lstm_artifacts(ticker: str, model_catalog: dict[str, dict[str, Path]]):
    ticker_clean = ticker.strip().upper()
    entry = model_catalog.get(ticker_clean)
    if not entry:
        raise FileNotFoundError(f"No saved LSTM model for {ticker_clean}")
    return str(entry["model"]), str(entry["scaler"])


def _compute_overview(data: pd.DataFrame) -> tuple[OverviewMetrics, OverviewHighlights]:
    latest_close = float(data["Close"].iloc[-1])
    prev_close = float(data["Close"].iloc[-2]) if len(data) > 1 else latest_close
    pct_change = ((latest_close - prev_close) / prev_close * 100) if prev_close else 0.0

    latest_volume = None
    if "Volume" in data.columns and pd.notna(data["Volume"]).any():
        latest_volume = float(data["Volume"].iloc[-1])

    range_high = float(data["High"].max()) if "High" in data.columns else None
    range_low = float(data["Low"].min()) if "Low" in data.columns else None

    metrics = OverviewMetrics(
        latest_close=latest_close,
        pct_change=pct_change,
        latest_volume=latest_volume,
        range_high=range_high,
        range_low=range_low,
        data_points=len(data),
    )

    daily_returns = data.set_index("Date")["Close"].pct_change().dropna()
    best_day = None
    worst_day = None
    if not daily_returns.empty:
        best_idx = daily_returns.idxmax()
        best_day = DayHighlight(date=pd.to_datetime(best_idx).to_pydatetime(), percent_change=float(daily_returns.max() * 100))
        worst_idx = daily_returns.idxmin()
        worst_day = DayHighlight(date=pd.to_datetime(worst_idx).to_pydatetime(), percent_change=float(daily_returns.min() * 100))

    annualized_vol = None
    if len(daily_returns) >= 5:
        annualized_vol = float(daily_returns.tail(30).std() * np.sqrt(252) * 100)

    highlights = OverviewHighlights(best_day=best_day, worst_day=worst_day, annualized_volatility=annualized_vol)
    return metrics, highlights


def _serialize_history(data: pd.DataFrame, limit: int = 180) -> list[PricePoint]:
    history = []
    for _, row in data.tail(limit).iterrows():
        ts = row["Date"]
        if isinstance(ts, pd.Timestamp):
            ts = ts.to_pydatetime()
        history.append(PricePoint(date=ts, close=float(row["Close"])) )
    return history


def _serialize_forecast(df: pd.DataFrame) -> list[ForecastPoint]:
    points: list[ForecastPoint] = []
    for _, row in df.iterrows():
        ts = row["Date"]
        if isinstance(ts, pd.Timestamp):
            ts = ts.to_pydatetime()
        points.append(ForecastPoint(date=ts, value=float(row["Forecast"])) )
    return points


app = FastAPI(title="AI Stock Analytics API", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health_check() -> dict:
    """Simple health check endpoint."""
    return {"status": "ok", "timestamp": datetime.now(UTC).isoformat()}


@app.get("/health/forecast")
def health_forecast_check() -> dict:
    """Health check for forecast dependencies."""
    try:
        import tensorflow as tf
        import yfinance as yf
        from sklearn.preprocessing import MinMaxScaler
        
        return {
            "status": "ok",
            "tensorflow_version": tf.__version__,
            "yfinance_available": True,
            "sklearn_available": True,
            "timestamp": datetime.now(UTC).isoformat()
        }
    except Exception as e:
        return {
            "status": "error",
            "error": str(e),
            "timestamp": datetime.now(UTC).isoformat()
        }


@app.get("/overview", response_model=OverviewResponse)
def get_overview(
    ticker: str = Query(..., description="Ticker symbol, e.g. AAPL"),
    start_date: Optional[str] = Query(None, description="ISO date for range start (inclusive)"),
    end_date: Optional[str] = Query(None, description="ISO date for range end (inclusive)"),
    interval: str = Query("1d", description="Yahoo Finance sampling interval"),
    preset: Optional[str] = Query("6M", description="Fallback preset window if explicit dates omitted"),
) -> OverviewResponse:
    try:
        start = _parse_iso_date(start_date)
        end = _parse_iso_date(end_date)
        default_days = PRESET_MAP.get(preset or "6M", 180)
        start, end = _resolve_date_range(start, end, default_days)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    data = load_data(ticker, start, end, interval)
    if data is None or data.empty:
        raise HTTPException(status_code=404, detail="No price data available for the requested configuration.")

    metadata_dict = fetch_company_metadata(ticker)
    metrics, highlights = _compute_overview(data)
    history = _serialize_history(data)

    metadata = Metadata(
        ticker=ticker.strip().upper(),
        name=metadata_dict.get("name"),
        sector=metadata_dict.get("sector"),
        industry=metadata_dict.get("industry"),
        website=metadata_dict.get("website"),
    )

    return OverviewResponse(
        ticker=metadata.ticker,
        metadata=metadata,
        metrics=metrics,
        highlights=highlights,
        history=history,
    )


@app.get("/forecast", response_model=ForecastResponse)
def get_forecast(
    ticker: str = Query(..., description="Ticker symbol, e.g. AAPL"),
    days: int = Query(30, ge=1, le=365, description="Number of future days to forecast"),
    interval: str = Query("1d", description="Historical sampling interval"),
    start_date: Optional[str] = Query(None),
    end_date: Optional[str] = Query(None),
    use_lstm: bool = Query(True, description="Whether to require an LSTM forecast"),
    window: int = Query(20, ge=5, le=120, description="Rolling window for LSTM inputs"),
) -> ForecastResponse:
    import logging
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    
    try:
        logger.info(f"Forecast request: ticker={ticker}, days={days}, interval={interval}, use_lstm={use_lstm}")
        
        start = _parse_iso_date(start_date)
        end = _parse_iso_date(end_date)
        default_days = max(days * 3, 180)
        start, end = _resolve_date_range(start, end, default_days)
        
        logger.info(f"Date range resolved: start={start}, end={end}")
    except ValueError as exc:
        logger.error(f"Date parsing error: {exc}")
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    try:
        logger.info(f"Loading data for {ticker}")
        data = load_data(ticker, start, end, interval)
        if data is None or data.empty:
            logger.warning(f"No data available for {ticker}")
            raise HTTPException(status_code=404, detail="No price data available for the requested configuration.")
        logger.info(f"Data loaded: {len(data)} rows")
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error loading data: {e}")
        raise HTTPException(status_code=500, detail=f"Error loading data: {str(e)}") from e

    ticker_clean = ticker.strip().upper()
    model_catalog = list_available_models()

    forecast_df: Optional[pd.DataFrame] = None
    source = "linear"
    note: Optional[str] = None
    train_error: Optional[str] = None

    if use_lstm:
        try:
            forecast_df = forecast_lstm_autotrain(
                data,
                days=days,
                window=window,
                ticker=ticker_clean,
                persist=True,
            )
            source = "lstm"
        except Exception as train_exc:
            train_error = str(train_exc)
            # refresh catalog in case training succeeded partially and saved artifacts
            model_catalog = list_available_models()
            if ticker_clean in model_catalog:
                try:
                    model_path, scaler_path = load_lstm_artifacts(ticker_clean, model_catalog)
                    forecast_df = forecast_lstm_inference(data, model_path, scaler_path, days=days, window=window)
                    source = "lstm"
                    note = f"Used cached LSTM due to training fallback: {train_error}"
                except Exception as exc:  # pragma: no cover - inference issues
                    train_error = f"{train_error}; cached model failed: {exc}"
            else:
                note = f"LSTM training unavailable: {train_error}"

    if forecast_df is None:
        if use_lstm and ticker_clean in model_catalog:
            try:
                model_path, scaler_path = load_lstm_artifacts(ticker_clean, model_catalog)
                forecast_df = forecast_lstm_inference(data, model_path, scaler_path, days=days, window=window)
                source = "lstm"
            except Exception as exc:  # pragma: no cover
                train_error = f"{train_error or ''}; cached model failed: {exc}".strip("; ")
        if forecast_df is None:
            forecast_df = forecast_linear(data, days=days)
            source = "linear"
            if train_error:
                note = f"Fell back to linear forecast because LSTM failed: {train_error}"

    history = _serialize_history(data, limit=max(days, 120))
    forecast_points = _serialize_forecast(forecast_df)

    return ForecastResponse(
        ticker=ticker_clean,
        source=source,
        forecast=forecast_points,
        history=history,
        note=note,
    )


@app.get("/sentiment", response_model=SentimentResponse)
def get_sentiment(
    ticker: str = Query(..., description="Ticker symbol, e.g. AAPL"),
    limit: int = Query(NEWS_RESULT_LIMIT, ge=1, le=50, description="Maximum number of headlines to return"),
) -> SentimentResponse:
    news_df = fetch_news_with_sentiment(ticker, limit=limit)
    ticker_clean = ticker.strip().upper()

    if news_df.empty:
        summary = SentimentSummary(total=0, average_score=None, dominant_sentiment=None)
        return SentimentResponse(ticker=ticker_clean, summary=summary, records=[])

    counts = news_df.groupby("Sentiment").size().reindex(["Positive", "Neutral", "Negative"], fill_value=0)
    total_articles = int(counts.sum())
    avg_score = float(news_df["Score"].mean()) if not news_df.empty else None
    dominant = counts.idxmax() if total_articles else None

    summary = SentimentSummary(
        total=total_articles,
        average_score=avg_score,
        positive=int(counts.get("Positive", 0)),
        neutral=int(counts.get("Neutral", 0)),
        negative=int(counts.get("Negative", 0)),
        dominant_sentiment=dominant,
    )

    records: list[SentimentRecord] = []
    for row in news_df.itertuples():
        published = getattr(row, "Published", None)
        if isinstance(published, pd.Timestamp):
            published = published.tz_localize(None).to_pydatetime()
        elif isinstance(published, datetime):
            published = published
        else:
            published = None

        records.append(
            SentimentRecord(
                headline=getattr(row, "Headline", ""),
                sentiment=getattr(row, "Sentiment", "Neutral"),
                score=float(getattr(row, "Score", 0.0)),
                publisher=getattr(row, "Publisher", None),
                summary=getattr(row, "Summary", None),
                link=getattr(row, "Link", None),
                published=published,
            )
        )

    return SentimentResponse(ticker=ticker_clean, summary=summary, records=records)


@app.get("/models", response_model=list[ModelInfo])
def list_models() -> list[ModelInfo]:
    catalog = list_available_models()
    payload: list[ModelInfo] = []
    for ticker, paths in catalog.items():
        payload.append(
            ModelInfo(
                ticker=ticker,
                model_path=str(Path(paths["model"]).as_posix()),
                scaler_path=str(Path(paths["scaler"]).as_posix()),
            )
        )
    return payload


__all__ = [
    "app",
    "forecast_linear",
    "forecast_lstm_inference",
    "forecast_lstm_autotrain",
    "load_data",
    "fetch_company_metadata",
]


if __name__ == "__main__":  # pragma: no cover - manual launch helper
    import uvicorn

    uvicorn.run(
        "app:app",
        host=os.getenv("HOST", "0.0.0.0"),
        port=int(os.getenv("PORT", "8000")),
        reload=True,
    )