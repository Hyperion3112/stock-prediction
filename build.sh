#!/bin/bash
# Build script to pre-train LSTM models during deployment

echo "Installing dependencies..."
pip install --no-cache-dir -r requirements.txt

echo "Pre-training LSTM models for common tickers..."
python -c "
import sys
sys.path.insert(0, '.')
from app import forecast_lstm_autotrain, load_data
from datetime import datetime, timedelta

tickers = ['AAPL', 'NVDA', 'TSLA']
end_date = datetime.now()
start_date = end_date - timedelta(days=365)

for ticker in tickers:
    print(f'Training model for {ticker}...')
    try:
        data = load_data(ticker, start_date, end_date, '1d')
        if data is not None and not data.empty:
            forecast_lstm_autotrain(data, days=30, window=20, ticker=ticker, persist=True)
            print(f'✓ Model trained for {ticker}')
        else:
            print(f'✗ No data for {ticker}')
    except Exception as e:
        print(f'✗ Failed to train {ticker}: {e}')

print('Build complete!')
"
