"""Train a small LSTM model on historical Close prices and save model + scaler.

This script is designed to be used programmatically by the Streamlit app.
It keeps defaults small so the demo trains quickly. For production, adjust
hyperparameters and training dataset size.
"""
from __future__ import annotations
import os
from typing import Tuple
import pandas as pd
import numpy as np
import joblib
import yfinance as yf

# Import tensorflow lazily inside functions to avoid heavy imports at module load


def _build_model(input_shape: Tuple[int, int]):
    from tensorflow.keras.models import Sequential
    from tensorflow.keras.layers import LSTM, Dense

    model = Sequential()
    model.add(LSTM(32, input_shape=input_shape, return_sequences=False))
    model.add(Dense(1))
    model.compile(optimizer="adam", loss="mse")
    return model


def train(
    ticker: str,
    start: str | None = None,
    end: str | None = None,
    model_dir: str = "models",
    window: int = 20,
    epochs: int = 5,
    batch_size: int = 32,
) -> Tuple[str, str]:
    """Train a demo LSTM on the Close price for `ticker` between start and end.

    Returns (model_path, scaler_path).
    """
    # Prepare output directory
    os.makedirs(model_dir, exist_ok=True)

    # Download data via yfinance
    t = yf.Ticker(ticker)
    if start and end:
        df = t.history(start=start, end=end)
    else:
        df = t.history(period="5y")

    if df is None or df.empty:
        raise ValueError("No historical data available for training")

    df = df.reset_index()
    closes = df["Close"].values.reshape(-1, 1).astype(float)

    # Scale
    from sklearn.preprocessing import MinMaxScaler

    scaler = MinMaxScaler(feature_range=(0, 1))
    closes_scaled = scaler.fit_transform(closes)

    # Create sequences
    X, y = [], []
    for i in range(window, len(closes_scaled)):
        X.append(closes_scaled[i - window : i, 0])
        y.append(closes_scaled[i, 0])

    X = np.array(X)
    y = np.array(y)

    # Reshape for LSTM: (samples, timesteps, features)
    X = X.reshape((X.shape[0], X.shape[1], 1))

    # Build model
    model = _build_model(input_shape=(window, 1))

    # Train
    # Import callbacks locally
    from tensorflow.keras.callbacks import EarlyStopping

    es = EarlyStopping(monitor="loss", patience=3, restore_best_weights=True)

    model.fit(X, y, epochs=epochs, batch_size=batch_size, callbacks=[es], verbose=1)

    # Save model and scaler
    model_path = os.path.join(model_dir, f"lstm_{ticker.upper()}.keras")
    scaler_path = os.path.join(model_dir, f"scaler_{ticker.upper()}.save")

    model.save(model_path)
    joblib.dump(scaler, scaler_path)

    return model_path, scaler_path


if __name__ == "__main__":
    # Quick CLI demo
    import argparse

    p = argparse.ArgumentParser()
    p.add_argument("ticker", help="Ticker symbol to train on")
    p.add_argument("--start", default=None)
    p.add_argument("--end", default=None)
    p.add_argument("--epochs", type=int, default=5)
    args = p.parse_args()

    m, s = train(args.ticker, start=args.start, end=args.end, epochs=args.epochs)
    print("Saved model:", m)
    print("Saved scaler:", s)
