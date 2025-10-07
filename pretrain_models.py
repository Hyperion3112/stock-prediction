#!/usr/bin/env python3
"""Pre-train LSTM models for popular tickers to speed up initial requests."""

import sys
from pathlib import Path
from datetime import datetime, timedelta
from app import load_data, forecast_lstm_autotrain

# Popular tickers to pre-train
POPULAR_TICKERS = ["AAPL", "MSFT", "GOOGL", "AMZN", "TSLA", "META", "NVDA", "JPM", "V", "WMT"]

def pretrain_ticker(ticker: str) -> bool:
    """Pre-train LSTM model for a ticker."""
    print(f"\n{'='*60}")
    print(f"Pre-training LSTM model for {ticker}...")
    print(f"{'='*60}")
    
    try:
        # Load 6 months of data
        end = datetime.now()
        start = end - timedelta(days=180)
        
        data = load_data(ticker, start, end, "1d")
        if data is None or data.empty:
            print(f"❌ No data available for {ticker}")
            return False
        
        print(f"✓ Loaded {len(data)} data points")
        
        # Train and save model
        forecast_df = forecast_lstm_autotrain(
            data,
            days=30,
            window=20,
            ticker=ticker,
            persist=True,
            epochs=8
        )
        
        print(f"✅ Successfully trained and cached LSTM model for {ticker}")
        print(f"   Generated {len(forecast_df)} forecast points")
        return True
        
    except Exception as exc:
        print(f"❌ Failed to train {ticker}: {exc}")
        return False

def main():
    """Pre-train models for all popular tickers."""
    tickers = POPULAR_TICKERS if len(sys.argv) == 1 else sys.argv[1:]
    
    print(f"\n🚀 Starting pre-training for {len(tickers)} tickers...")
    print(f"This will take approximately {len(tickers) * 45} seconds (45s per ticker)\n")
    
    results = {}
    for ticker in tickers:
        results[ticker] = pretrain_ticker(ticker)
    
    # Summary
    print(f"\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")
    successful = sum(1 for success in results.values() if success)
    failed = len(results) - successful
    
    print(f"✅ Successfully trained: {successful}/{len(results)}")
    print(f"❌ Failed: {failed}/{len(results)}")
    
    if failed > 0:
        print("\nFailed tickers:")
        for ticker, success in results.items():
            if not success:
                print(f"  - {ticker}")
    
    # Show model directory
    model_dir = Path("models")
    if model_dir.exists():
        model_files = list(model_dir.glob("lstm_*.keras"))
        print(f"\n📁 Model cache location: {model_dir.absolute()}")
        print(f"   Total cached models: {len(model_files)}")

if __name__ == "__main__":
    main()
