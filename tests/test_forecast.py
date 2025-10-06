import sys
import os
from pathlib import Path
# Ensure project root (one level up) is on sys.path so tests can import app
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import pandas as pd
import numpy as np
from datetime import datetime, timedelta

from app import forecast_linear


def make_dummy_data(n=100):
    np.random.seed(0)
    today = datetime.utcnow().date()
    dates = [pd.to_datetime(today - timedelta(days=(n - i))) for i in range(n)]
    # Create a linear increasing close price with small noise
    closes = np.linspace(100, 200, n) + np.random.normal(scale=0.1, size=n)
    df = pd.DataFrame({"Date": dates, "Close": closes})
    return df


def test_forecast_length():
    df = make_dummy_data(50)
    out = forecast_linear(df, days=10)
    assert len(out) == 10
    assert "Date" in out.columns and "Forecast" in out.columns


def test_forecast_monotonic():
    # For a roughly increasing series, linear forecast should continue increasing
    df = make_dummy_data(60)
    out = forecast_linear(df, days=5)
    assert out["Forecast"].iloc[-1] >= out["Forecast"].iloc[0]
